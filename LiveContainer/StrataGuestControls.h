#import <Foundation/Foundation.h>
void StrataStartGuestControls(NSString *group, NSString *appName, BOOL separateProcess);
void StrataStartGuestControlsWithIdentity(NSString *group, NSString *appName, BOOL separateProcess, NSString *key);

@class UIWindow;
void StrataToggleHostControls(UIWindow *window);
