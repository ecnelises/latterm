//
//  iTermTextShaderCommon.h
//  iTerm2
//
//  Created by George Nachman on 7/2/18.
//

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

#import "iTermShaderTypes.h"

typedef struct {
    float4 clipSpacePosition [[position]];  // In vector function is normalized. In fragment function is in pixels, with a half pixel offset since it refers to the center of the pixel.
    float2 textureCoordinate;
    float2 backgroundTextureCoordinate;
    float4 textColor;
    float4 underlineColor;
    float2 textureOffset;  // Normalized offset in texture.
    float2 cellOffset;  // Coordinate of bottom left of cell in pixel coordinates. 0,0 is the bottom left of the screen.
    int underlineStyle;  // should draw an underline? For some stupid reason the compiler won't let me set the type as iTermMetalGlyphAttributesUnderline
    float2 viewportSize;  // size of viewport in pixels. TODO: see if I can avoid passing this to fragment function.
    float scale;  // 2 for retina, 1 for non-retina
    float4 alphaVector;
    int flags;  // copied from iTermVertexTextInfoStruct.flags
    bool predecessorWasUnderlined;
    bool successorWillBeUnderlined;
    float verticalOffset;  // Used by offscreen command line to shift text so it is not grid-aligned.
} iTermTextVertexFunctionOutput;

typedef struct {
    float4 clipSpacePosition [[position]];  // In vector function is normalized. In fragment function is in pixels, with a half pixel offset since it refers to the center of the pixel.
    float2 textureCoordinate;
} iTermTextVertexFunctionOutputEmoji;

typedef struct {
    float4 clipSpacePosition [[position]];  // In vector function is normalized. In fragment function is in pixels, with a half pixel offset since it refers to the center of the pixel.
    float2 textureCoordinate;
    float4 textColor;
    float4 alphaVector;
} iTermTextVertexFunctionOutputMonochrome;

// Returns the weight in [0, 1] of underline for a pixel at `clipSpacePosition`
// when drawing underlined emoji or monochrome text.
// This respects the alpha channel of the texture.
float ComputeWeightOfUnderlineRegular(int underlineStyle,  // iTermMetalGlyphAttributesUnderline
                                      float2 clipSpacePosition,
                                      float2 viewportSize,
                                      float2 cellOffset,
                                      float2 underlineOffset,
                                      float underlineThickness,
                                      float2 textureSize,
                                      float2 textureOffset,
                                      float2 textureCoordinate,
                                      float2 glyphSize,
                                      float2 cellSize,
                                      texture2d<float> texture,
                                      sampler textureSampler,
                                      float scale,
                                      bool solid,
                                      bool predecessorWasUnderlined,
                                      bool successorWillBeUnderlined);
