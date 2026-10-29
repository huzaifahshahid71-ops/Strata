#import <Foundation/Foundation.h>

static inline NSBundle *StrataFind32BitRuntime(NSString *folder, NSURL *privateDocuments, NSURL *groupRoot) {
    if (!folder.length || ![folder.lastPathComponent isEqualToString:folder] || [folder containsString:@"\\"] || ![folder.pathExtension.lowercaseString isEqualToString:@"app"]) return nil;
    NSMutableArray<NSURL *> *roots = [NSMutableArray array];
    if (privateDocuments) [roots addObject:privateDocuments];
    if (groupRoot) [roots addObject:[groupRoot URLByAppendingPathComponent:@"LiveContainer"]];
    for (NSURL *root in roots) {
        NSBundle *bundle = [NSBundle bundleWithURL:[[root URLByAppendingPathComponent:@"Applications"] URLByAppendingPathComponent:folder]];
        if (bundle.executablePath && [bundle.infoDictionary[@"LC32BitTranslationLayer"] boolValue] &&
            [NSFileManager.defaultManager isReadableFileAtPath:bundle.executablePath]) return bundle;
    }
    return nil;
}
