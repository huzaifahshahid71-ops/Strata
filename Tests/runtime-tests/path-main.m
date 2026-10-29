#import <Foundation/Foundation.h>
#import "StrataRuntimePath.h"
int main(void) { @autoreleasepool {
    NSURL *root = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
    NSURL *docs = [root URLByAppendingPathComponent:@"Documents"];
    NSURL *group = [root URLByAppendingPathComponent:@"Group"];
    void (^create)(NSURL *, BOOL) = ^(NSURL *base, BOOL executable) {
        NSURL *bundle = [[base URLByAppendingPathComponent:@"Applications"] URLByAppendingPathComponent:@"LiveExec32.app"];
        [NSFileManager.defaultManager createDirectoryAtURL:bundle withIntermediateDirectories:YES attributes:nil error:nil];
        [@{@"CFBundleIdentifier":@"com.kdt.LiveExec32", @"CFBundleExecutable":@"engine", @"CFBundlePackageType":@"APPL", @"LC32BitTranslationLayer":@YES} writeToURL:[bundle URLByAppendingPathComponent:@"Info.plist"] atomically:YES];
        if (executable) [@"fixture" writeToURL:[bundle URLByAppendingPathComponent:@"engine"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    };
    create([group URLByAppendingPathComponent:@"LiveContainer"], YES);
    NSBundle *shared = StrataFind32BitRuntime(@"LiveExec32.app", docs, group);
    NSCAssert(shared && [shared.bundlePath containsString:@"Group/LiveContainer"], @"Private guests must find shared runtimes");
    create(docs, NO);
    NSCAssert(StrataFind32BitRuntime(@"LiveExec32.app", docs, group) != nil, @"Broken private shadow must not mask a readable shared runtime");
    NSCAssert(!StrataFind32BitRuntime(@"../LiveExec32.app", docs, group), @"Traversal rejected");
    NSCAssert(!StrataFind32BitRuntime(@"missing.app", docs, group), @"Missing runtime rejected");
    [NSFileManager.defaultManager removeItemAtURL:root error:nil];
    puts("PASS: actual bundle lookup handles shared runtimes independently of guest location and rejects bad paths.");
} }
