#import "StrataJITGuestGate.h"
#import <unistd.h>

NSError *StrataWaitForGuestDebugger(NSString *token, NSURL *root, NSTimeInterval timeout,
                                  BOOL (^isDebugged)(NSError **error)) {
    if (!token) return nil; // Normal launches retain the upstream path.
    NSError *(^failure)(NSString *) = ^NSError *(NSString *message) {
        return [NSError errorWithDomain:@"StrataJITGuest" code:12 userInfo:@{NSLocalizedDescriptionKey:message}];
    };
    if (![[NSUUID alloc] initWithUUIDString:token] || !root || !isfinite(timeout) || timeout <= 0)
        return failure(@"Invalid JIT guest startup request.");
    NSURL *directory = [root URLByAppendingPathComponent:@"Library/StrataJITGuest"];
    NSError *error;
    if (![NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:&error]) return error;
    NSURL *recordURL = [directory URLByAppendingPathComponent:[token stringByAppendingString:@".json"]];
    NSURL *pidURL = [directory URLByAppendingPathComponent:[NSString stringWithFormat:@"%d.json", getpid()]];
    BOOL (^report)(NSString *, NSString *) = ^BOOL (NSString *stage, NSString *message) {
        NSDictionary *record = @{@"token":token, @"pid":@(getpid()), @"stage":stage, @"message":message,
                                  @"revision":@12, @"timestamp":@([NSDate.date timeIntervalSince1970])};
        NSData *data = [NSJSONSerialization dataWithJSONObject:record options:0 error:nil];
        return data && [data writeToURL:recordURL options:NSDataWritingAtomic error:nil]
                    && [data writeToURL:pidURL options:NSDataWritingAtomic error:nil];
    };
    if (!report(@"waiting", @"Guest startup paused until debugger attaches."))
        return failure(@"Cannot save the guest JIT startup acknowledgement.");
    NSTimeInterval deadline = NSProcessInfo.processInfo.systemUptime + timeout;
    while (YES) {
        NSError *readError = nil;
        if (isDebugged(&readError)) {
            report(@"attached", @"Debugger attached; entering the existing guest runtime.");
            return nil;
        }
        if (readError) { report(@"failed", readError.localizedDescription); return readError; }
        if (NSProcessInfo.processInfo.systemUptime >= deadline) {
            NSError *expired = failure(@"Guest timed out waiting for debugger attachment. Check the saved JIT status.");
            report(@"failed", expired.localizedDescription);
            return expired;
        }
        [NSThread sleepForTimeInterval:0.05];
    }
}
