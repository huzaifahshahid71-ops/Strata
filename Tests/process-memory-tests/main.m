#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "../../LiveContainer/StrataProcessMemory.h"
#import <unistd.h>
static NSURL *testRoot;
@interface NSFileManager (StrataMemoryTest)
- (NSURL *)strataMemoryTestGroup:(NSString *)group;
@end
@implementation NSFileManager (StrataMemoryTest)
- (NSURL *)strataMemoryTestGroup:(NSString *)group { return testRoot; }
@end
int main(void) {
    @autoreleasepool {
        testRoot = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
        Method real = class_getInstanceMethod(NSFileManager.class, @selector(containerURLForSecurityApplicationGroupIdentifier:));
        Method fake = class_getInstanceMethod(NSFileManager.class, @selector(strataMemoryTestGroup:));
        method_exchangeImplementations(real, fake);
        StrataStartProcessMemoryDiagnostics(@"test-only", @"JSAB.app", @"inProcess");
        NSURL *sampleURL = [testRoot URLByAppendingPathComponent:@"Library/StrataDiagnostics/guest-memory.json"];
        NSDictionary *(^read)(void) = ^{
            NSData *data = [NSData dataWithContentsOfURL:sampleURL];
            return data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        };
        NSDictionary *first = read();
        NSCAssert([first[@"pid"] intValue] == getpid(), @"Actual process PID must be recorded");
        NSCAssert([first[@"executionMode"] isEqual:@"inProcess"], @"Normal launch mode must be recorded");
        NSCAssert([first[@"guest"] isEqual:@"JSAB.app"], @"App name must be recorded");
        NSCAssert(first[@"increasedMemoryEntitlement"] && first[@"availableReported"] && first[@"footprintReported"], @"Report must include availability/entitlement status");
        [NSThread sleepForTimeInterval:6.5];
        NSCAssert([read()[@"sampledAt"] doubleValue] > [first[@"sampledAt"] doubleValue], @"Background timer must update the saved sample");
        StrataStartProcessMemoryDiagnostics(@"test-only", @"AngryBirds.app", @"guestExtension");
        NSCAssert([read()[@"executionMode"] isEqual:@"guestExtension"], @"Guest mode must remain supported");
        method_exchangeImplementations(real, fake);
        [NSFileManager.defaultManager removeItemAtURL:testRoot error:nil];
        puts("PASS: actual process sample, mode/name/PID, status fields, periodic writes and guest mode.");
    }
    return 0;
}
