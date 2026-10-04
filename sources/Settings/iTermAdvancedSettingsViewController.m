//
//  iTermAdvancedSettingsController.m
//  iTerm
//
//  Created by George Nachman on 3/18/14.
//
//

#import "iTermAdvancedSettingsViewController.h"

#import "DebugLogging.h"
#import "NSApplication+iTerm.h"
#import "NSArray+iTerm.h"
#import "NSMutableAttributedString+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSTextField+iTerm.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermUserDefaults.h"
#import "iTerm2SharedARC-Swift.h"
#import <objc/runtime.h>

@interface iTermTableViewTextField : NSTextField
@property (nonatomic, strong) NSAttributedString *regularAttributedString;
@property (nonatomic, strong) NSAttributedString *selectedAttributedString;

// Called when self is dealloc'ed or when you assign NO to editing.
@property (nonatomic, copy) void (^onEndEditing)(NSString *);

// You're responsible for setting this in controlTextDidBeginEditing and controlTextDidEndEditing
@property (nonatomic) BOOL editing;
@end

@implementation iTermTableViewTextField {
    BOOL _editing;
}

- (void)dealloc {
    [self setEditing:NO];
}

- (void)setEditing:(BOOL)editing {
    if (editing == _editing) {
        return;
    }
    _editing = editing;
    if (!_editing && _onEndEditing) {
        _onEndEditing(self.stringValue);
    }
}

- (BOOL)becomeFirstResponder {
    self.textColor = [NSColor labelColor];
    return [super becomeFirstResponder];
}

- (void)setBackgroundStyle:(NSBackgroundStyle)backgroundStyle {
    if (self.editable) {
        return;
    }
    switch (backgroundStyle) {
        case NSBackgroundStyleNormal:
            self.textColor = [NSColor labelColor];
            if (self.regularAttributedString) {
                self.attributedStringValue = self.regularAttributedString;
            }
            break;
        case NSBackgroundStyleEmphasized:
            self.textColor = [NSColor selectedMenuItemTextColor];
            if (self.selectedAttributedString) {
                self.attributedStringValue = self.selectedAttributedString;
            }
            break;

        case NSBackgroundStyleRaised:
        case NSBackgroundStyleLowered:
            break;
    }
}

@end

@interface iTermTableViewTextFieldWrapper : NSTableCellView
@property (nonatomic, copy) void (^onEndEditing)(NSString *);
@property (nonatomic) BOOL ignoreBackgroundStyle;
@end

@implementation iTermTableViewTextFieldWrapper

- (iTermTableViewTextField *)it_textField {
    return self.subviews.firstObject;
}
- (void)setOnEndEditing:(void (^)(NSString *))onEndEditing {
    self.it_textField.onEndEditing = onEndEditing;
}

- (void (^)(NSString *))onEndEditing {
    return self.it_textField.onEndEditing;
}

- (void)setBackgroundStyle:(NSBackgroundStyle)backgroundStyle {
    if (self.ignoreBackgroundStyle) {
        return;
    }
    iTermTableViewTextField *textField = self.it_textField;
    [textField setBackgroundStyle:backgroundStyle];
}

@end

@interface NSDictionary (AdvancedSettings)
- (iTermAdvancedSettingType)advancedSettingType;
- (NSComparisonResult)compareAdvancedSettingDicts:(NSDictionary *)other;
@end

@implementation NSDictionary (AdvancedSettings)

- (iTermAdvancedSettingType)advancedSettingType {
    return (iTermAdvancedSettingType)[[self objectForKey:kAdvancedSettingType] intValue];
}

- (NSComparisonResult)compareAdvancedSettingDicts:(NSDictionary *)other {
    return [self[kAdvancedSettingDescription] compare:other[kAdvancedSettingDescription]];
}

@end

static NSDictionary *gIntrospection;

@interface iTermAdvancedSettingsViewController()<NSTextFieldDelegate>
@end

@interface iTermAdvancedSettingsTableView: NSTableView
@end

@implementation iTermAdvancedSettingsTableView

// Corbin Dunn is my hero
// https://stackoverflow.com/questions/7101237/respond-to-mouse-events-in-text-field-in-view-based-table-view
- (BOOL)validateProposedFirstResponder:(NSResponder *)responder forEvent:(NSEvent *)event {
    if ([responder isKindOfClass:[iTermTableViewTextField class]]) {
        return YES;
    }
    return [super validateProposedFirstResponder:responder forEvent:event];
}

@end

@interface iTermAdvancedSettingsDocumentView : NSView
@end

@implementation iTermAdvancedSettingsDocumentView
- (BOOL)isFlipped { return YES; }
@end

@implementation iTermAdvancedSettingsViewController {
    IBOutlet NSTableColumn *_settingColumn;
    IBOutlet NSTableColumn *_valueColumn;
    NSTableColumn *_resetColumn;
    IBOutlet NSSearchField *_searchField;
    IBOutlet NSTableView *_tableView;
    IBOutlet NSButton *_excludeDefaults;

    NSTextField *_editingHelp;
    NSScrollView *_pageScrollView;
    NSView *_pageDocument;
    NSArray *_filteredAdvancedSettings;
    NSArray<iTermPreferencesSearchDocument *> *_docs;
}

+ (NSDictionary *)settingsDictionary {
    static NSDictionary *settings;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableDictionary *temp = [NSMutableDictionary dictionary];
        for (NSDictionary *setting in [self advancedSettings]) {
            temp[setting[kAdvancedSettingIdentifier]] = setting;
        }
        settings = temp;
    });
    return settings;
}

+ (NSArray<NSDictionary *> *)sortedAdvancedSettings {
    static NSArray *sortedAdvancedSettings;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSArray *advancedSettings = [self advancedSettings];
        sortedAdvancedSettings = [advancedSettings sortedArrayUsingSelector:@selector(compareAdvancedSettingDicts:)];
    });
   return sortedAdvancedSettings;
}

// All presentation and search text comes from the same definition as editing.
+ (NSString *)searchTextForSetting:(NSDictionary *)setting {
    return [iTermSettingDefinition definitionForIdentifier:setting[kAdvancedSettingIdentifier]].searchText;
}

+ (NSArray *)groupedSettingsArrayFromSortedArray:(NSArray *)sorted {
    NSString *previousCategory = nil;
    NSMutableArray *result = [NSMutableArray array];
    for (NSDictionary *dict in sorted) {
        iTermSettingDefinition *definition = [iTermSettingDefinition definitionForIdentifier:dict[kAdvancedSettingIdentifier]];
        NSString *thisCategory = definition.category;
        if (![thisCategory isEqualToString:previousCategory]) {
            previousCategory = thisCategory;
            [result addObject:thisCategory];
        }
        NSMutableDictionary *temp = [dict mutableCopy];
        temp[kAdvancedSettingDescription] = definition.localizedDescription;
        [result addObject:temp];
    }
    return result;
}

+ (NSArray<NSDictionary *> *)advancedSettings {
    return [iTermSettingDefinition.all valueForKey:@"dictionary"];
}

- (iTermSettingDefinition *)definitionForRow:(NSInteger)row {
    NSArray *settings = self.filteredAdvancedSettings;
    if (row < 0 || row >= settings.count || ![settings[row] isKindOfClass:NSDictionary.class]) { return nil; }
    return [iTermSettingDefinition definitionForIdentifier:settings[row][kAdvancedSettingIdentifier]];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    // For reasons I don't understand the tableview outlives this view by a small amount.
    // To reproduce, select a row in advanced prefs. Switch to the profiles tab. Press esc to close
    // the prefs window. Doesn't reproduce all the time.
    _tableView.delegate = nil;
    _tableView.dataSource = nil;
}

- (void)awakeFromNib {
    _resetColumn = [[NSTableColumn alloc] initWithIdentifier:@"reset"];
    [_tableView addTableColumn:_resetColumn];
    _tableView.style = NSTableViewStylePlain;
    _tableView.columnAutoresizingStyle = NSTableViewNoColumnAutoresizing;
    _tableView.selectionHighlightStyle = NSTableViewSelectionHighlightStyleNone;
    _tableView.usesAlternatingRowBackgroundColors = NO;
    _tableView.backgroundColor = NSColor.windowBackgroundColor;
    // Scroll the complete page, including its filter and instructions. Keep
    // the table as a document child so AppKit still recycles visible rows.
    _pageScrollView = _tableView.enclosingScrollView;
    _pageScrollView.borderType = NSNoBorder;
    _pageScrollView.drawsBackground = NO;
    _pageScrollView.hasVerticalScroller = YES;
    _pageScrollView.hasHorizontalScroller = NO;
    _pageScrollView.accessibilityIdentifier = @"ExpertSettingsPage";
    _pageDocument = [[iTermAdvancedSettingsDocumentView alloc] init];
    [_tableView removeFromSuperview];
    _pageScrollView.documentView = _pageDocument;
    for (NSView *control in @[_searchField, _excludeDefaults, _tableView]) {
        [control removeFromSuperview];
        control.autoresizingMask = NSViewNotSizable;
        [_pageDocument addSubview:control];
    }
    _searchField.placeholderString = NSLocalizedString(@"Filter expert settings", @"Expert settings search");
    _editingHelp = [NSTextField wrappingLabelWithString:NSLocalizedString(
        @"Changes are saved when edited. Some settings require a restart. Check a box to enable a Boolean setting; enter numbers or text in the value field. Bold names indicate values changed from their defaults. Reset restores the factory value; hover over a name to see its source and default.",
        @"Expert settings editing instructions")];
    _editingHelp.font = [NSFont systemFontOfSize:12];
    _editingHelp.textColor = NSColor.secondaryLabelColor;
    [_pageDocument addSubview:_editingHelp];
    [_tableView setFloatsGroupRows:NO];
    [_tableView setGridColor:[NSColor clearColor]];
    [_tableView setGridStyleMask:NSTableViewGridNone];
    [_tableView setIntercellSpacing:NSMakeSize(0, 0)];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(advancedSettingsDidChange:)
                                                 name:iTermAdvancedSettingsDidChange
                                               object:nil];
}

- (void)viewDidLayout {
    [super viewDidLayout];
    [self layoutSettingsPage];
}

- (void)layoutSettingsPage {
    _pageScrollView.frame = self.view.bounds;
    const CGFloat pageWidth = _pageScrollView.contentSize.width;
    const CGFloat width = MAX(0, pageWidth - 64);
    const CGFloat checkboxWidth = MAX(192, _excludeDefaults.intrinsicContentSize.width);
    _searchField.frame = NSMakeRect(32, 6, MAX(160, width - checkboxWidth - 12), 26);
    _excludeDefaults.frame = NSMakeRect(32 + width - checkboxWidth, 8, checkboxWidth, 22);
    const CGFloat helpHeight = ceil([_editingHelp.cell cellSizeForBounds:NSMakeRect(0, 0, width, CGFLOAT_MAX)].height);
    _editingHelp.frame = NSMakeRect(32, 44, width, helpHeight);
    _valueColumn.width = 180;
    _resetColumn.width = 80;
    const CGFloat settingWidth = MAX(200, width - _valueColumn.width - _resetColumn.width);
    if (_settingColumn.width != settingWidth) {
        _settingColumn.width = settingWidth;
        [_tableView noteHeightOfRowsWithIndexesChanged:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, _tableView.numberOfRows)]];
    }
    const NSInteger rows = _tableView.numberOfRows;
    const CGFloat tableHeight = rows ? NSMaxY([_tableView rectOfRow:rows - 1]) : 0;
    _tableView.frame = NSMakeRect(32, NSMaxY(_editingHelp.frame) + 16, width, tableHeight);
    _pageDocument.frame = NSMakeRect(0, 0, pageWidth,
                                    MAX(_pageScrollView.contentSize.height, NSMaxY(_tableView.frame) + 20));
    [_pageScrollView reflectScrolledClipView:_pageScrollView.contentView];
}

- (void)reloadSettings {
    _filteredAdvancedSettings = nil;
    [_tableView reloadData];
    [self layoutSettingsPage];
}

- (NSMutableAttributedString *)attributedStringForString:(NSString *)string
                                                    size:(CGFloat)size
                                               topMargin:(CGFloat)topMargin
                                                selected:(BOOL)selected
                                                    bold:(BOOL)bold {
    NSDictionary *spacerAttributes = @{ NSFontAttributeName: [NSFont systemFontOfSize:topMargin] };
    NSAttributedString *topSpacer = [[NSAttributedString alloc] initWithString:@"\n"
                                                                    attributes:spacerAttributes];
    NSColor *textColor;
    if (selected) {
        textColor = [NSColor selectedMenuItemTextColor];
    } else {
        textColor = [NSColor labelColor];
    }
    NSDictionary *attributes =
        @{ NSFontAttributeName: bold ? [NSFont boldSystemFontOfSize:size] : [NSFont systemFontOfSize:size],
           NSForegroundColorAttributeName: textColor };
    NSAttributedString *title = [[NSAttributedString alloc] initWithString:string
                                                                attributes:attributes];
    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
    [result appendAttributedString:topSpacer];
    [result appendAttributedString:title];
    return result;
}

- (NSAttributedString *)attributedStringForGroupNamed:(NSString *)groupName {
    return [self attributedStringForString:groupName size:17 topMargin:16 selected:NO bold:YES];
}

- (iTermTableViewTextField *)viewForImmutableAttributedString:(NSAttributedString *)attributedString
                                                     selected:(NSAttributedString *)selectedAttributedString{
    iTermTableViewTextField *textField = [_tableView makeViewWithIdentifier:@"attributedstring" owner:self] ?: [[iTermTableViewTextField alloc] init];
    textField.delegate = nil;
    textField.identifier = @"attributedstring";
    textField.usesSingleLineMode = NO;
    textField.regularAttributedString = attributedString;
    textField.selectedAttributedString = attributedString;
    textField.attributedStringValue = attributedString;
    textField.bezeled = NO;
    textField.editable = NO;
    textField.selectable = NO;
    textField.drawsBackground = NO;
    return textField;
}

- (NSView *)onOffViewWithValue:(BOOL)on row:(int)row {
    NSButton *button = [_tableView makeViewWithIdentifier:@"onoff" owner:self] ?:
        [NSButton checkboxWithTitle:@"" target:self action:@selector(toggleOnOff:)];
    button.tag = row;
    button.target = self;
    button.action = @selector(toggleOnOff:);
    button.identifier = @"onoff";
    button.state = on ? NSControlStateValueOn : NSControlStateValueOff;
    NSDictionary *setting = [self filteredAdvancedSettings][row];
    button.accessibilityLabel = [setting[kAdvancedSettingDescription] componentsSeparatedByString:@"\n"].firstObject;
    button.accessibilityIdentifier = setting[kAdvancedSettingIdentifier];
    return button;
}

- (void)toggleOnOff:(NSButton *)sender {
    if (![[self definitionForRow:sender.tag] writeValue:@(sender.state == NSControlStateValueOn)]) {
        DLog(@"Could not update protected expert setting");
    }
    [self advancedSettingsDidChange:nil];
}

// 0 = unknown, 1 = off, 2 = on
- (NSView *)tristateViewWithValue:(int)tristate row:(int)row {
    NSPopUpButton *button = [_tableView makeViewWithIdentifier:@"tristate" owner:self] ?: [[NSPopUpButton alloc] init];
    button.tag = row;
    [button setTarget:self];
    [button setAction:@selector(toggleTristate:)];
    button.identifier = @"tristate";
    [button.menu removeAllItems];
    [button.menu addItemWithTitle:NSLocalizedString(@"Unspecified", @"Advanced setting value") action:nil keyEquivalent:@""];
    [button.menu addItemWithTitle:NSLocalizedString(@"No", @"Advanced setting value") action:nil keyEquivalent:@""];
    [button.menu addItemWithTitle:NSLocalizedString(@"Yes", @"Advanced setting value") action:nil keyEquivalent:@""];

    [button selectItemAtIndex:tristate];
    return button;
}

- (void)toggleTristate:(NSPopUpButton *)sender {
    id value = sender.indexOfSelectedItem == 0 ? NSNull.null : @(sender.indexOfSelectedItem == 2);
    if (![[self definitionForRow:sender.tag] writeValue:value]) { DLog(@"Could not update expert tristate"); }
    [self advancedSettingsDidChange:nil];
}

- (NSView *)enumViewWithValue:(int)value options:(NSArray<NSString *> *)options row:(int)row {
    NSPopUpButton *button = [_tableView makeViewWithIdentifier:@"enum" owner:self] ?: [[NSPopUpButton alloc] init];
    button.tag = row;
    [button setTarget:self];
    [button setAction:@selector(changeEnum:)];
    button.identifier = @"enum";
    [button.menu removeAllItems];
    for (NSString *title in options) {
        [button.menu addItemWithTitle:title action:nil keyEquivalent:@""];
    }
    if (value >= 0 && value < options.count) {
        [button selectItemAtIndex:value];
    }
    return button;
}

- (void)changeEnum:(NSPopUpButton *)sender {
    if (![[self definitionForRow:sender.tag] writeValue:@(sender.indexOfSelectedItem)]) {
        DLog(@"Could not update expert setting choice");
    }
    [self advancedSettingsDidChange:nil];
}

- (void)resetSetting:(NSButton *)sender {
    iTermSettingDefinition *definition = [self definitionForRow:sender.tag];
    [self.view.window makeFirstResponder:nil];
    if (![definition reset]) { DLog(@"Could not reset protected expert setting %@", definition.identifier); }
    [self reloadSettings];
}

- (iTermTableViewTextFieldWrapper *)viewForMutableString:(NSString *)string row:(int)row {
    iTermTableViewTextFieldWrapper *wrapper = [_tableView makeViewWithIdentifier:@"mutablestring" owner:self] ?: [[iTermTableViewTextFieldWrapper alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
    wrapper.ignoreBackgroundStyle = YES;
    wrapper.onEndEditing = nil;
    wrapper.frame = NSMakeRect(0, 0, 100, 100);
    iTermTableViewTextField *textField = wrapper.subviews.firstObject ?: [[iTermTableViewTextField alloc] init];
    [wrapper addSubview:textField];
    textField.tag = row;
    textField.delegate = self;
    textField.identifier = @"mutablestring";
    textField.editable = YES;
    textField.selectable = YES;
    textField.stringValue = string;
    NSDictionary *setting = [self filteredAdvancedSettings][row];
    NSString *type = setting.advancedSettingType == kiTermAdvancedSettingTypeInteger ? NSLocalizedString(@"Integer", @"Setting type") :
        setting.advancedSettingType == kiTermAdvancedSettingTypeFloat ? NSLocalizedString(@"Number", @"Setting type") :
        NSLocalizedString(@"Text", @"Setting type");
    textField.placeholderString = type;
    textField.accessibilityLabel = [NSString stringWithFormat:@"%@ — %@", setting[kAdvancedSettingIdentifier], type];
    textField.toolTip = [NSString stringWithFormat:NSLocalizedString(@"Type: %@ · Default: %@", @"Setting type and default"),
                        type, setting[kAdvancedSettingDefaultValue]];
    textField.bezeled = YES;
    textField.drawsBackground = YES;
    textField.backgroundColor = [NSColor textBackgroundColor];
    textField.textColor = [NSColor labelColor];
    textField.usesSingleLineMode = YES;
    [textField sizeToFit];
    textField.frame = NSMakeRect(0, (wrapper.frame.size.height - textField.frame.size.height) / 2.0, wrapper.frame.size.width, textField.frame.size.height);
    wrapper.autoresizesSubviews = YES;
    textField.autoresizingMask = (NSViewWidthSizable | NSViewMinYMargin | NSViewMaxYMargin);
    return wrapper;
}

- (BOOL)description:(NSString *)description matchesQuery:(NSArray *)queryWords {
    for (NSString *word in queryWords) {
        if (word.length == 0) {
            continue;
        }
        if ([description rangeOfString:word options:NSCaseInsensitiveSearch].location == NSNotFound) {
            return NO;
        }
    }
    return YES;
}

- (NSArray *)filteredAdvancedSettings {
    if (!_filteredAdvancedSettings) {
        NSArray *settings;

        if (_searchField.stringValue.length == 0) {
            settings = [[self class] sortedAdvancedSettings];
        } else {
            NSMutableArray *result = [NSMutableArray array];
            NSArray *parts = [_searchField.stringValue componentsSeparatedByString:@" "];
            NSArray *sortedSettings = [[self class] sortedAdvancedSettings];
            for (NSDictionary *dict in sortedSettings) {
                NSString *description = [self.class searchTextForSetting:dict];
                if ([self description:description matchesQuery:parts]) {
                    [result addObject:dict];
                }
            }

            settings = result;
        }
        if (_excludeDefaults.state == NSControlStateValueOn) {
            settings = [settings filteredArrayUsingBlock:^BOOL(id obj) {
                NSDictionary *dict = [NSDictionary castFrom:obj];
                if (!dict) {
                    return YES;
                }
                return [self isModifiedSetting:dict];
            }];
        }
        _filteredAdvancedSettings = [[self class] groupedSettingsArrayFromSortedArray:settings];
    }

    return _filteredAdvancedSettings;
}

- (void)advancedSettingsDidChange:(NSNotification *)notification {
    if (dispatch_queue_get_label(NULL) != dispatch_queue_get_label(dispatch_get_main_queue())) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self advancedSettingsDidChange:notification];
        });
        return;
    }
    id firstResponder = self.view.window.firstResponder;
    if ([firstResponder isKindOfClass:[NSTextView class]]) {
        if ([[firstResponder delegate] isKindOfClass:[iTermTableViewTextField class]]) {
            return;
        }
    }
    [self reloadSettings];
}

#pragma mark - Actions

- (IBAction)toggleExcludeDefaults:(id)sender {
    [self reloadSettings];
}

#pragma mark - NSTableViewDelegate

- (void)tableViewColumnDidResize:(NSNotification *)notification {
    [_tableView noteHeightOfRowsWithIndexesChanged:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, _tableView.numberOfRows)]];
}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row {
    NSArray *settings = [self filteredAdvancedSettings];
    id obj = settings[row];
    if ([obj isKindOfClass:[NSString class]]) {
        return [[self attributedStringForGroupNamed:obj] size].height + 14;
    } else {
        NSAttributedString *attributedString = [self attributedStringForSettingAtRow:row selected:NO];
        CGFloat height = [attributedString heightForWidth:tableView.tableColumns[0].width] + 8;
        return MAX(30, height);
    }
}

- (NSAttributedString *)attributedStringForSettingWithName:(NSString *)description
                                                  subtitle:(NSString *)subtitle
                                                  modified:(BOOL)modified {
    NSMutableAttributedString *attributedDescription =
    [self attributedStringForString:description
                               size:[NSFont systemFontSize]
                          topMargin:2
                           selected:NO
                               bold:modified];
    if (subtitle) {
        NSColor *color = NSColor.secondaryLabelColor;
        NSDictionary *attributes = @{ NSForegroundColorAttributeName: color,
                                      NSFontAttributeName: [NSFont systemFontOfSize:11] };
        NSAttributedString *attributedSubtitle =
        [[NSAttributedString alloc] initWithString:subtitle
                                        attributes:attributes];
        [attributedDescription appendAttributedString:attributedSubtitle];
    }
    return attributedDescription;
}

- (NSAttributedString *)attributedStringForSettingAtRow:(NSInteger)row selected:(BOOL)selected {
    NSArray *settings = [self filteredAdvancedSettings];
    NSString *description = settings[row][kAdvancedSettingDescription];
    NSUInteger newline = [description rangeOfString:@"\n"].location;
    NSString *subtitle = nil;
    if (newline != NSNotFound) {
        subtitle = [description substringFromIndex:newline];
        description = [description substringToIndex:newline];
    }
    return [self attributedStringForSettingWithName:description subtitle:subtitle
                                           modified:[self isModifiedSetting:settings[row]]];
}

- (BOOL)isModifiedSetting:(NSDictionary *)setting {
    return [iTermSettingDefinition definitionForIdentifier:setting[kAdvancedSettingIdentifier]].isModified;
}

- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row { return NO; }

- (id)valueInDictionary:(NSDictionary *)dict {
    return [iTermSettingDefinition definitionForIdentifier:dict[kAdvancedSettingIdentifier]].currentValue;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    NSArray *settings = [self filteredAdvancedSettings];
    id obj = settings[row];
    if ([obj isKindOfClass:[NSString class]]) {
        // AppKit requests a spanning group header with no table column.
        if (tableColumn && tableColumn != _settingColumn) { return nil; }
        return [self viewForImmutableAttributedString:[self attributedStringForGroupNamed:obj]
                                             selected:[self attributedStringForGroupNamed:obj]];
    }

    if (tableColumn == _settingColumn) {

        iTermTableViewTextField *textField = [self viewForImmutableAttributedString:[self attributedStringForSettingAtRow:row selected:NO]
                                                                           selected:[self attributedStringForSettingAtRow:row selected:YES]];
        textField.accessibilityIdentifier = obj[kAdvancedSettingIdentifier];
        iTermSettingDefinition *definition = [self definitionForRow:row];
        textField.toolTip = [NSString stringWithFormat:NSLocalizedString(@"%@\nSource: %@ · Default: %@", @"Setting value source"),
                             definition.identifier, definition.valueOrigin, definition.defaultDisplayValue];
        return textField;
    } else if (tableColumn == _resetColumn) {
        NSButton *button = [_tableView makeViewWithIdentifier:@"reset" owner:self] ?:
            [NSButton buttonWithTitle:NSLocalizedString(@"Reset", @"Reset one setting") target:self action:@selector(resetSetting:)];
        button.identifier = @"reset";
        button.tag = row;
        button.hidden = ![self definitionForRow:row].canReset;
        button.accessibilityLabel = [NSString stringWithFormat:NSLocalizedString(@"Reset %@ to its factory default", @"Reset setting accessibility"),
                                     [self definitionForRow:row].title];
        return button;
    } else if (tableColumn == _valueColumn) {
        NSDictionary *dict = settings[row];
        NSObject *value = [self valueInDictionary:dict];
        if (!value) {
            value = dict[kAdvancedSettingDefaultValue];
        }
        switch ([dict advancedSettingType]) {
            case kiTermAdvancedSettingTypeBoolean: {
                NSNumber *n = (NSNumber *)value;
                return [self onOffViewWithValue:n.boolValue row:row];
            }
            case kiTermAdvancedSettingTypeOptionalBoolean: {
                int tristate;
                if ([value isKindOfClass:[NSNull class]]) {
                    tristate = 0;
                } else if (![(NSNumber *)value boolValue]) {
                    tristate = 1;
                } else {
                    tristate = 2;
                }
                return [self tristateViewWithValue:tristate row:row];
            }

            case kiTermAdvancedSettingTypeIntEnum: {
                NSNumber *n = (NSNumber *)value;
                return [self enumViewWithValue:n.intValue
                                       options:[self definitionForRow:row].options
                                           row:row];
            }

            case kiTermAdvancedSettingTypeFloat:
            case kiTermAdvancedSettingTypeInteger: {
                iTermTableViewTextFieldWrapper *wrapper = [self viewForMutableString:[NSString stringWithFormat:@"%@", value] row:row];
                NSTableRowView *rowView = [tableView rowViewAtRow:row makeIfNecessary:NO];
                if (rowView) {
                    wrapper.backgroundStyle = [rowView interiorBackgroundStyle];
                }
                return wrapper;
            }

            case kiTermAdvancedSettingTypeString: {
                iTermTableViewTextFieldWrapper *wrapper = [self viewForMutableString:(NSString *)value row:row];
                NSTableRowView *rowView = [tableView rowViewAtRow:row makeIfNecessary:NO];
                if (rowView) {
                    wrapper.backgroundStyle = [rowView interiorBackgroundStyle];
                }
                if (dict[kAdvancedSettingSetter]) {
                    iTermSettingDefinition *definition = [self definitionForRow:row];
                    wrapper.onEndEditing = ^(NSString *value) {
                        if (![definition writeText:value]) { DLog(@"Could not update protected expert string %@", definition.identifier); }
                    };
                }

                return wrapper;
            }
        }
    } else {
        return nil;
    }
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return [[self filteredAdvancedSettings] count];
}


- (BOOL)tableView:(NSTableView *)aTableView
      shouldEditTableColumn:(NSTableColumn *)aTableColumn
              row:(NSInteger)rowIndex {
    NSArray *settings = [self filteredAdvancedSettings];
    id obj = settings[rowIndex];
    if ([obj isKindOfClass:[NSString class]]) {
        return NO;
    }

    return aTableColumn == _valueColumn;
}

- (BOOL)tableView:(NSTableView *)tableView isGroupRow:(NSInteger)row {
    NSArray *settings = [self filteredAdvancedSettings];
    id obj = settings[row];
    return ([obj isKindOfClass:[NSString class]]);
}

#pragma mark - NSControl Delegate

- (void)controlTextDidChange:(NSNotification *)aNotification {
    if ([aNotification object] == _searchField) {
        [self reloadSettings];
    } else {
        NSTextField *textField = aNotification.object;
        const NSInteger row = textField.tag;
        if (row < 0 || row >= [self filteredAdvancedSettings].count) { return; }
        iTermSettingDefinition *definition = [self definitionForRow:row];
        if (definition.isSecure) { return; } // Protected strings commit on end editing.
        const BOOL valid = [definition writeText:textField.stringValue];
        textField.textColor = valid ? NSColor.labelColor : NSColor.systemRedColor;
        if (!valid) { return; }
        [_tableView reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:row]
                             columnIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 1)]];
        [_tableView reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:row]
                             columnIndexes:[NSIndexSet indexSetWithIndex:2]];
    }
}

- (void)controlTextDidBeginEditing:(NSNotification *)obj {
    iTermTableViewTextField *textField = [iTermTableViewTextField castFrom:obj.object];
    [textField setEditing:YES];
}

- (void)controlTextDidEndEditing:(NSNotification *)obj {
    if ([obj object] == _searchField) {
        return;
    }
    iTermTableViewTextField *textField = obj.object;
    const NSInteger row = textField.tag;
    NSArray *settings = [self filteredAdvancedSettings];
    if (row < 0 || row >= settings.count) {
        return;
    }
    NSDictionary *dict = settings[row];
    textField.textColor = NSColor.labelColor;
    switch ([dict advancedSettingType]) {
        case kiTermAdvancedSettingTypeBoolean:
        case kiTermAdvancedSettingTypeOptionalBoolean:
        case kiTermAdvancedSettingTypeIntEnum:
            RLog(@"A popup ended editing somehow");
            break;

        case kiTermAdvancedSettingTypeFloat:
            textField.stringValue = [[self valueInDictionary:dict] description] ?: [dict[kAdvancedSettingDefaultValue] description];
            break;

        case kiTermAdvancedSettingTypeInteger:
            textField.stringValue = [[self valueInDictionary:dict] description] ?: [dict[kAdvancedSettingDefaultValue] description];
            break;

        case kiTermAdvancedSettingTypeString:
            [textField setEditing:NO];
            break;
    }

    NSTableRowView *rowView = [_tableView rowViewAtRow:row makeIfNecessary:NO];
    if (rowView) {
        textField.backgroundStyle = [rowView interiorBackgroundStyle];
    }
    [textField setEditing:NO];
    [self reloadSettings];
}

#pragma mark - iTermSearchableViewController

- (NSString *)documentOwnerIdentifier {
    return NSStringFromClass(self.class);
}

- (NSArray<iTermPreferencesSearchDocument *> *)searchableViewControllerDocuments {
    if (!_docs) {
        _docs = [[iTermAdvancedSettingsViewController sortedAdvancedSettings] mapWithBlock:^id(NSDictionary *dict) {
            iTermSettingDefinition *definition = [iTermSettingDefinition definitionForIdentifier:dict[kAdvancedSettingIdentifier]];
            iTermPreferencesSearchDocument *doc = [iTermPreferencesSearchDocument
                documentWithDisplayName:definition.title identifier:definition.identifier
                keywordPhrases:@[definition.searchText]];
            doc.pathComponents = @[definition.category];
            doc.queryIndependentScore = -1;
            doc.ownerIdentifier = self.documentOwnerIdentifier;
            return doc;
        }];
    }
    return _docs;
}

- (NSInteger)indexOfIdentifier:(NSString *)identifier {
    return [self.filteredAdvancedSettings indexOfObjectPassingTest:^BOOL(NSDictionary * _Nonnull dict, NSUInteger idx, BOOL * _Nonnull stop) {
        if (![dict isKindOfClass:[NSDictionary class]]) {
            return NO;
        }
        return [dict[kAdvancedSettingIdentifier] isEqualToString:identifier];
    }];
}

- (NSView *)searchableViewControllerRevealItemForDocument:(iTermPreferencesSearchDocument *)document
                                                 forQuery:(NSString *)query
                                            willChangeTab:(BOOL *)willChangeTab {
    *willChangeTab = NO;
    NSUInteger index = [self indexOfIdentifier:document.identifier];
    if (index == NSNotFound) {
        // A global search result must not be hidden by the local filter.
        _searchField.stringValue = @"";
        _excludeDefaults.state = NSControlStateValueOff;
        [self reloadSettings];
        index = [self indexOfIdentifier:document.identifier];
        
        if (index == NSNotFound) {
            // Pull the query from the prefs search engine and try again
            _searchField.stringValue = query;
            [self reloadSettings];
            return _tableView.enclosingScrollView;
        }
    }
    [self layoutSettingsPage];
    [_tableView deselectAll:nil];
    [_tableView scrollRowToVisible:index];
    return [_tableView viewAtColumn:0 row:index makeIfNecessary:YES];
}

@end
