#import <XCTest/XCTest.h>
#import "PreferencePanel.h"
#import "ITAddressBookMgr.h"
#import "ProfilePreferencesViewController.h"
#import "iTermSizeRememberingView.h"
#import "iTermPreferencesSearch.h"
#import "iTermPreferencesSearchEngineResultsWindowController.h"
#import "iTermUserDefaults.h"
#import "iTermAdvancedSettingsViewController.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermOpenStyle.h"
#import "iTermKeyMappingViewController.h"
#import "iTermEditSnippetWindowController.h"
#import "iTermEditKeyActionWindowController.h"
#import "iTermActionsModel.h"
#import "iTermDynamicProfileManager.h"
#import "PointerPrefsController.h"

@interface PointerPrefsController (SettingsTests)
+ (NSDictionary *)localizedActionMap;
@end

@interface PreferencePanel (NavigationTests)
- (void)resizeWindowForTabViewItem:(NSTabViewItem *)item animated:(BOOL)animated;
- (NSArray<iTermPreferencesSearchDocument *> *)searchResults;
- (NSView *)preferencePanelContentView;
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem;
- (CGFloat)preferencePanelNavigationWidth;
- (BOOL)revealDocument:(iTermPreferencesSearchDocument *)document
        switchingTabs:(BOOL *)switchingTabs
   switchingInnerTabs:(BOOL *)switchingInnerTabs;
@end

@interface iTermAdvancedSettingsViewController (SettingsTests)
- (NSArray *)filteredAdvancedSettings;
- (void)advancedSettingsDidChange:(NSNotification *)notification;
- (void)controlTextDidChange:(NSNotification *)notification;
- (void)controlTextDidEndEditing:(NSNotification *)notification;
@end

@interface iTermKeyMappingViewController (SettingsTests)
- (void)loadPresets:(id)sender;
- (void)importFromOpenPanel:(NSURL *)url;
@end

@interface iTermEditKeyActionWindowController (SettingsTests)
- (BOOL)shouldEnableOK;
- (void)ok:(id)sender;
@end

@interface iTermDynamicProfileManager (SettingsTests)
- (void)writeModifiedProfile:(Profile *)profile toFile:(NSString *)filename;
@end

@interface SettingsKeyMappingDelegate : NSObject <iTermKeyMappingViewControllerDelegate>
@property(nonatomic, copy) NSString *loadedPreset;
@property(nonatomic) NSUInteger importedKeys;
@end
@implementation SettingsKeyMappingDelegate
- (NSDictionary *)keyMappingDictionary:(iTermKeyMappingViewController *)vc { return @{}; }
- (NSArray *)keyMappingSortedKeystrokes:(iTermKeyMappingViewController *)vc { return @[]; }
- (NSArray *)keyMappingPresetNames:(iTermKeyMappingViewController *)vc { return @[@"Factory Defaults"]; }
- (void)keyMapping:(iTermKeyMappingViewController *)vc loadPresetsNamed:(NSString *)name { self.loadedPreset = name; }
- (BOOL)keyMapping:(iTermKeyMappingViewController *)vc shouldImportKeystrokes:(NSSet *)keys { return YES; }
- (void)keyMapping:(iTermKeyMappingViewController *)vc removeKeystrokes:(NSSet *)keys {}
- (void)keyMapping:(iTermKeyMappingViewController *)vc didChangeItem:(iTermKeystroke *)key
          atIndex:(NSInteger)index toAction:(iTermKeyBindingAction *)action isAddition:(BOOL)addition {
    XCTAssertTrue(key.isValid);
    self.importedKeys++;
}
@end

@interface NSView (SettingsSidebarTests)
- (NSInteger)rowFor:(id)page;
- (void)updateProfilesWithNames:(NSArray *)names identifiers:(NSArray *)identifiers selectedIdentifier:(NSString *)selectedIdentifier;
@end

// Load package resources independently to verify their custom view classes.
@interface SettingsDropdownNibOwner : NSViewController
@property(nonatomic, weak) IBOutlet NSSearchField *searchField;
@property(nonatomic, weak) IBOutlet NSTableView *tableView;
@property(nonatomic, weak) IBOutlet NSVisualEffectView *visualEffectView;
@end
@implementation SettingsDropdownNibOwner
@end

@interface SettingsSearchDelegate : NSObject<iTermPreferencesSearchEngineResultsWindowControllerDelegate>
@property(nonatomic, strong) iTermPreferencesSearchDocument *previewed;
@property(nonatomic, strong) iTermPreferencesSearchDocument *activated;
@end
@implementation SettingsSearchDelegate
- (void)preferencesSearchEngineResultsDidSelectDocument:(iTermPreferencesSearchDocument *)document { self.previewed = document; }
- (void)preferencesSearchEngineResultsDidActivateDocument:(iTermPreferencesSearchDocument *)document { self.activated = document; }
@end

@interface SettingsNavigationTests : XCTestCase
@end
@implementation SettingsNavigationTests

- (void)testPointerWindowAndTabActionsHaveDistinctLocalizedNames {
    NSDictionary *names = [PointerPrefsController localizedActionMap];
    XCTAssertEqualObjects(names[kNewWindowWithProfilePointerAction],
                          NSLocalizedString(@"New Window With Profile…", @""));
    XCTAssertEqualObjects(names[kNewTabWithProfilePointerAction],
                          NSLocalizedString(@"New Tab With Profile…", @""));
    // The action picker resolves its selection by display name.
    XCTAssertEqual([NSSet setWithArray:names.allValues].count, names.count);
}

- (NSTableView *)tableInSidebar:(NSView *)sidebar {
    for (NSView *view in sidebar.subviews) {
        if ([view isKindOfClass:[NSScrollView class]]) {
            return (NSTableView *)[(NSScrollView *)view documentView];
        }
    }
    XCTFail(@"Missing settings category table");
    return nil;
}

- (void)testPageHeadingsFitNarrowAndWideWindowsInBothAppearances {
    PreferencePanel *panel = [PreferencePanel sharedInstance];
    NSWindow *window = panel.window;
    NSRect originalFrame = window.frame;
    NSAppearance *originalAppearance = window.appearance;
    NSTabView *tabs = [panel valueForKey:@"_tabView"];
    NSTabViewItem *originalSelection = tabs.selectedTabViewItem;
    NSArray *pages = [panel valueForKey:@"_settingsPages"];
    @try {
        for (NSString *appearance in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]) {
            window.appearance = [NSAppearance appearanceNamed:appearance];
            for (NSNumber *width in @[@820, @1280]) {
                [window setContentSize:NSMakeSize(width.doubleValue, 780)];
                for (id page in pages) {
                    [tabs selectTabViewItem:[page valueForKey:@"tabViewItem"]];
                    [window.contentView layoutSubtreeIfNeeded];
                    NSView *header = [panel valueForKey:@"_settingsHeader"];
                    NSTextField *title = header.subviews[0];
                    XCTAssertEqual(header.subviews.count, 1);
                    XCTAssertEqualWithAccuracy(NSMinX(title.frame), 32, 1);
                    XCTAssertGreaterThanOrEqual(title.font.pointSize, 28);
                    XCTAssertGreaterThanOrEqual(NSWidth(title.frame), title.intrinsicContentSize.width, @"%@", title.stringValue);
                    XCTAssertTrue(NSContainsRect(header.bounds, title.frame));
                    if (page == pages[0] || page == pages[2]) {
                        // Include the theme frame so AppKit draws the window backing
                        // as well as the transparent content and vibrant sidebar.
                        [window displayIfNeeded];
                        NSView *content = window.contentView.superview;
                        [window.effectiveAppearance performAsCurrentDrawingAppearance:^{
                            NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc]
                                initWithBitmapDataPlanes:NULL pixelsWide:NSWidth(content.bounds) * 2
                                pixelsHigh:NSHeight(content.bounds) * 2 bitsPerSample:8 samplesPerPixel:4
                                hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace
                                bytesPerRow:0 bitsPerPixel:0];
                            bitmap.size = content.bounds.size;
                            [content cacheDisplayInRect:content.bounds toBitmapImageRep:bitmap];
                            NSImage *image = [[NSImage alloc] initWithCGImage:bitmap.CGImage size:content.bounds.size];
                            XCTAttachment *attachment = [XCTAttachment attachmentWithImage:image];
                            attachment.name = [NSString stringWithFormat:@"Settings %@ %@ %@", title.stringValue, width, appearance];
                            attachment.lifetime = XCTAttachmentLifetimeKeepAlways;
                            [self addAttachment:attachment];
                        }];
                    }
                }
            }
        }
    } @finally {
        window.appearance = originalAppearance;
        [tabs selectTabViewItem:originalSelection];
        [window setFrame:originalFrame display:NO];
        [panel close];
    }
}

- (void)testAppBehaviorSectionsStayLeftAlignedInWideWindow {
    PreferencePanel *panel = [PreferencePanel sharedInstance];
    NSWindow *window = panel.window;
    const NSRect originalFrame = window.frame;
    NSTabView *tabs = [[panel valueForKey:@"_generalPreferencesViewController"] tabView];
    @try {
        [panel showGlobalTabView:nil];
        [window setContentSize:NSMakeSize(1280, 780)];
        [window.contentView layoutSubtreeIfNeeded];
        NSView *document = tabs.tabViewItems.firstObject.view.superview;
        NSInteger headings = 0;
        for (NSView *view in document.subviews) {
            if ([view.accessibilityIdentifier hasPrefix:@"SettingsSection."]) {
                XCTAssertEqualWithAccuracy(NSMinX(view.frame), 32, 1);
                headings++;
            }
        }
        XCTAssertEqual(headings, tabs.numberOfTabViewItems);
        NSScrollView *scroll = (NSScrollView *)tabs.tabViewItems.firstObject.view;
        NSView *form = scroll.documentView.subviews.firstObject;
        NSView *card = form.subviews.firstObject;
        XCTAssertNotNil(card);
        XCTAssertLessThanOrEqual(NSWidth(card.frame), 720);
        XCTAssertGreaterThan(NSWidth(form.frame) - NSMaxX(card.frame), 100);
    } @finally {
        [window setFrame:originalFrame display:NO];
        [panel close];
    }
}


- (void)testSettingsPagesFitDefaultWindowSize {
    PreferencePanel *panel = [PreferencePanel sharedInstance];
    NSWindow *window = panel.window;
    const NSRect originalFrame = window.frame;
    NSTabView *tabs = [panel valueForKey:@"_tabView"];
    NSTabViewItem *originalSelection = tabs.selectedTabViewItem;
    NSArray *pages = [panel valueForKey:@"_settingsPages"];
    NSScrollView *viewport = [panel valueForKey:@"_settingsContent"];
    @try {
        [window setContentSize:NSMakeSize(1040, 720)];
        for (id page in pages) {
            [tabs selectTabViewItem:[page valueForKey:@"tabViewItem"]];
            [window.contentView layoutSubtreeIfNeeded];
            XCTAssertLessThanOrEqual(NSWidth(viewport.documentView.bounds),
                                     NSWidth(viewport.contentView.bounds) + 1, @"%@", [page valueForKey:@"title"]);
            NSString *identifier = [page valueForKey:@"identifier"];
            if ([identifier isEqualToString:@"arrangements"]) {
                NSView *preview = [[panel arrangements] valueForKey:@"previewView_"];
                NSRect frame = [preview convertRect:preview.bounds toView:viewport.documentView];
                XCTAssertLessThanOrEqual(NSMaxX(frame), NSWidth(viewport.documentView.bounds) + 1);
            } else if ([identifier isEqualToString:@"pointer"]) {
                NSTabView *pointerTabs = [[panel valueForKey:@"_pointerViewController"] valueForKey:@"_tabView"];
                [pointerTabs selectTabViewItem:pointerTabs.tabViewItems.lastObject];
                [window.contentView layoutSubtreeIfNeeded];
                NSView *bindings = pointerTabs.tabViewItems.lastObject.view.subviews.firstObject;
                NSUInteger titledActions = 0;
                for (NSView *child in bindings.subviews) {
                    if ([child isKindOfClass:NSScrollView.class]) {
                        XCTAssertLessThanOrEqual(NSMaxX(child.frame), NSWidth(bindings.bounds));
                    } else if ([child isKindOfClass:NSButton.class]) {
                        NSButton *button = (NSButton *)child;
                        if (button.action == @selector(add:) || button.action == @selector(remove:)) {
                            XCTAssertGreaterThan(button.title.length, 0);
                            XCTAssertEqual(button.imagePosition, NSNoImage);
                            titledActions++;
                        }
                    }
                }
                XCTAssertEqual(titledActions, 2);
            } else if ([identifier isEqualToString:@"shortcuts"]) {
                id shortcuts = [panel valueForKey:@"_shortcutsViewController"];
                NSRect previous = NSZeroRect;
                for (NSString *key in @[@"_actionsViewController", @"_snippetsViewController"]) {
                    NSView *editor = [[shortcuts valueForKey:key] view];
                    for (NSView *child in editor.subviews) {
                        if ([child isKindOfClass:NSScrollView.class]) {
                            NSRect rect = [child convertRect:child.bounds toView:viewport.documentView];
                            if (!NSEqualRects(previous, NSZeroRect)) {
                                XCTAssertEqualWithAccuracy(NSMinX(rect), NSMinX(previous), 1);
                                XCTAssertEqualWithAccuracy(NSWidth(rect), NSWidth(previous), 1);
                            }
                            previous = rect;
                        }
                        if ([child isKindOfClass:NSSearchField.class]) {
                            XCTAssertLessThanOrEqual(NSMaxX(child.frame), NSWidth(editor.bounds));
                        }
                    }
                }
            } else if ([identifier isEqualToString:@"advanced"]) {
                NSTableView *table = [[panel valueForKey:@"_advancedViewController"] valueForKey:@"_tableView"];
                CGFloat columnsWidth = 0;
                for (NSTableColumn *column in table.tableColumns) {
                    columnsWidth += column.width;
                }
                XCTAssertLessThanOrEqual(columnsWidth, NSWidth(table.bounds) + 1);
            }
            [window displayIfNeeded];
            NSView *content = window.contentView.superview;
            [window.effectiveAppearance performAsCurrentDrawingAppearance:^{
                NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc]
                    initWithBitmapDataPlanes:NULL pixelsWide:NSWidth(content.bounds) * 2
                    pixelsHigh:NSHeight(content.bounds) * 2 bitsPerSample:8 samplesPerPixel:4
                    hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace
                    bytesPerRow:0 bitsPerPixel:0];
                bitmap.size = content.bounds.size;
                [content cacheDisplayInRect:content.bounds toBitmapImageRep:bitmap];
                NSImage *image = [[NSImage alloc] initWithCGImage:bitmap.CGImage size:content.bounds.size];
                XCTAttachment *attachment = [XCTAttachment attachmentWithImage:image];
                attachment.name = [NSString stringWithFormat:@"Default Settings %@", [page valueForKey:@"title"]];
                attachment.lifetime = XCTAttachmentLifetimeKeepAlways;
                [self addAttachment:attachment];
            }];
        }
    } @finally {
        [tabs selectTabViewItem:originalSelection];
        [window setFrame:originalFrame display:NO];
        [panel close];
    }
}

- (void)checkControlsInSettingsView:(NSView *)view document:(NSView *)document {
    if (view.isHidden) { return; }
    if ([view isKindOfClass:NSScrollView.class]) {
        NSScrollView *scroll = (NSScrollView *)view;
        if ([NSStringFromClass(scroll.class) isEqualToString:@"iTermSettingsContentView"] ||
            [scroll.accessibilityIdentifier isEqualToString:@"SettingsSections"] ||
            [scroll.accessibilityIdentifier isEqualToString:@"ExpertSettingsPage"]) {
            [self checkControlsInSettingsView:scroll.documentView document:scroll.documentView];
        }
        return;  // Tables and other bounded list editors scroll independently.
    }
    if ([view isKindOfClass:NSControl.class]) {
        if ([view isKindOfClass:NSTextField.class] && ![(NSTextField *)view isEditable]) { return; }
        const NSRect rect = [view convertRect:view.bounds toView:document];
        XCTAssertGreaterThanOrEqual(NSMinX(rect), -1, @"%@ %@", view, NSStringFromRect(rect));
        XCTAssertLessThanOrEqual(NSMaxX(rect), NSWidth(document.bounds) + 1,
                                 @"%@ %@ in %@", view, NSStringFromRect(rect), NSStringFromRect(document.bounds));
        return;
    }
    for (NSView *child in view.subviews) { [self checkControlsInSettingsView:child document:document]; }
}

- (void)testSettingsControlsRemainReachableAtNarrowAndWideWidths {
    PreferencePanel *panel = [PreferencePanel sharedInstance];
    NSWindow *window = panel.window;
    NSRect originalFrame = window.frame;
    NSTabView *tabs = [panel valueForKey:@"_tabView"];
    NSTabViewItem *originalSelection = tabs.selectedTabViewItem;
    @try {
        for (NSNumber *width in @[@820, @1040, @1280]) {
            [window setContentSize:NSMakeSize(width.doubleValue, 720)];
            for (NSTabViewItem *page in tabs.tabViewItems) {
                [tabs selectTabViewItem:page];
                [window.contentView layoutSubtreeIfNeeded];
                [self checkControlsInSettingsView:page.view document:page.view];
            }
        }
    } @finally {
        [tabs selectTabViewItem:originalSelection];
        [window setFrame:originalFrame display:NO];
        [panel close];
    }
}

- (void)testAppearanceControlsStayLeftAlignedWhenWindowWidens {
    PreferencePanel *panel = [PreferencePanel sharedInstance];
    NSWindow *window = panel.window;
    const NSRect originalFrame = window.frame;
    id appearance = [panel valueForKey:@"_appearancePreferencesViewController"];
    NSTabView *tabs = [appearance tabView];
    NSView *theme = [appearance valueForKey:@"_tabStyle"];
    @try {
        [[panel valueForKey:@"_tabView"] selectTabViewItem:[panel valueForKey:@"_appearanceTabViewItem"]];
        [window setContentSize:NSMakeSize(1040, 720)];
        [window.contentView layoutSubtreeIfNeeded];
        NSRect initial = [theme convertRect:theme.bounds toView:tabs.tabViewItems.firstObject.view];
        [window setContentSize:NSMakeSize(1400, 720)];
        [window.contentView layoutSubtreeIfNeeded];
        NSRect widened = [theme convertRect:theme.bounds toView:tabs.tabViewItems.firstObject.view];
        XCTAssertEqualWithAccuracy(NSMinX(initial), NSMinX(widened), 1);
        XCTAssertEqualWithAccuracy(NSWidth(initial), NSWidth(widened), 1);
        XCTAssertLessThan(NSHeight(tabs.tabViewItems.firstObject.view.frame), 300);
    } @finally {
        [window setFrame:originalFrame display:NO];
        [panel close];
    }
}

- (void)testKeyboardSectionsStayLeftAligned {
    PreferencePanel *panel = [PreferencePanel sharedInstance];
    NSWindow *window = panel.window;
    const NSRect originalFrame = window.frame;
    NSTabView *pages = [panel valueForKey:@"_tabView"];
    NSTabViewItem *originalPage = pages.selectedTabViewItem;
    NSTabView *sections = [[panel valueForKey:@"_keysViewController"] tabView];
    NSTabViewItem *originalSection = sections.selectedTabViewItem;
    @try {
        [window setContentSize:NSMakeSize(1040, 720)];
        [panel showKeyboardTabView:nil];
        for (NSTabViewItem *section in sections.tabViewItems) {
            [sections selectTabViewItem:section];
            [window.contentView layoutSubtreeIfNeeded];
            NSView *page = section.view;
            NSView *group = page.subviews.firstObject;
            XCTAssertNotNil(group, @"%@", section.label);
            XCTAssertGreaterThanOrEqual(NSMinX(group.frame), 0, @"%@", section.label);
            XCTAssertLessThanOrEqual(NSMinX(group.frame), 40, @"%@", section.label);
            XCTAssertLessThanOrEqual(NSMaxX(group.frame), NSWidth(page.bounds) + 1,
                                     @"%@", section.label);
        }
    } @finally {
        [sections selectTabViewItem:originalSection];
        [pages selectTabViewItem:originalPage];
        [window setFrame:originalFrame display:NO];
        [panel close];
    }
}

- (void)verifyProfilePagesFitInWindow:(PreferencePanel *)panel {
    ProfilePreferencesViewController *profiles = [panel valueForKey:@"_profilesViewController"];
    NSTabView *tabs = [profiles valueForKey:@"_tabView"];
    const NSRect stableFrame = panel.window.frame;
    id general = [profiles valueForKey:@"_generalViewController"];
    for (NSString *key in @[@"_tagsLabel", @"_titleSettingsLabel", @"_iconLabel"]) {
        NSTextField *label = [general valueForKey:key];
        XCTAssertGreaterThanOrEqual(NSWidth(label.bounds), label.cell.cellSize.width, @"%@", key);
    }
    for (NSTabViewItem *item in tabs.tabViewItems) {
        [tabs selectTabViewItem:item];
        [profiles invalidateSavedSize];
        [profiles resizeWindowForCurrentTabAnimated:NO];
        [panel.window.contentView layoutSubtreeIfNeeded];
        XCTAssertTrue(NSEqualRects(panel.window.frame, stableFrame));
        iTermSizeRememberingView *page = (iTermSizeRememberingView *)item.view;
        XCTAssertTrue(NSContainsRect(page.superview.bounds, page.frame), @"%@", item.label);
        for (NSView *child in page.subviews) {
            if ([child isKindOfClass:NSScrollView.class]) {
                NSScrollView *scroll = (NSScrollView *)child;
                [scroll layoutSubtreeIfNeeded];
                NSView *detail = scroll.documentView.subviews.firstObject;
                XCTAssertNotNil(detail);
                XCTAssertTrue(NSContainsRect(scroll.documentView.bounds, detail.frame), @"%@", item.label);
                XCTAssertGreaterThan(NSWidth(detail.bounds), 500);
                XCTAssertGreaterThanOrEqual(NSHeight(scroll.documentView.bounds), NSHeight(scroll.contentView.bounds));
            }
        }
        NSRect frame = [tabs convertRect:tabs.bounds toView:panel.window.contentView];
        XCTAssertLessThanOrEqual(NSMaxX(frame), NSWidth(panel.preferencePanelContentView.bounds) + panel.preferencePanelNavigationWidth, @"%@", item.label);
    }
}

- (void)testEveryExistingCategoryRemainsReachableFromSidebar {
    PreferencePanel *panel = [PreferencePanel sharedInstance];
    NSWindow *window = panel.window;
    NSView *sidebar = [panel valueForKey:@"_settingsSidebar"];
    NSTabView *tabs = [panel valueForKey:@"_tabView"];
    NSArray *pages = [panel valueForKey:@"_settingsPages"];
    NSArray<NSTabViewItem *> *navigation = [pages valueForKey:@"tabViewItem"];
    NSTableView *table = [self tableInSidebar:sidebar];
    XCTAssertEqual(navigation.count, 8);
    XCTAssertEqual(pages.count, 8);
    XCTAssertEqual([NSSet setWithArray:[pages valueForKey:@"identifier"]].count, 8);
    XCTAssertEqualObjects([NSSet setWithArray:navigation], [NSSet setWithArray:tabs.tabViewItems]);
    XCTAssertEqual(table.numberOfRows, 12);
    XCTAssertTrue(window.styleMask & NSWindowStyleMaskFullSizeContentView);
    XCTAssertTrue(window.titlebarAppearsTransparent);
    XCTAssertEqual(window.titleVisibility, NSWindowTitleHidden);
    for (NSInteger row = 0; row < table.numberOfRows; row++) {
        const BOOL isPage = [pages indexesOfObjectsPassingTest:^BOOL(id page, NSUInteger index, BOOL *stop) {
            return [sidebar rowFor:page] == row;
        }].count > 0;
        XCTAssertEqual([table.delegate tableView:table shouldSelectRow:row], isPage);
    }
    NSRect tabFrame = [tabs convertRect:tabs.bounds toView:window.contentView];
    XCTAssertGreaterThanOrEqual(NSMinX(tabFrame), NSMaxX(sidebar.frame));
    const NSRect stableFrame = window.frame;
    XCTAssertGreaterThanOrEqual(NSHeight(window.contentView.bounds), 560);
    XCTAssertNil(window.toolbar);
    for (NSInteger index = 0; index < navigation.count; index++) {
        [table selectRowIndexes:[NSIndexSet indexSetWithIndex:[sidebar rowFor:pages[index]]] byExtendingSelection:NO];
        XCTAssertEqual(tabs.selectedTabViewItem, navigation[index]);
        XCTAssertEqualObjects([sidebar valueForKey:@"selectedIndex"], @(index));
        XCTAssertNotNil(navigation[index].view);
        XCTAssertGreaterThan([[pages[index] valueForKey:@"title"] length], 0);
        NSView *header = [panel valueForKey:@"_settingsHeader"];
        NSTextField *heading = (NSTextField *)header.subviews.firstObject;
        XCTAssertEqualObjects(heading.stringValue, [pages[index] valueForKey:@"title"]);
        XCTAssertEqual(header.subviews.count, 1);
        XCTAssertTrue(NSEqualRects(window.frame, stableFrame));
    }
    [panel showGlobalTabView:nil];
    [panel resizeWindowForTabViewItem:tabs.selectedTabViewItem animated:NO];
    XCTAssertEqualObjects([sidebar valueForKey:@"selectedIndex"], @0);
    [panel showProfilesTabView:nil];
    ProfilePreferencesViewController *profiles = [panel valueForKey:@"_profilesViewController"];
    [profiles invalidateSavedSize];
    [profiles resizeWindowForCurrentTabAnimated:NO];
    XCTAssertEqualObjects([sidebar valueForKey:@"selectedIndex"], @2);
    [window.contentView layoutSubtreeIfNeeded];
    NSTabView *profileTabs = [profiles valueForKey:@"_tabView"];
    iTermSizeRememberingView *profilePage = (iTermSizeRememberingView *)profileTabs.selectedTabViewItem.view;
    XCTAssertTrue(NSContainsRect(profilePage.superview.bounds, profilePage.frame));
    NSRect profileFrame = [profileTabs convertRect:profileTabs.bounds toView:window.contentView];
    XCTAssertGreaterThan(NSMinX(profileFrame), NSMaxX(sidebar.frame));
    XCTAssertLessThanOrEqual(NSMaxX(profileFrame), NSWidth(tabs.bounds) + panel.preferencePanelNavigationWidth);
    NSTableCellView *cell = [table viewAtColumn:0 row:[sidebar rowFor:pages[2]] makeIfNecessary:YES];
    XCTAssertEqualObjects(cell.textField.stringValue, [pages[2] valueForKey:@"title"]);
    XCTAssertTrue(NSContainsRect(cell.bounds, cell.textField.frame));
    [self verifyProfilePagesFitInWindow:panel];
    [panel close];
}

- (void)testSectionsShareOneDocumentAndDeepLinksScrollWithoutHidingSiblings {
    PreferencePanel *panel = [PreferencePanel sharedInstance];
    NSWindow *window = panel.window;
    NSArray *pages = [panel valueForKey:@"_settingsPages"];
    for (id page in pages) {
        id controller = [page valueForKey:@"controller"];
        if (![controller respondsToSelector:@selector(tabView)]) { continue; }
        NSTabView *tabs = [controller tabView];
        if (!tabs) { continue; }
        [[panel valueForKey:@"_tabView"] selectTabViewItem:[page valueForKey:@"tabViewItem"]];
        [window.contentView layoutSubtreeIfNeeded];
        NSView *document = tabs.tabViewItems.firstObject.view.superview;
        XCTAssertTrue(document.isFlipped);
        for (NSTabViewItem *item in tabs.tabViewItems) {
            [tabs selectTabViewItem:item];
            [window.contentView layoutSubtreeIfNeeded];
            CGFloat bottom = 0;
            for (NSTabViewItem *sibling in tabs.tabViewItems) {
                XCTAssertEqual(sibling.view.superview, document);
                XCTAssertFalse(sibling.view.hidden);
                XCTAssertGreaterThan(NSMinY(sibling.view.frame), bottom);
                XCTAssertTrue(NSContainsRect(document.bounds, sibling.view.frame));
                bottom = NSMaxY(sibling.view.frame);
            }
            NSScrollView *scroll = document.enclosingScrollView;
            XCTAssertTrue(NSIntersectsRect(scroll.documentVisibleRect, item.view.frame));
        }
    }
    [panel close];
}


- (void)testProgrammaticNavigationDoesNotReenterUserSelection {
    PreferencePanel *panel = [PreferencePanel sharedInstance];
    (void)panel.window;
    NSView *sidebar = [panel valueForKey:@"_settingsSidebar"];
    NSTabView *tabs = [panel valueForKey:@"_tabView"];
    id original = [sidebar valueForKey:@"onSelect"];
    __block NSInteger callbacks = 0;
    [sidebar setValue:[^(id page) { callbacks++; } copy] forKey:@"onSelect"];
    [panel showMouseTabView:nil];
    XCTAssertEqualObjects([sidebar valueForKey:@"selectedIndex"], @5);
    XCTAssertEqual(tabs.selectedTabViewItem, [panel valueForKey:@"_mouseTabViewItem"]);
    XCTAssertEqual(callbacks, 0);
    [sidebar setValue:original forKey:@"onSelect"];
    [panel close];
}

- (void)testSessionEditorKeepsItsProfileOnlyLayout {
    PreferencePanel *panel = [PreferencePanel sessionsInstance];
    XCTAssertNotNil(panel.window);
    XCTAssertNil([panel valueForKey:@"_settingsSidebar"]);
    XCTAssertFalse(panel.window.toolbar.visible);
    NSTabView *tabs = [panel valueForKey:@"_tabView"];
    XCTAssertEqual(tabs.selectedTabViewItem, [panel valueForKey:@"_profilesTabViewItem"]);
    XCTAssertEqualObjects([panel valueForKey:@"preferencePanelNavigationWidth"], @0);
    [self verifyProfilePagesFitInWindow:panel];
    [panel close];
}

- (void)testSearchRevealsProfileSettingAndSidebarDismissesHighlight {
    PreferencePanel *panel = [PreferencePanel sharedInstance];
    (void)panel.window;
    [panel showGlobalTabView:nil];
    NSSearchField *search = [panel valueForKey:@"searchField"];
    search.stringValue = [NSLocalizedString(@"Font:", @"Font setting search")
                         stringByTrimmingCharactersInSet:NSCharacterSet.punctuationCharacterSet];
    ProfilePreferencesViewController *profiles = [panel valueForKey:@"_profilesViewController"];
    iTermPreferencesBaseViewController *text = [profiles valueForKey:@"_textViewController"];
    NSButton *nonAscii = [text valueForKey:@"_useNonAsciiFont"];
    XCTAssertEqualObjects(nonAscii.title, NSLocalizedString(@"Use a different font for non-ASCII text", @"Font setting"));
    iTermPreferencesSearchDocument *fontDocument = nil;
    for (iTermPreferencesSearchDocument *document in [panel searchResults]) {
        if ([document.ownerIdentifier isEqualToString:text.documentOwnerIdentifier]) {
            fontDocument = document;
            break;
        }
    }
    XCTAssertNotNil(fontDocument);
    BOOL switched = NO;
    XCTAssertTrue([panel revealDocument:fontDocument switchingTabs:&switched switchingInnerTabs:NULL]);
    XCTAssertTrue(switched);
    NSView *sidebar = [panel valueForKey:@"_settingsSidebar"];
    XCTAssertEqualObjects([sidebar valueForKey:@"selectedIndex"], @2);
    NSView *scrim = [panel valueForKey:@"_scrim"];
    XCTAssertNotNil([scrim valueForKey:@"cutoutView"]);
    [[self tableInSidebar:sidebar] selectRowIndexes:[NSIndexSet indexSetWithIndex:[sidebar rowFor:[panel valueForKey:@"_settingsPages"][1]]]
                             byExtendingSelection:NO];
    XCTAssertNil([panel valueForKey:@"_scrim"]);
    search.stringValue = @"";
    [panel close];
}

- (void)testSearchRevealsRegroupedProfileControlInNarrowWindow {
    PreferencePanel *panel = [PreferencePanel sharedInstance];
    NSWindow *window = panel.window;
    const NSRect originalFrame = window.frame;
    id profiles = [panel valueForKey:@"_profilesViewController"];
    iTermPreferencesBaseViewController *general = [profiles valueForKey:@"_generalViewController"];
    iTermPreferencesSearchDocument *directory = nil;
    for (iTermPreferencesSearchDocument *document in general.searchableViewControllerDocuments) {
        if ([document.identifier isEqualToString:KEY_CUSTOM_DIRECTORY]) {
            directory = document;
        }
    }
    XCTAssertNotNil(directory);
    @try {
        [window setContentSize:NSMakeSize(820, 560)];
        [panel showGlobalTabView:nil];
        XCTAssertTrue([panel revealDocument:directory switchingTabs:NULL switchingInnerTabs:NULL]);
        [window.contentView layoutSubtreeIfNeeded];
        NSView *target = [[panel valueForKey:@"_scrim"] valueForKey:@"cutoutView"];
        NSScrollView *scroll = target.enclosingScrollView;
        XCTAssertNotNil(target);
        XCTAssertNotNil(scroll);
        NSRect visibleTarget = [target convertRect:target.bounds toView:scroll.documentView];
        XCTAssertTrue(NSContainsRect(scroll.documentVisibleRect, visibleTarget));
        NSTabView *profileSections = [profiles valueForKey:@"_tabView"];
        NSScrollView *sections = profileSections.tabViewItems.firstObject.view.enclosingScrollView;
        NSRect targetInSections = [target convertRect:target.bounds toView:sections.documentView];
        XCTAssertTrue(NSContainsRect(sections.documentVisibleRect, targetInSections));
        XCTAssertEqualObjects([[panel valueForKey:@"_settingsSidebar"] valueForKey:@"selectedIndex"], @2);
    } @finally {
        [panel showGlobalTabView:nil];
        [window setFrame:originalFrame display:NO];
        [panel close];
    }
}

- (void)testSidebarSearchKeepsItsOptionsWithoutAToolbar {
    PreferencePanel *panel = [PreferencePanel sharedInstance];
    (void)panel.window;
    NSSearchField *search = [panel valueForKey:@"searchField"];
    XCTAssertTrue([search isDescendantOf:[panel valueForKey:@"_settingsSidebar"]]);
    XCTAssertEqual((id)search.delegate, panel);
    XCTAssertEqualObjects(search.accessibilityLabel, NSLocalizedString(@"Search Settings", @"Settings search"));
    NSMenuItem *option = search.searchMenuTemplate.itemArray.firstObject;
    XCTAssertNotNil(option);
    XCTAssertEqual(option.target, panel);
    XCTAssertTrue([panel validateMenuItem:option]);
    const NSControlStateValue originalState = option.state;
    @try {
        XCTAssertTrue([NSApp sendAction:option.action to:option.target from:option]);
        XCTAssertTrue([panel validateMenuItem:option]);
        XCTAssertNotEqual(option.state, originalState);
        [panel showProfilesTabView:nil];
        XCTAssertEqual([panel valueForKey:@"searchField"], search);
        XCTAssertTrue([panel validateMenuItem:option]);
        XCTAssertNotEqual(option.state, originalState);
    } @finally {
        [panel validateMenuItem:option];
        if (option.state != originalState) {
            [NSApp sendAction:option.action to:option.target from:option];
        }
        [panel close];
    }
}

- (void)testDynamicProfileWriteSkipsMissingOrReadOnlyProfiles {
    iTermDynamicProfileManager *manager = [iTermDynamicProfileManager sharedInstance];
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSData *original = [@"original contents" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertTrue([original writeToFile:path atomically:YES]);
    @try {
        [manager writeModifiedProfile:nil toFile:path];
        [manager writeModifiedProfile:@{KEY_GUID: @"gone"} toFile:path];
        XCTAssertEqualObjects([NSData dataWithContentsOfFile:path], original);
    } @finally {
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    }
}

- (void)testMainScreenPickerNeverSelectsSeparator {
    PreferencePanel *panel = [PreferencePanel sharedInstance];
    (void)panel.window;
    id profiles = [panel valueForKey:@"_profilesViewController"];
    id controller = [profiles valueForKey:@"_windowViewController"];
    NSPopUpButton *screen = [controller valueForKey:@"_screen"];
    NSInteger original = screen.selectedTag;
    @try {
        XCTAssertTrue([screen selectItemWithTag:0]);
        XCTAssertFalse(screen.selectedItem.separatorItem);
        XCTAssertGreaterThan(screen.title.length, 0);
    } @finally {
        [screen selectItemWithTag:original];
        [panel close];
    }
}

- (void)testSearchResultsShowEmptyStateAndReturnActivatesFirstMatch {
    iTermPreferencesSearchEngineResultsWindowController *results = [[iTermPreferencesSearchEngineResultsWindowController alloc]
        initWithWindowNibName:@"iTermPreferencesSearchEngineResultsWindowController"];
    SettingsSearchDelegate *delegate = [[SettingsSearchDelegate alloc] init];
    results.delegate = delegate;
    (void)results.window;
    NSTableView *table = [results valueForKey:@"_tableView"];
    @try {
        results.documents = @[];
        XCTAssertEqual(results.window.alphaValue, 1);
        XCTAssertEqual(table.numberOfRows, 1);
        XCTAssertFalse([table.delegate tableView:table shouldSelectRow:0]);
        [results insertNewline:nil];
        XCTAssertNil(delegate.activated);
        iTermPreferencesSearchDocument *document = [iTermPreferencesSearchDocument
            documentWithDisplayName:@"Font" identifier:@"Font" keywordPhrases:@[]];
        document.pathComponents = @[@"Profiles", @"Text"];
        document.scope = @"Selected profile";
        results.documents = @[document];
        NSTableCellView *cell = [table viewAtColumn:0 row:0 makeIfNecessary:YES];
        XCTAssertTrue([cell.toolTip containsString:@"Profiles › Text"]);
        for (NSView *label in cell.subviews) {
            XCTAssertTrue(NSContainsRect(cell.bounds, label.frame));
        }
        [results.window.contentView layoutSubtreeIfNeeded];
        NSView *content = results.window.contentView;
        NSBitmapImageRep *bitmap = [content bitmapImageRepForCachingDisplayInRect:content.bounds];
        [content cacheDisplayInRect:content.bounds toBitmapImageRep:bitmap];
        NSImage *image = [[NSImage alloc] initWithCGImage:bitmap.CGImage size:content.bounds.size];
        XCTAttachment *attachment = [XCTAttachment attachmentWithImage:image];
        attachment.name = @"Settings search result layout";
        attachment.lifetime = XCTAttachmentLifetimeKeepAlways;
        [self addAttachment:attachment];
        [results insertNewline:nil];
        XCTAssertEqual(delegate.previewed, document);
        XCTAssertEqual(delegate.activated, document);
        results.documents = @[];
        XCTAssertNil(results.selectedDocument);
        [results moveDown:nil];
        XCTAssertNil(results.selectedDocument);
    } @finally {
        [results close];
    }
}

- (void)testSearchRanksTitlesAndPreservesDifferentScopes {
    iTermPreferencesSearchEngine *engine = [[iTermPreferencesSearchEngine alloc] init];
    iTermPreferencesSearchDocument *keyword = [iTermPreferencesSearchDocument
        documentWithDisplayName:@"A rendering option" identifier:@"Other" keywordPhrases:@[@"font"]];
    iTermPreferencesSearchDocument *app = [iTermPreferencesSearchDocument
        documentWithDisplayName:@"Font" identifier:@"SharedFont" keywordPhrases:@[]];
    app.ownerIdentifier = @"App";
    iTermPreferencesSearchDocument *profile = [iTermPreferencesSearchDocument
        documentWithDisplayName:@"Font" identifier:@"SharedFont" keywordPhrases:@[]];
    profile.ownerIdentifier = @"Profile";
    profile.pathComponents = @[@"Profiles", @"Text"];
    iTermPreferencesSearchDocument *duplicate = [iTermPreferencesSearchDocument
        documentWithDisplayName:@"Font" identifier:@"SharedFont" keywordPhrases:@[]];
    duplicate.ownerIdentifier = profile.ownerIdentifier;
    duplicate.pathComponents = profile.pathComponents;
    XCTAssertNotEqualObjects(duplicate.docid, profile.docid);
    for (iTermPreferencesSearchDocument *document in @[keyword, app, profile, duplicate]) {
        [engine addDocumentToIndex:document];
    }
    NSArray *results = [engine documentsMatchingQuery:@"font"];
    XCTAssertEqual(results.count, 3);
    XCTAssertEqualObjects([[results valueForKey:@"ownerIdentifier"] firstObject], @"App");
    XCTAssertEqual(results.lastObject, keyword);
    XCTAssertEqualObjects([engine documentsMatchingQuery:@"profiles font"], (@[profile]));
    XCTAssertEqual([engine documentsMatchingQuery:@"  \n"].count, 0);
    XCTAssertEqual([engine documentsMatchingQuery:@"\"\""].count, 0);
}

- (void)testSearchIndexSnapshotKeepsItsPathWhenControllerMetadataChanges {
    iTermPreferencesSearchDocument *source = [iTermPreferencesSearchDocument
        documentWithDisplayName:@"Font" identifier:@"Font" keywordPhrases:@[]];
    source.pathComponents = @[@"Profiles", @"Text"];
    iTermPreferencesSearchDocument *snapshot = [source copy];
    XCTAssertEqualObjects(snapshot, source);
    XCTAssertFalse(snapshot == source);
    iTermPreferencesSearchEngine *engine = [[iTermPreferencesSearchEngine alloc] init];
    [engine addDocumentToIndex:snapshot];
    source.pathComponents = @[@"Other"];
    XCTAssertEqualObjects(snapshot.pathComponents, (@[@"Profiles", @"Text"]));
    XCTAssertEqualObjects([engine documentsMatchingQuery:@"profiles font"], (@[snapshot]));
    XCTAssertEqual([engine documentsMatchingQuery:@"other font"].count, 0);
}

- (void)testSearchResultsFitScreenEdgesAndRecoverTheirHeightAndScrollPosition {
    iTermPreferencesSearchEngineResultsWindowController *results = [[iTermPreferencesSearchEngineResultsWindowController alloc]
        initWithWindowNibName:@"iTermPreferencesSearchEngineResultsWindowController"];
    iTermPreferencesSearchDocument *document = [iTermPreferencesSearchDocument
        documentWithDisplayName:@"Font" identifier:@"Font" keywordPhrases:@[]];
    NSMutableArray *documents = [NSMutableArray array];
    for (NSInteger i = 0; i < 40; i++) {
        [documents addObject:document];
    }
    @try {
        // Exercise loading via the data setter, without loading the window first.
        results.documents = documents;
        const NSRect smallScreen = NSMakeRect(-700, 100, 600, 400);
        const NSRect middle = NSMakeRect(-160, 300, 200, 28);
        [results positionRelativeToSearchRect:middle visibleFrame:smallScreen];
        XCTAssertTrue(NSContainsRect(smallScreen, results.window.frame));
        XCTAssertLessThan(NSMaxY(results.window.frame), NSMinY(middle));
        const CGFloat shortHeight = NSHeight(results.window.frame);

        const NSRect largeScreen = NSMakeRect(-700, 100, 1200, 900);
        const NSRect high = NSMakeRect(-650, 900, 200, 28);
        [results positionRelativeToSearchRect:high visibleFrame:largeScreen];
        XCTAssertGreaterThan(NSHeight(results.window.frame), shortHeight);
        XCTAssertTrue(NSContainsRect(largeScreen, results.window.frame));

        const NSRect low = NSMakeRect(-160, 120, 200, 28);
        [results positionRelativeToSearchRect:low visibleFrame:smallScreen];
        XCTAssertGreaterThan(NSMinY(results.window.frame), NSMaxY(low));
        XCTAssertTrue(NSContainsRect(smallScreen, results.window.frame));

        [results.window.contentView layoutSubtreeIfNeeded];
        NSTableView *table = [results valueForKey:@"_tableView"];
        [table scrollRowToVisible:39];
        XCTAssertFalse(NSIntersectsRect(table.visibleRect, [table rectOfRow:0]));
        results.documents = documents;
        XCTAssertTrue(NSIntersectsRect(table.visibleRect, [table rectOfRow:0]));
    } @finally {
        [results close];
    }
}

- (void)testSearchPathsFollowRegroupedNavigation {
    PreferencePanel *panel = [PreferencePanel sharedInstance];
    (void)panel.window;
    NSSearchField *field = [panel valueForKey:@"searchField"];
    NSString *original = field.stringValue;
    @try {
        field.stringValue = @"PromptOnQuit";
        NSArray<iTermPreferencesSearchDocument *> *results = [panel searchResults];
        iTermPreferencesSearchDocument *document = results.firstObject;
        XCTAssertEqualObjects(document.identifier, @"PromptOnQuit");
        XCTAssertTrue([document.pathComponents containsObject:NSLocalizedString(@"Startup & Exit", @"")]);
        XCTAssertEqualObjects(document.scope, NSLocalizedString(@"Application-wide", @""));
        field.stringValue = [NSString stringWithFormat:@"%@ PromptOnQuit", document.pathComponents.firstObject];
        XCTAssertTrue([[panel searchResults] containsObject:document]);
    } @finally {
        field.stringValue = original;
        [panel close];
    }
}

- (void)testChineseSearchFindsCharactersInsideAnIndexedPhrase {
    iTermPreferencesSearchEngine *engine = [[iTermPreferencesSearchEngine alloc] init];
    iTermPreferencesSearchDocument *document = [iTermPreferencesSearchDocument
        documentWithDisplayName:@"为非 ASCII 文本使用另一种字体"
        identifier:@"Non Ascii Font" keywordPhrases:@[]];
    [engine addDocumentToIndex:document];
    XCTAssertEqualObjects([engine documentsMatchingQuery:@"字体"], (@[document]));
    XCTAssertEqualObjects([engine documentsMatchingQuery:@"font"], (@[document]));
    XCTAssertEqual([engine documentsMatchingQuery:@"背景"].count, 0);
}

- (void)testManualWindowSizePersistsAndSmallViewportsKeepContentReachable {
    PreferencePanel *panel = [PreferencePanel sharedInstance];
    NSWindow *window = panel.window;
    [window setContentSize:NSMakeSize(900, 600)];
    NSRect resizedFrame = window.frame;
    [panel showProfilesTabView:nil];
    [self verifyProfilePagesFitInWindow:panel];
    XCTAssertTrue(NSEqualRects(resizedFrame, window.frame));
    NSScrollView *viewport = [panel valueForKey:@"_settingsContent"];
    [window.contentView layoutSubtreeIfNeeded];
    XCTAssertGreaterThanOrEqual(NSWidth(viewport.documentView.bounds), 800);
    XCTAssertEqualWithAccuracy(NSHeight(viewport.documentView.bounds), NSHeight(viewport.contentView.bounds), 1);

    NSString *frameName = @"SettingsSizeRegression";
    [window saveFrameUsingName:frameName];
    [window setContentSize:NSMakeSize(1000, 650)];
    XCTAssertTrue([window setFrameUsingName:frameName]);
    XCTAssertTrue(NSEqualRects(resizedFrame, window.frame));
    [[iTermUserDefaults userDefaults] removeObjectForKey:@"NoSyncFrame_SettingsSizeRegression"];
    [panel close];
}

- (void)testProfileDetailsAdaptToWideAndNarrowWindows {
    PreferencePanel *panel = [PreferencePanel sharedInstance];
    NSWindow *window = panel.window;
    const NSRect originalFrame = window.frame;
    [panel showProfilesTabView:nil];
    ProfilePreferencesViewController *profiles = [panel valueForKey:@"_profilesViewController"];
    NSTabView *tabs = [profiles valueForKey:@"_tabView"];
    [tabs selectTabViewItem:[profiles valueForKey:@"_generalTab"]];
    NSView *list = [profiles valueForKey:@"_profilesListView"];
    NSView *wrapper = [profiles valueForKey:@"_tabViewWrapperView"];
    NSViewController *general = [profiles valueForKey:@"_generalViewController"];
    NSTextField *name = [general valueForKey:@"_profileNameField"];
    NSString *selectedGuid = [panel.currentProfileGuid copy];
    CGFloat wideFieldWidth = 0;
    NSScrollView *sectionContent = (NSScrollView *)tabs.selectedTabViewItem.view.subviews.firstObject;
    NSScrollView *scroll = nil;
    for (NSView *child in tabs.subviews) {
        if ([child.accessibilityIdentifier isEqualToString:@"SettingsSections"]) {
            scroll = (NSScrollView *)child;
            break;
        }
    }
    XCTAssertNotNil(scroll);
    const NSScrollerStyle originalScrollerStyle = scroll.scrollerStyle;
    @try {
        // Also exercise always-visible scrollbars, which consume content width.
        for (NSNumber *width in @[@1400, @820, @1000, @1400, @820, @1400]) {
            if (wideFieldWidth > 0 && width.doubleValue == 1400) {
                scroll.scrollerStyle = NSScrollerStyleLegacy;
            }
            [window setContentSize:NSMakeSize(width.doubleValue, 680)];
            [window.contentView layoutSubtreeIfNeeded];
            XCTAssertTrue(NSContainsRect(profiles.view.bounds, list.frame));
            XCTAssertTrue(NSContainsRect(profiles.view.bounds, wrapper.frame));
            XCTAssertFalse(NSIntersectsRect(list.frame, wrapper.frame));
            if (width.doubleValue == 1400) {
                XCTAssertGreaterThan(NSMinX(wrapper.frame), NSMaxX(list.frame));
                wideFieldWidth = NSWidth(name.bounds);
            } else {
                XCTAssertGreaterThan(NSMinX(wrapper.frame), NSMaxX(list.frame));
                XCTAssertLessThan(NSWidth(name.bounds), wideFieldWidth);
                XCTAssertGreaterThan(NSWidth(scroll.documentView.bounds), NSWidth(scroll.contentView.bounds));
            }
            XCTAssertEqualObjects(panel.currentProfileGuid, selectedGuid);
            XCTAssertEqualWithAccuracy(NSWidth(sectionContent.documentView.bounds), NSWidth(sectionContent.contentView.bounds), 1);
            XCTAssertFalse(sectionContent.hasHorizontalScroller);
            XCTAssertTrue(scroll.hasHorizontalScroller);
            for (NSString *key in @[@"_profileNameField", @"_tagsTokenField", @"_badgeText", @"_editBadgeButton",
                                     @"_customCommand", @"_sendTextAtStart", @"_customDirectory", @"_urlSchemes"]) {
                NSView *control = [general valueForKey:key];
                NSRect frame = [control convertRect:control.bounds toView:general.view];
                XCTAssertGreaterThan(NSWidth(frame), 20, @"%@ at %@", key, width);
                XCTAssertGreaterThanOrEqual(NSMinX(frame), 0, @"%@ at %@", key, width);
                XCTAssertLessThanOrEqual(NSMaxX(frame), NSWidth(general.view.bounds), @"%@ at %@", key, width);
            }
        }
    } @finally {
        scroll.scrollerStyle = originalScrollerStyle;
        [window setFrame:originalFrame display:NO];
        [panel close];
    }
}

- (void)testProfileLibraryStaysVisibleAndPreservesSelection {
    PreferencePanel *panel = [PreferencePanel sharedInstance];
    NSWindow *window = panel.window;
    const NSRect originalFrame = window.frame;
    [panel showProfilesTabView:nil];
    id profiles = [panel valueForKey:@"_profilesViewController"];
    NSView *list = [profiles valueForKey:@"_profilesListView"];
    NSView *details = [profiles valueForKey:@"_tabViewWrapperView"];
    NSString *guid = [panel.currentProfileGuid copy];
    @try {
        for (NSNumber *width in @[@1400, @820, @1040]) {
            [window setContentSize:NSMakeSize(width.doubleValue, 680)];
            [window.contentView layoutSubtreeIfNeeded];
            XCTAssertFalse(list.hidden);
            XCTAssertFalse(NSIntersectsRect(list.frame, details.frame));
            XCTAssertLessThan(NSMaxX(list.frame), NSMinX(details.frame));
            for (NSString *key in @[@"_addProfileButton", @"_removeProfileButton", @"_otherActionsPopup", @"_toggleTagsButton"]) {
                NSView *action = [profiles valueForKey:key];
                XCTAssertFalse(action.hidden);
                XCTAssertLessThanOrEqual(NSMaxY(action.frame), NSMinY(list.frame));
                XCTAssertFalse(NSIntersectsRect(action.frame, details.frame));
            }
            XCTAssertEqualObjects(panel.currentProfileGuid, guid);
        }
    } @finally {
        [window setFrame:originalFrame display:NO];
        [panel close];
    }
}


- (void)testProfileHeadingUsesIdentityWhenNamesMatch {
    PreferencePanel *panel = [PreferencePanel sharedInstance];
    (void)panel.window;
    id profiles = [panel valueForKey:@"_profilesViewController"];
    NSView *root = [profiles view];
    NSTextField *title = nil;
    for (NSView *child in root.subviews) {
        if ([child.accessibilityIdentifier isEqualToString:@"SettingsSelectedProfile"]) { title = (NSTextField *)child; }
    }
    XCTAssertNotNil(title);
    @try {
        [root updateProfilesWithNames:@[@"Same Name", @"Same Name"] identifiers:@[@"first", @"second"] selectedIdentifier:@"second"];
        XCTAssertEqualObjects(title.stringValue, @"Same Name");
        [root updateProfilesWithNames:@[@"Renamed", @"Same Name"] identifiers:@[@"first", @"second"] selectedIdentifier:@"second"];
        XCTAssertEqualObjects(title.stringValue, @"Same Name");
        [root updateProfilesWithNames:@[] identifiers:@[] selectedIdentifier:nil];
        XCTAssertEqualObjects(title.stringValue, @"");
    } @finally {
        [profiles reloadData];
        [panel close];
    }
}


- (void)testStartupAndClosingShareSearchableResponsivePage {
    PreferencePanel *panel = [PreferencePanel sharedInstance];
    NSWindow *window = panel.window;
    const NSRect originalFrame = window.frame;
    iTermPreferencesBaseViewController *general = [panel valueForKey:@"_generalPreferencesViewController"];
    NSView *startup = [general valueForKey:@"_openWindowsAtStartup"];
    NSView *closing = [general valueForKey:@"_promptOnQuit"];
    NSTabView *tabs = [general valueForKey:@"_tabView"];
    @try {
        [window setContentSize:NSMakeSize(820, 560)];
        [panel showGlobalTabView:nil];
        [tabs selectTabViewItem:[general valueForKey:@"_startupClosingTab"]];
        [window.contentView layoutSubtreeIfNeeded];
        XCTAssertEqual(startup.enclosingScrollView, closing.enclosingScrollView);
        XCTAssertNotNil(startup.enclosingScrollView);
        XCTAssertEqual([tabs indexOfTabViewItemWithIdentifier:@"2"], NSNotFound);
        iTermPreferencesSearchDocument *document = nil;
        for (iTermPreferencesSearchDocument *candidate in general.searchableViewControllerDocuments) {
            if ([candidate.identifier isEqualToString:@"PromptOnQuit"]) { document = candidate; }
        }
        XCTAssertNotNil(document);
        XCTAssertTrue([panel revealDocument:document switchingTabs:NULL switchingInnerTabs:NULL]);
        NSView *target = [[panel valueForKey:@"_scrim"] valueForKey:@"cutoutView"];
        NSScrollView *scroll = target.enclosingScrollView;
        XCTAssertNotNil(target);
        XCTAssertTrue(NSContainsRect(scroll.documentVisibleRect, [target convertRect:target.bounds toView:scroll.documentView]));
        NSScrollView *outer = [panel valueForKey:@"_settingsContent"];
        XCTAssertEqualWithAccuracy(NSWidth(outer.documentView.bounds), NSWidth(outer.contentView.bounds), 1);
    } @finally {
        [panel showProfilesTabView:nil];
        [window setFrame:originalFrame display:NO];
        [panel close];
    }
}

- (void)testEverySelectedPageFillsItsTabContentAfterRepeatedNavigation {
    PreferencePanel *panel = [PreferencePanel sharedInstance];
    NSWindow *window = panel.window;
    NSTabView *tabs = [panel valueForKey:@"_tabView"];
    NSArray *pages = [panel valueForKey:@"_settingsPages"];
    NSArray<NSTabViewItem *> *navigation = [pages valueForKey:@"tabViewItem"];
    NSView *sidebar = [panel valueForKey:@"_settingsSidebar"];
    NSTableView *table = [self tableInSidebar:sidebar];
    for (NSValue *sizeValue in @[[NSValue valueWithSize:NSMakeSize(1100, 720)],
                                 [NSValue valueWithSize:NSMakeSize(900, 600)]]) {
        [window setContentSize:sizeValue.sizeValue];
        const NSRect windowFrame = window.frame;
        for (NSInteger pass = 0; pass < 2; pass++) {
            for (NSInteger index = 0; index < navigation.count; index++) {
                [table selectRowIndexes:[NSIndexSet indexSetWithIndex:[sidebar rowFor:pages[index]]] byExtendingSelection:NO];
                [window.contentView layoutSubtreeIfNeeded];
                XCTAssertTrue(NSEqualRects(tabs.selectedTabViewItem.view.frame, tabs.contentRect),
                              @"%@ page %@ should fill %@", navigation[index].label,
                              NSStringFromRect(tabs.selectedTabViewItem.view.frame), NSStringFromRect(tabs.contentRect));
                if (navigation[index] == [panel valueForKey:@"_advancedTabViewItem"]) {
                    id advanced = [panel valueForKey:@"_advancedViewController"];
                    NSTableView *settings = [advanced valueForKey:@"_tableView"];
                    NSScrollView *scroll = settings.enclosingScrollView;
                    // The scrolling document includes the filter and help,
                    // and fills the page after every navigation and resize.
                    XCTAssertEqualWithAccuracy(NSMinY(scroll.frame), 0, 1);
                    XCTAssertEqualWithAccuracy(NSMaxY(scroll.frame),
                                               NSHeight(scroll.superview.bounds), 1);
                }
                id controller = [panel valueForKey:@"_shortcutsViewController"];
                XCTAssertEqual([controller valueForKey:@"preferencePanel"], panel);
                XCTAssertTrue(NSEqualRects(window.frame, windowFrame));
            }
        }
    }
    [panel close];
}

- (void)testAdvancedSearchUsesStableIdentifiersAndClearsConflictingLocalFilters {
    PreferencePanel *panel = [PreferencePanel sharedInstance];
    (void)panel.window;
    iTermAdvancedSettingsViewController *advanced = [panel valueForKey:@"_advancedViewController"];
    NSArray<iTermPreferencesSearchDocument *> *documents = advanced.searchableViewControllerDocuments;
    NSMutableSet *identifiers = [NSMutableSet set];
    iTermPreferencesSearchDocument *target = nil;
    for (iTermPreferencesSearchDocument *document in documents) {
        XCTAssertFalse([identifiers containsObject:document.identifier]);
        [identifiers addObject:document.identifier];
        if ([document.identifier isEqualToString:@"UseUnevenTabs"]) {
            target = document;
        }
    }
    XCTAssertNotNil(target);
    NSSearchField *localSearch = [advanced valueForKey:@"_searchField"];
    localSearch.stringValue = @"not-a-setting";
    [localSearch.delegate controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:localSearch]];
    [(NSButton *)[advanced valueForKey:@"_excludeDefaults"] setState:NSControlStateValueOn];
    BOOL switched = NO;
    NSView *revealed = [advanced searchableViewControllerRevealItemForDocument:target forQuery:@"UseUnevenTabs" willChangeTab:&switched];
    XCTAssertNotNil(revealed);
    XCTAssertEqualObjects(localSearch.stringValue, @"");
    NSTableView *table = [advanced valueForKey:@"_tableView"];
    XCTAssertEqual(table.selectedRow, -1);
    XCTAssertEqualObjects(revealed.accessibilityIdentifier, target.identifier);
    NSSearchField *search = [panel valueForKey:@"searchField"];
    search.stringValue = NSLocalizedString(@"Uneven tab widths allowed.", @"Advanced setting");
    XCTAssertTrue([[panel searchResults] containsObject:target]);
    search.stringValue = @"";
    [panel close];
}


- (void)testExpertSettingsScrollAsAWholePageAndResizeAfterFiltering {
    PreferencePanel *panel = [PreferencePanel sharedInstance];
    NSWindow *window = panel.window;
    NSRect originalFrame = window.frame;
    NSTabView *tabs = [panel valueForKey:@"_tabView"];
    NSTabViewItem *originalSelection = tabs.selectedTabViewItem;
    iTermAdvancedSettingsViewController *advanced = [panel valueForKey:@"_advancedViewController"];
    NSTableView *table = [advanced valueForKey:@"_tableView"];
    NSSearchField *search = [advanced valueForKey:@"_searchField"];
    NSButton *exclude = [advanced valueForKey:@"_excludeDefaults"];
    NSString *originalQuery = search.stringValue;
    NSControlStateValue originalState = exclude.state;
    @try {
        [tabs selectTabViewItem:[panel valueForKey:@"_advancedTabViewItem"]];
        exclude.state = NSControlStateValueOff;
        search.stringValue = @"";
        [advanced advancedSettingsDidChange:nil];
        for (NSNumber *width in @[@1040, @1280]) {
            [window setContentSize:NSMakeSize(width.doubleValue, 720)];
            [window.contentView layoutSubtreeIfNeeded];
            NSScrollView *scroll = table.enclosingScrollView;
            XCTAssertEqual(search.enclosingScrollView, scroll);
            XCTAssertEqual(exclude.enclosingScrollView, scroll);
            XCTAssertEqual(table.superview, scroll.documentView);
            XCTAssertEqualWithAccuracy(NSWidth(scroll.frame), NSWidth(advanced.view.bounds), 1);
            XCTAssertGreaterThan(NSHeight(scroll.documentView.frame), NSHeight(scroll.contentView.bounds) * 2);
            XCTAssertEqualWithAccuracy(NSHeight(table.frame), NSMaxY([table rectOfRow:table.numberOfRows - 1]), 1);
            const CGFloat before = [search convertPoint:NSZeroPoint toView:advanced.view].y;
            [scroll.contentView scrollToPoint:NSMakePoint(0, 240)];
            [scroll reflectScrolledClipView:scroll.contentView];
            const CGFloat after = [search convertPoint:NSZeroPoint toView:advanced.view].y;
            XCTAssertEqualWithAccuracy(fabs(after - before), 240, 1);
            XCTAssertFalse(NSIntersectsRect(search.frame, scroll.documentVisibleRect));

            iTermPreferencesSearchDocument *last = advanced.searchableViewControllerDocuments.lastObject;
            BOOL switched = NO;
            NSView *revealed = [advanced searchableViewControllerRevealItemForDocument:last forQuery:last.identifier willChangeTab:&switched];
            XCTAssertNotNil(revealed);
            XCTAssertTrue(NSIntersectsRect([revealed convertRect:revealed.bounds toView:scroll.documentView], scroll.documentVisibleRect));

            search.stringValue = @"UseUnevenTabs";
            [advanced controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:search]];
            XCTAssertEqual(table.numberOfRows, 2);
            XCTAssertEqualWithAccuracy(NSHeight(scroll.documentView.frame), scroll.contentSize.height, 1);
            XCTAssertEqualWithAccuracy(scroll.contentView.bounds.origin.y, 0, 1);
            search.stringValue = @"not-a-setting";
            [advanced controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:search]];
            XCTAssertEqual(table.numberOfRows, 0);
            XCTAssertEqualWithAccuracy(NSHeight(table.frame), 0, 1);
            search.stringValue = @"";
            [advanced advancedSettingsDidChange:nil];
        }
    } @finally {
        search.stringValue = originalQuery;
        exclude.state = originalState;
        [advanced advancedSettingsDidChange:nil];
        [tabs selectTabViewItem:originalSelection];
        [window setFrame:originalFrame display:NO];
        [panel close];
    }
}

- (void)testExternalFileOpenStylePreservesLegacyChoicesAndExplicitOverrides {
    NSUserDefaults *defaults = [iTermUserDefaults userDefaults];
    NSArray<NSString *> *keys = @[@"OpenFileInNewWindows", @"OpenFileInSplitPanes",
                                  @"OpenFileInVerticalSplitPane", @"NewInstanceOpenStyle"];
    NSMutableDictionary *original = [NSMutableDictionary dictionary];
    for (NSString *key in keys) { original[key] = [defaults objectForKey:key] ?: NSNull.null; }
    @try {
        for (NSString *key in keys) { [defaults removeObjectForKey:key]; }
        XCTAssertEqual([iTermAdvancedSettingsModel newInstanceOpenStyle], iTermOpenStyleTab);
        XCTAssertNil([defaults objectForKey:keys.lastObject]);
        // New-window takes precedence over split; missing orientation means
        // vertical. Cover the old -1 sentinel and out-of-range imported values.
        NSArray<NSArray *> *cases = @[
            @[@NO, @NO, @NO, @(iTermOpenStyleTab)],
            @[@NO, @NO, @YES, @(iTermOpenStyleTab)],
            @[@NO, @YES, @NO, @(iTermOpenStyleHorizontalSplit)],
            @[@NO, @YES, @YES, @(iTermOpenStyleVerticalSplit)],
            @[@NO, @YES, NSNull.null, @(iTermOpenStyleVerticalSplit)],
            @[@YES, @NO, @NO, @(iTermOpenStyleWindow)],
            @[@YES, @NO, @YES, @(iTermOpenStyleWindow)],
            @[@YES, @YES, @NO, @(iTermOpenStyleWindow)],
            @[@YES, @YES, @YES, @(iTermOpenStyleWindow)]
        ];
        for (NSArray *values in cases) {
            for (NSUInteger index = 0; index < 3; index++) {
                if (values[index] == NSNull.null) { [defaults removeObjectForKey:keys[index]]; }
                else { [defaults setObject:values[index] forKey:keys[index]]; }
            }
            for (id raw in @[NSNull.null, @(-1), @(-2), @99]) {
                if (raw == NSNull.null) { [defaults removeObjectForKey:keys.lastObject]; }
                else { [defaults setObject:raw forKey:keys.lastObject]; }
                XCTAssertEqual([iTermAdvancedSettingsModel newInstanceOpenStyle], [values[3] intValue]);
                XCTAssertEqualObjects([defaults objectForKey:keys.lastObject] ?: NSNull.null, raw);
            }
            for (NSNumber *explicit in @[@0, @1, @2, @3]) {
                [defaults setObject:explicit forKey:keys.lastObject];
                XCTAssertEqual([iTermAdvancedSettingsModel newInstanceOpenStyle], explicit.intValue);
            }
        }
    } @finally {
        for (NSString *key in keys) {
            if (original[key] == NSNull.null) { [defaults removeObjectForKey:key]; }
            else { [defaults setObject:original[key] forKey:key]; }
        }
    }
}

- (void)testExternalFileOpenStyleEditorShowsResolvedChoiceAndSavesOnlyNewKey {
    PreferencePanel *panel = [PreferencePanel sharedInstance];
    (void)panel.window;
    iTermAdvancedSettingsViewController *advanced = [panel valueForKey:@"_advancedViewController"];
    NSTableView *table = [advanced valueForKey:@"_tableView"];
    NSSearchField *search = [advanced valueForKey:@"_searchField"];
    NSButton *exclude = [advanced valueForKey:@"_excludeDefaults"];
    NSString *originalQuery = search.stringValue;
    NSControlStateValue originalState = exclude.state;
    NSUserDefaults *defaults = [iTermUserDefaults userDefaults];
    NSArray<NSString *> *keys = @[@"NewInstanceOpenStyle", @"OpenFileInNewWindows"];
    NSMutableDictionary *original = [NSMutableDictionary dictionary];
    for (NSString *key in keys) { original[key] = [defaults objectForKey:key] ?: NSNull.null; }
    @try {
        [defaults setInteger:-1 forKey:keys[0]];
        [defaults setBool:YES forKey:keys[1]];
        exclude.state = NSControlStateValueOn;
        search.stringValue = @"NewInstanceOpenStyle";
        [advanced advancedSettingsDidChange:nil];
        XCTAssertEqual(table.numberOfRows, 2);
        NSDictionary *setting = [advanced filteredAdvancedSettings][1];
        XCTAssertEqual([setting[kAdvancedSettingDefaultValue] intValue], iTermOpenStyleTab);
        NSPopUpButton *popup = (NSPopUpButton *)[table.delegate tableView:table viewForTableColumn:table.tableColumns[1] row:1];
        XCTAssertTrue([popup isKindOfClass:NSPopUpButton.class]);
        XCTAssertEqual(popup.numberOfItems, 4);
        XCTAssertEqual(popup.indexOfSelectedItem, iTermOpenStyleWindow);
        XCTAssertEqualObjects(popup.selectedItem.title, NSLocalizedString(@"New window", @"Open style"));
        [popup selectItemAtIndex:iTermOpenStyleTab];
        [NSApp sendAction:popup.action to:popup.target from:popup];
        XCTAssertEqual([defaults integerForKey:keys[0]], iTermOpenStyleTab);
        XCTAssertTrue([defaults boolForKey:keys[1]]);
        XCTAssertEqual([iTermAdvancedSettingsModel newInstanceOpenStyle], iTermOpenStyleTab);
        XCTAssertEqual(table.numberOfRows, 0);  // The resolved value is now the default.
        NSSet *retired = [NSSet setWithArray:@[@"OpenFileInNewWindows", @"OpenFileInSplitPanes",
                                              @"OpenFileInVerticalSplitPane", @"DisableWindowShadowWhenTransparencyOnMojave"]];
        for (iTermPreferencesSearchDocument *doc in advanced.searchableViewControllerDocuments) {
            XCTAssertFalse([retired containsObject:doc.identifier]);
        }
    } @finally {
        for (NSString *key in keys) {
            if (original[key] == NSNull.null) { [defaults removeObjectForKey:key]; }
            else { [defaults setObject:original[key] forKey:key]; }
        }
        search.stringValue = originalQuery;
        exclude.state = originalState;
        [advanced advancedSettingsDidChange:nil];
        [panel close];
    }
}

- (void)testExpertEditorsPreserveNumericValuesAndMarkChangedBooleans {
    PreferencePanel *panel = [PreferencePanel sharedInstance];
    (void)panel.window;
    iTermAdvancedSettingsViewController *advanced = [panel valueForKey:@"_advancedViewController"];
    NSTableView *table = [advanced valueForKey:@"_tableView"];
    NSSearchField *search = [advanced valueForKey:@"_searchField"];
    NSButton *exclude = [advanced valueForKey:@"_excludeDefaults"];
    NSUserDefaults *defaults = [iTermUserDefaults userDefaults];
    id originalBool = [defaults objectForKey:@"UseUnevenTabs"];
    id originalInt = [defaults objectForKey:@"MinTabWidth"];
    @try {
        exclude.state = NSControlStateValueOff;
        search.stringValue = @"UseUnevenTabs";
        [advanced advancedSettingsDidChange:nil];
        NSDictionary *setting = [advanced filteredAdvancedSettings][1];
        const BOOL defaultValue = [setting[kAdvancedSettingDefaultValue] boolValue];
        [defaults setBool:defaultValue forKey:@"UseUnevenTabs"];
        NSButton *checkbox = (NSButton *)[table.delegate tableView:table viewForTableColumn:table.tableColumns[1] row:1];
        XCTAssertTrue([checkbox isKindOfClass:NSButton.class]);
        XCTAssertFalse([checkbox isKindOfClass:NSPopUpButton.class]);
        [checkbox performClick:nil];
        XCTAssertEqual([defaults boolForKey:@"UseUnevenTabs"], !defaultValue);
        NSTextField *name = (NSTextField *)[table.delegate tableView:table viewForTableColumn:table.tableColumns[0] row:1];
        NSFont *font = [name.attributedStringValue attribute:NSFontAttributeName atIndex:1 effectiveRange:NULL];
        XCTAssertTrue(([NSFontManager.sharedFontManager traitsOfFont:font] & NSBoldFontMask) != 0);
        XCTAssertFalse([table.delegate tableView:table shouldSelectRow:1]);
        XCTAssertEqual(table.selectionHighlightStyle, NSTableViewSelectionHighlightStyleNone);
        [defaults setBool:defaultValue forKey:@"UseUnevenTabs"];
        name = (NSTextField *)[table.delegate tableView:table viewForTableColumn:table.tableColumns[0] row:1];
        font = [name.attributedStringValue attribute:NSFontAttributeName atIndex:1 effectiveRange:NULL];
        XCTAssertEqual([NSFontManager.sharedFontManager traitsOfFont:font] & NSBoldFontMask, 0);

        search.stringValue = @"MinTabWidth";
        [advanced advancedSettingsDidChange:nil];
        [defaults setInteger:72 forKey:@"MinTabWidth"];
        NSView *wrapper = [table.delegate tableView:table viewForTableColumn:table.tableColumns[1] row:1];
        NSTextField *input = (NSTextField *)wrapper.subviews.firstObject;
        for (NSString *invalid in @[@"", @"-", @"wrong", @"12px", @"4.5"]) {
            input.stringValue = invalid;
            [advanced controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:input]];
            XCTAssertEqual([defaults integerForKey:@"MinTabWidth"], 72);
        }
        [advanced controlTextDidEndEditing:[NSNotification notificationWithName:NSControlTextDidEndEditingNotification object:input]];
        XCTAssertEqualObjects(input.stringValue, @"72");
        input.stringValue = @"84";
        [advanced controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:input]];
        XCTAssertEqual([defaults integerForKey:@"MinTabWidth"], 84);
    } @finally {
        if (originalBool) { [defaults setObject:originalBool forKey:@"UseUnevenTabs"]; }
        else { [defaults removeObjectForKey:@"UseUnevenTabs"]; }
        if (originalInt) { [defaults setObject:originalInt forKey:@"MinTabWidth"]; }
        else { [defaults removeObjectForKey:@"MinTabWidth"]; }
        search.stringValue = @"";
        [advanced advancedSettingsDidChange:nil];
        [panel close];
    }
}

- (void)testLocalizedKeyPresetsKeepTheirStorageNamesAndImportIgnoresRetiredTouchBarItems {
    SettingsKeyMappingDelegate *delegate = [[SettingsKeyMappingDelegate alloc] init];
    iTermKeyMappingViewController *controller = [[iTermKeyMappingViewController alloc] init];
    controller.delegate = delegate;
    NSView *placeholder = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 600, 400)];
    controller.placeholderView = placeholder;
    NSPopUpButton *popup = [controller valueForKey:@"_presetsPopup"];
    NSMenuItem *preset = popup.itemArray[1];
    XCTAssertEqualObjects(preset.title, NSLocalizedString(@"Factory Defaults", @"Preset"));
    XCTAssertEqualObjects(preset.representedObject, @"Factory Defaults");
    [popup selectItem:preset];
    [controller loadPresets:popup];
    XCTAssertEqualObjects(delegate.loadedPreset, @"Factory Defaults");
    XCTAssertEqual(popup.bezelStyle, NSBezelStyleRounded);
    for (iTermPreferencesSearchDocument *document in [(id)[[PreferencePanel sharedInstance] valueForKey:@"_keysViewController"] searchableViewControllerDocuments]) {
        XCTAssertFalse([document.displayName.lowercaseString containsString:@"touch bar"]);
    }
    NSDictionary *legacy = @{@"Key Mappings": @{@"0x61-0x0": @{@"Action": @0, @"Text": @""}},
                             @"Touch Bar Items": @{@"touchbar:old": @{@"Action": @0, @"Text": @"", @"Label": @"Old"}}};
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
    NSData *data = [NSJSONSerialization dataWithJSONObject:legacy options:0 error:NULL];
    XCTAssertTrue([data writeToURL:url atomically:YES]);
    [controller importFromOpenPanel:url];
    XCTAssertEqual(delegate.importedKeys, 1);
    [[NSFileManager defaultManager] removeItemAtURL:url error:NULL];
}

- (void)testPackagedFontPickerLoadsResourcesAndPreservesFontSelection {
    NSBundle *appBundle = NSBundle.mainBundle;
    NSURL *resourceURL = [appBundle URLForResource:@"BetterFontPicker_BetterFontPicker"
                                    withExtension:@"bundle"];
    XCTAssertNotNil(resourceURL);
    NSBundle *resources = resourceURL ? [NSBundle bundleWithURL:resourceURL] : nil;
    XCTAssertNotNil([resources URLForResource:@"MainViewController" withExtension:@"nib"]);
    for (NSString *name in @[@"EmptyStar", @"FilledStar", @"HorizontalSpacingIcon", @"VerticalSpacingIcon"]) {
        NSImage *image = [resources imageForResource:name];
        XCTAssertNotNil(image, @"%@", name);
        XCTAssertGreaterThan(image.size.width, 1, @"%@", name);
    }
    NSURL *frameworkURL = [appBundle.privateFrameworksURL URLByAppendingPathComponent:@"BetterFontPicker.framework"];
    NSBundle *framework = [NSBundle bundleWithURL:frameworkURL];
    XCTAssertNotNil(framework.executableURL);
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:framework.executablePath]);

    Class controllerClass = NSClassFromString(@"BFPMainViewController");
    XCTAssertNotNil(controllerClass);
    NSViewController *controller = [[controllerClass alloc] initWithNibName:nil bundle:nil];
    XCTAssertNotNil(controller.view);
    NSTableView *table = [controller valueForKey:@"tableView"];
    XCTAssertEqualObjects(NSStringFromClass(table.class), @"BFPFontListTableView");
    XCTAssertNotNil(table.dataSource);
    [table reloadData];
    XCTAssertGreaterThan(table.numberOfRows, 0);

    Class pickerClass = NSClassFromString(@"BFPCompositeView");
    XCTAssertNotNil(pickerClass);
    NSView *picker = [[pickerClass alloc] initWithFrame:NSMakeRect(0, 0, 400, 40)];
    NSFont *font = [NSFont monospacedSystemFontOfSize:17 weight:NSFontWeightRegular];
    [picker setValue:font forKey:@"font"];
    NSFont *selectedFont = [picker valueForKey:@"font"];
    XCTAssertEqualObjects(selectedFont.fontName, font.fontName);
    XCTAssertEqualWithAccuracy(selectedFont.pointSize, font.pointSize, 0.01);
}

- (void)testPackagedActionDropdownLoadsItsResourceBundle {
    NSBundle *appBundle = NSBundle.mainBundle;
    NSURL *resourceURL = [appBundle URLForResource:@"SearchableComboListView_SearchableComboListView"
                                    withExtension:@"bundle"];
    XCTAssertNotNil(resourceURL);
    NSBundle *resources = resourceURL ? [NSBundle bundleWithURL:resourceURL] : nil;
    XCTAssertNotNil([resources URLForResource:@"SearchableComboView" withExtension:@"nib"]);
    Class dropdownClass = NSClassFromString(@"iTermSearchableComboView");
    XCTAssertNotNil(dropdownClass);
    NSURL *frameworkURL = [appBundle.privateFrameworksURL URLByAppendingPathComponent:@"SearchableComboListView.framework"];
    NSBundle *framework = [NSBundle bundleWithURL:frameworkURL];
    XCTAssertNotNil(framework.executableURL);
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:framework.executablePath]);

    iTermEditKeyActionWindowController *controller = [[iTermEditKeyActionWindowController alloc]
        initWithContext:iTermVariablesSuggestionContextSession
                   mode:iTermEditKeyActionWindowControllerModeKeyboardShortcut];
    [controller setAction:KEY_ACTION_IGNORE parameter:@"" applyMode:iTermActionApplyModeCurrentSession];
    XCTAssertNotNil(controller.window);
    NSPopUpButton *dropdown = [controller valueForKey:@"_comboView"];
    XCTAssertTrue([dropdown isKindOfClass:dropdownClass]);
    XCTAssertTrue([dropdown selectItemWithTag:KEY_ACTION_IGNORE]);
    XCTAssertEqual(dropdown.selectedTag, KEY_ACTION_IGNORE);
    XCTAssertNotNil(dropdown.selectedItem);
    XCTAssertEqualObjects(dropdown.selectedItem.title, dropdown.title);
    XCTAssertFalse([dropdown selectItemWithTag:NSIntegerMax]);
    XCTAssertEqual(dropdown.selectedTag, -1);
    XCTAssertNil(dropdown.selectedItem);
    NSArray *nibObjects = nil;
    SettingsDropdownNibOwner *owner = [[SettingsDropdownNibOwner alloc] initWithNibName:nil bundle:nil];
    XCTAssertTrue([resources loadNibNamed:@"SearchableComboView" owner:owner topLevelObjects:&nibObjects]);
    NSView *content = owner.view;
    XCTAssertEqualObjects(NSStringFromClass(content.class), @"SearchableComboListView.SearchableComboContentView");
    XCTAssertEqualObjects(NSStringFromClass(content.subviews.firstObject.class),
                          @"SearchableComboListView.SearchableComboVibrantVisualEffectView");
    [controller close];
}

- (void)testKeyboardActionEditorRequiresKeystrokeAndHidesActionTitle {
    iTermEditKeyActionWindowController *controller = [[iTermEditKeyActionWindowController alloc]
        initWithContext:iTermVariablesSuggestionContextSession
                   mode:iTermEditKeyActionWindowControllerModeKeyboardShortcut];
    [controller setAction:KEY_ACTION_IGNORE parameter:@"" applyMode:iTermActionApplyModeCurrentSession];
    XCTAssertNotNil(controller.window);
    NSTextField *title = [controller valueForKey:@"_actionTitleField"];
    NSView *shortcut = [controller valueForKey:@"_shortcutField"];
    XCTAssertNotNil(title);
    XCTAssertTrue(title.hidden);
    XCTAssertFalse(shortcut.hidden);
    XCTAssertFalse([controller shouldEnableOK]);
    iTermKeystroke *keystroke = [[iTermKeystroke alloc] initWithSerialized:@"0x61-0x0"];
    controller.currentKeystroke = keystroke;
    XCTAssertTrue([controller shouldEnableOK]);
    [controller ok:nil];
    XCTAssertTrue(controller.ok);
    XCTAssertEqualObjects(controller.currentKeystroke, keystroke);
    XCTAssertEqual(controller.action, KEY_ACTION_IGNORE);
    [controller close];
}

- (void)testUnboundActionEditorPreservesPlainInterpolatedAndEmptyTitles {
    for (NSNumber *interpolated in @[@NO, @YES]) {
        iTermEditKeyActionWindowController *controller = [[iTermEditKeyActionWindowController alloc]
            initWithContext:iTermVariablesSuggestionContextSession
                       mode:iTermEditKeyActionWindowControllerModeUnbound];
        controller.titleIsInterpolated = interpolated.boolValue;
        controller.label = @"Saved action title";
        [controller setAction:KEY_ACTION_IGNORE parameter:@"" applyMode:iTermActionApplyModeCurrentSession];
        XCTAssertNotNil(controller.window);
        NSTextField *title = [controller valueForKey:@"_actionTitleField"];
        NSView *shortcut = [controller valueForKey:@"_shortcutField"];
        XCTAssertNotNil(title);
        XCTAssertFalse(title.hidden);
        XCTAssertTrue(shortcut.hidden);
        XCTAssertNotNil(title.delegate);
        XCTAssertEqualObjects(title.stringValue, controller.label);
        XCTAssertTrue([controller shouldEnableOK]);
        NSString *const editedTitle = interpolated.boolValue ? @"Session \\(session.name)" : @"Renamed action";
        title.stringValue = editedTitle;
        [controller ok:nil];
        XCTAssertTrue(controller.ok);
        XCTAssertEqualObjects(controller.unboundAction.title, editedTitle);
        title.stringValue = @"";
        XCTAssertTrue([controller shouldEnableOK]);
        [controller ok:nil];
        XCTAssertEqualObjects(controller.unboundAction.title, @"");
        [controller close];
    }
}

- (void)testSnippetEditorUsesLocalizedWindowWithoutTranslatingUserContent {
    iTermSnippet *snippet = [[iTermSnippet alloc] initWithTitle:@"Title" value:@"Cancel" guid:NSUUID.UUID.UUIDString
                                                        tags:@[@"General"] escaping:iTermSendTextEscapingCommon
                                                     version:[iTermSnippet currentVersion]];
    iTermEditSnippetWindowController *controller = [[iTermEditSnippetWindowController alloc]
        initWithSnippet:snippet completion:^(iTermSnippet *result) {}];
    XCTAssertEqualObjects(controller.window.title, NSLocalizedString(@"Edit Snippet", @"Snippet editor"));
    XCTAssertEqualObjects([[controller valueForKey:@"_titleView"] stringValue], @"Title");
    XCTAssertEqualObjects([[controller valueForKey:@"_valueView"] string], @"Cancel");
    [controller close];
}

@end
