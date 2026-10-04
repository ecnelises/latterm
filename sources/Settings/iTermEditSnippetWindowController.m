//
//  iTermEditSnippetWindowController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/14/20.
//

#import "iTermEditSnippetWindowController.h"
#import "NSStringITerm.h"
#import "iTerm2SharedARC-Swift.h"

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
    IBOutlet NSTextField *_titleView;
    IBOutlet NSTextView *_valueView;
    IBOutlet NSPopUpButton *_escapingButton;
    IBOutlet NSTokenField *_tokenView;
    IBOutlet NSTextField *_titleLabel;
    IBOutlet NSTextField *_tagsLabel;
    IBOutlet NSTextField *_valueLabel;
    IBOutlet NSTextField *_tagsHelp;
    IBOutlet NSButton *_helpButton;
    IBOutlet NSButton *_saveButton;
    IBOutlet NSButton *_cancelButton;
    IBOutlet NSScrollView *_valueScrollView;
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
    self = [super initWithWindowNibPath:[iTermSettingsLocalization nibPath:NSStringFromClass(self.class)] owner:self];
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
    _escapingLabel = [NSTextField labelWithString:NSLocalizedString(@"Escaping:", @"Snippet editor field")];
    [self.window.contentView addSubview:_escapingLabel];
    for (NSTextField *label in @[_titleLabel, _tagsLabel, _valueLabel, _escapingLabel]) {
        label.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
        label.alignment = NSTextAlignmentLeft;
    }
    _tagsHelp.font = [NSFont systemFontOfSize:11];
    _tagsHelp.textColor = NSColor.secondaryLabelColor;
    _tagsHelp.cell.wraps = YES;
    _tagsHelp.cell.usesSingleLineMode = NO;
    _tagsHelp.lineBreakMode = NSLineBreakByWordWrapping;
    _saveButton.title = NSLocalizedString(@"Save", @"Snippet editor action");
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
