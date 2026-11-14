//
//  ProfilesWindowPreferencesViewController.h
//  iTerm
//
//  Created by George Nachman on 4/16/14.
//
//

#import "iTermProfilePreferencesBaseViewController.h"

CGFloat iTermMaxBlurRadius(void);

@interface ProfilesWindowPreferencesViewController : iTermProfilePreferencesBaseViewController

@property(nonatomic, readonly) NSSlider *transparency;
@property(nonatomic, readonly) NSTextField *transparencyLabel;
@property(nonatomic, readonly) NSTextField *transparencyOverrideNotice;
@property(nonatomic, readonly) NSButton *transparencyAffectsOnlyDefaultBackgroundColor;
@property(nonatomic, readonly) NSButton *useBlur;
@property(nonatomic, readonly) NSSlider *blurRadius;
@property(nonatomic, readonly) NSTextField *largeBlurRadiusWarning;
@property(nonatomic, readonly) NSButton *useBackgroundImage;
@property(nonatomic, readonly) NSPopUpButton *backgroundImageSourceMode;
@property(nonatomic, readonly) NSTextField *backgroundImageLabel;
@property(nonatomic, readonly) NSTextField *backgroundImageTextField;
@property(nonatomic, readonly) NSTextField *backgroundImageFolderTextField;
@property(nonatomic, readonly) NSTextField *backgroundImageFolderIntervalLabel;
@property(nonatomic, readonly) NSTextField *backgroundImageFolderIntervalField;
@property(nonatomic, readonly) NSTextField *rotationIntervalUnitsLabel;
@property(nonatomic, readonly) NSView *backgroundImagePreview;
@property(nonatomic, readonly) NSView *backgroundImageMode;
@property(nonatomic, readonly) NSSlider *blendAmount;
@property(nonatomic, readonly) NSView *settingsForNewWindows;
@property(nonatomic, readonly) NSTextField *columnsField;
@property(nonatomic, readonly) NSTextField *percentageWidthField;
@property(nonatomic, readonly) NSTextField *widthLabel;
@property(nonatomic, readonly) NSTextField *byLabel;
@property(nonatomic, readonly) NSTextField *rowsField;
@property(nonatomic, readonly) NSTextField *percentageHeightField;
@property(nonatomic, readonly) NSTextField *heightLabel;
@property(nonatomic, readonly) NSPopUpButton *rowsUnitsButton;
@property(nonatomic, readonly) NSPopUpButton *columnsUnitsButton;
@property(nonatomic, readonly) NSPopUpButton *windowStyle;
@property(nonatomic, readonly) NSTextField *windowStyleLabel;
@property(nonatomic, readonly) NSPopUpButton *screen;
@property(nonatomic, readonly) NSTextField *screenLabel;
@property(nonatomic, readonly) NSPopUpButton *space;
@property(nonatomic, readonly) NSTextField *spaceLabel;
@property(nonatomic, readonly) NSButton *openToolbelt;
@property(nonatomic, readonly) NSButton *hideAfterOpening;
@property(nonatomic, readonly) NSButton *lockSizeAutomatically;
@property(nonatomic, readonly) NSButton *preventTab;
@property(nonatomic, readonly) NSButton *initialUseTransparency;
@property(nonatomic, readonly) NSButton *useCustomTabTitle;
@property(nonatomic, readonly) NSTextField *customTabTitle;
@property(nonatomic, readonly) NSButton *useCustomWindowTitle;
@property(nonatomic, readonly) NSTextField *customWindowTitle;

@property(nonatomic, strong) IBOutlet NSTextField *transparencyMinLabel;
@property(nonatomic, strong) IBOutlet NSTextField *transparencyMaxLabel;
@property(nonatomic, strong) IBOutlet NSTextField *blurLabel;
@property(nonatomic, strong) IBOutlet NSTextField *blurMinLabel;
@property(nonatomic, strong) IBOutlet NSTextField *blurMaxLabel;
@property(nonatomic, strong) IBOutlet NSTextField *backgroundImageSectionLabel;
@property(nonatomic, strong) IBOutlet NSTextField *backgroundImageSourceLabel;
@property(nonatomic, strong) IBOutlet NSTextField *backgroundImageScalingLabel;
@property(nonatomic, strong) IBOutlet NSTextField *backgroundImageBlendingLabel;
@property(nonatomic, strong) IBOutlet NSTextField *blendBackgroundColorLabel;
@property(nonatomic, strong) IBOutlet NSTextField *blendImageLabel;
@property(nonatomic, strong) IBOutlet NSTextField *newTabsLabel NS_RETURNS_NOT_RETAINED;
@property(nonatomic, strong) IBOutlet NSTextField *newWindowsSizeLabel NS_RETURNS_NOT_RETAINED;

- (void)layoutSubviewsForEditCurrentSessionMode;

@end
