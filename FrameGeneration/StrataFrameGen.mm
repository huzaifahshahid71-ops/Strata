#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <objc/runtime.h>
#import <atomic>
#import <TargetConditionals.h>
#import "../Vendor/MetalFG/Headers/MetalFGWarper.h"

// Explicit guest-only entry point. This library has no injection constructor.
static thread_local bool internalDrawable = false;
static IMP originalNext;
static NSMutableDictionary<NSString *, NSValue *> *presentIMPs;
static NSLock *hookLock;
static NSInteger sourceRequest;
static NSHashTable *gameDisplayLinks;
static thread_local bool forwardingPresent = false;
struct PresentForward { bool previous; PresentForward(): previous(forwardingPresent) { forwardingPresent = true; } ~PresentForward() { forwardingPresent = previous; } };
static NSString *hookKey(Class cls, SEL sel) { return [NSString stringWithFormat:@"%p:%s", cls, sel_getName(sel)]; }
static IMP originalFor(id obj, SEL sel) {
    [hookLock lock]; IMP found = NULL;
    for (Class cls = object_getClass(obj); cls && !found; cls = class_getSuperclass(cls)) found = (IMP)[presentIMPs[hookKey(cls, sel)] pointerValue];
    [hookLock unlock]; return found;
}
@class StrataFGEngine;
static StrataFGEngine *engine;
static void installPresentHooks(Class cls);

@interface StrataFGEngine : NSObject {
    dispatch_queue_t _queue;
    dispatch_semaphore_t _gate;
    MetalFGWarper *_warper;
    __weak CAMetalLayer *_layer;
    BOOL _benchmark;
    std::atomic<bool> _metalReady;
    std::atomic<bool> _disabled;
    double _interval, _lastNative, _started;
    std::atomic<uint64_t> _native, _generated, _presented, _fallback;
    UILabel *_hud;
    NSURL *_report;
    NSInteger _displayMax;
    NSMapTable<CAMetalLayer *, NSDictionary *> *_surfaceFailures;
}
@property (atomic, copy) NSString *status;
@property (atomic, copy) NSDictionary *surfaceError;
- (instancetype)initWithConfig:(NSDictionary *)config report:(NSURL *)report;
- (void)prepare:(CAMetalLayer *)layer;
- (BOOL)intercept:(id<CAMetalDrawable>)drawable command:(id<MTLCommandBuffer>)buffer;
- (void)observePresented:(id<CAMetalDrawable>)drawable;
- (void)report;
- (BOOL)hasMetal;
@end

@implementation StrataFGEngine
- (instancetype)initWithConfig:(NSDictionary *)config report:(NSURL *)report {
    if ((self = [super init])) {
        _benchmark = [config[@"mode"] isEqual:@"benchmark"];
        _queue = dispatch_queue_create("Strata.FrameGeneration", DISPATCH_QUEUE_SERIAL);
        _gate = dispatch_semaphore_create(1); _interval = 1.0 / 60; _started = CACurrentMediaTime();
        _surfaceFailures = [NSMapTable weakToStrongObjectsMapTable];
        _report = report; self.status = @"Waiting for a compatible Metal surface";
        _displayMax = MAX(1, UIScreen.mainScreen.maximumFramesPerSecond);
        __weak StrataFGEngine *weak = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer) { [weak report]; }];
        });
    }
    return self;
}
- (void)prepare:(CAMetalLayer *)layer {
    if (_disabled || !layer.device || layer.drawableSize.width < 250 || layer.drawableSize.height < 150) return;
    if (dispatch_semaphore_wait(_gate, DISPATCH_TIME_NOW)) return;
    NSString *signature = [NSString stringWithFormat:@"%lu:%.0fx%.0f:%p", (unsigned long)layer.pixelFormat, layer.drawableSize.width, layer.drawableSize.height, layer.device];
    NSDictionary *previous = [_surfaceFailures objectForKey:layer];
    if (![previous[@"surfaceSignature"] isEqual:signature]) previous = nil;
    NSInteger attempts = [previous[@"attempts"] integerValue];
    if (attempts >= 3 || [previous[@"retryAfter"] doubleValue] > CACurrentMediaTime()) { dispatch_semaphore_signal(_gate); return; }
    NSString *stage = @"initializing optical-flow shaders";
    @try {
        if (!_warper || _layer != layer || _warper.pixelFormat != layer.pixelFormat) {
            MetalFGWarper *candidate = [[MetalFGWarper alloc] initWithDevice:layer.device pixelFormat:layer.pixelFormat];
            if (!candidate.isReady) @throw [NSException exceptionWithName:@"StrataShaderInitialization" reason:@"Metal did not create a ready optical-flow pipeline" userInfo:nil];
            stage = @"configuring optical-flow parameters";
            candidate.motionScale = 0.5; candidate.disocclusionThreshold = 0.18; candidate.uiSensitivity = 0.035; candidate.motionDeadzone = 0.0003; candidate.benchmarkOnly = _benchmark;
            _warper = candidate; _layer = layer; _metalReady = true;
            [_surfaceFailures removeObjectForKey:layer];
            if (sourceRequest > 0) dispatch_async(dispatch_get_main_queue(), ^{
                NSArray *links; @synchronized(gameDisplayLinks) { links = gameDisplayLinks.allObjects; }
                for (CADisplayLink *link in links) link.preferredFramesPerSecond = sourceRequest;
            });
            self.status = _benchmark ? @"Uncapped offscreen 2× benchmark" : @"2× interpolation active";
        }
    } @catch (NSException *exception) {
        NSString *reason = exception.reason ?: @"No reason supplied";
        if (reason.length > 768) reason = [reason substringToIndex:768];
        NSDictionary *failure = @{@"exception":exception.name ?: @"Unknown", @"reason":reason, @"stage":stage,
            @"layerClass":NSStringFromClass(layer.class), @"pixelFormat":@(layer.pixelFormat),
            @"width":@(layer.drawableSize.width), @"height":@(layer.drawableSize.height),
            @"surfaceSignature":signature, @"attempts":@(attempts + 1), @"retryAfter":@(CACurrentMediaTime() + 5),
            @"sampledAt":@(NSDate.date.timeIntervalSince1970)};
        [_surfaceFailures setObject:failure forKey:layer]; self.surfaceError = failure;
        self.status = [NSString stringWithFormat:@"Metal setup failed (%ld/3): %@ — %@. Native rendering retained; other surfaces can still initialize.", (long)(attempts + 1), exception.name, reason];
        NSLog(@"[StrataFG] Surface error: %@", failure);
    }
    dispatch_semaphore_signal(_gate);
}
- (BOOL)hasMetal { return _metalReady.load() && !_disabled.load(); }
- (void)observePresented:(id<CAMetalDrawable>)drawable {
#if !TARGET_OS_SIMULATOR
    if ([drawable respondsToSelector:@selector(addPresentedHandler:)]) {
        [drawable addPresentedHandler:^(id<MTLDrawable> shown) { if (shown.presentedTime > 0) self->_presented.fetch_add(1); }];
    }
#endif
}
- (BOOL)intercept:(id<CAMetalDrawable>)drawable command:(id<MTLCommandBuffer>)buffer {
    if (_disabled || !_warper.isReady || drawable.layer != _layer || drawable.texture.framebufferOnly || [buffer.label hasPrefix:@"com.metalfg."]) return NO;
    [self observePresented:drawable];
    if (dispatch_semaphore_wait(_gate, DISPATCH_TIME_NOW)) {
        [buffer addCompletedHandler:^(id<MTLCommandBuffer> cb) { if (cb.status == MTLCommandBufferStatusCompleted) self->_native.fetch_add(1); }];
        _fallback.fetch_add(1); return NO;
    }
    [buffer addCompletedHandler:^(id<MTLCommandBuffer> cb) {
        if (cb.status != MTLCommandBufferStatusCompleted) { dispatch_semaphore_signal(self->_gate); return; }
        self->_native.fetch_add(1);
        dispatch_async(self->_queue, ^{
            @autoreleasepool {
                double now = CACurrentMediaTime(), dt = now - self->_lastNative;
                if (dt > 0.003 && dt < 0.25) self->_interval = self->_lastNative > 0 ? dt : self->_interval;
                self->_lastNative = now;
                if (!self->_benchmark && self->_interval * self->_displayMax < 1.85) {
                    self.status = @"Native cadence already near display limit; interpolation bypassed";
                    [drawable present]; self->_fallback.fetch_add(1); dispatch_semaphore_signal(self->_gate); return;
                }
                self.status = self->_benchmark ? @"Uncapped offscreen 2× benchmark" : @"2× interpolation active";
                self->_warper.presentationDuration = self->_benchmark ? 0 : MAX(1.0 / self->_displayMax, self->_interval / 2);
                __weak StrataFGEngine *weak = self;
                self->_warper.frameCompleted = ^(BOOL made, BOOL success) {
                    StrataFGEngine *owner = weak; if (!owner) return;
                    // Keep the source drawable alive until the GPU has finished reading it.
                    (void)drawable.texture;
                    if (made && success) owner->_generated.fetch_add(1);
                    dispatch_async(owner->_queue, ^{
                        if (!success) { owner->_disabled = YES; owner.status = @"Generation GPU error; native rendering retained"; }
                        if (owner->_benchmark || !made || !success) { dispatch_semaphore_signal(owner->_gate); return; }
                        double delay = MAX(1.0 / owner->_displayMax, owner->_interval / 2);
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), owner->_queue, ^{
                            internalDrawable = true;
                            id<CAMetalDrawable> real = [owner->_layer nextDrawable];
                            internalDrawable = false;
                            if (real) { [owner observePresented:real]; [owner->_warper presentCachedNativeFrameToDrawable:real]; }
                            dispatch_semaphore_signal(owner->_gate);
                        });
                    });
                };
                @try {
                    [self->_warper processAndInterpolateNativeDrawable:drawable];
                    if (!self->_warper.lastFrameSubmitted) {
                        self->_disabled = YES; self.status = @"Generation allocation failed; native rendering retained";
                        if (!self->_benchmark) [drawable present];
                        dispatch_semaphore_signal(self->_gate);
                    }
                } @catch (NSException *exception) {
                    self->_disabled = YES; self.status = @"Generation error; native rendering retained";
                    if (!self->_benchmark) [drawable present];
                    dispatch_semaphore_signal(self->_gate);
                }
            }
        });
    }];
    // In benchmark mode the real native frame presents normally; only GPU generation is offscreen.
    return !_benchmark;
}
- (void)report {
    double elapsed = MAX(0.001, CACurrentMediaTime() - _started);
    double native = _native.exchange(0) / elapsed, generated = _generated.exchange(0) / elapsed, shown = _presented.exchange(0) / elapsed;
    _started = CACurrentMediaTime();
    NSDictionary *data = @{@"schema":@1, @"pid":@(getpid()), @"sampledAt":@(NSDate.date.timeIntervalSince1970), @"nativeGPUFPS":@(native), @"generatedGPUFPS":@(generated), @"computedFPS":@(native + generated), @"presentedFPS":@(shown), @"displayMaximumHz":@(_displayMax), @"benchmark":@(_benchmark), @"status":self.status ?: @"Starting", @"fallbackFrames":@(_fallback.load()), @"surfaceError":self.surfaceError ?: @{}, @"revision":@31};
    NSData *json = [NSJSONSerialization dataWithJSONObject:data options:NSJSONWritingPrettyPrinted error:nil];
    [json writeToURL:_report options:NSDataWritingAtomic error:nil];
    UIWindow *window = nil;
    for (UIWindowScene *scene in UIApplication.sharedApplication.connectedScenes) if ([scene isKindOfClass:UIWindowScene.class]) for (UIWindow *candidate in scene.windows) if (candidate.isKeyWindow) window = candidate;
    if (window && _warper.isReady) {
        if (!_hud) { _hud = [[UILabel alloc] initWithFrame:CGRectMake(12, 54, 310, 48)]; _hud.numberOfLines = 2; _hud.font = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightMedium]; _hud.textColor = UIColor.whiteColor; _hud.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.7]; _hud.layer.cornerRadius = 10; _hud.clipsToBounds = YES; _hud.userInteractionEnabled = NO; }
        if (_hud.superview != window) [window addSubview:_hud];
        _hud.text = [NSString stringWithFormat:@" FG 2× %@ | GPU %.0f + %.0f = %.0f\n Presented %.0f / %ld Hz", _benchmark ? @"BENCH" : @"", native, generated, native + generated, shown, (long)_displayMax];
    }
}
@end

static BOOL route(id object, id drawable) {
    return !forwardingPresent && engine && [drawable conformsToProtocol:@protocol(CAMetalDrawable)] && ![objc_getAssociatedObject(drawable, &kMetalFGIsSyntheticKey) boolValue] && [engine intercept:drawable command:object];
}
static void installPresentHooks(Class cls) {
    if (!cls) return;
    SEL plain = @selector(presentDrawable:), timed = @selector(presentDrawable:atTime:), duration = @selector(presentDrawable:afterMinimumDuration:);
    for (NSString *name in @[@"presentDrawable:", @"presentDrawable:atTime:", @"presentDrawable:afterMinimumDuration:"]) {
        SEL sel = NSSelectorFromString(name); [hookLock lock];
        if (presentIMPs[hookKey(cls, sel)]) { [hookLock unlock]; continue; }
        Method method = class_getInstanceMethod(cls, sel);
        if (!method) { [hookLock unlock]; continue; }
        IMP old = method_getImplementation(method), replacement;
        if (sel == plain) replacement = imp_implementationWithBlock(^(id object, id drawable) { if (!route(object, drawable)) { PresentForward guard; ((void(*)(id,SEL,id))originalFor(object, plain))(object, plain, drawable); } });
        else if (sel == timed) replacement = imp_implementationWithBlock(^(id object, id drawable, CFTimeInterval time) { if (!route(object, drawable)) { PresentForward guard; ((void(*)(id,SEL,id,CFTimeInterval))originalFor(object, timed))(object, timed, drawable, time); } });
        else replacement = imp_implementationWithBlock(^(id object, id drawable, CFTimeInterval time) { if (!route(object, drawable)) { PresentForward guard; ((void(*)(id,SEL,id,CFTimeInterval))originalFor(object, duration))(object, duration, drawable, time); } });
        presentIMPs[hookKey(cls, sel)] = [NSValue valueWithPointer:(const void *)old];
        if (!class_addMethod(cls, sel, replacement, method_getTypeEncoding(method))) method_setImplementation(class_getInstanceMethod(cls, sel), replacement);
        [hookLock unlock];
    }
}

extern "C" __attribute__((visibility("default"))) void StrataFrameGenStart(NSDictionary *config, NSString *directory) {
    if (engine || ![@[@"2x", @"benchmark"] containsObject:config[@"mode"]]) return;
    hookLock = [NSLock new]; presentIMPs = [NSMutableDictionary new];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    engine = [[StrataFGEngine alloc] initWithConfig:config report:[NSURL fileURLWithPath:[directory stringByAppendingPathComponent:@"latest.json"]]];
    sourceRequest = [config[@"sourceFPS"] integerValue];
    if (sourceRequest > 0) {
        gameDisplayLinks = [NSHashTable weakObjectsHashTable];
        sourceRequest = MIN(sourceRequest, UIScreen.mainScreen.maximumFramesPerSecond);
        Method method = class_getInstanceMethod(CADisplayLink.class, @selector(setPreferredFramesPerSecond:));
        IMP old = method_getImplementation(method);
        method_setImplementation(method, imp_implementationWithBlock(^(id obj, NSInteger value) {
            @synchronized(gameDisplayLinks) { [gameDisplayLinks addObject:obj]; }
            ((void(*)(id,SEL,NSInteger))old)(obj,@selector(setPreferredFramesPerSecond:),[engine hasMetal] ? sourceRequest : value);
        }));
        Method rangeMethod = class_getInstanceMethod(CADisplayLink.class, @selector(setPreferredFrameRateRange:));
        IMP rangeOld = method_getImplementation(rangeMethod);
        method_setImplementation(rangeMethod, imp_implementationWithBlock(^(id obj, CAFrameRateRange range) {
            @synchronized(gameDisplayLinks) { [gameDisplayLinks addObject:obj]; }
            if ([engine hasMetal]) range = CAFrameRateRangeMake(sourceRequest, sourceRequest, sourceRequest);
            ((void(*)(id,SEL,CAFrameRateRange))rangeOld)(obj,@selector(setPreferredFrameRateRange:),range);
        }));
    }
    Method next = class_getInstanceMethod(CAMetalLayer.class, @selector(nextDrawable)); originalNext = method_getImplementation(next);
    method_setImplementation(next, imp_implementationWithBlock(^id(CAMetalLayer *layer) {
        if (!internalDrawable && layer.device && layer.drawableSize.width >= 250 && layer.drawableSize.height >= 150) {
            layer.framebufferOnly = NO; layer.maximumDrawableCount = 3; layer.allowsNextDrawableTimeout = YES;
            [engine prepare:layer];
            static id<MTLDevice> hookedDevice;
            if (hookedDevice != layer.device) { hookedDevice = layer.device; installPresentHooks(object_getClass([[layer.device newCommandQueue] commandBuffer])); }
        }
        id drawable = ((id(*)(id,SEL))originalNext)(layer,@selector(nextDrawable));
        if (!internalDrawable && drawable) objc_setAssociatedObject(drawable, &kMetalFGIsSyntheticKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return drawable;
    }));
    [engine report];
}
