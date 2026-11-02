#import "StrataGuestControls.h"
#import "LCSharedUtils.h"
#import "utils.h"
#import <UIKit/UIKit.h>
#import <unistd.h>

static NSString *const kStrataFloatingHomeButtonKey = @"StrataFloatingHomeButton";
static NSString *const kStrataFloatingHomeButtonSideKey = @"StrataFloatingHomeButtonLeft";
static NSString *const kStrataFloatingHomeButtonYKey = @"StrataFloatingHomeButtonY";
static const CGFloat kFloatingButtonSize = 48.0;
static const CGFloat kFloatingEdgeInset = 10.0;
static const CGFloat kFloatingIdleAlpha = 0.45;

@interface StrataControlsWindow : UIWindow
@end
@implementation StrataControlsWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return (hit == self || hit == self.rootViewController.view) ? nil : hit;
}
@end

@interface StrataFloatingWindow : UIWindow
@property(nonatomic, weak) UIView *passthroughTarget;
@end
@implementation StrataFloatingWindow
- (BOOL)canBecomeKeyWindow { return NO; }
- (void)makeKeyWindow {}
- (BOOL)_canAffectStatusBarAppearance { return NO; }
- (BOOL)_shouldControlAutorotation { return NO; }
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *target = self.passthroughTarget;
    if (!target || target.hidden || target.alpha < 0.01) return nil;
    CGPoint localPoint = [self convertPoint:point toView:target];
    if (![target pointInside:localPoint withEvent:event]) return nil;
    return [super hitTest:point withEvent:event];
}
@end

@interface StrataControlsController : UIViewController
@property(nonatomic) UIInterfaceOrientationMask orientationMask;
@end
@implementation StrataControlsController
- (BOOL)prefersStatusBarHidden { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return self.orientationMask ?: UIInterfaceOrientationMaskAllButUpsideDown; }
@end

@interface StrataFloatingController : UIViewController
@property(nonatomic, copy) void (^onLayout)(void);
@property(nonatomic) CGSize lastLayoutSize;
@end
@implementation StrataFloatingController
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGSize size = self.view.bounds.size;
    if (!CGSizeEqualToSize(size, self.lastLayoutSize)) {
        self.lastLayoutSize = size;
        if (self.onLayout) self.onLayout();
    }
}
@end

@interface StrataGuestControls : NSObject<UIGestureRecognizerDelegate>
@property(nonatomic) NSString *group;
@property(nonatomic) NSString *appName;
@property(nonatomic) NSString *currentKey;
@property(nonatomic) BOOL separateProcess;
@property(nonatomic) BOOL hostMode;
@property(nonatomic) BOOL floatingEnabled;
@property(nonatomic) BOOL floatingSnapLeft;
@property(nonatomic) CGFloat floatingRatioY;
@property(nonatomic) BOOL floatingPositionLoaded;
@property(nonatomic) UIWindow *panel;
@property(nonatomic) StrataFloatingWindow *floatingWindow;
@property(nonatomic) UIView *floatingButton;
@property(nonatomic) NSTimer *floatingIdleTimer;
@property(nonatomic, weak) UIWindow *previousKeyWindow;
@property(nonatomic) NSHashTable<UIWindow *> *installedWindows;
@end
@implementation StrataGuestControls
- (NSUserDefaults *)sharedDefaults {
    return NSUserDefaults.lcSharedDefaults ?: (self.group.length ? [[NSUserDefaults alloc] initWithSuiteName:self.group] : nil);
}
- (void)loadFloatingPositionIfNeeded {
    if (self.floatingPositionLoaded) return;
    self.floatingPositionLoaded = YES;
    NSUserDefaults *defaults = [self sharedDefaults];
    self.floatingSnapLeft = [defaults objectForKey:kStrataFloatingHomeButtonSideKey] ? [defaults boolForKey:kStrataFloatingHomeButtonSideKey] : NO;
    CGFloat ratioY = [defaults objectForKey:kStrataFloatingHomeButtonYKey] ? [defaults doubleForKey:kStrataFloatingHomeButtonYKey] : 0.35;
    self.floatingRatioY = MIN(MAX(ratioY, 0.05), 0.95);
}
- (void)installInWindow:(UIWindow *)window {
    if (!window || window == self.floatingWindow || [self.installedWindows containsObject:window]) return;
    [self.installedWindows addObject:window];
    UITapGestureRecognizer *gesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggle:)];
    gesture.numberOfTouchesRequired = 3;
    gesture.cancelsTouchesInView = window == self.panel;
    gesture.delaysTouchesEnded = window == self.panel;
    gesture.delaysTouchesBegan = NO;
    gesture.delegate = self;
    [window addGestureRecognizer:gesture];
    if (self.floatingEnabled && !self.hostMode && window != self.panel) {
        [self refreshFloatingHomeButtonForWindow:window];
    }
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other { return YES; }
- (void)hide {
    self.panel.hidden = YES;
    self.panel = nil;
    if (!self.previousKeyWindow.hidden) [self.previousKeyWindow makeKeyWindow];
    self.previousKeyWindow = nil;
}
- (void)hideFloatingHomeButton {
    [self.floatingIdleTimer invalidate];
    self.floatingIdleTimer = nil;
    self.floatingWindow.passthroughTarget = nil;
    self.floatingWindow.hidden = YES;
    self.floatingWindow = nil;
    self.floatingButton = nil;
}
- (void)scheduleFloatingIdleFade {
    [self.floatingIdleTimer invalidate];
    __weak typeof(self) weakSelf = self;
    self.floatingIdleTimer = [NSTimer scheduledTimerWithTimeInterval:2.5 repeats:NO block:^(NSTimer *timer) {
        [UIView animateWithDuration:0.25 animations:^{
            weakSelf.floatingButton.alpha = kFloatingIdleAlpha;
        }];
    }];
}
- (CGPoint)snappedFloatingCenterForPoint:(CGPoint)point inView:(UIView *)hostView {
    CGRect bounds = hostView.bounds;
    UIEdgeInsets insets = hostView.safeAreaInsets;
    CGFloat half = kFloatingButtonSize * 0.5;
    CGFloat minX = insets.left + kFloatingEdgeInset + half;
    CGFloat maxX = MAX(minX, CGRectGetWidth(bounds) - insets.right - kFloatingEdgeInset - half);
    CGFloat minY = insets.top + kFloatingEdgeInset + half;
    CGFloat maxY = MAX(minY, CGRectGetHeight(bounds) - insets.bottom - kFloatingEdgeInset - half);
    BOOL snapLeft = point.x < CGRectGetMidX(bounds);
    CGFloat targetX = snapLeft ? minX : maxX;
    CGFloat targetY = MIN(MAX(point.y, minY), maxY);
    return CGPointMake(targetX, targetY);
}
- (void)layoutFloatingButtonAnimated:(BOOL)animated {
    UIView *hostView = self.floatingWindow.rootViewController.view;
    if (!hostView || !self.floatingButton || CGRectIsEmpty(hostView.bounds)) return;
    [self loadFloatingPositionIfNeeded];
    CGPoint desired = CGPointMake(self.floatingSnapLeft ? 0.0 : CGRectGetWidth(hostView.bounds), CGRectGetHeight(hostView.bounds) * self.floatingRatioY);
    CGPoint center = [self snappedFloatingCenterForPoint:desired inView:hostView];
    if (animated) {
        [UIView animateWithDuration:0.22 delay:0 usingSpringWithDamping:0.82 initialSpringVelocity:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
            self.floatingButton.center = center;
        } completion:nil];
    } else {
        self.floatingButton.center = center;
    }
}
- (void)handleFloatingPan:(UIPanGestureRecognizer *)pan {
    UIView *hostView = self.floatingWindow.rootViewController.view;
    if (!hostView || !self.floatingButton) return;
    if (pan.state == UIGestureRecognizerStateBegan) {
        [self.floatingIdleTimer invalidate];
        [UIView animateWithDuration:0.15 animations:^{ self.floatingButton.alpha = 1.0; }];
    } else if (pan.state == UIGestureRecognizerStateChanged) {
        CGPoint delta = [pan translationInView:hostView];
        [pan setTranslation:CGPointZero inView:hostView];
        CGFloat half = kFloatingButtonSize * 0.5;
        CGFloat x = MIN(MAX(self.floatingButton.center.x + delta.x, half), CGRectGetWidth(hostView.bounds) - half);
        CGFloat y = MIN(MAX(self.floatingButton.center.y + delta.y, half), CGRectGetHeight(hostView.bounds) - half);
        self.floatingButton.center = CGPointMake(x, y);
    } else if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        CGPoint velocity = [pan velocityInView:hostView];
        CGPoint projected = CGPointMake(self.floatingButton.center.x + velocity.x * 0.08, self.floatingButton.center.y + velocity.y * 0.08);
        CGPoint snapped = [self snappedFloatingCenterForPoint:projected inView:hostView];
        BOOL snapLeft = snapped.x < CGRectGetMidX(hostView.bounds);
        CGFloat height = MAX(CGRectGetHeight(hostView.bounds), 1.0);
        self.floatingSnapLeft = snapLeft;
        self.floatingRatioY = MIN(MAX(snapped.y / height, 0.05), 0.95);
        NSUserDefaults *defaults = [self sharedDefaults];
        [defaults setBool:self.floatingSnapLeft forKey:kStrataFloatingHomeButtonSideKey];
        [defaults setDouble:self.floatingRatioY forKey:kStrataFloatingHomeButtonYKey];
        [UIView animateWithDuration:0.26 delay:0 usingSpringWithDamping:0.78 initialSpringVelocity:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
            self.floatingButton.center = snapped;
        } completion:nil];
        [self scheduleFloatingIdleFade];
    }
}
- (void)handleFloatingHomeTap {
    [self.floatingIdleTimer invalidate];
    [UIView animateWithDuration:0.12 animations:^{
        self.floatingButton.alpha = 1.0;
        self.floatingButton.transform = CGAffineTransformMakeScale(0.9, 0.9);
    } completion:^(BOOL finished) {
        self.floatingButton.transform = CGAffineTransformIdentity;
        [self hideFloatingHomeButton];
        [self request:@"close"];
    }];
}
- (void)refreshFloatingHomeButtonForWindow:(UIWindow *)source {
    if (self.hostMode || !self.floatingEnabled) return;
    if (self.floatingWindow) {
        if (!self.floatingWindow.windowScene && source.windowScene) {
            self.floatingWindow.windowScene = source.windowScene;
            self.floatingWindow.frame = source.windowScene.coordinateSpace.bounds;
            [self layoutFloatingButtonAnimated:NO];
        }
        self.floatingWindow.hidden = NO;
        return;
    }
    UIApplication *app = UIApplication.sharedApplication;
    if (!app || app.applicationState == UIApplicationStateBackground) return;
    UIWindow *anchor = (source && ![source isKindOfClass:StrataControlsWindow.class] && ![source isKindOfClass:StrataFloatingWindow.class]) ? source : nil;
    if (!anchor) {
        for (UIWindowScene *scene in app.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow *candidate in scene.windows) {
                if (![candidate isKindOfClass:StrataControlsWindow.class] && ![candidate isKindOfClass:StrataFloatingWindow.class] && !candidate.hidden) { anchor = candidate; break; }
            }
            if (anchor) break;
        }
    }
    if (!anchor) {
        for (UIWindow *candidate in app.windows) {
            if (![candidate isKindOfClass:StrataControlsWindow.class] && ![candidate isKindOfClass:StrataFloatingWindow.class] && !candidate.hidden) { anchor = candidate; break; }
        }
    }
    if (!anchor) return;

    UIWindowScene *scene = anchor.windowScene;
    CGRect frame = scene ? scene.coordinateSpace.bounds : (CGRectIsEmpty(anchor.bounds) ? UIScreen.mainScreen.bounds : anchor.bounds);
    StrataFloatingWindow *window = scene ? [[StrataFloatingWindow alloc] initWithWindowScene:scene] : [[StrataFloatingWindow alloc] initWithFrame:frame];
    window.frame = frame;
    window.accessibilityIdentifier = @"strata.floatingHome.window";
    window.windowLevel = UIWindowLevelStatusBar - 1;
    window.backgroundColor = UIColor.clearColor;

    StrataFloatingController *controller = [StrataFloatingController new];
    __weak typeof(self) weakSelf = self;
    controller.onLayout = ^{ [weakSelf layoutFloatingButtonAnimated:NO]; };
    window.rootViewController = controller;
    controller.view.backgroundColor = UIColor.clearColor;

    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kFloatingButtonSize, kFloatingButtonSize)];
    container.layer.shadowColor = UIColor.blackColor.CGColor;
    container.layer.shadowOpacity = 0.32;
    container.layer.shadowRadius = 8.0;
    container.layer.shadowOffset = CGSizeMake(0, 3);

    UIVisualEffect *effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterialDark];
    if (@available(iOS 26.0, *)) effect = [UIGlassEffect effectWithStyle:UIGlassEffectStyleRegular];
    UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:effect];
    blur.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    blur.frame = container.bounds;
    blur.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    blur.layer.cornerRadius = kFloatingButtonSize * 0.5;
    blur.layer.borderWidth = 1.0;
    blur.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.28].CGColor;
    blur.clipsToBounds = YES;
    blur.userInteractionEnabled = NO;
    [container addSubview:blur];

    UIView *innerRing = [[UIView alloc] initWithFrame:CGRectInset(container.bounds, 9, 9)];
    innerRing.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    innerRing.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.16];
    innerRing.layer.cornerRadius = CGRectGetWidth(innerRing.bounds) * 0.5;
    innerRing.layer.borderWidth = 1.5;
    innerRing.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.85].CGColor;
    innerRing.userInteractionEnabled = NO;
    [blur.contentView addSubview:innerRing];

    UIImageSymbolConfiguration *symConfig = [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightSemibold];
    UIImageView *glyph = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"house.fill" withConfiguration:symConfig]];
    glyph.tintColor = UIColor.whiteColor;
    glyph.center = CGPointMake(CGRectGetMidX(innerRing.bounds), CGRectGetMidY(innerRing.bounds));
    glyph.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    [innerRing addSubview:glyph];

    UIButton *tapButton = [UIButton buttonWithType:UIButtonTypeCustom];
    tapButton.frame = container.bounds;
    tapButton.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    tapButton.accessibilityIdentifier = @"strata.floatingHome.button";
    tapButton.accessibilityLabel = @"Return to Strata Home";
    [tapButton addTarget:self action:@selector(handleFloatingHomeTap) forControlEvents:UIControlEventTouchUpInside];
    [container addSubview:tapButton];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleFloatingPan:)];
    [container addGestureRecognizer:pan];

    [controller.view addSubview:container];
    window.passthroughTarget = container;
    self.floatingWindow = window;
    self.floatingButton = container;
    [self layoutFloatingButtonAnimated:NO];
    window.hidden = NO;
    [self scheduleFloatingIdleFade];
}
- (void)restorePortraitOrientation {
    if (@available(iOS 16.0, *)) {
        UIWindowSceneGeometryPreferencesIOS *prefs = [[UIWindowSceneGeometryPreferencesIOS alloc] initWithInterfaceOrientations:UIInterfaceOrientationMaskPortrait];
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            UIWindowScene *windowScene = (UIWindowScene *)scene;
            for (UIWindow *window in windowScene.windows) {
                [window.rootViewController setNeedsUpdateOfSupportedInterfaceOrientations];
            }
            [windowScene requestGeometryUpdateWithPreferences:prefs errorHandler:^(NSError *error) {}];
        }
    }
    @try {
        [UIDevice.currentDevice setValue:@(UIInterfaceOrientationPortrait) forKey:@"orientation"];
        [UIViewController attemptRotationToDeviceOrientation];
    } @catch (NSException *exception) {}
}
- (void)request:(NSString *)action {
    if (self.hostMode) {
        [self hide];
        if ([action isEqualToString:@"minimize"]) [NSNotificationCenter.defaultCenter postNotificationName:@"StrataMinimizeAllWindows" object:nil];
        return;
    }
    if (!self.separateProcess) {
        [self hide];
        [self hideFloatingHomeButton];
        [self restorePortraitOrientation];
        // A normal guest owns the main process. Use the existing self-relaunch
        // path to return to the launcher, without requiring a manual force-quit.
        [NSUserDefaults.lcUserDefaults removeObjectForKey:@"selected"];
        [NSUserDefaults.lcUserDefaults removeObjectForKey:@"selectedContainer"];
        [NSUserDefaults.lcUserDefaults removeObjectForKey:@"launchAppUrlScheme"];
        [LCSharedUtils launchToGuestAppWithClassicMode:0];
        return;
    }
    NSURL *root = [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:self.group];
    if (!root) { [self showError:@"Strata's shared container is unavailable. Reinstall with all extensions kept, then reopen this app from Strata."]; return; }
    NSURL *directory = [root URLByAppendingPathComponent:@"Library/StrataControls"];
    NSError *error = nil;
    if (![NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:&error]) { [self showError:error.localizedDescription]; return; }
    NSDictionary *request = @{@"id":NSUUID.UUID.UUIDString, @"pid":@(getpid()), @"action":action, @"timestamp":@(NSDate.date.timeIntervalSince1970)};
    NSData *data = [NSJSONSerialization dataWithJSONObject:request options:0 error:nil];
    if ([data writeToURL:[directory URLByAppendingPathComponent:@"request.json"] options:NSDataWritingAtomic error:nil]) {
        [self hide];
        if ([action isEqualToString:@"close"]) [self hideFloatingHomeButton];
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.strata.controls.request"), NULL, NULL, true);
    } else { [self showError:@"The app controls request could not be saved. Return to Strata and reopen this app."]; }
}
- (void)selectEntry:(NSDictionary *)entry close:(BOOL)close {
    if (close && [entry[@"key"] isEqualToString:self.currentKey]) { [self request:@"close"]; return; }
    if (!close && [entry[@"key"] isEqualToString:self.currentKey]) { [self hide]; return; }
    NSURL *root = [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:self.group];
    NSURL *directory = [root URLByAppendingPathComponent:@"Library/StrataControls"];
    NSError *error = nil;
    if (!directory || ![NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:&error]) {
        [self showError:error.localizedDescription ?: @"Strata's shared container is unavailable."]; return;
    }
    NSDictionary *command = @{@"key":entry[@"key"], @"close":@(close), @"timestamp":@(NSDate.date.timeIntervalSince1970)};
    NSData *data = [NSJSONSerialization dataWithJSONObject:command options:0 error:nil];
    if (![data writeToURL:[directory URLByAppendingPathComponent:@"switch.json"] options:NSDataWritingAtomic error:&error]) { [self showError:error.localizedDescription]; return; }
    if (self.hostMode) {
        [self hide];
        [NSNotificationCenter.defaultCenter postNotificationName:@"StrataLaunchFromControls" object:nil];
    } else [self request:@"library"];
}
- (void)showError:(NSString *)message {
    UIViewController *presenter = self.panel.rootViewController ?: self.floatingWindow.rootViewController ?: UIApplication.sharedApplication.keyWindow.rootViewController;
    if (!presenter) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"App controls unavailable" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [presenter presentViewController:alert animated:YES completion:nil];
}
- (UIButton *)button:(NSString *)title action:(void (^)(void))action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *config;
    config = UIButtonConfiguration.plainButtonConfiguration;
    NSString *symbol = [title isEqualToString:@"Library"] ? @"square.grid.2x2" : ([title isEqualToString:@"Minimize"] ? @"rectangle.stack.badge.minus" : ([title isEqualToString:@"⌄"] ? @"chevron.down" : nil));
    if (symbol) config.image = [UIImage systemImageNamed:symbol];
    else config.title = title;
    config.contentInsets = NSDirectionalEdgeInsetsMake(8, 4, 8, 4);
    button.accessibilityLabel = [title isEqualToString:@"⌄"] ? @"Hide app strip" : title;
    config.baseForegroundColor = UIColor.whiteColor;
    config.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    button.configuration = config;
    [button addAction:[UIAction actionWithHandler:^(UIAction *item) { action(); }] forControlEvents:UIControlEventTouchUpInside];
    return button;
}
- (void)toggle:(UITapGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateRecognized) return;
    [self toggleFromWindow:gesture.view.window ?: (UIWindow *)gesture.view];
}
- (void)toggleFromWindow:(UIWindow *)source {
    if (self.panel) { [self hide]; return; }
    UIWindowScene *scene = source.windowScene;
    UIWindow *window = scene ? [[StrataControlsWindow alloc] initWithWindowScene:scene] : [[StrataControlsWindow alloc] initWithFrame:source.bounds];
    if (scene) window.frame = scene.coordinateSpace.bounds;
    window.multipleTouchEnabled = YES;
    window.accessibilityIdentifier = @"strata.controls.window";
    window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    window.windowLevel = UIWindowLevelAlert + 1;
    window.backgroundColor = UIColor.clearColor;
    StrataControlsController *controller = [StrataControlsController new];
    UIInterfaceOrientation orientation = scene ? scene.interfaceOrientation : UIApplication.sharedApplication.statusBarOrientation;
    if (orientation != UIInterfaceOrientationUnknown) controller.orientationMask = 1 << orientation;
    window.rootViewController = controller;
    controller.view.multipleTouchEnabled = YES;
    controller.view.backgroundColor = UIColor.clearColor;
    UIVisualEffect *effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterialDark];
    if (@available(iOS 26.0, *)) effect = [UIGlassEffect effectWithStyle:UIGlassEffectStyleRegular];
    UIVisualEffectView *glass = [[UIVisualEffectView alloc] initWithEffect:effect];
    glass.multipleTouchEnabled = YES;
    glass.contentView.multipleTouchEnabled = YES;
    glass.accessibilityIdentifier = @"strata.controls.panel";
    glass.layer.cornerRadius = 15;
    glass.clipsToBounds = YES;
    glass.translatesAutoresizingMaskIntoConstraints = NO;
    [controller.view addSubview:glass];
    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [glass.contentView addSubview:stack];
    __weak typeof(self) weakSelf = self;
    [stack addArrangedSubview:[self button:@"⌄" action:^{ [weakSelf hide]; }]];
    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.showsVerticalScrollIndicator = NO;
    [stack addArrangedSubview:scroll];
    UIStackView *icons = [UIStackView new];
    icons.axis = UILayoutConstraintAxisVertical; icons.spacing = 12;
    icons.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:icons];
    NSURL *root = [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:self.group];
    NSData *data = [NSData dataWithContentsOfURL:[root URLByAppendingPathComponent:@"Library/StrataControls/library.json"]];
    NSArray *entries = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (![entries isKindOfClass:NSArray.class]) entries = @[];
    NSUserDefaults *settings = [self sharedDefaults];
    NSArray *pinned = [settings stringArrayForKey:@"StrataSwitcherPinnedApps"] ?: @[];
    entries = [entries filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *entry, NSDictionary *bindings) {
        if (![entry isKindOfClass:NSDictionary.class]) return NO;
        return [entry[@"running"] isEqualToString:@"1"] || [entry[@"key"] isEqualToString:self.currentKey] || [pinned containsObject:entry[@"key"]];
    }]];
    for (NSDictionary *entry in entries) {
        if (![entry isKindOfClass:NSDictionary.class] || ![entry[@"key"] isKindOfClass:NSString.class]) continue;
        UIButton *icon = [UIButton buttonWithType:UIButtonTypeCustom];
        UIImage *image = [UIImage imageWithData:[[NSData alloc] initWithBase64EncodedString:entry[@"icon"] ?: @"" options:0]];
        UIImageView *art = [[UIImageView alloc] initWithImage:image ?: [UIImage systemImageNamed:@"app"]];
        art.contentMode = UIViewContentModeScaleAspectFill;
        art.translatesAutoresizingMaskIntoConstraints = NO; art.userInteractionEnabled = NO;
        [icon addSubview:art];
        [NSLayoutConstraint activateConstraints:@[[art.leadingAnchor constraintEqualToAnchor:icon.leadingAnchor], [art.trailingAnchor constraintEqualToAnchor:icon.trailingAnchor], [art.topAnchor constraintEqualToAnchor:icon.topAnchor], [art.bottomAnchor constraintEqualToAnchor:icon.bottomAnchor]]];
        icon.layer.cornerRadius = 17; icon.clipsToBounds = YES;
        icon.accessibilityLabel = entry[@"name"] ?: @"App";
        [icon.heightAnchor constraintEqualToConstant:72].active = YES;
        [icon addAction:[UIAction actionWithHandler:^(UIAction *action) { [weakSelf selectEntry:entry close:NO]; }] forControlEvents:UIControlEventTouchUpInside];
        UIAction *open = [UIAction actionWithTitle:@"Open app" image:[UIImage systemImageNamed:@"play"] identifier:nil handler:^(UIAction *action) { [weakSelf selectEntry:entry close:NO]; }];
        UIAction *close = [UIAction actionWithTitle:@"Close app" image:[UIImage systemImageNamed:@"xmark.circle"] identifier:nil handler:^(UIAction *action) { [weakSelf selectEntry:entry close:YES]; }];
        close.attributes = UIMenuElementAttributesDestructive;
        BOOL running = [entry[@"key"] isEqualToString:self.currentKey] || [entry[@"running"] isEqualToString:@"1"];
        BOOL isPinned = [pinned containsObject:entry[@"key"]];
        UIAction *pin = [UIAction actionWithTitle:isPinned ? @"Unpin" : @"Pin app" image:[UIImage systemImageNamed:@"pin"] identifier:nil handler:^(UIAction *action) {
            NSMutableArray *values = [[settings stringArrayForKey:@"StrataSwitcherPinnedApps"] mutableCopy] ?: [NSMutableArray new];
            if ([values containsObject:entry[@"key"]]) [values removeObject:entry[@"key"]]; else [values addObject:entry[@"key"]];
            [settings setObject:values forKey:@"StrataSwitcherPinnedApps"];
        }];
        icon.menu = [UIMenu menuWithTitle:entry[@"name"] ?: @"App" children:running ? @[open, close, pin] : @[open, pin]];
        [icons addArrangedSubview:icon];
    }
    if (entries.count == 0) {
        UILabel *empty = [UILabel new]; empty.text = @"No open apps"; empty.numberOfLines = 2; empty.textAlignment = NSTextAlignmentCenter; empty.font = [UIFont systemFontOfSize:12]; empty.textColor = UIColor.secondaryLabelColor;
        [icons addArrangedSubview:empty];
    }
    [stack addArrangedSubview:[self button:@"Minimize" action:^{ [weakSelf request:@"minimize"]; }]];
    [NSLayoutConstraint activateConstraints:@[
        [glass.trailingAnchor constraintEqualToAnchor:controller.view.safeAreaLayoutGuide.trailingAnchor constant:-8],
        [glass.centerYAnchor constraintEqualToAnchor:controller.view.centerYAnchor],
        [glass.widthAnchor constraintEqualToConstant:96],
        [glass.heightAnchor constraintEqualToConstant:MIN(window.bounds.size.height * 0.72, MAX(230, entries.count * 84 + 152))],
        [stack.leadingAnchor constraintEqualToAnchor:glass.contentView.leadingAnchor constant:12],
        [stack.trailingAnchor constraintEqualToAnchor:glass.contentView.trailingAnchor constant:-12],
        [stack.topAnchor constraintEqualToAnchor:glass.contentView.topAnchor constant:10],
        [stack.bottomAnchor constraintEqualToAnchor:glass.contentView.bottomAnchor constant:-10],
        [icons.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],
        [icons.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],
        [icons.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],
        [icons.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],
        [icons.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor],
    ]];
    self.previousKeyWindow = source;
    self.panel = window;
    [self installInWindow:window];
    [window makeKeyAndVisible];
}
@end
void StrataStartGuestControls(NSString *group, NSString *appName, BOOL separateProcess) {
    StrataStartGuestControlsWithIdentity(group, appName, separateProcess, nil);
}
void StrataStartGuestControlsWithIdentity(NSString *group, NSString *appName, BOOL separateProcess, NSString *key) {
    static StrataGuestControls *controls;
    BOOL floatingEnabled = [NSUserDefaults.lcSharedDefaults boolForKey:kStrataFloatingHomeButtonKey];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (controls) return;
        controls = [StrataGuestControls new];
        controls.group = group;
        controls.appName = appName.lastPathComponent ?: @"Strata";
        controls.currentKey = key;
        controls.separateProcess = separateProcess;
        controls.floatingEnabled = floatingEnabled;
        controls.installedWindows = [NSHashTable weakObjectsHashTable];
        [NSNotificationCenter.defaultCenter addObserverForName:UIWindowDidBecomeVisibleNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            if ([note.object isKindOfClass:UIWindow.class]) [controls installInWindow:note.object];
        }];
        if (floatingEnabled) {
            [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                [controls refreshFloatingHomeButtonForWindow:nil];
            }];
        }
        for (UIWindow *window in UIApplication.sharedApplication.windows) [controls installInWindow:window];
        for (UIWindowScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow *window in scene.windows) [controls installInWindow:window];
        }
        if (floatingEnabled) {
            [controls refreshFloatingHomeButtonForWindow:nil];
        }
    });
}

void StrataToggleHostControls(UIWindow *window) {
    static StrataGuestControls *host;
    if (!window) return;
    if (!host) {
        host = [StrataGuestControls new]; host.group = [LCSharedUtils appGroupID]; host.appName = @"Strata";
        host.hostMode = YES; host.installedWindows = [NSHashTable weakObjectsHashTable];
    }
    [host toggleFromWindow:window];
}
