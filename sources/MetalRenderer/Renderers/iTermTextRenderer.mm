#import "iTermTextRenderer.h"

extern "C" {
#import "DebugLogging.h"
#import "iTermPreciseTimer.h"
}

#import "iTermMetalCellRenderer.h"

#import "GlyphKey.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermASCIITexture.h"
#import "iTermCharacterParts.h"
#import "iTermGlyphEntry.h"
#import "iTermMetalBufferPool.h"
#import "iTermMetalDebugInfo.h"
#import "iTermPIUArray.h"
#import "iTermTexture.h"
#import "iTermTexturePageCollection.h"
#import "iTermTextRendererTransientState.h"
#import "iTermTextRendererTransientState+Private.h"
#import "iTermTextureArray.h"
#import "iTermTexturePage.h"
#import "iTermTexturePageCollection.h"
#import "NSArray+iTerm.h"
#import "NSMutableData+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSObject+iTerm.h"
#import <map>
#import <set>
#import <unordered_map>
#import <vector>

static const NSInteger iTermTextAtlasCapacity = 16;

// This seems like a good number 🤷. It lets you draw this many * iTermTextAtlasCapacity distinct
// non-ascii characters at one time without having to constantly prune and redraw glyphs. That's
// 64k chars under the current values of 16 and 4096.
static const int iTermTextRendererMaximumNumberOfTexturePages = 4096;

@interface iTermTextRendererCachedQuad : NSObject
@property (nonatomic, strong) id<MTLBuffer> quad;
@property (nonatomic) CGSize textureSize;
@property (nonatomic) CGSize cellSize;
@end

@implementation iTermTextRendererCachedQuad

- (BOOL)isEqual:(id)object {
    iTermTextRendererCachedQuad *other = [iTermTextRendererCachedQuad castFrom:object];
    if (!other) {
        return NO;
    }

    return (CGSizeEqualToSize(_textureSize, other->_textureSize) &&
            CGSizeEqualToSize(_cellSize, other->_cellSize));
}

@end

@interface iTermTextRenderer() <iTermMetalDebugInfoFormatter>
@end

@implementation iTermTextRenderer {
    iTermMetalCellRenderer *_cellRenderer;
    iTermASCIITextureGroup *_asciiTextureGroup;

    iTermTexturePageCollectionSharedPointer *_texturePageCollectionSharedPointer;
    NSMutableArray<iTermTextRendererCachedQuad *> *_quadCache;
    CGSize _cellSizeForQuadCache;

    iTermMetalBufferPool *_emptyBuffers;
    iTermMetalBufferPool *_verticesPool;
    iTermMetalBufferPool *_dimensionsPool;
    iTermMetalBufferPool *_textInfoPool;
    iTermMetalMixedSizeBufferPool *_piuPool;
}

- (iTermMetalFrameDataStat)createTransientStateStat {
    return iTermMetalFrameDataStatPqCreateTextTS;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device {
    self = [super init];
    if (self) {
        // NOTE: The vertex and fragment function names get changed later. These aren't used but must be valid.
        iTermMetalBlending *blending = [iTermMetalBlending premultipliedCompositing];
        _cellRenderer = [[iTermMetalCellRenderer alloc] initWithDevice:device
                                                    vertexFunctionName:@"iTermTextVertexShader"
                                                  fragmentFunctionName:@"iTermTextFragmentShaderMonochromeEmoji"
                                                              blending:blending
                                                        piuElementSize:sizeof(iTermTextPIU)
                                                   transientStateClass:[iTermTextRendererTransientState class]];
        _cellRenderer.formatterDelegate = self;

        _quadCache = [NSMutableArray array];
        _emptyBuffers = [[iTermMetalBufferPool alloc] initWithDevice:device bufferSize:1];
        _verticesPool = [[iTermMetalBufferPool alloc] initWithDevice:device bufferSize:sizeof(iTermVertex) * 6];
        _dimensionsPool = [[iTermMetalBufferPool alloc] initWithDevice:device bufferSize:sizeof(iTermTextureDimensions)];
        _textInfoPool = [[iTermMetalBufferPool alloc] initWithDevice:device bufferSize:sizeof(iTermVertexTextInfoStruct)];

        // Allow the pool to reserve up to this many bytes. Work backward to find the largest number
        // of buffers we are OK with keeping permanently allocated. By having enough characters on
        // screen you could easily go over this, which will cost a major performance penalty because
        // vertex buffers are slow to create.
        const NSInteger memoryBudget = 1024 * 1024 * 100;
        const NSInteger maxInstances = memoryBudget / sizeof(iTermTextPIU);
        const size_t capacity = iTerm2::PIUArray<iTermTextPIU>::DEFAULT_CAPACITY;
        _piuPool = [[iTermMetalMixedSizeBufferPool alloc] initWithDevice:device
                                                                capacity:(maxInstances / capacity) * iTermMetalDriverMaximumNumberOfFramesInFlight
                                                                    name:@"text PIU"];
    }
    return self;
}

- (BOOL)rendererDisabled {
    return NO;
}

- (nullable __kindof iTermMetalRendererTransientState *)createTransientStateForCellConfiguration:(iTermCellRenderConfiguration *)configuration
                                                                                   commandBuffer:(id<MTLCommandBuffer>)commandBuffer {
    if (!CGSizeEqualToSize(configuration.cellSize, _cellSizeForQuadCache)) {
        // All quads depend on cell size. No point keeping usesless entries in the cache.
        [_quadCache removeAllObjects];
        _cellSizeForQuadCache = configuration.cellSize;
    }
    // NOTE: Any time a glyph overflows its bounds into a neighboring cell it's possible the strokes will intersect.
    // I haven't thought of a way to make that look good yet without having to do one draw pass per overflow glyph that
    // blends using the output of the preceding passes.
    __kindof iTermMetalCellRendererTransientState * _Nonnull transientState =
        [_cellRenderer createTransientStateForCellConfiguration:configuration
                                              commandBuffer:commandBuffer];
    [self initializeTransientState:transientState
                     commandBuffer:commandBuffer];
    return transientState;

}

- (void)initializeTransientState:(iTermTextRendererTransientState *)tState
                   commandBuffer:(id<MTLCommandBuffer>)commandBuffer {
    const CGSize currentSize = tState.cellConfiguration.glyphSize;
    if (_texturePageCollectionSharedPointer != NULL) {
        const vector_uint2 &oldSize = _texturePageCollectionSharedPointer.object->get_cell_size();
        if (oldSize.x != currentSize.width || oldSize.y != currentSize.height) {
            _texturePageCollectionSharedPointer = nil;
        }
    }
    if (!_texturePageCollectionSharedPointer) {
        iTerm2::TexturePageCollection *collection = new iTerm2::TexturePageCollection(_cellRenderer.device,
                                                                                      simd_make_uint2(currentSize.width, currentSize.height),
                                                                                      iTermTextAtlasCapacity,
                                                                                      iTermTextRendererMaximumNumberOfTexturePages);
        _texturePageCollectionSharedPointer = [[iTermTexturePageCollectionSharedPointer alloc] initWithObject:collection];
    }

    tState.device = _cellRenderer.device;
    tState.asciiTextureGroup = _asciiTextureGroup;
    tState.texturePageCollectionSharedPointer = _texturePageCollectionSharedPointer;
    tState.numberOfCells = tState.cellConfiguration.gridSize.width * tState.cellConfiguration.gridSize.height;
    tState.asciiOffset = _asciiOffset;
    tState.verticalOffset = _verticalOffset;
}

- (id<MTLBuffer>)quadOfSize:(CGSize)size
                textureSize:(CGSize)textureSize
                poolContext:(iTermMetalBufferPoolContext *)poolContext {
    iTermTextRendererCachedQuad *entry = [[iTermTextRendererCachedQuad alloc] init];
    entry.cellSize = size;
    entry.textureSize = textureSize;
    NSInteger index = [_quadCache indexOfObject:entry];
    if (index != NSNotFound) {
        id<MTLBuffer> quad = _quadCache[index].quad;
        return quad;
    }

    const float vw = static_cast<float>(size.width);
    const float vh = static_cast<float>(size.height);

    const float w = size.width / textureSize.width;
    const float h = size.height / textureSize.height;

    const iTermVertex vertices[] = {
        // Pixel Positions, Texture Coordinates
        { { vw,  0 + _verticalOffset }, { w, 0 } },
        { { 0,   0 + _verticalOffset }, { 0, 0 } },
        { { 0,  vh + _verticalOffset }, { 0, h } },

        { { vw,  0 + _verticalOffset }, { w, 0 } },
        { { 0,  vh + _verticalOffset }, { 0, h } },
        { { vw, vh + _verticalOffset }, { w, h } },
    };
    entry.quad = [_verticesPool requestBufferFromContext:poolContext
                                               withBytes:vertices
                                          checkIfChanged:YES];
    entry.quad.label = @"Text Quad";
    // I cache quads myself, so I don't want them returned to the pool where they could change
    // out from under my cache.
    [poolContext relinquishOwnershipOfBuffer:entry.quad];
    [_quadCache addObject:entry];
    // It's useful to hold a quad for ascii and one for non-ascii.
    if (_quadCache.count > 2) {
        [_quadCache removeObjectAtIndex:0];
    }

    return entry.quad;
}

- (id<MTLBuffer>)piuBufferForPIUs:(const iTermTextPIU *)pius
                           tState:(__kindof iTermTextRendererTransientState *)tState
                        instances:(NSInteger)instances {
    id<MTLBuffer> piuBuffer;
    piuBuffer = [_piuPool requestBufferFromContext:tState.poolContext
                                              size:sizeof(iTermTextPIU) * instances
                                             bytes:pius];
    piuBuffer.label = @"Text PIUs";
    ITDebugAssert(piuBuffer);
    return piuBuffer;
}

static NSString *const FragmentFunctionName(const BOOL &underlined,
                                            const BOOL &emoji) {
    static NSArray<NSString *> *names = @[
        @"iTermTextFragmentShaderMonochrome",                  // regular text
        @"iTermTextFragmentShaderMonochromeEmoji",             // emoji
        @"iTermTextFragmentShaderMonochromeUnderlined",        // underlined regular text
        @"iTermTextFragmentShaderMonochromeUnderlinedEmoji" ]; // underlined emoji
    const int index = (underlined ? 2 : 0) | (emoji ? 1 : 0);
    return names[index];
}

static NSString *const VertexFunctionName(const BOOL &underlined,
                                          const BOOL &emoji) {
    static NSArray<NSString *> *names = @[
        @"iTermTextVertexShaderMonochrome",  // regular text
        @"iTermTextVertexShaderEmoji",       // emoji
        @"iTermTextVertexShader",            // underlined regular text
        @"iTermTextVertexShader" ];          // underlined emoji
    const int index = (underlined ? 2 : 0) | (emoji ? 1 : 0);
    return names[index];
}

- (id<MTLBuffer>)textInfoBufferForTransientState:(iTermTextRendererTransientState *)tState
                                    numInstances:(unsigned int)numInstances {
    iTermVertexTextInfoStruct textInfo;
    memset(&textInfo, 0, sizeof(textInfo));
    if ([iTermAdvancedSettingsModel solidUnderlines]) {
        textInfo.flags |= iTermTextVertexInfoFlagsSolidUnderlines;
    }
    textInfo.glyphWidth = tState.cellConfiguration.glyphSize.width;
    textInfo.cellWidth = tState.cellConfiguration.cellSize.width;
    textInfo.numInstances = numInstances;
    textInfo.verticalOffset = tState.verticalOffset;
    id<MTLBuffer> buffer = [self->_textInfoPool requestBufferFromContext:tState.poolContext
                                                               withBytes:&textInfo
                                                          checkIfChanged:YES];
    buffer.label = @"Text info";
    return buffer;
}

- (void)drawWithFrameData:(iTermMetalFrameData *)frameData
           transientState:(__kindof iTermMetalCellRendererTransientState *)transientState {
    iTermTextRendererTransientState *tState = transientState;
    tState.vertexBuffer.label = @"Text vertex buffer";
    tState.offsetBuffer.label = @"Offset";
    const float scale = tState.cellConfiguration.scale;
    const simd_float2 cellSize = simd_make_float2(frameData.cellConfiguration.cellSize.width,
                                                  frameData.cellConfiguration.cellSize.height);

    // The vertex buffer's texture coordinates depend on the texture map's atlas size so it must
    // be initialized after the texture map.
    __block iTermTextureDimensions previousTextureDimensions;
    __block id<MTLBuffer> previousTextureDimensionsBuffer = nil;

    [tState enumerateDraws:^(const iTermTextPIU *pius,
                             NSInteger instances,
                             id<MTLTexture> texture,
                             vector_uint2 textureSize,
                             vector_uint2 glyphSize,
                             iTermMetalUnderlineDescriptor underlineDescriptor,
                             iTermMetalUnderlineDescriptor strikethroughDescriptor,
                             BOOL underlined,
                             BOOL emoji) {
        __block id<MTLBuffer> vertexBuffer;
        [tState measureTimeForStat:iTermTextRendererStatNewQuad ofBlock:^{
            vertexBuffer = [self quadOfSize:CGSizeMake(glyphSize.x, glyphSize.y)
                                textureSize:CGSizeMake(textureSize.x, textureSize.y)
                                poolContext:tState.poolContext];
        }];

        __block id<MTLBuffer> textInfoBuffer;
        [tState measureTimeForStat:iTermTextRendererStatNewTextInfo ofBlock:^{
            textInfoBuffer = [self textInfoBufferForTransientState:tState
                                                      numInstances:instances];
        }];
        __block id<MTLBuffer> piuBuffer;
        [tState measureTimeForStat:iTermTextRendererStatNewPIU ofBlock:^{
            piuBuffer = [self piuBufferForPIUs:pius tState:tState instances:instances];
        }];

        NSDictionary *textures = @{ @(iTermTextureIndexPrimary): texture };

        __block id<MTLBuffer> textureDimensionsBuffer;
        const float underlineThickness = underlineDescriptor.thickness * scale;
        const float strikethroughThickness = strikethroughDescriptor.thickness * scale;
        [tState measureTimeForStat:iTermTextRendererStatNewDims ofBlock:^{
            iTermTextureDimensions textureDimensions = {
                .textureSize = simd_make_float2(textureSize.x, textureSize.y),
                .glyphSize = simd_make_float2(glyphSize.x, glyphSize.y),
                .cellSize = cellSize,
                .underlineOffset = simd_make_float2(tState.asciiOffset.width,
                                                    MAX(underlineThickness, cellSize.y - (underlineDescriptor.offset * scale))),
                .underlineThickness = underlineThickness,
                .strikethroughOffset = simd_make_float2(tState.asciiOffset.width,
                                                        cellSize.y - strikethroughDescriptor.offset * scale),
                .strikethroughThickness = strikethroughThickness,
                .scale = scale,
            };

            // These tend to get reused so avoid changing the buffer if it is the same as the last one.
            if (previousTextureDimensionsBuffer != nil &&
                !memcmp(&textureDimensions, &previousTextureDimensions, sizeof(textureDimensions))) {
                textureDimensionsBuffer = previousTextureDimensionsBuffer;
            } else {
                textureDimensionsBuffer = [self->_dimensionsPool requestBufferFromContext:tState.poolContext
                                                                               withBytes:&textureDimensions
                                                                           checkIfChanged:YES];
                textureDimensionsBuffer.label = @"Texture dimensions";
                previousTextureDimensionsBuffer = textureDimensionsBuffer;
                std::memcpy((void *)&previousTextureDimensions,
                            (void *)&textureDimensions,
                            sizeof(textureDimensions));
            }
        }];

        [tState measureTimeForStat:iTermTextRendererStatDraw ofBlock:^{
            // Change the pipeline state just before drawing so we get the right underlined/not underlined state.
            self->_cellRenderer.fragmentFunctionName = FragmentFunctionName(underlined, emoji);
            self->_cellRenderer.vertexFunctionName = VertexFunctionName(underlined, emoji);
            tState.pipelineState = [self->_cellRenderer pipelineState];
            NSDictionary *fragmentBuffers;
            fragmentBuffers = @{ @(iTermFragmentInputIndexTextureDimensions): textureDimensionsBuffer };
            [self->_cellRenderer drawWithTransientState:tState
                                          renderEncoder:frameData.renderEncoder
                                       numberOfVertices:6
                                           numberOfPIUs:instances
                                          vertexBuffers:@{ @(iTermVertexInputIndexVertices): vertexBuffer,
                                                           @(iTermVertexTextInfo): textInfoBuffer,
                                                           @(iTermVertexInputIndexPerInstanceUniforms): piuBuffer,
                                                           @(iTermVertexInputIndexOffset): tState.offsetBuffer }
                                        fragmentBuffers:fragmentBuffers
                                               textures:textures];
        }];
    }];
}

- (void)setASCIICellSize:(CGSize)cellSize
                  offset:(CGSize)asciiOffset
              descriptor:(iTermCharacterSourceDescriptor *)descriptor
      creationIdentifier:(id)creationIdentifier
                creation:(NSDictionary<NSNumber *, iTermCharacterBitmap *> *(^)(char, iTermASCIITextureAttributes))creation {
    iTermASCIITextureGroup *replacement = [[iTermASCIITextureGroup alloc] initWithDevice:_cellRenderer.device
                                                                      creationIdentifier:(id)creationIdentifier
                                                                              descriptor:descriptor
                                                                                creation:creation];
    if (![replacement isEqual:_asciiTextureGroup]) {
        _asciiTextureGroup = replacement;
    }
    _asciiOffset = asciiOffset;
}

- (void)writeDebugInfoToFolder:(NSURL *)folder {
}

#pragma mark - iTermMetalDebugInfoFormatter

- (void)writeVertexBuffer:(id<MTLBuffer>)buffer index:(NSUInteger)index toFolder:(NSURL *)folder {
    if (index == iTermVertexInputIndexPerInstanceUniforms) {
        NSMutableString *s = [NSMutableString string];
        const iTermTextPIU *pius = (const iTermTextPIU *)buffer.contents;
        for (int i = 0; i < buffer.length / sizeof(iTermTextPIU); i++) {
            [s appendString:[iTermTextRendererTransientState formatTextPIU:pius[i]]];
        }
        NSURL *url = [folder URLByAppendingPathComponent:@"vertexBuffer.iTermVertexInputIndexPerInstanceUniforms.txt"];
        [s writeToURL:url atomically:NO encoding:NSUTF8StringEncoding error:nil];
    }
}

@end

@implementation iTermOffscreenCommandLineTextRenderer
@end
