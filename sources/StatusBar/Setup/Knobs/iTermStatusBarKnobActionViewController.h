//
//  iTermStatusBarKnobActionViewController.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/22/19.
//

#import <Cocoa/Cocoa.h>
#import "iTermStatusBarComponentKnob.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermStatusBarKnobActionViewController : NSViewController<iTermStatusBarKnobViewController>

@property (nonatomic) NSDictionary *value;
- (instancetype)init NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)initWithNibName:(NSNibName _Nullable)nibNameOrNil
                         bundle:(NSBundle * _Nullable)nibBundleOrNil NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
