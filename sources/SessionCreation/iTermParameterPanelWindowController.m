//
//  iTermParameterPanelWindowController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/3/18.
//

#import "iTermParameterPanelWindowController.h"

@interface iTermParameterPanelWindowController ()

@end

@implementation iTermParameterPanelWindowController

- (instancetype)init {
    return [self initWithWindow:nil];
}

- (instancetype)initWithWindowNibName:(NSNibName)windowNibName {
    return [self initWithWindow:nil];
}

- (NSNibName)windowNibName {
    return @"iTermParameterPanelWindowController";
}

- (void)loadWindow {
    NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 347, 116)
                                                styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    panel.title = @"Session Parameter";
    panel.releasedWhenClosed = NO;
    panel.minSize = NSMakeSize(213, 107);

    NSView *contentView = panel.contentView;

    NSTextField *promptField = [NSTextField labelWithString:@"Enter the value for "];
    promptField.font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
    promptField.alignment = NSTextAlignmentLeft;
    promptField.frame = NSMakeRect(18, 79, 118, 17);
    [contentView addSubview:promptField];
    self.parameterPrompt = promptField;

    NSTextField *nameField = [NSTextField labelWithString:@"Name"];
    nameField.font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
    nameField.lineBreakMode = NSLineBreakByTruncatingTail;
    nameField.frame = NSMakeRect(133, 79, 196, 17);
    [contentView addSubview:nameField];
    self.parameterName = nameField;

    NSTextField *valueField = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 49, 307, 22)];
    valueField.editable = YES;
    valueField.selectable = YES;
    valueField.bezeled = YES;
    valueField.bezelStyle = NSTextFieldSquareBezel;
    valueField.drawsBackground = YES;
    valueField.font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
    valueField.focusRingType = NSFocusRingTypeNone;
    valueField.lineBreakMode = NSLineBreakByClipping;
    valueField.cell.scrollable = YES;
    [contentView addSubview:valueField];
    self.parameterValue = valueField;

    NSButton *cancelButton = [NSButton buttonWithTitle:@"Cancel"
                                                target:self
                                                action:@selector(parameterPanelEnd:)];
    cancelButton.tag = 0;
    cancelButton.keyEquivalent = @"\033";
    cancelButton.frame = NSMakeRect(149, 13, 83, 32);
    [contentView addSubview:cancelButton];

    NSButton *okButton = [NSButton buttonWithTitle:@"OK"
                                            target:self
                                            action:@selector(parameterPanelEnd:)];
    okButton.tag = 1;
    okButton.keyEquivalent = @"\r";
    okButton.frame = NSMakeRect(244, 13, 83, 32);
    [contentView addSubview:okButton];

    panel.initialFirstResponder = valueField;
    self.window = panel;
}

// Called when the parameter panel should close.
- (IBAction)parameterPanelEnd:(id)sender {
    _canceled = ([sender tag] == 0);
    [NSApp stopModal];
}

@end
