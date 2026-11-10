#import "LCUtils.h"
#import "../../LiveContainer/UIKitPrivate.h"
#import <objc/message.h>

static id StrataPhoneValue(id object, NSString *selectorName) {
    SEL selector = NSSelectorFromString(selectorName);
    return [object respondsToSelector:selector] ? ((id (*)(id, SEL))objc_msgSend)(object, selector) : nil;
}

@implementation LCUtils (StrataPhoneApplications)
+ (NSDictionary *)strataPhoneApplications {
    @try {
        id workspace = StrataPhoneValue(NSClassFromString(@"LSApplicationWorkspace"), @"defaultWorkspace");
        id proxies = StrataPhoneValue(workspace, @"allInstalledApplications");
        if (![proxies isKindOfClass:NSArray.class] || [proxies count] == 0) proxies = StrataPhoneValue(workspace, @"allApplications");
        NSMutableArray *apps = [NSMutableArray array];
        NSMutableSet *seen = [NSMutableSet set];
        for (id proxy in [proxies isKindOfClass:NSArray.class] ? proxies : @[]) {
            NSString *identifier = StrataPhoneValue(proxy, @"applicationIdentifier");
            NSString *name = StrataPhoneValue(proxy, @"localizedName");
            if (![identifier isKindOfClass:NSString.class] || !identifier.length || [identifier isEqual:NSBundle.mainBundle.bundleIdentifier] || [seen containsObject:identifier]) continue;
            if (![name isKindOfClass:NSString.class] || !name.length) continue;
            [seen addObject:identifier]; [apps addObject:@{@"id":identifier,@"name":name}];
        }
        return @{@"apps":apps};
    } @catch (NSException *exception) {
        return @{@"apps":@[],@"error":@"iOS did not allow Strata to read the installed app list."};
    }
}

+ (void)strataOpenPhoneApplication:(NSString *)identifier completion:(void (^)(NSString *))completion {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!identifier.length || identifier.length > 255 || [identifier isEqual:NSBundle.mainBundle.bundleIdentifier] ||
            [identifier rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_"] invertedSet]].location != NSNotFound) {
            completion(@"Invalid iPhone app selection."); return;
        }
        __block BOOL finished = NO;
        void (^finish)(NSString *) = ^(NSString *error) {
            dispatch_async(dispatch_get_main_queue(), ^{ if (!finished) { finished = YES; completion(error); } });
        };
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 8 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ finish(@"iOS did not confirm opening this app. Check that it is installed, or use its App URL."); });
        @try {
            LSApplicationWorkspace *workspace = [NSClassFromString(@"LSApplicationWorkspace") defaultWorkspace];
            _LSOpenConfiguration *configuration = [NSClassFromString(@"_LSOpenConfiguration") new];
            void (^result)(BOOL, NSError *) = ^(BOOL success, NSError *error) {
                finish(success ? nil : (error.localizedDescription ?: @"iOS did not allow this app to open directly. Use its App URL or a Shortcut instead."));
            };
            if ([workspace respondsToSelector:@selector(openApplicationWithBundleIdentifier:usingConfiguration:completionHandler:)]) {
                [workspace openApplicationWithBundleIdentifier:identifier usingConfiguration:configuration completionHandler:result];
            } else if ([workspace respondsToSelector:@selector(openApplicationWithBundleIdentifier:configuration:completionHandler:)]) {
                [workspace openApplicationWithBundleIdentifier:identifier configuration:configuration completionHandler:result];
            } else if ([workspace respondsToSelector:@selector(openApplicationWithBundleID:)]) {
                result([workspace openApplicationWithBundleID:identifier], nil);
            } else { finish(@"Direct app opening is unavailable on this iOS version."); }
        } @catch (NSException *exception) { finish(@"iOS rejected direct app opening. Use an App URL or Shortcut for this app."); }
    });
}
@end

@implementation LCUtils (StrataPhoneApplicationIcons)
+ (UIImage *)strataPhoneApplicationIcon:(NSString *)identifier {
    // Optional private UIKit helper; may return nil or a generic placeholder under current signing.
    SEL selector = NSSelectorFromString(@"_applicationIconImageForBundleIdentifier:format:scale:");
    if (!identifier.length || ![UIImage respondsToSelector:selector]) return nil;
    @try {
        UIImage *image = ((UIImage *(*)(id, SEL, NSString *, int, CGFloat))objc_msgSend)(UIImage.class, selector, identifier, 2, 3.0);
        return image.size.width >= 20 ? image : nil;
    } @catch (NSException *exception) { return nil; }
}
@end
