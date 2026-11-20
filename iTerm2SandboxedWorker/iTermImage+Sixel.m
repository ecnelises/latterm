//
//  iTermImage+Sixel.m
//  iTerm2SandboxedWorker
//
//  Created by Benedek Kozma on 2020. 12. 26..
//

#import "iTermImage+Sixel.h"
#import "iTermImage+Private.h"
#ifdef SANDBOXED_WORKER
#import "iTerm2SandboxedWorker-Swift.h"
#else
#import "iTerm2SharedARC-Swift.h"
#endif

@implementation NSImage(ImageDecoder)

+ (instancetype)imageWithRawData:(NSData *)data
                            size:(NSSize)size
                      scaledSize:(NSSize)scaledSize
                   bitsPerSample:(NSInteger)bitsPerSample
                 samplesPerPixel:(NSInteger)samplesPerPixel
                        hasAlpha:(BOOL)hasAlpha
                  colorSpaceName:(NSString *)colorSpaceName {
    assert(data.length == size.width * size.height * bitsPerSample * samplesPerPixel / 8);
    NSBitmapImageRep *bitmapImageRep =
    [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:nil  // allocate the pixel buffer for us
                                            pixelsWide:size.width
                                            pixelsHigh:size.height
                                         bitsPerSample:bitsPerSample
                                       samplesPerPixel:samplesPerPixel
                                              hasAlpha:hasAlpha
                                              isPlanar:NO
                                        colorSpaceName:colorSpaceName
                                           bytesPerRow:bitsPerSample * samplesPerPixel * size.width / 8
                                          bitsPerPixel:bitsPerSample * samplesPerPixel];  // 0 means OS infers it
    
    memmove([bitmapImageRep bitmapData], data.bytes, data.length);
    
    NSImage *theImage = [[NSImage alloc] initWithSize:scaledSize];
    [theImage addRepresentation:bitmapImageRep];
    
    return theImage;
}

@end

@implementation iTermImage(Sixel)

- (instancetype)initWithSixelData:(NSData *)data {
    self = [self init];
    if (self) {
        NSImage *image = [iTermSixelDecoder decodeImageFromData:data];
        if (!image) {
            return nil;
        }
        [self.images addObject:image];
        self.size = image.size;
        self.scaledSize = image.size;
    }
    return self;
}

@end
