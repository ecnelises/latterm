//
//  ProfilesTerminalPreferencesViewController.h
//  iTerm
//
//  Created by George Nachman on 4/17/14.
//
//

#import "iTermProfilePreferencesBaseViewController.h"

@interface ProfilesTerminalPreferencesViewController : iTermProfilePreferencesBaseViewController

@property(nonatomic, readonly) NSTextField *numScrollbackLines;
@property(nonatomic, readonly) NSTextField *numScrollbackLinesLabel;
@property(nonatomic, readonly) NSButton *unlimitedScrollback;
@property(nonatomic, readonly) NSButton *scrollbackWithStatusBar;
@property(nonatomic, readonly) NSButton *scrollbackInAlternateScreen;
@property(nonatomic, readonly) NSButton *dragToScrollInAlternateScreenModeDisabled;
@property(nonatomic, readonly) NSPopUpButton *characterEncoding;
@property(nonatomic, readonly) NSTextField *characterEncodingLabel;
@property(nonatomic, readonly) NSComboBox *terminalType;
@property(nonatomic, readonly) NSTextField *terminalTypeLabel;
@property(nonatomic, readonly) NSTextField *answerBackString;
@property(nonatomic, readonly) NSTextField *answerBackStringLabel;
@property(nonatomic, readonly) NSButton *xtermMouseReporting;
@property(nonatomic, readonly) NSButton *xtermMouseReportingAllowMouseWheel;
@property(nonatomic, readonly) NSButton *xtermMouseReportingAllowClicksAndDrags;
@property(nonatomic, readonly) NSButton *allowAlternateMouseScroll;
@property(nonatomic, readonly) NSButton *automaticallyEnableAlternatemouseScroll;
@property(nonatomic, readonly) NSButton *restrictAlternateMouseScrollToVertical;
@property(nonatomic, readonly) NSButton *restrictMouseReportingToAlternateScreenMode;
@property(nonatomic, readonly) NSButton *allowTitleReporting;
@property(nonatomic, readonly) NSButton *allowCursorBlinkControlSequence;
@property(nonatomic, readonly) NSButton *disablePrinting;
@property(nonatomic, readonly) NSButton *disableAltScreen;
@property(nonatomic, readonly) NSButton *disableWindowResizing;
@property(nonatomic, readonly) NSButton *disableUnfocusedWindowResizing;
@property(nonatomic, readonly) NSButton *allowPasteBracketing;
@property(nonatomic, readonly) NSButton *flashingBell;
@property(nonatomic, readonly) NSButton *bellIconInTabs;
@property(nonatomic, readonly) NSButton *silenceBell;
@property(nonatomic, readonly) NSButton *postNotifications;
@property(nonatomic, readonly) NSButton *filterAlertsButton;
@property(nonatomic, readonly) NSPopUpButton *localeVars;
@property(nonatomic, readonly) NSButton *changeLocale;
@property(nonatomic, readonly) NSTextField *localeName;
@property(nonatomic, readonly) NSButton *forceCommandPromptToFirstColumn;
@property(nonatomic, readonly) NSButton *promptPathClickOpensNavigator;
@property(nonatomic, readonly) NSButton *shellIntegrationRequiredButton;
@property(nonatomic, readonly) NSButton *tmuxNewline;

@property(nonatomic, strong) IBOutlet NSTextField *historySectionLabel;
@property(nonatomic, strong) IBOutlet NSTextField *emulationSectionLabel;
@property(nonatomic, strong) IBOutlet NSTextField *mouseReportingSectionLabel;
@property(nonatomic, strong) IBOutlet NSTextField *bellSectionLabel;
@property(nonatomic, strong) IBOutlet NSTextField *notificationsSectionLabel;
@property(nonatomic, strong) IBOutlet NSTextField *environmentSectionLabel;
@property(nonatomic, strong) IBOutlet NSTextField *terminalMetadataSectionLabel;
@property(nonatomic, strong) IBOutlet NSTextField *tmuxIntegrationSectionLabel;

- (void)layoutSubviewsForEditCurrentSessionMode;

// Rebuilds the locale name field's attributed string. Its colors are baked into
// an attributed string that NSTextField does not re-resolve on its own when the
// effective appearance changes, so this must be called when the pane becomes
// visible again (in case the appearance changed while it was hidden).
- (void)updateLocaleDescription;

@end
