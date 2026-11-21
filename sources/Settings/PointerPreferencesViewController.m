//
//  PointerPreferencesViewController.m
//  iTerm
//
//  Created by George Nachman on 4/7/14.
//
//

#import "PointerPreferencesViewController.h"
#import "PointerPrefsController.h"
#import "PreferencePanel.h"
#import "iTermSizeRememberingView.h"
#import "iTerm2SharedARC-Swift.h"

NSString *const kPointerPrefsChangedNotification = @"kPointerPrefsChangedNotification";
NSString *const kPointerPrefsSemanticHistoryEnabledChangedNotification = @"kPointerPrefsSemanticHistoryEnabledChangedNotification";

@implementation PointerPreferencesViewController {
    IBOutlet NSTabView *_tabView;
    PointerPrefsController *_pointerPrefsController;
    BOOL _configured;

    // Cmd-click to launch url.
    IBOutlet NSButton *_cmdSelection;

    // Control-click doesn't open the context menu, is mouse-reported as right click.
    IBOutlet NSButton *_controlLeftClickActsLikeRightClick;
    IBOutlet NSButton *_rightClickActsLikeRightClick;

    // Opt-click moves cursor.
    IBOutlet NSButton *_optionClickMovesCursor;

    // Three finger click emulates middle button.
    IBOutlet NSButton *_threeFingerEmulatesMiddle;

    // Focus follows mouse.
    IBOutlet NSButton *_focusFollowsMouse;
    IBOutlet NSButton *_focusFollowsMouseIncludingSubviews;

    // Focus on right or middle click
    IBOutlet NSButton *_focusOnRightOrMiddleClick;

    IBOutlet NSButton *_reportHorizontalScrollEvents;
}

- (void)loadView {
    iTermSizeRememberingView *root = [[iTermSizeRememberingView alloc] initWithFrame:NSMakeRect(0, 0, 892, 421)];
    iTermSettingsTabView *tabs = [iTermSettingsControlFactory sectionTabViewWithFrame:NSMakeRect(0, 10, 879, 417)
                                                                                items:@[
        @[ @"2", @"Behavior" ],
        @[ @"1", @"Pointer Bindings" ]
    ]];

    SEL changed = @selector(settingChanged:);
    _cmdSelection = [iTermSettingsControlFactory checkbox:@"⌘-Click opens filename/URL (semantic history)" target:self action:changed toolTip:nil];
    _optionClickMovesCursor = [iTermSettingsControlFactory checkbox:@"⌥-Click moves cursor" target:self action:changed toolTip:nil];
    _threeFingerEmulatesMiddle = [iTermSettingsControlFactory checkbox:@"Three-finger tap emulates middle click" target:self action:changed toolTip:nil];
    _focusFollowsMouse = [iTermSettingsControlFactory checkbox:@"Focus follows mouse" target:self action:changed toolTip:nil];
    _focusFollowsMouseIncludingSubviews = [iTermSettingsControlFactory checkbox:@"Include embedded fields such as Find" target:self action:changed toolTip:nil];
    _focusOnRightOrMiddleClick = [iTermSettingsControlFactory checkbox:@"Focus window after right or middle click" target:self action:changed toolTip:nil];
    _reportHorizontalScrollEvents = [iTermSettingsControlFactory checkbox:@"Mouse reporting supports horizontal scrolling" target:self action:changed toolTip:nil];
    _controlLeftClickActsLikeRightClick = [iTermSettingsControlFactory checkbox:@"^-Click reported to apps, does not open menu" target:self action:changed toolTip:nil];
    _rightClickActsLikeRightClick = [iTermSettingsControlFactory checkbox:@"Right click reported to apps, does not open menu" target:self action:changed toolTip:nil];

    _pointerPrefsController = [[PointerPrefsController alloc] init];
    NSView *bindingsView = [_pointerPrefsController createBindingsView];
    [tabs.tabViewItems[1].view addSubview:bindingsView];

    [root addSubview:tabs];
    _tabView = tabs;
    self.view = root;
    [self configurePointerSettings];
}

- (void)awakeFromNib {
    [self configurePointerSettings];
}

- (void)configurePointerSettings {
    if (_configured) {
        return;
    }
    _configured = YES;
    PreferenceInfo *info;

    __weak __typeof(self) weakSelf = self;
    info = [self defineControl:_cmdSelection
                           key:kPreferenceKeyCmdClickOpensURLs
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() {
        [[NSNotificationCenter defaultCenter] postNotificationName:kPointerPrefsSemanticHistoryEnabledChangedNotification
                                                            object:nil];
    };

    [self defineControl:_controlLeftClickActsLikeRightClick
                    key:kPreferenceKeyControlLeftClickBypassesContextMenu
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_rightClickActsLikeRightClick
                    key:kPreferenceKeyRightClickClickBypassesContextMenu
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_optionClickMovesCursor
                    key:kPreferenceKeyOptionClickMovesCursor
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    info = [self defineControl:_threeFingerEmulatesMiddle
                           key:kPreferenceKeyThreeFingerEmulatesMiddle
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() {
        [weakSelf postRefreshNotification];
        [[NSNotificationCenter defaultCenter] postNotificationName:kPointerPrefsChangedNotification
                                                            object:nil
                                                          userInfo:nil];
    };

    _focusFollowsMouseIncludingSubviews.title = NSLocalizedString(@"Include embedded fields such as Find",
                                                                  @"Focus follows mouse sub-option");
    [self defineControl:_focusFollowsMouse
                    key:kPreferenceKeyFocusFollowsMouse
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];
    info = [self defineControl:_focusFollowsMouseIncludingSubviews
                           key:kPreferenceKeyFocusFollowsMouseIncludingSubviews
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.shouldBeEnabled = ^BOOL {
        return [weakSelf boolForKey:kPreferenceKeyFocusFollowsMouse];
    };
    [info addShouldBeEnabledDependencyOnSetting:kPreferenceKeyFocusFollowsMouse
                                     controller:self];
    [self defineControl:_focusOnRightOrMiddleClick
                    key:kPreferenceKeyFocusOnRightOrMiddleClick
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];
    [self defineControl:_reportHorizontalScrollEvents
                    key:kPreferenceKeyReportHorizontalScrollEvents
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    if (_tabView.numberOfTabViewItems >= 2) {
        _tabView.tabViewItems[0].label = NSLocalizedString(@"Behavior", @"Mouse settings section");
        _tabView.tabViewItems[1].label = NSLocalizedString(@"Pointer Bindings", @"Mouse settings section");
        NSView *bindingsView = _tabView.tabViewItems[1].view.subviews.firstObject;
        if (bindingsView) {
            [self addViewToSearchIndex:bindingsView
                           displayName:@"Pointer bindings"
                               phrases:@[ @"mouse bindings", @"trackpad gestures", @"middle click", @"three finger", @"force touch", @"swipe" ]
                                   key:nil];
            [iTermPointerFormLayout installIn:_tabView controls:@{
                @"cmdSelection": _cmdSelection,
                @"optionClickMovesCursor": _optionClickMovesCursor,
                @"threeFingerEmulatesMiddle": _threeFingerEmulatesMiddle,
                @"focusFollowsMouse": _focusFollowsMouse,
                @"focusFollowsMouseIncludingSubviews": _focusFollowsMouseIncludingSubviews,
                @"focusOnRightOrMiddleClick": _focusOnRightOrMiddleClick,
                @"reportHorizontalScrollEvents": _reportHorizontalScrollEvents,
                @"controlLeftClickActsLikeRightClick": _controlLeftClickActsLikeRightClick,
                @"rightClickActsLikeRightClick": _rightClickActsLikeRightClick,
                @"bindings": bindingsView
            }];
        }
    }
}

- (NSTabView *)tabView {
    return _tabView;
}

- (CGFloat)minimumWidth {
    return 468;
}

@end
