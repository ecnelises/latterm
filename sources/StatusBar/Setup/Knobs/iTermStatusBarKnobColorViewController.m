//
//  iTermStatusBarKnobColorViewController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/5/18.
//

#import "iTermStatusBarKnobColorViewController.h"

#import "DebugLogging.h"
#import "NSColor+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSObject+iTerm.h"

@interface iTermStatusBarKnobColorViewController ()

@end

@implementation iTermStatusBarKnobColorViewController {
    CPKColorWell *_well;
    NSDictionary *_value;
}

- (void)loadView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 113, 21)];
    view.autoresizesSubviews = NO;

    NSTextField *label = [NSTextField labelWithString:@""];
    label.frame = NSMakeRect(-2, 2, 77, 17);
    label.lineBreakMode = NSLineBreakByClipping;
    [view addSubview:label];

    CPKColorWell *well = [[CPKColorWell alloc] initWithFrame:NSMakeRect(81, 0, 32, 21)
                                                  colorSpace:[NSColorSpace it_defaultColorSpace]];
    [view addSubview:well];

    _label = label;
    _well = well;
    self.view = view;
}

- (void)viewDidLoad {
    _well.colorSpace = [NSColorSpace it_defaultColorSpace];
    _well.noColorAllowed = YES;
    self.view.autoresizesSubviews = NO;
    self.value = _value;
}

- (void)setValue:(NSDictionary *)value {
    _value = value;
    NSColor *color = [_value colorValue];
    _well.color = color;
}

- (NSDictionary *)value {
    return [_well.color dictionaryValue];
}

- (void)setDescription:(NSString *)description placeholder:(nonnull NSString *)placeholder {
    _label.stringValue = description;
    [self sizeToFit];
}

- (void)sizeToFit {
    const CGFloat marginBetweenLabelAndWell = NSMinX(_well.frame) - NSMaxX(_label.frame);
    
    [_label sizeToFit];
    NSRect rect = _label.frame;
    _label.frame = rect;
    
    rect = _well.frame;
    rect.origin.x = NSMaxX(_label.frame) + marginBetweenLabelAndWell;
    _well.frame = rect;

    rect = self.view.frame;
    rect.size.width = NSMaxX(_well.frame);
    self.view.frame = rect;
}

- (CGFloat)controlOffset {
    return NSMinX(_well.frame);
}

- (void)setHelpURL:(NSURL *)url {
    ITAssertWithMessage(NO, @"Not supported");
}

@end
