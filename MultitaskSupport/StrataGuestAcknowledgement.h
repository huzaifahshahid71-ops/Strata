#import <Foundation/Foundation.h>

static inline BOOL StrataGuestAcknowledgementMatches(NSDictionary *record, NSString *token, int requestPID) {
    if (![record isKindOfClass:NSDictionary.class] || ![record[@"token"] isEqual:token] || requestPID <= 0) return NO;
    if (![record[@"pid"] isKindOfClass:NSNumber.class] || [record[@"pid"] intValue] != requestPID) return NO;
    if ([record[@"revision"] intValue] < 12) return NO;
    return [record[@"stage"] isEqual:@"waiting"] || [record[@"stage"] isEqual:@"attached"];
}
