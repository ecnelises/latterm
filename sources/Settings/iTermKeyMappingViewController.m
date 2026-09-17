//
//  iTermKeyMappingViewController.m
//  iTerm
//
//  Created by George Nachman on 4/7/14.
//
//

#import "iTermKeyMappingViewController.h"
#import "DebugLogging.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermKeyMappings.h"
#import "iTermKeystroke.h"
#import "iTermKeystrokeFormatter.h"
#import "iTermEditKeyActionWindowController.h"
#import "iTermKeyBindingAction.h"
#import "iTermPreferences.h"
#import "iTermPreferencesBaseViewController.h"
#import "iTermWarning.h"
#import "NSArray+iTerm.h"
#import "NSJSONSerialization+iTerm.h"
#import "NSTextField+iTerm.h"
#import "PreferencePanel.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static NSString *const INTERCHANGE_KEY_MAPPING_DICT = @"Key Mappings";

@implementation iTermKeyMappingViewController {
    IBOutlet NSTableView *_tableView;
    IBOutlet NSTableColumn *_keyCombinationColumn;
    IBOutlet NSTableColumn *_actionColumn;
    IBOutlet NSButton *_removeMappingButton;
    IBOutlet NSButton *_addMappingButton;
    IBOutlet NSPopUpButton *_presetsPopup;
    iTermEditKeyActionWindowController *_editActionWindowController;
    iTermModernSavePanel *_savePanel;
    // Index of row being edited. Valid after presenting the edit key mapping sheet.
    NSInteger _rowIndex;
}

- (instancetype)init {
    self = [super initWithNibName:@"iTermKeyMapping" bundle:[NSBundle bundleForClass:self.class]];
    if (self) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(keyBindingsChanged)
                                                     name:kKeyBindingsChangedNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(leaderDidChange:)
                                                     name:iTermKeyMappingsLeaderDidChange
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    _tableView.delegate = nil;
    _tableView.dataSource = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)awakeFromNib {
    _actionColumn.title = NSLocalizedString(@"Action", @"Key mapping column");
    _keyCombinationColumn.title = NSLocalizedString(@"Key Combination", @"Key mapping column");
    _presetsPopup.itemArray.firstObject.title = NSLocalizedString(@"Presets…", @"Key mapping presets");
    _addMappingButton.toolTip = NSLocalizedString(@"Add key mapping", @"Key mapping action");
    [_addMappingButton setAccessibilityLabel:_addMappingButton.toolTip];
    _removeMappingButton.toolTip = NSLocalizedString(@"Remove key mapping", @"Key mapping action");
    [_removeMappingButton setAccessibilityLabel:_removeMappingButton.toolTip];
}

- (void)keyBindingsChanged {
    [_tableView reloadData];
}

- (void)leaderDidChange:(NSNotification *)notification {
    [_tableView reloadData];
}

- (void)setPlaceholderView:(NSView *)placeholderView {
    _placeholderView = placeholderView;
    [self.placeholderView addSubview:self.view];
    self.view.frame = self.placeholderView.bounds;
    self.view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    placeholderView.autoresizesSubviews = YES;

    [_tableView setDoubleAction:@selector(doubleClick:)];
    [_tableView setTarget:self];
    NSArray* presetArray = [_delegate keyMappingPresetNames:self];
    for (NSString *name in presetArray) {
        NSMenuItem *preset = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(name, @"Key mapping preset")
                                                     action:nil keyEquivalent:@""];
        preset.representedObject = name;
        [_presetsPopup.menu addItem:preset];
    }
    if (_presetsPopup.menu.itemArray.count) {
        [_presetsPopup.menu addItem:[NSMenuItem separatorItem]];
    }
    NSMenuItem *item;
    item = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Import…", @"Key mapping action")
                                      action:@selector(importMenuItem:)
                               keyEquivalent:@""];
    item.target = self;
    [_presetsPopup.menu addItem:item];
    item = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Export…", @"Key mapping action")
                                      action:@selector(exportMenuItem:)
                               keyEquivalent:@""];
    item.target = self;
    [_presetsPopup.menu addItem:item];
}

- (void)addViewsToSearchIndex:(iTermPreferencesBaseViewController *)vc {
    [vc addViewToSearchIndex:_presetsPopup
                 displayName:@"Key binding presets"
                     phrases:@[]
                         key:nil];
}

- (void)reloadData {
    [_tableView reloadData];
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView {
    NSDictionary *dict = [_delegate keyMappingDictionary:self];
    return dict.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    static NSString *const identifier = @"KeyMappingTableViewIdentifier";
    NSTextField *result = [tableView makeViewWithIdentifier:identifier owner:self];
    if (result == nil) {
        result = [NSTextField it_textFieldForTableViewWithIdentifier:identifier];
        result.lineBreakMode = NSLineBreakByTruncatingTail;
        result.usesSingleLineMode = YES;
        result.font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
    }

    result.stringValue = [self stringValueForColumn:tableColumn row:row];
    result.toolTip = result.stringValue;
    return result;
}

- (NSString *)keyCombinationStringForKeystroke:(iTermKeystroke *)keystroke {
    return [iTermKeystrokeFormatter stringForKeystroke:keystroke];
}

- (NSString *)descriptionForKeystroke:(iTermKeystroke *)keystroke
                    bindingDictionary:(NSDictionary *)dict {
    iTermKeyBindingAction *action = [iTermKeyBindingAction withDictionary:[keystroke valueInBindingDictionary:dict]];
    return action.displayName;
}

- (NSString *)stringValueForKeyMappingOnRow:(NSInteger)rowIndex
                                     column:(NSTableColumn *)column
                          bindingDictionary:(NSDictionary *)dict {
    NSArray<iTermKeystroke *> *sortedKeystrokes = [_delegate keyMappingSortedKeystrokes:self];
    iTermKeystroke *keystroke = sortedKeystrokes[rowIndex];

    if (column == _keyCombinationColumn) {
        return [self keyCombinationStringForKeystroke:keystroke];
    }
    if (column == _actionColumn) {
        return [self descriptionForKeystroke:keystroke
                           bindingDictionary:dict];
    }
    return nil;
}

- (NSString *)stringValueForColumn:(NSTableColumn *)column row:(NSInteger)rowIndex {
    return [self stringValueForKeyMappingOnRow:rowIndex
                                      column:column
                           bindingDictionary:[_delegate keyMappingDictionary:self]];
}

#pragma mark - Modal Sheets

- (void)presentEditActionSheet:(iTermEditKeyActionWindowController *)editActionWindowController {
    _rowIndex = _tableView.selectedRow;
    [self.view.window beginSheet:editActionWindowController.window completionHandler:^(NSModalResponse returnCode) {
        [self editActionWindowCompletionHandler:editActionWindowController];
    }];
}

- (void)editActionWindowCompletionHandler:(iTermEditKeyActionWindowController *)editActionWindowController {
    if (editActionWindowController.ok) {
        [_delegate keyMapping:self
                didChangeItem:editActionWindowController.currentKeystroke
                      atIndex:_rowIndex
                     toAction:[iTermKeyBindingAction withAction:editActionWindowController.action
                                                      parameter:editActionWindowController.parameterValue
                                                          label:editActionWindowController.label
                                                       escaping:editActionWindowController.escaping
                                                      applyMode:editActionWindowController.applyMode]
                   isAddition:editActionWindowController.isNewMapping];
    }
    [editActionWindowController close];
    [_tableView reloadData];
    [editActionWindowController.window close];
}

#pragma mark - NSTableViewDelegate

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification {
    const NSUInteger numberSelected = _tableView.selectedRowIndexes.count;
    _removeMappingButton.enabled = (numberSelected > 0);
}

#pragma mark - Actions

- (IBAction)addNewMapping:(id)sender {
    iTermEditKeyActionWindowController *editActionWindowController;
    editActionWindowController =
    [[iTermEditKeyActionWindowController alloc] initWithContext:iTermVariablesSuggestionContextSession | iTermVariablesSuggestionContextApp
                                                           mode:iTermEditKeyActionWindowControllerModeKeyboardShortcut];
    editActionWindowController.isNewMapping = YES;
    [editActionWindowController setAction:KEY_ACTION_IGNORE parameter:@"" applyMode:iTermActionApplyModeCurrentSession];
    editActionWindowController.escaping = iTermSendTextEscapingCommon;
    [self presentEditActionSheet:editActionWindowController];
}

- (IBAction)removeMapping:(id)sender {
    if (_tableView.selectedRowIndexes.count == 0) {
        return;
    }
    NSIndexSet *indexes = [_tableView.selectedRowIndexes copy];
    NSMutableSet<iTermKeystroke *> *regularKeystrokes = [NSMutableSet set];
    NSArray<iTermKeystroke *> *sortedRegularKeystrokes = [_delegate keyMappingSortedKeystrokes:self];

    [indexes enumerateIndexesUsingBlock:^(NSUInteger row, BOOL * _Nonnull stop) {
        if (row < sortedRegularKeystrokes.count) {
            [regularKeystrokes addObject:sortedRegularKeystrokes[row]];
        }
    }];
    [_tableView beginUpdates];
    [_delegate keyMapping:self
         removeKeystrokes:regularKeystrokes];
    [_tableView removeRowsAtIndexes:_tableView.selectedRowIndexes withAnimation:YES];
    [_tableView endUpdates];
    [_tableView selectRowIndexes:[NSIndexSet indexSet] byExtendingSelection:NO];
}

- (void)doubleClick:(id)sender {
    NSInteger row = [_tableView clickedRow];
    if (row < 0) {
        return;
    }
    [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];

    int rowIndex = [_tableView selectedRow];
    if (rowIndex < 0) {
        [self addNewMapping:sender];
        return;
    }

    NSDictionary *dict = [_delegate keyMappingDictionary:self];
    NSArray<iTermKeystroke *> *sortedItems = [_delegate keyMappingSortedKeystrokes:self];
    if (rowIndex >= sortedItems.count) {
        return;
    }
    iTermKeystroke *keystroke = sortedItems[rowIndex];
    _editActionWindowController =
    [[iTermEditKeyActionWindowController alloc] initWithContext:iTermVariablesSuggestionContextSession | iTermVariablesSuggestionContextApp
                                                           mode:iTermEditKeyActionWindowControllerModeKeyboardShortcut];
    _editActionWindowController.currentKeystroke = keystroke;
    NSDictionary *binding = [keystroke valueInBindingDictionary:dict];
    _editActionWindowController.isNewMapping = NO;

    [_editActionWindowController setAction:(KEY_ACTION)[binding[iTermKeyBindingDictionaryKeyAction] intValue]
                                 parameter:binding[iTermKeyBindingDictionaryKeyParameter]
                                 applyMode:[binding[iTermKeyBindingDictionaryKeyApplyMode] unsignedIntegerValue]];
    iTermSendTextEscaping escaping;
    if ([binding[iTermKeyBindingDictionaryKeyVersion] intValue] == 0) {
        escaping = iTermSendTextEscapingCompatibility;
    } else if (binding[iTermKeyBindingDictionaryKeyEscaping]) {
        escaping = [binding[iTermKeyBindingDictionaryKeyEscaping] unsignedIntegerValue];
    } else {
        escaping = iTermSendTextEscapingCommon;  // v1 migration path
    }
    _editActionWindowController.escaping = escaping;
    [self presentEditActionSheet:_editActionWindowController];
}

- (IBAction)loadPresets:(id)sender {
    NSString *name = [[sender selectedItem] representedObject];
    if (!name) {
        return;
    }
    [_delegate keyMapping:self loadPresetsNamed:name];
    [_tableView reloadData];
}

#pragma mark - Import/Export

- (void)importMenuItem:(id)sender {
    iTermOpenPanel *panel = [[iTermOpenPanel alloc] init];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = NO;
    __weak __typeof(self) weakSelf = self;
    [panel beginWithFallbackWindow:self.view.window handler:^(NSModalResponse result, NSArray<NSURL *> *urls) {
        if (result == NSModalResponseOK) {
            [weakSelf importFromOpenPanel:urls.firstObject];
        }
    }];
}

- (void)importFromOpenPanel:(NSURL *)url {
    if (!url) {
        return;
    }
    NSError *error = nil;
    NSString *const content = [NSString stringWithContentsOfURL:url
                                                       encoding:NSUTF8StringEncoding
                                                          error:&error];
    if (!content) {
        XLog(@"Beep: %@", error);
        NSBeep();
        return;
    }

    id decoded = [NSJSONSerialization it_objectForJsonString:content error:&error];
    if (!decoded) {
        XLog(@"Beep: %@", error);
        NSBeep();
        return;
    }

    NSDictionary *dict = [NSDictionary castFrom:decoded];
    NSDictionary *keymappings = [NSDictionary castFrom:dict[INTERCHANGE_KEY_MAPPING_DICT]];
    NSSet<iTermKeystroke *> *keystrokesThatWillChange = [NSSet setWithArray:[keymappings.allKeys mapWithBlock:^id(id anObject) {
        return [[iTermKeystroke alloc] initWithSerialized:anObject];
    }]];

    if (![self.delegate keyMapping:self shouldImportKeystrokes:keystrokesThatWillChange]) {
        return;
    }

    for (id serialized in keymappings) {
        iTermKeystroke *keystroke = [[iTermKeystroke alloc] initWithSerialized:serialized];
        if (!keystroke.isValid) {
            continue;
        }

        NSDictionary *entry = [NSDictionary castFrom:[keystroke valueInBindingDictionary:keymappings]];
        iTermKeyBindingAction *action = [iTermKeyBindingAction withDictionary:entry];
        if (!action) {
            continue;
        }
        [self.delegate keyMapping:self
                    didChangeItem:keystroke
                          atIndex:NSNotFound
                         toAction:[iTermKeyBindingAction withAction:action.keyAction
                                                          parameter:action.parameter
                                                           escaping:action.escaping
                                                          applyMode:action.applyMode]
                       isAddition:YES];
    }

}

- (NSNumber *)removeBeforeLoading:(NSString *)thing {
    const iTermWarningSelection selection =
    [iTermWarning showWarningWithTitle:[NSString stringWithFormat:NSLocalizedString(@"Remove all key mappings before %@?", @"Key mapping import confirmation"), NSLocalizedString(thing, @"Key mapping operation")]
                               actions:@[ NSLocalizedString(@"Keep", @"Keep mappings"), NSLocalizedString(@"Remove", @"Remove mappings"), NSLocalizedString(@"Cancel", @"Cancel import") ]
                             accessory:nil
                            identifier:@"RemoveExistingGlobalKeyMappingsBeforeLoading"
                           silenceable:kiTermWarningTypePersistent
                               heading:NSLocalizedString(@"Load Preset", @"Key mapping import")
                                window:self.view.window];
    switch (selection) {
        case kiTermWarningSelection0:
            return @NO;
        case kiTermWarningSelection1:
            return @YES;
        case kiTermWarningSelection2:
            return nil;
        default:
            assert(NO);
    }
    return nil;
}

- (void)exportMenuItem:(id)sender {
    _savePanel = [[iTermModernSavePanel alloc] init];
    _savePanel.preferredSSHIdentity = SSHIdentity.localhost;
    [_savePanel setAllowedContentTypes:@[ [UTType typeWithFilenameExtension:@"itermkeymap"] ]];
    __weak __typeof(self) weakSelf = self;
    [_savePanel beginWithFallbackWindow:self.view.window handler:^(NSModalResponse response, iTermSavePanelItem *item) {
        if (response == NSModalResponseOK) {
            [weakSelf exportFromSavePanel:item];
        }
    }];
}

- (void)exportFromSavePanel:(iTermSavePanelItem *)item {
    _savePanel = nil;

    NSDictionary *const keymappings = [self.delegate keyMappingDictionary:self];
    NSDictionary *const dict = @{ INTERCHANGE_KEY_MAPPING_DICT: keymappings ?: @{} };
    NSString *json = [NSJSONSerialization it_jsonStringForObject:dict];
    [json writeToSaveItem:item completionHandler:^(NSError *error) {
        if (error) {
            XLog(@"Beep: %@", error);
            NSBeep();
            return;
        }
    }];
}

@end
