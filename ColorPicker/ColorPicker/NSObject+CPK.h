#import <Cocoa/Cocoa.h>

FOUNDATION_EXPORT NSBundle *CPKResourceBundle(void);

@interface NSObject (CPK)

- (NSImage *)cpk_imageNamed:(NSString *)name;

@end
