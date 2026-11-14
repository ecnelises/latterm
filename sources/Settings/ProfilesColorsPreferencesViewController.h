//
//  ProfilesColorsPreferencesViewController.h
//  iTerm
//
//  Created by George Nachman on 4/14/14.
//
//

#import "iTermProfilePreferencesBaseViewController.h"

extern NSString *const iTermColorPreferencesDidDisappear;
extern NSString *const iTermColorPreferencesDidAppear;

@interface ProfilesColorsPreferencesViewController : iTermProfilePreferencesBaseViewController
@property(nonatomic, readonly) NSButton *useSeparateColorsForLightAndDarkMode;
@property(nonatomic, readonly) NSButton *modeWarning;
@property(nonatomic, readonly) NSTextField *modeLabel;
@property(nonatomic, readonly) NSPopUpButton *mode;
@property(nonatomic, readonly) NSPopUpButton *presetsPopupButton;
@property(nonatomic, readonly) NSView *foregroundColor;
@property(nonatomic, readonly) NSTextField *foregroundColorLabel;
@property(nonatomic, readonly) NSView *backgroundColor;
@property(nonatomic, readonly) NSTextField *backgroundColorLabel;
@property(nonatomic, readonly) NSView *boldColor;
@property(nonatomic, readonly) NSView *linkColor;
@property(nonatomic, readonly) NSTextField *linkColorLabel;
@property(nonatomic, readonly) NSView *selectionColor;
@property(nonatomic, readonly) NSTextField *selectionColorLabel;
@property(nonatomic, readonly) NSView *selectedTextColor;
@property(nonatomic, readonly) NSButton *selectedTextColorEnabledButton;
@property(nonatomic, readonly) NSView *matchColor;
@property(nonatomic, readonly) NSTextField *matchColorLabel;
@property(nonatomic, readonly) NSView *cursorColor;
@property(nonatomic, readonly) NSTextField *cursorColorLabel;
@property(nonatomic, readonly) NSView *cursorTextColor;
@property(nonatomic, readonly) NSTextField *cursorTextColorLabel;
@property(nonatomic, readonly) NSView *imeCursorColor;
@property(nonatomic, readonly) NSTextField *imeCursorColorLabel;
@property(nonatomic, readonly) NSView *ansi0Color;
@property(nonatomic, readonly) NSView *ansi1Color;
@property(nonatomic, readonly) NSView *ansi2Color;
@property(nonatomic, readonly) NSView *ansi3Color;
@property(nonatomic, readonly) NSView *ansi4Color;
@property(nonatomic, readonly) NSView *ansi5Color;
@property(nonatomic, readonly) NSView *ansi6Color;
@property(nonatomic, readonly) NSView *ansi7Color;
@property(nonatomic, readonly) NSView *ansi8Color;
@property(nonatomic, readonly) NSView *ansi9Color;
@property(nonatomic, readonly) NSView *ansi10Color;
@property(nonatomic, readonly) NSView *ansi11Color;
@property(nonatomic, readonly) NSView *ansi12Color;
@property(nonatomic, readonly) NSView *ansi13Color;
@property(nonatomic, readonly) NSView *ansi14Color;
@property(nonatomic, readonly) NSView *ansi15Color;
@property(nonatomic, readonly) NSTextField *ansi0ColorLabel;
@property(nonatomic, readonly) NSTextField *ansi1ColorLabel;
@property(nonatomic, readonly) NSTextField *ansi2ColorLabel;
@property(nonatomic, readonly) NSTextField *ansi3ColorLabel;
@property(nonatomic, readonly) NSTextField *ansi4ColorLabel;
@property(nonatomic, readonly) NSTextField *ansi5ColorLabel;
@property(nonatomic, readonly) NSTextField *ansi6ColorLabel;
@property(nonatomic, readonly) NSTextField *ansi7ColorLabel;
@property(nonatomic, readonly) NSView *hueVisualization;
@property(nonatomic, readonly) NSSlider *minimumContrast;
@property(nonatomic, readonly) NSTextField *minimumContrastLabel;
@property(nonatomic, readonly) NSView *bwWarning1;
@property(nonatomic, readonly) NSView *bwWarning2;
@property(nonatomic, readonly) NSSlider *faintTextAlpha;
@property(nonatomic, readonly) NSTextField *faintTextAlphaLabel;
@property(nonatomic, readonly) NSSlider *cursorBoost;
@property(nonatomic, readonly) NSTextField *cursorBoostLabel;
@property(nonatomic, readonly) NSButton *harmonize256;
@property(nonatomic, readonly) NSButton *brightenBoldText;
@property(nonatomic, readonly) NSButton *useBrightBold;
@property(nonatomic, readonly) NSButton *useTabColor;
@property(nonatomic, readonly) NSView *tabColor;
@property(nonatomic, readonly) NSButton *useUnderlineColor;
@property(nonatomic, readonly) NSView *underlineColor;
@property(nonatomic, readonly) NSButton *useGuide;
@property(nonatomic, readonly) NSView *guideColor;
@property(nonatomic, readonly) NSButton *useSmartCursorColor;
@property(nonatomic, readonly) NSView *badgeColor;
@property(nonatomic, readonly) NSTextField *badgeColorLabel;
@property(nonatomic, readonly) NSButton *useActivePaneBorder;
@property(nonatomic, readonly) NSView *activePaneBorderColor;

@property(nonatomic, strong) IBOutlet NSTextField *modesSectionLabel;
@property(nonatomic, strong) IBOutlet NSTextField *presetsLabel;
@property(nonatomic, strong) IBOutlet NSTextField *defaultsForegroundHeader;
@property(nonatomic, strong) IBOutlet NSTextField *cursorBackgroundHeader;
@property(nonatomic, strong) IBOutlet NSTextField *selectionBackgroundHeader;
@property(nonatomic, strong) IBOutlet NSTextField *selectionForegroundHeader;
@property(nonatomic, strong) IBOutlet NSTextField *boldColorLabel;
@property(nonatomic, strong) IBOutlet NSTextField *ansiColorsSectionLabel;
@property(nonatomic, strong) IBOutlet NSTextField *ansiNormalHeader;
@property(nonatomic, strong) IBOutlet NSTextField *ansiBrightHeader;
@property(nonatomic, strong) IBOutlet NSTextField *faintTransparentLabel;
@property(nonatomic, strong) IBOutlet NSTextField *faintOpaqueLabel;
@property(nonatomic, strong) IBOutlet NSTextField *tabColorLabel;
@property(nonatomic, strong) IBOutlet NSTextField *underlineColorLabel;
@property(nonatomic, strong) IBOutlet NSTextField *cursorGuideLabel;
@property(nonatomic, strong) IBOutlet NSTextField *paneColorLabel;

+ (NSString *)nameOfPresetUsedByProfile:(Profile *)profile;
@end
