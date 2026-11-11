#import <objc/runtime.h>
#import "StrataGuestControls.h"
#import "LCSharedUtils.h"
#import "utils.h"
#import <UIKit/UIKit.h>
#import <unistd.h>

@interface StrataControlsWindow : UIWindow
@end
@implementation StrataControlsWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return hit == self.rootViewController.view ? nil : hit;
}
@end
@interface StrataControlsController : UIViewController
@property(nonatomic) UIInterfaceOrientationMask orientationMask;
@end
@implementation StrataControlsController
- (BOOL)prefersStatusBarHidden { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return self.orientationMask ?: UIInterfaceOrientationMaskAllButUpsideDown; }
@end
@interface StrataGuestControls : NSObject<UIGestureRecognizerDelegate, UIScrollViewDelegate>
@property(nonatomic) NSString *group;
@property(nonatomic) NSString *appName;
@property(nonatomic) NSString *currentKey;
@property(nonatomic) BOOL separateProcess;
@property(nonatomic) BOOL hostMode;
@property(nonatomic) UIWindow *panel;
@property(nonatomic, weak) UIWindow *previousKeyWindow;
@property(nonatomic) NSHashTable<UIWindow *> *installedWindows;
@property(nonatomic) CGFloat cardStride;
@property(nonatomic) NSMutableArray<NSDictionary *> *deck;      // {view, body, header, entry}
@property(nonatomic) CGRect deckBounds;
@property(nonatomic) CGFloat deckPosition;
@property(nonatomic) NSInteger deckPage;
@property(nonatomic) NSInteger deckMode;                         // 0 none, 1 browse, 2 lift, 3 home
@property(nonatomic) NSInteger deckLiftIndex;
@property(nonatomic) CGFloat deckLiftOffset;
@property(nonatomic, weak) UIView *deckRoot;
@end
@implementation StrataGuestControls
- (void)installInWindow:(UIWindow *)window {
    if (!window || [self.installedWindows containsObject:window]) return;
    [self.installedWindows addObject:window];
    UITapGestureRecognizer *gesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggle:)];
    gesture.numberOfTouchesRequired = 3;
    gesture.cancelsTouchesInView = window == self.panel;
    gesture.delaysTouchesEnded = window == self.panel;
    gesture.delaysTouchesBegan = NO;
    gesture.delegate = self;
    [window addGestureRecognizer:gesture];
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    // Card swipe-up pans must not run alongside the horizontal card scroll.
    if ([gesture isKindOfClass:UIPanGestureRecognizer.class] && objc_getAssociatedObject(gesture.view, @selector(cardPanned:))) return NO;
    return YES;
}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture {
    if (![gesture isKindOfClass:UIPanGestureRecognizer.class] || !objc_getAssociatedObject(gesture.view, @selector(cardPanned:))) return YES;
    CGPoint velocity = [(UIPanGestureRecognizer *)gesture velocityInView:gesture.view];
    return velocity.y < 0 && fabs(velocity.y) > fabs(velocity.x) * 1.2;   // mostly-vertical, upward
}
- (void)scrollViewWillEndDragging:(UIScrollView *)scrollView withVelocity:(CGPoint)velocity targetContentOffset:(inout CGPoint *)target {
    if (self.cardStride <= 0) return;
    CGFloat page = round(target->x / self.cardStride);
    if (velocity.x > 0.3) page = floor(scrollView.contentOffset.x / self.cardStride) + 1;
    else if (velocity.x < -0.3) page = ceil(scrollView.contentOffset.x / self.cardStride) - 1;
    CGFloat maxX = MAX(0, scrollView.contentSize.width - scrollView.bounds.size.width);
    target->x = MIN(maxX, MAX(0, page * self.cardStride));
}
- (void)hide {
    self.panel.hidden = YES;
    self.panel = nil;
    if (!self.previousKeyWindow.hidden) [self.previousKeyWindow makeKeyWindow];
    self.previousKeyWindow = nil;
}
- (void)request:(NSString *)action {
    if (self.hostMode) {
        [self hide];
        if ([action isEqualToString:@"minimize"]) [NSNotificationCenter.defaultCenter postNotificationName:@"StrataMinimizeAllWindows" object:nil];
        return;
    }
    if (!self.separateProcess) {
        [self hide];
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
/// Closes another running app without leaving the switcher.
- (void)closeInBackground:(NSDictionary *)entry {
    NSURL *root = [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:self.group];
    NSURL *directory = [root URLByAppendingPathComponent:@"Library/StrataControls"];
    if (!directory || ![NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:nil]) return;
    NSDictionary *command = @{@"key":entry[@"key"], @"close":@YES, @"timestamp":@(NSDate.date.timeIntervalSince1970)};
    [[NSJSONSerialization dataWithJSONObject:command options:0 error:nil] writeToURL:[directory URLByAppendingPathComponent:@"switch.json"] atomically:YES];
    if (self.hostMode) { [NSNotificationCenter.defaultCenter postNotificationName:@"StrataLaunchFromControls" object:nil]; return; }
    NSDictionary *request = @{@"id":NSUUID.UUID.UUIDString, @"pid":@(getpid()), @"action":@"closeOther", @"timestamp":@(NSDate.date.timeIntervalSince1970)};
    [[NSJSONSerialization dataWithJSONObject:request options:0 error:nil] writeToURL:[directory URLByAppendingPathComponent:@"request.json"] atomically:YES];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.strata.controls.request"), NULL, NULL, true);
}
- (void)showError:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"App controls unavailable" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self.panel.rootViewController presentViewController:alert animated:YES completion:nil];
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

#pragma mark - Card switcher
// Full-screen card switcher: current app first (live snapshot), then running and pinned apps (icons).
// Tap a card to switch, swipe it up to close it (or unpin a pinned app), tap the background or Home to leave.
- (NSURL *)snapshotURLForKey:(NSString *)key {
    NSURL *root = [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:self.group];
    if (!root || key.length == 0) return nil;
    NSString *safe = [[key componentsSeparatedByCharactersInSet:[[NSCharacterSet alphanumericCharacterSet] invertedSet]] componentsJoinedByString:@"_"];
    NSURL *dir = [root URLByAppendingPathComponent:@"Library/StrataControls/Snapshots" isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return [dir URLByAppendingPathComponent:[safe stringByAppendingString:@".jpg"]];
}
/// Saves the current app's screen for its switcher card. Metal-only screens can come out black;
/// those are skipped so the card falls back to the app icon.
- (void)saveSnapshotOfWindow:(UIWindow *)window {
    NSURL *url = [self snapshotURLForKey:self.currentKey];
    if (!url || !window || window.bounds.size.width < 10) return;
    CGFloat scale = MIN(1.0, 640.0 / MAX(window.bounds.size.width, window.bounds.size.height)) * window.screen.scale;
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat]; format.scale = scale; format.opaque = YES;
    UIImage *image = [[[UIGraphicsImageRenderer alloc] initWithSize:window.bounds.size format:format] imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [window drawViewHierarchyInRect:window.bounds afterScreenUpdates:NO];
    }];
    unsigned char pixel[4] = {0};
    CGContextRef tiny = CGBitmapContextCreate(pixel, 1, 1, 8, 4, CGColorSpaceCreateDeviceRGB(), kCGImageAlphaPremultipliedLast);
    if (tiny && image.CGImage) { CGContextDrawImage(tiny, CGRectMake(0, 0, 1, 1), image.CGImage); }
    if (tiny) CGContextRelease(tiny);
    if (pixel[0] + pixel[1] + pixel[2] < 9) return;
    [UIImageJPEGRepresentation(image, 0.7) writeToURL:url atomically:YES];
}
- (UIImage *)snapshotForKey:(NSString *)key {
    NSURL *url = [self snapshotURLForKey:key];
    return url ? [UIImage imageWithContentsOfFile:url.path] : nil;
}
- (NSArray *)switcherEntries:(NSArray **)pinnedOut {
    NSURL *root = [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:self.group];
    NSData *data = root ? [NSData dataWithContentsOfURL:[root URLByAppendingPathComponent:@"Library/StrataControls/library.json"]] : nil;
    NSArray *all = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (![all isKindOfClass:NSArray.class]) all = @[];
    NSUserDefaults *settings = [[NSUserDefaults alloc] initWithSuiteName:self.group];
    NSArray *pinned = [settings stringArrayForKey:@"StrataSwitcherPinnedApps"] ?: @[];
    NSArray *recents = [settings stringArrayForKey:@"StrataRecentApps"] ?: @[];
    if (pinnedOut) *pinnedOut = pinned;
    NSMutableDictionary *byKey = [NSMutableDictionary new];
    for (NSDictionary *entry in all) if ([entry isKindOfClass:NSDictionary.class] && [entry[@"key"] isKindOfClass:NSString.class]) byKey[entry[@"key"]] = entry;
    NSMutableArray *ordered = [NSMutableArray new]; NSMutableSet *seen = [NSMutableSet new];
    void (^add)(NSString *) = ^(NSString *key) { NSDictionary *entry = byKey[key]; if (entry && ![seen containsObject:key]) { [seen addObject:key]; [ordered addObject:entry]; } };
    if (self.currentKey) add(self.currentKey);
    for (NSDictionary *entry in all) if ([entry isKindOfClass:NSDictionary.class] && [entry[@"running"] isEqualToString:@"1"]) add(entry[@"key"]);
    for (NSString *key in recents) if ([key isKindOfClass:NSString.class]) add(key);
    for (NSString *key in pinned) if ([key isKindOfClass:NSString.class]) add(key);
    return ordered;
}
- (void)cardPanned:(UIPanGestureRecognizer *)pan {
    UIView *card = pan.view;
    CGFloat dy = MIN(0, [pan translationInView:card.superview].y);
    if (pan.state == UIGestureRecognizerStateChanged) {
        card.transform = CGAffineTransformMakeTranslation(0, dy);
        card.alpha = 1 - MIN(0.6, -dy / 600);
    } else if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        BOOL dismiss = dy < -120 || [pan velocityInView:card.superview].y < -900;
        NSDictionary *entry = objc_getAssociatedObject(card, @selector(cardPanned:));
        if (!dismiss || !entry) { [UIView animateWithDuration:0.25 animations:^{ card.transform = CGAffineTransformIdentity; card.alpha = 1; }]; return; }
        [UIView animateWithDuration:0.22 animations:^{ card.transform = CGAffineTransformMakeTranslation(0, -card.superview.bounds.size.height); card.alpha = 0; } completion:^(BOOL finished) {
            BOOL isRunning = [entry[@"key"] isEqualToString:self.currentKey] || [entry[@"running"] isEqualToString:@"1"];
            if (isRunning) { [self selectEntry:entry close:YES]; return; }
            NSUserDefaults *settings = [[NSUserDefaults alloc] initWithSuiteName:self.group];
            for (NSString *list in @[@"StrataSwitcherPinnedApps", @"StrataRecentApps"]) {
                NSMutableArray *values = [[settings stringArrayForKey:list] mutableCopy] ?: [NSMutableArray new];
                [values removeObject:entry[@"key"]]; [settings setObject:values forKey:list];
            }
            [UIView animateWithDuration:0.2 animations:^{ card.hidden = YES; [card.superview layoutIfNeeded]; }];
        }];
    }
}
/// iOS-style open: the tapped card grows to fill the screen, the rest of the switcher fades away.
- (void)zoomCard:(UIView *)card inRoot:(UIView *)root completion:(void (^)(void))completion {
    UIView *portal = [card viewWithTag:7701];
    if (portal) {
        // Live card: grow the card itself (the running app keeps drawing) to full screen.
        CGRect from = [card convertRect:card.bounds toView:root];
        [root addSubview:card]; card.frame = from;
        [UIView animateWithDuration:0.36 delay:0 usingSpringWithDamping:0.9 initialSpringVelocity:0 options:0 animations:^{
            card.frame = root.bounds; card.layer.cornerRadius = 0;
            portal.transform = CGAffineTransformIdentity; portal.center = CGPointMake(CGRectGetMidX(root.bounds), CGRectGetMidY(root.bounds));
            for (UIView *view in root.subviews) if (view != card) view.alpha = 0;
        } completion:^(BOOL finished) { completion(); }];
        return;
    }
    UIView *shot = [card snapshotViewAfterScreenUpdates:NO];
    if (!shot || card.bounds.size.width < 1) { completion(); return; }
    CGRect from = [card convertRect:card.bounds toView:root];
    shot.frame = from; shot.layer.cornerRadius = 22; shot.layer.cornerCurve = kCACornerCurveContinuous; shot.clipsToBounds = YES;
    [root addSubview:shot];
    card.alpha = 0;
    CGFloat scale = root.bounds.size.width / from.size.width;
    [UIView animateWithDuration:0.34 delay:0 usingSpringWithDamping:0.92 initialSpringVelocity:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
        shot.center = CGPointMake(CGRectGetMidX(root.bounds), CGRectGetMidY(root.bounds));
        shot.transform = CGAffineTransformMakeScale(scale, scale);
        shot.layer.cornerRadius = 22 / scale;
        for (UIView *view in root.subviews) if (view != shot) view.alpha = 0;
    } completion:^(BOOL finished) { completion(); }];
}
#pragma mark - Live cards (host)
// Strata registers these when it hosts apps in their own processes: a live view of the app shown full screen,
// and its key. The front card then mirrors the running app live (_UIPortalView) instead of a screenshot.
static UIView *(^strataLiveViewProvider)(NSString *key);
static NSString *(^strataFrontKeyProvider)(void);
void StrataSetSwitcherProviders(UIView *(^live)(NSString *key), NSString *(^front)(void)) {
    strataLiveViewProvider = [live copy]; strataFrontKeyProvider = [front copy];
}
static UIView *StrataPortalForView(UIView *source) {
    Class portalClass = NSClassFromString(@"_UIPortalView");
    if (!portalClass || !source) return nil;
    UIView *portal = [[portalClass alloc] initWithFrame:source.bounds];
    @try {
        [portal setValue:source forKey:@"sourceView"];
        [portal setValue:@NO forKey:@"matchesAlpha"];
        [portal setValue:@NO forKey:@"matchesTransform"];
        [portal setValue:@NO forKey:@"matchesPosition"];
    } @catch (NSException *exception) { return nil; }
    portal.userInteractionEnabled = NO;
    portal.tag = 7701;
    return portal;
}

#pragma mark - iOS-style deck
// Deck geometry and gesture model adapted from ryC0's AppSwitcherView (RYSwitcherLayout / RYSwitcherDeck),
// https://github.com/Sami-Wali/ryC0, AGPL-3.0. Ported to UIKit so it also runs inside guest processes.
static CGRect StrataDeckBaseFrame(CGRect b) {
    CGSize size = CGSizeMake(b.size.width * 0.685, b.size.height * 0.685);
    return CGRectMake(CGRectGetMidX(b) - size.width / 2, CGRectGetMinY(b) + b.size.height * 0.49 - size.height / 2, size.width, size.height);
}
static CGFloat StrataDeckStride(CGRect b) { return MAX(1, b.size.width * 0.53); }
static CGRect StrataDeckFrame(NSInteger index, CGFloat position, CGRect b) {
    CGFloat distance = index - position;
    CGFloat spread = MIN(MAX(position, 0), 1);
    CGFloat offset = b.size.width * (b.size.width > b.size.height ? 0.03 : 0.075) * spread;
    CGRect frame = CGRectOffset(StrataDeckBaseFrame(b), offset, 0);
    if (distance <= 0) return CGRectOffset(frame, -distance * StrataDeckStride(b), 0);
    CGFloat depth = MIN(distance, 4);
    CGFloat peek = 0.135 + spread * 0.045;
    CGFloat inset = (MIN(distance, 1) * peek + MAX(0, distance - 1) * 0.048) * b.size.width;
    return CGRectOffset(CGRectInset(frame, frame.size.width * depth * 0.004, frame.size.height * depth * 0.008), -inset, 0);
}
static const CGFloat StrataDeckHeader = 36;   // icon row + gap above each card

- (void)layoutDeck {
    CGRect b = self.deckBounds;
    for (NSInteger i = 0; i < (NSInteger)self.deck.count; i++) {
        NSDictionary *item = self.deck[i];
        UIView *view = item[@"view"], *body = item[@"body"], *header = item[@"header"], *shade = item[@"shade"];
        CGRect frame = StrataDeckFrame(i, self.deckPosition, b);
        CGFloat lift = (self.deckMode == 2 && self.deckLiftIndex == i) ? MIN(0, self.deckLiftOffset) : 0;
        view.frame = CGRectMake(frame.origin.x, frame.origin.y - StrataDeckHeader + lift, frame.size.width, frame.size.height + StrataDeckHeader);
        body.frame = CGRectMake(0, StrataDeckHeader, frame.size.width, frame.size.height);
        body.layer.cornerRadius = MIN(frame.size.width, frame.size.height) * 0.16;
        header.frame = CGRectMake(frame.size.width * 0.08, 0, frame.size.width * 0.84, 28);
        CGFloat depth = i - self.deckPosition;
        header.alpha = MAX(0, 1 - fabs(depth));
        shade.alpha = MIN(0.28, MAX(0, depth) * 0.24);
        view.layer.zPosition = -i;
    }
}
- (void)settleDeckOn:(NSInteger)page {
    self.deckPage = MIN(MAX(page, 0), MAX(0, (NSInteger)self.deck.count - 1));
    self.deckPosition = self.deckPage; self.deckMode = 0; self.deckLiftOffset = 0;
    [UIView animateWithDuration:0.34 delay:0 usingSpringWithDamping:0.9 initialSpringVelocity:0 options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState animations:^{ [self layoutDeck]; } completion:nil];
}
- (NSInteger)deckIndexAtPoint:(CGPoint)point {
    for (NSInteger i = MAX(0, self.deckPage - 2); i < MIN((NSInteger)self.deck.count, self.deckPage + 5); i++) {
        CGRect frame = StrataDeckFrame(i, self.deckPage, self.deckBounds);
        frame.origin.y -= StrataDeckHeader; frame.size.height += StrataDeckHeader;
        if (CGRectContainsPoint(frame, point)) return i;
    }
    return NSNotFound;
}
- (void)deckPanned:(UIPanGestureRecognizer *)pan {
    CGPoint t = [pan translationInView:pan.view], v = [pan velocityInView:pan.view];
    CGRect b = self.deckBounds;
    if (pan.state == UIGestureRecognizerStateBegan) {
        CGPoint start = CGPointMake([pan locationInView:pan.view].x - t.x, [pan locationInView:pan.view].y - t.y);
        if (fabs(t.x) >= fabs(t.y)) self.deckMode = 1;
        else if (start.y > b.size.height - 45) self.deckMode = 3;
        else { NSInteger index = [self deckIndexAtPoint:start]; self.deckMode = index == NSNotFound ? 0 : 2; self.deckLiftIndex = index; }
    }
    if (pan.state == UIGestureRecognizerStateChanged) {
        if (self.deckMode == 1) {
            CGFloat proposed = self.deckPage + t.x / StrataDeckStride(b);
            CGFloat clamped = MIN(MAX(proposed, 0), MAX(0, (CGFloat)self.deck.count - 1));
            self.deckPosition = clamped + (proposed - clamped) * 0.2;   // rubber band past the ends
            [self layoutDeck];
        } else if (self.deckMode == 2) { self.deckLiftOffset = t.y; [self layoutDeck]; }
    } else if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        if (self.deckMode == 1) {
            CGFloat stride = StrataDeckStride(b);
            CGFloat distance = t.x / stride, predicted = (t.x + v.x * 0.25) / stride;
            CGFloat projected = MIN(MAX(predicted, distance - 1), distance + 1);
            [self settleDeckOn:self.deckPage + (NSInteger)lround(projected)];
        } else if (self.deckMode == 2) {
            BOOL fling = t.y < -28 && (t.y < -b.size.height * 0.10 || v.y < -900);
            if (fling && self.deckLiftIndex != NSNotFound) [self flyAwayDeckCard:self.deckLiftIndex velocity:-v.y];
            else [self settleDeckOn:self.deckPage];
        } else if (self.deckMode == 3) {
            self.deckMode = 0;
            if (t.y < -30) [self hide];
        } else self.deckMode = 0;
    }
}
- (void)deckTapped:(UITapGestureRecognizer *)tap {
    NSInteger index = [self deckIndexAtPoint:[tap locationInView:tap.view]];
    if (index == NSNotFound) { [self hide]; return; }
    NSDictionary *item = self.deck[index];
    __weak typeof(self) weakSelf = self;
    [self zoomCard:item[@"body"] inRoot:self.deckRoot completion:^{ [weakSelf selectEntry:item[@"entry"] close:NO]; }];
}
- (void)flyAwayDeckCard:(NSInteger)index velocity:(CGFloat)velocity {
    NSDictionary *item = self.deck[index];
    UIView *view = item[@"view"];
    CGFloat remaining = MAX(0, self.deckBounds.size.height + view.frame.origin.y);
    NSTimeInterval duration = MAX(0.14, MIN(0.24, remaining / MAX(velocity, 1)));
    self.deckMode = 0;
    [UIView animateWithDuration:duration delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        view.frame = CGRectOffset(view.frame, 0, -self.deckBounds.size.height);
    } completion:^(BOOL finished) {
        NSDictionary *entry = item[@"entry"];
        BOOL running = [entry[@"key"] isEqualToString:self.currentKey] || [entry[@"running"] isEqualToString:@"1"];
        [view removeFromSuperview];
        [self.deck removeObjectAtIndex:index];
        if (running && [entry[@"key"] isEqualToString:self.currentKey] && !self.hostMode) {
            // Closing the app the switcher lives in: in its own process, ask Strata to close it and
            // reopen the switcher there, so the switcher stays up like iOS.
            if (self.separateProcess) [self request:@"closeReopen"]; else [self selectEntry:entry close:YES];
            return;
        }
        if (running) [self closeInBackground:entry];   // like iOS: the switcher stays open
        NSUserDefaults *settings = [[NSUserDefaults alloc] initWithSuiteName:self.group];
        for (NSString *list in @[@"StrataSwitcherPinnedApps", @"StrataRecentApps"]) {
            NSMutableArray *values = [[settings stringArrayForKey:list] mutableCopy] ?: [NSMutableArray new];
            [values removeObject:entry[@"key"]]; [settings setObject:values forKey:list];
        }
        [self settleDeckOn:MIN(self.deckPage, (NSInteger)self.deck.count - 1)];
    }];
}

- (void)presentCardsInController:(StrataControlsController *)controller window:(UIWindow *)window source:(UIWindow *)source {
    if (!self.hostMode) [self saveSnapshotOfWindow:source];
    NSArray *entries = [self switcherEntries:nil];
    UIView *root = controller.view;
    self.deckRoot = root;
    UIVisualEffectView *backdrop = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterialDark]];
    backdrop.frame = root.bounds; backdrop.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    backdrop.accessibilityIdentifier = @"strata.switcher.cards";
    [root addSubview:backdrop];
    UIView *dim = [[UIView alloc] initWithFrame:root.bounds]; dim.backgroundColor = [UIColor colorWithWhite:0 alpha:0.14];
    dim.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight; dim.userInteractionEnabled = NO;
    [backdrop.contentView addSubview:dim];
    UIView *stage = [[UIView alloc] initWithFrame:root.bounds];
    stage.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [backdrop.contentView addSubview:stage];
    self.deckBounds = root.bounds;
    self.deck = [NSMutableArray new];
    self.deckPage = 0; self.deckPosition = 0; self.deckMode = 0;
    UIView *intro = [source snapshotViewAfterScreenUpdates:NO];
    UIView *liveSnapshot = [source snapshotViewAfterScreenUpdates:NO];
    for (NSDictionary *entry in entries) {
        BOOL isCurrent = [entry[@"key"] isEqualToString:self.currentKey];
        UIImage *icon = [UIImage imageWithData:[[NSData alloc] initWithBase64EncodedString:entry[@"icon"] ?: @"" options:0]] ?: [UIImage systemImageNamed:@"app.fill"];
        UIView *view = [UIView new];
        CGRect base = StrataDeckBaseFrame(root.bounds);
        UIView *body = [[UIView alloc] initWithFrame:CGRectMake(0, 0, base.size.width, base.size.height)];
        body.backgroundColor = UIColor.secondarySystemBackgroundColor;
        body.layer.cornerCurve = kCACornerCurveContinuous; body.clipsToBounds = YES;
        body.accessibilityLabel = entry[@"name"] ?: @"App";
        body.accessibilityIdentifier = [@"strata.switcher.card." stringByAppendingString:entry[@"key"]];
        UIImage *shotImage = isCurrent ? nil : [self snapshotForKey:entry[@"key"]];
        UIView *liveSource = (self.hostMode && isCurrent && strataLiveViewProvider) ? strataLiveViewProvider(entry[@"key"]) : nil;
        UIView *portal = liveSource ? StrataPortalForView(liveSource) : nil;
        if (portal) {
            portal.bounds = liveSource.bounds;
            portal.transform = CGAffineTransformMakeScale(base.size.width / MAX(1, liveSource.bounds.size.width), base.size.height / MAX(1, liveSource.bounds.size.height));
            portal.center = CGPointMake(base.size.width / 2, base.size.height / 2);
            [body addSubview:portal];
        } else if (isCurrent && liveSnapshot) {
            liveSnapshot.userInteractionEnabled = NO;
            liveSnapshot.bounds = source.bounds;
            liveSnapshot.transform = CGAffineTransformMakeScale(base.size.width / MAX(1, source.bounds.size.width), base.size.height / MAX(1, source.bounds.size.height));
            liveSnapshot.center = CGPointMake(base.size.width / 2, base.size.height / 2);
            [body addSubview:liveSnapshot];
        } else if (shotImage) {
            UIImageView *shot = [[UIImageView alloc] initWithImage:shotImage];
            shot.frame = body.bounds; shot.clipsToBounds = YES;
            shot.contentMode = UIViewContentModeScaleAspectFill; shot.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            [body addSubview:shot];
        } else {
            UIImageView *big = [[UIImageView alloc] initWithImage:icon];
            big.layer.cornerRadius = 14; big.clipsToBounds = YES;
            big.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
            big.frame = CGRectMake(0, 0, 64, 64);
            big.center = CGPointMake(base.size.width / 2, base.size.height / 2);
            [body addSubview:big];
        }
        UIView *shade = [[UIView alloc] initWithFrame:body.bounds]; shade.backgroundColor = UIColor.blackColor; shade.alpha = 0; shade.userInteractionEnabled = NO;
        shade.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [body addSubview:shade];
        UIStackView *header = [UIStackView new]; header.axis = UILayoutConstraintAxisHorizontal; header.spacing = 8; header.alignment = UIStackViewAlignmentCenter;
        UIImageView *small = [[UIImageView alloc] initWithImage:icon]; small.layer.cornerRadius = 6.5; small.clipsToBounds = YES;
        [small.widthAnchor constraintEqualToConstant:28].active = YES; [small.heightAnchor constraintEqualToConstant:28].active = YES;
        UILabel *name = [UILabel new]; name.text = entry[@"name"] ?: @"App"; name.textColor = UIColor.whiteColor;
        name.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold]; name.lineBreakMode = NSLineBreakByTruncatingTail;
        [header addArrangedSubview:small]; [header addArrangedSubview:name];
        [view addSubview:header]; [view addSubview:body];
        [stage addSubview:view];
        [self.deck addObject:@{@"view": view, @"body": body, @"header": header, @"shade": shade, @"entry": entry}];
    }
    if (entries.count == 0) {
        UILabel *empty = [UILabel new]; empty.text = @"No open apps"; empty.textColor = [UIColor colorWithWhite:1 alpha:0.8];
        empty.font = [UIFont systemFontOfSize:17 weight:UIFontWeightMedium]; [empty sizeToFit];
        empty.center = CGPointMake(CGRectGetMidX(root.bounds), CGRectGetMidY(root.bounds));
        [stage addSubview:empty];
    }
    [self layoutDeck];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(deckPanned:)];
    pan.maximumNumberOfTouches = 1;
    [stage addGestureRecognizer:pan];
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(deckTapped:)];
    [tap requireGestureRecognizerToFail:pan];
    [stage addGestureRecognizer:tap];
    // iOS-style open: the current screen shrinks into the front card.
    NSDictionary *front = self.deck.firstObject;
    if (intro && front && [front[@"entry"][@"key"] isEqualToString:self.currentKey] && !UIAccessibilityIsReduceMotionEnabled()) {
        CGRect target = StrataDeckFrame(0, 0, root.bounds);
        UIView *frontView = front[@"view"];
        intro.frame = root.bounds; intro.clipsToBounds = YES; intro.layer.cornerCurve = kCACornerCurveContinuous;
        [root addSubview:intro];
        backdrop.alpha = 0; frontView.alpha = 0;
        CGFloat scale = target.size.width / MAX(1, root.bounds.size.width);
        [UIView animateWithDuration:0.36 delay:0 usingSpringWithDamping:0.9 initialSpringVelocity:0 options:0 animations:^{
            intro.center = CGPointMake(CGRectGetMidX(target), CGRectGetMidY(target));
            intro.transform = CGAffineTransformMakeScale(scale, scale);
            intro.layer.cornerRadius = MIN(target.size.width, target.size.height) * 0.16 / MAX(0.01, scale);
            backdrop.alpha = 1;
        } completion:^(BOOL finished) { frontView.alpha = 1; [intro removeFromSuperview]; }];
    }
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
    NSString *style = [[[NSUserDefaults alloc] initWithSuiteName:self.group] stringForKey:@"StrataSwitcherStyle"] ?: @"cards";
    if ([style isEqualToString:@"cards"] && self.separateProcess && !self.hostMode) {
        // This app runs in its own process inside Strata: save its snapshot, then let Strata show the deck,
        // where every running app is available and the front card is live.
        [self saveSnapshotOfWindow:source];
        [self request:@"switcher"];
        return;
    }
    if ([style isEqualToString:@"cards"]) {
        [self presentCardsInController:controller window:window source:source];
        self.previousKeyWindow = source;
        self.panel = window;
        [self installInWindow:window];
        [window makeKeyAndVisible];
        return;
    }
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
    NSUserDefaults *settings = [[NSUserDefaults alloc] initWithSuiteName:self.group];
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
    dispatch_async(dispatch_get_main_queue(), ^{
        if (controls) return;
        controls = [StrataGuestControls new];
        controls.group = group;
        controls.appName = appName.lastPathComponent ?: @"Strata";
        controls.currentKey = key;
        controls.separateProcess = separateProcess;
        controls.installedWindows = [NSHashTable weakObjectsHashTable];
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            if (controls.panel) return;
            for (UIWindowScene *scene in UIApplication.sharedApplication.connectedScenes) {
                if (![scene isKindOfClass:UIWindowScene.class]) continue;
                for (UIWindow *window in scene.windows) if (window.isKeyWindow) { [controls saveSnapshotOfWindow:window]; return; }
            }
        }];
        [NSNotificationCenter.defaultCenter addObserverForName:UIWindowDidBecomeVisibleNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            if ([note.object isKindOfClass:UIWindow.class]) [controls installInWindow:note.object];
        }];
        for (UIWindow *window in UIApplication.sharedApplication.windows) [controls installInWindow:window];
        for (UIWindowScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow *window in scene.windows) [controls installInWindow:window];
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
    host.currentKey = strataFrontKeyProvider ? strataFrontKeyProvider() : nil;
    [host toggleFromWindow:window];
}
