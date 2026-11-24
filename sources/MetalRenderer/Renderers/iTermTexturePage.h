//
//  iTermTexturePage.h
//  iTerm2
//
//  Created by George Nachman on 12/22/17.
//

#import <Metal/Metal.h>
#import <simd/simd.h>
#import "GlyphKey.h"
#import "iTermTextureArray.h"

NS_ASSUME_NONNULL_BEGIN

@class iTermCharacterBitmap;

@interface iTermTexturePage : NSObject {
@public
    vector_uint2 _cellSize;
    vector_uint2 _atlasSize;
    vector_float2 _reciprocalAtlasSize;
    long long _lastUsed;
    int _capacity;
    int _count;
}

@property (nonatomic, readonly) iTermTextureArray *textureArray;
@property (nonatomic, readonly) id<MTLTexture> texture;
@property (nonatomic, readonly) int availableCount;

- (instancetype)initWithDevice:(id<MTLDevice>)device
                      capacity:(int)capacity
                      cellSize:(vector_uint2)cellSize NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (int)addImage:(iTermCharacterBitmap *)image isEmoji:(BOOL)isEmoji;
- (BOOL)isEmojiAtIndex:(int)index;
- (void)recordUse;

- (void)recordGlyphKey:(iTermGlyphKey)key;
- (size_t)glyphKeysCount;
- (const iTermGlyphKey * _Nullable)glyphKeys;

@end

NS_ASSUME_NONNULL_END
