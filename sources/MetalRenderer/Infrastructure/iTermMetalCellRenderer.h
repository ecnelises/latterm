#import "iTermMetalRenderer.h"

#import "iTermMetalFrameData.h"
#import "VT100GridTypes.h"

NS_ASSUME_NONNULL_BEGIN

extern const CGFloat MARGIN_WIDTH;
extern const CGFloat TOP_MARGIN;
extern const CGFloat BOTTOM_MARGIN;

@class iTermMetalCellRendererTransientState;

@interface iTermCellRenderConfiguration : iTermRenderConfiguration
// This is the size of a cell on screen--the distance from the beginning of one character to the next.
@property (nonatomic, readonly) CGSize cellSize;
// The same, but without extra vertical/horizontal spacing.
@property (nonatomic, readonly) CGSize cellSizeWithoutSpacing;
// Maximum size of a glyph part. Large enough to contain all ASCII glyphs.
@property (nonatomic, readonly) CGSize glyphSize;
@property (nonatomic, readonly) VT100GridSize gridSize;

- (instancetype)initWithViewportSize:(vector_uint2)viewportSize
                legacyScrollbarWidth:(unsigned int)legacyScrollbarWidth
                               scale:(CGFloat)scale
                  hasBackgroundImage:(BOOL)hasBackgroundImage
                        extraMargins:(NSEdgeInsets)extraMargins
maximumExtendedDynamicRangeColorComponentValue:(CGFloat)maximumExtendedDynamicRangeColorComponentValue
                          colorSpace:(NSColorSpace *)colorSpace
                    rightExtraPixels:(CGFloat)rightExtraPixels
              panelReservationPixels:(CGFloat)panelReservationPixels NS_UNAVAILABLE;

- (instancetype)initWithViewportSize:(vector_uint2)viewportSize
                legacyScrollbarWidth:(unsigned int)legacyScrollbarWidth
                               scale:(CGFloat)scale
                  hasBackgroundImage:(BOOL)hasBackgroundImage
                        extraMargins:(NSEdgeInsets)extraMargins
maximumExtendedDynamicRangeColorComponentValue:(CGFloat)maximumExtendedDynamicRangeColorComponentValue
                          colorSpace:(NSColorSpace *)colorSpace
                    rightExtraPixels:(CGFloat)rightExtraPixels
              panelReservationPixels:(CGFloat)panelReservationPixels
                            cellSize:(CGSize)cellSize
                           glyphSize:(CGSize)glyphSize
              cellSizeWithoutSpacing:(CGSize)cellSizeWithoutSpacing
                            gridSize:(VT100GridSize)gridSize NS_DESIGNATED_INITIALIZER;

@end

@protocol iTermMetalCellRenderer<NSObject>
@property (nonatomic, readonly) BOOL rendererDisabled;

- (iTermMetalFrameDataStat)createTransientStateStat;
- (void)drawWithFrameData:(iTermMetalFrameData *)frameData
           transientState:(__kindof iTermMetalCellRendererTransientState *)transientState;

- (nullable __kindof iTermMetalRendererTransientState *)createTransientStateForCellConfiguration:(iTermCellRenderConfiguration *)configuration
                                                                                   commandBuffer:(id<MTLCommandBuffer>)commandBuffer;

@optional
- (void)writeDebugInfoToFolder:(NSURL *)folderURL;

@end

@interface iTermMetalCellRendererTransientState : iTermMetalRendererTransientState
@property (nonatomic, readonly) __kindof iTermCellRenderConfiguration *cellConfiguration;
@property (nonatomic, readonly) id<MTLBuffer> offsetBuffer;
@property (nonatomic, strong) id<MTLBuffer> pius;

// NOTE: margins.top affects the bottom margin because flipped.
@property (nonatomic, readonly) NSEdgeInsets margins;

- (instancetype)init NS_UNAVAILABLE;

- (void)setPIUValue:(void *)c coord:(VT100GridCoord)coord;
- (const void *)piuForCoord:(VT100GridCoord)coord;

@end

@interface iTermMetalCellRenderer : iTermMetalRenderer

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device NS_UNAVAILABLE;

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device
                     vertexFunctionName:(NSString *)vertexFunctionName
                   fragmentFunctionName:(NSString *)fragmentFunctionName
                               blending:(nullable iTermMetalBlending *)blending
                    transientStateClass:(Class)transientStateClass NS_UNAVAILABLE;

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device
                     vertexFunctionName:(NSString *)vertexFunctionName
                   fragmentFunctionName:(NSString *)fragmentFunctionName
                               blending:(nullable iTermMetalBlending *)blending
                         piuElementSize:(size_t)piuElementSize
                    transientStateClass:(Class)transientStateClass NS_DESIGNATED_INITIALIZER;

- (nullable __kindof iTermMetalRendererTransientState *)createTransientStateForCellConfiguration:(iTermCellRenderConfiguration *)configuration
                                                                                   commandBuffer:(id<MTLCommandBuffer>)commandBuffer;

@end

NS_ASSUME_NONNULL_END
