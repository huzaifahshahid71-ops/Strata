#import "LCSharedUtils.h"
#import "FoundationPrivate.h"
#import "UIKitPrivate.h"
#import "utils.h"
@import MachO;
#include <sys/sysctl.h>
#include <sys/file.h>
#include <fcntl.h>
#import <objc/message.h>

extern NSUserDefaults *lcUserDefaults;
extern NSString *lcAppUrlScheme;
extern NSBundle *lcMainBundle;
static int strataGuestDataFD = -1;
static NSExtension *strataHostHelper;

NSString* FBSOpenApplicationOptionKeyActivateAsClassic = @"__ActivateAsClassic";
NSString* FBSOpenApplicationOptionKeyPayloadURL = @"__PayloadURL";

@implementation LCSharedUtils

+ (void)strataStopHostJIT {
    if (strataHostHelper) { [strataHostHelper _kill:0]; strataHostHelper = nil; }
    NSUserDefaults *preferences = [[NSUserDefaults alloc] initWithSuiteName:self.appGroupID];
    [preferences removeObjectForKey:@"StrataJITVPNOwnerPID"];
    [preferences removeObjectForKey:@"StrataJITVPNActiveUntil"];
}

+ (void)strataReleaseGuestDataLease { if (strataGuestDataFD >= 0) { close(strataGuestDataFD); strataGuestDataFD = -1; } }

+ (NSString *)strataAcquireGuestDataLease:(NSString *)container {

    if (!container.length || ![container.lastPathComponent isEqualToString:container] || [container isEqualToString:@"."] || [container isEqualToString:@".."]) return @"Invalid guest data container.";
    NSURL *root = [self.appGroupPath URLByAppendingPathComponent:@"Library/StrataDataLocks"];
    if (!root || ![NSFileManager.defaultManager createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:nil]) return @"Cannot open the guest data lock directory.";
    NSURL *file = [root URLByAppendingPathComponent:[container stringByAppendingString:@".lock"]];
    int fd = open(file.fileSystemRepresentation, O_CREAT | O_RDWR | O_NOFOLLOW, 0600);
    if (fd < 0 || flock(fd, LOCK_SH | LOCK_NB) != 0) {
        if (fd >= 0) close(fd);
        return @"A backup, restore or file import is using this guest's data. Wait for it to finish before launching.";
    }
    if (strataGuestDataFD >= 0) close(strataGuestDataFD);
    strataGuestDataFD = fd; // Released automatically when this guest process exits.
    return nil;
}

+ (NSString *)strataAttachHostJIT:(NSDictionary *)request {
    // Cold-start experiment: the debugger lives in JITHelper; the target is this
    // host PID. Retain the helper for the lifetime of the executing guest.

    if (@available(iOS 17.4, *)) {
        void *task = SecTaskCreateFromSelf(NULL);
        CFTypeRef flag = task ? SecTaskCopyValueForEntitlement(task, CFSTR("get-task-allow"), NULL) : NULL;
        BOOL permitted = flag && CFEqual(flag, kCFBooleanTrue);
        if (flag) CFRelease(flag); if (task) CFRelease(task);
        if (!permitted) return @"HostJIT requires get-task-allow on Strata. Use the existing guest-extension JIT path.";
        NSURL *root = self.appGroupPath;
        NSString *home = NSProcessInfo.processInfo.environment[@"LC_HOME_PATH"] ?: NSHomeDirectory();
        NSURL *pairingURL = [NSURL fileURLWithPath:[home stringByAppendingPathComponent:@"Documents/StrataJIT/pairingFile.plist"]];
        NSData *pairing = [NSData dataWithContentsOfURL:pairingURL];
        if (!root || !pairing.length || pairing.length >= 2000000) return @"Import a pairing file and prepare the device before testing HostJIT.";
        NSUserDefaults *preferences = [[NSUserDefaults alloc] initWithSuiteName:self.appGroupID];
        NSString *address = [[preferences stringForKey:@"StrataJITDeviceAddress"] ?: @"10.7.0.1" componentsSeparatedByString:@"/"][0];
        NSInteger port = ([preferences stringForKey:@"StrataJITRemotePairPort"] ?: @"49152").integerValue;
        NSString *token = NSUUID.UUID.UUIDString;
        NSURL *statusURL = [root URLByAppendingPathComponent:[NSString stringWithFormat:@"Library/StrataJIT/%@.json", token]];
        NSURL *diagnosticURL = [root URLByAppendingPathComponent:@"Library/StrataDiagnostics/host-jit.json"];
        void (^record)(NSString *, BOOL) = ^(NSString *message, BOOL attached) {
            [NSFileManager.defaultManager createDirectoryAtURL:diagnosticURL.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
            struct kinfo_proc process = {0}; size_t processSize = sizeof(process); int mib[] = {CTL_KERN,KERN_PROC,KERN_PROC_PID,getpid()};
            BOOL tracing = sysctl(mib, 4, &process, &processSize, NULL, 0) == 0 && (process.kp_proc.p_flag & P_TRACED);
            NSDictionary *object = @{@"schema":@1,@"pid":@(getpid()),@"executionMode":@"inProcess",@"debuggerAttached":@(tracing),@"codeSigningDebugged":@(attached),@"JITVerified":@NO,@"message":message,@"sampledAt":@(NSDate.date.timeIntervalSince1970)};
            [[NSJSONSerialization dataWithJSONObject:object options:0 error:nil] writeToURL:diagnosticURL options:NSDataWritingAtomic error:nil];
        };
        NSError *error = nil;
        strataHostHelper = [NSExtension extensionWithIdentifier:[lcMainBundle.bundleIdentifier stringByAppendingString:@".JITHelper"] error:&error];
        if (!strataHostHelper) { record(@"JIT helper unavailable.", NO); return @"HostJIT helper unavailable. Keep all app extensions when signing."; }
        NSExtensionItem *item = [NSExtensionItem new];
        item.userInfo = @{@"strataJIT":@YES,@"group":self.appGroupID,@"operation":@"enable",@"token":token,@"pid":@(getpid()),@"pairing":pairing,@"script":request[@"script"] ?: @"",@"deviceAddress":address,@"remotePairPort":@(port)};
        [preferences setInteger:getpid() forKey:@"StrataJITVPNOwnerPID"];
        [preferences setDouble:NSDate.date.timeIntervalSince1970 + 30 forKey:@"StrataJITVPNActiveUntil"];
        [strataHostHelper beginExtensionRequestWithInputItems:@[item] completion:^(NSUUID *requestID) {}];
        record(@"Waiting for debugger on the cold-start host process.", NO);
        NSTimeInterval deadline = NSProcessInfo.processInfo.systemUptime + 12;
        NSString *failure = @"HostJIT attachment timed out. Prepare the device with LocalDevVPN connected, then retry or disable HostJIT for this guest.";
        while (NSProcessInfo.processInfo.systemUptime < deadline) {
            unsigned int codeFlags = 0;
            if (csops(getpid(), 0, &codeFlags, sizeof(codeFlags)) == 0 && (codeFlags & CS_DEBUGGED)) {
                record(@"Host marked debugged; entering guest runtime. JIT execution still requires verification.", YES);
                return nil;
            }
            NSData *data = [NSData dataWithContentsOfURL:statusURL];
            NSDictionary *status = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
            if ([status isKindOfClass:NSDictionary.class] && [status[@"done"] boolValue] && ![status[@"success"] boolValue]) { failure = @"HostJIT helper failed. Inspect the latest host-JIT diagnostic and use the existing JIT path."; break; }
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, false);
            [NSThread sleepForTimeInterval:0.01];
        }
        [strataHostHelper _kill:0]; strataHostHelper = nil;
        [preferences removeObjectForKey:@"StrataJITVPNOwnerPID"];
        [preferences removeObjectForKey:@"StrataJITVPNActiveUntil"];
        record(failure, NO);
        return failure;
    }
    return @"HostJIT requires iOS 17.4 or later.";
}

+ (NSString*) teamIdentifier {
    static NSString* ans = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
#if !TARGET_OS_SIMULATOR
        void* taskSelf = SecTaskCreateFromSelf(NULL);
        CFErrorRef error = NULL;
        CFTypeRef cfans = SecTaskCopyValueForEntitlement(taskSelf, CFSTR("com.apple.developer.team-identifier"), &error);
        if(CFGetTypeID(cfans) == CFStringGetTypeID()) {
            ans = (__bridge NSString*)cfans;
        }
        CFRelease(taskSelf);
#endif
        if(!ans) {
            // the above seems not to work if the device is jailbroken by Palera1n, so we use the public api one as backup
            // https://stackoverflow.com/a/11841898
            NSString *tempAccountName = @"bundleSeedID";
            NSDictionary *query = @{
                (__bridge NSString *)kSecClass : (__bridge NSString *)kSecClassGenericPassword,
                (__bridge NSString *)kSecAttrAccount : tempAccountName,
                (__bridge NSString *)kSecAttrService : @"",
                (__bridge NSString *)kSecReturnAttributes: (__bridge NSNumber *)kCFBooleanTrue,
            };
            CFDictionaryRef result = nil;
            OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, (CFTypeRef *)&result);
            if (status == errSecItemNotFound)
                status = SecItemAdd((__bridge CFDictionaryRef)query, (CFTypeRef *)&result);
            if (status == errSecSuccess) {
                status = SecItemDelete((__bridge CFDictionaryRef)query); // remove temp item
                NSDictionary *dict = (__bridge_transfer NSDictionary *)result;
                NSString *accessGroup = dict[(__bridge NSString *)kSecAttrAccessGroup];
                NSArray *components = [accessGroup componentsSeparatedByString:@"."];
                NSString *bundleSeedID = [[components objectEnumerator] nextObject];
                ans = bundleSeedID;
            }
        }
    });
    return ans;
}

+ (NSString *)appGroupID {
    static dispatch_once_t once;
    static NSString *appGroupID = @"Unknown";
    dispatch_once(&once, ^{
        NSArray* possibleAppGroups = @[
            [@"group.com.SideStore.SideStore." stringByAppendingString:[self teamIdentifier]],
            [@"group.com.rileytestut.AltStore." stringByAppendingString:[self teamIdentifier]]
        ];
        
        // we prefer app groups with "Apps" in it, which indicate this app group is actually used by the store.
        for (NSString *group in possibleAppGroups) {
            NSURL *path = [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:group];
            if(!path) {
                continue;
            }
            NSURL *bundlePath = [path URLByAppendingPathComponent:@"Apps"];
            if ([NSFileManager.defaultManager fileExistsAtPath:bundlePath.path]) {
                // This will fail if LiveContainer is installed in both stores, but it should never be the case
                appGroupID = group;
                return;
            }
        }
        
        // if no "Apps" is found, we choose a valid group
        for (NSString *group in possibleAppGroups) {
            NSURL *path = [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:group];
            if(!path) {
                continue;
            }
            appGroupID = group;
            return;
        }
        
        // if no possibleAppGroup is found, we detect app group from entitlement file
        // Cache app group after importing cert so we don't have to analyze executable every launch
        NSString *cached = [lcUserDefaults objectForKey:@"LCAppGroupID"];
        if (cached && [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:cached]) {
            appGroupID = cached;
            return;
        }
        CFErrorRef error = NULL;
        void* taskSelf = SecTaskCreateFromSelf(NULL);
        CFTypeRef value = SecTaskCopyValueForEntitlement(taskSelf, CFSTR("com.apple.security.application-groups"), &error);
        CFRelease(taskSelf);
        
        if(!value) {
            return;
        }
        NSArray* appGroups = (__bridge NSArray *)value;
        if(appGroups.count > 0) {
            appGroupID = [appGroups firstObject];
        }
    });
    return appGroupID;
}

+ (NSURL*) appGroupPath {
    static NSURL *appGroupPath = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        appGroupPath = [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:[LCSharedUtils appGroupID]];
    });
    return appGroupPath;
}

+ (NSString *)certificatePassword {
    NSDictionary *identity = [self strataSigningIdentity];
    if (identity) return identity[@"password"];
    NSUserDefaults* nud = NSUserDefaults.lcSharedDefaults ?: NSUserDefaults.standardUserDefaults;
    return [nud objectForKey:@"LCCertificatePassword"];
}

// A single Keychain item replaces identity and password atomically. All execution
// paths use the already-provisioned shared group; no new entitlement is requested.
+ (NSMutableDictionary *)strataIdentityQuery {
    NSMutableDictionary *q = [@{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService:@"com.strata.signing.v1", (__bridge id)kSecAttrAccount:@"activeIdentity"} mutableCopy];
#if !TARGET_OS_SIMULATOR
    NSString *team = self.teamIdentifier;
    if (team.length) q[(__bridge id)kSecAttrAccessGroup] = [team stringByAppendingString:@".com.kdt.livecontainer.shared"];
#endif
    return q;
}
+ (NSDictionary *)strataSigningIdentity {
    NSMutableDictionary *q = [self strataIdentityQuery];
    q[(__bridge id)kSecReturnData] = @YES;
    q[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    CFTypeRef result = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)q, &result) != errSecSuccess) return nil;
    NSData *bytes = CFBridgingRelease(result);
    if (![bytes isKindOfClass:NSData.class]) return nil;
    NSDictionary *record = [NSPropertyListSerialization propertyListWithData:bytes options:0 format:nil error:nil];
    if (![record isKindOfClass:NSDictionary.class] || ![record[@"p12"] isKindOfClass:NSData.class] || ![record[@"password"] isKindOfClass:NSString.class]) return nil;
    return record;
}
+ (BOOL)strataStoreSigningIdentity:(NSData *)p12 password:(NSString *)password error:(NSError **)error {
    if (!p12.length || p12.length > 16*1024*1024 || !password) {
        if (error) *error = [NSError errorWithDomain:@"StrataIdentity" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Choose a valid .p12 signing identity."}];
        return NO;
    }
    // Reuse the shipping signer's PKCS#12/private-key validation. Apple's native
    // importer rejects some valid empty-password encodings that this signer accepts.
    Class validator = NSClassFromString(@"LCUtils");
    SEL selector = NSSelectorFromString(@"getCertTeamIdWithKeyData:password:");
    NSString *team = [validator respondsToSelector:selector] ? ((id (*)(id, SEL, id, id))objc_msgSend)(validator, selector, p12, password) : nil;
    if (!team.length) {
        if (error) *error = [NSError errorWithDomain:@"StrataIdentity" code:2 userInfo:@{NSLocalizedDescriptionKey:@"The .p12 could not be opened with that password, or has no usable signing private key."}];
        return NO;
    }
    OSStatus status;
    NSData *bytes = [NSPropertyListSerialization dataWithPropertyList:@{@"schema":@1,@"p12":p12,@"password":password,@"importedAt":NSDate.date} format:NSPropertyListBinaryFormat_v1_0 options:0 error:error];
    if (!bytes) return NO;
    NSMutableDictionary *q = [self strataIdentityQuery];
    NSDictionary *attributes = @{(__bridge id)kSecValueData:bytes,(__bridge id)kSecAttrAccessible:(__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly};
    status = SecItemUpdate((__bridge CFDictionaryRef)q, (__bridge CFDictionaryRef)attributes);
    if (status == errSecItemNotFound) {
        [q addEntriesFromDictionary:attributes];
        status = SecItemAdd((__bridge CFDictionaryRef)q, NULL);
    }
    if (status != errSecSuccess && error) *error = [NSError errorWithDomain:@"StrataIdentity" code:status userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"The shared Keychain could not save the identity (%d). The previous identity was retained.", (int)status]}];
    if (status == errSecSuccess) {
        NSDictionary *stored = [self strataSigningIdentity];
        if (![stored[@"p12"] isEqual:p12] || ![stored[@"password"] isEqual:password]) {
            if (error) *error = [NSError errorWithDomain:@"StrataIdentity" code:3 userInfo:@{NSLocalizedDescriptionKey:@"The saved identity could not be read back. Legacy credentials were retained; retry after unlocking the device."}];
            return NO;
        }
    }
    return status == errSecSuccess;
}
+ (BOOL)strataRemoveSigningIdentityWithError:(NSError **)error {
    OSStatus status = SecItemDelete((__bridge CFDictionaryRef)[self strataIdentityQuery]);
    if (status != errSecSuccess && status != errSecItemNotFound) {
        if (error) *error = [NSError errorWithDomain:@"StrataIdentity" code:status userInfo:@{NSLocalizedDescriptionKey:@"The shared Keychain identity could not be removed."}];
        return NO;
    }
    return YES;
}

+ (BOOL)launchToGuestAppWithClassicMode:(NSUInteger)classicMode {
    void (^completionHandler)(BOOL) = ^(BOOL success) {
        // syscall(SYS_ptrace, PT_DENY_ATTACH, 0, 0, 0);
        __asm__ __volatile__ (
                              "mov x0, #31\n"
                              "mov x16, #26\n"
                              "svc #0x80"
                              );
        raise(SIGKILL);
    };
    
    if (!self.certificatePassword) {
        NSString *urlScheme = nil;
        NSString *tsPath = [NSString stringWithFormat:@"%@/../_TrollStore", NSBundle.mainBundle.bundlePath];
        if (!access(tsPath.UTF8String, F_OK)) {
            urlScheme = @"apple-magnifier://enable-jit?bundle-id=%@";
        }
        
        if(urlScheme) {
            NSURL *launchURL = [NSURL URLWithString:[NSString stringWithFormat:urlScheme, NSBundle.mainBundle.bundleIdentifier]];
            UIApplication *application = [NSClassFromString(@"UIApplication") sharedApplication];
            [application openURL:launchURL options:@{} completionHandler:completionHandler];
            return YES;
        }
    }

    int tries = 2;
    _LSOpenConfiguration *configuration = [[PrivClass(_LSOpenConfiguration) alloc] init];
    if(classicMode) {
        NSMutableDictionary* dict = [NSMutableDictionary new];
        dict[FBSOpenApplicationOptionKeyActivateAsClassic] = @(classicMode);
        configuration.frontBoardOptions = dict;
    }
    LSApplicationWorkspace* workspace = [PrivClass(LSApplicationWorkspace) defaultWorkspace];
    
    for (int i = 0; i < tries; i++) {
        [workspace openApplicationWithBundleIdentifier:NSUserDefaults.lcMainBundle.bundleIdentifier
                                         configuration:configuration
                                     completionHandler:^(BOOL success, NSError* error) {
            NSLog(@"success=%d error=%@", success, error);
            completionHandler(success);
        }];
    }
    return YES;
}

+ (BOOL)launchToGuestAppWithURL:(NSURL *)url {
    NSURLComponents* components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    if(![components.host isEqualToString:@"livecontainer-launch"]) return NO;

    NSString* launchBundleId = nil;
    NSString* openUrl = nil;
    NSString* containerFolderName = nil;
    for (NSURLQueryItem* queryItem in components.queryItems) {
        if ([queryItem.name isEqualToString:@"bundle-name"]) {
            launchBundleId = queryItem.value;
        } else if ([queryItem.name isEqualToString:@"open-url"]){
            NSData *decodedData = [[NSData alloc] initWithBase64EncodedString:queryItem.value options:0];
            openUrl = [[NSString alloc] initWithData:decodedData encoding:NSUTF8StringEncoding];
        } else if ([queryItem.name isEqualToString:@"container-folder-name"]) {
            containerFolderName = queryItem.value;
        }
    }
    if(launchBundleId) {
        if (openUrl) {
            [lcUserDefaults setObject:openUrl forKey:@"launchAppUrlScheme"];
        }
        
        // Attempt to restart LiveContainer with the selected guest app
        [lcUserDefaults setObject:launchBundleId forKey:@"selected"];
        [lcUserDefaults setObject:containerFolderName forKey:@"selectedContainer"];
        bool isSharedApp = false;
        NSBundle *appBundle = [self findBundleWithBundleId:launchBundleId isSharedAppOut:&isSharedApp];
        NSDictionary *appInfo = [NSDictionary dictionaryWithContentsOfFile:
            [appBundle.bundlePath stringByAppendingPathComponent:@"LCAppInfo.plist"]];
        NSUInteger classicMode = [appInfo[@"classicMode"] boolValue]
            ? [appInfo[@"LCClassicModeCache"][@"defaultClassicMode"] unsignedIntegerValue]
            : 0;
        return [self launchToGuestAppWithClassicMode:classicMode];
    }
    
    return NO;
}

+ (void)setWebPageUrlForNextLaunch:(NSString*) urlString {
    [lcUserDefaults setObject:urlString forKey:@"webPageToOpen"];
}

+ (NSURL*)containerLockPath {
    static dispatch_once_t once;
    static NSURL *infoPath;
    
    dispatch_once(&once, ^{
        infoPath = [[LCSharedUtils appGroupPath] URLByAppendingPathComponent:@"LiveContainer/containerLock.plist"];
    });
    return infoPath;
}

+ (BOOL)isLCSchemeInUse:(NSString*)lc {
    NSURL* infoPath = [self containerLockPath];
    NSMutableDictionary *info = [NSMutableDictionary dictionaryWithContentsOfFile:infoPath.path];
    if (!info) {
        return NO;
    }
    
    NSNumber* num57 = info[lc];
    if(![num57 isKindOfClass:NSNumber.class]) {
        return NO;
    }
    
    uint64_t val57 = [num57 longLongValue];
    audit_token_t token;
    token.val[5] = val57 >> 32;
    token.val[7] = val57 & 0xffffffff;
    
    errno = 0;
    csops_audittoken(token.val[5], 0, NULL, 0, &token);
    return errno != ESRCH;
}

+ (NSString*)getContainerUsingLCSchemeWithFolderName:(NSString*)folderName {
    NSURL* infoPath = [self containerLockPath];
    NSMutableDictionary *info = [NSMutableDictionary dictionaryWithContentsOfFile:infoPath.path];
    if (!info) {
        return nil;
    }
    
    NSDictionary* appUsageInfo = info[folderName];
    if (!appUsageInfo) {
        return nil;
    }
    uint64_t val57 = [appUsageInfo[@"auditToken57"] longLongValue];
    audit_token_t token;
    token.val[5] = val57 >> 32;
    token.val[7] = val57 & 0xffffffff;
    
    errno = 0;
    csops_audittoken(token.val[5], 0, NULL, 0, &token);
    return errno==ESRCH ? nil : appUsageInfo[@"runningLC"];
}

// lc can be something like livecontainer or livecontainer2.liveprocess, such that one LC can jump to another LC hosting the multitask app when user presses run while it's running
+ (void)setContainerUsingByLC:(NSString*)lc folderName:(NSString*)folderName auditToken:(uint64_t)val57 {
    NSURL* infoPath = [self containerLockPath];
    
    NSMutableDictionary *info = [NSMutableDictionary dictionaryWithContentsOfFile:infoPath.path];
    if (!info) {
        info = [NSMutableDictionary new];
    }
    
    if(val57 == 0) {
        audit_token_t token;
        mach_msg_type_number_t size = TASK_AUDIT_TOKEN_COUNT;
        
        kern_return_t kr = task_info(mach_task_self(), TASK_AUDIT_TOKEN, (task_info_t)&token, &size);
        if (kr != KERN_SUCCESS) {
            NSLog(@"Error getting task audit_token");
        }
        val57 = token.val[7] | ((uint64_t)token.val[5] << 32);
    }
    info[folderName] = @{
        @"runningLC": lc,
        @"auditToken57": @(val57)
    };
    
    info[lc] = @(val57);

    [info writeBinToFile:infoPath.path atomically:YES];
}

// move app data to private folder to prevent 0xdead10cc https://forums.developer.apple.com/forums/thread/126438
// This method is here for backward compatability, 0xdead10cc is already resolved.
+ (void)moveSharedAppFolderBack {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSURL *libraryPathUrl = [fm URLsForDirectory:NSLibraryDirectory inDomains:NSUserDomainMask]
        .lastObject;
    NSURL *docPathUrl = [fm URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask]
        .lastObject;
    NSURL *appGroupFolder = [[LCSharedUtils appGroupPath] URLByAppendingPathComponent:@"LiveContainer"];
    
    NSError *error;
    NSString *sharedAppDataFolderPath = [libraryPathUrl.path stringByAppendingPathComponent:@"SharedDocuments"];
    if(![fm fileExistsAtPath:sharedAppDataFolderPath]){
        return;
    }
    // move all apps in shared folder back
    NSArray<NSString *> * sharedDataFoldersToMove = [fm contentsOfDirectoryAtPath:sharedAppDataFolderPath error:&error];
    
    // something went wrong with app group
    if(!appGroupFolder && sharedDataFoldersToMove.count > 0) {
        [lcUserDefaults setObject:@"LiveContainer was unable to move the data of shared app back because LiveContainer cannot access app group. Please check JITLess diagnose page in LiveContainer settings for more information." forKey:@"error"];
        return;
    }
    
    for(int i = 0; i < [sharedDataFoldersToMove count]; ++i) {
        NSString* destPath = [appGroupFolder.path stringByAppendingPathComponent:[NSString stringWithFormat:@"Data/Application/%@", sharedDataFoldersToMove[i]]];
        if([fm fileExistsAtPath:destPath]) {
            [fm
             moveItemAtPath:[sharedAppDataFolderPath stringByAppendingPathComponent:sharedDataFoldersToMove[i]]
             toPath:[docPathUrl.path stringByAppendingPathComponent:[NSString stringWithFormat:@"FOLDER_EXISTS_AT_APP_GROUP_%@", sharedDataFoldersToMove[i]]]
             error:&error
            ];
            
        } else {
            [fm
             moveItemAtPath:[sharedAppDataFolderPath stringByAppendingPathComponent:sharedDataFoldersToMove[i]]
             toPath:destPath
             error:&error
            ];
        }
    }
    
}

+ (NSBundle*)findBundleWithBundleId:(NSString*)bundleId isSharedAppOut:(bool*)isSharedAppOut {
    NSString *docPath = [NSString stringWithFormat:@"%s/Documents", getenv("LC_HOME_PATH")];
    
    NSURL *appGroupFolder = nil;
    
    NSString *bundlePath = [NSString stringWithFormat:@"%@/Applications/%@", docPath, bundleId];
    NSBundle *appBundle;
    if([NSFileManager.defaultManager fileExistsAtPath:bundlePath]) {
        appBundle = [[NSBundle alloc] initWithPath:bundlePath];
    }

    // not found locally, let's look for the app in shared folder
    if (!appBundle) {
        appGroupFolder = [[LCSharedUtils appGroupPath] URLByAppendingPathComponent:@"LiveContainer"];
        
        bundlePath = [NSString stringWithFormat:@"%@/Applications/%@", appGroupFolder.path, bundleId];
        if([NSFileManager.defaultManager fileExistsAtPath:bundlePath]) {
            appBundle = [[NSBundle alloc] initWithPath:bundlePath];
        }
        if(appBundle) {
            *isSharedAppOut = true;
        }
    } else {
        *isSharedAppOut = false;
    }
    return appBundle;
}

// This method is here for backward compatability, preferences is direcrly saved to app's preference folder.
+ (void)dumpPreferenceToPath:(NSString*)plistLocationTo dataUUID:(NSString*)dataUUID {
    NSFileManager* fm = [[NSFileManager alloc] init];
    NSError* error1;
    
    NSDictionary* preferences = [lcUserDefaults objectForKey:dataUUID];
    if(!preferences) {
        return;
    }
    
    [fm createDirectoryAtPath:plistLocationTo withIntermediateDirectories:YES attributes:@{} error:&error1];
    for(NSString* identifier in preferences) {
        NSDictionary* preference = preferences[identifier];
        NSString *itemPath = [plistLocationTo stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.plist", identifier]];
        if([preference count] == 0) {
            // Attempt to delete the file
            [fm removeItemAtPath:itemPath error:&error1];
            continue;
        }
        [preference writeToFile:itemPath atomically:YES];
    }
    [lcUserDefaults removeObjectForKey:dataUUID];
}

+ (NSString*)findDefaultContainerWithBundleId:(NSString*)bundleId {
    // find app's default container
    NSURL* appGroupFolder = [[LCSharedUtils appGroupPath] URLByAppendingPathComponent:@"LiveContainer"];
    
    NSString* bundleInfoPath = [NSString stringWithFormat:@"%@/Applications/%@/LCAppInfo.plist", appGroupFolder.path, bundleId];
    NSDictionary* infoDict = [NSDictionary dictionaryWithContentsOfFile:bundleInfoPath];
    return infoDict[@"LCDataUUID"];
}

+ (NSArray<NSString*>*)lcUnorderedUrlSchemes {
    NSArray<NSString *> *defaultSchemes = @[@"livecontainer", @"livecontainer2", @"livecontainer3"];
    return defaultSchemes;
}

+ (NSArray<NSString*>*)lcUrlSchemes {
    NSArray<NSString *> *defaultSchemes = [self lcUnorderedUrlSchemes];
    NSSet<NSString *> *allowedSchemes = [NSSet setWithArray:defaultSchemes];
    NSMutableArray<NSString *> *result = [NSMutableArray array];

    id savedValue = [NSUserDefaults.lcSharedDefaults objectForKey:@"LCMultiLaunchPriority"];
    if([savedValue isKindOfClass:NSArray.class]) {
        for(id value in (NSArray *)savedValue) {
            if(![value isKindOfClass:NSString.class]) {
                continue;
            }

            NSString *scheme = [(NSString *)value lowercaseString];
            if(![allowedSchemes containsObject:scheme] || [result containsObject:scheme]) {
                continue;
            }

            [result addObject:scheme];
        }
    }

    for(NSString *scheme in defaultSchemes) {
        if(![result containsObject:scheme]) {
            [result addObject:scheme];
        }
    }

    return result;
}
@end
