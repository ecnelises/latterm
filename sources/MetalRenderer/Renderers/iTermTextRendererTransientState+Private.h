//
//  iTermTextRendererTransientStatePrivate.h
//  iTerm2
//
//  Created by George Nachman on 12/22/17.
//

#import "iTermASCIITexture.h"
#import "iTermTextRendererTransientState.h"
#import "iTermTexturePageCollection.h"

@interface iTermTextRendererTransientState ()

@property (nonatomic, readonly) NSData *piuData;
@property (nonatomic, strong) id<MTLDevice> device;
@property (nonatomic, strong) iTermASCIITextureGroup *asciiTextureGroup;
@property (nonatomic, strong) iTermTexturePageCollection *texturePageCollection;
@property (nonatomic) NSInteger numberOfCells;
@property (nonatomic) CGSize asciiOffset;

+ (NSString *)formatTextPIU:(iTermTextPIU)a;

- (void)enumerateDraws:(void (^)(const iTermTextPIU *,
                                 NSInteger,
                                 id<MTLTexture>,
                                 vector_uint2,
                                 vector_uint2,
                                 iTermMetalUnderlineDescriptor,
                                 iTermMetalUnderlineDescriptor,
                                 BOOL underlined,
                                 BOOL emoji))block;

@end
