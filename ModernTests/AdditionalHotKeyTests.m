#import <XCTest/XCTest.h>

#import "iTermHotkeyPreferencesWindowController.h"
#import "iTermShortcut.h"
#import "iTermShortcutInputView.h"

// NIB-owned types are looked up by their stable Objective-C runtime names.
// Declare the row's selector contract without importing unrelated generated APIs.
@protocol AdditionalHotKeyRow <NSObject>
@property(nonatomic, strong) iTermShortcut *shortcut;
@property(nonatomic, copy) NSArray<NSDictionary *> *descriptorsInUseByOtherProfiles;
@property(nonatomic, readonly) BOOL isDuplicate;
+ (instancetype)objectValueWithShortcut:(iTermShortcut *)shortcut
                       inUseDescriptors:(NSArray<NSDictionary *> *)descriptors;
@end
@interface AdditionalHotKeyTests : XCTestCase
@end

@implementation AdditionalHotKeyTests

- (Class<AdditionalHotKeyRow>)rowClass {
    Class rowClass = NSClassFromString(@"iTermAdditionalHotKeyObjectValue");
    XCTAssertNotNil(rowClass);
    return rowClass;
}

- (iTermShortcut *)shortcutWithCode:(NSUInteger)code characters:(NSString *)characters modifiers:(NSEventModifierFlags)modifiers {
    return [[iTermShortcut alloc] initWithKeyCode:code
                                     hasKeyCode:YES
                                      modifiers:modifiers
                                     characters:characters
                    charactersIgnoringModifiers:characters];
}

- (void)testDuplicatesCompareDescriptorsByValue {
    iTermShortcut *shortcut = [self shortcutWithCode:12 characters:@"q" modifiers:NSEventModifierFlagCommand];
    iTermShortcut *other = [self shortcutWithCode:12 characters:@"Q" modifiers:NSEventModifierFlagCommand];
    id<AdditionalHotKeyRow> row =
        [[self rowClass] objectValueWithShortcut:shortcut inUseDescriptors:@[other.descriptor]];
    XCTAssertTrue(row.isDuplicate);
    XCTAssertEqual(row.shortcut, shortcut);
    shortcut.keyCode = 13;
    XCTAssertFalse(row.isDuplicate);
}

- (void)testDifferentModifiersDoNotConflict {
    iTermShortcut *shortcut = [self shortcutWithCode:12 characters:@"q" modifiers:NSEventModifierFlagCommand];
    iTermShortcut *other = [self shortcutWithCode:12 characters:@"q" modifiers:NSEventModifierFlagOption];
    id<AdditionalHotKeyRow> row =
        [[self rowClass] objectValueWithShortcut:shortcut inUseDescriptors:@[other.descriptor]];
    XCTAssertFalse(row.isDuplicate);
}

- (void)testUnassignedAndDescriptorlessShortcutsDoNotConflict {
    iTermShortcut *other = [self shortcutWithCode:12 characters:@"q" modifiers:NSEventModifierFlagCommand];
    id<AdditionalHotKeyRow> row =
        [[self rowClass] objectValueWithShortcut:nil inUseDescriptors:@[other.descriptor]];
    XCTAssertFalse(row.isDuplicate);
    row.shortcut = [[iTermShortcut alloc] init];
    XCTAssertFalse(row.isDuplicate);
    // Existing descriptor rules require characters ignoring modifiers, even for a key code.
    row.shortcut.keyCode = 12;
    row.shortcut.modifiers = NSEventModifierFlagCommand;
    row.shortcut.characters = @"´";
    XCTAssertFalse(row.isDuplicate);
}

- (void)testDescriptorListCanBeReplacedOrCleared {
    iTermShortcut *shortcut = [self shortcutWithCode:12 characters:@"q" modifiers:NSEventModifierFlagCommand];
    id<AdditionalHotKeyRow> row =
        [[self rowClass] objectValueWithShortcut:shortcut inUseDescriptors:nil];
    XCTAssertFalse(row.isDuplicate);
    row.descriptorsInUseByOtherProfiles = @[shortcut.descriptor];
    XCTAssertTrue(row.isDuplicate);
    row.descriptorsInUseByOtherProfiles = @[];
    XCTAssertFalse(row.isDuplicate);
}

- (NSTableCellView *)cellWithInput:(iTermShortcutInputView **)input warning:(NSView **)warning {
    Class cellClass = NSClassFromString(@"iTermAdditionalHotKeyTableCellView");
    XCTAssertNotNil(cellClass);
    NSTableCellView *cell = [[cellClass alloc] initWithFrame:NSMakeRect(0, 0, 260, 32)];
    iTermShortcutInputView *shortcutInput = [[iTermShortcutInputView alloc] initWithFrame:NSMakeRect(0, 0, 220, 22)];
    NSView *duplicateWarning = [[NSView alloc] initWithFrame:NSMakeRect(230, 0, 20, 20)];
    [cell addSubview:shortcutInput];
    [cell addSubview:duplicateWarning];
    [cell setValue:shortcutInput forKey:@"shortcutInput"];
    [cell setValue:duplicateWarning forKey:@"duplicateWarning"];
    [cell awakeFromNib];
    *input = shortcutInput;
    *warning = duplicateWarning;
    return cell;
}

- (void)testCellDisplaysShortcutAndClearsReusedRow {
    iTermShortcutInputView *input;
    NSView *warning;
    NSTableCellView *cell = [self cellWithInput:&input warning:&warning];
    iTermShortcut *shortcut = [self shortcutWithCode:12 characters:@"q" modifiers:NSEventModifierFlagCommand];
    id<AdditionalHotKeyRow> row =
        [[self rowClass] objectValueWithShortcut:shortcut inUseDescriptors:@[shortcut.descriptor]];
    cell.objectValue = row;
    XCTAssertEqual(cell.objectValue, row);
    XCTAssertEqualObjects(input.stringValue, shortcut.stringValue);
    XCTAssertFalse(warning.hidden);
    cell.objectValue = nil;
    XCTAssertNil(cell.objectValue);
    XCTAssertEqualObjects(input.stringValue, @"");
    XCTAssertTrue(warning.hidden);
}

- (void)testCellConfiguresInputAndPropagatesSelectionAppearance {
    iTermShortcutInputView *input;
    NSView *warning;
    NSTableCellView *cell = [self cellWithInput:&input warning:&warning];
    XCTAssertEqualObjects(input.purpose, @"as a hotkey");
    XCTAssertEqual((id)input.shortcutDelegate, cell);
    cell.backgroundStyle = NSBackgroundStyleEmphasized;
    XCTAssertEqual(input.backgroundStyle, NSBackgroundStyleEmphasized);
    cell.backgroundStyle = NSBackgroundStyleNormal;
    XCTAssertEqual(input.backgroundStyle, NSBackgroundStyleNormal);
}

- (void)testEditingAndClearingMutateSharedShortcutAndRefreshConflict {
    iTermShortcutInputView *input;
    NSView *warning;
    NSTableCellView *cell = [self cellWithInput:&input warning:&warning];
    iTermShortcut *shortcut = [self shortcutWithCode:13 characters:@"w" modifiers:NSEventModifierFlagCommand];
    iTermShortcut *conflict = [self shortcutWithCode:12 characters:@"q" modifiers:NSEventModifierFlagCommand];
    cell.objectValue = [[self rowClass] objectValueWithShortcut:shortcut
                                                               inUseDescriptors:@[conflict.descriptor]];
    XCTAssertTrue(warning.hidden);
    NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown
                                    location:NSZeroPoint
                               modifierFlags:NSEventModifierFlagCommand
                                   timestamp:0
                                windowNumber:0
                                     context:nil
                                  characters:@"q"
                 charactersIgnoringModifiers:@"q"
                                   isARepeat:NO
                                     keyCode:12];
    [input.shortcutDelegate shortcutInputView:input didReceiveKeyPressEvent:event];
    XCTAssertEqual(shortcut.keyCode, 12u);
    XCTAssertEqualObjects(shortcut.characters, @"q");
    XCTAssertFalse(warning.hidden);
    [input.shortcutDelegate shortcutInputView:input didReceiveKeyPressEvent:nil];
    XCTAssertFalse(shortcut.isAssigned);
    XCTAssertTrue(warning.hidden);
}

- (void)testCellAndModelReleaseWithoutDelegateCycle {
    __weak NSTableCellView *weakCell;
    __weak id<AdditionalHotKeyRow> weakRow;
    @autoreleasepool {
        iTermShortcutInputView *input;
        NSView *warning;
        NSTableCellView *cell = [self cellWithInput:&input warning:&warning];
        cell.objectValue = [[self rowClass] objectValueWithShortcut:nil inUseDescriptors:nil];
        weakCell = cell;
        weakRow = cell.objectValue;
    }
    XCTAssertNil(weakCell);
    XCTAssertNil(weakRow);
}

- (void)testPreferencesNibInstantiatesSwiftCellAndConnectsOutlets {
    iTermHotkeyPreferencesWindowController *controller = [[iTermHotkeyPreferencesWindowController alloc] init];
    XCTAssertNotNil(controller.window);
    iTermShortcut *shortcut = [self shortcutWithCode:12 characters:@"q" modifiers:NSEventModifierFlagCommand];
    controller.descriptorsInUseByOtherProfiles = @[shortcut.descriptor];
    [controller setValue:[@[shortcut] mutableCopy] forKey:@"_mutableShortcuts"];
    NSTableView *table = [controller valueForKey:@"_tableView"];
    [table reloadData];
    NSTableCellView *cell = [table viewAtColumn:0 row:0 makeIfNecessary:YES];
    XCTAssertEqualObjects(NSStringFromClass(cell.class), @"iTermAdditionalHotKeyTableCellView");
    iTermShortcutInputView *input = [cell valueForKey:@"shortcutInput"];
    NSView *warning = [cell valueForKey:@"duplicateWarning"];
    XCTAssertNotNil(input);
    XCTAssertNotNil(warning);
    XCTAssertEqual((id)input.shortcutDelegate, cell);
    XCTAssertEqualObjects(input.stringValue, shortcut.stringValue);
    XCTAssertFalse(warning.hidden);
    [controller close];
}

@end
