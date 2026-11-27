//
//  iTermStatusBarKnobNumericViewController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/30/18.
//

#import "iTermStatusBarKnobNumericViewController.h"

#import "DebugLogging.h"
#import "NSObject+iTerm.h"
#import "NSStringITerm.h"

@interface iTermStatusBarKnobNumericViewController ()<NSTextFieldDelegate, NSControlTextEditingDelegate>

@end

@implementation iTermStatusBarKnobNumericViewController

- (void)loadView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 286, 27)];
    view.autoresizesSubviews = NO;

    NSTextField *label = [NSTextField labelWithString:@""];
    label.frame = NSMakeRect(0, 6, 163, 17);
    label.alignment = NSTextAlignmentRight;
    label.lineBreakMode = NSLineBreakByClipping;
    [view addSubview:label];

    NSTextField *textField = [[NSTextField alloc] initWithFrame:NSMakeRect(169, 3, 96, 22)];
    textField.bezeled = YES;
    textField.bezelStyle = NSTextFieldSquareBezel;
    textField.editable = YES;
    textField.selectable = YES;
    textField.drawsBackground = YES;
    textField.cell.scrollable = YES;
    textField.cell.wraps = NO;
    textField.target = self;
    textField.action = @selector(stepperAction:);
    textField.delegate = self;
    [view addSubview:textField];

    NSStepper *stepper = [[NSStepper alloc] initWithFrame:NSMakeRect(270, 0, 19, 27)];
    stepper.continuous = YES;
    stepper.maxValue = 100;
    stepper.target = self;
    stepper.action = @selector(stepperAction:);
    [view addSubview:stepper];

    _label = label;
    _textField = textField;
    _stepper = stepper;
    self.view = view;
}

- (void)viewDidLoad {
    self.view.autoresizesSubviews = NO;
    self.value = _value;
    _stepper.maxValue = INFINITY;
    _stepper.minValue = -INFINITY;
}

- (void)setValue:(NSNumber *)value {
    _value = value;
    _stepper.doubleValue = _value.doubleValue;
    if (_value.doubleValue == INFINITY) {
        _textField.stringValue = @"∞";
    } else if (_value.doubleValue == -INFINITY) {
        _textField.stringValue = @"-∞";
    } else {
        _textField.doubleValue = _value.doubleValue;
    }
}

- (IBAction)stepperAction:(id)sender {
    self.value = @([(NSControl *)sender doubleValue]);
}

- (void)controlTextDidChange:(NSNotification *)obj {
    NSString *string = [(NSControl *)obj.object stringValue];
    NSNumber *safeValue = @(string.it_localizedDoubleValue);
    _value = safeValue;
    _stepper.doubleValue = safeValue.doubleValue;
}

- (void)controlTextDidEndEditing:(NSNotification *)obj {
    NSControl *control = obj.object;
    control.doubleValue = _value.doubleValue;
}

- (void)setDescription:(NSString *)description placeholder:(nonnull NSString *)placeholder {
    _label.stringValue = description;
    [self sizeToFit];
}

- (void)sizeToFit {
    const CGFloat marginBetweenLabelAndField = NSMinX(_textField.frame) - NSMaxX(_label.frame);
    const CGFloat marginBetweenTextFieldAndStepper = NSMinX(_stepper.frame) - NSMaxX(_textField.frame);

    [_label sizeToFit];
    NSRect rect = _label.frame;
    _label.frame = rect;

    rect = _textField.frame;
    rect.origin.x = NSMaxX(_label.frame) + marginBetweenLabelAndField;
    _textField.frame = rect;

    rect = _stepper.frame;
    rect.origin.x = NSMaxX(_textField.frame) + marginBetweenTextFieldAndStepper;
    _stepper.frame = rect;

    rect = self.view.frame;
    rect.size.width = NSMaxX(_stepper.frame);
    self.view.frame = rect;
}

- (CGFloat)controlOffset {
    return NSMinX(_textField.frame);
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)fieldEditor doCommandBySelector:(SEL)commandSelector {
    if ([self respondsToSelector:commandSelector]) {
        [self it_performNonObjectReturningSelector:commandSelector withObject:control];
        return YES;
    } else {
        return NO;
    }
}

- (void)insertNewline:(id)sender {
    [self.view.window.sheetParent endSheet:self.view.window returnCode:NSModalResponseOK];
}

- (void)setHelpURL:(NSURL *)url {
    ITAssertWithMessage(NO, @"Not supported");
}

@end

