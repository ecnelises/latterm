//
//  iTermCopyBackgroundRenderer.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/4/17.
//

#import <Foundation/Foundation.h>
#import "iTermMetalRenderer.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermCopyRendererTransientState : iTermMetalRendererTransientState

// The texture to copy from.
@property (nonatomic, strong) id<MTLTexture> sourceTexture;

@end

// Copies from one texture to another.
@interface iTermCopyRenderer : NSObject<iTermMetalRenderer>

@property (nonatomic) BOOL enabled;

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

@interface iTermCopyOffscreenRendererTransientState : iTermCopyRendererTransientState
@end

@interface iTermCopyOffscreenRenderer : iTermCopyRenderer
@end

@interface iTermCopyToDrawableRendererTransientState : iTermCopyRendererTransientState
@end

@interface iTermCopyToDrawableRenderer : iTermCopyRenderer
@end

NS_ASSUME_NONNULL_END
