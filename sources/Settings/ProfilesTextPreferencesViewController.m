//
//  ProfilesTextPreferencesViewController.m
//  iTerm
//
//  Created by George Nachman on 4/15/14.
//
//

#import "ProfilesTextPreferencesViewController.h"

#import "DebugLogging.h"
#import "FutureMethods.h"
#import "ITAddressBookMgr.h"
#import "iTermCursorBlinkFadeCurveIcon.h"
#import "iTermCursorBlinkFadePreset.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermFontPanel.h"
#import "iTermSizeRememberingView.h"
#import "iTermWarning.h"
#import "NSDictionary+iTerm.h"
#import "NSFont+iTerm.h"
#import "NSStringITerm.h"
#import "NSTextField+iTerm.h"
#import "PreferencePanel.h"
#import "PTYFontInfo.h"
#import "PTYTextView.h"
@import BetterFontPicker;

@interface ProfilesTextPreferencesViewController ()<BFPCompositeViewDelegate, BFPSizePickerViewDelegate, NSMenuItemValidation>
@property(nonatomic, strong) NSFont *normalFont;
@property(nonatomic, strong) NSFont *nonAsciiFont;
@end


@implementation ProfilesTextPreferencesViewController {
    // cursor type: underline/vertical bar/box
    // See ITermCursorType. One of: CURSOR_UNDERLINE, CURSOR_VERTICAL, CURSOR_BOX
    IBOutlet NSMatrix *_cursorType;
    IBOutlet NSTextField *_cursorTypeLabel;
    IBOutlet NSButton *_blinkingCursor;
    IBOutlet NSButton *_useBoldFont;
    IBOutlet NSButton *_blinkAllowed;
    IBOutlet NSButton *_shadow;
    IBOutlet NSButton *_hideOnLostFocus;
    IBOutlet NSButton *_animateMovement;
    IBOutlet NSButton *_animateMovementOnlyInInteractiveApps;
    IBOutlet NSButton *_cursorSmoothSlide;
    IBOutlet NSButton *_cursorSmoothBlink;
    // Button that opens the smooth-blink configuration popover.
    IBOutlet NSButton *_cursorSmoothBlinkConfigureButton;
    // Detached top-level view shown inside the popover. Hosts the fade duration
    // and curve controls below.
    IBOutlet NSView *_cursorBlinkFadePopoverView;
    IBOutlet NSTextField *_cursorBlinkFadeInDuration;
    IBOutlet NSTextField *_cursorBlinkFadeInDurationLabel;
    IBOutlet NSTextField *_cursorBlinkFadeOutDuration;
    IBOutlet NSTextField *_cursorBlinkFadeOutDurationLabel;
    IBOutlet NSPopUpButton *_cursorBlinkFadeInCurve;
    IBOutlet NSTextField *_cursorBlinkFadeInCurveLabel;
    IBOutlet NSPopUpButton *_cursorBlinkFadeOutCurve;
    IBOutlet NSTextField *_cursorBlinkFadeOutCurveLabel;
    IBOutlet NSTextField *_cursorBlinkVisibleDwell;
    IBOutlet NSTextField *_cursorBlinkVisibleDwellLabel;
    IBOutlet NSTextField *_cursorBlinkHiddenDwell;
    IBOutlet NSTextField *_cursorBlinkHiddenDwellLabel;
    IBOutlet NSPopUpButton *_cursorBlinkPresets;
    NSPopover *_cursorBlinkFadePopover;
    IBOutlet NSButton *_useItalicFont;
    IBOutlet NSButton *_ambiguousIsDoubleWidth;
    IBOutlet NSPopUpButton *_normalization;
    IBOutlet NSTextField *_normalizationLabel;
    IBOutlet NSButton *_useNonAsciiFont;
    IBOutlet NSButton *_asciiAntiAliased;
    IBOutlet NSButton *_nonasciiAntiAliased;
    IBOutlet NSPopUpButton *_thinStrokes;
    IBOutlet NSTextField *_thinStrokesLabel;
    IBOutlet NSButton *_unicodeVersion9;
    IBOutlet NSButton *_asciiLigatures;
    IBOutlet NSButton *_nonAsciiLigatures;
    IBOutlet NSButton *_powerline;
    IBOutlet BFPCompositeView *_asciiFontPicker;
    IBOutlet BFPCompositeView *_nonASCIIFontPicker;
    IBOutlet NSTextField *_ligatureWarning;
    IBOutlet NSTextField *_ligatureWarningNonAscii;
    BFPSizePickerView *_horizontalSpacingView;
    BFPSizePickerView *_verticalSpacingView;

    // Warning labels
    IBOutlet NSTextField *_normalFontWantsAntialiasing;
    IBOutlet NSTextField *_nonasciiFontWantsAntialiasing;

    // Hide this view to hide all non-ASCII font settings.
    IBOutlet NSView *_nonAsciiFontView;

    NSTextField *_cellMetricsLabel;
    iTermLanguageFontRulesEditorView *_languageFontRulesEditorView;
    SpecialExceptionsWindowController *_specialExceptionsWindowController;
    BOOL _controlsInitialized;
}

- (NSMatrix *)cursorType { return _cursorType; }
- (NSTextField *)cursorTypeLabel { return _cursorTypeLabel; }
- (NSButton *)blinkingCursor { return _blinkingCursor; }
- (NSButton *)cursorSmoothBlink { return _cursorSmoothBlink; }
- (NSButton *)cursorSmoothBlinkConfigureButton { return _cursorSmoothBlinkConfigureButton; }
- (NSButton *)cursorSmoothSlide { return _cursorSmoothSlide; }
- (NSButton *)shadow { return _shadow; }
- (NSButton *)hideOnLostFocus { return _hideOnLostFocus; }
- (NSButton *)animateMovement { return _animateMovement; }
- (NSButton *)animateMovementOnlyInInteractiveApps { return _animateMovementOnlyInInteractiveApps; }
- (NSView *)asciiFontPicker { return _asciiFontPicker; }
- (NSTextField *)cellMetricsLabel { return _cellMetricsLabel; }
- (NSView *)languageFontRulesEditorView { return _languageFontRulesEditorView; }
- (NSButton *)asciiAntiAliased { return _asciiAntiAliased; }
- (NSTextField *)normalFontWantsAntialiasing { return _normalFontWantsAntialiasing; }
- (NSButton *)asciiLigatures { return _asciiLigatures; }
- (NSTextField *)ligatureWarning { return _ligatureWarning; }
- (NSPopUpButton *)thinStrokes { return _thinStrokes; }
- (NSTextField *)thinStrokesLabel { return _thinStrokesLabel; }
- (NSButton *)useNonAsciiFont { return _useNonAsciiFont; }
- (NSView *)nonAsciiFontView { return _nonAsciiFontView; }
- (NSView *)nonASCIIFontPicker { return _nonASCIIFontPicker; }
- (NSButton *)nonasciiAntiAliased { return _nonasciiAntiAliased; }
- (NSTextField *)nonasciiFontWantsAntialiasing { return _nonasciiFontWantsAntialiasing; }
- (NSButton *)nonAsciiLigatures { return _nonAsciiLigatures; }
- (NSTextField *)ligatureWarningNonAscii { return _ligatureWarningNonAscii; }
- (NSButton *)useBoldFont { return _useBoldFont; }
- (NSButton *)blinkAllowed { return _blinkAllowed; }
- (NSButton *)useItalicFont { return _useItalicFont; }
- (NSButton *)powerline { return _powerline; }
- (NSPopUpButton *)normalization { return _normalization; }
- (NSTextField *)normalizationLabel { return _normalizationLabel; }
- (NSButton *)unicodeVersion9 { return _unicodeVersion9; }
- (NSButton *)ambiguousIsDoubleWidth { return _ambiguousIsDoubleWidth; }

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)loadView {
    iTermSizeRememberingView *root = [[iTermSizeRememberingView alloc] initWithFrame:NSMakeRect(0, 0, 694, 721)];
    NSBundle *bundle = [NSBundle bundleForClass:self.class];
    NSString *(^loc)(NSString *) = ^NSString *(NSString *key) {
        return NSLocalizedStringFromTableInBundle(key, @"Localizable", bundle, @"Profiles Text setting");
    };

    _cursorTypeLabel = [iTermSettingsControlFactory rightAlignedLabelWithTitle:@"Cursor:"];
    _cursorType = [iTermSettingsControlFactory radioMatrixWithTitles:@[ @"_", @"⏐", @"▋" ]
                                                                tags:@[ @0, @1, @2 ]
                                                          horizontal:YES
                                                              target:self
                                                              action:@selector(settingChanged:)];
    _blinkingCursor = [iTermSettingsControlFactory checkboxWithTitle:@"Blink" target:self action:@selector(settingChanged:)];
    _cursorSmoothBlink = [iTermSettingsControlFactory checkboxWithTitle:@"Smooth blink" target:self action:@selector(settingChanged:)];
    _cursorSmoothBlinkConfigureButton = [iTermSettingsControlFactory pushButtonWithTitle:@"Configure…"
                                                                                  target:self
                                                                                  action:@selector(configureSmoothBlink:)];
    _cursorSmoothSlide = [iTermSettingsControlFactory checkboxWithTitle:@"Smooth-typing animation" target:self action:@selector(settingChanged:)];
    _cursorSmoothSlide.toolTip = loc(@"When enabled, small horizontal cursor movements are animated. Not available for block cursors.");
    _shadow = [iTermSettingsControlFactory checkboxWithTitle:@"Shadow" target:self action:@selector(settingChanged:)];
    _hideOnLostFocus = [iTermSettingsControlFactory checkboxWithTitle:@"Hide when keyboard focus lost" target:self action:@selector(settingChanged:)];
    _animateMovement = [iTermSettingsControlFactory checkboxWithTitle:@"Animate large movements" target:self action:@selector(settingChanged:)];
    _animateMovement.toolTip = loc(@"When enabled, large cursor movements get an animation to help your eye follow the cursor.");
    _animateMovementOnlyInInteractiveApps = [iTermSettingsControlFactory checkboxWithTitle:@"…but only in interactive apps" target:self action:@selector(settingChanged:)];
    _animateMovementOnlyInInteractiveApps.toolTip = loc(@"When enabled, cursor animation only occurs in alternate screen mode. When disabled, cursor movements are always animated.");

    _cursorBlinkFadePopoverView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 297, 276)];
    _cursorBlinkFadeInDurationLabel = [iTermSettingsControlFactory rightAlignedLabelWithTitle:@"Fade in duration:"];
    _cursorBlinkFadeInDurationLabel.frame = NSMakeRect(12, 240, 121, 16);
    [_cursorBlinkFadePopoverView addSubview:_cursorBlinkFadeInDurationLabel];
    _cursorBlinkFadeInDuration = [iTermSettingsControlFactory textFieldWithWidth:96 placeholder:nil target:nil action:nil delegate:self];
    _cursorBlinkFadeInDuration.frame = NSMakeRect(139, 236, 96, 24);
    [_cursorBlinkFadePopoverView addSubview:_cursorBlinkFadeInDuration];
    NSTextField *sec1 = [iTermSettingsControlFactory labelWithTitle:@"sec"];
    sec1.frame = NSMakeRect(241, 240, 44, 16);
    [_cursorBlinkFadePopoverView addSubview:sec1];

    _cursorBlinkFadeInCurveLabel = [iTermSettingsControlFactory rightAlignedLabelWithTitle:@"Fade in curve:"];
    _cursorBlinkFadeInCurveLabel.frame = NSMakeRect(12, 206, 121, 16);
    [_cursorBlinkFadePopoverView addSubview:_cursorBlinkFadeInCurveLabel];
    _cursorBlinkFadeInCurve = [iTermSettingsControlFactory popUpButtonWithTitles:@[ @"Linear", @"Ease In", @"Ease Out", @"Ease In-Out" ]
                                                                            tags:@[ @0, @1, @2, @3 ]
                                                                          target:self
                                                                          action:@selector(settingChanged:)];
    _cursorBlinkFadeInCurve.frame = NSMakeRect(139, 201, 138, 24);
    [_cursorBlinkFadePopoverView addSubview:_cursorBlinkFadeInCurve];

    _cursorBlinkVisibleDwellLabel = [iTermSettingsControlFactory rightAlignedLabelWithTitle:@"Dwell visible:"];
    _cursorBlinkVisibleDwellLabel.frame = NSMakeRect(12, 173, 121, 16);
    [_cursorBlinkFadePopoverView addSubview:_cursorBlinkVisibleDwellLabel];
    _cursorBlinkVisibleDwell = [iTermSettingsControlFactory textFieldWithWidth:96 placeholder:nil target:nil action:nil delegate:self];
    _cursorBlinkVisibleDwell.frame = NSMakeRect(139, 169, 96, 24);
    [_cursorBlinkFadePopoverView addSubview:_cursorBlinkVisibleDwell];
    NSTextField *sec2 = [iTermSettingsControlFactory labelWithTitle:@"sec"];
    sec2.frame = NSMakeRect(241, 173, 44, 16);
    [_cursorBlinkFadePopoverView addSubview:sec2];

    NSBox *sep1 = [[NSBox alloc] initWithFrame:NSMakeRect(20, 158, 265, 5)];
    sep1.boxType = NSBoxSeparator;
    [_cursorBlinkFadePopoverView addSubview:sep1];

    _cursorBlinkFadeOutDurationLabel = [iTermSettingsControlFactory rightAlignedLabelWithTitle:@"Fade out duration:"];
    _cursorBlinkFadeOutDurationLabel.frame = NSMakeRect(12, 132, 121, 16);
    [_cursorBlinkFadePopoverView addSubview:_cursorBlinkFadeOutDurationLabel];
    _cursorBlinkFadeOutDuration = [iTermSettingsControlFactory textFieldWithWidth:96 placeholder:nil target:nil action:nil delegate:self];
    _cursorBlinkFadeOutDuration.frame = NSMakeRect(139, 128, 96, 24);
    [_cursorBlinkFadePopoverView addSubview:_cursorBlinkFadeOutDuration];
    NSTextField *sec3 = [iTermSettingsControlFactory labelWithTitle:@"sec"];
    sec3.frame = NSMakeRect(241, 132, 44, 16);
    [_cursorBlinkFadePopoverView addSubview:sec3];

    _cursorBlinkFadeOutCurveLabel = [iTermSettingsControlFactory rightAlignedLabelWithTitle:@"Fade out curve:"];
    _cursorBlinkFadeOutCurveLabel.frame = NSMakeRect(12, 97, 121, 16);
    [_cursorBlinkFadePopoverView addSubview:_cursorBlinkFadeOutCurveLabel];
    _cursorBlinkFadeOutCurve = [iTermSettingsControlFactory popUpButtonWithTitles:@[ @"Linear", @"Ease In", @"Ease Out", @"Ease In-Out" ]
                                                                             tags:@[ @0, @1, @2, @3 ]
                                                                           target:self
                                                                           action:@selector(settingChanged:)];
    _cursorBlinkFadeOutCurve.frame = NSMakeRect(139, 93, 138, 24);
    [_cursorBlinkFadePopoverView addSubview:_cursorBlinkFadeOutCurve];

    _cursorBlinkHiddenDwellLabel = [iTermSettingsControlFactory rightAlignedLabelWithTitle:@"Dwell invisible:"];
    _cursorBlinkHiddenDwellLabel.frame = NSMakeRect(12, 65, 121, 16);
    [_cursorBlinkFadePopoverView addSubview:_cursorBlinkHiddenDwellLabel];
    _cursorBlinkHiddenDwell = [iTermSettingsControlFactory textFieldWithWidth:96 placeholder:nil target:nil action:nil delegate:self];
    _cursorBlinkHiddenDwell.frame = NSMakeRect(139, 61, 96, 24);
    [_cursorBlinkFadePopoverView addSubview:_cursorBlinkHiddenDwell];
    NSTextField *sec4 = [iTermSettingsControlFactory labelWithTitle:@"sec"];
    sec4.frame = NSMakeRect(241, 65, 44, 16);
    [_cursorBlinkFadePopoverView addSubview:sec4];

    NSBox *sep2 = [[NSBox alloc] initWithFrame:NSMakeRect(20, 50, 265, 5)];
    sep2.boxType = NSBoxSeparator;
    [_cursorBlinkFadePopoverView addSubview:sep2];

    _cursorBlinkPresets = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(20, 20, 265, 24) pullsDown:YES];
    _cursorBlinkPresets.target = self;
    _cursorBlinkPresets.action = @selector(applyBlinkPreset:);
    NSMenuItem *presetHeader = [[NSMenuItem alloc] initWithTitle:loc(@"Presets") action:nil keyEquivalent:@""];
    presetHeader.hidden = YES;
    [_cursorBlinkPresets.menu addItem:presetHeader];
    NSArray<NSArray *> *presetPairs = @[
        @[ @"Breathing", @0 ],
        @[ @"Linear", @1 ],
        @[ @"Fast", @2 ],
        @[ @"Slow", @3 ],
        @[ @"Subtle", @4 ]
    ];
    for (NSArray *pair in presetPairs) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:loc(pair[0]) action:nil keyEquivalent:@""];
        item.tag = [pair[1] integerValue];
        [_cursorBlinkPresets.menu addItem:item];
    }
    [_cursorBlinkFadePopoverView addSubview:_cursorBlinkPresets];

    self.asciiFontLabel = [iTermSettingsControlFactory rightAlignedLabelWithTitle:@"Font:"];
    _asciiFontPicker = [[BFPCompositeView alloc] initWithFrame:NSMakeRect(0, 0, 544, 27)];
    _asciiAntiAliased = [iTermSettingsControlFactory checkboxWithTitle:@"Anti-aliased" target:self action:@selector(settingChanged:)];
    _normalFontWantsAntialiasing = [iTermSettingsControlFactory secondaryLabelWithTitle:@"(recommended for this font)" wrapping:NO];
    _asciiLigatures = [iTermSettingsControlFactory checkboxWithTitle:@"Use ligatures" target:self action:@selector(settingChanged:)];
    _ligatureWarning = [iTermSettingsControlFactory secondaryLabelWithTitle:@"⚠️ This may reduce performance" wrapping:NO];
    _thinStrokesLabel = [iTermSettingsControlFactory rightAlignedLabelWithTitle:@"Thin strokes:"];
    _thinStrokes = [iTermSettingsControlFactory popUpButtonWithTitles:@[
        @"Never",
        @"Always",
        @"On Retina Displays",
        @"-",
        @"With Dark Backgrounds",
        @"On Retina Displays and Dark Backgrounds"
    ]
                                                                 tags:@[ @0, @3, @4, @(-1), @2, @1 ]
                                                          separators:@[ @3 ]
                                                               target:self
                                                               action:@selector(settingChanged:)];

    self.manageCharacterFontsButton = [iTermSettingsControlFactory pushButtonWithTitle:@"Character Fonts…"
                                                                                target:self
                                                                                action:@selector(manageSpecialExceptions:)];
    self.nonAsciiFontLabel = [iTermSettingsControlFactory rightAlignedLabelWithTitle:@"Non-ASCII Font:"];
    _useNonAsciiFont = [iTermSettingsControlFactory checkboxWithTitle:@"Use a different font for non-ASCII text"
                                                               target:self
                                                               action:@selector(settingChanged:)];
    _useNonAsciiFont.toolTip = loc(@"The non-ASCII font affects all characters above code point 127.");
    _nonAsciiFontView = [[NSView alloc] initWithFrame:NSZeroRect];
    _nonASCIIFontPicker = [[BFPCompositeView alloc] initWithFrame:NSMakeRect(0, 0, 400, 27)];
    _nonasciiAntiAliased = [iTermSettingsControlFactory checkboxWithTitle:@"Anti-aliased" target:self action:@selector(settingChanged:)];
    _nonasciiFontWantsAntialiasing = [iTermSettingsControlFactory secondaryLabelWithTitle:@"(recommended for this font)" wrapping:NO];
    _nonAsciiLigatures = [iTermSettingsControlFactory checkboxWithTitle:@"Use ligatures" target:self action:@selector(settingChanged:)];
    _ligatureWarningNonAscii = [iTermSettingsControlFactory secondaryLabelWithTitle:@"⚠️ This may reduce performance" wrapping:NO];

    self.textRenderingLabel = [iTermSettingsControlFactory rightAlignedLabelWithTitle:@"Text Rendering:"];
    _useBoldFont = [iTermSettingsControlFactory checkboxWithTitle:@"Draw bold text in bold font" target:self action:@selector(settingChanged:)];
    _blinkAllowed = [iTermSettingsControlFactory checkboxWithTitle:@"Allow blinking text" target:self action:@selector(settingChanged:)];
    _useItalicFont = [iTermSettingsControlFactory checkboxWithTitle:@"Allow italic text" target:self action:@selector(settingChanged:)];
    _powerline = [iTermSettingsControlFactory checkboxWithTitle:@"Use built-in Powerline glyphs" target:self action:@selector(settingChanged:)];

    self.unicodeLabel = [iTermSettingsControlFactory rightAlignedLabelWithTitle:@"Unicode:"];
    _unicodeVersion9 = [iTermSettingsControlFactory checkboxWithTitle:@"Use Unicode version 9+ widths" target:self action:@selector(settingChanged:)];
    _ambiguousIsDoubleWidth = [iTermSettingsControlFactory checkboxWithTitle:@"Ambiguous characters are double-width" target:self action:@selector(settingChanged:)];
    _ambiguousIsDoubleWidth.toolTip = loc(@"If you work mostly in East Asian languages this can be helpful. For most users, it causes misalignment.");
    _normalizationLabel = [iTermSettingsControlFactory rightAlignedLabelWithTitle:@"Normalization:"];
    _normalization = [iTermSettingsControlFactory popUpButtonWithTitles:@[ @"None", @"NFC", @"NFD", @"HFS+" ]
                                                                   tags:@[ @0, @1, @2, @3 ]
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
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reloadProfiles)
                                                 name:kReloadAllProfiles
                                               object:nil];
    __weak __typeof(self) weakSelf = self;
    PreferenceInfo *info;
    info = [self defineControl:_cursorType
                    key:KEY_CURSOR_TYPE
            displayName:@"Cursor style"
                   type:kPreferenceInfoTypeMatrix
         settingChanged:^(id sender) { [self setInt:[[sender selectedCell] tag] forKey:KEY_CURSOR_TYPE]; }
                 update:^BOOL{
                     __strong __typeof(weakSelf) strongSelf = weakSelf;
                     if (!strongSelf) {
                         return NO;
                     }
                     [strongSelf->_cursorType selectCellWithTag:[self intForKey:KEY_CURSOR_TYPE]];
                     return YES;
                 }];
    info.observer = ^{
        [weakSelf updateShadowEnabled];
        [weakSelf updateSmoothSlideEnabled];
    };

    info = [self defineControl:_blinkingCursor
                           key:KEY_BLINKING_CURSOR
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.observer = ^{ [weakSelf updateSmoothBlinkControlsEnabled]; };

    [self defineControl:_useBoldFont
                    key:KEY_USE_BOLD_FONT
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_thinStrokes
                    key:KEY_THIN_STROKES
            relatedView:_thinStrokesLabel
                   type:kPreferenceInfoTypePopup];

    [self defineControl:_blinkAllowed
                    key:KEY_BLINK_ALLOWED
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_shadow
                    key:KEY_CURSOR_SHADOW
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];
    [self updateShadowEnabled];

    [self defineControl:_hideOnLostFocus
                    key:KEY_CURSOR_HIDDEN_WITHOUT_FOCUS
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_animateMovement
                    key:KEY_ANIMATE_MOVEMENT
            displayName:nil
                   type:kPreferenceInfoTypeCheckbox];
    info = [self defineControl:_animateMovementOnlyInInteractiveApps
                           key:KEY_ANIMATE_MOVEMENT_ONLY_IN_INTERACTIVE_APPS
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.shouldBeEnabled = ^BOOL{
        return [weakSelf boolForKey:KEY_ANIMATE_MOVEMENT];
    };
    [info addShouldBeEnabledDependencyOnSetting:KEY_ANIMATE_MOVEMENT controller:self];

    [self defineControl:_cursorSmoothSlide
                    key:KEY_CURSOR_SMOOTH_SLIDE
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];
    [self updateSmoothSlideEnabled];

    info = [self defineControl:_cursorSmoothBlink
                           key:KEY_CURSOR_SMOOTH_BLINK
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.shouldBeEnabled = ^BOOL{
        return [weakSelf boolForKey:KEY_BLINKING_CURSOR];
    };
    [info addShouldBeEnabledDependencyOnSetting:KEY_BLINKING_CURSOR controller:self];
    info.observer = ^{ [weakSelf updateSmoothBlinkControlsEnabled]; };

    // The fade/dwell controls live in the smooth-blink popover. They share
    // identical enable logic and (for the double fields) custom get/set blocks,
    // so they're defined via helpers below.
    [self defineSmoothBlinkDoubleField:_cursorBlinkFadeInDuration
                                 label:_cursorBlinkFadeInDurationLabel
                                   key:KEY_CURSOR_BLINK_FADE_IN_DURATION];
    [self defineSmoothBlinkDoubleField:_cursorBlinkFadeOutDuration
                                 label:_cursorBlinkFadeOutDurationLabel
                                   key:KEY_CURSOR_BLINK_FADE_OUT_DURATION];
    [self defineSmoothBlinkDoubleField:_cursorBlinkVisibleDwell
                                 label:_cursorBlinkVisibleDwellLabel
                                   key:KEY_CURSOR_BLINK_VISIBLE_DWELL];
    [self defineSmoothBlinkDoubleField:_cursorBlinkHiddenDwell
                                 label:_cursorBlinkHiddenDwellLabel
                                   key:KEY_CURSOR_BLINK_HIDDEN_DWELL];
    [self defineSmoothBlinkCurvePopup:_cursorBlinkFadeInCurve
                                label:_cursorBlinkFadeInCurveLabel
                                  key:KEY_CURSOR_BLINK_FADE_IN_CURVE
                              fadeOut:NO];
    [self defineSmoothBlinkCurvePopup:_cursorBlinkFadeOutCurve
                                label:_cursorBlinkFadeOutCurveLabel
                                  key:KEY_CURSOR_BLINK_FADE_OUT_CURVE
                              fadeOut:YES];
    [self updateSmoothBlinkControlsEnabled];

    [self defineControl:_useItalicFont
                    key:KEY_USE_ITALIC_FONT
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    info = [self defineControl:_asciiLigatures
                           key:KEY_ASCII_LIGATURES
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.observer = ^{
        [weakSelf updateLigatureWarning];
    };
    info = [self defineUnsearchableControl:_nonAsciiLigatures
                                       key:KEY_NON_ASCII_LIGATURES
                                      type:kPreferenceInfoTypeCheckbox];
    info.observer = ^{
        [weakSelf updateLigatureWarning];
    };
    info = [self defineControl:_ambiguousIsDoubleWidth
                           key:KEY_AMBIGUOUS_DOUBLE_WIDTH
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.customSettingChangedHandler = ^(id sender) {
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        BOOL isOn = [(NSButton *)sender state] == NSControlStateValueOn;
        if (isOn) {
            static NSString *const kWarnAboutAmbiguousWidth = @"NoSyncWarnAboutAmbiguousWidth";
            // This is a feature of dubious value inherited from iTerm 0.1. Some users who work in
            // mixed Asian/non-asian environments find it useful but almost nobody should turn it on
            // unless they really know what they're doing.
            iTermWarningSelection selection =
                [iTermWarning showWarningWithTitle:@"You probably don’t want to turn this on. "
                                                   @"It will confuse interactive programs. "
                                                   @"You might want it if you work mostly with "
                                                   @"East Asian text combined with legacy or "
                                                   @"mathematical character sets. "
                                                   @"Are you sure you want this?"
                                           actions:@[ @"Enable", @"Cancel" ]
                                        identifier:kWarnAboutAmbiguousWidth
                                       silenceable:kiTermWarningTypePermanentlySilenceable
                                            window:weakSelf.view.window];
            if (selection == kiTermWarningSelection0) {
                [strongSelf setBool:YES forKey:KEY_AMBIGUOUS_DOUBLE_WIDTH];
            } else {
                strongSelf->_ambiguousIsDoubleWidth.state = NSControlStateValueOff;
            }
        } else {
            [strongSelf setBool:NO forKey:KEY_AMBIGUOUS_DOUBLE_WIDTH];
        }
    };

    [self defineControl:_normalization
                    key:KEY_UNICODE_NORMALIZATION
            relatedView:_normalizationLabel
                   type:kPreferenceInfoTypePopup];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(unicodeVersionDidChange)
                                                 name:iTermUnicodeVersionDidChangeNotification
                                               object:nil];
    info = [self defineControl:_unicodeVersion9
                           key:KEY_UNICODE_VERSION
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox
                settingChanged:^(id sender) {
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        const NSInteger version = (strongSelf->_unicodeVersion9.state == NSControlStateValueOn) ? 9 : 8;
        [strongSelf setInteger:version forKey:KEY_UNICODE_VERSION];
    }
                        update:^BOOL{
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return NO;
        }
        strongSelf->_unicodeVersion9.state = [strongSelf integerForKey:KEY_UNICODE_VERSION] == 9 ? NSControlStateValueOn : NSControlStateValueOff;
        return YES;
    }];
    info.hasDefaultValue = ^BOOL{
        // Computed value
        return [weakSelf unsignedIntegerForKey:KEY_UNICODE_VERSION] == 9;
    };
    [self updateNonDefaultIndicatorVisibleForInfo:info];

    _asciiFontPicker.delegate = self;
    _asciiFontPicker.mode = BFPCompositeViewModeFixedPitch;
    _nonASCIIFontPicker.delegate = self;
    _nonASCIIFontPicker.mode = BFPCompositeViewModeFixedPitch;
    _horizontalSpacingView = [_asciiFontPicker addHorizontalSpacingAccessoryWithInitialValue:[self doubleForKey:KEY_HORIZONTAL_SPACING] * 100];
    _horizontalSpacingView.delegate = self;
    [_horizontalSpacingView clampWithMin:50 max:200];
    _verticalSpacingView = [_asciiFontPicker addVerticalSpacingAccessoryWithInitialValue:[self doubleForKey:KEY_VERTICAL_SPACING] * 100];
    _verticalSpacingView.delegate = self;
    [_verticalSpacingView clampWithMin:50 max:200];
    [self defineControl:_asciiFontPicker.horizontalSpacing.textField
                    key:KEY_HORIZONTAL_SPACING
            relatedView:nil
            displayName:@"Horizontal spacing"
                   type:kPreferenceInfoTypeIntegerTextField
         settingChanged:^(id sender) { assert(false); }
                 update:^BOOL{
                     __strong __typeof(weakSelf) strongSelf = weakSelf;
                     if (!strongSelf) {
                         return NO;
                     }
                     strongSelf->_asciiFontPicker.horizontalSpacing.size = [self doubleForKey:KEY_HORIZONTAL_SPACING] * 100;
                     return YES;
                 }
             searchable:YES];

    [self defineControl:_asciiFontPicker.verticalSpacing.textField
                    key:KEY_VERTICAL_SPACING
            relatedView:nil
            displayName:@"Vertical spacing"
                   type:kPreferenceInfoTypeIntegerTextField
         settingChanged:^(id sender) { assert(false); }
                 update:^BOOL{
                     __strong __typeof(weakSelf) strongSelf = weakSelf;
                     if (!strongSelf) {
                         return NO;
                     }
                     strongSelf->_asciiFontPicker.verticalSpacing.size = [self doubleForKey:KEY_VERTICAL_SPACING] * 100;
                     return YES;
                 }
             searchable:YES];

    info = [self defineControl:_useNonAsciiFont
                           key:KEY_USE_NONASCII_FONT
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.observer = ^{ [weakSelf updateNonAsciiFontViewVisibility]; };

    info = [self defineControl:_asciiAntiAliased
                           key:KEY_ASCII_ANTI_ALIASED
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.observer = ^{ [weakSelf updateWarnings]; };

    info = [self defineUnsearchableControl:_nonasciiAntiAliased
                                       key:KEY_NONASCII_ANTI_ALIASED
                                      type:kPreferenceInfoTypeCheckbox];
    info.observer = ^{ [weakSelf updateWarnings]; };

    [self defineControl:_powerline
                    key:KEY_POWERLINE
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    _cellMetricsLabel = [NSTextField labelWithString:@""];
    _cellMetricsLabel.font = [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightRegular];
    _cellMetricsLabel.textColor = [NSColor secondaryLabelColor];

    _languageFontRulesEditorView = [[iTermLanguageFontRulesEditorView alloc] init];
    _languageFontRulesEditorView.onConfigChanged = ^(NSString * _Nullable configString) {
        [weakSelf setString:configString ?: @"" forKey:KEY_FONT_CONFIG];
    };
    _languageFontRulesEditorView.onLayoutInvalidated = ^{
        [weakSelf.view it_invalidateProfileFormLayout];
    };

    [self updateFontsDescriptionsIncludingSpacing:YES];
    [self updateNonAsciiFontViewVisibility];
    [self updateLigatureWarning];
    [self installProfileLayout];
}

- (void)updateLigatureWarning {
    // Metal now renders both ASCII and non-ASCII ligatures natively on the GPU,
    // so enabling ligatures no longer forces a fallback to the legacy CPU renderer.
    _ligatureWarning.hidden = YES;
    _ligatureWarningNonAscii.hidden = YES;

    // Show the options button only when ligatures are enabled. I didn't want to do this but the
    // only way to prevent ligatures from being drawn is to use the "fast path" drawing code.
    // In the fast path, we also do not support stylistic alternatives or contextual alternates.
    if (_asciiLigatures.state == NSControlStateValueOn) {
        if (!_asciiFontPicker.hasOptionsButton) {
            [_asciiFontPicker addOptionsButton];
        }
    } else {
        [_asciiFontPicker removeOptionsButton];
    }
    if (_nonAsciiLigatures.state == NSControlStateValueOn) {
        if (![_nonASCIIFontPicker hasOptionsButton]) {
            [_nonASCIIFontPicker addOptionsButton];
        }
    } else {
        [_nonASCIIFontPicker removeOptionsButton];
    }
    [self.view it_invalidateProfileFormLayout];
}


- (void)unicodeVersionDidChange {
    [self infoForControl:_unicodeVersion9].onUpdate();
}

- (void)windowWillClose {
    [super windowWillClose];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)reloadProfile {
    [super reloadProfile];
    [self updateFontsDescriptionsIncludingSpacing:YES];
    [self updateNonAsciiFontViewVisibility];
    // reloadProfile runs once the profile (and thus boolForKey) is available, so
    // this is where the smooth-blink controls get their correct initial enabled
    // state.
    [self updateSmoothBlinkControlsEnabled];
}

- (NSArray *)keysForBulkCopy {
    NSArray *keys = @[ KEY_NORMAL_FONT, KEY_NON_ASCII_FONT, KEY_FONT_CONFIG ];
    return [[super keysForBulkCopy] arrayByAddingObjectsFromArray:keys];
}

- (void)updateNonAsciiFontViewVisibility {
    _nonAsciiFontView.hidden = ![self boolForKey:KEY_USE_NONASCII_FONT];
    [self.view it_invalidateProfileFormLayout];
}

- (void)updateFontsDescriptionsIncludingSpacing:(BOOL)includingSpacing {
    // Update the fonts.
    self.normalFont = [[self stringForKey:KEY_NORMAL_FONT] fontValueWithLigaturesEnabled:YES];
    self.nonAsciiFont = [[self stringForKey:KEY_NON_ASCII_FONT] fontValueWithLigaturesEnabled:YES];

    // Update the controls.
    const double horizontalSpacing = round([self doubleForKey:KEY_HORIZONTAL_SPACING] * 100);
    _asciiFontPicker.horizontalSpacing.size = horizontalSpacing;
    const double verticalSpacing = round([self doubleForKey:KEY_VERTICAL_SPACING] * 100);
    _asciiFontPicker.verticalSpacing.size = verticalSpacing;
    _asciiFontPicker.font = _normalFont;
    _nonASCIIFontPicker.font = _nonAsciiFont;

    if (self.normalFont.it_defaultLigatures) {
        _asciiLigatures.state = NSControlStateValueOn;
        _asciiLigatures.enabled = NO;
    } else if (self.normalFont.it_ligatureLevel == 0) {
        _asciiLigatures.state = NSControlStateValueOff;
        _asciiLigatures.enabled = NO;
    } else {
        _asciiLigatures.state = [self boolForKey:KEY_ASCII_LIGATURES] ? NSControlStateValueOn : NSControlStateValueOff;
        _asciiLigatures.enabled = YES;
    }
    if (self.nonAsciiFont.it_defaultLigatures) {
        _nonAsciiLigatures.state = NSControlStateValueOn;
        _nonAsciiLigatures.enabled = NO;
    } else if (self.nonAsciiFont.it_ligatureLevel == 0) {
        _nonAsciiLigatures.state = NSControlStateValueOff;
        _nonAsciiLigatures.enabled = NO;
    } else {
        _nonAsciiLigatures.state = [self boolForKey:KEY_NON_ASCII_LIGATURES] ? NSControlStateValueOn : NSControlStateValueOff;
        _nonAsciiLigatures.enabled = YES;
    }

    [self updateCellMetricsLabel];
    [_languageFontRulesEditorView loadConfigString:[self stringForKey:KEY_FONT_CONFIG]];
    [self updateWarnings];
}

- (void)updateCellMetricsLabel {
    NSFont *font = self.normalFont ?: [NSFont userFixedPitchFontOfSize:12];
    if (!font) {
        _cellMetricsLabel.stringValue = @"";
        return;
    }
    const CGFloat hspace = [self doubleForKey:KEY_HORIZONTAL_SPACING] ?: 1.0;
    const CGFloat vspace = [self doubleForKey:KEY_VERTICAL_SPACING] ?: 1.0;
    const NSSize cellSize = [PTYTextView charSizeForFont:font
                                       horizontalSpacing:hspace
                                         verticalSpacing:vspace];
    NSString *widthStr = (fabs(cellSize.width - round(cellSize.width)) > 0.01)
        ? [NSString stringWithFormat:@"%.1f", cellSize.width]
        : [NSString stringWithFormat:@"%.0f", cellSize.width];
    _cellMetricsLabel.stringValue = [NSString stringWithFormat:NSLocalizedString(@"Cell grid: %@ × %.0f pt", @"Computed terminal cell size in Typography settings"),
                                     widthStr,
                                     cellSize.height];
}

- (BOOL)cursorTypeSupportsShadow {
    switch ((ITermCursorType)[self intForKey:KEY_CURSOR_TYPE]) {
        case CURSOR_UNDERLINE:
        case CURSOR_VERTICAL:
            return YES;
        case CURSOR_BOX:
        case CURSOR_DEFAULT:
            return NO;
    }
    return NO;
}

- (void)updateShadowEnabled {
    _shadow.enabled = [self cursorTypeSupportsShadow];
}

- (BOOL)cursorTypeSupportsSmoothSlide {
    switch ((ITermCursorType)[self intForKey:KEY_CURSOR_TYPE]) {
        case CURSOR_UNDERLINE:
        case CURSOR_VERTICAL:
            return YES;
        case CURSOR_BOX:
        case CURSOR_DEFAULT:
            return NO;
    }
    return NO;
}

- (void)updateSmoothSlideEnabled {
    _cursorSmoothSlide.enabled = [self cursorTypeSupportsSmoothSlide];
}

// Smooth blink only matters when the cursor blinks, so its checkbox is enabled
// only when blinking is on, and the Configure button only when both are on. The
// framework's shouldBeEnabled dependency isn't reliably applied for these (the
// initial enabled state is evaluated before shouldBeEnabled is assigned), so we
// drive it explicitly from the blinking/smooth-blink observers and reloadProfile.
- (void)updateSmoothBlinkControlsEnabled {
    const BOOL blinks = [self boolForKey:KEY_BLINKING_CURSOR];
    _cursorSmoothBlink.enabled = blinks;
    _cursorSmoothBlinkConfigureButton.enabled = blinks && [self boolForKey:KEY_CURSOR_SMOOTH_BLINK];
}

// Defines one of the smooth-blink duration/dwell fields. Custom get/set blocks
// are supplied so the non-integer default is not type-checked against
// kPreferenceInfoTypeDoubleTextField (which otherwise requires whole-number
// defaults). All such fields are enabled only when blinking and smooth blink
// are both on.
- (void)defineSmoothBlinkDoubleField:(NSTextField *)field
                               label:(NSView *)label
                                 key:(NSString *)key {
    __weak __typeof(self) weakSelf = self;
    __weak NSTextField *weakField = field;
    PreferenceInfo *info = [self defineControl:field
                                           key:key
                                   relatedView:label
                                          type:kPreferenceInfoTypeDoubleTextField
                                settingChanged:^(id sender) {
        [weakSelf setFloat:MAX(0, [sender doubleValue]) forKey:key];
    }
                                        update:^BOOL{
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        NSTextField *strongField = weakField;
        if (!strongSelf || !strongField) {
            return NO;
        }
        strongField.doubleValue = [strongSelf floatForKey:key];
        return YES;
    }];
    info.shouldBeEnabled = ^BOOL{
        return [weakSelf boolForKey:KEY_BLINKING_CURSOR] && [weakSelf boolForKey:KEY_CURSOR_SMOOTH_BLINK];
    };
    [info addShouldBeEnabledDependencyOnSetting:KEY_BLINKING_CURSOR controller:self];
    [info addShouldBeEnabledDependencyOnSetting:KEY_CURSOR_SMOOTH_BLINK controller:self];
}

// Defines a fade curve popup and assigns its menu-item icons.
- (void)defineSmoothBlinkCurvePopup:(NSPopUpButton *)popup
                              label:(NSView *)label
                                key:(NSString *)key
                            fadeOut:(BOOL)fadeOut {
    __weak __typeof(self) weakSelf = self;
    PreferenceInfo *info = [self defineControl:popup
                                           key:key
                                   relatedView:label
                                          type:kPreferenceInfoTypePopup];
    info.shouldBeEnabled = ^BOOL{
        return [weakSelf boolForKey:KEY_BLINKING_CURSOR] && [weakSelf boolForKey:KEY_CURSOR_SMOOTH_BLINK];
    };
    [info addShouldBeEnabledDependencyOnSetting:KEY_BLINKING_CURSOR controller:self];
    [info addShouldBeEnabledDependencyOnSetting:KEY_CURSOR_SMOOTH_BLINK controller:self];
    [self assignCurveIconsToPopup:popup fadeOut:fadeOut];
}

// Checkmarks the preset (if any) that matches the current configuration when
// the presets pull-down opens. Nothing is checked when the values are custom.
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    if (menuItem.action == @selector(applyBlinkPreset:)) {
        iTermCursorBlinkFadePreset *preset = [iTermCursorBlinkFadePreset presetWithTag:menuItem.tag];
        const BOOL matches =
            preset != nil &&
            [preset matchesFadeInDuration:[self floatForKey:KEY_CURSOR_BLINK_FADE_IN_DURATION]
                          fadeOutDuration:[self floatForKey:KEY_CURSOR_BLINK_FADE_OUT_DURATION]
                              fadeInCurve:[self intForKey:KEY_CURSOR_BLINK_FADE_IN_CURVE]
                             fadeOutCurve:[self intForKey:KEY_CURSOR_BLINK_FADE_OUT_CURVE]
                             visibleDwell:[self floatForKey:KEY_CURSOR_BLINK_VISIBLE_DWELL]
                              hiddenDwell:[self floatForKey:KEY_CURSOR_BLINK_HIDDEN_DWELL]];
        menuItem.state = matches ? NSControlStateValueOn : NSControlStateValueOff;
    }
    return YES;
}

// Give each menu item in a curve popup an icon that plots its curve. Items are
// matched by tag to the iTermCursorBlinkFadeCurve value. The fade-out popup
// flips the plot vertically so it reads as opacity falling over time.
- (void)assignCurveIconsToPopup:(NSPopUpButton *)popup fadeOut:(BOOL)fadeOut {
    for (NSMenuItem *item in popup.itemArray) {
        item.image = [iTermCursorBlinkFadeCurveIcon imageForCurve:(iTermCursorBlinkFadeCurve)item.tag
                                                          fadeOut:fadeOut];
    }
}

- (IBAction)configureSmoothBlink:(id)sender {
    if (_cursorBlinkFadePopover.isShown) {
        [_cursorBlinkFadePopover close];
        return;
    }
    if (!_cursorBlinkFadePopover) {
        NSViewController *viewController = [[NSViewController alloc] init];
        viewController.view = _cursorBlinkFadePopoverView;
        _cursorBlinkFadePopover = [[NSPopover alloc] init];
        _cursorBlinkFadePopover.contentViewController = viewController;
        _cursorBlinkFadePopover.behavior = NSPopoverBehaviorTransient;
    }
    // The popover controls are wired in the xib to the -settingChanged: responder
    // chain, which reaches this controller while the view lives in the prefs
    // window but breaks once the view is hosted in the popover's own window and
    // cycled. Bind the controls' targets explicitly so they keep working across
    // repeated opens.
    [self bindSmoothBlinkPopoverControls];
    NSView *anchor = [sender isKindOfClass:[NSView class]] ? (NSView *)sender : _cursorSmoothBlinkConfigureButton;
    [_cursorBlinkFadePopover showRelativeToRect:anchor.bounds
                                         ofView:anchor
                                  preferredEdge:NSRectEdgeMaxY];
}

// Point the popover's controls directly at this controller instead of relying
// on the responder chain (see configureSmoothBlink:). Idempotent.
- (void)bindSmoothBlinkPopoverControls {
    for (NSControl *control in @[ _cursorBlinkFadeInDuration, _cursorBlinkFadeOutDuration,
                                  _cursorBlinkVisibleDwell, _cursorBlinkHiddenDwell,
                                  _cursorBlinkFadeInCurve, _cursorBlinkFadeOutCurve ]) {
        control.target = self;
        control.action = @selector(settingChanged:);
    }
    // The presets pull-down's menu items carry their own action (the sender is
    // the NSMenuItem). Restore the target on just those items so both the action
    // and -validateMenuItem: reach this controller; leave the title/separator
    // items alone.
    for (NSMenuItem *item in _cursorBlinkPresets.itemArray) {
        if (item.action == @selector(applyBlinkPreset:)) {
            item.target = self;
        }
    }
}

// Applies the selected preset by writing the six smooth-blink keys, then
// refreshes the duration/dwell/curve controls to show the new values.
- (IBAction)applyBlinkPreset:(id)sender {
    // The sender may be the popup button (selectedTag) or, when the menu item's
    // own action is connected, the NSMenuItem (tag).
    NSInteger tag;
    if ([sender isKindOfClass:[NSPopUpButton class]]) {
        tag = [(NSPopUpButton *)sender selectedTag];
    } else if ([sender respondsToSelector:@selector(tag)]) {
        tag = [(id)sender tag];
    } else {
        return;
    }
    iTermCursorBlinkFadePreset *preset = [iTermCursorBlinkFadePreset presetWithTag:tag];
    if (!preset) {
        return;
    }
    [self setFloat:preset.fadeInDuration forKey:KEY_CURSOR_BLINK_FADE_IN_DURATION];
    [self setFloat:preset.fadeOutDuration forKey:KEY_CURSOR_BLINK_FADE_OUT_DURATION];
    [self setInt:preset.fadeInCurve forKey:KEY_CURSOR_BLINK_FADE_IN_CURVE];
    [self setInt:preset.fadeOutCurve forKey:KEY_CURSOR_BLINK_FADE_OUT_CURVE];
    [self setFloat:preset.visibleDwell forKey:KEY_CURSOR_BLINK_VISIBLE_DWELL];
    [self setFloat:preset.hiddenDwell forKey:KEY_CURSOR_BLINK_HIDDEN_DWELL];

    for (NSString *key in @[ KEY_CURSOR_BLINK_FADE_IN_DURATION,
                             KEY_CURSOR_BLINK_FADE_OUT_DURATION,
                             KEY_CURSOR_BLINK_FADE_IN_CURVE,
                             KEY_CURSOR_BLINK_FADE_OUT_CURVE,
                             KEY_CURSOR_BLINK_VISIBLE_DWELL,
                             KEY_CURSOR_BLINK_HIDDEN_DWELL ]) {
        [self updateControlForKey:key];
    }
}

- (void)updateWarnings {
    [_normalFontWantsAntialiasing setHidden:!self.normalFont.futureShouldAntialias];
    [_nonasciiFontWantsAntialiasing setHidden:!self.nonAsciiFont.futureShouldAntialias];
    [self.view it_invalidateProfileFormLayout];
}


#pragma mark - Actions

- (IBAction)manageSpecialExceptions:(id)sender {
    _specialExceptionsWindowController = [SpecialExceptionsWindowController createWithConfigString:[self stringForKey:KEY_FONT_CONFIG]];
    __weak __typeof(self) weakSelf = self;
    [self.view.window beginSheet:_specialExceptionsWindowController.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSModalResponseOK) {
            [weakSelf loadConfigFromSpecialExceptionsWindowController];
        }
    }];
}

- (void)loadConfigFromSpecialExceptionsWindowController {
    NSString *updated = _specialExceptionsWindowController.configString;
    [self setString:updated forKey:KEY_FONT_CONFIG];
    [_languageFontRulesEditorView loadConfigString:updated];
    [self.view it_invalidateProfileFormLayout];
}

#pragma mark - Notifications

- (void)reloadProfiles {
    [self updateFontsDescriptionsIncludingSpacing:YES];
    [self.view it_invalidateProfileFormLayout];
}

- (void)preferenceDidChangeFromOtherPanel:(NSNotification *)notification {
    NSString *key = notification.userInfo[kPreferenceDidChangeFromOtherPanelKeyUserInfoKey];
    if ([key isEqualToString:KEY_NORMAL_FONT]) {
        _asciiFontPicker.font = [[self stringForKey:KEY_NORMAL_FONT] fontValueWithLigaturesEnabled:YES];
        self.normalFont = _asciiFontPicker.font;
        [self updateCellMetricsLabel];
    } else if ([key isEqualToString:KEY_NON_ASCII_FONT]) {
        _nonASCIIFontPicker.font = [[self stringForKey:KEY_NON_ASCII_FONT] fontValueWithLigaturesEnabled:YES];
    } else if ([key isEqualToString:KEY_FONT_CONFIG]) {
        [_languageFontRulesEditorView loadConfigString:[self stringForKey:KEY_FONT_CONFIG]];
        [self.view it_invalidateProfileFormLayout];
    }
    [super preferenceDidChangeFromOtherPanel:notification];
}

#pragma mark - BFPCompositeViewDelegate

- (void)fontPickerCompositeView:(BFPCompositeView *)view didSelectFont:(NSFont *)font {
    NSString *key;
    if (view == _asciiFontPicker) {
        key = KEY_NORMAL_FONT;
    } else {
        assert(view == _nonASCIIFontPicker);
        key = KEY_NON_ASCII_FONT;
    }
    [self setString:view.font.stringValue
             forKey:key];
    [self updateFontsDescriptionsIncludingSpacing:YES];
    [self updateLigatureWarning];
}

#pragma mark - BFPSizePickerViewDelegate

- (void)sizePickerView:(BFPSizePickerView *)sizePickerView didChangeSizeTo:(double)size {
    [self saveChangesFromFontPicker];
}

- (void)saveDeferredUpdates {
    [self.view.window makeFirstResponder:nil];
    [self saveChangesFromFontPicker];
    [super saveDeferredUpdates];
}

- (void)saveChangesFromFontPicker {
    NSInteger (^clamp)(NSInteger value) = ^NSInteger(NSInteger value) {
        return MIN(MAX(value, 50), 200);
    };
    // I don't know why these would sometimes be null, but let's not crash if
    // that happens. It was one of the major crashes in 3.3.1.
    id normalFont = _asciiFontPicker.font.stringValue ?: [NSNull null];
    id nonAsciiFont = _nonASCIIFontPicker.font.stringValue ?: [NSNull null];
    RLog(@"Save changes from font picker. asciiFontPicker=%@ asciiFontPicker.font=%@ asciiFontPicker.font.stringValue=%@", _asciiFontPicker, _asciiFontPicker.font, _asciiFontPicker.font.stringValue);
    RLog(@"Save changes from font picker. nonASCIIFontPicker=%@ asciiFontPicker.font=%@ asciiFontPicker.font.stringValue=%@", _nonASCIIFontPicker, _nonASCIIFontPicker.font, _nonASCIIFontPicker.font.stringValue);
    NSDictionary *dictionaryWithNulls = @{ KEY_HORIZONTAL_SPACING: @(clamp(_asciiFontPicker.horizontalSpacing.size) / 100.0),
                                           KEY_VERTICAL_SPACING: @(clamp(_asciiFontPicker.verticalSpacing.size) / 100.0),
                                           KEY_NORMAL_FONT: normalFont,
                                           KEY_NON_ASCII_FONT: nonAsciiFont };
    NSDictionary *dict = [dictionaryWithNulls dictionaryByRemovingNullValues];
    [self setObjectsFromDictionary:dict];
    self.normalFont = _asciiFontPicker.font ?: self.normalFont;
    [self updateCellMetricsLabel];
}

@end
