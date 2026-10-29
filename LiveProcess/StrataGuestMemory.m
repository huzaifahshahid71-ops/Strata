#import "StrataGuestMemory.h"
#import "../LiveContainer/StrataProcessMemory.h"
void StrataStartGuestMemoryDiagnostics(NSString *group, NSString *guestName) {
    StrataStartProcessMemoryDiagnostics(group, guestName, @"guestExtension");
}
