/*
 **  PreferencePanel.m
 **
 **  Copyright (c) 2002, 2003
 **
 **  Author: Fabian, Ujwal S. Setlur
 **
 **  Project: iTerm
 **
 **  Description: Implements the model and controller for the preference panel.
 **
 **  This program is free software; you can redistribute it and/or modify
 **  it under the terms of the GNU General Public License as published by
 **  the Free Software Foundation; either version 2 of the License, or
 **  (at your option) any later version.
 **
 **  This program is distributed in the hope that it will be useful,
 **  but WITHOUT ANY WARRANTY; without even the implied warranty of
 **  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 **  GNU General Public License for more details.
 **
 **  You should have received a copy of the GNU General Public License
 **  along with this program; if not, write to the Free Software
 **  Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

/*
 * Preferences in iTerm2 are complicated, to say the least. Here is how the classes are organized.
 *
 * - PreferencePanel: There are two instances of this class: -sharedInstance and -sessionsInstance.
 *       The sharedInstance is the app settings panel, while sessionsInstance is for editing a
 *       single session (View>Edit Current Session).
 *     - GeneralPreferencesViewController:    View controller for Prefs>General
 *     - AppearancePreferencesViewController: View controller for Prefs>Appearance
 *     - KeysPreferencesViewController:       View controller for Prefs>Keys
 *     - PointerPreferencesViewController:    View controller for Prefs>Pointer
 *     - iTermShortcutsViewController:        View controller for Prefs>Shortcuts
 *     - ProfilePreferencesViewController:    View controller for Prefs>Profiles
 *     - WindowArrangements:                  Owns Prefs>Arrangements
 *     - iTermAdvancedSettingsController:     Owns Prefs>Advanced
 *
 *  View controllers of tabs in PreferencePanel derive from iTermPreferencesBaseViewController.
 *  iTermPreferencesBaseViewController provides a map from NSControl* to PreferenceInfo.
 *  PreferenceInfo stores a pref's type, user defaults key, can constrain its value, and
 *  stores pointers to blocks that are run when a value is changed or a field needs to be updated
 *  for customizing how controls are bound to storage. Each view controller defines these bindings
 *  in its -awakeFromNib method.
 *
 *  User defaults are accessed through iTermPreferences, which assigns string constants to user
 *  defaults keys, defines default values for each key, and provides accessors. It also allows the
 *  exposed values to be computed from underlying values. (Currently, iTermPreferences is not used
 *  by advanced settings, but that should change).
 *
 *  Because per-profile preferences are similar, a parallel class structure exists for them.
 *  The following classes are view controllers for tabs in Prefs>Profiles:
 *
 *  - ProfilesGeneralPreferencesViewController
 *  - ProfilesColorPreferencesViewController
 *  - ProfilesTextPreferencesViewController
 *  - ProfilesWindowPreferencesViewController
 *  - ProfilesTerminalPreferencesViewController
 *  - ProfilesKeysPreferencesViewController
 *  - ProfilesAdvancedPreferencesViewController
 *
 *  These derive from iTermProfilePreferencesBaseViewController, which is just like
 *  iTermPreferencesBaseViewController, but its methods for accessing preference values take an
 *  additional profile: parameter. The analog of iTermPreferences is iTermProfilePreferences.
 *  */
#import "PreferencePanel.h"
#import "SFSymbolEnum/SFSymbolEnum.h"

#import "AppearancePreferencesViewController.h"
#import "DebugLogging.h"
#import "GeneralPreferencesViewController.h"
#import "ITAddressBookMgr.h"
#import "KeysPreferencesViewController.h"
#import "NSAppearance+iTerm.h"
#import "NSArray+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSFileManager+iTerm.h"
#import "NSImage+iTerm.h"
#import "NSNumber+iTerm.h"
#import "NSPopUpButton+iTerm.h"
#import "NSStringITerm.h"
#import "NSView+iTerm.h"
#import "NSWindow+iTerm.h"
#import "PTYSession.h"
#import "PasteboardHistory.h"
#import "PointerPrefsController.h"
#import "ProfileModel.h"
#import "ProfilePreferencesViewController.h"
#import "ProfilesColorsPreferencesViewController.h"
#import "PseudoTerminal.h"
#import "SessionView.h"
#import "WindowArrangements.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermAdvancedSettingsViewController.h"
#import "iTermApplication.h"
#import "iTermApplicationDelegate.h"
#import "iTermController.h"
#import "iTermKeyMappingViewController.h"
#import "iTermLaunchServices.h"
#import "iTermPreferences.h"
#import "iTermPreferencesSearch.h"
#import "iTermPreferencesSearchEngineResultsWindowController.h"
#import "iTermRemotePreferences.h"
#import "iTermSearchableViewController.h"
#import "iTermShortcutsViewController.h"
#import "iTermSizeRememberingView.h"
#import "iTermUserDefaults.h"
#import "iTermWarning.h"
#include <stdlib.h>

NSString *const kRefreshTerminalNotification = @"kRefreshTerminalNotification";
NSString *const kUpdateLabelsNotification = @"kUpdateLabelsNotification";
NSString *const kPreferencePanelDidUpdateProfileFields = @"kPreferencePanelDidUpdateProfileFields";
NSString *const kSessionProfileDidChange = @"kSessionProfileDidChange";
NSString *const kPreferencePanelDidLoadNotification = @"kPreferencePanelDidLoadNotification";
NSString *const kPreferencePanelWillCloseNotification = @"kPreferencePanelWillCloseNotification";

static NSString *const iTermPrefsScrimMouseUpNotification = @"iTermPrefsScrimMouseUpNotification";

CGFloat iTermPreferencePanelGetWindowMinimumWidth(BOOL session) {
    if (session) {
        return 560;
    }
#if DEBUG
    if (@available(macOS 26.1, *)) {} else if (@available(macOS 26, *)) {
        // Work around a bug in macOS Tahoe that causes constraint failures
        return 880;
    }
#endif

    // Preserve enough room for the existing preference forms and inner tabs.
    return 785;
}

// Strong references to the two preference panels.
static PreferencePanel *gSharedPreferencePanel;
static PreferencePanel *gSessionsPreferencePanel;

@interface iTermPrefsScrim : NSView
@property (nonatomic) NSView *cutoutView;
@end

@implementation iTermPrefsScrim {
    NSClickGestureRecognizer *_recognizer;
    BOOL savedPostNotifs;
    __weak NSClipView *_enclosingClipView;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _recognizer = [[NSClickGestureRecognizer alloc] initWithTarget:self action:@selector(click:)];
        [self addGestureRecognizer:_recognizer];
    }
    return self;
}

- (void)setCutoutView:(NSView *)cutoutView {
    _enclosingClipView.postsBoundsChangedNotifications = savedPostNotifs;
    [[NSNotificationCenter defaultCenter] removeObserver:self];

    _cutoutView = cutoutView;

    NSView *temp = cutoutView;
    NSScrollView *outermostScrollview = nil;
    while (temp.enclosingScrollView) {
        outermostScrollview = temp.enclosingScrollView;
        temp = outermostScrollview;
    }
    _enclosingClipView = outermostScrollview.contentView;
    if (_enclosingClipView) {
        savedPostNotifs = _enclosingClipView.postsBoundsChangedNotifications;
        _enclosingClipView.postsBoundsChangedNotifications = YES;
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(scrollViewDidScroll:)
                                                     name:NSViewBoundsDidChangeNotification
                                                   object:_enclosingClipView];
    }
    [self setNeedsDisplay:YES];
}

- (void)scrollViewDidScroll:(NSNotification *)notification {
    [self setNeedsDisplay:YES];
}

- (BOOL)isOpaque {
    return NO;
}

- (void)drawRect:(NSRect)dirtyRect {
    dirtyRect = NSIntersectionRect(dirtyRect, self.bounds);
    const BOOL darkMode = [self.window.effectiveAppearance it_isDark];
    const CGFloat baselineAlpha = darkMode ? 0.8 : 0.7;
    [[[NSColor blackColor] colorWithAlphaComponent:baselineAlpha] set];
    NSRectFill(dirtyRect);

    if (!_cutoutView) {
        return;
    }
    NSRect rect = [self convertRect:_cutoutView.bounds fromView:_cutoutView];

    const NSInteger steps = darkMode ? 15 : 30;
    const CGFloat stepSize = 0.5;
    const CGFloat highlightAlpha = darkMode ? 0.0 : 0.2;
    const CGFloat alphaStride = (baselineAlpha - highlightAlpha) / steps;
    CGFloat a = baselineAlpha - alphaStride;
    [[[NSColor blackColor] colorWithAlphaComponent:a] set];

    [[NSGraphicsContext currentContext] setCompositingOperation:NSCompositingOperationCopy];
    for (int i = 0; i < steps; i++) {
        const int r = (steps - i - 1);
        const CGFloat inset = stepSize * r;
        [[[NSColor blackColor] colorWithAlphaComponent:a] set];
        const NSRect insetRect = NSInsetRect(rect, -inset, -inset);
        const CGFloat radius = (inset + 1) * 2;
        NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:insetRect xRadius:radius yRadius:radius];
        [path fill];
        a -= alphaStride;
    }
}

- (void)click:(NSGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer.state == NSGestureRecognizerStateRecognized) {
        [[NSNotificationCenter defaultCenter] postNotificationName:iTermPrefsScrimMouseUpNotification object:nil];
    }
}

@end

@interface iTermPrefsFieldEditor: NSTextView
@end

@implementation iTermPrefsFieldEditor

- (BOOL)isFieldEditor {
    return YES;
}

- (BOOL)isRichText {
    return NO;
}

- (NSMenu *)menuForEvent:(NSEvent *)event {
    NSMenu *menu = [super menuForEvent:event];
    if (!menu) {
        return nil;
    }
    NSTextField *textField = [NSTextField castFrom:self.delegate];
    if (!textField) {
        return menu;
    }

    id defaultObj = [self defaultObjectForSetting];
    if (!defaultObj) {
        return menu;
    }
    NSString *defaultString = nil;
    if ([defaultObj isKindOfClass:[NSString class]])  {
        if ([textField.stringValue isEqualToString:defaultObj]) {
            return menu;
        }
        defaultString = defaultObj;
    } else if ([defaultObj isKindOfClass:[NSNumber class]]) {
        NSNumber *n = defaultObj;
        if ([n isEqualToString:textField.stringValue threshold:0.001]) {
            return menu;
        }
        NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
        formatter.locale = [NSLocale currentLocale];
        formatter.numberStyle = NSNumberFormatterDecimalStyle;
        formatter.generatesDecimalNumbers = YES;
        formatter.allowsFloats = n.it_hasFractionalPart;
        defaultString = [formatter stringFromNumber:n];

    } else {
        return menu;
    }
    NSString *repr = defaultString;
    if (!repr.length) {
        repr = @"Empty Default";
    }
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"Reset to %@", repr]
                                                  action:@selector(resetPrefToDefaultValue:)
                                           keyEquivalent:@""];
    item.target = self;
    item.representedObject = defaultString;
    [menu insertItem:item atIndex:0];
    [menu insertItem:[NSMenuItem separatorItem] atIndex:1];
    return menu;
}

- (id)defaultObjectForSetting {
    NSTextField *textField = [NSTextField castFrom:self.delegate];
    if (!textField) {
        return nil;
    }

    NSResponder *responder = textField;
    while (responder != nil && ![responder isKindOfClass:[iTermPreferencesBaseViewController class]]) {
        responder = responder.nextResponder;
    }
    iTermPreferencesBaseViewController *vc = [iTermPreferencesBaseViewController castFrom:responder];
    if (!vc) {
        return nil;
    }
    PreferenceInfo *info = [vc safeInfoForControl:textField];
    if (!info) {
        return nil;
    }
    return [vc defaultValueForKey:info.key];
}

- (NSString *)defaultValueForSetting {
    id obj = [self defaultObjectForSetting];
    NSString *defaultValue = [NSString castFrom:obj];
    if (!defaultValue) {
        defaultValue = [[NSNumber castFrom:obj] stringValue];
    }
    if (!defaultValue) {
        return nil;
    }
    return defaultValue;
}

- (void)resetPrefToDefaultValue:(id)sender {
    NSTextField *textField = [NSTextField castFrom:self.delegate];
    if (!textField) {
        return;
    }

    textField.stringValue = [sender representedObject];
}
@end

@implementation iTermPrefsPanel {
    iTermPrefsFieldEditor *_fieldEditor;
}

- (BOOL)setFrameUsingName:(NSWindowFrameAutosaveName)name {
    return [self setFrameUsingName:name force:NO];
}

- (NSString *)userDefaultsKeyForFrameName:(NSString *)name {
    return [NSString stringWithFormat:@"NoSyncFrame_%@", name];
}

- (BOOL)setFrameUsingName:(NSWindowFrameAutosaveName)name force:(BOOL)force {
    NSDictionary *dict = [[iTermUserDefaults userDefaults] objectForKey:[self userDefaultsKeyForFrameName:name]];
    return [self setFrameFromDict:dict];
}

- (void)saveFrameUsingName:(NSWindowFrameAutosaveName)name {
    [[iTermUserDefaults userDefaults] setObject:[self dictForFrame:self.frame onScreen:self.screen]
                                              forKey:[self userDefaultsKeyForFrameName:name]];
}

- (BOOL)haveSavedFrameForFrameWithName:(NSString *)name {
    return [[iTermUserDefaults userDefaults] objectForKey:[self userDefaultsKeyForFrameName:name]] != nil;
}

- (BOOL)setFrameFromDict:(NSDictionary *)dict {
    if (!dict[@"topLeft"] || !dict[@"screenFrame"]) {
        return NO;
    }
    const NSPoint topLeft = NSPointFromString(dict[@"topLeft"]);
    const NSRect screenFrame = NSRectFromString(dict[@"screenFrame"]);

    for (NSScreen *screen in [NSScreen screens]) {
        if (NSEqualRects(screen.frame, screenFrame)) {
            NSRect frame = self.frame;
            if (dict[@"size"]) {
                NSSize size = NSSizeFromString(dict[@"size"]);
                frame.size.width = MIN(screen.visibleFrame.size.width, MAX(self.minSize.width, size.width));
                frame.size.height = MIN(screen.visibleFrame.size.height, MAX(self.minSize.height, size.height));
            }
            frame.origin.x = topLeft.x;
            frame.origin.y = topLeft.y - frame.size.height;
            [self setFrame:frame display:NO];
            return YES;
        }
    }
    return NO;
}

- (NSDictionary *)dictForFrame:(NSRect)frame onScreen:(NSScreen *)screen {
    const NSPoint topLeft = NSMakePoint(frame.origin.x,
                                        frame.origin.y + frame.size.height);
    return @{ @"topLeft": NSStringFromPoint(topLeft),
              @"screenFrame": NSStringFromRect(screen.frame),
              @"size": NSStringFromSize(frame.size) };
}

- (NSWindowPersistableFrameDescriptor)stringWithSavedFrame {
    return @"";
}

- (void)setFrameFromString:(NSWindowPersistableFrameDescriptor)string {
}

// Animated window changes call this a lot of times fast. Dumber than iOS, but occasionally comprehensible!
- (void)setFrame:(NSRect)frameRect display:(BOOL)flag {
    [super setFrame:frameRect display:flag];
    [self.prefsPanelDelegate prefsPanelDidChangeFrameTo:frameRect];
}

- (BOOL)makeFirstResponder:(NSResponder *)responder {
    BOOL result = [self it_makeFirstResponderIfNotDeclined:responder callSuper:^BOOL(NSResponder *newResponse) {
        return [super makeFirstResponder:newResponse];
    }];
    if (result) {
        [self.prefsPanelDelegate responderWillBecomeFirstResponder:responder];
    }
    return result;
}

- (NSText *)fieldEditor:(BOOL)createFlag forObject:(id)object {
    if (![object isKindOfClass:[NSTextField class]]) {
        return [super fieldEditor:createFlag forObject:object];
    }
    if (createFlag && !_fieldEditor) {
        _fieldEditor = [[iTermPrefsFieldEditor alloc] initWithFrame:NSZeroRect];
        _fieldEditor.fieldEditor = YES;
        _fieldEditor.richText = NO;
    }
    return _fieldEditor;
}

@end

@interface PreferencePanel() <iTermPrefsPanelDelegate, iTermPreferencesSearchEngineResultsWindowControllerDelegate, NSSearchFieldDelegate, NSTabViewDelegate, iTermPreferencePanelSizing, NSMenuItemValidation>

@end

static iTermPreferencesSearchEngine *gSearchEngine;

@implementation PreferencePanel {
    ProfileModel *_profileModel;
    BOOL _editCurrentSessionMode;
    IBOutlet GeneralPreferencesViewController *_generalPreferencesViewController;
    IBOutlet AppearancePreferencesViewController *_appearancePreferencesViewController;
    IBOutlet KeysPreferencesViewController *_keysViewController;
    IBOutlet ProfilePreferencesViewController *_profilesViewController;
    IBOutlet PointerPreferencesViewController *_pointerViewController;
    IBOutlet iTermAdvancedSettingsViewController *_advancedViewController;
    IBOutlet iTermShortcutsViewController *_shortcutsViewController;

    IBOutlet NSTabView *_tabView;
    iTermSettingsSidebarView *_settingsSidebar;
    iTermSettingsContentView *_settingsContent;
    iTermSettingsPageHeaderView *_settingsHeader;
    NSArray<iTermSettingsPage *> *_settingsPages;
    IBOutlet NSTabViewItem *_globalTabViewItem;
    IBOutlet NSTabViewItem *_appearanceTabViewItem;
    IBOutlet NSTabViewItem *_keyboardTabViewItem;
    IBOutlet NSTabViewItem *_arrangementsTabViewItem;
    IBOutlet NSTabViewItem *_profilesTabViewItem;
    IBOutlet NSTabViewItem *_mouseTabViewItem;
    IBOutlet NSTabViewItem *_advancedTabViewItem;
    IBOutlet NSTabViewItem *_shortcutsTabViewItem;

    NSSearchField *_settingsSearchField;
    // This class is not well named. It is a view controller for the window
    // arrangements tab. It's also a singleton :(
    IBOutlet WindowArrangements *arrangements_;
    NSInteger _disableResize;
    BOOL _tmux;
    NSTimeInterval _delay;

    iTermPrefsScrim *_scrim;
    iTermPreferencesSearchEngineResultsWindowController *_serpWindowController;
    BOOL _revealingControl;
}

+ (instancetype)sharedInstance {
    if (!gSharedPreferencePanel) {
        gSharedPreferencePanel = [[PreferencePanel alloc] initWithProfileModel:[ProfileModel sharedInstance]
                                                        editCurrentSessionMode:NO];
    }
    return gSharedPreferencePanel;
}

+ (instancetype)sessionsInstance {
    if (!gSessionsPreferencePanel) {
        gSessionsPreferencePanel = [[PreferencePanel alloc] initWithProfileModel:[ProfileModel sessionsInstance]
                                                          editCurrentSessionMode:YES];
    }
    return gSessionsPreferencePanel;
}

- (BOOL)isSessionsInstance {
    return (self == [PreferencePanel sessionsInstance]);
}

- (instancetype)initWithProfileModel:(ProfileModel*)model
              editCurrentSessionMode:(BOOL)editCurrentSessionMode {
    NSString *path = [iTermSettingsLocalization nibPath:@"PreferencePanel"];
    self = path ? [super initWithWindowNibPath:path owner:self] : [super initWithWindowNibName:@"PreferencePanel"];
    if (self) {
        _profileModel = model;

        _editCurrentSessionMode = editCurrentSessionMode;
    }
    return self;
}

- (BOOL)autoHidesHotKeyWindow {
    return NO;
}

#pragma mark - View layout

- (void)awakeFromNib {
    ITAssertWithMessage(self.isWindowLoaded, @"window not loaded in %@", NSStringFromSelector(_cmd));
    [self.window setCollectionBehavior:NSWindowCollectionBehaviorMoveToActiveSpace];

    _globalTabViewItem.view = _generalPreferencesViewController.view;
    _appearanceTabViewItem.view = _appearancePreferencesViewController.view;
    _keyboardTabViewItem.view = _keysViewController.view;
    _arrangementsTabViewItem.view = arrangements_.view;
    _mouseTabViewItem.view = _pointerViewController.view;
    _advancedTabViewItem.view = _advancedViewController.view;
    _shortcutsTabViewItem.view = _shortcutsViewController.view;

    _generalPreferencesViewController.preferencePanel = self;
    _appearancePreferencesViewController.preferencePanel = self;
    _keysViewController.preferencePanel = self;
    _profilesViewController.preferencePanel = self;
    _profilesViewController.tmuxSession = _tmux;
    _pointerViewController.preferencePanel = self;
    _shortcutsViewController.preferencePanel = self;

    _settingsPages = @[
        [[iTermSettingsPage alloc] initWithCategory:iTermSettingsCategoryGeneral
                                       tabViewItem:_globalTabViewItem controller:_generalPreferencesViewController],
        [[iTermSettingsPage alloc] initWithCategory:iTermSettingsCategoryAppearance
                                       tabViewItem:_appearanceTabViewItem controller:_appearancePreferencesViewController],
        [[iTermSettingsPage alloc] initWithCategory:iTermSettingsCategoryProfiles
                                       tabViewItem:_profilesTabViewItem controller:_profilesViewController],
        [[iTermSettingsPage alloc] initWithCategory:iTermSettingsCategoryKeys
                                       tabViewItem:_keyboardTabViewItem controller:_keysViewController],
        [[iTermSettingsPage alloc] initWithCategory:iTermSettingsCategoryArrangements
                                       tabViewItem:_arrangementsTabViewItem controller:arrangements_],
        [[iTermSettingsPage alloc] initWithCategory:iTermSettingsCategoryPointer
                                       tabViewItem:_mouseTabViewItem controller:_pointerViewController],
        [[iTermSettingsPage alloc] initWithCategory:iTermSettingsCategoryShortcuts
                                       tabViewItem:_shortcutsTabViewItem controller:_shortcutsViewController],
        [[iTermSettingsPage alloc] initWithCategory:iTermSettingsCategoryAdvanced
                                       tabViewItem:_advancedTabViewItem controller:_advancedViewController]
    ];
    [self installSettingsContent];
    if (!_editCurrentSessionMode) {
        [self installSettingsSidebar];
    }

    if (_editCurrentSessionMode) {
        [self layoutSubviewsForEditCurrentSessionMode];
        self.window.title = NSLocalizedString(@"Edit Session", @"Session settings window");
    } else {
        [self resizeWindowForTabViewItem:_globalTabViewItem animated:NO];
        NSString *suiteName = [iTermUserDefaults customSuiteName];
        if (suiteName.length > 0) {
            self.window.title = [NSString stringWithFormat:NSLocalizedString(@"Settings: %@", @"Settings window with custom suite"), suiteName];
        } else {
            self.window.title = NSLocalizedString(@"Settings", @"Settings window");
        }
    }

    iTermPrefsPanel *panel = (iTermPrefsPanel *)self.window;
    panel.prefsPanelDelegate = self;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(scrimMouseUp:)
                                                 name:iTermPrefsScrimMouseUpNotification
                                               object:nil];
    if (!_editCurrentSessionMode && iTermUserDefaultsUnsavedController.allowed) {
        iTermUserDefaultsUnsavedController *unsaved = [[iTermUserDefaultsUnsavedController alloc] init];
        [self.window addTitlebarAccessoryViewController:unsaved];
    }
    if (!_editCurrentSessionMode) {
        [_profilesViewController selectDefaultProfile];
    }
}

- (void)installSettingsContent {
    self.window.toolbar = nil;
    self.window.styleMask |= NSWindowStyleMaskResizable;
    if (!_editCurrentSessionMode) {
        self.window.styleMask |= NSWindowStyleMaskFullSizeContentView;
        self.window.titleVisibility = NSWindowTitleHidden;
        self.window.titlebarAppearsTransparent = YES;
        self.window.titlebarSeparatorStyle = NSTitlebarSeparatorStyleNone;
        self.window.movableByWindowBackground = YES;
    }
    self.window.contentMinSize = NSMakeSize(820, 560);
    NSRect visible = (self.window.screen ?: NSScreen.mainScreen).visibleFrame;
    const NSSize preferredSize = _editCurrentSessionMode ? NSMakeSize(1280, 780) : NSMakeSize(1040, 720);
    [self.window setContentSize:NSMakeSize(MIN(preferredSize.width, visible.size.width - 40),
                                           MIN(preferredSize.height, visible.size.height - 80))];
    _settingsContent = [[iTermSettingsContentView alloc] initWithContent:_tabView];
    const CGFloat width = self.preferencePanelNavigationWidth;
    NSRect frame = self.window.contentView.bounds;
    frame.origin.x += width;
    frame.size.width -= width;
    if (!_editCurrentSessionMode) {
        const CGFloat headerHeight = iTermSettingsPageHeaderView.preferredHeight;
        _settingsHeader = [[iTermSettingsPageHeaderView alloc] initWithFrame:
            NSMakeRect(NSMinX(frame), NSMaxY(frame) - headerHeight, NSWidth(frame), headerHeight)];
        [self.window.contentView addSubview:_settingsHeader];
        frame.size.height -= headerHeight;
        self.window.backgroundColor = NSColor.windowBackgroundColor;
    }
    _settingsContent.frame = frame;
    [self.window.contentView addSubview:_settingsContent];
}

- (void)installSettingsSidebar {
    const CGFloat width = iTermSettingsSidebarView.preferredWidth;
    _settingsSidebar = [[iTermSettingsSidebarView alloc] initWithPages:_settingsPages
                                                        searchField:self.searchField];
    _settingsSidebar.frame = NSMakeRect(0, 0, width, NSHeight(self.window.contentView.bounds));
    __weak PreferencePanel *weakSelf = self;
    _settingsSidebar.onSelect = ^(iTermSettingsPage *page) {
        PreferencePanel *strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        [strongSelf hideScrimAndSERP];
        [strongSelf->_tabView selectTabViewItem:page.tabViewItem];
    };
    [self.window.contentView addSubview:_settingsSidebar];
    [self synchronizeNavigationForTabViewItem:_tabView.selectedTabViewItem];
}

- (void)layoutSubviewsForEditCurrentSessionMode {
    [self selectProfilesTab];
    [_profilesViewController layoutSubviewsForEditCurrentSessionMode];
    [_profilesViewController resizeWindowForCurrentTabAnimated:NO];
    [_profilesViewController didLayoutSubviewsForEditCurrentSessionMode];
}

#pragma mark - API

- (BOOL)toggleSetting:(NSString *)key {
    if (!key) {
        return NO;
    }
    if (![iTermPreferences keyHasDefaultValue:key]) {
        return NO;
    }
    [self window];
    for (NSTabViewItem *tabViewItem in _tabView.tabViewItems) {
        if ([tabViewItem.identifier isEqualToString:@"Profiles"]) {
            continue;
        }
        iTermPreferencesBaseViewController *vc = [self viewControllerForTabViewItem:tabViewItem];
        if (![vc hasControlWithKey:key]) {
            continue;
        }
        [vc tryToggleControlWithKey:key];
        break;
    }
    return YES;
}

- (BOOL)toggleProfileSetting:(NSString *)key {
    if (!key) {
        return NO;
    }
    [self window];
    if (![iTermProfilePreferences keyHasDefaultValue:key]) {
        return NO;
    }
    if (![_profilesViewController hasControlWithKey:key]) {
        return NO;
    }
    [_profilesViewController tryToggleControlWithKey:key];
    return YES;
}

- (void)configureHotkeyForProfile:(Profile *)profile {
    _profilesViewController.scope = nil;
    [self window];
    [self selectProfilesTab];
    [self run];
    [_profilesViewController openToProfileWithGuidAndEditHotKey:profile[KEY_GUID]
                                                          scope:nil];
}

- (void)selectProfilesTab {
    // We want to disable resizing when opening sessionsInstace because it
    // would resize to be way too big (leaving space for the profiles list).
    // You can also get here because you want to open prefs directly to the
    // profile tab (such as when coming from the Profiles window).
    const BOOL shouldDisableResize = [self isSessionsInstance];
    if (shouldDisableResize) {
       _disableResize++;
    }
    [_tabView selectTabViewItem:_profilesTabViewItem];
    if (shouldDisableResize) {
        _disableResize--;
    }
}

// NOTE: Callers should invoke makeKeyAndOrderFront if they are so inclined.
- (void)openToProfileWithGuid:(NSString *)guid
             selectGeneralTab:(BOOL)selectGeneralTab
                         tmux:(BOOL)tmux
                        scope:(iTermVariableScope<iTermSessionScope> *)scope
                   showWindow:(BOOL)show {
    _tmux = tmux;
    _profilesViewController.tmuxSession = tmux;
    _profilesViewController.scope = scope;
    [self window];
    [self selectProfilesTab];
    [self runAndShow:show];
    [_profilesViewController openToProfileWithGuid:guid
                                  selectGeneralTab:selectGeneralTab
                                             scope:scope];
}

- (void)openToProfileWithGuid:(NSString *)guid
andEditComponentWithIdentifier:(NSString *)identifier
                         tmux:(BOOL)tmux
                        scope:(iTermVariableScope<iTermSessionScope> *)scope {
    _tmux = tmux;
    _profilesViewController.tmuxSession = tmux;
    _profilesViewController.scope = scope;
    [self window];
    [self selectProfilesTab];
    [self run];
    [_profilesViewController openToProfileWithGuid:guid
                    andEditComponentWithIdentifier:identifier
                                             scope:scope];
}

- (void)openToProfileWithGuid:(NSString *)guid
                          key:(NSString *)key {
    _tmux = NO;
    _profilesViewController.tmuxSession = NO;
    _profilesViewController.scope = nil;
    [self window];
    [self selectProfilesTab];
    [self run];
    [_profilesViewController openToProfileWithGuid:guid];
    [self openToPreferenceWithKey:key];
}

- (void)openToPreferenceWithKey:(NSString *)key {
    [self window];
    [self buildSearchEngineIfNeeded];
    iTermPreferencesSearchDocument *document = [gSearchEngine documentWithKey:key];
    if (!document) {
        return;
    }
    [self run];
    // Let it become first responder. Then show the scrim. Becoming first responder hides the scrim.
    [self performSelector:@selector(revalDocument:) withObject:document afterDelay:0];
}

- (void)revalDocument:(iTermPreferencesSearchDocument *)document {
    [self showScrimIfNeeded];
    [self.window makeKeyAndOrderFront:nil];
    BOOL switchingTabs = NO;
    BOOL switchingInnerTabs = NO;
    [self revealDocument:document
           switchingTabs:&switchingTabs
      switchingInnerTabs:&switchingInnerTabs];
    [self fadeOutScrimAfterDelay:[self delayToWaitForTabToSwitch:switchingTabs
                                         waitForInnerTabToSwitch:switchingInnerTabs]];
}

- (NSWindow *)window {
    BOOL shouldPostWindowLoadNotification = !self.windowLoaded;
    NSWindow *window = [super window];
    if (shouldPostWindowLoadNotification) {
        [[NSNotificationCenter defaultCenter] postNotificationName:kPreferencePanelDidLoadNotification
                                                            object:self];
    }
    return window;
}

- (NSWindow *)windowIfLoaded {
    if (self.isWindowLoaded) {
        return self.window;
    } else {
        return nil;
    }
}

- (WindowArrangements *)arrangements {
    return arrangements_;
}

- (void)run {
    [self runAndShow:YES];
}

- (void)runAndShow:(BOOL)show {
    if (show) {
        [NSApp activateIgnoringOtherApps:YES];
    }
    [self window];
    [_generalPreferencesViewController updateEnabledState];
    [_profilesViewController selectFirstProfileIfNecessary];
    if (!self.window.isVisible && show) {
        [self showWindow:self];
    }
}

// Update the values in form fields to reflect the profile's state
- (void)underlyingProfileDidChange {
    [_profilesViewController refresh];
}

- (NSString *)nameForFrame {
    return [NSString stringWithFormat:@"%@Preferences", _profileModel.modelName];
}

- (NSArray<iTermSetting *> *)allSettings {
    return [_tabView.tabViewItems flatMapWithBlock:^NSArray *(__kindof NSTabViewItem *tabViewItem) {
        iTermSettingsPage *page = [self settingsPageForTabViewItem:tabViewItem];
        iTermPreferencesBaseViewController *vc = [self viewControllerForTabViewItem:tabViewItem];
        return page && vc ? [vc allSettingsWithPathComponents:@[page.title]] : @[];
    }];
}

#pragma mark - NSWindowController

- (void)windowWillLoad {
    DLog(@"Will load prefs panel from %@", [NSThread callStackSymbols]);
    // We finally set our autosave window frame name and restore the one from the user's defaults.
    [self setShouldCascadeWindows:NO];
}

- (void)windowDidLoad {
    // We shouldn't use setFrameAutosaveName: because this window controller controls two windows
    // with different frames (besides, I tried it and it doesn't work here for some reason).
    if (![(iTermPrefsPanel *)self.window haveSavedFrameForFrameWithName:self.nameForFrame]) {
        [self.window center];
    } else {
        [self.window setFrameUsingName:self.nameForFrame force:NO];
    }
}

#pragma mark - NSWindowDelegate

- (void)responderWillBecomeFirstResponder:(NSResponder *)responder {
    NSSearchField *searchField = self.searchField;
    if (responder == searchField && searchField.stringValue.length > 0) {
        [self showScrimAndSERP];
    } else if (responder != nil && !_revealingControl) {
        [self hideScrimAndSERP];
    }
}

- (void)windowDidMove:(NSNotification *)notification {
    [self.window saveFrameUsingName:self.nameForFrame];
}

- (void)windowWillClose:(NSNotification *)aNotification {
    [self.window saveFrameUsingName:self.nameForFrame];
    __typeof(self) strongSelf = self;
    if (self == gSharedPreferencePanel) {
        gSharedPreferencePanel = nil;
    } else if (self == gSessionsPreferencePanel) {
        gSessionsPreferencePanel = nil;
    }

    [strongSelf postWillCloseNotification];
    [[iTermUserDefaults userDefaults] synchronize];
}

- (void)windowDidBecomeKey:(NSNotification *)aNotification {
    [[NSNotificationCenter defaultCenter] postNotificationName:kNonTerminalWindowBecameKeyNotification
                                                        object:nil
                                                      userInfo:nil];
}

- (void)postWillCloseNotification {
    [[NSNotificationCenter defaultCenter] postNotificationName:kPreferencePanelWillCloseNotification
                                                        object:self];
}

- (void)updateSERPOrigin {
    if (!_serpWindowController) {
        return;
    }
    NSRect searchRect = [self.window convertRectToScreen:[self.searchField convertRect:self.searchField.bounds toView:nil]];
    NSRect visible = (self.window.screen ?: NSScreen.mainScreen).visibleFrame;
    [_serpWindowController positionRelativeToSearchRect:searchRect visibleFrame:visible];
}

#pragma mark - Handle calls to current first responder

// Shell>Close
- (void)closeCurrentSession:(id)sender {
    [self close];
}

// Shell>Close Terminal Window
- (void)closeWindow:(id)sender {
    [self close];
}

- (void)close {
    [self postWillCloseNotification];
    [super close];
}

#pragma mark - IBActions

- (IBAction)showGlobalTabView:(id)sender {
    [self hideScrimAndSERP];
    [_tabView selectTabViewItem:_globalTabViewItem];
}

- (IBAction)showAppearanceTabView:(id)sender {
    [self hideScrimAndSERP];
    [_tabView selectTabViewItem:_appearanceTabViewItem];
}

- (IBAction)showProfilesTabView:(id)sender {
    [self hideScrimAndSERP];
    [_tabView selectTabViewItem:_profilesTabViewItem];
}

- (IBAction)showKeyboardTabView:(id)sender {
    [self hideScrimAndSERP];
    [_tabView selectTabViewItem:_keyboardTabViewItem];
}

- (IBAction)showArrangementsTabView:(id)sender {
    [self hideScrimAndSERP];
    [_tabView selectTabViewItem:_arrangementsTabViewItem];
}

- (IBAction)showMouseTabView:(id)sender {
    [self hideScrimAndSERP];
    [_tabView selectTabViewItem:_mouseTabViewItem];
}

- (IBAction)showAdvancedTabView:(id)sender {
    [self hideScrimAndSERP];
    [_tabView selectTabViewItem:_advancedTabViewItem];
}

- (IBAction)showShortcutsTabView:(id)sender {
    [self hideScrimAndSERP];
    [_tabView selectTabViewItem:_shortcutsTabViewItem];
}

#pragma mark - Settings Search

- (NSSearchField *)searchField {
    if (!_settingsSearchField) {
        _settingsSearchField = [[NSSearchField alloc] initWithFrame:NSMakeRect(0, 0, 180, 26)];
        _settingsSearchField.delegate = self;
        _settingsSearchField.accessibilityLabel = NSLocalizedString(@"Search Settings", @"Settings search");
        _settingsSearchField.accessibilityIdentifier = @"SettingsSearch";
        NSMenu *menu = [[NSMenu alloc] initWithTitle:NSLocalizedString(@"Search Options", @"Settings search menu")];
        NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Show indicators for non-default values", @"Settings search menu")
                                                          action:@selector(toggleIndicateNonDefaultValues:)
                                                   keyEquivalent:@""];
        menuItem.target = self;
        [menu addItem:menuItem];
        _settingsSearchField.searchMenuTemplate = menu;
    }
    return _settingsSearchField;
}

- (void)toggleIndicateNonDefaultValues:(id)sender {
    [iTermPreferences setBool:![iTermPreferences boolForKey:kPreferenceKeyIndicateNonDefaultValues]
                       forKey:kPreferenceKeyIndicateNonDefaultValues];
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermPreferencesDidToggleIndicateNonDefaultValues
                                                        object:nil];
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    if (menuItem.action == @selector(toggleIndicateNonDefaultValues:)) {
        menuItem.state = [iTermPreferences boolForKey:kPreferenceKeyIndicateNonDefaultValues] ? NSControlStateValueOn : NSControlStateValueOff;
    }
    return YES;
}

#pragma mark - Hotkey Window

// This is used by iTermHotKeyController to not activate the hotkey while the field for typing
// the hotkey into is the first responder.
- (iTermShortcutInputView *)hotkeyField {
    return _keysViewController.hotkeyField;
}

#pragma mark - Accessors

- (NSString *)currentProfileGuid {
    return [_profilesViewController selectedProfile][KEY_GUID];
}

#pragma mark - ProfilePreferencesViewControllerDelegate

- (ProfileModel *)profilePreferencesModel {
    return _profileModel;
}

#pragma mark - NSTabViewDelegate

- (iTermSettingsPage *)settingsPageForTabViewItem:(NSTabViewItem *)tabViewItem {
    for (iTermSettingsPage *page in _settingsPages) {
        if (page.tabViewItem == tabViewItem) {
            return page;
        }
    }
    return nil;
}

- (void)synchronizeNavigationForTabViewItem:(NSTabViewItem *)tabViewItem {
    iTermSettingsPage *page = [self settingsPageForTabViewItem:tabViewItem];
    if (!page) {
        return;
    }
    [_settingsSidebar selectPage:page];
    [_settingsHeader showPage:page];
}

- (NSTabViewItem *)tabViewItemForViewController:(id)viewController {
    for (iTermSettingsPage *page in _settingsPages) {
        if (page.controller == viewController) {
            return page.tabViewItem;
        }
    }
    if ([_profilesViewController hasViewController:viewController]) {
        return _profilesTabViewItem;
    }
    return nil;
}

- (iTermPreferencesBaseViewController *)viewControllerForTabViewItem:(NSTabViewItem *)tabViewItem {
    NSViewController *controller = [self settingsPageForTabViewItem:tabViewItem].controller;
    return [iTermPreferencesBaseViewController castFrom:controller];
}

- (void)tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)tabViewItem {
    [self synchronizeNavigationForTabViewItem:tabViewItem];
    [_settingsContent scrollToTop];
    if (tabViewItem == _profilesTabViewItem) {
        if (_disableResize == 0) {
            [_profilesViewController resizeWindowForCurrentTabAnimated:YES];
        }
        return;
    }

    [self resizeWindowForTabViewItem:tabViewItem animated:YES];
    [_profilesViewController invalidateSavedSize];
}

- (void)tabView:(NSTabView *)tabView willSelectTabViewItem:(NSTabViewItem *)tabViewItem {
    [[self viewControllerForTabViewItem:[tabView selectedTabViewItem]] willDeselectTab];
}

- (void)resizeWindowForTabViewItem:(NSTabViewItem *)tabViewItem animated:(BOOL)animated {
    iTermPreferencesBaseViewController *viewController = [self viewControllerForTabViewItem:tabViewItem];
    if (viewController.tabView != nil) {
        [viewController resizeWindowForCurrentTabAnimated:animated];
        return;
    }

    iTermSizeRememberingView *theView = (iTermSizeRememberingView *)tabViewItem.view;
    NSSize size = theView.originalSize;
    size.width += 26;
    size.height += 9;
    [self preferencePanelSetContentSize:size];
}

#pragma mark - NSSearchFieldDelegate

- (void)controlTextDidChange:(NSNotification *)obj {
    NSSearchField *searchField = self.searchField;
    if ([searchField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length == 0) {
        [self hideScrimAndSERP];
        return;
    }
    [self showScrimAndSERP];
    _scrim.cutoutView = nil;
}

- (NSArray<id<iTermSearchableViewController>> *)searchableViewControllers {
    NSMutableArray<id<iTermSearchableViewController>> *controllers = [NSMutableArray array];
    for (iTermSettingsPage *page in _settingsPages) {
        if ([page.controller conformsToProtocol:@protocol(iTermSearchableViewController)]) {
            [controllers addObject:(id<iTermSearchableViewController>)page.controller];
        }
    }
    return controllers;
}

- (void)buildSearchEngineIfNeeded {
    if (gSearchEngine) {
        return;
    }
    gSearchEngine = [[iTermPreferencesSearchEngine alloc] init];

    for (iTermSettingsPage *page in _settingsPages) {
        if (![page.controller conformsToProtocol:@protocol(iTermSearchableViewController)]) {
            continue;
        }
        id<iTermSearchableViewController> controller = (id<iTermSearchableViewController>)page.controller;
        for (iTermPreferencesSearchDocument *source in [controller searchableViewControllerDocuments]) {
            iTermPreferencesSearchDocument *doc = [source copy];
            doc.pathComponents = [@[page.title] arrayByAddingObjectsFromArray:doc.pathComponents];
            doc.scope = page.scope;
            [gSearchEngine addDocumentToIndex:doc];
        }
    }
}

- (NSArray<iTermPreferencesSearchDocument *> *)searchResults {
    [self buildSearchEngineIfNeeded];
    return [gSearchEngine documentsMatchingQuery:self.searchField.stringValue];
}

- (void)controlTextDidEndEditing:(NSNotification *)obj {
    [self hideScrimAndSERP];
}

- (void)controlTextDidBeginEditing:(NSNotification *)obj {
    [self controlTextDidChange:obj];
}

- (void)hideScrimAndSERP {
    [_serpWindowController close];
    _serpWindowController = nil;
    [_scrim removeFromSuperview];
    _scrim = nil;
}

- (void)showScrimAndSERP {
    if ([self.searchField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length == 0) {
        [self hideScrimAndSERP];
        return;
    }
    [self showScrimIfNeeded];
    if (!_serpWindowController) {
        _serpWindowController = [[iTermPreferencesSearchEngineResultsWindowController alloc] initWithWindowNibName:@"iTermPreferencesSearchEngineResultsWindowController"];
        _serpWindowController.delegate = self;
    }
    _serpWindowController.documents = [self searchResults];
    [self updateSERPOrigin];
    if (!_serpWindowController.window.parentWindow) {
        [self.window addChildWindow:_serpWindowController.window ordered:NSWindowAbove];
    }
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector {
    if (commandSelector == @selector(moveDown:)) {
        [_serpWindowController moveDown:nil];
        return YES;
    } else if (commandSelector == @selector(moveUp:)) {
        [_serpWindowController moveUp:nil];
        return YES;
    } else if (commandSelector == @selector(cancelOperation:)) {
        [self hideScrimAndSERP];
        [self.window makeFirstResponder:nil];
        return YES;
    } else if (commandSelector == @selector(insertNewline:)) {
        [_serpWindowController insertNewline:nil];
        return YES;
    }
    return NO;
}

#pragma mark - iTermPrefsPanelDelegate

- (void)prefsPanelDidChangeFrameTo:(NSRect)newFrame {
    [self updateSERPOrigin];
    [_scrim setNeedsDisplay:YES];
}

#pragma mark - iTermPreferencesSearchEngineResultsWindowControllerDelegate

- (void)selectTabViewItem:(NSTabViewItem *)tabViewItem {
    [_tabView selectTabViewItem:tabViewItem];
    [self synchronizeNavigationForTabViewItem:tabViewItem];
}

- (void)selectTabForViewController:(id<iTermSearchableViewController>)viewController {
    NSTabViewItem *tabViewItem = [self tabViewItemForViewController:viewController];
    if (tabViewItem) {
        [self selectTabViewItem:tabViewItem];
        return;
    }
    if ([viewController isKindOfClass:[iTermProfilePreferencesBaseViewController class]]) {
        [self selectTabViewItem:_profilesTabViewItem];
        if (_profilesViewController.selectedProfile == nil) {
            [_profilesViewController openToProfileWithGuid:[[ProfileModel sharedInstance] defaultProfile][KEY_GUID]
                                          selectGeneralTab:NO
                                                     scope:nil];
        }
    }
}

- (id<iTermSearchableViewController>)viewControllerForDocumentOwnerIdentifier:(NSString *)ownerIdentifier {
    for (id<iTermSearchableViewController> vc in [self searchableViewControllers]) {
        if ([vc.documentOwnerIdentifier isEqualToString:ownerIdentifier]) {
            return vc;
        }
    }
    return [_profilesViewController viewControllerWithOwnerIdentifier:ownerIdentifier];
}

- (BOOL)revealDocument:(iTermPreferencesSearchDocument *)document
         switchingTabs:(out BOOL *)switchingTabsOut
    switchingInnerTabs:(out BOOL *)switchingInnerTabsOut {
    _scrim.cutoutView = nil;
    id<iTermSearchableViewController> viewController = [self viewControllerForDocumentOwnerIdentifier:document.ownerIdentifier];
    if (!viewController) {
        return NO;
    }
    NSTabViewItem *tabViewItemBefore = _tabView.selectedTabViewItem;
    [self selectTabForViewController:viewController];
    const BOOL waitForTabToSwitch = (tabViewItemBefore != _tabView.selectedTabViewItem);
    BOOL waitForInnerTabToSwitch = NO;
     [self showScrimIfNeeded];
    // Revealing can cause a first responder change which removes the scrim, so note that we shouldn't do that.
    _revealingControl = YES;
    _scrim.cutoutView = [viewController searchableViewControllerRevealItemForDocument:document
                                                                             forQuery:self.searchField.stringValue
                                                                        willChangeTab:&waitForInnerTabToSwitch];
    [self.window.contentView layoutSubtreeIfNeeded];
    NSView *target = _scrim.cutoutView;
    for (NSView *ancestor = target.superview; ancestor; ancestor = ancestor.superview) {
        if ([ancestor isKindOfClass:[NSScrollView class]]) {
            NSScrollView *scrollView = (NSScrollView *)ancestor;
            NSView *document = scrollView.documentView;
            [document scrollRectToVisible:[target convertRect:target.bounds toView:document]];
        }
    }
    _revealingControl = NO;
    if (switchingTabsOut) {
        *switchingTabsOut = waitForTabToSwitch;
    }
    if (switchingInnerTabsOut) {
        *switchingInnerTabsOut = waitForInnerTabToSwitch;
    }
    return YES;
}

- (NSTimeInterval)delayToWaitForTabToSwitch:(BOOL)waitForTabToSwitch
                    waitForInnerTabToSwitch:(BOOL)waitForInnerTabToSwitch {
    if (waitForTabToSwitch || (!waitForTabToSwitch && waitForInnerTabToSwitch)) {
        return 2;
    }
    return 1;
}

- (void)preferencesSearchEngineResultsDidSelectDocument:(iTermPreferencesSearchDocument *)document {
    BOOL waitForTabToSwitch = NO;
    BOOL waitForInnerTabToSwitch = NO;
    if (![self revealDocument:document
                switchingTabs:&waitForTabToSwitch
           switchingInnerTabs:&waitForInnerTabToSwitch]) {
        return;
    }
    _delay = [self delayToWaitForTabToSwitch:waitForTabToSwitch
                     waitForInnerTabToSwitch:waitForInnerTabToSwitch];
}

- (NSTabViewItem *)innerTabViewItem {
    return [self viewControllerForTabViewItem:_tabView.selectedTabViewItem].tabView.selectedTabViewItem;
}

- (void)fadeOutScrimAfterDelay:(NSTimeInterval)delay {
    NSView *scrim = _scrim;
    self->_scrim = nil;
    [self.window makeFirstResponder:nil];
    [NSView animateWithDuration:0.5
                          delay:delay
                     animations:^{
                         scrim.animator.alphaValue = 0;
                     }
                     completion:^(BOOL finished) {
                         [scrim removeFromSuperview];
                     }];
}

- (void)preferencesSearchEngineResultsDidActivateDocument:(iTermPreferencesSearchDocument *)document {
    [self fadeOutScrimAfterDelay:_delay];
}

#pragma mark - Scrim

- (void)showScrimIfNeeded {
    if (_scrim) {
        return;
    }
    _scrim = [[iTermPrefsScrim alloc] init];
    _scrim.frame = self.window.contentView.bounds;
    _scrim.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self.window.contentView addSubview:_scrim];
}

- (void)scrimMouseUp:(NSNotification *)notification {
    [self.window makeFirstResponder:nil];
}

#pragma mark - iTermPreferencePanelSizing

- (NSView *)preferencePanelContentView {
    return _tabView;
}

- (void)preferencePanelSetContentSize:(NSSize)size {
    if (!_editCurrentSessionMode) {
        // Legacy panes remember their old wide NIB size, but resize cleanly
        // at the page minimum. Keep horizontal scrolling for smaller windows.
        size.width = MIN(size.width, iTermSettingsContentView.minimumPageWidth);
    }
    [_settingsContent setMinimumContentSize:size];
}

- (CGFloat)preferencePanelMinimumWidth {
    return iTermPreferencePanelGetWindowMinimumWidth(_editCurrentSessionMode) + self.preferencePanelNavigationWidth;
}

- (CGFloat)preferencePanelNavigationWidth {
    return _editCurrentSessionMode ? 0 : iTermSettingsSidebarView.preferredWidth;
}

@end

@interface iTermPreferencesPanelRootView: NSView
@end

@implementation iTermPreferencesPanelRootView

// Some day when support for macOS 15 is dropped, remove this and nudge everything around.
- (BOOL)prefersCompactControlSizeMetrics {
    return YES;
}
@end
