//
//  iTermTextRendererTransientState.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/22/17.
//

#import "FutureMethods.h"
#import "iTermTextRendererTransientState.h"
#import "iTermTextRendererTransientState+Private.h"
#import "iTermGCD.h"
#import "iTermMalloc.h"
#import "iTermPIUArray.h"
#import "iTermTexturePage.h"
#import "iTermTexturePageCollection.h"
#import "NSMutableData+iTerm.h"
#import <stdlib.h>

const vector_float4 iTermAnnotationUnderlineColor = { 1, 1, 0, 1 };

static vector_uint2 CGSizeToVectorUInt2(CGSize size) {
    return simd_make_uint2(size.width, size.height);
}

#define iTermPIUArrayIndexNotUnderlined 0
#define iTermPIUArrayIndexUnderlined 1
#define iTermPIUArrayIndexNotUnderlinedEmoji 2
#define iTermPIUArrayIndexUnderlinedEmoji 3
#define iTermPIUArraySize 4

#define iTermNumberOfPIUArrays (iTermASCIITextureAttributesMax * 2)

#pragma mark - Open-Addressing Map: iTermTexturePage * -> iTermTextPIUArray *

typedef struct {
    __unsafe_unretained iTermTexturePage *page;
    iTermTextPIUArray *array;
} iTermPagePIUSlot;

typedef struct {
    iTermPagePIUSlot *slots;
    size_t capacity;
    size_t count;
} iTermPagePIUMap;

NS_INLINE size_t iTermPagePointerHash(const void *ptr) {
    uint64_t x = (uint64_t)(uintptr_t)ptr >> 4;
    x ^= x >> 33;
    x *= 0xff51afd7ed558ccdULL;
    x ^= x >> 33;
    return (size_t)x;
}

static void iTermPagePIUMapDestroy(iTermPagePIUMap *map) {
    free(map->slots);
    map->slots = NULL;
    map->capacity = 0;
    map->count = 0;
}

static void iTermPagePIUMapInsertNoGrow(iTermPagePIUMap *map,
                                        iTermTexturePage *page,
                                        iTermTextPIUArray *array) {
    const size_t mask = map->capacity - 1;
    size_t idx = iTermPagePointerHash((__bridge const void *)page) & mask;
    while (map->slots[idx].page != nil) {
        if (map->slots[idx].page == page) {
            map->slots[idx].array = array;
            return;
        }
        idx = (idx + 1) & mask;
    }
    map->slots[idx].page = page;
    map->slots[idx].array = array;
    map->count += 1;
}

static iTermTextPIUArray *iTermPagePIUMapFind(const iTermPagePIUMap *map, iTermTexturePage *page) {
    if (!map->slots || map->capacity == 0 || map->count == 0) {
        return NULL;
    }
    const size_t mask = map->capacity - 1;
    size_t idx = iTermPagePointerHash((__bridge const void *)page) & mask;
    while (map->slots[idx].page != nil) {
        if (map->slots[idx].page == page) {
            return map->slots[idx].array;
        }
        idx = (idx + 1) & mask;
    }
    return NULL;
}

static void iTermPagePIUMapSet(iTermPagePIUMap *map,
                               iTermTexturePage *page,
                               iTermTextPIUArray *array) {
    if (!map->slots || map->capacity == 0) {
        const size_t initialCapacity = 16;
        map->slots = (iTermPagePIUSlot *)iTermCalloc(initialCapacity, sizeof(iTermPagePIUSlot));
        map->capacity = initialCapacity;
        map->count = 0;
    } else if ((map->count + 1) * 10 >= map->capacity * 7) {
        iTermPagePIUSlot *oldSlots = map->slots;
        const size_t oldCapacity = map->capacity;
        const size_t newCapacity = oldCapacity * 2;
        map->slots = (iTermPagePIUSlot *)iTermCalloc(newCapacity, sizeof(iTermPagePIUSlot));
        map->capacity = newCapacity;
        map->count = 0;
        for (size_t i = 0; i < oldCapacity; i++) {
            if (oldSlots[i].page != nil) {
                iTermPagePIUMapInsertNoGrow(map, oldSlots[i].page, oldSlots[i].array);
            }
        }
        free(oldSlots);
    }
    iTermPagePIUMapInsertNoGrow(map, page, array);
}

// Carrier struct for moving PIUArrays to background deallocation queue.
typedef struct {
    iTermTextPIUArray asciiArrays[iTermPIUArraySize][iTermNumberOfPIUArrays];
    iTermTextPIUArray **heapArrays;
    size_t heapArrayCount;
} iTermPIUArrayDeallocCarrier;

static void iTermPIUArrayDeallocCarrierDestroy(iTermPIUArrayDeallocCarrier *carrier) {
    for (size_t i = 0; i < iTermPIUArraySize; i++) {
        for (size_t j = 0; j < iTermNumberOfPIUArrays; j++) {
            iTermTextPIUArrayDestroy(&carrier->asciiArrays[i][j]);
        }
    }
    for (size_t i = 0; i < carrier->heapArrayCount; i++) {
        iTermTextPIUArrayDestroy(carrier->heapArrays[i]);
        free(carrier->heapArrays[i]);
    }
    free(carrier->heapArrays);
    free(carrier);
}

@implementation iTermTextRendererTransientState {
    iTermTextPIUArray _asciiPIUArrays[iTermPIUArraySize][iTermNumberOfPIUArrays];

    // Array of PIUs for each texture page.
    iTermPagePIUMap _pius[iTermPIUArraySize];
    NSMutableArray<iTermTexturePage *> *_retainedPages;

    iTermPreciseTimerStats _stats[iTermTextRendererStatCount];

    // Set per-row to suppress underlines on DECDHL top-half lines.
    BOOL _suppressUnderlineForDHL;
}

- (void)dealloc {
    // Count total PIUs to decide if background deallocation is worthwhile.
    // The dispatch overhead isn't free, so for small amounts of data it's
    // cheaper to just deallocate inline.
    static const size_t kAsyncDeallocThreshold = 100;
    size_t totalSize = 0;
    size_t totalHeapCount = 0;
    for (size_t i = 0; i < iTermPIUArraySize; i++) {
        if (totalSize < kAsyncDeallocThreshold) {
            for (size_t j = 0; j < iTermNumberOfPIUArrays && totalSize < kAsyncDeallocThreshold; j++) {
                totalSize += iTermTextPIUArraySize(&_asciiPIUArrays[i][j]);
            }
            totalSize += _pius[i].count;
        }
        totalHeapCount += _pius[i].count;
    }

    if (totalSize < kAsyncDeallocThreshold) {
        for (size_t i = 0; i < iTermPIUArraySize; i++) {
            for (size_t j = 0; j < iTermNumberOfPIUArrays; j++) {
                iTermTextPIUArrayDestroy(&_asciiPIUArrays[i][j]);
            }
            for (size_t s = 0; s < _pius[i].capacity; s++) {
                if (_pius[i].slots[s].page != nil) {
                    iTermTextPIUArrayDestroy(_pius[i].slots[s].array);
                    free(_pius[i].slots[s].array);
                }
            }
            iTermPagePIUMapDestroy(&_pius[i]);
        }
        return;
    }

    iTermPIUArrayDeallocCarrier *carrier = (iTermPIUArrayDeallocCarrier *)iTermCalloc(1, sizeof(iTermPIUArrayDeallocCarrier));
    if (totalHeapCount > 0) {
        carrier->heapArrays = (iTermTextPIUArray **)malloc(totalHeapCount * sizeof(iTermTextPIUArray *));
    }
    size_t heapIdx = 0;
    for (size_t i = 0; i < iTermPIUArraySize; i++) {
        for (size_t j = 0; j < iTermNumberOfPIUArrays; j++) {
            iTermTextPIUArrayMove(&carrier->asciiArrays[i][j], &_asciiPIUArrays[i][j]);
        }
        for (size_t s = 0; s < _pius[i].capacity; s++) {
            if (_pius[i].slots[s].page != nil) {
                carrier->heapArrays[heapIdx++] = _pius[i].slots[s].array;
            }
        }
        iTermPagePIUMapDestroy(&_pius[i]);
    }
    carrier->heapArrayCount = heapIdx;

    dispatch_async([iTermGCD deallocQueue], ^{
        iTermPIUArrayDeallocCarrierDestroy(carrier);
    });
}

+ (NSString *)formatTextPIU:(iTermTextPIU)a {
    return [NSString stringWithFormat:
            @"offset=(%@, %@) "
            @"textureOffset=(%@, %@) "
            @"textColor=(%@, %@, %@, %@) "
            @"underlineStyle=%@ "
            @"underlineColor=(%@, %@, %@, %@)\n",
            @(a.offset.x),
            @(a.offset.y),
            @(a.textureOffset.x),
            @(a.textureOffset.y),
            @(a.textColor.x),
            @(a.textColor.y),
            @(a.textColor.z),
            @(a.textColor.w),
            @(a.underlineStyle),
            @(a.underlineColor.x),
            @(a.underlineColor.y),
            @(a.underlineColor.z),
            @(a.underlineColor.w)];
}

- (void)writeDebugInfoToFolder:(NSURL *)folder {
    [super writeDebugInfoToFolder:folder];

    @autoreleasepool {
        for (int k = 0; k < iTermPIUArraySize; k++) {
            for (NSUInteger i = 0; i < iTermNumberOfPIUArrays; i++) {
                NSMutableString *s = [NSMutableString string];
                const size_t size = iTermTextPIUArraySize(&_asciiPIUArrays[k][i]);
                for (size_t j = 0; j < size; j++) {
                    const iTermTextPIU *a = iTermTextPIUArrayGet(&_asciiPIUArrays[k][i], j);
                    [s appendString:[self.class formatTextPIU:*a]];
                }
                NSMutableString *name = [NSMutableString stringWithFormat:@"asciiPIUs.CenterPart."];
                if (i & iTermASCIITextureAttributesBold) {
                    [name appendString:@"B"];
                }
                if (i & iTermASCIITextureAttributesItalic) {
                    [name appendString:@"I"];
                }
                if (i & iTermASCIITextureAttributesThinStrokes) {
                    [name appendString:@"T"];
                }
                if (k == iTermPIUArrayIndexUnderlined ||
                    k == iTermPIUArrayIndexUnderlinedEmoji) {
                    [name appendString:@"U"];
                }
                if (k == iTermPIUArrayIndexNotUnderlinedEmoji ||
                    k == iTermPIUArrayIndexUnderlinedEmoji) {
                    [name appendString:@"E"];
                }
                [name appendString:@".txt"];
                [s writeToURL:[folder URLByAppendingPathComponent:name] atomically:NO encoding:NSUTF8StringEncoding error:nil];
            }
        }
    }

    @autoreleasepool {
        for (int k = 0; k < iTermPIUArraySize; k++) {
            NSMutableString *s = [NSMutableString string];
            for (size_t idx = 0; idx < _pius[k].capacity; idx++) {
                iTermTexturePage *texturePage = _pius[k].slots[idx].page;
                if (!texturePage) {
                    continue;
                }
                iTermTextPIUArray *piuArray = _pius[k].slots[idx].array;
                [s appendFormat:@"Texture Page with texture %@:\n", texturePage.texture.label];
                if (piuArray) {
                    const size_t count = iTermTextPIUArraySize(piuArray);
                    for (size_t j = 0; j < count; j++) {
                        iTermTextPIU *piu = iTermTextPIUArrayGet(piuArray, j);
                        [s appendString:[self.class formatTextPIU:*piu]];
                    }
                }
            }
            NSString *name = @"non-ascii-pius.txt";
            if (k & iTermPIUArrayIndexUnderlined) {
                name = [@"underlined-" stringByAppendingString:name];
            }
            if (k & iTermPIUArrayIndexNotUnderlinedEmoji) {
                name = [@"emoji-" stringByAppendingString:name];
            }
            [s writeToURL:[folder URLByAppendingPathComponent:name] atomically:NO encoding:NSUTF8StringEncoding error:nil];
        }
    }

    NSString *s = [NSString stringWithFormat:@"asciiUnderlineDescriptor=%@\nnonAsciiUnderlineDescriptor=%@\nstrikethroughUnderlineDescriptor=%@",
                   iTermMetalUnderlineDescriptorDescription(&_asciiUnderlineDescriptor),
                   iTermMetalUnderlineDescriptorDescription(&_nonAsciiUnderlineDescriptor),
                   iTermMetalUnderlineDescriptorDescription(&_strikethroughUnderlineDescriptor)];
    [s writeToURL:[folder URLByAppendingPathComponent:@"state.txt"]
       atomically:NO
         encoding:NSUTF8StringEncoding
            error:NULL];
}

- (iTermPreciseTimerStats *)stats {
    return _stats;
}

- (int)numberOfStats {
    return iTermTextRendererStatCount;
}

- (NSString *)nameForStat:(int)i {
    return [@[ @"text.newQuad",
               @"text.newPIU",
               @"text.newDims",
               @"text.info",
               @"text.draw" ] objectAtIndex:i];
}

- (void)enumerateASCIIDrawsFromArrays:(const iTermTextPIUArray *)piuArrays
                           underlined:(BOOL)underlined
                                emoji:(BOOL)emoji
                                block:(void (^)(const iTermTextPIU *,
                                                NSInteger,
                                                id<MTLTexture>,
                                                vector_uint2,
                                                vector_uint2,
                                                iTermMetalUnderlineDescriptor,
                                                iTermMetalUnderlineDescriptor,
                                                BOOL underlined,
                                                BOOL emoji))block {
    // ASCII glyphs are shifted by self.asciiOffset.height pixels relative to non-ascii glyphs.
    // The underlines would come along with them so we adjust them here. Issue 10168.
    iTermMetalUnderlineDescriptor adjustedASCIIUnderlineDescriptor = _asciiUnderlineDescriptor;
    adjustedASCIIUnderlineDescriptor.offset -= self.asciiOffset.height / self.configuration.scale;
    vector_uint2 augmentedGlyphSize = CGSizeToVectorUInt2(_asciiTextureGroup.glyphSize);
    // There is only a center part for ASCII because the glyph size is increased to contain the largest ASCII glyph, notwithstanding the ascii offset.
    // If we don't account for ascii offset here than glyphs that spill into the right (such as Italic often does) can be truncated.
    augmentedGlyphSize.x += self.asciiOffset.width;
    augmentedGlyphSize.y += self.asciiOffset.height;
    for (int i = 0; i < (int)iTermNumberOfPIUArrays; i++) {
        const size_t n = iTermTextPIUArraySegmentCount(&piuArrays[i]);
        iTermASCIITexture *asciiTexture = [_asciiTextureGroup asciiTextureForAttributes:(iTermASCIITextureAttributes)i];
        ITBetaAssert(asciiTexture, @"nil ascii texture for attributes %d", i);
        for (size_t j = 0; j < n; j++) {
            const size_t segSize = iTermTextPIUArraySegmentSize(&piuArrays[i], j);
            if (segSize > 0) {
                block(iTermTextPIUArraySegmentStart(&piuArrays[i], j),
                      (NSInteger)segSize,
                      asciiTexture.textureArray.texture,
                      CGSizeToVectorUInt2(asciiTexture.textureArray.atlasSize),
                      augmentedGlyphSize,
                      adjustedASCIIUnderlineDescriptor,
                      _strikethroughUnderlineDescriptor,
                      underlined,
                      emoji);
            }
        }
    }
}

- (size_t)enumerateNonASCIIDraws:(void (^)(const iTermTextPIU *,
                                           NSInteger,
                                           id<MTLTexture>,
                                           vector_uint2,
                                           vector_uint2,
                                           iTermMetalUnderlineDescriptor,
                                           iTermMetalUnderlineDescriptor,
                                           BOOL underlined,
                                           BOOL emoji))block {
    size_t sum = 0;
    for (size_t k = 0; k < iTermPIUArraySize; k++) {
        for (size_t idx = 0; idx < _pius[k].capacity; idx++) {
            iTermTexturePage *texturePage = _pius[k].slots[idx].page;
            if (!texturePage) {
                continue;
            }
            const iTermTextPIUArray *piuArray = _pius[k].slots[idx].array;
            const size_t segCount = iTermTextPIUArraySegmentCount(piuArray);
            for (size_t i = 0; i < segCount; i++) {
                const size_t count = iTermTextPIUArraySegmentSize(piuArray, i);
                if (count > 0) {
                    sum += count;
                    block(iTermTextPIUArraySegmentStart(piuArray, i),
                          (NSInteger)count,
                          texturePage.texture,
                          texturePage->_atlasSize,
                          texturePage->_cellSize,
                          _nonAsciiUnderlineDescriptor,
                          _strikethroughUnderlineDescriptor,
                          !!(k & iTermPIUArrayIndexUnderlined),
                          !!(k & iTermPIUArrayIndexNotUnderlinedEmoji));
                }
            }
        }
    }
    return sum;
}

- (void)enumerateASCIIDrawsWithBlock:(void (^)(const iTermTextPIU *, NSInteger, id<MTLTexture>, vector_uint2, vector_uint2, iTermMetalUnderlineDescriptor, iTermMetalUnderlineDescriptor, BOOL, BOOL))block {
    [self enumerateASCIIDrawsFromArrays:_asciiPIUArrays[iTermPIUArrayIndexUnderlined]
                             underlined:YES
                                  emoji:NO
                                  block:block];
    [self enumerateASCIIDrawsFromArrays:_asciiPIUArrays[iTermPIUArrayIndexUnderlinedEmoji]
                             underlined:YES
                                  emoji:YES
                                  block:block];
    [self enumerateASCIIDrawsFromArrays:_asciiPIUArrays[iTermPIUArrayIndexNotUnderlined]
                             underlined:NO
                                  emoji:NO
                                  block:block];
    [self enumerateASCIIDrawsFromArrays:_asciiPIUArrays[iTermPIUArrayIndexNotUnderlinedEmoji]
                             underlined:NO
                                  emoji:YES
                                  block:block];
}

- (void)enumerateDraws:(void (^)(const iTermTextPIU *,
                                 NSInteger,
                                 id<MTLTexture>,
                                 vector_uint2,
                                 vector_uint2,
                                 iTermMetalUnderlineDescriptor,
                                 iTermMetalUnderlineDescriptor,
                                 BOOL underlined,
                                 BOOL emoji))block {
    [self enumerateNonASCIIDraws:block];
    [self enumerateASCIIDrawsWithBlock:block];
}

- (void)willDraw {
    DLog(@"WILL DRAW %@", self);
    for (int k = 0; k < iTermPIUArraySize; k++) {
        for (size_t idx = 0; idx < _pius[k].capacity; idx++) {
            iTermTexturePage *page = _pius[k].slots[idx].page;
            if (page) {
                [page recordUse];
            }
        }
    }
    DLog(@"END WILL DRAW");
}

NS_INLINE iTermTextPIU *iTermTextRendererTransientStateAddASCIIPart(iTermTextPIU *piu,
                                                                    char code,
                                                                    float w,
                                                                    float h,
                                                                    iTermASCIITexture *texture,
                                                                    float cellWidth,
                                                                    int visualColumn,
                                                                    CGSize asciiOffset,
                                                                    iTermASCIITextureOffset offset,
                                                                    vector_float4 textColor,
                                                                    iTermMetalGlyphAttributesUnderline underlineStyle,
                                                                    vector_float4 underlineColor) {
    piu->offset = simd_make_float2(visualColumn * cellWidth + asciiOffset.width,
                                   asciiOffset.height);
    const int index = iTermASCIITextureIndexOfCode(code, offset);
    MTLOrigin origin = iTermTextureArrayOffsetForIndex(texture.textureArray, index);
    piu->textureOffset = (vector_float2){ origin.x * w, origin.y * h };
    piu->textColor = textColor;
    piu->underlineStyle = underlineStyle;
    piu->underlineColor = underlineColor;
    return piu;
}

static inline int iTermOuterPIUIndex(BOOL annotation, BOOL underlined, BOOL emoji) {
    const int underlineBit = (annotation || underlined) ? iTermPIUArrayIndexUnderlined : 0;
    const int emojiBit = emoji ? iTermPIUArrayIndexNotUnderlinedEmoji : 0;
    return underlineBit | emojiBit;
}

- (void)addASCIICellToPIUsForCode:(char)code
                     logicalIndex:(int)logicalIndex
                     visualColumn:(int)visualColumn
                           offset:(CGSize)asciiOffset
                                w:(float)w
                                h:(float)h
                        cellWidth:(float)cellWidth
                       asciiAttrs:(iTermASCIITextureAttributes)asciiAttrs
                       attributes:(const iTermMetalGlyphAttributes *)attributes
                    inMarkedRange:(BOOL)inMarkedRange {
    // When profiling, objc_retain and objc_release took 20% of the time in this function, which
    // is called super frequently. It should be safe not to retain the texture because the texture
    // group retains it. Once a texture is set in the group it won't be removed or replaced.
    __unsafe_unretained iTermASCIITexture *texture = _asciiTextureGroup->_textures[asciiAttrs];
    if (!texture) {
        texture = [_asciiTextureGroup asciiTextureForAttributes:asciiAttrs];
    }

    vector_float4 underlineColor = { 0, 0, 0, 0 };

    const BOOL suppressUnderlines = self.suppressUnderlines || _suppressUnderlineForDHL;
    const BOOL hasAnnotation = suppressUnderlines ? NO : attributes[visualColumn].annotation;
    const BOOL hasUnderline = suppressUnderlines ? NO : (attributes[visualColumn].underlineStyle != iTermMetalGlyphAttributesUnderlineNone);
    const int outerPIUIndex = iTermOuterPIUIndex(hasAnnotation, hasUnderline, NO);
    if (hasAnnotation) {
        underlineColor = iTermAnnotationUnderlineColor;
    } else if (hasUnderline) {
        if (attributes[visualColumn].hasUnderlineColor) {
            underlineColor = attributes[visualColumn].underlineColor;
        } else {
            underlineColor = _asciiUnderlineDescriptor.color.w > 0 ? _asciiUnderlineDescriptor.color : attributes[visualColumn].foregroundColor;
        }
    }

    iTermMetalGlyphAttributesUnderline underlineStyle = suppressUnderlines ? iTermMetalGlyphAttributesUnderlineNone : attributes[visualColumn].underlineStyle;
    vector_float4 textColor = attributes[visualColumn].foregroundColor;
    if (!suppressUnderlines && inMarkedRange) {
        // Marked range gets a yellow underline.
        underlineStyle = iTermMetalGlyphAttributesUnderlineSingle;
    }

    iTermTextRendererTransientStateAddASCIIPart(iTermTextPIUArrayGetNext(&_asciiPIUArrays[outerPIUIndex][asciiAttrs]),
                                                code,
                                                w,
                                                h,
                                                texture,
                                                cellWidth,
                                                visualColumn,
                                                asciiOffset,
                                                iTermASCIITextureOffsetCenter,
                                                textColor,
                                                underlineStyle,
                                                underlineColor);
}

static inline BOOL GlyphKeyCanTakeASCIIFastPath(const iTermMetalGlyphKey *glyphKey) {
    return (glyphKey->type == iTermMetalGlyphTypeRegular &&
            glyphKey->payload.regular.code <= iTermASCIITextureMaximumCharacter &&
            glyphKey->payload.regular.code >= iTermASCIITextureMinimumCharacter &&
            !glyphKey->payload.regular.isComplex &&
            !glyphKey->payload.regular.boxDrawing &&
            !iTermLineAttributeIsDoubleWidth(glyphKey->lineAttribute));
}

typedef struct {
    const iTermMetalGlyphKey *glyphKeys;
    int i;
    float asciiXOffset;
    float asciiYOffset;
    float yOffset;
    vector_float2 reciprocalAsciiAtlasSize;
    CGSize cellSize;
    CGSize glyphSize;
    const iTermMetalGlyphAttributes *attributes;
    BOOL inMarkedRange;
    iTermMetalBufferPoolContext *context;
    NSDictionary<NSNumber *, iTermCharacterBitmap *> *(^creation)(int x, BOOL *emoji);
} iTermTextRendererGlyphState;

- (void)setGlyphKeysData:(iTermGlyphKeyData *)glyphKeysData
           glyphKeyCount:(NSUInteger)glyphKeyCount
                   count:(int)count
          attributesData:(iTermAttributesData *)attributesData
                     row:(int)row
  backgroundColorRLEData:(nonnull iTermData *)backgroundColorRLEData
       markedRangeOnLine:(NSRange)markedRangeOnLine
                 context:(iTermMetalBufferPoolContext *)context
                creation:(NSDictionary<NSNumber *, iTermCharacterBitmap *> *(NS_NOESCAPE ^)(int x, BOOL *emoji))creation {
    const iTermMetalGlyphKey *glyphKeys = (iTermMetalGlyphKey *)glyphKeysData.bytes;
    const iTermMetalGlyphAttributes *attributes = (iTermMetalGlyphAttributes *)attributesData.bytes;
    vector_float2 reciprocalAsciiAtlasSize = 1.0 / _asciiTextureGroup.atlasSize;
    CGSize glyphSize = self.cellConfiguration.glyphSize;
    const CGSize cellSize = self.cellConfiguration.cellSize;
    const float cellHeight = self.cellConfiguration.cellSize.height;
    // NOTE: This must match logic in -[iTermCharacterSource drawBoxAtOffset:iteration:]
    const float verticalShift = round((cellHeight - self.cellConfiguration.cellSizeWithoutSpacing.height) / (2 * self.configuration.scale)) * self.configuration.scale;
    const float yOffset = (self.cellConfiguration.gridSize.height - row - 1) * cellHeight + verticalShift;
    const float asciiYOffset = -self.asciiOffset.height;
    const float asciiXOffset = -self.asciiOffset.width;

    iTermTextRendererGlyphState state = {
        .glyphKeys = glyphKeys,
        .asciiXOffset = asciiXOffset,
        .asciiYOffset = asciiYOffset,
        .yOffset = yOffset,
        .reciprocalAsciiAtlasSize = reciprocalAsciiAtlasSize,
        .cellSize = cellSize,
        .glyphSize = glyphSize,
        .attributes = attributes,
        .context = context,
        .creation = creation
    };
    // Suppress underlines on DECDHL top-half lines (underlines belong
    // on the bottom half, below the text).
    _suppressUnderlineForDHL = (glyphKeyCount > 0 &&
                                glyphKeys[0].lineAttribute == iTermLineAttributeDoubleHeightTop);
    int previousLogicalIndex = -1;
    for (state.i = 0; state.i < (int)glyphKeyCount; state.i++) {
        const int logicalIndex = glyphKeys[state.i].logicalIndex;
        const int visualIndex = glyphKeys[state.i].visualColumn;
        state.inMarkedRange = NSLocationInRange(visualIndex, markedRangeOnLine);

        switch (glyphKeys[state.i].type) {
            case iTermMetalGlyphTypeRegular:
                if (!glyphKeys[state.i].payload.regular.drawable) {
                    break;
                }
                if (GlyphKeyCanTakeASCIIFastPath(&glyphKeys[state.i])) {
                    [self addASCII:&state];
                } else {
                    [self addNonASCII:&state allowUnderline:YES];
                }
                break;
            case iTermMetalGlyphTypeDecomposed:
                [self addNonASCII:&state allowUnderline:(logicalIndex != previousLogicalIndex)];
                break;
        }
        previousLogicalIndex = logicalIndex;
    }
}

// ASCII fast path
- (void)addASCII:(const iTermTextRendererGlyphState *)state {
    const iTermMetalGlyphKey theGlyphKey = state->glyphKeys[state->i];
    const int logicalIndex = theGlyphKey.logicalIndex;

    iTermASCIITextureAttributes asciiAttrs =
        iTermASCIITextureAttributesFromGlyphKeyTypeface(theGlyphKey.typeface,
                                                        theGlyphKey.thinStrokes);
    [self addASCIICellToPIUsForCode:theGlyphKey.payload.regular.code
                       logicalIndex:logicalIndex
                       visualColumn:theGlyphKey.visualColumn
                             offset:CGSizeMake(state->asciiXOffset,
                                               state->yOffset + state->asciiYOffset)
                                  w:state->reciprocalAsciiAtlasSize.x
                                  h:state->reciprocalAsciiAtlasSize.y
                          cellWidth:state->cellSize.width
                         asciiAttrs:asciiAttrs
                         attributes:state->attributes
                      inMarkedRange:state->inMarkedRange];
}

// Non-ASCII slower path
- (void)addNonASCII:(const iTermTextRendererGlyphState *)state
     allowUnderline:(BOOL)allowUnderline {
    const iTermMetalGlyphKey theGlyphKey = state->glyphKeys[state->i];
    const int visualIndex = theGlyphKey.visualColumn;

    const iTermGlyphKey glyphKey = iTermGlyphKeyMake(&theGlyphKey);
    const iTermGlyphEntryList *entries = [_texturePageCollection findEntriesForGlyphKey:glyphKey];
    if (!entries) {
        entries = [_texturePageCollection addEntriesForColumn:state->i
                                                     glyphKey:glyphKey
                                                      context:state->context
                                                      creator:state->creation];
        if (!entries || entries->count == 0) {
            return;
        }
    } else if (entries->count == 0) {
        return;
    }

    const iTermMetalGlyphAttributes *attributes = state->attributes;
    const BOOL suppressUnderlines = self.suppressUnderlines || _suppressUnderlineForDHL;
    const BOOL hasAnnotation = suppressUnderlines ? NO : attributes[visualIndex].annotation;
    const BOOL hasUnderline = suppressUnderlines ? NO : (attributes[visualIndex].underlineStyle != iTermMetalGlyphAttributesUnderlineNone);
    const iTermGlyphEntry *firstGlyphEntry = &entries->entries[0];
    const int outerPIUIndex = iTermOuterPIUIndex(hasAnnotation, hasUnderline, firstGlyphEntry->isEmoji);
    for (size_t idx = 0; idx < entries->count; idx++) {
        const iTermGlyphEntry *entry = &entries->entries[idx];
        iTermTextPIUArray *array = iTermPagePIUMapFind(&_pius[outerPIUIndex], entry->page);
        if (!array) {
            array = (iTermTextPIUArray *)malloc(sizeof(iTermTextPIUArray));
            iTermTextPIUArrayInit(array, (size_t)_numberOfCells);
            iTermPagePIUMapSet(&_pius[outerPIUIndex], entry->page, array);
            if (!_retainedPages) {
                _retainedPages = [NSMutableArray array];
            }
            if ([_retainedPages indexOfObjectIdenticalTo:entry->page] == NSNotFound) {
                [_retainedPages addObject:entry->page];
            }
        }
        iTermTextPIU *piu = iTermTextPIUArrayGetNext(array);
        const int part = entry->part;
        const int dx = iTermImagePartDX(part);
        const int dy = iTermImagePartDY(part);
        piu->offset = simd_make_float2(theGlyphKey.visualColumn * state->cellSize.width + dx * state->glyphSize.width,
                                       -dy * state->glyphSize.height + state->yOffset);
        MTLOrigin origin = entry->origin;
        vector_float2 reciprocal_atlas_size = entry->page->_reciprocalAtlasSize;
        piu->textureOffset = simd_make_float2(origin.x * reciprocal_atlas_size.x,
                                              origin.y * reciprocal_atlas_size.y);
        piu->textColor = attributes[visualIndex].foregroundColor;
        if (suppressUnderlines) {
            piu->underlineStyle = iTermMetalGlyphAttributesUnderlineNone;
            piu->underlineColor = simd_make_float4(0, 0, 0, 0);
        } else if (attributes[visualIndex].annotation) {
            piu->underlineStyle = iTermMetalGlyphAttributesUnderlineSingle;
            piu->underlineColor = iTermAnnotationUnderlineColor;
        } else if (state->inMarkedRange) {
            piu->underlineStyle = iTermMetalGlyphAttributesUnderlineSingle;
            piu->underlineColor = _nonAsciiUnderlineDescriptor.color.w > 0 ? _nonAsciiUnderlineDescriptor.color : piu->textColor;
        } else {
            piu->underlineStyle = attributes[visualIndex].underlineStyle;
            if (attributes[visualIndex].hasUnderlineColor) {
                piu->underlineColor = attributes[visualIndex].underlineColor;
            } else {
                piu->underlineColor = _nonAsciiUnderlineDescriptor.color.w > 0 ? _nonAsciiUnderlineDescriptor.color : piu->textColor;
            }
        }
        if (part != iTermTextureMapMiddleCharacterPart &&
            part != iTermTextureMapMiddleCharacterPart + 1) {
            // Only underline center part and its right neighbor of the character. There are weird artifacts otherwise,
            // such as floating underlines (for parts above and below) or doubly drawn
            // underlines.
            piu->underlineStyle = iTermMetalGlyphAttributesUnderlineNone;
        }
    }
}

- (void)computeUnderlineSpansFromAttributes:(const iTermMetalGlyphAttributes *)attributes
                                      count:(int)count
                                        row:(int)row
                          markedRangeOnLine:(NSRange)markedRangeOnLine
                                       line:(const screen_char_t *)line
                                 lineLength:(int)lineLength
                                 inverseLUT:(const int *)inverseLUT
                             inverseLUTLen:(int)inverseLUTLen
                              lineAttribute:(iTermLineAttribute)lineAttribute
                             underlineSpans:(NSMutableData *)underlineSpans
                         strikethroughSpans:(NSMutableData *)strikethroughSpans {
    BOOL inUnderlineSpan = NO;
    BOOL inStrikethroughSpan = NO;
    iTermMetalUnderlineSpan currentUnderline = {};
    iTermMetalUnderlineSpan currentStrikethrough = {};

    // On DECDHL top-half lines, underlines belong on the bottom half
    // (below the text). Suppress them here.
    const BOOL suppressUnderlineForDHL = (lineAttribute == iTermLineAttributeDoubleHeightTop);

    for (int col = 0; col < count; col++) {
        iTermMetalGlyphAttributesUnderline rawStyle = attributes[col].underlineStyle;

        // IME marked range overrides underline style.
        if (NSLocationInRange(col, markedRangeOnLine)) {
            rawStyle = iTermMetalGlyphAttributesUnderlineSingle;
        }

        iTermMetalGlyphAttributesUnderline baseStyle =
            (iTermMetalGlyphAttributesUnderline)(rawStyle & iTermMetalGlyphAttributesUnderlineBitmask);
        const BOOL hasStrikethrough = (rawStyle & iTermMetalGlyphAttributesUnderlineStrikethroughFlag) != 0;

        if (suppressUnderlineForDHL) {
            baseStyle = iTermMetalGlyphAttributesUnderlineNone;
        }

        // Select the correct underline descriptor based on ASCII vs non-ASCII.
        const int logicalIndex = (inverseLUT && col < inverseLUTLen) ? inverseLUT[col] : col;
        const BOOL isASCII = (logicalIndex >= 0 && logicalIndex < lineLength &&
                              !line[logicalIndex].complexChar &&
                              !line[logicalIndex].image &&
                              line[logicalIndex].code < 128);

        // Resolve underline color (same priority as addASCIICellToPIUsForCode / addNonASCII).
        vector_float4 underlineColor = {};
        if (attributes[col].annotation) {
            underlineColor = iTermAnnotationUnderlineColor;
        } else if (attributes[col].hasUnderlineColor) {
            underlineColor = attributes[col].underlineColor;
        } else {
            const iTermMetalUnderlineDescriptor descriptor = isASCII
                ? _asciiUnderlineDescriptor
                : _nonAsciiUnderlineDescriptor;
            underlineColor = descriptor.color.w > 0
                ? descriptor.color
                : attributes[col].foregroundColor;
        }

        // Pack base style and ASCII flag into the style field.
        const int asciiFlag = isASCII ? iTermMetalUnderlineSpanASCIIFlag : 0;
        const int packedStyle = baseStyle | asciiFlag;

        // Handle underline spans. Break on style, color, or ASCII status change.
        if (baseStyle != iTermMetalGlyphAttributesUnderlineNone) {
            if (inUnderlineSpan &&
                currentUnderline.style == packedStyle &&
                simd_equal(currentUnderline.color, underlineColor)) {
                currentUnderline.endColumn = col;
            } else {
                if (inUnderlineSpan) {
                    [underlineSpans appendBytes:&currentUnderline length:sizeof(currentUnderline)];
                }
                currentUnderline = (iTermMetalUnderlineSpan){
                    .row = row,
                    .startColumn = col,
                    .endColumn = col,
                    .style = packedStyle,
                    .color = underlineColor,
                    .lineAttribute = lineAttribute,
                };
                inUnderlineSpan = YES;
            }
        } else {
            if (inUnderlineSpan) {
                [underlineSpans appendBytes:&currentUnderline length:sizeof(currentUnderline)];
                inUnderlineSpan = NO;
            }
        }

        // Handle strikethrough spans. Break on color or ASCII status change.
        const int packedStrikethroughStyle = iTermMetalGlyphAttributesUnderlineStrikethrough | asciiFlag;
        if (hasStrikethrough) {
            if (inStrikethroughSpan &&
                currentStrikethrough.style == packedStrikethroughStyle &&
                simd_equal(currentStrikethrough.color, underlineColor)) {
                currentStrikethrough.endColumn = col;
            } else {
                if (inStrikethroughSpan) {
                    [strikethroughSpans appendBytes:&currentStrikethrough length:sizeof(currentStrikethrough)];
                }
                currentStrikethrough = (iTermMetalUnderlineSpan){
                    .row = row,
                    .startColumn = col,
                    .endColumn = col,
                    .style = packedStrikethroughStyle,
                    .color = underlineColor,
                    .lineAttribute = lineAttribute,
                };
                inStrikethroughSpan = YES;
            }
        } else {
            if (inStrikethroughSpan) {
                [strikethroughSpans appendBytes:&currentStrikethrough length:sizeof(currentStrikethrough)];
                inStrikethroughSpan = NO;
            }
        }
    }

    if (inUnderlineSpan) {
        [underlineSpans appendBytes:&currentUnderline length:sizeof(currentUnderline)];
    }
    if (inStrikethroughSpan) {
        [strikethroughSpans appendBytes:&currentStrikethrough length:sizeof(currentStrikethrough)];
    }
}

- (void)didComplete {
    DLog(@"BEGIN didComplete for %@", self);
    [_texturePageCollection pruneIfNeeded];
    DLog(@"END didComplete");
}

- (void)expireNonASCIIGlyphs {
    [_texturePageCollection removeAll];
}

@end
