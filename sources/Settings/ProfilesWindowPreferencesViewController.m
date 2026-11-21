//
//  ProfilesWindowPreferencesViewController.m
//  iTerm
//
//  Created by George Nachman on 4/16/14.
//
//

#import "ProfilesWindowPreferencesViewController.h"
#import "DebugLogging.h"
#import "FutureMethods.h"
#import "ITAddressBookMgr.h"
#import "iTermFunctionCallTextFieldDelegate.h"
#import "iTermImageWell.h"
#import "iTermPreferences.h"
#import "iTermSizeRememberingView.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermVariableScope.h"
#import "iTermWarning.h"
#import "NSArray+iTerm.h"
#import "NSImage+iTerm.h"
#import "NSScreen+iTerm.h"
#import "NSTextField+iTerm.h"
#import "NSView+iTerm.h"
#import "PreferencePanel.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

// On macOS 10.13, we see that blur over 26 can turn red (issue 6138).
// On macOS 10.14, we have evidence that it's safe up to 64 (issue 9438).
// On macOS 10.15, this doesn't seem to be a problem and it works up to 64 (issue 9229).
CGFloat iTermMaxBlurRadius(void) {
    return 64;
}

typedef NS_ENUM(NSUInteger, iTermWindowUnitsTag) {
    iTermWindowUnitsTagCells = 0,
    iTermWindowUnitsTagScreenPercentage = 1
};

@interface ProfilesWindowPreferencesViewController ()<iTermImageWellDelegate>

@property(nonatomic, copy) NSString *backgroundImageFilename;

@end

@implementation ProfilesWindowPreferencesViewController {
    IBOutlet NSSlider *_transparency;
    IBOutlet NSTextField *_transparencyLabel;
    IBOutlet NSButton *_useBlur;
    IBOutlet NSButton *_initialUseTransparency;
    IBOutlet NSSlider *_blurRadius;
    IBOutlet NSButton *_useBackgroundImage;
    IBOutlet NSPopUpButton *_backgroundImageSourceMode;
    IBOutlet NSTextField *_backgroundImageLabel;  // text swaps between "Image:" and "Folder:"
    IBOutlet NSTextField *_backgroundImageTextField;
    IBOutlet NSTextField *_rotationIntervalUnitsLabel;
    IBOutlet NSTextField *_backgroundImageFolderTextField;
    IBOutlet NSTextField *_backgroundImageFolderIntervalLabel;
    IBOutlet NSTextField *_backgroundImageFolderIntervalField;
    IBOutlet NSTextField *_transparencyOverrideNotice;
    iTermFunctionCallTextFieldDelegate *_backgroundImageTextFieldDelegate;

    IBOutlet iTermImageWell *_backgroundImagePreview;
    IBOutlet NSButton *_backgroundImageMode;
    IBOutlet NSSlider *_blendAmount;
    IBOutlet NSTextField *_columnsField;
    IBOutlet NSTextField *_rowsField;

    IBOutlet NSTextField *_percentageWidthField;
    IBOutlet NSTextField *_percentageHeightField;
    IBOutlet NSTextField *_widthLabel;
    IBOutlet NSTextField *_heightLabel;
    IBOutlet NSPopUpButton *_columnsUnitsButton;
    IBOutlet NSPopUpButton *_rowsUnitsButton;
    IBOutlet NSTextField *_byLabel;

    IBOutlet NSButton *_hideAfterOpening;
    IBOutlet NSButton *_lockSizeAutomatically;
    IBOutlet NSPopUpButton *_windowStyle;
    IBOutlet NSPopUpButton *_screen;
    IBOutlet NSTextField *_screenLabel;
    IBOutlet NSPopUpButton *_space;
    IBOutlet NSTextField *_windowStyleLabel;
    IBOutlet NSTextField *_spaceLabel;
    IBOutlet NSButton *_preventTab;
    IBOutlet NSButton *_transparencyAffectsOnlyDefaultBackgroundColor;
    IBOutlet NSButton *_openToolbelt;
    IBOutlet NSButton *_useCustomWindowTitle;
    IBOutlet NSTextField *_customWindowTitle;
    IBOutlet NSView *_settingsForNewWindows;
    IBOutlet NSTextField *_largeBlurRadiusWarning;
    iTermFunctionCallTextFieldDelegate *_customWindowTitleDelegate;

    IBOutlet NSButton *_useCustomTabTitle;
    IBOutlet NSTextField *_customTabTitle;
    iTermFunctionCallTextFieldDelegate *_customTabTitleDelegate;
    NSString *_lastGuid;
    BOOL _controlsInitialized;
}

- (NSSlider *)transparency { return _transparency; }
- (NSTextField *)transparencyLabel { return _transparencyLabel; }
- (NSTextField *)transparencyOverrideNotice { return _transparencyOverrideNotice; }
- (NSButton *)transparencyAffectsOnlyDefaultBackgroundColor { return _transparencyAffectsOnlyDefaultBackgroundColor; }
- (NSButton *)useBlur { return _useBlur; }
- (NSSlider *)blurRadius { return _blurRadius; }
- (NSTextField *)largeBlurRadiusWarning { return _largeBlurRadiusWarning; }
- (NSButton *)useBackgroundImage { return _useBackgroundImage; }
- (NSPopUpButton *)backgroundImageSourceMode { return _backgroundImageSourceMode; }
- (NSTextField *)backgroundImageLabel { return _backgroundImageLabel; }
- (NSTextField *)backgroundImageTextField { return _backgroundImageTextField; }
- (NSTextField *)backgroundImageFolderTextField { return _backgroundImageFolderTextField; }
- (NSTextField *)backgroundImageFolderIntervalLabel { return _backgroundImageFolderIntervalLabel; }
- (NSTextField *)backgroundImageFolderIntervalField { return _backgroundImageFolderIntervalField; }
- (NSTextField *)rotationIntervalUnitsLabel { return _rotationIntervalUnitsLabel; }
- (NSView *)backgroundImagePreview { return _backgroundImagePreview; }
- (NSView *)backgroundImageMode { return _backgroundImageMode; }
- (NSSlider *)blendAmount { return _blendAmount; }
- (NSView *)settingsForNewWindows { return _settingsForNewWindows; }
- (NSTextField *)columnsField { return _columnsField; }
- (NSTextField *)percentageWidthField { return _percentageWidthField; }
- (NSTextField *)widthLabel { return _widthLabel; }
- (NSTextField *)byLabel { return _byLabel; }
- (NSTextField *)rowsField { return _rowsField; }
- (NSTextField *)percentageHeightField { return _percentageHeightField; }
- (NSTextField *)heightLabel { return _heightLabel; }
- (NSPopUpButton *)rowsUnitsButton { return _rowsUnitsButton; }
- (NSPopUpButton *)columnsUnitsButton { return _columnsUnitsButton; }
- (NSPopUpButton *)windowStyle { return _windowStyle; }
- (NSTextField *)windowStyleLabel { return _windowStyleLabel; }
- (NSPopUpButton *)screen { return _screen; }
- (NSTextField *)screenLabel { return _screenLabel; }
- (NSPopUpButton *)space { return _space; }
- (NSTextField *)spaceLabel { return _spaceLabel; }
- (NSButton *)openToolbelt { return _openToolbelt; }
- (NSButton *)hideAfterOpening { return _hideAfterOpening; }
- (NSButton *)lockSizeAutomatically { return _lockSizeAutomatically; }
- (NSButton *)preventTab { return _preventTab; }
- (NSButton *)initialUseTransparency { return _initialUseTransparency; }
- (NSButton *)useCustomTabTitle { return _useCustomTabTitle; }
- (NSTextField *)customTabTitle { return _customTabTitle; }
- (NSButton *)useCustomWindowTitle { return _useCustomWindowTitle; }
- (NSTextField *)customWindowTitle { return _customWindowTitle; }

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)loadView {
    iTermSizeRememberingView *root = [[iTermSizeRememberingView alloc] initWithFrame:NSMakeRect(0, 0, 609, 838)];
    NSBundle *bundle = [NSBundle bundleForClass:self.class];
    NSString *(^loc)(NSString *) = ^NSString *(NSString *key) {
        return NSLocalizedStringFromTableInBundle(key, @"Localizable", bundle, @"Profiles Window setting");
    };

    _transparencyLabel = [iTermSettingsControlFactory rightAlignedLabelWithTitle:@"Transparency:"];
    _transparency = [iTermSettingsControlFactory sliderWithMinValue:0
                                                           maxValue:1
                                                       initialValue:0
                                                              width:218
                                                  wrapInSliderView:YES
                                                             target:self
                                                             action:@selector(settingChanged:)];
    self.transparencyMinLabel = [iTermSettingsControlFactory secondaryLabelWithTitle:@"Opaque" wrapping:NO];
    self.transparencyMaxLabel = [iTermSettingsControlFactory secondaryLabelWithTitle:@"Transparent" wrapping:NO];
    _transparencyOverrideNotice = [iTermSettingsControlFactory secondaryLabelWithTitle:@"View > Use Transparency can override this setting temporarily per window."
                                                                              wrapping:YES];
    _transparencyAffectsOnlyDefaultBackgroundColor = [iTermSettingsControlFactory checkboxWithTitle:@"Keep background colors opaque"
                                                                                             target:self
                                                                                             action:@selector(settingChanged:)];
    _transparencyAffectsOnlyDefaultBackgroundColor.toolTip = loc(@"Enable this to make non-default background colors always opaque. This is useful when using Powerline in a translucent window.");

    self.blurLabel = [iTermSettingsControlFactory rightAlignedLabelWithTitle:@"Blur:"];
    _useBlur = [iTermSettingsControlFactory checkboxWithTitle:@"Blur content behind the window"
                                                       target:self
                                                       action:@selector(settingChanged:)];
    _blurRadius = [iTermSettingsControlFactory sliderWithMinValue:0.1
                                                         maxValue:iTermMaxBlurRadius()
                                                     initialValue:0.1
                                                            width:218
                                                wrapInSliderView:YES
                                                           target:self
                                                           action:@selector(settingChanged:)];
    self.blurMinLabel = [iTermSettingsControlFactory secondaryLabelWithTitle:@"Small Radius" wrapping:NO];
    self.blurMaxLabel = [iTermSettingsControlFactory secondaryLabelWithTitle:@"Large Radius" wrapping:NO];
    _largeBlurRadiusWarning = [iTermSettingsControlFactory secondaryLabelWithTitle:@"⚠️ Large radius may reduce performance" wrapping:NO];
    _largeBlurRadiusWarning.hidden = YES;

    self.backgroundImageSectionLabel = [iTermSettingsControlFactory rightAlignedLabelWithTitle:@"Background Image:"];
    _useBackgroundImage = [iTermSettingsControlFactory checkboxWithTitle:@"Use background image"
                                                                  target:self
                                                                  action:@selector(useBackgroundImageDidChange:)];
    self.backgroundImageSourceLabel = [iTermSettingsControlFactory rightAlignedLabelWithTitle:@"Source:"];
    _backgroundImageSourceMode = [iTermSettingsControlFactory popUpButtonWithTitles:@[ @"Single Image", @"Folder Rotation" ]
                                                                               tags:@[ @0, @1 ]
                                                                             target:self
                                                                             action:@selector(settingChanged:)];
    _backgroundImageLabel = [iTermSettingsControlFactory rightAlignedLabelWithTitle:@"Image:"];
    _backgroundImageTextField = [iTermSettingsControlFactory textFieldWithWidth:320
                                                                    placeholder:@"Path (Interpolated String)"
                                                                         target:self
                                                                         action:@selector(settingChanged:)
                                                                       delegate:self];
    _backgroundImageFolderTextField = [iTermSettingsControlFactory textFieldWithWidth:320
                                                                          placeholder:@"Folder path"
                                                                               target:self
                                                                               action:@selector(settingChanged:)
                                                                             delegate:self];
    _backgroundImageFolderIntervalLabel = [iTermSettingsControlFactory rightAlignedLabelWithTitle:@"Rotation Interval:"];
    _backgroundImageFolderIntervalField = [iTermSettingsControlFactory textFieldWithWidth:80
                                                                              placeholder:nil
                                                                                   target:self
                                                                                   action:@selector(settingChanged:)
                                                                                 delegate:self];
    _backgroundImageFolderIntervalField.stringValue = @"300";
    _rotationIntervalUnitsLabel = [iTermSettingsControlFactory labelWithTitle:@"seconds"];

    _backgroundImagePreview = [[iTermImageWell alloc] initWithFrame:NSMakeRect(0, 0, 426, 72)];
    _backgroundImagePreview.imageFrameStyle = NSImageFrameGrayBezel;
    _backgroundImagePreview.editable = NO;
    _backgroundImagePreview.wantsLayer = YES;
    _backgroundImagePreview.delegate = self;

    self.backgroundImageScalingLabel = [iTermSettingsControlFactory rightAlignedLabelWithTitle:@"Scaling mode:"];
    _backgroundImageMode = [iTermSettingsControlFactory popUpButtonWithTitles:@[ @"Stretch", @"Tile", @"Scale to Fill", @"Scale to Fit" ]
                                                                         tags:@[ @0, @1, @2, @3 ]
                                                                       target:self
                                                                       action:@selector(settingChanged:)];
    self.backgroundImageBlendingLabel = [iTermSettingsControlFactory rightAlignedLabelWithTitle:@"Blending:"];
    _blendAmount = [iTermSettingsControlFactory sliderWithMinValue:0
                                                          maxValue:1
                                                      initialValue:0.4
                                                             width:215
                                                 wrapInSliderView:YES
                                                            target:self
                                                            action:@selector(settingChanged:)];
    _blendAmount.toolTip = loc(@"How much of the background image is visible through the background color.");
    self.blendBackgroundColorLabel = [iTermSettingsControlFactory secondaryLabelWithTitle:@"Background Color" wrapping:NO];
    self.blendImageLabel = [iTermSettingsControlFactory secondaryLabelWithTitle:@"Image" wrapping:NO];

    _settingsForNewWindows = [[NSView alloc] initWithFrame:NSZeroRect];
    self.newTabsLabel = [iTermSettingsControlFactory rightAlignedLabelWithTitle:@"New tabs:"];
    _useCustomTabTitle = [iTermSettingsControlFactory checkboxWithTitle:@"Use custom title for new tabs using this profile"
                                                                 target:self
                                                                 action:@selector(settingChanged:)];
    _customTabTitle = [iTermSettingsControlFactory textFieldWithWidth:320
                                                          placeholder:@"Tab Title (Interpolated String)"
                                                               target:self
                                                               action:@selector(settingChanged:)
                                                             delegate:self];

    self.newWindowsSizeLabel = [iTermSettingsControlFactory rightAlignedLabelWithTitle:@"New windows:"];
    _columnsField = [iTermSettingsControlFactory textFieldWithWidth:54 placeholder:nil target:nil action:nil delegate:self];
    _columnsField.identifier = @"columns";
    _percentageWidthField = [iTermSettingsControlFactory textFieldWithWidth:54 placeholder:nil target:nil action:nil delegate:self];
    _percentageWidthField.identifier = @"percent_width";
    _columnsUnitsButton = [iTermSettingsControlFactory popUpButtonWithTitles:@[ @"Cells", @"% of screen" ]
                                                                        tags:@[ @0, @1 ]
                                                                      target:self
                                                                      action:@selector(unitsChanged:)];
    _columnsUnitsButton.identifier = @"column units";
    _widthLabel = [iTermSettingsControlFactory labelWithTitle:@"columns by"];
    _widthLabel.identifier = @"width_label";
    _byLabel = [iTermSettingsControlFactory labelWithTitle:@"by"];
    _byLabel.identifier = @"by_label";

    _rowsField = [iTermSettingsControlFactory textFieldWithWidth:54 placeholder:nil target:nil action:nil delegate:self];
    _rowsField.identifier = @"rows";
    _percentageHeightField = [iTermSettingsControlFactory textFieldWithWidth:54 placeholder:nil target:nil action:nil delegate:self];
    _percentageHeightField.identifier = @"percent_height";
    _rowsUnitsButton = [iTermSettingsControlFactory popUpButtonWithTitles:@[ @"Cells", @"% of screen" ]
                                                                     tags:@[ @0, @1 ]
                                                                   target:self
                                                                   action:@selector(unitsChanged:)];
    _rowsUnitsButton.identifier = @"row units";
    _heightLabel = [iTermSettingsControlFactory labelWithTitle:@"rows"];
    _heightLabel.identifier = @"height_label";

    _windowStyleLabel = [iTermSettingsControlFactory rightAlignedLabelWithTitle:@"Style:"];
    _windowStyle = [iTermSettingsControlFactory popUpButtonWithTitles:@[
        @"Normal",
        @"Full Screen",
        @"Maximized",
        @"-",
        @"No Title Bar",
        @"-",
        @"Centered",
        @"-",
        @"Bottom of Screen",
        @"Top of Screen",
        @"Left of Screen",
        @"Right of Screen"
    ]
                                                                 tags:@[ @0, @1, @15, @(-1), @12, @(-1), @17, @(-1), @5, @2, @6, @7 ]
                                                          separators:@[ @3, @5, @7 ]
                                                               target:self
                                                               action:@selector(settingChanged:)];

    _screenLabel = [iTermSettingsControlFactory rightAlignedLabelWithTitle:@"Screen:"];
    _screen = [iTermSettingsControlFactory popUpButtonWithTitles:@[] tags:@[] target:self action:@selector(settingChanged:)];

    _spaceLabel = [iTermSettingsControlFactory rightAlignedLabelWithTitle:@"Space:"];
    _space = [iTermSettingsControlFactory popUpButtonWithTitles:@[
        @"Current Space",
        @"All Spaces",
        @"-",
        @"Space 1",
        @"Space 2",
        @"Space 3",
        @"Space 4",
        @"Space 5",
        @"Space 6",
        @"Space 7",
        @"Space 8",
        @"Space 9"
    ]
                                                           tags:@[ @0, @(-1), @(-999), @1, @2, @3, @4, @5, @6, @7, @8, @9 ]
                                                    separators:@[ @2 ]
                                                         target:self
                                                         action:@selector(settingChanged:)];

    _hideAfterOpening = [iTermSettingsControlFactory checkboxWithTitle:@"Hide after opening" target:self action:@selector(settingChanged:)];
    _lockSizeAutomatically = [iTermSettingsControlFactory checkboxWithTitle:@"Lock window size automatically" target:self action:@selector(settingChanged:)];
    _openToolbelt = [iTermSettingsControlFactory checkboxWithTitle:@"Open toolbelt" target:self action:@selector(settingChanged:)];
    _preventTab = [iTermSettingsControlFactory checkboxWithTitle:@"Always open in a new window, never in a tab" target:self action:@selector(settingChanged:)];
    _initialUseTransparency = [iTermSettingsControlFactory checkboxWithTitle:@"Use transparency" target:self action:@selector(settingChanged:)];
    _useCustomWindowTitle = [iTermSettingsControlFactory checkboxWithTitle:@"Use custom window title for new windows using this profile"
                                                                    target:self
                                                                    action:@selector(settingChanged:)];
    _customWindowTitle = [iTermSettingsControlFactory textFieldWithWidth:320
                                                             placeholder:@"Window Title (Interpolated String)"
                                                                  target:self
                                                                  action:@selector(settingChanged:)
                                                                delegate:self];

    self.view = root;
    [self awakeFromNib];
}

- (void)awakeFromNib {
    if (_controlsInitialized) {
        return;
    }
    _controlsInitialized = YES;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reloadProfile)  // In superclass
                                                 name:kReloadAllProfiles
                                               object:nil];
    _backgroundImagePreview.layer.masksToBounds = YES;
    _backgroundImagePreview.acceptsFolders = YES;

    __weak __typeof(self) weakSelf = self;
    PreferenceInfo *info;
    info = [self defineControl:_backgroundImageTextField
                           key:KEY_BACKGROUND_IMAGE_LOCATION
                   displayName:@"Path to background image"
                          type:kPreferenceInfoTypeStringTextField];
    info.observer = ^{
        [weakSelf backgroundImageTextFieldDidChange];
    };
    _backgroundImageTextFieldDelegate = [[iTermFunctionCallTextFieldDelegate alloc] initWithPathSource:[iTermVariableHistory pathSourceForContext:iTermVariablesSuggestionContextSession]
                                                                                    passthrough:self
                                                                                  functionsOnly:NO];
    _backgroundImageTextField.delegate = _backgroundImageTextFieldDelegate;
    _backgroundImageFolderTextField.delegate = _backgroundImageTextFieldDelegate;
    info = [self defineControl:_backgroundImageSourceMode
                           key:KEY_BACKGROUND_IMAGE_SOURCE_MODE
                   displayName:@"Background image source mode"
                          type:kPreferenceInfoTypePopup];
    info.observer = ^{
        [weakSelf synchronizeBackgroundImageEnabledState];
        [weakSelf updateBackgroundImageUI];
        [weakSelf loadBackgroundImageForCurrentSource];
    };
    info = [self defineControl:_backgroundImageFolderTextField
                           key:KEY_BACKGROUND_IMAGE_FOLDER_LOCATION
                   displayName:@"Path to background image folder"
                          type:kPreferenceInfoTypeStringTextField];
    info.observer = ^{
        [weakSelf backgroundImageFolderTextFieldDidChange];
    };
    info = [self defineControl:_backgroundImageFolderIntervalField
                           key:KEY_BACKGROUND_IMAGE_FOLDER_INTERVAL
                   displayName:@"Background image folder interval"
                          type:kPreferenceInfoTypeIntegerTextField];
    info.observer = ^{
        [weakSelf sanitizeBackgroundImageFolderInterval];
    };

    info = [self defineControl:_transparency
                           key:KEY_TRANSPARENCY
                   relatedView:_transparencyLabel
                          type:kPreferenceInfoTypeSlider];
    info.observer = ^() {
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        BOOL haveTransparency = (strongSelf->_transparency.doubleValue > 0);
        strongSelf->_transparencyAffectsOnlyDefaultBackgroundColor.enabled = haveTransparency;
        strongSelf->_blurRadius.enabled = (strongSelf->_useBlur.state == NSControlStateValueOn) && haveTransparency;
        strongSelf->_useBlur.enabled = haveTransparency;
        strongSelf->_transparencyOverrideNotice.hidden = !haveTransparency;
        [strongSelf.view it_invalidateProfileFormLayout];
    };

    [self defineControl:_initialUseTransparency
                    key:KEY_INITIAL_USE_TRANSPARENCY
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    info = [self defineControl:_useBlur
                           key:KEY_BLUR
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.observer = ^() {
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        BOOL haveTransparency = (strongSelf->_transparency.doubleValue > 0);
        strongSelf->_blurRadius.enabled = (strongSelf->_useBlur.state == NSControlStateValueOn) && haveTransparency;
        [strongSelf updateBlurRadiusWarning];
    };

    _blurRadius.maxValue = iTermMaxBlurRadius();
    info = [self defineControl:_blurRadius
                           key:KEY_BLUR_RADIUS
                   displayName:@"Blur radius"
                          type:kPreferenceInfoTypeSlider];
    info.observer = ^{
        [weakSelf updateBlurRadiusWarning];
    };
    [self updateBlurRadiusWarning];

    info = [self defineControl:_backgroundImageMode
                           key:KEY_BACKGROUND_IMAGE_MODE
                   displayName:@"Background image scaling mode"
                          type:kPreferenceInfoTypePopup];
    info.observer = ^() {
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        switch ((iTermBackgroundImageMode)strongSelf->_backgroundImageMode.selectedTag) {
            case iTermBackgroundImageModeTile:
                self->_backgroundImagePreview.imageScaling = NSImageScaleNone;
                break;
            case iTermBackgroundImageModeStretch:
                self->_backgroundImagePreview.imageScaling = NSImageScaleAxesIndependently;
                break;
            case iTermBackgroundImageModeScaleAspectFit:
                self->_backgroundImagePreview.imageScaling = NSImageScaleProportionallyDown;
                break;
            case iTermBackgroundImageModeScaleAspectFill: {
                self->_backgroundImagePreview.imageScaling = NSImageScaleNone;
                NSString *filename = [self.backgroundImageFilename stringByExpandingTildeInPath];
                if (filename) {
                    NSImage *anImage = [[NSImage alloc] initWithContentsOfFile:filename];
                    strongSelf->_backgroundImagePreview.image = [anImage it_imageFillingSize:strongSelf->_backgroundImagePreview.frame.size];
                    self->_backgroundImagePreview.imageScaling = NSImageScaleNone;
                    self.backgroundImageFilename = filename;
                }
                break;
            }
        }
    };

    [self defineControl:_blendAmount
                    key:KEY_BLEND
            displayName:@"Background image blending"
                   type:kPreferenceInfoTypeSlider];
    [self updateBackgroundImageUI];
    [self loadBackgroundImageForCurrentSource];

    info = [self defineControl:_columnsField
                           key:KEY_COLUMNS
                   displayName:@"Window width in columns"
                          type:kPreferenceInfoTypeIntegerTextField];
    info.range = NSMakeRange(1, iTermMaxInitialSessionSize);

    info = [self defineControl:_rowsField
                           key:KEY_ROWS
                   displayName:@"Window height in rows"
                          type:kPreferenceInfoTypeIntegerTextField];
    info.range = NSMakeRange(1, iTermMaxInitialSessionSize);

    info = [self defineControl:_percentageWidthField
                           key:KEY_WIDTH_PERCENTAGE
                   displayName:@"Window width in percentage of screen width"
                          type:kPreferenceInfoTypeIntegerTextField];
    info.range = NSMakeRange(1, 100);

    info = [self defineControl:_percentageHeightField
                           key:KEY_HEIGHT_PERCENTAGE
                   displayName:@"Window height in percentage of screen height"
                          type:kPreferenceInfoTypeIntegerTextField];
    info.range = NSMakeRange(1, 100);

    [self defineControl:_hideAfterOpening
                    key:KEY_HIDE_AFTER_OPENING
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_lockSizeAutomatically
                    key:KEY_LOCK_WINDOW_SIZE_AUTOMATICALLY
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    info = [self defineControl:_windowStyle
                           key:KEY_WINDOW_TYPE
                   displayName:@"Window style for new windows"
                          type:kPreferenceInfoTypePopup];
    info.onUpdate = ^BOOL{
        // Reading KEY_WINDOW_TYPE can give a value for which the popup has no tag because when
        // the theme is compact some window types are rewritten to compact-specific values by
        // iTermThemedWindowType(). Therefore we must modify the value in user defaults to properly
        // select an item in the popup.
        return [weakSelf updateWindowTypeControlFromSettings];
    };
    info.customSettingChangedHandler = ^(id sender) {
        [weakSelf saveWindowType];
    };
    [self defineControl:_screen
                    key:KEY_SCREEN
            displayName:@"Initial screen for new windows"
                   type:kPreferenceInfoTypePopup
         settingChanged:^(id sender) { [self screenDidChange]; }
                 update:^BOOL{ [weakSelf updateScreen]; return YES; }];

    info = [self defineControl:_space
                           key:KEY_SPACE
                   displayName:@"Initial desktop/space for new windows"
                          type:kPreferenceInfoTypePopup];
    info.onChange = ^() {
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        if ([strongSelf->_space selectedTag] > 0) {
            [strongSelf maybeWarnAboutSpaces];
        }
    };

    [self defineControl:_preventTab
                    key:KEY_PREVENT_TAB
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_transparencyAffectsOnlyDefaultBackgroundColor
                    key:KEY_TRANSPARENCY_AFFECTS_ONLY_DEFAULT_BACKGROUND_COLOR
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_openToolbelt
                    key:KEY_OPEN_TOOLBELT
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    // Custom window title
    {
        info = [self defineControl:_useCustomWindowTitle
                               key:KEY_USE_CUSTOM_WINDOW_TITLE
                       displayName:@"Enable custom window title for new windows"
                              type:kPreferenceInfoTypeCheckbox];
        info.onChange = ^{
            [weakSelf updateCustomWindowTitleEnabled];
        };

        _customWindowTitleDelegate = [[iTermFunctionCallTextFieldDelegate alloc] initWithPathSource:[iTermVariableHistory pathSourceForContext:iTermVariablesSuggestionContextWindow]
                                                                                        passthrough:self
                                                                                      functionsOnly:NO];
        _customWindowTitleDelegate.canWarnAboutContextMistake = YES;
        _customWindowTitleDelegate.contextMistakeText = @"This interpolated string is evaluated in the window’s context, not the session’s context. To access variables in the current session, use currentTab.currentSession.sessionVariableNameHere";
        _customWindowTitle.delegate = _customWindowTitleDelegate;
        [self defineControl:_customWindowTitle
                        key:KEY_CUSTOM_WINDOW_TITLE
                displayName:@"Custom window title for new windows"
                       type:kPreferenceInfoTypeStringTextField];
        [self updateCustomWindowTitleEnabled];
    }

    // Custom tab title
    {
        info = [self defineControl:_useCustomTabTitle
                               key:KEY_USE_CUSTOM_TAB_TITLE
                       displayName:@"Enable custom tab title for new tabs"
                              type:kPreferenceInfoTypeCheckbox];
        info.onChange = ^{
            [weakSelf updateCustomTabTitleEnabled];
        };

        _customTabTitleDelegate = [[iTermFunctionCallTextFieldDelegate alloc] initWithPathSource:[iTermVariableHistory pathSourceForContext:iTermVariablesSuggestionContextTab]
                                                                                        passthrough:self
                                                                                      functionsOnly:NO];
        _customTabTitleDelegate.canWarnAboutContextMistake = YES;
        _customTabTitleDelegate.contextMistakeText = @"This interpolated string is evaluated in the tab’s context, not the session’s context. To access variables in the current session, use currentSession.sessionVariableNameHere";
        _customTabTitle.delegate = _customTabTitleDelegate;
        [self defineControl:_customTabTitle
                        key:KEY_CUSTOM_TAB_TITLE
                displayName:@"Custom tab title for new tabs"
                       type:kPreferenceInfoTypeStringTextField];
        [self updateCustomTabTitleEnabled];
    }

    [self addViewToSearchIndex:_useBackgroundImage
                   displayName:@"Background image enabled"
                       phrases:@[]
                           key:nil];
    [self addViewToSearchIndex:_backgroundImageSourceMode
                   displayName:@"Background image source mode"
                       phrases:@[]
                           key:nil];
    [self installProfileLayout];
}

- (NSDictionary *)dictionaryToSaveWindowType:(iTermWindowType)windowType {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    dict[KEY_WINDOW_TYPE] = @(windowType);
    switch ((iTermWindowUnitsTag)_rowsUnitsButton.selectedTag) {
        case iTermWindowUnitsTagScreenPercentage: {
            NSInteger height = _percentageHeightField.integerValue;
            if (height < 0) {
                height = 50;
            }
            dict[KEY_HEIGHT_PERCENTAGE] = @(height);
            break;
        }
        case iTermWindowUnitsTagCells:
            dict[KEY_HEIGHT_PERCENTAGE] = @-1;
            dict[KEY_ROWS] = @(_rowsField.integerValue);
            break;
    }

    switch ((iTermWindowUnitsTag)_columnsUnitsButton.selectedTag) {
        case iTermWindowUnitsTagScreenPercentage: {
            NSInteger width = _percentageWidthField.integerValue;
            if (width < 0) {
                width = 25;
            }
            dict[KEY_WIDTH_PERCENTAGE] = @(width);
            break;
        }
        case iTermWindowUnitsTagCells:
            dict[KEY_WIDTH_PERCENTAGE] = @-1;
            dict[KEY_COLUMNS] = @(_columnsField.integerValue);
            break;
    }
    return dict;
}

- (void)saveWindowType {
    const BOOL percentage = (_columnsUnitsButton.selectedTag == iTermWindowUnitsTagScreenPercentage ||
                             _rowsUnitsButton.selectedTag == iTermWindowUnitsTagScreenPercentage);
    switch ((iTermWindowType)_windowStyle.selectedTag) {
        case WINDOW_TYPE_NORMAL:
        case WINDOW_TYPE_NO_TITLE_BAR:
        case WINDOW_TYPE_COMPACT:
        case WINDOW_TYPE_CENTERED:
            [self setObjectsFromDictionary:[self dictionaryToSaveWindowType:_windowStyle.selectedTag]];
            break;

        case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:
        case WINDOW_TYPE_LION_FULL_SCREEN:
        case WINDOW_TYPE_ACCESSORY:
        case WINDOW_TYPE_MAXIMIZED:
        case WINDOW_TYPE_COMPACT_MAXIMIZED:
            [self setInteger:_windowStyle.selectedTag
                      forKey:KEY_WINDOW_TYPE];
            break;

        case WINDOW_TYPE_TOP_PERCENTAGE:
            [self setObjectsFromDictionary:[self dictionaryToSaveWindowType:percentage ? WINDOW_TYPE_TOP_PERCENTAGE : WINDOW_TYPE_TOP_CELLS]];
            break;
        case WINDOW_TYPE_BOTTOM_PERCENTAGE:
            [self setObjectsFromDictionary:[self dictionaryToSaveWindowType:percentage ? WINDOW_TYPE_BOTTOM_PERCENTAGE : WINDOW_TYPE_BOTTOM_CELLS]];
            break;
        case WINDOW_TYPE_LEFT_PERCENTAGE:
            [self setObjectsFromDictionary:[self dictionaryToSaveWindowType:percentage ? WINDOW_TYPE_LEFT_PERCENTAGE : WINDOW_TYPE_LEFT_CELLS]];
            break;
        case WINDOW_TYPE_RIGHT_PERCENTAGE:
            [self setObjectsFromDictionary:[self dictionaryToSaveWindowType:percentage ? WINDOW_TYPE_RIGHT_PERCENTAGE : WINDOW_TYPE_RIGHT_CELLS]];
            break;

        case WINDOW_TYPE_BOTTOM_CELLS:
        case WINDOW_TYPE_TOP_CELLS:
        case WINDOW_TYPE_LEFT_CELLS:
        case WINDOW_TYPE_RIGHT_CELLS:
            assert(NO);
            break;
    }
}

// The NIB titles are localized, but each window style swaps in more specific
// unit names, so these titles must be localized here too.
- (void)showUnitsButtonsWithColumnsInCells:(BOOL)columnsIsCells rowsInCells:(BOOL)rowsIsCells {
    _columnsUnitsButton.hidden = NO;
    _columnsUnitsButton.menu.itemArray[0].title = NSLocalizedString(@"Columns", @"Profile window size units");
    _columnsUnitsButton.menu.itemArray[1].title = NSLocalizedString(@"% of screen width", @"Profile window size units");
    [_columnsUnitsButton selectItemWithTag:columnsIsCells ? iTermWindowUnitsTagCells : iTermWindowUnitsTagScreenPercentage];

    _rowsUnitsButton.hidden = NO;
    _rowsUnitsButton.menu.itemArray[0].title = NSLocalizedString(@"Rows", @"Profile window size units");
    _rowsUnitsButton.menu.itemArray[1].title = NSLocalizedString(@"% of screen height", @"Profile window size units");
    [_rowsUnitsButton selectItemWithTag:rowsIsCells ? iTermWindowUnitsTagCells : iTermWindowUnitsTagScreenPercentage];
}

- (void)showCellCountLabels {
    _widthLabel.hidden = NO;
    _heightLabel.hidden = NO;
    _widthLabel.stringValue = NSLocalizedString(@"columns by", @"Profile window size");
    _heightLabel.stringValue = NSLocalizedString(@"rows", @"Profile window size");
}

- (BOOL)updateWindowTypeControlFromSettings {
    PreferenceInfo *info = [self infoForControl:_windowStyle];
    iTermWindowType type = iTermUnthemedWindowType([self intForKey:info.key]);
    switch (type) {
        case WINDOW_TYPE_NORMAL:
        case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:
        case WINDOW_TYPE_LION_FULL_SCREEN:
        case WINDOW_TYPE_TOP_PERCENTAGE:
        case WINDOW_TYPE_BOTTOM_PERCENTAGE:
        case WINDOW_TYPE_LEFT_PERCENTAGE:
        case WINDOW_TYPE_RIGHT_PERCENTAGE:
        case WINDOW_TYPE_NO_TITLE_BAR:
        case WINDOW_TYPE_COMPACT:
        case WINDOW_TYPE_ACCESSORY:
        case WINDOW_TYPE_MAXIMIZED:
        case WINDOW_TYPE_COMPACT_MAXIMIZED:
        case WINDOW_TYPE_CENTERED:
            [_windowStyle selectItemWithTag:type];
            break;
        case WINDOW_TYPE_BOTTOM_CELLS:
            [_windowStyle selectItemWithTag:WINDOW_TYPE_BOTTOM_PERCENTAGE];
            break;
        case WINDOW_TYPE_TOP_CELLS:
            [_windowStyle selectItemWithTag:WINDOW_TYPE_TOP_PERCENTAGE];
            break;
        case WINDOW_TYPE_LEFT_CELLS:
            [_windowStyle selectItemWithTag:WINDOW_TYPE_LEFT_PERCENTAGE];
            break;
        case WINDOW_TYPE_RIGHT_CELLS:
            [_windowStyle selectItemWithTag:WINDOW_TYPE_RIGHT_PERCENTAGE];
            break;
    }
    if (info.observer) {
        info.observer();
    }
    _columnsUnitsButton.hidden = YES;
    _rowsUnitsButton.hidden = YES;
    const BOOL columnsIsCells = (![self valueIsExplicitlySetForKey:KEY_WIDTH_PERCENTAGE] ||
                                 [self doubleForKey:KEY_WIDTH_PERCENTAGE] < 0);
    const BOOL rowsIsCells = (![self valueIsExplicitlySetForKey:KEY_HEIGHT_PERCENTAGE] ||
                              [self doubleForKey:KEY_HEIGHT_PERCENTAGE] < 0);

    switch (type) {
        case WINDOW_TYPE_NORMAL:
        case WINDOW_TYPE_COMPACT:
        case WINDOW_TYPE_CENTERED:
        case WINDOW_TYPE_NO_TITLE_BAR:
            _columnsField.hidden = !columnsIsCells;
            _rowsField.hidden = !rowsIsCells;
            _percentageWidthField.hidden = columnsIsCells;
            _percentageHeightField.hidden = rowsIsCells;

            _columnsField.enabled = YES;
            _rowsField.enabled = YES;
            _percentageWidthField.enabled = YES;
            _percentageHeightField.enabled = YES;

            [self showUnitsButtonsWithColumnsInCells:columnsIsCells rowsInCells:rowsIsCells];

            _widthLabel.hidden = YES;
            _heightLabel.hidden = YES;

            _byLabel.hidden = NO;
            break;

        case WINDOW_TYPE_ACCESSORY:
            _columnsField.enabled = YES;
            _columnsField.hidden = NO;

            _rowsField.enabled = YES;
            _rowsField.hidden = NO;

            _percentageWidthField.hidden = YES;
            _percentageHeightField.hidden = YES;

            [self showCellCountLabels];

            _byLabel.hidden = YES;
            break;

        case WINDOW_TYPE_BOTTOM_CELLS:
        case WINDOW_TYPE_TOP_CELLS:
            _columnsField.enabled = YES;
            _columnsField.hidden = NO;

            _rowsField.enabled = YES;
            _rowsField.hidden = NO;

            _percentageWidthField.hidden = YES;
            _percentageHeightField.hidden = YES;

            [self showUnitsButtonsWithColumnsInCells:columnsIsCells rowsInCells:rowsIsCells];

            _widthLabel.hidden = YES;
            _heightLabel.hidden = YES;

            _byLabel.hidden = NO;
            break;

        case WINDOW_TYPE_LEFT_CELLS:
        case WINDOW_TYPE_RIGHT_CELLS: {
            _columnsField.enabled = YES;
            _columnsField.hidden = NO;

            _rowsField.enabled = YES;
            _rowsField.hidden = NO;

            _percentageWidthField.hidden = YES;
            _percentageHeightField.hidden = YES;

            [self showUnitsButtonsWithColumnsInCells:columnsIsCells rowsInCells:rowsIsCells];

            _widthLabel.hidden = YES;
            _heightLabel.hidden = YES;

            _byLabel.hidden = YES;
            break;
        }

        case WINDOW_TYPE_TOP_PERCENTAGE:
        case WINDOW_TYPE_BOTTOM_PERCENTAGE:
            _columnsField.hidden = !columnsIsCells;
            _rowsField.hidden = !rowsIsCells;
            _percentageWidthField.hidden = columnsIsCells;
            _percentageHeightField.hidden = rowsIsCells;

            _columnsField.enabled = YES;
            _rowsField.enabled = YES;
            _percentageWidthField.enabled = YES;
            _percentageHeightField.enabled = YES;

            [self showUnitsButtonsWithColumnsInCells:columnsIsCells rowsInCells:rowsIsCells];

            _widthLabel.hidden = YES;
            _heightLabel.hidden = YES;

            _byLabel.hidden = NO;
            break;

        case WINDOW_TYPE_LEFT_PERCENTAGE:
        case WINDOW_TYPE_RIGHT_PERCENTAGE:
            _columnsField.hidden = !columnsIsCells;
            _rowsField.hidden = !rowsIsCells;
            _percentageWidthField.hidden = columnsIsCells;
            _percentageHeightField.hidden = rowsIsCells;

            _columnsField.enabled = YES;
            _rowsField.enabled = YES;
            _percentageWidthField.enabled = YES;
            _percentageHeightField.enabled = YES;

            [self showUnitsButtonsWithColumnsInCells:columnsIsCells rowsInCells:rowsIsCells];

            _widthLabel.hidden = YES;
            _heightLabel.hidden = YES;

            _byLabel.hidden = YES;
            break;

        case WINDOW_TYPE_MAXIMIZED:
        case WINDOW_TYPE_COMPACT_MAXIMIZED:
        case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:
        case WINDOW_TYPE_LION_FULL_SCREEN:
            _columnsField.hidden = NO;
            _columnsField.enabled = NO;

            _rowsField.hidden = NO;
            _rowsField.enabled = NO;

            _percentageWidthField.hidden = YES;
            _percentageHeightField.hidden = YES;

            _columnsUnitsButton.hidden = YES;
            _rowsUnitsButton.hidden = YES;
            [self showCellCountLabels];

            _byLabel.hidden = YES;
            break;
    }
    NSArray<NSView *> *views = @[ _columnsField,           // Editable number of columns
                                  _percentageWidthField,   // Editable percent of screen width
                                  _widthLabel,             // "columns by"
                                  _columnsUnitsButton,      // Popup [Columns / % of screen width]
                                  _byLabel,                // "by"
                                  _rowsField,              // Editable number of rows
                                  _percentageHeightField,  // Editable percent of screen height
                                  _heightLabel,            // "rows"
                                  _rowsUnitsButton          // Popup [Rows / % of screen height]
    ];
    if ([self.view it_hasProfileForm]) {
        [self.view it_invalidateProfileFormLayout];
        return YES;
    }
    CGFloat x = 0;
    for (NSView *view in views) {
        if (view.isHidden) {
            continue;
        }
        NSTextField *textField = [NSTextField castFrom:view];
        if (textField && !textField.isEditable) {
            [textField sizeToFit];
        }
        [[NSButton castFrom:view] sizeToFit];

        NSRect frame = view.frame;
        frame.origin.x = x;
        view.frame = frame;
        DLog(@"Set frame of %@ to %@", view.identifier, NSStringFromRect(frame));
        x += frame.size.width;
    }
    return YES;
}

- (void)backgroundImageTextFieldDidChange {
    [self synchronizeBackgroundImageEnabledState];
    [self loadBackgroundImageForCurrentSource];
    [self updateBackgroundImageUI];
}

- (void)backgroundImageFolderTextFieldDidChange {
    [self synchronizeBackgroundImageEnabledState];
    [self loadBackgroundImageForCurrentSource];
    [self updateBackgroundImageUI];
}

- (void)sanitizeBackgroundImageFolderInterval {
    const NSInteger minimumInterval = (NSInteger)iTermBackgroundImageRotationManager.minimumInterval;
    NSInteger interval = [self integerForKey:KEY_BACKGROUND_IMAGE_FOLDER_INTERVAL];
    if (interval < minimumInterval) {
        [self setInteger:minimumInterval forKey:KEY_BACKGROUND_IMAGE_FOLDER_INTERVAL];
        _backgroundImageFolderIntervalField.integerValue = minimumInterval;
    }
}

- (void)updateBlurRadiusWarning {
    // It seems to get slow around this point on some machines circa 2017.
    _largeBlurRadiusWarning.hidden = !([self boolForKey:KEY_BLUR] && [self floatForKey:KEY_BLUR_RADIUS] > 26);
    [self.view it_invalidateProfileFormLayout];
}

- (void)updateCustomWindowTitleEnabled {
    _customWindowTitle.enabled = [self boolForKey:KEY_USE_CUSTOM_WINDOW_TITLE];
}

- (void)updateCustomTabTitleEnabled {
    _customTabTitle.enabled = [self boolForKey:KEY_USE_CUSTOM_TAB_TITLE];
}

- (void)layoutSubviewsForEditCurrentSessionMode {
    _settingsForNewWindows.hidden = YES;
    [self.view it_invalidateProfileFormLayout];
}

#pragma mark - Notifications

// This is also a superclass method.
- (void)reloadProfile {
    [super reloadProfile];
    [self sanitizeBackgroundImageFolderInterval];
    [self synchronizeBackgroundImageEnabledState];
    [self updateBackgroundImageUI];
    [self loadBackgroundImageForCurrentSource];
    [self updateCustomWindowTitleEnabled];
    [self updateCustomTabTitleEnabled];
    [_customWindowTitle it_removeWarning];
    [_customTabTitle it_removeWarning];
    if (![[self stringForKey:KEY_GUID] isEqual:_lastGuid]) {
        _customTabTitleDelegate.canWarnAboutContextMistake = YES;
        _customWindowTitleDelegate.canWarnAboutContextMistake = YES;
        _lastGuid = [self stringForKey:KEY_GUID];
    }
}

#pragma mark - Actions

- (IBAction)unitsChanged:(id)sender {
    [self saveWindowType];
    [self updateWindowTypeControlFromSettings];
}

// Opens a file picker and updates views and state.
- (IBAction)useBackgroundImageDidChange:(id)sender {
    if ([_useBackgroundImage state] == NSControlStateValueOn) {
        [self openBackgroundPathPicker];
    } else {
        [self loadBackgroundImageWithFilename:nil];
        if ([self backgroundImageUsesFolderRotation]) {
            [self setString:nil forKey:KEY_BACKGROUND_IMAGE_FOLDER_LOCATION];
        } else {
            [self setString:nil forKey:KEY_BACKGROUND_IMAGE_LOCATION];
        }
    }
    [self updateBackgroundImageUI];
}

- (void)openBackgroundPathPicker {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseDirectories = YES;
    panel.canChooseFiles = YES;
    panel.allowsMultipleSelection = NO;
    panel.treatsFilePackagesAsDirectories = NO;
    panel.message = @"Choose an image for the background, or a folder to rotate through its images.";
    // Image-only filter dims non-image files. Folders stay selectable because
    // canChooseDirectories=YES treats them as containers, not content.
    panel.allowedContentTypes = [NSImage.imageTypes mapWithBlock:^id _Nullable(NSString *ext) {
        return [UTType typeWithIdentifier:ext];
    }];

    void (^completion)(NSInteger) = ^(NSInteger result) {
        if (result == NSModalResponseOK) {
            [self applyBackgroundImageSelectionAtPath:[[panel URLs] firstObject].path];
        } else {
            [self loadBackgroundImageForCurrentSource];
        }
    };

    [panel beginSheetModalForWindow:self.view.window completionHandler:completion];
}

// Applies a user-chosen path (from picker or drop) to the appropriate key and
// source mode, switching mode as needed.
- (void)applyBackgroundImageSelectionAtPath:(NSString *)path {
    if (path.length == 0) {
        return;
    }
    BOOL isDirectory = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory]) {
        [self loadBackgroundImageForCurrentSource];
        return;
    }
    if (isDirectory) {
        if (![self checkFolder:path]) {
            [self loadBackgroundImageForCurrentSource];
            return;
        }
        if ([iTermBackgroundImageRotationManager firstImagePathInFolder:path] == nil) {
            [iTermWarning showWarningWithTitle:[NSString stringWithFormat:@"The folder “%@” contains no images, so no background image will be shown.", path.lastPathComponent]
                                       actions:@[ @"OK" ]
                                     accessory:nil
                                    identifier:@"BackgroundFolderEmpty"
                                   silenceable:kiTermWarningTypePersistent
                                       heading:@"Empty Folder"
                                        window:self.view.window];
            [self setString:nil forKey:KEY_BACKGROUND_IMAGE_FOLDER_LOCATION];
            [self updateControlForKey:KEY_BACKGROUND_IMAGE_FOLDER_LOCATION];
            [self synchronizeBackgroundImageEnabledState];
            [self loadBackgroundImageForCurrentSource];
            [self updateBackgroundImageUI];
            return;
        }
        [self setString:path forKey:KEY_BACKGROUND_IMAGE_FOLDER_LOCATION];
        [self setUnsignedInteger:iTermBackgroundImageSourceModeFolderRotation
                          forKey:KEY_BACKGROUND_IMAGE_SOURCE_MODE];
        [self updateControlForKey:KEY_BACKGROUND_IMAGE_FOLDER_LOCATION];
    } else {
        [self checkImage:path];
        [self setString:path forKey:KEY_BACKGROUND_IMAGE_LOCATION];
        [self setUnsignedInteger:iTermBackgroundImageSourceModeSingleImage
                          forKey:KEY_BACKGROUND_IMAGE_SOURCE_MODE];
        [self updateControlForKey:KEY_BACKGROUND_IMAGE_LOCATION];
    }
    [self updateControlForKey:KEY_BACKGROUND_IMAGE_SOURCE_MODE];
    [self synchronizeBackgroundImageEnabledState];
    [self loadBackgroundImageForCurrentSource];
    [self updateBackgroundImageUI];
}

#pragma mark - iTermImageWellDelegate

- (void)imageWellDidClick:(iTermImageWell *)imageWell {
    [self openBackgroundPathPicker];
}

- (void)imageWellDidPerformDropOperation:(iTermImageWell *)imageWell filename:(NSString *)filename {
    [self applyBackgroundImageSelectionAtPath:filename];
}

#pragma mark - Background Image

- (BOOL)backgroundImageUsesFolderRotation {
    return [self unsignedIntegerForKey:KEY_BACKGROUND_IMAGE_SOURCE_MODE] == iTermBackgroundImageSourceModeFolderRotation;
}

- (NSString *)backgroundImageConfigurationPathForCurrentSource {
    if ([self backgroundImageUsesFolderRotation]) {
        return [self stringForKey:KEY_BACKGROUND_IMAGE_FOLDER_LOCATION];
    }
    return [self stringForKey:KEY_BACKGROUND_IMAGE_LOCATION];
}

- (void)updateBackgroundImageUI {
    const BOOL usesFolderRotation = [self backgroundImageUsesFolderRotation];
    _backgroundImageLabel.stringValue = usesFolderRotation ? @"Folder:" : @"Image:";
    // The image and folder text fields share the same xib rect, so hide the
    // inactive one. Disabled NSControls still consume hit-testing and would
    // block clicks to the field underneath.
    _backgroundImageTextField.hidden = usesFolderRotation;
    _backgroundImageFolderTextField.hidden = !usesFolderRotation;
    _backgroundImageFolderIntervalLabel.labelEnabled = usesFolderRotation;
    _rotationIntervalUnitsLabel.labelEnabled = usesFolderRotation;
    _backgroundImageFolderIntervalField.enabled = usesFolderRotation;
    [self.view it_invalidateProfileFormLayout];
}

- (void)synchronizeBackgroundImageEnabledState {
    _useBackgroundImage.state = self.backgroundImageConfigurationPathForCurrentSource.length > 0 ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)loadBackgroundImageForCurrentSource {
    if ([self backgroundImageUsesFolderRotation]) {
        [self loadBackgroundImageWithFilename:[self firstImageFilenameInFolder:[self stringForKey:KEY_BACKGROUND_IMAGE_FOLDER_LOCATION]]];
    } else {
        [self loadBackgroundImageWithFilename:[self stringForKey:KEY_BACKGROUND_IMAGE_LOCATION]];
    }
}

- (NSString *)firstImageFilenameInFolder:(NSString *)folderPath {
    return [iTermBackgroundImageRotationManager firstImagePathInFolder:folderPath];
}

// Sets _backgroundImagePreview and _useBackgroundImage.
- (void)loadBackgroundImageWithFilename:(NSString *)filename {
    NSImage *anImage = filename.length > 0 ? [[NSImage alloc] initWithContentsOfFile:[filename stringByExpandingTildeInPath]] : nil;
    if (anImage) {
        [_backgroundImagePreview setImage:anImage];
        self.backgroundImageFilename = filename;
    } else {
        [_backgroundImagePreview setImage:nil];
        self.backgroundImageFilename = nil;
    }
    [self updatePrivateNonDefaultInicators];
}

- (void)updateNonDefaultIndicators {
    [super updateNonDefaultIndicators];
    [self updatePrivateNonDefaultInicators];
}

- (void)updatePrivateNonDefaultInicators {
    _useBackgroundImage.it_showNonDefaultIndicator = [iTermPreferences boolForKey:kPreferenceKeyIndicateNonDefaultValues] && _useBackgroundImage.state == NSControlStateValueOn;
}

- (BOOL)checkImage:(NSString *)filename {
    NSError *error = nil;
    NSData *data = [NSData dataWithContentsOfFile:filename options:0 error:&error];
    if (!data) {
        [iTermWarning showWarningWithTitle:error.localizedDescription
                                   actions:@[ @"OK" ]
                                 accessory:nil
                                identifier:@"BackgroundImageUnreadable"
                               silenceable:kiTermWarningTypePersistent
                                   heading:@"Problem Loading Image"
                                    window:self.view.window];
        return NO;
    }
    if (data.length == 0) {
        [iTermWarning showWarningWithTitle:[NSString stringWithFormat:@"The image “%@” could not be loaded because the file is empty.", filename.lastPathComponent]
                                   actions:@[ @"OK" ]
                                 accessory:nil
                                identifier:@"BackgroundImageUnreadable"
                               silenceable:kiTermWarningTypePersistent
                                   heading:@"Problem Loading Image"
                                    window:self.view.window];
        return NO;
    }
    if (![[NSImage alloc] initWithData:data]) {
        [iTermWarning showWarningWithTitle:[NSString stringWithFormat:@"The image “%@” could not be loaded because it is corrupt or not a supported format.", filename.lastPathComponent]
                                   actions:@[ @"OK" ]
                                 accessory:nil
                                identifier:@"BackgroundImageUnreadable"
                               silenceable:kiTermWarningTypePersistent
                                   heading:@"Problem Loading Image"
                                    window:self.view.window];
        return NO;
    }
    return YES;
}

- (BOOL)checkFolder:(NSString *)filename {
    BOOL isDirectory = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:filename isDirectory:&isDirectory] || !isDirectory) {
        [iTermWarning showWarningWithTitle:[NSString stringWithFormat:@"The folder “%@” could not be used because it does not exist or is not a directory.", filename.lastPathComponent]
                                   actions:@[ @"OK" ]
                                 accessory:nil
                                identifier:@"BackgroundFolderUnreadable"
                               silenceable:kiTermWarningTypePersistent
                                   heading:@"Problem Loading Folder"
                                    window:self.view.window];
        return NO;
    }
    NSArray<NSURL *> *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:[NSURL fileURLWithPath:filename isDirectory:YES]
                                                               includingPropertiesForKeys:nil
                                                                                  options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                                    error:nil];
    if (!contents) {
        [iTermWarning showWarningWithTitle:[NSString stringWithFormat:@"The folder “%@” could not be read.", filename.lastPathComponent]
                                   actions:@[ @"OK" ]
                                 accessory:nil
                                identifier:@"BackgroundFolderUnreadable"
                               silenceable:kiTermWarningTypePersistent
                                   heading:@"Problem Loading Folder"
                                    window:self.view.window];
        return NO;
    }
    return YES;
}

#pragma mark - Screen

- (void)screenDidChange {
    [self repopulateScreen];
    [self setInt:[_screen selectedTag] forKey:KEY_SCREEN];
}

// Refreshes the entries in the list of screens and tries to preserve the current selection.
- (void)repopulateScreen {
    int selectedTag = [_screen selectedTag];
    [_screen removeAllItems];
    int i = 0;
    [_screen addItemWithTitle:NSLocalizedString(@"No Preference", @"Profile window screen")];
    [[_screen lastItem] setTag:-1];
    [_screen addItemWithTitle:NSLocalizedString(@"Screen with Cursor", @"Profile window screen")];
    [[_screen lastItem] setTag:-2];
    NSArray<NSScreen *> *screens = [NSScreen screens];
    NSMenuItem *separator = [NSMenuItem separatorItem];
    // Tag zero belongs to the main screen; selecting a separator hides its title.
    separator.tag = -1000;
    [_screen.menu addItem:separator];
    const int numScreens = [screens count];
    for (i = 0; i < numScreens; i++) {
        if (i == 0) {
            [_screen addItemWithTitle:NSLocalizedString(@"Main Screen", @"Profile window screen")];
        } else {
            [_screen addItemWithTitle:screens[i].it_uniqueName];
        }
        [[_screen lastItem] setTag:i];
    }
    if (selectedTag >= 0 && selectedTag < i) {
        [_screen selectItemWithTag:selectedTag];
    } else if (selectedTag == -1 || selectedTag == -2) {
        [_screen selectItemWithTag:selectedTag];
    } else {
        [_screen selectItemWithTag:-1];
    }
}

- (void)updateScreen {
    [self repopulateScreen];
    if (![_screen selectItemWithTag:[self intForKey:KEY_SCREEN]]) {
        [_screen selectItemWithTag:-1];
    }
}

#pragma mark - Spaces

- (void)maybeWarnAboutSpaces
{
    [iTermWarning showWarningWithTitle:@"To have a new window open in a specific space, "
                                       @"make sure that Spaces is enabled in System "
                                       @"Preferences and that it is configured to switch directly "
                                       @"to a space with ^ Number Keys."
                               actions:@[ @"OK" ]
                            identifier:@"NeverWarnAboutSpaces"
                           silenceable:kiTermWarningTypePermanentlySilenceable
                                window:self.view.window];
}


@end
