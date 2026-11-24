//
//  iTermMetalGlueDelegate.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/8/17.
//

#import <Cocoa/Cocoa.h>
#import "ITAddressBookMgr.h"

NS_ASSUME_NONNULL_BEGIN

@class iTermImageWrapper;

@protocol iTermMetalGlueDelegate<NSObject>
- (void)metalGlueDidDrawFrameAndNeedsRedraw:(BOOL)redrawAsap;
- (nullable CGContextRef)metalGlueContext CF_RETURNS_NOT_RETAINED;
- (nullable CGContextRef)metalGlueContextDoubleWidth CF_RETURNS_NOT_RETAINED;
- (nullable iTermImageWrapper *)metalGlueBackgroundImage;
- (iTermBackgroundImageMode)metalGlueBackgroundImageMode;
- (CGFloat)metalGlueBackgroundImageBlend;

@end

NS_ASSUME_NONNULL_END
