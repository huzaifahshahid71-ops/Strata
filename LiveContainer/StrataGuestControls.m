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
@interface StrataGuestControls : NSObject<UIGestureRecognizerDelegate>
@property(nonatomic) NSString *group;
@property(nonatomic) NSString *appName;
@property(nonatomic) NSString *currentKey;
@property(nonatomic) BOOL separateProcess;
@property(nonatomic) BOOL hostMode;
@property(nonatomic) UIWindow *panel;
@property(nonatomic, weak) UIWindow *previousKeyWindow;
@property(nonatomic) NSHashTable<UIWindow *> *installedWindows;
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
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other { return YES; }
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
    [host toggleFromWindow:window];
}
