//
//  iTermStatusBarKnobCheckboxViewController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/30/18.
//

#import "iTermStatusBarKnobCheckboxViewController.h"

#import "DebugLogging.h"

@interface iTermStatusBarKnobCheckboxViewController ()

@end

@implementation iTermStatusBarKnobCheckboxViewController

- (void)loadView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 222, 14)];
    view.autoresizesSubviews = NO;

    NSButton *checkbox = [NSButton checkboxWithTitle:@"" target:nil action:nil];
    checkbox.frame = NSMakeRect(-2, -2, 226, 18);
    checkbox.state = NSControlStateValueOn;
    [view addSubview:checkbox];

    _checkbox = checkbox;
    self.view = view;
}

- (NSNumber *)value {
    self.view.autoresizesSubviews = NO;
    return @(_checkbox.state == NSControlStateValueOn);
}

- (void)setDescription:(NSString *)description placeholder:(nonnull NSString *)placeholder {
    _checkbox.title = description;
    [self sizeToFit];
    self.view.frame = _checkbox.frame;
}

- (CGFloat)controlOffset {
    return 0;
}

- (void)setValue:(id)value {
    _checkbox.state = [value boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)sizeToFit {
    [_checkbox sizeToFit];
}


- (void)encodeWithCoder:(nonnull NSCoder *)aCoder {
    [aCoder encodeObject:self.value forKey:@"value"];
}

- (void)setHelpURL:(NSURL *)url {
    ITAssertWithMessage(NO, @"Not supported");
}

@end
