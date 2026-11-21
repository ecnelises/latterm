//
//  SmartSelection.m
//  iTerm
//
//  Created by George Nachman on 9/25/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import "SmartSelectionController.h"

#import "DebugLogging.h"
#import "FutureMethods.h"
#import "ITAddressBookMgr.h"
#import "NSArray+iTerm.h"
#import "NSMutableAttributedString+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSTableView+iTerm.h"
#import "NSTextField+iTerm.h"
#import "NSWorkspace+iTerm.h"
#import "ProfileModel.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermProfilePreferences.h"
#import "iTermTextExtractor.h"
#import "iTermUserDefaults.h"

NSString *const kRegexKey = @"regex";
NSString *const kNotesKey = @"notes";
NSString *const kPrecisionKey = @"precision";
NSString *const kActionsKey = @"actions";

NSString *const kVeryLowPrecision = @"very_low";
NSString *const kLowPrecision = @"low";
NSString *const kNormalPrecision = @"normal";
NSString *const kHighPrecision = @"high";
NSString *const kVeryHighPrecision = @"very_high";

static NSString *const kLogDebugInfoKey = @"Log Smart Selection Debug Info";

const double SmartSelectionVeryLowPrecision = 0.00001;
const double SmartSelectionLowPrecision = 0.001;
const double SmartSelectionNormalPrecision = 1.0;
const double SmartSelectionHighPrecision = 1000.0;
const double SmartSelectionVeryHighPrecision = 1000000.0;

@interface NSString(iTermTextDataSource)<iTermTextDataSource>
@end

@interface SmartSelectionController() <NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate, iTermPlaygroundTextViewDelegate, NSMenuItemValidation>
@end

@implementation SmartSelectionController {
    IBOutlet NSTableView *tableView_;
    IBOutlet ContextMenuActionPrefsController *contextMenuPrefsController_;
    IBOutlet NSButton *logDebugInfo_;

    IBOutlet NSTextField *_nameTextField;
    IBOutlet NSTextView *_regexTextView;
    IBOutlet iTermPlaygroundTextView *_playgroundTextView;
    IBOutlet NSView *_detailView;
    IBOutlet NSPopUpButton *_precisionButton;
    IBOutlet NSTextField *_playgroundResultLabel;
    IBOutlet NSTextField *_noRuleSelected;
    IBOutlet NSButton *_removeButton;
    IBOutlet NSButton *_syntaxHelpButton;
    IBOutlet NSButton *_actionsButton;
    NSUndoManager *_undoManager;
}

@synthesize guid = guid_;
@synthesize hasSelection = hasSelection_;
@synthesize delegate = delegate_;

+ (NSArray<NSString *> *)precisionKeys {
    return @[ kVeryLowPrecision,
              kLowPrecision,
              kNormalPrecision,
              kHighPrecision,
              kVeryHighPrecision ];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    tableView_.delegate = nil;
    tableView_.dataSource = nil;
}

- (instancetype)init {
    return [self initWithWindow:nil];
}

- (instancetype)initWithWindow:(NSWindow *)window {
    self = [super initWithWindow:window];
    if (self) {
        contextMenuPrefsController_ = [[ContextMenuActionPrefsController alloc] init];
    }
    return self;
}

- (NSNibName)windowNibName {
    return @"SmartSelection";
}

- (void)loadWindow {
    NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(162, 156, 805, 448)
                                                styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
                                                  backing:NSBackingStoreBuffered
                                                    defer:YES];
    panel.releasedWhenClosed = NO;
    panel.hidesOnDeactivate = NO;
    panel.title = NSLocalizedStringFromTableInBundle(@"Smart Selection Rules",
                                                     @"Localizable",
                                                     [NSBundle bundleForClass:self.class],
                                                     @"Smart Selection Rules panel title");
    NSView *content = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 805, 448)];
    panel.contentView = content;

    NSTextField *heading = [iTermSettingsControlFactory labelWithTitle:@"Smart Selection Rules"];
    heading.font = [NSFont boldSystemFontOfSize:[NSFont systemFontSize]];
    [heading sizeToFit];
    heading.frame = NSMakeRect(17, 418, NSWidth(heading.frame), 18);
    [content addSubview:heading];

    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, 54, 375, 355)];
    scrollView.borderType = NSBezelBorder;
    scrollView.hasVerticalScroller = YES;
    scrollView.hasHorizontalScroller = NO;
    scrollView.autohidesScrollers = YES;

    tableView_ = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 373, 353)];
    tableView_.headerView = nil;
    tableView_.usesAlternatingRowBackgroundColors = YES;
    tableView_.allowsMultipleSelection = YES;
    tableView_.allowsColumnReordering = NO;
    tableView_.allowsColumnResizing = NO;
    tableView_.columnAutoresizingStyle = NSTableViewLastColumnOnlyAutoresizingStyle;
    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"notes"];
    col.width = 355;
    col.minWidth = 10;
    col.maxWidth = 10000;
    [tableView_ addTableColumn:col];
    tableView_.dataSource = self;
    tableView_.delegate = self;
    scrollView.documentView = tableView_;
    [content addSubview:scrollView];

    NSButton *addButton = [iTermSettingsControlFactory addButtonWithTarget:self action:@selector(addRule:)];
    addButton.frame = NSMakeRect(20, 18, 24, 25);
    [content addSubview:addButton];

    _removeButton = [iTermSettingsControlFactory removeButtonWithTarget:self action:@selector(removeRule:)];
    _removeButton.frame = NSMakeRect(44, 18, 24, 25);
    _removeButton.enabled = NO;
    [content addSubview:_removeButton];

    NSButton *defaultsButton = [iTermSettingsControlFactory pushButtonWithTitle:@"Load Defaults"
                                                                         target:self
                                                                         action:@selector(loadDefaults:)];
    defaultsButton.frame = NSMakeRect(70, 18, MAX(106, NSWidth(defaultsButton.frame)), 25);
    [content addSubview:defaultsButton];

    logDebugInfo_ = [iTermSettingsControlFactory checkboxWithTitle:@"Log debug info to Console.app"
                                                            target:self
                                                            action:@selector(logDebugInfoChanged:)];
    [logDebugInfo_ sizeToFit];
    logDebugInfo_.frame = NSMakeRect(CGRectGetMaxX(defaultsButton.frame) + 12, 21, NSWidth(logDebugInfo_.frame), 18);
    [content addSubview:logDebugInfo_];

    NSButton *helpButton = [iTermSettingsControlFactory helpButtonWithTarget:self action:@selector(help:)];
    helpButton.frame = NSMakeRect(667, 16, 25, 25);
    [content addSubview:helpButton];

    NSButton *closeButton = [iTermSettingsControlFactory pushButtonWithTitle:@"Close"
                                                                      target:self
                                                                      action:@selector(closeSheet:)];
    closeButton.keyEquivalent = @"\r";
    closeButton.frame = NSMakeRect(695, 12, 96, 32);
    [content addSubview:closeButton];

    _noRuleSelected = [iTermSettingsControlFactory secondaryLabelWithTitle:@"No rule selected" wrapping:NO];
    _noRuleSelected.alignment = NSTextAlignmentCenter;
    _noRuleSelected.frame = NSMakeRect(403, 302, 382, 18);
    [content addSubview:_noRuleSelected];

    _detailView = [[NSView alloc] initWithFrame:NSMakeRect(403, 178, 382, 243)];

    NSTextField *nameLabel = [iTermSettingsControlFactory rightAlignedLabelWithTitle:@"Name"];
    nameLabel.frame = NSMakeRect(0, 225, 118, 16);
    [_detailView addSubview:nameLabel];

    _nameTextField = [iTermSettingsControlFactory textFieldWithWidth:258 placeholder:nil target:nil action:nil delegate:self];
    _nameTextField.frame = NSMakeRect(124, 222, 258, 21);
    [_detailView addSubview:_nameTextField];

    NSTextField *regexLabel = [iTermSettingsControlFactory rightAlignedLabelWithTitle:@"Regular expression"];
    regexLabel.frame = NSMakeRect(0, 201, 118, 16);
    [_detailView addSubview:regexLabel];

    iTermLinkButton *syntaxHelp = [[iTermLinkButton alloc] initWithFrame:NSMakeRect(0, 181, 118, 19)];
    syntaxHelp.title = NSLocalizedStringFromTableInBundle(@"Syntax Help",
                                                          @"Localizable",
                                                          [NSBundle bundleForClass:self.class],
                                                          @"Regex syntax help link");
    syntaxHelp.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
    syntaxHelp.alignment = NSTextAlignmentRight;
    syntaxHelp.target = self;
    syntaxHelp.action = @selector(syntaxHelp:);
    [syntaxHelp configureLinkAppearance];
    _syntaxHelpButton = syntaxHelp;
    [_detailView addSubview:_syntaxHelpButton];

    NSScrollView *regexScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(124, 79, 258, 135)];
    regexScroll.borderType = NSBezelBorder;
    regexScroll.hasVerticalScroller = YES;
    regexScroll.hasHorizontalScroller = NO;
    regexScroll.autohidesScrollers = YES;
    _regexTextView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 256, 133)];
    _regexTextView.minSize = NSMakeSize(0, 133);
    _regexTextView.maxSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
    _regexTextView.verticallyResizable = YES;
    _regexTextView.horizontallyResizable = NO;
    _regexTextView.autoresizingMask = NSViewWidthSizable;
    _regexTextView.textContainer.containerSize = NSMakeSize(256, CGFLOAT_MAX);
    _regexTextView.textContainer.widthTracksTextView = YES;
    regexScroll.documentView = _regexTextView;
    [_detailView addSubview:regexScroll];

    NSTextField *precisionLabel = [iTermSettingsControlFactory rightAlignedLabelWithTitle:@"Precision"];
    precisionLabel.frame = NSMakeRect(0, 33, 118, 16);
    [_detailView addSubview:precisionLabel];

    _precisionButton = [iTermSettingsControlFactory popUpButtonWithTitles:@[
        @"Very Low",
        @"Low",
        @"Normal",
        @"High",
        @"Very High"
    ]
                                                                     tags:@[ @0, @1, @2, @3, @4 ]
                                                                   target:self
                                                                   action:@selector(changePrecision:)];
    _precisionButton.frame = NSMakeRect(121, 26, 265, 25);
    [_detailView addSubview:_precisionButton];

    _actionsButton = [iTermSettingsControlFactory pushButtonWithTitle:@"Actions…" target:self action:@selector(editActions:)];
    _actionsButton.frame = NSMakeRect(267, -7, 115, 32);
    [_detailView addSubview:_actionsButton];

    [content addSubview:_detailView];

    NSBox *divider = [[NSBox alloc] initWithFrame:NSMakeRect(403, 167, 381, 5)];
    divider.boxType = NSBoxSeparator;
    [content addSubview:divider];

    NSScrollView *playgroundScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(403, 76, 381, 85)];
    playgroundScroll.borderType = NSBezelBorder;
    playgroundScroll.hasVerticalScroller = YES;
    playgroundScroll.hasHorizontalScroller = NO;
    playgroundScroll.autohidesScrollers = YES;
    _playgroundTextView = [[iTermPlaygroundTextView alloc] initWithFrame:NSMakeRect(0, 0, 379, 83)];
    _playgroundTextView.minSize = NSMakeSize(0, 83);
    _playgroundTextView.maxSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
    _playgroundTextView.verticallyResizable = YES;
    _playgroundTextView.horizontallyResizable = NO;
    _playgroundTextView.autoresizingMask = NSViewWidthSizable;
    _playgroundTextView.textContainer.containerSize = NSMakeSize(379, CGFLOAT_MAX);
    _playgroundTextView.textContainer.widthTracksTextView = YES;
    playgroundScroll.documentView = _playgroundTextView;
    [content addSubview:playgroundScroll];

    _playgroundResultLabel = [iTermSettingsControlFactory secondaryLabelWithTitle:@"Click on text in playground to test rules"
                                                                         wrapping:NO];
    _playgroundResultLabel.frame = NSMakeRect(403, 52, 382, 16);
    [content addSubview:_playgroundResultLabel];

    self.window = panel;
}

- (void)windowDidLoad {
    [super windowDidLoad];
    [self configureSmartSelectionControls];
    [self reloadData];
}

- (IBAction)closeSheet:(id)sender {
    [self.window.sheetParent endSheet:self.window];
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    DLog(@"%@", menuItem);
    if (menuItem.action == @selector(undo:)) {
        return [_undoManager canUndo];
    }
    if (menuItem.action == @selector(redo:)) {
        return [_undoManager canRedo];
    }
    return YES;
}

- (void)awakeFromNib {
    [self configureSmartSelectionControls];
}

- (void)configureSmartSelectionControls {
    _undoManager = [[NSUndoManager alloc] init];

    _regexTextView.font = [NSFont userFixedPitchFontOfSize:[NSFont systemFontSize]];
    _regexTextView.automaticSpellingCorrectionEnabled = NO;
    _regexTextView.automaticDashSubstitutionEnabled = NO;
    _regexTextView.automaticQuoteSubstitutionEnabled = NO;
    _regexTextView.automaticDataDetectionEnabled = NO;
    _regexTextView.automaticLinkDetectionEnabled = NO;
    _regexTextView.smartInsertDeleteEnabled = NO;
    _regexTextView.richText = NO;

    _playgroundTextView.font = [NSFont userFixedPitchFontOfSize:[NSFont systemFontSize]];
    _playgroundTextView.playgroundDelegate = self;
    _playgroundTextView.automaticSpellingCorrectionEnabled = NO;
    _playgroundTextView.automaticDashSubstitutionEnabled = NO;
    _playgroundTextView.automaticQuoteSubstitutionEnabled = NO;
    _playgroundTextView.automaticDataDetectionEnabled = NO;
    _playgroundTextView.automaticLinkDetectionEnabled = NO;
    _playgroundTextView.smartInsertDeleteEnabled = NO;
    _playgroundTextView.richText = NO;

    _removeButton.enabled = NO;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(regexDidChange:)
                                                 name:NSTextDidChangeNotification
                                               object:_regexTextView];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(playgroundDidChange:)
                                                 name:NSTextDidChangeNotification
                                               object:_playgroundTextView];
}

+ (NSArray *)defaultRules {
    static NSArray *rulesArray;
    if (!rulesArray) {
        NSString* plistFile = [[NSBundle bundleForClass:[self class]] pathForResource:@"SmartSelectionRules"
                                                                               ofType:@"plist"];
        NSDictionary* rulesDict = plistFile ? [NSDictionary dictionaryWithContentsOfFile:plistFile] : nil;
        if (!rulesDict) {
            [iTermAppSignatureValidator warnAndExitWithReason:@"While loading the default smart selection rules"];
        }
        rulesArray = [rulesDict objectForKey:@"Rules"];
    }
    return rulesArray;
}

+ (NSArray *)actionsInRule:(NSDictionary *)rule {
    return [rule objectForKey:kActionsKey];
}

// Nil if the rule has no usable regex. Rules can come from hand-edited, dynamic, or imported
// profiles, so the value may be missing or not a string.
+ (NSString *)regexInRule:(NSDictionary *)rule {
    NSString *regex = [NSString castFrom:[rule objectForKey:kRegexKey]];
    return regex.length > 0 ? regex : nil;
}

+ (double)precisionInRule:(NSDictionary *)rule {
    NSDictionary *precisionValues = @{ kVeryLowPrecision: @(SmartSelectionVeryLowPrecision),
                                       kLowPrecision: @(SmartSelectionLowPrecision),
                                       kNormalPrecision: @(SmartSelectionNormalPrecision),
                                       kHighPrecision: @(SmartSelectionHighPrecision),
                                       kVeryHighPrecision: @(SmartSelectionVeryHighPrecision) };

    NSString *precision = rule[kPrecisionKey];
    return [precisionValues[precision] doubleValue];
}

- (Profile *)bookmark {
    Profile* bookmark = [[ProfileModel sharedInstance] bookmarkWithGuid:self.guid];
    if (!bookmark) {
        bookmark = [[ProfileModel sessionsInstance] bookmarkWithGuid:self.guid];
    }
    return bookmark;
}

- (ProfileModel *)modelForBookmark:(Profile *)bookmark {
    if ([[ProfileModel sharedInstance] bookmarkWithGuid:[bookmark objectForKey:KEY_GUID]]) {
        return [ProfileModel sharedInstance];
    } else if ([[ProfileModel sessionsInstance] bookmarkWithGuid:[bookmark objectForKey:KEY_GUID]]) {
        return [ProfileModel sessionsInstance];
    } else {
        return nil;
    }
}

- (NSArray<NSDictionary *> *)rules {
    Profile *bookmark = [self bookmark];
    NSArray<NSDictionary *> *rules = [bookmark objectForKey:KEY_SMART_SELECTION_RULES];
    return rules ? rules : [SmartSelectionController defaultRules];
}

- (NSDictionary *)defaultRule {
    return @{ kRegexKey: @"",
              kPrecisionKey: kVeryLowPrecision };
}

- (void)setRule:(NSDictionary *)rule forRow:(NSInteger)rowIndex {
    NSMutableArray *rules = [self.rules mutableCopy];
    NSInteger actualIndex = rowIndex;
    if (rowIndex < 0) {
        assert(rule);
        [rules addObject:rule];
        actualIndex = rules.count - 1;
    } else {
        if (rule) {
            [rules replaceObjectAtIndex:rowIndex withObject:rule];
        } else {
            [rules removeObjectAtIndex:rowIndex];
        }
    }
    Profile* bookmark = [self bookmark];
    [iTermProfilePreferences setObject:rules forKey:KEY_SMART_SELECTION_RULES inProfile:bookmark model:[self modelForBookmark:bookmark] withSideEffects:NO];
    if (rowIndex < 0) {
        [tableView_ insertRowsAtIndexes:[NSIndexSet indexSetWithIndex:actualIndex]
                          withAnimation:NSTableViewAnimationEffectNone];
    } else {
        if (rule) {
            [tableView_ reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:actualIndex]
                                  columnIndexes:[NSIndexSet indexSetWithIndex:0]];
        } else {
            [tableView_ removeRowsAtIndexes:[NSIndexSet indexSetWithIndex:actualIndex]
                              withAnimation:NSTableViewAnimationEffectNone];
        }
    }
    [tableView_ noteHeightOfRowsWithIndexesChanged:[NSIndexSet indexSetWithIndex:rowIndex]];
    // This must flush user defaults for setUseInterpolatedStrings to work.
    [delegate_ smartSelectionChanged:nil];
}

- (IBAction)syntaxHelp:(id)sender {
    [[NSWorkspace sharedWorkspace] it_openURL:[NSURL URLWithString:@"https://unicode-org.github.io/icu/userguide/strings/regexp.html"]];
}

- (IBAction)help:(id)sender {
    [[NSWorkspace sharedWorkspace] it_openURL:[NSURL URLWithString:@"http://www.iterm2.com/smartselection.html"]];
}

- (IBAction)addRule:(id)sender {
    [self pushUndo];
    [self setRule:[self defaultRule] forRow:-1];
    [tableView_ selectRowIndexes:[NSIndexSet indexSetWithIndex:tableView_.numberOfRows - 1]
            byExtendingSelection:NO];
}

- (IBAction)removeRule:(id)sender {
    [self pushUndo];
    [tableView_.selectedRowIndexes enumerateIndexesWithOptions:NSEnumerationReverse
                                                    usingBlock:^(NSUInteger row, BOOL * _Nonnull stop) {
        [self setRule:nil forRow:row];
    }];
}

- (IBAction)loadDefaults:(id)sender {
    [self pushUndo];
    Profile *bookmark = [self bookmark];
    [[self modelForBookmark:bookmark] setObject:[SmartSelectionController defaultRules]
                                         forKey:KEY_SMART_SELECTION_RULES
                                     inBookmark:bookmark];
    [self reloadData];
    [delegate_ smartSelectionChanged:nil];
}

- (void)setGuid:(NSString *)guid {
    if (guid == guid_ || [guid isEqualToString:guid_]) {
        return;
    }
    guid_ = [guid copy];
    [self reloadData];
}

- (NSString *)displayNameForPrecision:(NSString *)precision {
    NSDictionary *names = @{ kVeryLowPrecision: @"Very Low",
                             kLowPrecision: @"Low",
                             kNormalPrecision: @"Normal",
                             kHighPrecision: @"High",
                             kVeryHighPrecision: @"Very High" };
    return names[precision] ?: @"Undefined";
}

- (int)indexForPrecision:(NSString *)precision {
    NSUInteger index = [[SmartSelectionController precisionKeys] indexOfObject:precision];
    if (index == NSNotFound) {
        return 0;
    } else {
        return index;
    }
}

- (NSString *)precisionKeyWithIndex:(int)i {
    return [[SmartSelectionController precisionKeys] objectAtIndex:i];
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView {
    DLog(@"Reporting number of rows: %@", @(self.rules.count));
    DLog(@"%@", [NSThread callStackSymbols]);
    return self.rules.count;
}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row {
    NSArray<NSDictionary *> *rules = self.rules;
    NSDictionary *rule = rules[row];
    NSAttributedString *attributedString = [self attributedStringForRule:rule];
    return [attributedString heightForWidth:tableView.tableColumns[0].width] + 8;
}


- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex {
    NSArray<NSDictionary *> *rules = self.rules;
    NSDictionary *rule = rules[rowIndex];
    iTermTableCellViewWithTextField *view = [tableView newTableCellViewWithTextFieldUsingIdentifier:@"Smart Selection Tableview Entry"
                                                                                   attributedString:[self attributedStringForRule:rule]];
    return view;
}

- (NSAttributedString *)attributedStringForRule:(NSDictionary *)rule {
    NSAttributedString *newline = [[NSAttributedString alloc] initWithString:@"\n" attributes:self.regularAttributes];
    NSString *regex = rule[kRegexKey];
    id regexAttributedString = regex.length > 0 ? [self attributedStringForRegex:regex] : [NSNull null];
    NSArray *lines = nil;
    NSString *name = rule[kNotesKey];
    NSAttributedString *precisionAttributedString = [self precisionAttributedString:rule[kPrecisionKey]
                                                                        actionCount:[[NSArray castFrom:rule[kActionsKey]] count]];
    if ([name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length > 0) {
        NSAttributedString *nameAttributedString = [[NSAttributedString alloc] initWithString:name
                                                                                   attributes:self.nameAttributes];
        lines = @[nameAttributedString, regexAttributedString, precisionAttributedString];
    } else {
        lines = @[regexAttributedString, precisionAttributedString];
    }
    lines = [lines filteredArrayUsingBlock:^BOOL(id anObject) {
        return [anObject isKindOfClass:[NSAttributedString class]];
    }];
    return [lines it_componentsJoinedBySeparator:newline];
}

- (NSAttributedString *)precisionAttributedString:(NSString *)precision actionCount:(NSInteger)actionCount {
    NSMutableParagraphStyle *paragraphStyle = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
    NSDictionary *boldAttributes = @{
        NSParagraphStyleAttributeName: paragraphStyle,
        NSFontAttributeName: [NSFont systemFontOfSize:[NSFont systemFontSize] weight:NSFontWeightSemibold]
    };
    NSString *name = [[self displayNameForPrecision:precision] stringByAppendingString:@" precision"];
    if (actionCount == 1) {
        name = [name stringByAppendingFormat:@", one action"];
    } else if (actionCount > 1) {
        name = [name stringByAppendingFormat:@", %@ actions", @(actionCount)];
    }
    return [[NSAttributedString alloc] initWithString:name attributes:boldAttributes];
}

- (NSDictionary *)nameAttributes {
    NSMutableParagraphStyle *paragraphStyle = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
    paragraphStyle.lineBreakMode = NSLineBreakByTruncatingTail;
    NSDictionary *attributes = @{
        NSParagraphStyleAttributeName: paragraphStyle,
        NSFontAttributeName: [NSFont boldSystemFontOfSize:[NSFont systemFontSize] + 2]
    };
    return attributes;
}

- (NSDictionary *)regularAttributes {
    NSMutableParagraphStyle *paragraphStyle = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
    paragraphStyle.lineBreakMode = NSLineBreakByTruncatingTail;
    NSDictionary *attributes = @{
        NSParagraphStyleAttributeName: paragraphStyle,
        NSFontAttributeName: [NSFont systemFontOfSize:[NSFont systemFontSize]]
    };
    return attributes;
}

- (NSAttributedString *)attributedStringForRegex:(NSString *)regex {
    NSMutableParagraphStyle *paragraphStyle = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
    NSDictionary *attributes = @{
        NSParagraphStyleAttributeName: paragraphStyle,
        NSFontAttributeName: [NSFont monospacedSystemFontOfSize:[NSFont systemFontSize] weight:NSFontWeightRegular]
    };
    return [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"/%@/", regex]
                                           attributes:attributes];
}

- (IBAction)changePrecision:(NSPopUpButton *)sender {
    [self pushUndo];
    const NSInteger rowIndex = tableView_.selectedRow;
    const NSInteger index = sender.indexOfSelectedItem;
    NSMutableDictionary *rule = [self.rules[rowIndex] mutableCopy];
    rule[kPrecisionKey] = [self precisionKeyWithIndex:index];
    [self setRule:rule forRow:rowIndex];
}

#pragma mark - NSTableViewDelegate

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    [self updateDetailView];
}

- (void)reloadData {
    [tableView_ reloadData];
    [self updateDetailView];
}

- (void)updateDetailView {
    self.hasSelection = [tableView_ numberOfSelectedRows] == 1;
    _removeButton.enabled = tableView_.numberOfSelectedRows > 0;
    _detailView.hidden = !self.hasSelection;
    _noRuleSelected.hidden = self.hasSelection;
    if (tableView_.numberOfSelectedRows > 1) {
        _noRuleSelected.stringValue = @"Multiple rules selected";
    } else {
        _noRuleSelected.stringValue = @"No rule selected";
    }
    if (self.hasSelection) {
        const NSInteger row = [tableView_ selectedRow];
        NSDictionary *rule = self.rules[row];
        _nameTextField.stringValue = rule[kNotesKey] ?: @"";
        [_regexTextView setString:rule[kRegexKey] ?: @""];
        [_precisionButton selectItemAtIndex:[self indexForPrecision:rule[kPrecisionKey]]];
        const NSInteger actionCount = [[NSArray castFrom:rule[kActionsKey]] count];
        if (actionCount == 0) {
            _actionsButton.title = [NSString stringWithFormat:@"Actions…"];
        } else {
            _actionsButton.title = [NSString stringWithFormat:@"Actions (%@)…", @(actionCount)];
        }
    } else {
        _nameTextField.stringValue = @"";
        [_regexTextView setString:@""];
        [_precisionButton selectItemAtIndex:0];
    }
}

- (IBAction)logDebugInfoChanged:(id)sender {
    [[iTermUserDefaults userDefaults] setObject:[NSNumber numberWithInt:logDebugInfo_.state]
                                              forKey:kLogDebugInfoKey];
}

+ (BOOL)logDebugInfo {
    NSNumber *n = [[iTermUserDefaults userDefaults] valueForKey:kLogDebugInfoKey];
    if (n) {
        return [n intValue] == NSControlStateValueOn;
    } else {
        return NO;
    }
}

- (IBAction)editActions:(id)sender {
    if (!self.hasSelection) {
        return;
    }
    const NSInteger row = [tableView_ selectedRow];
    if (row < 0 || row >= self.rules.count) {
        return;
    }
    NSDictionary *rule = [self.rules objectAtIndex:row];
    if (!rule) {
        return;
    }
    [self pushUndo];
    NSArray *actions = [SmartSelectionController actionsInRule:rule];
    [contextMenuPrefsController_ setActions:actions];
    contextMenuPrefsController_.useInterpolatedStrings = [self useInterpolatedStrings];
    [contextMenuPrefsController_ window];
    [contextMenuPrefsController_ setDelegate:self];
    __weak __typeof(self) weakSelf = self;
    [self.window beginSheet:contextMenuPrefsController_.window completionHandler:^(NSModalResponse returnCode) {
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf) {
            [strongSelf->contextMenuPrefsController_.window close];
            [strongSelf updateDetailView];
        }
    }];
}

- (void)windowWillOpen {
    [logDebugInfo_ setState:[SmartSelectionController logDebugInfo] ? NSControlStateValueOn : NSControlStateValueOff];
}

#pragma mark - Context Menu Actions Delegate

- (void)contextMenuActionsChanged:(NSArray *)newActions useInterpolatedStrings:(BOOL)useInterpolatedStrings {
    if (self.hasSelection) {
        int rowIndex = [tableView_ selectedRow];
        NSMutableDictionary *rule = [[self.rules objectAtIndex:rowIndex] mutableCopy];
        [rule setObject:newActions forKey:kActionsKey];
        [self setUseInterpolatedStrings:useInterpolatedStrings];
        // This call flushes user defaults, which setUseInterpolatedStrings: needs.
        [self setRule:rule forRow:rowIndex];
    }
    [contextMenuPrefsController_.window.sheetParent endSheet:contextMenuPrefsController_.window];
}

- (void)setUseInterpolatedStrings:(BOOL)useInterpolatedStrings {
    // Note: this assumes the caller will flush to user defaults.
    Profile *profile = [self bookmark];
    [[self modelForBookmark:profile] setObject:@(useInterpolatedStrings)
                                        forKey:KEY_SMART_SELECTION_ACTIONS_USE_INTERPOLATED_STRINGS
                                    inBookmark:profile];
}

- (BOOL)useInterpolatedStrings {
    return [iTermProfilePreferences boolForKey:KEY_SMART_SELECTION_ACTIONS_USE_INTERPOLATED_STRINGS
                                     inProfile:self.bookmark];
}

#pragma mark - NSTextFieldDelegate

- (void)save {
    if (!self.hasSelection) {
        return;
    }
    const NSInteger rowIndex = tableView_.selectedRow;
    if (rowIndex < 0) {
        return;
    }
    [self pushUndo];
    NSMutableDictionary *rule = [self.rules[rowIndex] mutableCopy];
    rule[kNotesKey] = [_nameTextField.stringValue copy];
    rule[kRegexKey] = [_regexTextView.textStorage.string copy] ?: @"";
    rule[kPrecisionKey] = [self precisionKeyWithIndex:_precisionButton.selectedTag];
    [self setRule:rule forRow:rowIndex];
}

- (void)controlTextDidEndEditing:(NSNotification *)obj {
    [self save];
}

- (void)controlTextDidChange:(NSNotification *)obj {
    [self save];
}

- (void)regexDidChange:(NSNotification *)notification {
    [self save];
}

- (void)playgroundDidChange:(NSNotification *)notification {
    [self updatePlayground];
}

- (void)updatePlayground {
    if (_playgroundTextView.lastCoord.x < 0 || _playgroundTextView.lastCoord.y < 0) {
        _playgroundResultLabel.stringValue = @"Click on text in playground to test rules";
        return;
    }
    if (_playgroundTextView.lastCoord.y >= _playgroundTextView.textStorage.string.numberOfLines ||
        _playgroundTextView.lastCoord.x >= _playgroundTextView.textStorage.string.width) {
        _playgroundResultLabel.stringValue = @"Click on text in playground to test rules";
        return;
    }
    iTermTextExtractor *extractor = [[iTermTextExtractor alloc] initWithDataSource:_playgroundTextView.textStorage.string ?: @""];
    VT100GridWindowedRange relativeRange;
    SmartMatch *result = [extractor smartSelectionAt:_playgroundTextView.lastCoord
                                           withRules:self.rules
                                      actionRequired:NO
                                               range:&relativeRange
                                    ignoringNewlines:NO];
    if (!result) {
        _playgroundResultLabel.stringValue = @"No match";
        return;
    }
    _playgroundResultLabel.stringValue = result.rule[kNotesKey];
    [_playgroundTextView highlightGridRange:VT100GridCoordRangeMake(result.startX,
                                                                    result.absStartY,
                                                                    result.endX,
                                                                    result.absEndY)];
}

- (IBAction)undo:(id)sender {
    [_undoManager undo];
}

- (IBAction)redo:(id)sender {
    [_undoManager redo];
}

- (void)pushUndo {
    [_undoManager registerUndoWithTarget:self
                                selector:@selector(setRules:)
                                  object:self.rules];
}

- (void)setRules:(NSArray<NSDictionary *> *)rules {
    Profile *profile = [self bookmark];
    [[self modelForBookmark:profile] setObject:rules forKey:KEY_SMART_SELECTION_RULES
                                    inBookmark:profile];
    [self reloadData];
    [delegate_ smartSelectionChanged:nil];
}

#pragma mark - iTermPlaygroundTextViewDelegate

- (void)playgroundClickCoordinateDidChange:(iTermPlaygroundTextView *)sender coordinate:(VT100GridCoord)coordinate {
    [self updatePlayground];
}

@end

@implementation NSString(iTermTextDataSource)
- (id<VT100ScreenMarkReading> _Nullable)commandMarkAt:(VT100GridCoord)coord mustHaveCommand:(BOOL)mustHaveCommand range:(out nullable VT100GridWindowedRange *)range { 
    return nil;
}

- (NSDate * _Nullable)dateForLine:(int)line {
    return nil;
}

- (id<iTermExternalAttributeIndexReading> _Nullable)externalAttributeIndexForLine:(int)y { 
    return nil;
}

- (id)fetchLine:(int)line block:(id  _Nullable (^NS_NOESCAPE)(ScreenCharArray * _Nonnull))block {
    ScreenCharArray *sca = [self screenCharArrayForLine:line];
    return block(sca);
}

- (iTermImmutableMetadata)metadataOnLine:(int)lineNumber { 
    return iTermImmutableMetadataDefault();
}

- (nonnull ScreenCharArray *)screenCharArrayAtScreenIndex:(int)index {
    return [self screenCharArrayForLine:index];
}

- (nonnull ScreenCharArray *)screenCharArrayForLine:(int)line {
    NSArray<NSString *> *lines = [self componentsSeparatedByString:@"\n"];
    return [[lines[line] asScreenCharArray] paddedToAtLeastLength:self.width];
}

- (long long)totalScrollbackOverflow { 
    return 0;
}

- (int)width { 
    NSArray<NSString *> *lines = [self componentsSeparatedByString:@"\n"];
    NSString *line = [lines maxWithBlock:^NSComparisonResult(NSString *obj1, NSString *obj2) {
        return [@(obj1.length) compare:@(obj2.length)];
    }];
    const NSUInteger length = [[line asScreenCharArray] length];
    return MAX(2, length + 1);
}

- (BOOL)isFirstLineOfBlock:(int)lineNumber { 
    return NO;
}


- (int)numberOfLines { 
    return [[self componentsSeparatedByString:@"\n"] count];
}


@end
