#import "StrataProcessMemory.h"
#import <os/proc.h>
#import <mach/mach.h>
#import <Security/Security.h>
#import <unistd.h>
#import <TargetConditionals.h>

#if !TARGET_OS_OSX
extern void *SecTaskCreateFromSelf(CFAllocatorRef allocator);
extern CFTypeRef SecTaskCopyValueForEntitlement(void *task, CFStringRef key, CFErrorRef *error);
#endif

// Capture the real process identity before the guest runtime replaces bundle/home metadata.
// Samples contain no pairing data, account identifiers, paths, or game contents.
void StrataStartProcessMemoryDiagnostics(NSString *group, NSString *guestName, NSString *executionMode) {
    NSURL *root = group.length ? [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:group] : nil;
    if (!root) return;
    NSURL *directory = [root URLByAppendingPathComponent:@"Library/StrataDiagnostics" isDirectory:YES];
    if (![NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:nil]) return;
    void *task = SecTaskCreateFromSelf(NULL);
    CFTypeRef value = task ? SecTaskCopyValueForEntitlement(task, CFSTR("com.apple.developer.kernel.increased-memory-limit"), NULL) : NULL;
    BOOL increased = value && CFEqual(value, kCFBooleanTrue);
    if (value) CFRelease(value);
    if (task) CFRelease(task);
    const pid_t pid = getpid();
    NSString *name = guestName.lastPathComponent ?: @"Guest";
    NSURL *latest = [directory URLByAppendingPathComponent:@"guest-memory.json"];
    NSURL *byPID = [directory URLByAppendingPathComponent:[NSString stringWithFormat:@"%d-memory.json", pid]];
    NSTimeInterval startedAt = NSDate.date.timeIntervalSince1970;
    void (^sample)(void) = ^{
        @autoreleasepool {
            task_vm_info_data_t vm = {0};
            mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
            BOOL hasFootprint = task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&vm, &count) == KERN_SUCCESS;
#if TARGET_OS_OSX
            uint64_t available = 0; // iOS headroom API is unavailable on native macOS.
#else
            uint64_t available = os_proc_available_memory();
#endif
            NSMutableDictionary *record = [@{@"schema":@1, @"pid":@(pid), @"guest":name, @"executionMode":executionMode ?: @"unknown",
                @"startedAt":@(startedAt), @"sampledAt":@(NSDate.date.timeIntervalSince1970),
                @"increasedMemoryEntitlement":@(increased), @"availableBytes":@(available),
                @"availableReported":@(available > 0), @"footprintReported":@(hasFootprint)} mutableCopy];
            if (hasFootprint) record[@"footprintBytes"] = @(vm.phys_footprint);
            NSData *json = [NSJSONSerialization dataWithJSONObject:record options:NSJSONWritingPrettyPrinted error:nil];
            [json writeToURL:byPID options:NSDataWritingAtomic error:nil];
            [json writeToURL:latest options:NSDataWritingAtomic error:nil];
        }
    };
    sample();
    static dispatch_source_t timer;
    if (timer) dispatch_source_cancel(timer);
    timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), 5 * NSEC_PER_SEC, NSEC_PER_SEC);
    dispatch_source_set_event_handler(timer, sample);
    dispatch_resume(timer);
}
