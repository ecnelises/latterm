//
//  iTermEditSnippetWindowController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/14/20.
//

#import "iTermEditSnippetWindowController.h"
#import "NSStringITerm.h"

// Return key equivalents are managed as default buttons by AppKit. Handle
// Command-Return on the panel so editing text cannot clear the save shortcut.
@interface iTermSnippetEditorPanel : NSPanel
@property(nonatomic, copy) void (^saveSnippet)(void);
@end

@implementation iTermSnippetEditorPanel
- (BOOL)performKeyEquivalent:(NSEvent *)event {
    const NSEventModifierFlags modifiers = event.modifierFlags &
        (NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption | NSEventModifierFlagShift);
    if (event.type == NSEventTypeKeyDown && modifiers == NSEventModifierFlagCommand &&
        (event.keyCode == 36 || event.keyCode == 76) && self.saveSnippet) {
        self.saveSnippet();
        return YES;
    }
    return [super performKeyEquivalent:event];
}
@end

@interface iTermEditSnippetWindowController ()<NSTokenFieldDelegate, NSWindowDelegate>

@end

@implementation iTermEditSnippetWindowController {
    NSTextField *_titleView;
    NSTextView *_valueView;
    NSPopUpButton *_escapingButton;
    NSTokenField *_tokenView;
    NSTextField *_titleLabel;
    NSTextField *_tagsLabel;
    NSTextField *_valueLabel;
    NSTextField *_tagsHelp;
    NSButton *_helpButton;
    NSButton *_saveButton;
    NSButton *_cancelButton;
    NSScrollView *_valueScrollView;
    NSTextField *_escapingLabel;
    NSString *_title;
    NSString *_value;
    NSString *_guid;
    NSArray<NSString *> *_tags;
    iTermSendTextEscaping _escaping;
    BOOL _canceled;
}

- (instancetype)initWithSnippet:(iTermSnippet *)snippet
                     completion:(void (^)(iTermSnippet * _Nullable snippet))completion {
    self = [super initWithWindow:nil];
    if (self) {
        if (snippet) {
            _title = snippet.title;
            _value = snippet.value;
            _tags = snippet.tags ?: @[];
            _guid = snippet.guid;
            _escaping = snippet.escaping;
        } else {
            NSString *pasteboardString = [NSString stringFromPasteboard];
            if (pasteboardString) {
                _title = [pasteboardString ellipsizedDescriptionNoLongerThan:40];
                _value = pasteboardString;
            } else {
                _title = NSLocalizedString(@"Untitled", @"New snippet title");
                _value = @"";
            }
            _guid = [[NSUUID UUID] UUIDString];
            _tags = @[];
            _escaping = iTermSendTextEscapingCommon;
        }
        _completion = [completion copy];
    }
    return self;
}

- (iTermSnippet *)snippet {
    if (_canceled) {
        return nil;
    }
    return [[iTermSnippet alloc] initWithTitle:_title
                                         value:_value
                                          guid:_guid
                                          tags:_tags
                                      escaping:_escaping
                                       version:[iTermSnippet currentVersion]];
}

- (NSNibName)windowNibName {
    return @"iTermEditSnippetWindowController";
}

- (void)loadWindow {
    iTermSnippetEditorPanel *panel = [[iTermSnippetEditorPanel alloc]
        initWithContentRect:NSMakeRect(0, 0, 640, 520)
                  styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskResizable | NSWindowStyleMaskDocModalWindow)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    panel.title = NSLocalizedString(@"Edit Snippet", @"Window title for snippet editor");
    panel.hidesOnDeactivate = YES;
    panel.releasedWhenClosed = NO;
    panel.delegate = self;
    panel.autorecalculatesKeyViewLoop = NO;

    NSView *contentView = panel.contentView;

    _titleLabel = [NSTextField labelWithString:NSLocalizedString(@"Title:", @"Snippet editor field")];
    [contentView addSubview:_titleLabel];

    _titleView = [[NSTextField alloc] initWithFrame:NSZeroRect];
    _titleView.editable = YES;
    _titleView.selectable = YES;
    _titleView.bezeled = YES;
    _titleView.bezelStyle = NSTextFieldSquareBezel;
    _titleView.drawsBackground = YES;
    _titleView.font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
    _titleView.focusRingType = NSFocusRingTypeNone;
    _titleView.lineBreakMode = NSLineBreakByClipping;
    _titleView.cell.scrollable = YES;
    [contentView addSubview:_titleView];

    _tagsLabel = [NSTextField labelWithString:NSLocalizedString(@"Tags:", @"Snippet editor field")];
    [contentView addSubview:_tagsLabel];

    _tokenView = [[NSTokenField alloc] initWithFrame:NSZeroRect];
    _tokenView.editable = YES;
    _tokenView.selectable = YES;
    _tokenView.bezeled = YES;
    _tokenView.bezelStyle = NSTextFieldSquareBezel;
    _tokenView.drawsBackground = YES;
    _tokenView.font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
    _tokenView.focusRingType = NSFocusRingTypeNone;
    [contentView addSubview:_tokenView];

    _tagsHelp = [NSTextField labelWithString:NSLocalizedString(@"Use / in tag names to create folders in Edit > Snippets menu", @"Snippet editor tags hint")];
    [contentView addSubview:_tagsHelp];

    _valueLabel = [NSTextField labelWithString:NSLocalizedString(@"Value:", @"Snippet editor field")];
    [contentView addSubview:_valueLabel];

    _valueScrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    _valueScrollView.borderType = NSLineBorder;
    _valueScrollView.hasVerticalScroller = YES;
    _valueScrollView.hasHorizontalScroller = NO;
    _valueScrollView.autohidesScrollers = YES;

    _valueView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 592, 220)];
    _valueView.importsGraphics = NO;
    _valueView.richText = NO;
    _valueView.allowsUndo = YES;
    _valueView.textColor = NSColor.textColor;
    _valueView.backgroundColor = NSColor.textBackgroundColor;
    _valueView.insertionPointColor = NSColor.textColor;
    _valueView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _valueScrollView.documentView = _valueView;
    [contentView addSubview:_valueScrollView];

    _escapingLabel = [NSTextField labelWithString:NSLocalizedString(@"Escaping:", @"Snippet editor field")];
    [contentView addSubview:_escapingLabel];

    _escapingButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    NSMenu *escapingMenu = _escapingButton.menu;
    NSMenuItem *cStyleItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"C-Style Backslash Escaping", @"Snippet escaping option")
                                                        action:nil
                                                 keyEquivalent:@""];
    cStyleItem.tag = iTermSendTextEscapingCommon;
    [escapingMenu addItem:cStyleItem];

    NSMenuItem *literalItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Unescaped Literal Text", @"Snippet escaping option")
                                                         action:nil
                                                  keyEquivalent:@""];
    literalItem.tag = iTermSendTextEscapingNone;
    [escapingMenu addItem:literalItem];

    [escapingMenu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *legacyItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Backward Compatibility Escaping", @"Snippet escaping option")
                                                        action:nil
                                                 keyEquivalent:@""];
    legacyItem.tag = iTermSendTextEscapingCompatibility;
    [escapingMenu addItem:legacyItem];
    [contentView addSubview:_escapingButton];

    _helpButton = [NSButton buttonWithTitle:@"" target:self action:@selector(help:)];
    _helpButton.bezelStyle = NSBezelStyleHelpButton;
    [contentView addSubview:_helpButton];

    _cancelButton = [NSButton buttonWithTitle:NSLocalizedString(@"Cancel", @"Snippet editor action")
                                       target:self
                                       action:@selector(cancel:)];
    _cancelButton.keyEquivalent = @"\033";
    [contentView addSubview:_cancelButton];

    _saveButton = [NSButton buttonWithTitle:NSLocalizedString(@"Save", @"Snippet editor action")
                                     target:self
                                     action:@selector(ok:)];
    [contentView addSubview:_saveButton];

    self.window = panel;
}

- (void)windowDidLoad {
    [super windowDidLoad];
    _titleView.stringValue = _title;
    _valueView.string  = _value;
    _valueView.automaticQuoteSubstitutionEnabled = NO;
    _valueView.automaticLinkDetectionEnabled = NO;
    _valueView.automaticDataDetectionEnabled = NO;
    _valueView.automaticDashSubstitutionEnabled = NO;
    _valueView.automaticTextReplacementEnabled = NO;
    _valueView.automaticSpellingCorrectionEnabled = NO;
    _valueView.continuousSpellCheckingEnabled = NO;
    _valueView.grammarCheckingEnabled = NO;
    _valueView.font = [NSFont monospacedSystemFontOfSize:13 weight:NSFontWeightRegular];
    _valueView.textContainerInset = NSMakeSize(8, 8);
    _valueView.horizontallyResizable = NO;
    _valueView.verticallyResizable = YES;
    _valueView.maxSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
    _valueView.textContainer.widthTracksTextView = YES;

    _tokenView.objectValue = _tags ?: @[];
    _tokenView.delegate = self;

    [_escapingButton selectItemWithTag:_escaping];
    for (NSTextField *label in @[_titleLabel, _tagsLabel, _valueLabel, _escapingLabel]) {
        label.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
        label.alignment = NSTextAlignmentLeft;
    }
    _tagsHelp.font = [NSFont systemFontOfSize:11];
    _tagsHelp.textColor = NSColor.secondaryLabelColor;
    _tagsHelp.cell.wraps = YES;
    _tagsHelp.cell.usesSingleLineMode = NO;
    _tagsHelp.lineBreakMode = NSLineBreakByWordWrapping;
    self.window.defaultButtonCell = nil;
    _saveButton.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    _saveButton.keyEquivalent = @"\n";
    _saveButton.toolTip = NSLocalizedString(@"Save with Command-Return", @"Snippet editor shortcut");
    __weak typeof(self) weakSelf = self;
    ((iTermSnippetEditorPanel *)self.window).saveSnippet = ^{ [weakSelf ok:nil]; };
    _helpButton.toolTip = NSLocalizedString(@"Learn about text escaping", @"Snippet editor help");
    self.window.contentView.autoresizesSubviews = NO;
    self.window.contentMinSize = NSMakeSize(560, 440);
    [self.window setContentSize:NSMakeSize(640, 520)];
    self.window.initialFirstResponder = _titleView;
    [self layoutEditor];
}

- (void)windowDidResize:(NSNotification *)notification {
    [self layoutEditor];
}

- (void)layoutEditor {
    const NSRect bounds = self.window.contentView.bounds;
    const CGFloat width = NSWidth(bounds) - 48;
    const CGFloat height = NSHeight(bounds);
    _titleLabel.frame = NSMakeRect(24, height - 40, width, 18);
    _titleView.frame = NSMakeRect(24, height - 70, width, 24);
    _tagsLabel.frame = NSMakeRect(24, height - 100, width, 18);
    _tokenView.frame = NSMakeRect(24, height - 130, width, 24);
    _tagsHelp.frame = NSMakeRect(24, height - 164, width, 30);
    _valueLabel.frame = NSMakeRect(24, height - 192, width, 18);
    _valueScrollView.frame = NSMakeRect(24, 98, width, MAX(0, height - 300));
    _valueView.frame = NSMakeRect(0, 0, _valueScrollView.contentSize.width,
                                 MAX(_valueView.frame.size.height, _valueScrollView.contentSize.height));
    _valueView.minSize = NSMakeSize(0, _valueScrollView.contentSize.height);
    _escapingLabel.frame = NSMakeRect(24, 66, 90, 18);
    _escapingButton.frame = NSMakeRect(120, 62, MAX(0, NSWidth(bounds) - 184), 28);
    _helpButton.frame = NSMakeRect(NSWidth(bounds) - 49, 64, 25, 25);
    _saveButton.frame = NSMakeRect(NSWidth(bounds) - 134, 16, 110, 32);
    _cancelButton.frame = NSMakeRect(NSWidth(bounds) - 246, 16, 100, 32);
}

- (IBAction)ok:(id)sender {
    [self.window makeFirstResponder:nil];
    _canceled = NO;
    _title = _titleView.stringValue.copy ?: @"";
    _value = _valueView.string.copy ?: @"";
    _tags = _tokenView.objectValue ?: @[];
    _escaping = _escapingButton.selectedTag;

    self.completion(self.snippet);
    [self.window.sheetParent endSheet:self.window];
}

- (IBAction)cancel:(id)sender {
    _canceled = YES;
    self.completion(nil);
    [self.window.sheetParent endSheet:self.window];
}

- (IBAction)help:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = NSLocalizedString(@"Snippet Text Escaping", @"Snippet escaping help title");
    alert.informativeText = [self escapingHelpText];
    [alert beginSheetModalForWindow:self.window completionHandler:nil];
}

- (NSString *)escapingHelpText {
    return NSLocalizedString(@"C-style backslash escaping interprets \\a (bell), \\b (backspace), \\e (escape), \\n (newline), \\r (carriage return), \\t (tab), \\\\ (backslash), and \\x followed by two hexadecimal digits for a UTF-8 byte.\n\nLiteral text sends every character exactly as entered.\n\nLegacy escaping supports only \\n, \\e, \\a, and \\t. Choose C-style escaping for new snippets that need escape sequences.", @"Snippet escaping help");
}

#pragma mark - NSTokenFieldDelegate

- (NSArray *)tokenField:(NSTokenField *)tokenField
       shouldAddObjects:(NSArray *)tokens
                atIndex:(NSUInteger)index {
    return tokens;
}

@end
