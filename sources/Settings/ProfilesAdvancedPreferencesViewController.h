//
//  ProfilesAdvancedPreferencesViewController.h
//  iTerm
//
//  Created by George Nachman on 4/19/14.
//
//

#import "iTermProfilePreferencesBaseViewController.h"

@class iTermSemanticHistoryPrefsController;

@interface ProfilesAdvancedPreferencesViewController : iTermProfilePreferencesBaseViewController

@property(nonatomic, readonly) NSButton *triggersButton;
@property(nonatomic, readonly) NSView *triggersHelp;
@property(nonatomic, readonly) NSButton *enableTriggersInInteractiveApps;
@property(nonatomic, readonly) NSButton *smartSelectionButton;
@property(nonatomic, readonly) NSControl *boundHostLabel;
@property(nonatomic, readonly) NSControl *boundHostHelp;
@property(nonatomic, readonly) NSTableView *boundHostsTableView;
@property(nonatomic, readonly) NSControl *addBoundHost;
@property(nonatomic, readonly) NSControl *removeBoundHost;
@property(nonatomic, readonly) NSControl *boundHostShellIntegrationWarning;
@property(nonatomic, readonly) NSButton *enableAPSLogging;
@property(nonatomic, readonly) NSTextField *snippetsFilterLabel;
@property(nonatomic, readonly) NSTokenField *snippetsFilter;
@property(nonatomic, readonly) iTermSemanticHistoryPrefsController *semanticHistoryPrefController;
@property(nonatomic, readonly) NSTextField *disabledTip;

@property(nonatomic, strong) IBOutlet NSTextField *triggersLabel;
@property(nonatomic, strong) IBOutlet NSTextField *smartSelectionLabel;
@property(nonatomic, strong) IBOutlet NSView *smartSelectionHelp;
@property(nonatomic, strong) IBOutlet NSView *snippetsFilterHelp;
@property(nonatomic, strong) IBOutlet NSTextField *semanticHistoryLabel;
@property(nonatomic, strong) IBOutlet NSView *semanticHistoryHelp;

- (void)layoutSubviewsForEditCurrentSessionMode;
@end
