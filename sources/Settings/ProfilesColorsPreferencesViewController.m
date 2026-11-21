//
//  ProfilesColorsPreferencesViewController.m
//  iTerm
//
//  Created by George Nachman on 4/14/14.
//
//

#import "ProfilesColorsPreferencesViewController.h"
#import "DebugLogging.h"
#import "iTerm2SharedARC-Swift.h"
#import "ITAddressBookMgr.h"
#import "iTermColorPresets.h"
#import "iTermDynamicProfileManager.h"
#import "iTermPreferenceDidChangeNotification.h"
#import "iTermProfilePreferences.h"
#import "iTermSizeRememberingView.h"
#import "iTermTextPopoverViewController.h"
#import "iTermWarning.h"
#import "NSAppearance+iTerm.h"
#import "NSAlert+iTerm.h"
#import "NSArray+iTerm.h"
#import "NSColor+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSTextField+iTerm.h"
#import "NSView+iTerm.h"
#import "NSWorkspace+iTerm.h"
#import "PreferencePanel.h"

#import <ColorPicker/ColorPicker.h>

NSString *const iTermColorPreferencesDidDisappear = @"iTermColorPreferencesDidDisappear";
NSString *const iTermColorPreferencesDidAppear = @"iTermColorPreferencesDidAppear";

static NSString * const kColorGalleryURL = @"https://www.iterm2.com/colorgallery";

@interface ProfilesColorsPreferencesViewController()<iTermHueVisualizationViewDelegate, iTermSizeRememberingViewDelegate, NSMenuDelegate>
@end

@implementation ProfilesColorsPreferencesViewController {
    IBOutlet NSPopUpButton *_mode;
    IBOutlet NSButton *_useSeparateColorsForLightAndDarkMode;
    IBOutlet NSTextField *_modeLabel;

    IBOutlet iTermSettingsColorWell *_ansi0Color;
    IBOutlet iTermSettingsColorWell *_ansi1Color;
    IBOutlet iTermSettingsColorWell *_ansi2Color;
    IBOutlet iTermSettingsColorWell *_ansi3Color;
    IBOutlet iTermSettingsColorWell *_ansi4Color;
    IBOutlet iTermSettingsColorWell *_ansi5Color;
    IBOutlet iTermSettingsColorWell *_ansi6Color;
    IBOutlet iTermSettingsColorWell *_ansi7Color;
    IBOutlet iTermSettingsColorWell *_ansi8Color;
    IBOutlet iTermSettingsColorWell *_ansi9Color;
    IBOutlet iTermSettingsColorWell *_ansi10Color;
    IBOutlet iTermSettingsColorWell *_ansi11Color;
    IBOutlet iTermSettingsColorWell *_ansi12Color;
    IBOutlet iTermSettingsColorWell *_ansi13Color;
    IBOutlet iTermSettingsColorWell *_ansi14Color;
    IBOutlet iTermSettingsColorWell *_ansi15Color;
    IBOutlet iTermSettingsColorWell *_foregroundColor;
    IBOutlet iTermSettingsColorWell *_backgroundColor;
    IBOutlet NSButton *_useBrightBold;  // Respect bold
    IBOutlet NSButton *_brightenBoldText;
    IBOutlet iTermSettingsColorWell *_boldColor;
    IBOutlet iTermSettingsColorWell *_linkColor;
    IBOutlet iTermSettingsColorWell *_matchColor;
    IBOutlet iTermSettingsColorWell *_selectionColor;
    IBOutlet iTermSettingsColorWell *_selectedTextColor;
    IBOutlet iTermSettingsColorWell *_cursorColor;
    IBOutlet iTermSettingsColorWell *_cursorTextColor;
    IBOutlet iTermSettingsColorWell *_imeCursorColor;
    IBOutlet iTermSettingsColorWell *_tabColor;
    IBOutlet iTermSettingsColorWell *_underlineColor;
    IBOutlet iTermSettingsColorWell *_badgeColor;

    IBOutlet NSButton *_harmonize256;
    IBOutlet NSTextField *_ansi0ColorLabel;
    IBOutlet NSTextField *_ansi1ColorLabel;
    IBOutlet NSTextField *_ansi2ColorLabel;
    IBOutlet NSTextField *_ansi3ColorLabel;
    IBOutlet NSTextField *_ansi4ColorLabel;
    IBOutlet NSTextField *_ansi5ColorLabel;
    IBOutlet NSTextField *_ansi6ColorLabel;
    IBOutlet NSTextField *_ansi7ColorLabel;
    IBOutlet NSTextField *_foregroundColorLabel;
    IBOutlet NSTextField *_backgroundColorLabel;
    IBOutlet NSTextField *_linkColorLabel;
    IBOutlet NSTextField *_matchColorLabel;
    IBOutlet NSTextField *_selectionColorLabel;
    IBOutlet NSButton *_selectedTextColorEnabledButton;
    IBOutlet NSTextField *_badgeColorLabel;

    IBOutlet NSTextField *_cursorColorLabel;
    IBOutlet NSTextField *_cursorTextColorLabel;
    IBOutlet NSTextField *_imeCursorColorLabel;

    IBOutlet NSButton *_useTabColor;
    IBOutlet NSButton *_useUnderlineColor;
    IBOutlet NSButton *_useSmartCursorColor;
    IBOutlet NSButton *_useActivePaneBorder;
    IBOutlet iTermSettingsColorWell *_activePaneBorderColor;

    IBOutlet NSSlider *_minimumContrast;
    IBOutlet NSTextField *_faintTextAlphaLabel;
    IBOutlet NSSlider *_faintTextAlpha;
    IBOutlet NSSlider *_cursorBoost;
    IBOutlet NSTextField *_minimumContrastLabel;
    IBOutlet NSTextField *_cursorBoostLabel;

    IBOutlet NSMenu *_presetsMenu;

    IBOutlet NSButton *_useGuide;
    IBOutlet iTermSettingsColorWell *_guideColor;

    IBOutlet NSPopUpButton *_presetsPopupButton;
    IBOutlet NSView *_bwWarning1;
    IBOutlet NSView *_bwWarning2;

    IBOutlet NSButton *_modeWarning;
    IBOutlet iTermHueVisualizationView *_hueVisualization;

    NSDictionary<NSString *, id> *_savedColors;
    BOOL _didPreviewPreset;
    NSTimer *_timer;
    BOOL _controlsInitialized;
}

- (NSButton *)useSeparateColorsForLightAndDarkMode { return _useSeparateColorsForLightAndDarkMode; }
- (NSButton *)modeWarning { return _modeWarning; }
- (NSTextField *)modeLabel { return _modeLabel; }
- (NSPopUpButton *)mode { return _mode; }
- (NSPopUpButton *)presetsPopupButton { return _presetsPopupButton; }
- (NSView *)foregroundColor { return _foregroundColor; }
- (NSTextField *)foregroundColorLabel { return _foregroundColorLabel; }
- (NSView *)backgroundColor { return _backgroundColor; }
- (NSTextField *)backgroundColorLabel { return _backgroundColorLabel; }
- (NSView *)boldColor { return _boldColor; }
- (NSView *)linkColor { return _linkColor; }
- (NSTextField *)linkColorLabel { return _linkColorLabel; }
- (NSView *)selectionColor { return _selectionColor; }
- (NSTextField *)selectionColorLabel { return _selectionColorLabel; }
- (NSView *)selectedTextColor { return _selectedTextColor; }
- (NSButton *)selectedTextColorEnabledButton { return _selectedTextColorEnabledButton; }
- (NSView *)matchColor { return _matchColor; }
- (NSTextField *)matchColorLabel { return _matchColorLabel; }
- (NSView *)cursorColor { return _cursorColor; }
- (NSTextField *)cursorColorLabel { return _cursorColorLabel; }
- (NSView *)cursorTextColor { return _cursorTextColor; }
- (NSTextField *)cursorTextColorLabel { return _cursorTextColorLabel; }
- (NSView *)imeCursorColor { return _imeCursorColor; }
- (NSTextField *)imeCursorColorLabel { return _imeCursorColorLabel; }
- (NSView *)ansi0Color { return _ansi0Color; }
- (NSView *)ansi1Color { return _ansi1Color; }
- (NSView *)ansi2Color { return _ansi2Color; }
- (NSView *)ansi3Color { return _ansi3Color; }
- (NSView *)ansi4Color { return _ansi4Color; }
- (NSView *)ansi5Color { return _ansi5Color; }
- (NSView *)ansi6Color { return _ansi6Color; }
- (NSView *)ansi7Color { return _ansi7Color; }
- (NSView *)ansi8Color { return _ansi8Color; }
- (NSView *)ansi9Color { return _ansi9Color; }
- (NSView *)ansi10Color { return _ansi10Color; }
- (NSView *)ansi11Color { return _ansi11Color; }
- (NSView *)ansi12Color { return _ansi12Color; }
- (NSView *)ansi13Color { return _ansi13Color; }
- (NSView *)ansi14Color { return _ansi14Color; }
- (NSView *)ansi15Color { return _ansi15Color; }
- (NSTextField *)ansi0ColorLabel { return _ansi0ColorLabel; }
- (NSTextField *)ansi1ColorLabel { return _ansi1ColorLabel; }
- (NSTextField *)ansi2ColorLabel { return _ansi2ColorLabel; }
- (NSTextField *)ansi3ColorLabel { return _ansi3ColorLabel; }
- (NSTextField *)ansi4ColorLabel { return _ansi4ColorLabel; }
- (NSTextField *)ansi5ColorLabel { return _ansi5ColorLabel; }
- (NSTextField *)ansi6ColorLabel { return _ansi6ColorLabel; }
- (NSTextField *)ansi7ColorLabel { return _ansi7ColorLabel; }
- (NSView *)hueVisualization { return _hueVisualization; }
- (NSSlider *)minimumContrast { return _minimumContrast; }
- (NSTextField *)minimumContrastLabel { return _minimumContrastLabel; }
- (NSView *)bwWarning1 { return _bwWarning1; }
- (NSView *)bwWarning2 { return _bwWarning2; }
- (NSSlider *)faintTextAlpha { return _faintTextAlpha; }
- (NSTextField *)faintTextAlphaLabel { return _faintTextAlphaLabel; }
- (NSSlider *)cursorBoost { return _cursorBoost; }
- (NSTextField *)cursorBoostLabel { return _cursorBoostLabel; }
- (NSButton *)harmonize256 { return _harmonize256; }
- (NSButton *)brightenBoldText { return _brightenBoldText; }
- (NSButton *)useBrightBold { return _useBrightBold; }
- (NSButton *)useTabColor { return _useTabColor; }
- (NSView *)tabColor { return _tabColor; }
- (NSButton *)useUnderlineColor { return _useUnderlineColor; }
- (NSView *)underlineColor { return _underlineColor; }
- (NSButton *)useGuide { return _useGuide; }
- (NSView *)guideColor { return _guideColor; }
- (NSButton *)useSmartCursorColor { return _useSmartCursorColor; }
- (NSView *)badgeColor { return _badgeColor; }
- (NSTextField *)badgeColorLabel { return _badgeColorLabel; }
- (NSButton *)useActivePaneBorder { return _useActivePaneBorder; }
- (NSView *)activePaneBorderColor { return _activePaneBorderColor; }

+ (NSArray<NSString *> *)presetNames {
    NSArray<NSString *> *builtInNames = [[iTermColorPresets builtInColorPresets] allKeys];
    NSArray<NSString *> *customNames = [[iTermColorPresets customColorPresets] allKeys];
    return [builtInNames arrayByAddingObjectsFromArray:customNames];
}

+ (iTermColorPreset *)presetWithName:(NSString *)name {
    iTermColorPreset *dict = [[iTermColorPresets builtInColorPresets] objectForKey:name];
    if (dict) {
        return dict;
    }
    return [[iTermColorPresets customColorPresets] objectForKey:name];
}

+ (NSString *)nameOfPresetUsedByProfile:(Profile *)profile {
    for (NSString *presetName in [self presetNames]) {
        iTermColorPreset *preset = [self presetWithName:presetName];
        BOOL ok = YES;
        const BOOL presetUsesModes = iTermColorPresetHasModes(preset);
        const BOOL profileUsesModes = [iTermProfilePreferences boolForKey:KEY_USE_SEPARATE_COLORS_FOR_LIGHT_AND_DARK_MODE
                                                                inProfile:profile];
        if (presetUsesModes != profileUsesModes) {
            continue;
        }
        for (NSString *colorName in [ProfileModel colorKeysWithModes:presetUsesModes]) {
            iTermColorDictionary *presetColorDict = [preset iterm_presetColorWithName:colorName];
            NSDictionary *profileColorDict = [iTermProfilePreferences objectForKey:colorName
                                                                         inProfile:profile];
            if (![presetColorDict isEqual:profileColorDict] && presetColorDict != profileColorDict) {
                ok = NO;
                break;
            }
        }
        if (ok) {
            return presetName;
        }
    }
    return nil;
}

- (void)loadView {
    iTermSizeRememberingView *root = [[iTermSizeRememberingView alloc] initWithFrame:NSMakeRect(0, 0, 560, 916)];

    self.modesSectionLabel = [iTermSettingsControlFactory rightAlignedLabelWithTitle:@"Modes:"];
    _useSeparateColorsForLightAndDarkMode = [iTermSettingsControlFactory checkboxWithTitle:@"Use separate colors for light and dark mode"
                                                                                    target:self
                                                                                    action:@selector(settingChanged:)];
    _modeWarning = [iTermSettingsControlFactory warningButtonWithTarget:self action:@selector(showModeWarning:)];
    _modeLabel = [iTermSettingsControlFactory rightAlignedLabelWithTitle:@"Editing:"];
    _mode = [iTermSettingsControlFactory popUpButtonWithTitles:@[ @"Light Mode", @"Dark Mode" ]
                                                          tags:@[ @0, @1 ]
                                                        target:self
                                                        action:@selector(modeDidChange:)];
    self.presetsLabel = [iTermSettingsControlFactory rightAlignedLabelWithTitle:@"Color Preset:"];
    _presetsPopupButton = [iTermSettingsControlFactory pullDownButtonWithTitle:@"Color Presets…"
                                                                    itemTitles:@[]
                                                                        target:nil
                                                                        action:nil];
    _presetsMenu = _presetsPopupButton.menu;

    _foregroundColorLabel = [iTermSettingsControlFactory rightAlignedLabelWithTitle:@"Defaults:"];
    _backgroundColorLabel = [iTermSettingsControlFactory labelWithTitle:@"Background"];
    self.defaultsForegroundHeader = [iTermSettingsControlFactory labelWithTitle:@"Foreground"];
    _backgroundColor = [iTermSettingsControlFactory colorWellWithAlphaAllowed:NO];
    _foregroundColor = [iTermSettingsControlFactory colorWellWithAlphaAllowed:NO];

    _cursorColorLabel = [iTermSettingsControlFactory rightAlignedLabelWithTitle:@"Cursor:"];
    self.cursorBackgroundHeader = [iTermSettingsControlFactory labelWithTitle:@"Background"];
    _cursorTextColorLabel = [iTermSettingsControlFactory labelWithTitle:@"Foreground"];
    _cursorColor = [iTermSettingsControlFactory colorWellWithAlphaAllowed:NO];
    _cursorTextColor = [iTermSettingsControlFactory colorWellWithAlphaAllowed:NO];
    _useSmartCursorColor = [iTermSettingsControlFactory checkboxWithTitle:@"Context-aware cursor color (affects box cursor only)"
                                                                   target:self
                                                                   action:@selector(settingChanged:)];

    _imeCursorColorLabel = [iTermSettingsControlFactory rightAlignedLabelWithTitle:@"Input Method Editor:"];
    _imeCursorColor = [iTermSettingsControlFactory colorWellWithAlphaAllowed:YES];

    _selectionColorLabel = [iTermSettingsControlFactory rightAlignedLabelWithTitle:@"Selection:"];
    self.selectionBackgroundHeader = [iTermSettingsControlFactory labelWithTitle:@"Background"];
    self.selectionForegroundHeader = [iTermSettingsControlFactory labelWithTitle:@"Foreground"];
    _selectionColor = [iTermSettingsControlFactory colorWellWithAlphaAllowed:NO];
    _selectedTextColor = [iTermSettingsControlFactory colorWellWithAlphaAllowed:NO];
    _selectedTextColorEnabledButton = [iTermSettingsControlFactory checkboxWithTitle:@"Use custom color for selected text"
                                                                              target:self
                                                                              action:@selector(settingChanged:)];

    _matchColorLabel = [iTermSettingsControlFactory rightAlignedLabelWithTitle:@"Search results:"];
    _matchColor = [iTermSettingsControlFactory colorWellWithAlphaAllowed:NO];

    _linkColorLabel = [iTermSettingsControlFactory rightAlignedLabelWithTitle:@"Links:"];
    _linkColor = [iTermSettingsControlFactory colorWellWithAlphaAllowed:NO];

    self.boldColorLabel = [iTermSettingsControlFactory rightAlignedLabelWithTitle:@"Bold:"];
    _boldColor = [iTermSettingsControlFactory colorWellWithAlphaAllowed:NO];
    _useBrightBold = [iTermSettingsControlFactory checkboxWithTitle:@"Use custom color for bold text"
                                                             target:self
                                                             action:@selector(settingChanged:)];
    _brightenBoldText = [iTermSettingsControlFactory checkboxWithTitle:@"Use bright version of ANSI colors for bold text"
                                                                target:self
                                                                action:@selector(settingChanged:)];

    self.underlineColorLabel = [iTermSettingsControlFactory rightAlignedLabelWithTitle:@"Underlines:"];
    _underlineColor = [iTermSettingsControlFactory colorWellWithAlphaAllowed:NO];
    _useUnderlineColor = [iTermSettingsControlFactory checkboxWithTitle:@"Use custom underline color"
                                                                 target:self
                                                                 action:@selector(settingChanged:)];

    self.cursorGuideLabel = [iTermSettingsControlFactory rightAlignedLabelWithTitle:@"Cursor Guide:"];
    _guideColor = [iTermSettingsControlFactory colorWellWithAlphaAllowed:YES];
    _useGuide = [iTermSettingsControlFactory checkboxWithTitle:@"Use cursor guide"
                                                        target:self
                                                        action:@selector(settingChanged:)];

    _badgeColorLabel = [iTermSettingsControlFactory rightAlignedLabelWithTitle:@"Badge:"];
    _badgeColor = [iTermSettingsControlFactory colorWellWithAlphaAllowed:YES];

    self.ansiColorsSectionLabel = [iTermSettingsControlFactory rightAlignedLabelWithTitle:@"ANSI Colors:"];
    self.ansiNormalHeader = [iTermSettingsControlFactory labelWithTitle:@"Normal"];
    self.ansiNormalHeader.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
    self.ansiBrightHeader = [iTermSettingsControlFactory labelWithTitle:@"Bright"];
    self.ansiBrightHeader.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];

    _ansi0ColorLabel = [iTermSettingsControlFactory rightAlignedLabelWithTitle:@"Black"];
    _ansi1ColorLabel = [iTermSettingsControlFactory rightAlignedLabelWithTitle:@"Red"];
    _ansi2ColorLabel = [iTermSettingsControlFactory rightAlignedLabelWithTitle:@"Green"];
    _ansi3ColorLabel = [iTermSettingsControlFactory rightAlignedLabelWithTitle:@"Yellow"];
    _ansi4ColorLabel = [iTermSettingsControlFactory rightAlignedLabelWithTitle:@"Blue"];
    _ansi5ColorLabel = [iTermSettingsControlFactory rightAlignedLabelWithTitle:@"Magenta"];
    _ansi6ColorLabel = [iTermSettingsControlFactory rightAlignedLabelWithTitle:@"Cyan"];
    _ansi7ColorLabel = [iTermSettingsControlFactory rightAlignedLabelWithTitle:@"White"];

    _ansi0Color = [iTermSettingsControlFactory colorWellWithAlphaAllowed:NO];
    _ansi1Color = [iTermSettingsControlFactory colorWellWithAlphaAllowed:NO];
    _ansi2Color = [iTermSettingsControlFactory colorWellWithAlphaAllowed:NO];
    _ansi3Color = [iTermSettingsControlFactory colorWellWithAlphaAllowed:NO];
    _ansi4Color = [iTermSettingsControlFactory colorWellWithAlphaAllowed:NO];
    _ansi5Color = [iTermSettingsControlFactory colorWellWithAlphaAllowed:NO];
    _ansi6Color = [iTermSettingsControlFactory colorWellWithAlphaAllowed:NO];
    _ansi7Color = [iTermSettingsControlFactory colorWellWithAlphaAllowed:NO];
    _ansi8Color = [iTermSettingsControlFactory colorWellWithAlphaAllowed:NO];
    _ansi9Color = [iTermSettingsControlFactory colorWellWithAlphaAllowed:NO];
    _ansi10Color = [iTermSettingsControlFactory colorWellWithAlphaAllowed:NO];
    _ansi11Color = [iTermSettingsControlFactory colorWellWithAlphaAllowed:NO];
    _ansi12Color = [iTermSettingsControlFactory colorWellWithAlphaAllowed:NO];
    _ansi13Color = [iTermSettingsControlFactory colorWellWithAlphaAllowed:NO];
    _ansi14Color = [iTermSettingsControlFactory colorWellWithAlphaAllowed:NO];
    _ansi15Color = [iTermSettingsControlFactory colorWellWithAlphaAllowed:NO];

    _hueVisualization = [[iTermHueVisualizationView alloc] initWithFrame:NSMakeRect(0, 0, 203, 203)];
    _harmonize256 = [iTermSettingsControlFactory checkboxWithTitle:@"Select 8-bit colors to match ANSI colors"
                                                            target:self
                                                            action:@selector(settingChanged:)];

    _minimumContrastLabel = [iTermSettingsControlFactory rightAlignedLabelWithTitle:@"Minimum Contrast:"];
    _minimumContrast = [iTermSettingsControlFactory sliderWithMinValue:0
                                                              maxValue:1
                                                          initialValue:0
                                                                 width:180
                                                     wrapInSliderView:YES
                                                                target:self
                                                                action:@selector(settingChanged:)];
    NSTextField *bwWarn1 = [iTermSettingsControlFactory labelWithTitle:@"⚠️"];
    bwWarn1.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
    bwWarn1.hidden = YES;
    _bwWarning1 = bwWarn1;
    NSTextField *bwWarn2 = [iTermSettingsControlFactory secondaryLabelWithTitle:@"Black & White Text Only" wrapping:NO];
    bwWarn2.hidden = YES;
    _bwWarning2 = bwWarn2;

    _faintTextAlphaLabel = [iTermSettingsControlFactory rightAlignedLabelWithTitle:@"Faint text:"];
    _faintTextAlpha = [iTermSettingsControlFactory sliderWithMinValue:0.1
                                                             maxValue:1
                                                         initialValue:0.1
                                                                width:180
                                                    wrapInSliderView:YES
                                                               target:self
                                                               action:@selector(settingChanged:)];
    self.faintTransparentLabel = [iTermSettingsControlFactory secondaryLabelWithTitle:@"Transparent" wrapping:NO];
    self.faintOpaqueLabel = [iTermSettingsControlFactory secondaryLabelWithTitle:@"Opaque" wrapping:NO];

    _cursorBoostLabel = [iTermSettingsControlFactory rightAlignedLabelWithTitle:@"Cursor Boost:"];
    _cursorBoost = [iTermSettingsControlFactory sliderWithMinValue:0
                                                          maxValue:0.8
                                                      initialValue:0
                                                             width:180
                                                 wrapInSliderView:YES
                                                            target:self
                                                            action:@selector(settingChanged:)];

    self.tabColorLabel = [iTermSettingsControlFactory rightAlignedLabelWithTitle:@"Tab:"];
    _tabColor = [iTermSettingsControlFactory colorWellWithAlphaAllowed:NO];
    _useTabColor = [iTermSettingsControlFactory checkboxWithTitle:@"Use custom tab color"
                                                           target:self
                                                           action:@selector(settingChanged:)];

    self.paneColorLabel = [iTermSettingsControlFactory rightAlignedLabelWithTitle:@"Pane:"];
    _activePaneBorderColor = [iTermSettingsControlFactory colorWellWithAlphaAllowed:NO];
    _useActivePaneBorder = [iTermSettingsControlFactory checkboxWithTitle:@"Border around active pane"
                                                                   target:self
                                                                   action:@selector(settingChanged:)];

    self.view = root;
    [self awakeFromNib];
}

- (void)awakeFromNib {
    if (_controlsInitialized) {
        return;
    }
    _controlsInitialized = YES;
    ((iTermSizeRememberingView *)self.view).delegate = self;

    // Updates fields when a preset is loaded.
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reloadProfile)
                                                 name:kReloadAllProfiles
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(rebuildColorPresetsMenu)
                                                 name:kRebuildColorPresetsMenuNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(popupButtonWillPopUp:)
                                                 name:NSPopUpButtonWillPopUpNotification
                                               object:_presetsPopupButton];

    __weak __typeof(self) weakSelf = self;
    [iTermPreferenceDidChangeNotification subscribe:self block:^(iTermPreferenceDidChangeNotification * _Nonnull notification) {
        if ([notification.key isEqualToString:kPreferenceKeyTabStyle]) {
            // If the tab style changes the warning button may need to (dis)appear.
            [weakSelf reloadProfile];
        }
    }];
    // Add presets to preset color selection.
    [self rebuildColorPresetsMenu];

    NSDictionary *colorWellDictionary = [self colorWellDictionary];
    NSDictionary *relatedViews = [self colorWellRelatedViews];
    for (NSString *key in colorWellDictionary) {
        iTermSettingsColorWell *colorWell = colorWellDictionary[key];
        colorWell.colorSpace = [NSColorSpace it_defaultColorSpace];
        NSTextField *relatedView = relatedViews[key];
        PreferenceInfo *info = [self defineControl:colorWell
                                               key:key
                                       relatedView:nil
                                       displayName:[NSString stringWithFormat:@"%@ color", relatedView.stringValue]
                                              type:kPreferenceInfoTypeColorWell
                                    settingChanged:nil
                                            update:nil
                                        searchable:relatedView != nil];
        colorWell.action = @selector(settingChanged:);
        colorWell.target = self;
        colorWell.continuous = YES;
        __weak NSView *weakColorWell = colorWell;
        colorWell.willClosePopover = ^() {
            // NSSearchField remembers who was first responder before it gained
            // first responder status. That is the popover at this time. When
            // the app becomes inactive, the search field makes the previous
            // first responder the new first responder. The search field is not
            // smart and doesn't realize the popover has been deallocated. So
            // this changes its conception of who was the previous first
            // responder and prevents the crash.
            [weakColorWell.window makeFirstResponder:nil];
        };
        __weak __typeof(self) weakSelf = self;
        info.observer = ^{
            [weakSelf updateHueChromaVisualizationForKey:key];
        };
    }

    PreferenceInfo *info;

    // The separate colors stuff should be done first because -amendedKey:, which is called when
    // defining controls, expects it to be correct.
    const BOOL dark = [NSApp effectiveAppearance].it_isDark;
    [_mode selectItemWithTag:dark ? 1 : 0];
    info = [self defineControl:_useSeparateColorsForLightAndDarkMode
                           key:KEY_USE_SEPARATE_COLORS_FOR_LIGHT_AND_DARK_MODE
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.customSettingChangedHandler = ^(id sender) {
        const BOOL useModes = [(NSButton *)sender state] == NSControlStateValueOn;
        [[iTermDynamicProfileManager sharedInstance] performAtomically:^{
            [weakSelf useSeparateColorsDidChange:useModes];
            // This has to be done after copying colors or else default colors might be used.
            [weakSelf setBool:useModes forKey:KEY_USE_SEPARATE_COLORS_FOR_LIGHT_AND_DARK_MODE];
        }];
    };


    info = [self defineControl:_useTabColor
                           key:KEY_USE_TAB_COLOR
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.observer = ^() { [weakSelf updateColorControlsEnabled]; };

    info = [self defineControl:_selectedTextColorEnabledButton
                           key:KEY_USE_SELECTED_TEXT_COLOR
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.observer = ^() { [weakSelf updateColorControlsEnabled]; };

    info = [self defineControl:_useUnderlineColor
                           key:KEY_USE_UNDERLINE_COLOR
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.observer = ^() { [weakSelf updateColorControlsEnabled]; };

    info = [self defineControl:_useSmartCursorColor
                           key:KEY_SMART_CURSOR_COLOR
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.observer = ^() { [weakSelf updateColorControlsEnabled]; };

    info = [self defineControl:_useActivePaneBorder
                           key:KEY_USE_ACTIVE_PANE_BORDER
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.observer = ^() { [weakSelf updateColorControlsEnabled]; };

    info = [self defineControl:_minimumContrast
                           key:KEY_MINIMUM_CONTRAST
                   relatedView:_minimumContrastLabel
                          type:kPreferenceInfoTypeSlider];
    info.observer = ^() { [weakSelf maybeWarnAboutExcessiveContrast]; };

    [self defineControl:_faintTextAlpha
                    key:KEY_FAINT_TEXT_ALPHA
            relatedView:_faintTextAlphaLabel
                   type:kPreferenceInfoTypeSlider];

    [self defineControl:_cursorBoost
                    key:KEY_CURSOR_BOOST
            relatedView:_cursorBoostLabel
                   type:kPreferenceInfoTypeSlider];

    [self defineControl:_useGuide
                    key:KEY_USE_CURSOR_GUIDE
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    info = [self defineControl:_useBrightBold
                           key:KEY_USE_BOLD_COLOR
                   displayName:@"Custom color for bold text"
                          type:kPreferenceInfoTypeCheckbox];
    info.observer = ^{ [weakSelf updateColorControlsEnabled]; };

    info = [self defineControl:_brightenBoldText
                           key:KEY_BRIGHTEN_BOLD_TEXT
                   displayName:@"Brighten bold text"
                          type:kPreferenceInfoTypeCheckbox];
    info.observer = ^{ [weakSelf updateColorControlsEnabled]; };

    [self addViewToSearchIndex:_presetsPopupButton
                   displayName:@"Color presets"
                       phrases:@[]
                           key:nil];

    [self defineControl:_harmonize256
                    key:KEY_HARMONIZE_256_COLORS
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self maybeWarnAboutExcessiveContrast];
    [self updateColorControlsEnabled];
    _hueVisualization.delegate = self;
    [self installProfileLayout];
}

- (void)viewWillAppear {
    DLog(@"Colors will appear");
    [super viewWillAppear];
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermColorPreferencesDidAppear
                                                        object:nil];
}

- (void)viewWillDisappear {
    DLog(@"Colors will disappear");
    [super viewWillDisappear];
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermColorPreferencesDidDisappear
                                                        object:nil];
}
- (void)reloadProfile {
    [super reloadProfile];
    [self updateModeEnabled:[self boolForKey:KEY_USE_SEPARATE_COLORS_FOR_LIGHT_AND_DARK_MODE]];
}

- (void)useSeparateColorsDidChange:(BOOL)useModes {
    [self updateModeEnabled:useModes];
    if (useModes) {
        [self copySharedColorsToModalColorsIfNeeded:YES];
    } else {
        [self copyCurrentModeColorsToShared];
    }
}

- (void)updateModeEnabled:(BOOL)useModes {
    const BOOL wasHidden = _modeWarning.hidden;
    if (!useModes) {
        _mode.enabled = NO;
        _modeLabel.labelEnabled = NO;
        _modeWarning.hidden = YES;
        DLog(@"Do not copy");
        if (wasHidden != _modeWarning.hidden) {
            [self.view it_invalidateProfileFormLayout];
        }
        return;
    }
    _mode.enabled = YES;
    _modeLabel.labelEnabled = YES;

    switch ((iTermPreferencesTabStyle)[iTermPreferences intForKey:kPreferenceKeyTabStyle]) {
        case TAB_STYLE_COMPACT:
        case TAB_STYLE_MINIMAL:
        case TAB_STYLE_AUTOMATIC:
            _modeWarning.hidden = YES;
            break;

        case TAB_STYLE_LIGHT:
        case TAB_STYLE_DARK:
        case TAB_STYLE_LIGHT_HIGH_CONTRAST:
        case TAB_STYLE_DARK_HIGH_CONTRAST:
            _modeWarning.hidden = NO;
            break;
    }
    if (wasHidden != _modeWarning.hidden) {
        [self.view it_invalidateProfileFormLayout];
    }
}

- (void)copySharedColorsToModalColorsIfNeeded:(BOOL)useModes {
    [self updateModeEnabled:useModes];
    if (!useModes) {
        DLog(@"Do not copy");
        return;
    }
    // Copy the shared colors to the per-mode colors in user defaults if they do not already exist.
    RLog(@"-- begin copying colors --");
    Profile *profile = [self.delegate profilePreferencesCurrentProfile];
    NSString *guid = profile[KEY_GUID];
    ProfileModel *model = [self.delegate profilePreferencesCurrentModel];
    if (!profile || !guid || !model) {
        return;
    }
    NSMutableDictionary *updated = [profile mutableCopy];
    BOOL changed = NO;
    for (NSString *baseKey in [super keysForBulkCopy]) {
        if ([baseKey isEqualToString:KEY_USE_SEPARATE_COLORS_FOR_LIGHT_AND_DARK_MODE] ||
            [baseKey isEqualToString:KEY_BINDINGS]) {
            DLog(@"Ignore %@", baseKey);
            continue;
        }
        id newValue = [super objectForKey:baseKey];
        if (!newValue) {
            DLog(@"Have no value for %@", baseKey);
            continue;
        }
        for (NSString *suffix in @[ COLORS_LIGHT_MODE_SUFFIX, COLORS_DARK_MODE_SUFFIX ]) {
            NSString *key = [baseKey stringByAppendingString:suffix];
            if (updated[key] != nil) {
                DLog(@"Already have a non-default value key %@", key);
                continue;
            }
            DLog(@"Set %@ = %@ [baseKey=%@]", key, newValue, baseKey);
            updated[key] = newValue;
            changed = YES;
        }
    }
    if (changed) {
        [model setBookmark:updated withGuid:guid];
    }
    RLog(@"-- finished copying colors --");
}

- (void)copyCurrentModeColorsToShared {
    RLog(@"-- begin copying colors to shared --");
    Profile *profile = [self.delegate profilePreferencesCurrentProfile];
    NSString *guid = profile[KEY_GUID];
    ProfileModel *model = [self.delegate profilePreferencesCurrentModel];
    if (!profile || !guid || !model) {
        return;
    }
    NSMutableDictionary *updated = [profile mutableCopy];
    BOOL changed = NO;
    NSString *suffix = _mode.selectedTag == 1 ? COLORS_DARK_MODE_SUFFIX : COLORS_LIGHT_MODE_SUFFIX;
    for (NSString *baseKey in [super keysForBulkCopy]) {
        if ([baseKey isEqualToString:KEY_USE_SEPARATE_COLORS_FOR_LIGHT_AND_DARK_MODE] ||
            [baseKey isEqualToString:KEY_BINDINGS]) {
            continue;
        }
        NSString *key = [baseKey stringByAppendingString:suffix];
        id newValue = [super objectForKey:key];
        if (!newValue) {
            DLog(@"Have no value for %@", key);
            continue;
        }
        DLog(@"Set %@ = %@ [source key=%@]", baseKey, newValue, key);
        updated[baseKey] = newValue;
        changed = YES;
    }
    if (changed) {
        [model setBookmark:updated withGuid:guid];
    }
    RLog(@"-- finished copying colors to shared --");
}

- (void)maybeWarnAboutExcessiveContrast {
    const BOOL hidden = ([self floatForKey:KEY_MINIMUM_CONTRAST] < 0.97);
    if (_bwWarning1.hidden != hidden || _bwWarning2.hidden != hidden) {
        _bwWarning1.hidden = hidden;
        _bwWarning2.hidden = hidden;
        [self.view it_invalidateProfileFormLayout];
    }
}

- (void)updateColorControlsEnabled {
    _tabColor.enabled = [self boolForKey:KEY_USE_TAB_COLOR];
    _selectedTextColor.enabled = [self boolForKey:KEY_USE_SELECTED_TEXT_COLOR];
    _underlineColor.enabled = [self boolForKey:KEY_USE_UNDERLINE_COLOR];
    _activePaneBorderColor.enabled = [self boolForKey:KEY_USE_ACTIVE_PANE_BORDER];

    const BOOL smartCursorColorSelected = [self boolForKey:KEY_SMART_CURSOR_COLOR];
    const BOOL shouldEnableSmartCursorColor = ([self intForKey:KEY_CURSOR_TYPE] == CURSOR_BOX);
    const BOOL shouldEnableCursorColor = !(smartCursorColorSelected && shouldEnableSmartCursorColor);

    _cursorColor.enabled = shouldEnableCursorColor;
    _cursorTextColor.enabled = shouldEnableCursorColor;
    _boldColor.enabled = [self boolForKey:KEY_USE_BOLD_COLOR];
    _cursorColorLabel.labelEnabled = shouldEnableCursorColor;
    _cursorTextColorLabel.labelEnabled = shouldEnableCursorColor;
}

- (NSDictionary<NSString *, iTermSettingsColorWell *> *)colorWellDictionary {
    return @{ KEY_ANSI_0_COLOR: _ansi0Color,
              KEY_ANSI_1_COLOR: _ansi1Color,
              KEY_ANSI_2_COLOR: _ansi2Color,
              KEY_ANSI_3_COLOR: _ansi3Color,
              KEY_ANSI_4_COLOR: _ansi4Color,
              KEY_ANSI_5_COLOR: _ansi5Color,
              KEY_ANSI_6_COLOR: _ansi6Color,
              KEY_ANSI_7_COLOR: _ansi7Color,
              KEY_ANSI_8_COLOR: _ansi8Color,
              KEY_ANSI_9_COLOR: _ansi9Color,
              KEY_ANSI_10_COLOR: _ansi10Color,
              KEY_ANSI_11_COLOR: _ansi11Color,
              KEY_ANSI_12_COLOR: _ansi12Color,
              KEY_ANSI_13_COLOR: _ansi13Color,
              KEY_ANSI_14_COLOR: _ansi14Color,
              KEY_ANSI_15_COLOR: _ansi15Color,
              KEY_FOREGROUND_COLOR: _foregroundColor,
              KEY_BACKGROUND_COLOR: _backgroundColor,
              KEY_BOLD_COLOR: _boldColor,
              KEY_LINK_COLOR: _linkColor,
              KEY_MATCH_COLOR: _matchColor,
              KEY_SELECTION_COLOR: _selectionColor,
              KEY_SELECTED_TEXT_COLOR: _selectedTextColor,
              KEY_CURSOR_COLOR: _cursorColor,
              KEY_CURSOR_TEXT_COLOR: _cursorTextColor,
              KEY_IME_CURSOR_COLOR: _imeCursorColor,
              KEY_TAB_COLOR: _tabColor,
              KEY_UNDERLINE_COLOR: _underlineColor,
              KEY_CURSOR_GUIDE_COLOR: _guideColor,
              KEY_BADGE_COLOR: _badgeColor,
              KEY_ACTIVE_PANE_BORDER_COLOR: _activePaneBorderColor };
}

- (NSDictionary *)colorWellRelatedViews {
    return @{ KEY_ANSI_0_COLOR: _ansi0ColorLabel,
              KEY_ANSI_1_COLOR: _ansi1ColorLabel,
              KEY_ANSI_2_COLOR: _ansi2ColorLabel,
              KEY_ANSI_3_COLOR: _ansi3ColorLabel,
              KEY_ANSI_4_COLOR: _ansi4ColorLabel,
              KEY_ANSI_5_COLOR: _ansi5ColorLabel,
              KEY_ANSI_6_COLOR: _ansi6ColorLabel,
              KEY_ANSI_7_COLOR: _ansi7ColorLabel,
              KEY_FOREGROUND_COLOR: _foregroundColorLabel,
              KEY_BACKGROUND_COLOR: _backgroundColorLabel,
              KEY_SELECTION_COLOR: _selectionColorLabel,
              KEY_SELECTED_TEXT_COLOR: _selectedTextColorEnabledButton,
              KEY_CURSOR_COLOR: _cursorColorLabel,
              KEY_CURSOR_TEXT_COLOR: _cursorTextColorLabel,
              KEY_IME_CURSOR_COLOR: _imeCursorColorLabel,
              KEY_BADGE_COLOR: _badgeColorLabel };
}

- (NSArray<NSString *> *)chromaHueVisualizationKeys {
    return @[// skip black (0)
             KEY_ANSI_1_COLOR,
             KEY_ANSI_2_COLOR,
             KEY_ANSI_3_COLOR,
             KEY_ANSI_4_COLOR,
             KEY_ANSI_5_COLOR,
             KEY_ANSI_6_COLOR,
             // skip white (7)
             // skip light black (8)
             KEY_ANSI_9_COLOR,
             KEY_ANSI_10_COLOR,
             KEY_ANSI_11_COLOR,
             KEY_ANSI_12_COLOR,
             KEY_ANSI_13_COLOR,
             KEY_ANSI_14_COLOR
             // skip light white (15)
    ];
}

- (void)updateHueChromaVisualizationForKey:(NSString *)key {
    if (![self.chromaHueVisualizationKeys containsObject:key]) {
        return;
    }
    NSDictionary *dict = [NSDictionary castFrom:[self objectForKey:key]];
    NSColor *color = [dict colorValue];
    if (color) {
        [_hueVisualization setColor:color forKey:key];
    }
}

#pragma mark - Color Presets

- (void)rebuildColorPresetsMenu {
    while ([_presetsMenu numberOfItems] > 1) {
        [_presetsMenu removeItemAtIndex:1];
    }

    iTermColorPresetDictionary *presetsDict = [iTermColorPresets builtInColorPresets];
    [self addColorPresetsInDict:presetsDict toMenu:_presetsMenu];

    iTermColorPresetDictionary *customPresets = [iTermColorPresets customColorPresets];
    if (customPresets && [customPresets count] > 0) {
        [_presetsMenu addItem:[NSMenuItem separatorItem]];
        [self addColorPresetsInDict:customPresets toMenu:_presetsMenu];
    }

    [_presetsMenu addItem:[NSMenuItem separatorItem]];

    [self addPresetItemWithTitle:NSLocalizedString(@"Import…", @"Color presets") action:@selector(importColorPreset:)];
    [self addPresetItemWithTitle:NSLocalizedString(@"Export…", @"Color presets") action:@selector(exportColorPreset:)];
    [self addPresetItemWithTitle:NSLocalizedString(@"Save As…", @"Color presets") action:@selector(saveColorPreset:)];
    [self addPresetItemWithTitle:NSLocalizedString(@"Delete Preset…", @"Color presets") action:@selector(deleteColorPreset:)];
    [self addPresetItemWithTitle:NSLocalizedString(@"Visit Online Gallery", @"Color presets") action:@selector(visitGallery:)];
    _presetsMenu.delegate = self;
}

- (void)addPresetItemWithTitle:(NSString *)title action:(SEL)action {
    NSMenuItem *item = [_presetsMenu addItemWithTitle:title action:action keyEquivalent:@""];
    item.target = self;
}

- (void)addColorPresetsInDict:(iTermColorPresetDictionary *)presetsDict toMenu:(NSMenu *)theMenu {
    ProfileModel *model = [self.delegate profilePreferencesCurrentModel];
    for (int i = 0; i < 2; i++) {
        NSInteger count = 0;
        for (NSString* key in  [[presetsDict allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
            NSString *title = key;
            if ([model presetHasMultipleModes:key]) {
                if (i == 1) {
                    continue;
                }
                title = [@"☯ " stringByAppendingString:key];
            } else if (i == 0) {
                continue;
            }
            count += 1;
            NSMenuItem* presetItem = [[NSMenuItem alloc] initWithTitle:title
                                                                action:@selector(loadColorPreset:)
                                                         keyEquivalent:@""];
            presetItem.identifier = key;
            presetItem.target = self;
            [theMenu addItem:presetItem];
        }
        if (i == 0 && count > 0) {
            [theMenu addItem:[NSMenuItem separatorItem]];
        }
    }
}

- (void)importColorPreset:(id)sender {
    // Create the File Open Dialog class.
    iTermOpenPanel *openPanel = [[iTermOpenPanel alloc] init];

    // Set options.
    [openPanel setCanChooseFiles:YES];
    [openPanel setCanChooseDirectories:NO];
    [openPanel setAllowsMultipleSelection:YES];
    [openPanel setAllowedContentTypes:@[ [UTType typeWithFilenameExtension:@"itermcolors"] ]];
    openPanel.preferredSSHIdentity = [SSHIdentity localhost];

    // Display the dialog.  If the OK button was pressed,
    // process the files.
    [openPanel beginWithFallbackWindow:self.view.window handler:^(NSModalResponse response, NSArray<NSURL *> *urls) {
        if (response == NSModalResponseOK) {
            // Get an array containing the full filenames of all
            // files and directories selected.
            for (NSURL *url in urls) {
                [iTermColorPresets importColorPresetFromFile:url.path];
            }
        }
    }];
}

- (void)saveColorPreset:(id)sender {
    iTermColorPresetDictionary *customPresets = [iTermColorPresets customColorPresets];
    __weak __typeof(self) weakSelf = self;
    NSArray<NSString *> *names = [customPresets.allKeys sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
    [self showSaveColorPresetAlertWithItems:names completion:^(NSString *name) {
        // A blank name would create a preset that can't be told apart in menus.
        name = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (name.length == 0) {
            return;
        }
        [weakSelf reallySaveColorPresetWithName:name customPresets:customPresets];
    }];
}

- (void)reallySaveColorPresetWithName:(NSString *)name
                        customPresets:(iTermColorPresetDictionary *)customPresets {
    if (customPresets[name]) {
        [iTermColorPresets deletePresetWithName:name];
    }
    [iTermColorPresets addColorPreset:name withColors:[self presetDictionaryForCurrentColors]];
    [self rebuildColorPresetsMenu];
}

- (double)differenceFromPreset:(NSDictionary *)preset {
    return [iTermColorPresets differenceBetweenPreset:[self presetDictionaryForCurrentColors]
                                            andPreset:preset
                                            usingKeys:preset.allKeys];
}
- (NSString *)mostSimilarCustomPresetName {
    NSDictionary *presets = [iTermColorPresets customColorPresets];
    NSString *best = [[presets allKeys] minWithBlock:^NSComparisonResult(NSString *key1, NSString *key2) {
        const double diff1 = [self differenceFromPreset:presets[key1]];
        const double diff2 = [self differenceFromPreset:presets[key2]];
        return [@(diff1) compare:@(diff2)];
    }];
    if (best && [self differenceFromPreset:presets[best]] > 5) {
        return nil;
    }
    return best;
}

- (void)showSaveColorPresetAlertWithItems:(NSArray<NSString *> *)items
                               completion:(void (^)(NSString *name))completion {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = NSLocalizedString(@"Save Color Preset", @"Color presets");
    alert.informativeText = NSLocalizedString(@"Enter a name for the new preset, or choose a custom preset to replace.", @"Color presets");
    alert.alertStyle = NSAlertStyleInformational;

    // Add the ComboBox
    NSComboBox *comboBox = [[NSComboBox alloc] initWithFrame:NSMakeRect(0, 0, 300, 25)];
    [comboBox addItemsWithObjectValues:items];
    comboBox.stringValue = [self mostSimilarCustomPresetName] ?: @"";

    alert.accessoryView = comboBox;
    alert.window.initialFirstResponder = comboBox;

    [alert addButtonWithTitle:NSLocalizedString(@"Save", @"Color presets")];
    [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"Color presets")];

    [alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse response) {
        if (response == NSAlertFirstButtonReturn) {
            NSString *selectedName = [comboBox stringValue];
            completion(selectedName);
        } else {
            completion(nil);
        }
    }];
}

- (void)exportColorPreset:(id)sender {
    // Create the File Open Dialog class.
    iTermModernSavePanel *savePanel = [[iTermModernSavePanel alloc] init];
    savePanel.preferredSSHIdentity = SSHIdentity.localhost;

    // Set options.
    [savePanel setAllowedContentTypes:@[ [UTType typeWithFilenameExtension:@"itermcolors"] ]];

    [savePanel beginWithFallback:^(NSModalResponse response, iTermSavePanelItem *item) {
        if (response == NSModalResponseOK) {
            [self exportColorPresetToItem:item];
        }
    }];
}

- (void)deleteColorPreset:(id)sender {
    iTermColorPresetDictionary *customPresets = [iTermColorPresets customColorPresets];
    if (!customPresets || [customPresets count] == 0) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = NSLocalizedString(@"No Custom Color Presets", @"Color presets");
        alert.informativeText = NSLocalizedString(@"Built-in presets can’t be deleted, and no custom presets have been saved or imported.", @"Color presets");
        [alert addButtonWithTitle:NSLocalizedString(@"OK", @"Color presets")];
        [alert runModal];
        return;
    }

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = NSLocalizedString(@"Delete Color Preset", @"Color presets");
    alert.informativeText = NSLocalizedString(@"Choose a custom preset to delete.", @"Color presets");
    [alert addButtonWithTitle:NSLocalizedString(@"Delete", @"Color presets")];
    [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"Color presets")];
    NSPopUpButton *popUpButton = [[NSPopUpButton alloc] init];
    for (NSString *key in [[customPresets allKeys] sortedArrayUsingSelector:@selector(localizedStandardCompare:)]) {
        [popUpButton addItemWithTitle:key];
        popUpButton.itemArray.lastObject.identifier = key;
    }
    [popUpButton sizeToFit];
    [alert setAccessoryView:popUpButton];
    NSInteger button = [alert runModal];
    if (button == NSAlertFirstButtonReturn) {
        [iTermColorPresets deletePresetWithName:[[popUpButton selectedItem] identifier]];
    }
}

- (NSDictionary *)presetDictionaryForCurrentColors {
    NSMutableDictionary* theDict = [NSMutableDictionary dictionaryWithCapacity:24];
    NSDictionary<NSString *, iTermSettingsColorWell *> *colorWellDictionary = [self colorWellDictionary];
    if ([self boolForKey:KEY_USE_SEPARATE_COLORS_FOR_LIGHT_AND_DARK_MODE]) {
        for (NSString *baseKey in colorWellDictionary) {
            // For compatibility with older versions of iTerm2 - just use the current mode.
            // They'll ignore other keys.
            theDict[baseKey] = [[colorWellDictionary[baseKey] color] dictionaryValue];

            // New versions infer that only modes are to be used if one of the mode keys is present.
            NSString *key = [baseKey stringByAppendingString:COLORS_LIGHT_MODE_SUFFIX];
            theDict[key] = [super objectForKey:key];

            key = [baseKey stringByAppendingString:COLORS_DARK_MODE_SUFFIX];
            theDict[key] = [super objectForKey:key];
        }
    } else {
        for (NSString *key in colorWellDictionary) {
            theDict[key] = [[colorWellDictionary[key] color] dictionaryValue];
        }
    }
    return theDict;
}

- (void)exportColorPresetToItem:(iTermSavePanelItem *)item {
    NSDictionary *theDict = [self presetDictionaryForCurrentColors];
    [theDict writeToSaveItem:item completionHandler:^(NSError *error) {
        if (error) {
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = NSLocalizedString(@"Couldn’t Export Color Preset", @"Color presets");
            alert.informativeText = [NSString stringWithFormat:NSLocalizedString(@"The preset could not be saved to %@.", @"Color presets"), item.displayName];
            [alert addButtonWithTitle:NSLocalizedString(@"OK", @"Color presets")];
            [alert runModal];
        } else {
            [item revealInFinderIfLocal];
        }
    }];
}

- (void)applyColorPresetWithName:(NSString *)presetName updateBothModes:(BOOL)both {
    Profile *profile = [self.delegate profilePreferencesCurrentProfile];
    ProfileModel *model = [self.delegate profilePreferencesCurrentModel];
    if (!profile || !model) {
        return;
    }
    if (both) {
        const iTermColorPresetMode bothModes = (iTermColorPresetModeLight | iTermColorPresetModeDark);
        [model addColorPresetNamed:presetName
                         toProfile:profile
                              from:bothModes
                                to:bothModes
                    updateUseModes:YES];
        return;
    }

    const BOOL modes = [self boolForKey:KEY_USE_SEPARATE_COLORS_FOR_LIGHT_AND_DARK_MODE];
    if (modes) {
        const BOOL currentModeIsDark = _mode.selectedTag == 1;
        const iTermColorPresetMode mode = currentModeIsDark ? iTermColorPresetModeDark : iTermColorPresetModeLight;
        [model addColorPresetNamed:presetName
                         toProfile:profile
                              from:mode
                                to:mode];
    } else {
        const BOOL dark = [NSApp effectiveAppearance].it_isDark;
        [model addColorPresetNamed:presetName
                         toProfile:profile
                              from:dark ? iTermColorPresetModeDark : iTermColorPresetModeLight
                                to:0];
    }
}

- (void)loadColorPresetWithName:(NSString *)presetName prompt:(BOOL)prompt {
    if (!prompt) {
        [self applyColorPresetWithName:presetName updateBothModes:NO];
        return;
    }

    ProfileModel *model = [self.delegate profilePreferencesCurrentModel];
    const BOOL presetHasModes = [model presetHasMultipleModes:presetName];
    const BOOL modes = [self boolForKey:KEY_USE_SEPARATE_COLORS_FOR_LIGHT_AND_DARK_MODE];
    if (!modes) {
        [self applyColorPresetWithName:presetName updateBothModes:presetHasModes];
        return;
    }

    const BOOL currentModeIsDark = _mode.selectedTag == 1;
    NSString *title = presetHasModes
        ? NSLocalizedString(@"This preset has colors for both light mode and dark mode.", @"Color presets")
        : NSLocalizedString(@"This preset does not have separate colors for light mode and dark mode.", @"Color presets");
    NSString *heading = NSLocalizedString(@"Update Which Modes?", @"Color presets");
    NSString *bothAction = NSLocalizedString(@"Update Both Modes", @"Color presets");
    NSString *singleAction = currentModeIsDark
        ? NSLocalizedString(@"Update Dark Mode Only", @"Color presets")
        : NSLocalizedString(@"Update Light Mode Only", @"Color presets");
    NSString *cancelAction = NSLocalizedString(@"Cancel", @"Color presets");
    NSString *identifier = presetHasModes
        ? @"NoSyncUpdateWhichModes_PresetHasModes"
        : @"NoSyncUpdateWhichModes_PresetLacksModes";

    __weak __typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        [iTermWarning asyncShowWarningWithTitle:title
                                        actions:@[ bothAction, singleAction, cancelAction ]
                                  actionMapping:nil
                                      accessory:nil
                                     identifier:identifier
                                    silenceable:kiTermWarningTypePersistent
                                        heading:heading
                                    cancelLabel:cancelAction
                                         window:strongSelf.view.window
                                     completion:^(iTermWarningSelection selection, iTermWarning *warning) {
            if (selection == kiTermWarningSelection0) {
                [weakSelf applyColorPresetWithName:presetName updateBothModes:YES];
            } else if (selection == kiTermWarningSelection1) {
                [weakSelf applyColorPresetWithName:presetName updateBothModes:NO];
            }
        }];
    });
}

- (void)loadColorPreset:(id)sender {
    _savedColors = nil;
    _didPreviewPreset = NO;
    [self loadColorPresetWithName:[sender identifier] prompt:YES];
}

- (void)visitGallery:(id)sender {
    [[NSWorkspace sharedWorkspace] it_openURL:[NSURL URLWithString:kColorGalleryURL]];
}

- (BOOL)currentColorsEqualPreset:(NSDictionary *)preset 
                           modal:(BOOL)modal
                            dark:(BOOL)dark {
    Profile *profile = [self.delegate profilePreferencesCurrentProfile];
    const BOOL presetUsesModes = iTermColorPresetHasModes(preset);
    const BOOL separate = [self boolForKey:KEY_USE_SEPARATE_COLORS_FOR_LIGHT_AND_DARK_MODE];
    if (!modal) {
        // Check both modes
        if (presetUsesModes != separate) {
            return NO;
        }
        for (NSString *colorName in [ProfileModel colorKeysWithModes:presetUsesModes]) {
            iTermColorDictionary *presetColorDict = [preset iterm_presetColorWithName:colorName];
            NSDictionary *profileColorDict = [iTermProfilePreferences objectForKey:colorName
                                                                         inProfile:profile];
            if (![presetColorDict isEqual:profileColorDict] && presetColorDict != profileColorDict) {
                return NO;
            }
        }
    } else {
        // Check only specified mode
        for (NSString *baseName in [ProfileModel colorKeysWithModes:NO]) {
            iTermColorDictionary *presetColorDict = [preset iterm_presetColorWithName:iTermAmendedColorKey2(baseName, presetUsesModes, dark)];
            NSDictionary *profileColorDict = [iTermProfilePreferences objectForKey:iTermAmendedColorKey2(baseName, separate, dark)
                                                                         inProfile:profile];
            if (![presetColorDict isEqual:profileColorDict] && presetColorDict != profileColorDict) {
                return NO;
            }
        }
    }
    return YES;
}

- (NSDictionary<NSString *, id> *)rawCurrentColors {
    Profile *profile = [self.delegate profilePreferencesCurrentProfile];
    if (!profile) {
        return nil;
    }
    NSMutableDictionary<NSString *, id> *dict = [NSMutableDictionary dictionary];
    for (NSString *key in [ProfileModel colorKeysWithModes:NO]) {
        dict[key] = profile[key] ?: [NSNull null];
    }
    for (NSString *key in [ProfileModel colorKeysWithModes:YES]) {
        dict[key] = profile[key] ?: [NSNull null];
    }
    return dict;
}

- (void)restoreColors {
    if (!_didPreviewPreset || !_savedColors) {
        return;
    }
    _didPreviewPreset = NO;
    Profile *profile = [self.delegate profilePreferencesCurrentProfile];
    NSString *guid = profile[KEY_GUID];
    ProfileModel *model = [self.delegate profilePreferencesCurrentModel];
    if (!profile || !guid || !model) {
        return;
    }
    NSMutableDictionary *restored = [profile mutableCopy];
    __block BOOL changed = NO;
    [_savedColors enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        id value = [obj nilIfNull];
        id current = restored[key];
        if (value != current && ![value isEqual:current]) {
            changed = YES;
            if (value) {
                restored[key] = value;
            } else {
                [restored removeObjectForKey:key];
            }
        }
    }];
    if (changed) {
        [model setBookmark:restored withGuid:guid];
        [model flush];
        [[NSNotificationCenter defaultCenter] postNotificationName:kReloadAllProfiles object:nil];
    }
}

// If the current color settings exactly match a preset, place a check mark next to it and uncheck
// all others. If multiple presets match, check the first matching one.
- (void)popupButtonWillPopUp:(id)sender {
    BOOL found = NO;
    iTermColorPresetDictionary *allPresets = [iTermColorPresets allColorPresets];

    _savedColors = [self rawCurrentColors];
    _didPreviewPreset = NO;
    const BOOL separate = [self boolForKey:KEY_USE_SEPARATE_COLORS_FOR_LIGHT_AND_DARK_MODE];

    for (NSMenuItem *item in _presetsMenu.itemArray) {
        if (item.action == @selector(loadColorPreset:)) {
            NSString *name = item.identifier;
            if (!found && [self currentColorsEqualPreset:allPresets[name] modal:NO dark:NO]) {
                item.state = NSControlStateValueOn;
                found = YES;
            } else {
                item.state = NSControlStateValueOff;
            }
        }
    }

    if (!found && separate) {
        // Search for partial matches. These are monomode presets that match exactly one of the
        // light mode or dark mode settings.
        for (NSMenuItem *item in _presetsMenu.itemArray) {
            if (item.action == @selector(loadColorPreset:)) {
                NSString *name = item.identifier;
                if ([self currentColorsEqualPreset:allPresets[name] modal:YES dark:YES] ||
                    [self currentColorsEqualPreset:allPresets[name] modal:YES dark:NO]) {
                    item.state = NSControlStateValueMixed;
                }
            }
        }
    }
}

#pragma mark - NSMenuDelegate

- (void)menu:(NSMenu *)menu willHighlightItem:(nullable NSMenuItem *)item {
    if (item.action == @selector(loadColorPreset:)) {
        [self removeTimer];
        _timer = [NSTimer scheduledTimerWithTimeInterval:0.4 target:self selector:@selector(previewColors:) userInfo:item repeats:NO];
        [[NSRunLoop currentRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];
    } else {
        [self removeTimer];
        [self restoreColors];
    }
}

- (void)previewColors:(NSTimer *)timer {
    NSMenuItem *item = timer.userInfo;
    if (_timer) {
        _didPreviewPreset = YES;
        [self loadColorPresetWithName:item.identifier prompt:NO];
    }
    [self removeTimer];
}
- (void)removeTimer {
    [_timer invalidate];
    _timer = nil;
}

- (void)menuDidClose:(NSMenu *)menu {
    [self removeTimer];
    [self restoreColors];
    _savedColors = nil;
    _didPreviewPreset = NO;
}

#pragma mark - Actions

- (IBAction)modeDidChange:(id)sender {
    for (PreferenceInfo *info in [self.keyMap objectEnumerator]) {
        [self updateValueForInfo:info];
    }
}

- (IBAction)showModeWarning:(id)sender {
    [_modeWarning it_showWarning:NSLocalizedString(@"Your current theme overrides the system light and dark mode setting, so color switching will not occur. You can change it in Settings > Appearance > General > Theme.", @"Color presets")];
}

#pragma mark - Overrides

- (NSArray *)keysForBulkCopy {
    return [[super keysForBulkCopy] flatMapWithBlock:^NSArray *(NSString *key) {
        if (![self shouldAmendKey:key]) {
            return @[ key ];
        }
        return @[ [key stringByAppendingString:COLORS_LIGHT_MODE_SUFFIX],
                  [key stringByAppendingString:COLORS_DARK_MODE_SUFFIX] ];
    }];
}

- (BOOL)shouldAmendKey:(NSString *)key {
    if ([key isEqualToString:KEY_BINDINGS]) {
        return NO;
    }
    if ([key isEqualToString:KEY_USE_SEPARATE_COLORS_FOR_LIGHT_AND_DARK_MODE]) {
        return NO;
    }
    if (![super boolForKey:KEY_USE_SEPARATE_COLORS_FOR_LIGHT_AND_DARK_MODE]) {
        return NO;
    }
    return YES;
}

- (NSString *)amendedKey:(NSString *)key {
    if (![self shouldAmendKey:key]) {
        return key;
    }
    switch (_mode.selectedTag) {
        case 0:  // Light mode
            return [key stringByAppendingString:COLORS_LIGHT_MODE_SUFFIX];
        case 1:  // Dark mode
            return [key stringByAppendingString:COLORS_DARK_MODE_SUFFIX];
    }
    return key;
}

- (void)setObject:(NSObject *)object forKey:(NSString *)key {
    [super setObject:object forKey:[self amendedKey:key]];
}

- (void)setBool:(BOOL)value forKey:(NSString *)key {
    [super setBool:value forKey:[self amendedKey:key]];
}

- (BOOL)boolForKey:(NSString *)key {
    return [super boolForKey:[self amendedKey:key]];
}

- (void)setFloat:(double)value forKey:(NSString *)key {
    [super setFloat:value forKey:[self amendedKey:key]];
}

- (double)floatForKey:(NSString *)key {
    return [super floatForKey:[self amendedKey:key]];
}

- (NSObject *)objectForKey:(NSString *)key {
    return [super objectForKey:[self amendedKey:key]];
}

#pragma mark - iTermSizeRememberingViewDelegate

- (void)sizeRememberingView:(iTermSizeRememberingView *)sender effectiveAppearanceDidChange:(NSAppearance *)effectiveAppearance {
    const BOOL dark = [NSApp effectiveAppearance].it_isDark;
    [_mode selectItemWithTag:dark ? 1 : 0];
    [self modeDidChange:_mode];
}

#pragma mark - iTermHueVisualizationViewDelegate

- (void)hueVisualizationDidModifyColorWithKey:(NSString *)key to:(NSColor *)color {
    // Preserve the source color space; see Issue 12720.
    [self setObject:[color dictionaryValuePreservingColorSpace] forKey:key];
}

@end
