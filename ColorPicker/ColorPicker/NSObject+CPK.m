#import "NSObject+CPK.h"
#import "CPKColorWell.h"

NSBundle *CPKResourceBundle(void) {
#if SWIFT_PACKAGE
    return SWIFTPM_MODULE_BUNDLE;
#else
    return [NSBundle bundleForClass:[CPKColorWell class]];
#endif
}

@implementation NSObject (CPK)

- (NSImage *)cpk_imageNamed:(NSString *)name {
#if SWIFT_PACKAGE
    NSBundle *bundle = CPKResourceBundle();
    NSURL *url = [bundle URLForResource:name withExtension:@"png"];
    NSImage *image = url ? [[NSImage alloc] initWithContentsOfURL:url] : nil;
    NSURL *retinaURL = [bundle URLForResource:[name stringByAppendingString:@"@2x"] withExtension:@"png"];
    NSImageRep *retina = retinaURL ? [NSImageRep imageRepWithContentsOfURL:retinaURL] : nil;
    if (image && retina) {
        retina.size = image.size;
        [image addRepresentation:retina];
    }
    return image;
#else
    NSString *path = [CPKResourceBundle() pathForResource:name ofType:@"tiff"];
    return [[NSImage alloc] initWithContentsOfFile:path];
#endif
}

@end
