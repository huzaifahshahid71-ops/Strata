#import <Foundation/Foundation.h>
#import "StrataJITGuestGate.h"
#import "StrataGuestAcknowledgement.h"
#import <unistd.h>
int main(void) { @autoreleasepool {
    NSURL *root = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
    NSString *token = NSUUID.UUID.UUIDString;
    __block int calls = 0;
    NSDictionary *ready = @{@"token":token, @"pid":@123, @"revision":@12, @"stage":@"waiting"};
    NSCAssert(StrataGuestAcknowledgementMatches(ready, token, 123), @"Matching live request accepted");
    NSCAssert(!StrataGuestAcknowledgementMatches(ready, NSUUID.UUID.UUIDString, 123), @"Stale token rejected");
    NSCAssert(!StrataGuestAcknowledgementMatches(ready, token, 124), @"Wrong PID rejected");
    NSMutableDictionary *failed = ready.mutableCopy; failed[@"stage"] = @"failed";
    NSCAssert(!StrataGuestAcknowledgementMatches(failed, token, 123), @"Exited guest rejected");
    NSError *error = StrataWaitForGuestDebugger(token, root, 1, ^BOOL(NSError **e) { return ++calls == 3; });
    NSCAssert(!error && calls == 3, @"Must wait for actual attach before startup");
    NSURL *recordURL = [root URLByAppendingPathComponent:[NSString stringWithFormat:@"Library/StrataJITGuest/%@.json", token]];
    NSDictionary *record = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:recordURL] options:0 error:nil];
    NSCAssert([record[@"pid"] intValue] == getpid() && [record[@"token"] isEqual:token] && [record[@"stage"] isEqual:@"attached"], @"Own PID and correlated token required");
    error = StrataWaitForGuestDebugger(NSUUID.UUID.UUIDString, root, 0.02, ^BOOL(NSError **e) { return NO; });
    NSCAssert(error && [error.localizedDescription containsString:@"timed out"], @"Missing attach must time out");
    error = StrataWaitForGuestDebugger(NSUUID.UUID.UUIDString, root, 1, ^BOOL(NSError **e) { *e = [NSError errorWithDomain:@"test" code:1 userInfo:nil]; return NO; });
    NSCAssert(error && [error.domain isEqual:@"test"], @"Status read failures must not continue startup");
    NSCAssert(StrataWaitForGuestDebugger(@"invalid", root, 1, ^BOOL(NSError **e){ return YES; }) != nil, @"Invalid token rejected");
    NSCAssert(StrataWaitForGuestDebugger(nil, nil, 0, nil) == nil, @"Normal launch bypass unchanged");
    [NSFileManager.defaultManager removeItemAtURL:root error:nil];
    puts("PASS: guest waits for attach, publishes own PID, times out, rejects invalid requests and preserves normal launches.");
} }
