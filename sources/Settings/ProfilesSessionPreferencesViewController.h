//
//  ProfilesSessionViewController.h
//  iTerm
//
//  Created by George Nachman on 4/18/14.
//
//

#import "iTermProfilePreferencesBaseViewController.h"

@interface ProfilesSessionPreferencesViewController : iTermProfilePreferencesBaseViewController

@property(nonatomic, readonly) NSPopUpButton *promptBeforeClosing;
@property(nonatomic, readonly) NSButton *warnAboutShortLivedSessions;
@property(nonatomic, readonly) NSTextField *undoTimeout;
@property(nonatomic, readonly) NSPopUpButton *onEndAction;
@property(nonatomic, readonly) NSTableView *jobsTable;
@property(nonatomic, readonly) NSButton *addJob;
@property(nonatomic, readonly) NSButton *removeJob;
@property(nonatomic, readonly) NSButton *autoLog;
@property(nonatomic, readonly) NSPopUpButton *loggingStyle;
@property(nonatomic, readonly) NSTextField *logDir;
@property(nonatomic, readonly) NSImageView *logDirWarning;
@property(nonatomic, readonly) NSButton *changeLogDir;
@property(nonatomic, readonly) NSTextField *logFilenameFormat;
@property(nonatomic, readonly) NSButton *archive;
@property(nonatomic, readonly) NSTextField *archiveDir;
@property(nonatomic, readonly) NSImageView *archiveDirWarning;
@property(nonatomic, readonly) NSButton *changeArchiveDir;
@property(nonatomic, readonly) NSButton *timestampsEnabled;
@property(nonatomic, readonly) NSTextField *showTimestampsLabel;
@property(nonatomic, readonly) NSPopUpButton *showTimestampsPopup;
@property(nonatomic, readonly) NSButton *openPasswordManagerAutomatically;
@property(nonatomic, readonly) NSButton *statusBarEnabled;
@property(nonatomic, readonly) NSButton *configureStatusBar;
@property(nonatomic, readonly) NSButton *enableProgressBars;
@property(nonatomic, readonly) NSTextField *progressBarHeight;
@property(nonatomic, readonly) NSStepper *progressBarHeightStepper;
@property(nonatomic, readonly) NSPopUpButton *progressBarColorScheme;
@property(nonatomic, readonly) NSButton *sendCodeWhenIdle;
@property(nonatomic, readonly) NSTextField *idleCode;
@property(nonatomic, readonly) NSTextField *idlePeriod;
@property(nonatomic, readonly) NSButton *reduceFlicker;
@property(nonatomic, readonly) NSButton *defaultPaneLocked;
@property(nonatomic, readonly) NSButton *bufferByDefault;
@property(nonatomic, readonly) NSTextField *bufferWarning;

@property(nonatomic, strong) IBOutlet NSTextField *closingSectionLabel;
@property(nonatomic, strong) IBOutlet NSTextField *promptBeforeClosingLabel;
@property(nonatomic, strong) IBOutlet NSTextField *undoRevivePrefixLabel;
@property(nonatomic, strong) IBOutlet NSTextField *undoSecondsLabel;
@property(nonatomic, strong) IBOutlet NSTextField *afterSessionEndsLabel;
@property(nonatomic, strong) IBOutlet NSTextField *loggingSectionLabel;
@property(nonatomic, strong) IBOutlet NSTextField *logFormatLabel;
@property(nonatomic, strong) IBOutlet NSTextField *logFolderLabel;
@property(nonatomic, strong) IBOutlet NSTextField *logFilenameLabel;
@property(nonatomic, strong) IBOutlet NSTextField *archivingSectionLabel;
@property(nonatomic, strong) IBOutlet NSView *archivingHelpButton;
@property(nonatomic, strong) IBOutlet NSTextField *archiveFolderLabel;
@property(nonatomic, strong) IBOutlet NSTextField *passwordManagerLabel;
@property(nonatomic, strong) IBOutlet NSTextField *statusBarSectionLabel;
@property(nonatomic, strong) IBOutlet NSTextField *progressBarsSectionLabel;
@property(nonatomic, strong) IBOutlet NSTextField *progressBarHeightLabel;
@property(nonatomic, strong) IBOutlet NSTextField *progressBarColorSchemeLabel;
@property(nonatomic, strong) IBOutlet NSTextField *miscSectionLabel;
@property(nonatomic, strong) IBOutlet NSTextField *idleEveryLabel;
@property(nonatomic, strong) IBOutlet NSTextField *idleSecondsLabel;
@property(nonatomic, strong) IBOutlet NSView *bufferHelpButton;

- (void)layoutSubviewsForEditCurrentSessionMode;
- (void)configureStatusBarComponentWithIdentifier:(NSString *)identifier;

@end
