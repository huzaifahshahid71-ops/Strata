#import <Foundation/Foundation.h>

/// Wait before entering the guest runtime, allowing its real debugger attachment first.
NSError *StrataWaitForGuestDebugger(NSString *token, NSURL *root, NSTimeInterval timeout,
                                  BOOL (^isDebugged)(NSError **error));
