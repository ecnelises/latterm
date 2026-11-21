//
//  AppearancePreferencesViewController.m
//  iTerm
//
//  Created by George Nachman on 4/6/14.
//
//

#import "AppearancePreferencesViewController.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermHotKeyController.h"
#import "iTermApplicationDelegate.h"
#import "iTermSizeRememberingView.h"
#import "iTermWarning.h"
#import "PreferencePanel.h"

NSString *const iTermProcessTypeDidChangeNotification = @"iTermProcessTypeDidChangeNotification";

@interface AppearancePreferencesViewController()<NSTabViewDelegate>
@end

@implementation AppearancePreferencesViewController {
    // This is actually the tab style. See TAB_STYLE_XXX defines.
    IBOutlet NSPopUpButton *_tabStyle;
    IBOutlet NSTextField *_tabStyleLabel;

    // Tab position within window. See TAB_POSITION_XXX defines.
    IBOutlet NSPopUpButton *_tabPosition;
    IBOutlet NSTextField *_tabPositionLabel;

    IBOutlet NSPopUpButton *_statusBarPosition;
    IBOutlet NSTextField *_statusBarPositionLabel;

    IBOutlet NSButton *_perPaneStatusBars;

    // Hide tab bar when there is only one session
    IBOutlet NSButton *_hideTab;

    IBOutlet NSButton *_preserveWindowSizeWhenTabBarVisibilityChanges;
    IBOutlet NSButton *_preserveWindowSizeToKeepOnScreenWhenTabBarVisibilityChanges;

    // Remove tab number from tabs.
    IBOutlet NSButton *_hideTabNumber;

    // Tabs have close buttons?
    IBOutlet NSButton *_tabsHaveCloseButtons;

    // Hide activity indicator.
    IBOutlet NSButton *_hideActivityIndicator;

    // Show new-output indicator
    IBOutlet NSButton *_showNewOutputIndicator;

    // Show per-pane title bar with split panes.
    IBOutlet NSButton *_showPaneTitles;
    IBOutlet NSButton *_showPaneTitlesEvenIfOnlyOnePane;

    // Separate background images per pane
    IBOutlet NSButton *_separateBackgroundImages;
    
    // Hide menu bar in non-lion fullscreen.
    IBOutlet NSButton *_hideMenuBarInFullscreen;

    // Exclude from dock and cmd-tab (LSUIElement)
    IBOutlet NSButton *_uiElement;
    IBOutlet NSButton *_uiElementRequiresHotkeyWindows;

    IBOutlet NSButton *_newTabsOpenAtEndOfTabBar;

    IBOutlet NSButton *_flashTabBarInFullscreenWhenSwitchingTabs;
    IBOutlet NSButton *_showTabBarInFullscreen;

    IBOutlet NSButton *_stretchTabsToFillBar;
    IBOutlet NSButton *_htmlTabTitles;

    // Show window number in title bar.
    IBOutlet NSButton *_windowNumber;

    // Dim text (and non-default background colors).
    IBOutlet NSButton *_dimOnlyText;

    // Dimming amount.
    IBOutlet NSSlider *_dimmingAmount;
    IBOutlet NSTextField *_dimmingAmountLabel;

    // Dim inactive split panes.
    IBOutlet NSButton *_dimInactiveSplitPanes;

    // Dim background windows.
    IBOutlet NSButton *_dimBackgroundWindows;

    // Window border.
    IBOutlet NSButton *_showWindowBorder;

    // Hide scrollbar.
    IBOutlet NSButton *_hideScrollbar;

    // Disable transparency in fullscreen by default.
    IBOutlet NSButton *_disableFullscreenTransparency;

    // Draw line under title bar when the tab bar is not visible
    IBOutlet NSButton *_enableDivisionView;

    IBOutlet NSButton *_enableProxyIcon;

    IBOutlet NSTabView *_tabView;
    NSRect _desiredFrame;

    IBOutlet NSTextField *_sideMarginsLabel;
    IBOutlet NSTextField *_sideMargins;
    IBOutlet NSStepper *_sideMarginsStepper;

    IBOutlet NSTextField *_topBottomMarginsLabel;
    IBOutlet NSTextField *_topBottomMargins;
    IBOutlet NSStepper *_topBottomMarginsStepper;

    IBOutlet NSButton *_hideMenuItemIcons;
    iTermAppIconPreferencesView *_appIconView;
    BOOL _configured;
}

- (void)loadView {
    iTermSizeRememberingView *root = [[iTermSizeRememberingView alloc] initWithFrame:NSMakeRect(0, 0, 623, 384)];
    iTermSettingsTabView *tabs = [iTermSettingsControlFactory sectionTabViewWithFrame:NSMakeRect(0, 10, 610, 380)
                                                                                items:@[
        @[ @"General", @"General" ],
        @[ @"Windows", @"Windows" ],
        @[ @"Tabs", @"Tabs" ],
        @[ @"Panes", @"Panes" ],
        @[ @"Dimming", @"Dimming" ]
    ]];
    tabs.delegate = self;

    SEL changed = @selector(settingChanged:);
    _tabStyleLabel = [iTermSettingsControlFactory label:@"Theme:"];
    _tabStyle = [iTermSettingsControlFactory popupButtonWithPullsDown:NO width:191 target:self action:changed items:@[
        @[ @"Regular", @4 ],
        @[ @"Minimal", @5 ],
        @[ @"Compact", @6 ],
        @[ @"---" ],
        @[ @"Light", @0 ],
        @[ @"Dark", @1 ],
        @[ @"---" ],
        @[ @"Light (High Contrast)", @2 ],
        @[ @"Dark (High Contrast)", @3 ]
    ]];
    _tabPositionLabel = [iTermSettingsControlFactory label:@"Tab bar location:"];
    _tabPosition = [iTermSettingsControlFactory popupButtonWithPullsDown:NO width:191 target:self action:changed items:@[
        @[ @"Top", @0 ],
        @[ @"Bottom", @1 ],
        @[ @"Left", @2 ],
        @[ @"Right", @3 ]
    ]];
    _statusBarPositionLabel = [iTermSettingsControlFactory label:@"Status bar location:"];
    _statusBarPosition = [iTermSettingsControlFactory popupButtonWithPullsDown:NO width:191 target:self action:changed items:@[
        @[ @"Top", @0 ],
        @[ @"Bottom", @1 ]
    ]];
    _hideMenuBarInFullscreen = [iTermSettingsControlFactory checkbox:@"Auto-hide menu bar in non-native fullscreen" target:self action:changed toolTip:nil];
    _uiElement = [iTermSettingsControlFactory checkbox:@"Exclude from Dock and ⌘-Tab Application Switcher" target:self action:changed toolTip:nil];
    _uiElementRequiresHotkeyWindows = [iTermSettingsControlFactory checkbox:@"…but only if all windows are hotkey windows" target:self action:changed toolTip:nil];
    _hideMenuItemIcons = [iTermSettingsControlFactory checkbox:@"Hide menu item icons" target:self action:changed toolTip:nil];

    _windowNumber = [iTermSettingsControlFactory checkbox:@"Show window number in title bar" target:self action:changed toolTip:nil];
    _enableDivisionView = [iTermSettingsControlFactory checkbox:@"Show line under title bar when the tab bar is not visible"
                                                         target:self
                                                         action:changed
                                                        toolTip:@"If this is on then transparency can be toggled window-by-window under View>Use Transparency"];
    _enableProxyIcon = [iTermSettingsControlFactory checkbox:@"Show proxy icon in window title bar"
                                                      target:self
                                                      action:changed
                                                     toolTip:@"Enables an icon in the window title bar that represents the current working directory."];
    _showWindowBorder = [iTermSettingsControlFactory checkbox:@"Heavy border around windows in light mode" target:self action:changed toolTip:nil];
    _hideScrollbar = [iTermSettingsControlFactory checkbox:@"Hide scrollbars" target:self action:changed toolTip:nil];
    _disableFullscreenTransparency = [iTermSettingsControlFactory checkbox:@"Disable transparency for non-native fullscreen windows by default" target:self action:changed toolTip:nil];

    _newTabsOpenAtEndOfTabBar = [iTermSettingsControlFactory checkbox:@"New tabs open at end of tab bar" target:self action:changed toolTip:nil];
    _hideTab = [iTermSettingsControlFactory checkbox:@"Show tab bar even when there is only one tab" target:self action:changed toolTip:nil];
    _flashTabBarInFullscreenWhenSwitchingTabs = [iTermSettingsControlFactory checkbox:@"Flash tab bar when switching tabs in fullscreen" target:self action:changed toolTip:nil];
    _showTabBarInFullscreen = [iTermSettingsControlFactory checkbox:@"Show tab bar in fullscreen" target:self action:changed toolTip:nil];
    _preserveWindowSizeWhenTabBarVisibilityChanges = [iTermSettingsControlFactory checkbox:@"Preserve window size when tab bar shows or hides" target:self action:changed toolTip:nil];
    _preserveWindowSizeToKeepOnScreenWhenTabBarVisibilityChanges = [iTermSettingsControlFactory checkbox:@"…but only if it would cause the window to go off-screen" target:self action:changed toolTip:nil];
    _hideTabNumber = [iTermSettingsControlFactory checkbox:@"Show tab numbers" target:self action:changed toolTip:nil];
    _tabsHaveCloseButtons = [iTermSettingsControlFactory checkbox:@"Tabs have close buttons" target:self action:changed toolTip:nil];
    _hideActivityIndicator = [iTermSettingsControlFactory checkbox:@"Show activity indicator" target:self action:changed toolTip:nil];
    _showNewOutputIndicator = [iTermSettingsControlFactory checkbox:@"Show new-output indicator" target:self action:changed toolTip:nil];
    _stretchTabsToFillBar = [iTermSettingsControlFactory checkbox:@"Stretch tabs to fill bar" target:self action:changed toolTip:nil];
    _htmlTabTitles = [iTermSettingsControlFactory checkbox:@"Support basic HTML tags in tab titles"
                                                    target:self
                                                    action:changed
                                                   toolTip:@"The following tags are recognized: <u>, <i>, and <b>. You can also use &lt; and &amp;."];

    _showPaneTitles = [iTermSettingsControlFactory checkbox:@"Show per-pane title bars" target:self action:changed toolTip:nil];
    _showPaneTitlesEvenIfOnlyOnePane = [iTermSettingsControlFactory checkbox:@"…even if there is only one pane" target:self action:changed toolTip:nil];
    _perPaneStatusBars = [iTermSettingsControlFactory checkbox:@"Separate status bars per pane" target:self action:changed toolTip:nil];
    _separateBackgroundImages = [iTermSettingsControlFactory checkbox:@"Separate background images per pane" target:self action:changed toolTip:nil];
    _sideMarginsLabel = [iTermSettingsControlFactory label:@"Side margins:"];
    _sideMargins = [iTermSettingsControlFactory textFieldWithPlaceholder:nil width:44 target:self action:changed delegate:self];
    _sideMarginsStepper = [iTermSettingsControlFactory stepperWithMinValue:0 maxValue:100 increment:1 target:self action:changed];
    _topBottomMarginsLabel = [iTermSettingsControlFactory label:@"Top & bottom margins:"];
    _topBottomMargins = [iTermSettingsControlFactory textFieldWithPlaceholder:nil width:44 target:self action:changed delegate:self];
    _topBottomMarginsStepper = [iTermSettingsControlFactory stepperWithMinValue:0 maxValue:100 increment:1 target:self action:changed];

    _dimmingAmountLabel = [iTermSettingsControlFactory label:@"Dimming amount:"];
    _dimmingAmount = [iTermSettingsControlFactory sliderWithMinValue:0.01
                                                            maxValue:0.6
                                                         doubleValue:0.6
                                                               width:215
                                                              target:self
                                                              action:changed
                                                             toolTip:@"Inactive sessions get dimmed to help find the active session."
                                              wrappedInSteppedSlider:YES];
    _dimInactiveSplitPanes = [iTermSettingsControlFactory checkbox:@"Dim inactive split panes" target:self action:changed toolTip:nil];
    _dimBackgroundWindows = [iTermSettingsControlFactory checkbox:@"Dim background windows" target:self action:changed toolTip:nil];
    _dimOnlyText = [iTermSettingsControlFactory checkbox:@"Dimming affects only text, not background." target:self action:changed toolTip:nil];

    [root addSubview:tabs];
    _tabView = tabs;
    self.view = root;
    [self configureAppearanceSettings];
}

- (void)awakeFromNib {
    [self configureAppearanceSettings];
}

- (void)configureAppearanceSettings {
    if (_configured) {
        return;
    }
    _configured = YES;
    PreferenceInfo *info;

    __weak __typeof(self) weakSelf = self;
    info = [self defineControl:_tabPosition
                           key:kPreferenceKeyTabPosition
                   relatedView:_tabPositionLabel
                          type:kPreferenceInfoTypePopup];
    info.onChange = ^() { [weakSelf postRefreshNotification]; };

    info = [self defineControl:_statusBarPosition
                           key:kPreferenceKeyStatusBarPosition
                   relatedView:_statusBarPositionLabel
                          type:kPreferenceInfoTypePopup];
    info.onChange = ^{ [weakSelf postRefreshNotification]; };

    info = [self defineControl:_perPaneStatusBars
                           key:kPreferenceKeySeparateStatusBarsPerPane
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^{ [weakSelf postRefreshNotification]; };

    info = [self defineControl:_tabStyle
                           key:kPreferenceKeyTabStyle
                   relatedView:_tabStyleLabel
                          type:kPreferenceInfoTypePopup];
    // updateAppearance and kRefreshTerminalNotification are handled by
    // iTermApplicationDelegate's iTermPreferenceDidChangeNotification observer.
    info.hasDefaultValue = ^BOOL{
        return [weakSelf unsignedIntegerForKey:kPreferenceKeyTabStyle] == TAB_STYLE_AUTOMATIC;
    };
    [self updateNonDefaultIndicatorVisibleForInfo:info];

    info = [self defineControl:_sideMargins
                           key:kPreferenceKeySideMargins
                   relatedView:_sideMarginsLabel
                          type:kPreferenceInfoTypeIntegerTextField];
    [self associateStepper:_sideMarginsStepper withPreference:info];
    info.onChange = ^{
        [weakSelf postRefreshNotification];
    };

    info = [self defineControl:_topBottomMargins
                           key:kPreferenceKeyTopBottomMargins
                   relatedView:_topBottomMarginsLabel
                          type:kPreferenceInfoTypeIntegerTextField];
    info.onChange = ^{
        [weakSelf postRefreshNotification];
    };
    [self associateStepper:_topBottomMarginsStepper withPreference:info];

    info = [self defineControl:_hideTab
                           key:kPreferenceKeyHideTabBar
                   relatedView:nil
                          type:kPreferenceInfoTypeInvertedCheckbox];
    info.onChange = ^() {
        [weakSelf postRefreshNotification];
        [weakSelf updateHiddenAndEnabled];
    };

    [self defineControl:_preserveWindowSizeWhenTabBarVisibilityChanges
                    key:kPreferenceKeyPreserveWindowSizeWhenTabBarVisibilityChanges
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];
    
    info = [self defineControl:_preserveWindowSizeToKeepOnScreenWhenTabBarVisibilityChanges
                    key:kPreferenceKeyPreserveWindowSizeToKeepOnScreenWhenTabBarVisibilityChanges
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];
    info.shouldBeEnabled = ^BOOL {
        return [weakSelf boolForKey:kPreferenceKeyPreserveWindowSizeWhenTabBarVisibilityChanges];
    };
    [info addShouldBeEnabledDependencyOnSetting:kPreferenceKeyPreserveWindowSizeWhenTabBarVisibilityChanges
                                     controller:self];

    info = [self defineControl:_hideTabNumber
                           key:kPreferenceKeyHideTabNumber
                   relatedView:nil
                          type:kPreferenceInfoTypeInvertedCheckbox];
    info.onChange = ^() { [weakSelf postRefreshNotification]; };

    info = [self defineControl:_tabsHaveCloseButtons
                           key:kPreferenceKeyTabsHaveCloseButton
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() { [weakSelf postRefreshNotification]; };

    info = [self defineControl:_hideActivityIndicator
                           key:kPreferenceKeyHideTabActivityIndicator
                   relatedView:nil
                          type:kPreferenceInfoTypeInvertedCheckbox];
    info.onChange = ^() { [weakSelf postRefreshNotification]; };

    info = [self defineControl:_showNewOutputIndicator
                           key:kPreferenceKeyShowNewOutputIndicator
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() { [weakSelf postRefreshNotification]; };

    info = [self defineControl:_showPaneTitles
                           key:kPreferenceKeyShowPaneTitles
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() { [weakSelf postRefreshNotification]; };

    info = [self defineControl:_showPaneTitlesEvenIfOnlyOnePane
                           key:kPreferenceKeyShowPaneTitlesEvenIfOnlyOnePane
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() { [weakSelf postRefreshNotification]; };
    info.shouldBeEnabled = ^BOOL {
        return [weakSelf boolForKey:kPreferenceKeyShowPaneTitles];
    };
    [info addShouldBeEnabledDependencyOnSetting:kPreferenceKeyShowPaneTitles controller:self];

    info = [self defineControl:_separateBackgroundImages
                           key:kPreferenceKeyPerPaneBackgroundImage
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() { [weakSelf postRefreshNotification]; };

    info = [self defineControl:_hideMenuBarInFullscreen
                           key:kPreferenceKeyHideMenuBarInFullscreen
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() { [weakSelf postRefreshNotification]; };
    
    info = [self defineControl:_uiElement
                           key:kPreferenceKeyUIElement
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.customSettingChangedHandler = ^(id sender) {
        BOOL isOn = [(NSButton *)sender state] == NSControlStateValueOn;
        BOOL didChange = NO;
        if (isOn) {
            iTermWarningSelection selection =
                [iTermWarning showWarningWithTitle:@"When Latterm is excluded from the dock, you can "
                                                   @"always get back to Preferences using the status "
                                                   @"bar item. Look for a Latterm icon on the right "
                                                   @"side of your menu bar."
                                           actions:@[ @"Exclude From Dock and App Switcher", @"Cancel" ]
                                        identifier:nil
                                       silenceable:kiTermWarningTypePersistent
                                            window:weakSelf.view.window];
            if (selection == kiTermWarningSelection0) {
                [weakSelf setBool:YES forKey:kPreferenceKeyUIElement];
                [weakSelf setBool:NO forKey:kPreferenceKeyHideMenuBarInFullscreen];
                didChange = YES;
            }
        } else {
            didChange = YES;
            [weakSelf setBool:NO forKey:kPreferenceKeyUIElement];
        }
        if (didChange) {
            __strong __typeof(self) strongSelf = weakSelf;
            if (strongSelf) {
                if (isOn) {
                    strongSelf->_hideMenuBarInFullscreen.state = NSControlStateValueOff;
                }
            }
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:iTermProcessTypeDidChangeNotification
                                                            object:nil];
        [weakSelf updateHiddenAndEnabled];
    };

    info = [self defineControl:_uiElementRequiresHotkeyWindows
                           key:kPreferenceKeyUIElementRequiresHotkeys
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.shouldBeEnabled = ^BOOL{
        return [weakSelf boolForKey:kPreferenceKeyUIElement];
    };
    info.observer = ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:iTermProcessTypeDidChangeNotification
                                                            object:nil];
        [weakSelf updateHiddenAndEnabled];
    };

    info = [self defineControl:_flashTabBarInFullscreenWhenSwitchingTabs
                    key:kPreferenceKeyFlashTabBarInFullscreen
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:kRefreshTerminalNotification object:nil];
    };

    [self updateHiddenAndEnabled];

    [self defineControl:_newTabsOpenAtEndOfTabBar
                    key:kPreferenceKeyNewTabsOpenAtEndOfTabBar
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    info = [self defineControl:_showTabBarInFullscreen
                           key:kPreferenceKeyShowFullscreenTabBar
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() {
        [[NSNotificationCenter defaultCenter] postNotificationName:kShowFullscreenTabsSettingDidChange
                                                            object:nil];
    };

    // There's a menu item to change this setting. We want the control to reflect it.
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(showFullscreenTabsSettingDidChange:)
                                                 name:kShowFullscreenTabsSettingDidChange
                                               object:nil];

    info = [self defineControl:_stretchTabsToFillBar
                           key:kPreferenceKeyStretchTabsToFillBar
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() { [weakSelf postRefreshNotification]; };

    info = [self defineControl:_htmlTabTitles
                           key:kPreferenceKeyHTMLTabTitles
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() { [weakSelf postRefreshNotification]; };

    info = [self defineControl:_windowNumber
                           key:kPreferenceKeyShowWindowNumber
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() { [weakSelf postUpdateLabelsNotification]; };

    info = [self defineControl:_dimOnlyText
                           key:kPreferenceKeyDimOnlyText
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() { [weakSelf postRefreshNotification]; };

    info = [self defineControl:_dimmingAmount
                           key:kPreferenceKeyDimmingAmount
                   relatedView:_dimmingAmountLabel
                          type:kPreferenceInfoTypeSlider];
    info.onChange = ^() { [weakSelf postRefreshNotification]; };

    info = [self defineControl:_dimInactiveSplitPanes
                           key:kPreferenceKeyDimInactiveSplitPanes
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() { [weakSelf postRefreshNotification]; };

    info = [self defineControl:_dimBackgroundWindows
                           key:kPreferenceKeyDimBackgroundWindows
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() { [weakSelf postRefreshNotification]; };

    info = [self defineControl:_showWindowBorder
                           key:kPreferenceKeyShowWindowBorder
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() { [weakSelf postRefreshNotification]; };
    info = [self defineControl:_hideScrollbar
                           key:kPreferenceKeyHideScrollbar
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() { [weakSelf postRefreshNotification]; };

    info = [self defineControl:_disableFullscreenTransparency
                           key:kPreferenceKeyDisableFullscreenTransparencyByDefault
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() { [weakSelf postRefreshNotification]; };
    info.shouldBeEnabled = ^BOOL{
        return ![iTermPreferences boolForKey:kPreferenceKeyLionStyleFullscreen];
    };
    [info addShouldBeEnabledDependencyOnSetting:kPreferenceKeyLionStyleFullscreen controller:self];

    info = [self defineControl:_enableDivisionView
                           key:kPreferenceKeyEnableDivisionView
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() { [weakSelf postRefreshNotification]; };

    info = [self defineControl:_enableProxyIcon
                           key:kPreferenceKeyEnableProxyIcon
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() { [weakSelf postRefreshNotification]; };

    info = [self defineControl:_hideMenuItemIcons
                           key:kPreferenceKeyMenuActionImages
                   relatedView:nil
                          type:kPreferenceInfoTypeInvertedCheckbox];
    if (@available(macOS 26, *)) {} else {
        _hideMenuItemIcons.enabled = NO;
    }

    [self installAppIconSection];
    [iTermAppearanceFormLayout installIn:_tabView controls:@{
        @"tabStyle": _tabStyle,
        @"tabStyleLabel": _tabStyleLabel,
        @"tabPosition": _tabPosition,
        @"tabPositionLabel": _tabPositionLabel,
        @"statusBarPosition": _statusBarPosition,
        @"statusBarPositionLabel": _statusBarPositionLabel,
        @"hideMenuBarInFullscreen": _hideMenuBarInFullscreen,
        @"uiElement": _uiElement,
        @"uiElementRequiresHotkeyWindows": _uiElementRequiresHotkeyWindows,
        @"hideMenuItemIcons": _hideMenuItemIcons,
        @"windowNumber": _windowNumber,
        @"enableDivisionView": _enableDivisionView,
        @"enableProxyIcon": _enableProxyIcon,
        @"showWindowBorder": _showWindowBorder,
        @"hideScrollbar": _hideScrollbar,
        @"disableFullscreenTransparency": _disableFullscreenTransparency,
        @"newTabsOpenAtEndOfTabBar": _newTabsOpenAtEndOfTabBar,
        @"hideTab": _hideTab,
        @"flashTabBarInFullscreenWhenSwitchingTabs": _flashTabBarInFullscreenWhenSwitchingTabs,
        @"showTabBarInFullscreen": _showTabBarInFullscreen,
        @"preserveWindowSizeWhenTabBarVisibilityChanges": _preserveWindowSizeWhenTabBarVisibilityChanges,
        @"preserveWindowSizeToKeepOnScreenWhenTabBarVisibilityChanges": _preserveWindowSizeToKeepOnScreenWhenTabBarVisibilityChanges,
        @"hideTabNumber": _hideTabNumber,
        @"tabsHaveCloseButtons": _tabsHaveCloseButtons,
        @"hideActivityIndicator": _hideActivityIndicator,
        @"showNewOutputIndicator": _showNewOutputIndicator,
        @"stretchTabsToFillBar": _stretchTabsToFillBar,
        @"htmlTabTitles": _htmlTabTitles,
        @"showPaneTitles": _showPaneTitles,
        @"showPaneTitlesEvenIfOnlyOnePane": _showPaneTitlesEvenIfOnlyOnePane,
        @"perPaneStatusBars": _perPaneStatusBars,
        @"separateBackgroundImages": _separateBackgroundImages,
        @"sideMarginsLabel": _sideMarginsLabel,
        @"sideMargins": _sideMargins,
        @"sideMarginsStepper": _sideMarginsStepper,
        @"topBottomMarginsLabel": _topBottomMarginsLabel,
        @"topBottomMargins": _topBottomMargins,
        @"topBottomMarginsStepper": _topBottomMarginsStepper,
        @"dimmingAmountLabel": _dimmingAmountLabel,
        @"dimmingAmount": _dimmingAmount,
        @"dimInactiveSplitPanes": _dimInactiveSplitPanes,
        @"dimBackgroundWindows": _dimBackgroundWindows,
        @"dimOnlyText": _dimOnlyText
    }];
}

- (void)installAppIconSection {
    _appIconView = [[iTermAppIconPreferencesView alloc] initWithFrame:NSMakeRect(0, 0, 512, 208)];
    _appIconView.lightPopupButton.target = self;
    _appIconView.lightPopupButton.action = @selector(settingChanged:);
    _appIconView.darkPopupButton.target = self;
    _appIconView.darkPopupButton.action = @selector(settingChanged:);

    __weak iTermAppIconPreferencesView *weakIconView = _appIconView;
    PreferenceInfo *info = [self defineControl:_appIconView.lightPopupButton
                                           key:kPreferenceKeyLightAppIcon
                                   relatedView:_appIconView.lightLabel
                                          type:kPreferenceInfoTypeStringPopup];
    info.onChange = ^{
        [weakIconView refreshPreviews];
    };

    info = [self defineControl:_appIconView.darkPopupButton
                           key:kPreferenceKeyDarkAppIcon
                   relatedView:_appIconView.darkLabel
                          type:kPreferenceInfoTypeStringPopup];
    info.onChange = ^{
        [weakIconView refreshPreviews];
    };

    NSTabViewItem *appIconItem = [[NSTabViewItem alloc] initWithIdentifier:@"AppIcon"];
    appIconItem.label = NSLocalizedString(@"App Icon",
                                          @"Appearance settings section title for Light and Dark app icons");
    appIconItem.view = _appIconView;
    const NSInteger insertIndex = MIN((NSInteger)_tabView.numberOfTabViewItems, 1);
    [_tabView insertTabViewItem:appIconItem atIndex:insertIndex];
    [_appIconView refreshPreviews];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)postUpdateLabelsNotification {
    [[NSNotificationCenter defaultCenter] postNotificationName:kUpdateLabelsNotification
                                                        object:nil
                                                      userInfo:nil];
}

- (void)showFullscreenTabsSettingDidChange:(NSNotification *)notification {
    _showTabBarInFullscreen.state =
        [iTermPreferences boolForKey:kPreferenceKeyShowFullscreenTabBar] ? NSControlStateValueOn : NSControlStateValueOff;
    [self updateHiddenAndEnabled];
}

- (void)updateHiddenAndEnabled {
    // Enable flashing tabs in fullscreen when it's possible for the tab bar in fullscreen to be
    // hidden: either it's not always visible or it's hidden when there's a single tab. The single-
    // tab case is relevant when going from two tabs to one, which could be considered a "switch".
    _flashTabBarInFullscreenWhenSwitchingTabs.enabled =
        (![iTermPreferences boolForKey:kPreferenceKeyShowFullscreenTabBar] ||
         [iTermPreferences boolForKey:kPreferenceKeyHideTabBar]);

    // Can't preserve size if you can't hide the tab bar.
    _preserveWindowSizeWhenTabBarVisibilityChanges.enabled = (_hideTab.state != NSControlStateValueOn);
    [self updateEnabledState];

    _hideMenuBarInFullscreen.enabled = (![self boolForKey:kPreferenceKeyUIElement] ||
                                        [self boolForKey:kPreferenceKeyUIElementRequiresHotkeys]);
}

- (NSTabView *)tabView {
    return _tabView;
}

- (CGFloat)minimumWidth {
    return 374;
}

@end
