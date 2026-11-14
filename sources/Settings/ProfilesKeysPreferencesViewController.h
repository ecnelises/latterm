//
//  ProfilesKeysPreferencesViewController.h
//  iTerm
//
//  Created by George Nachman on 4/19/14.
//
//

#import "iTermProfilePreferencesBaseViewController.h"

@class iTermKeyMappingViewController;

@interface ProfilesKeysPreferencesViewController : iTermProfilePreferencesBaseViewController

@property(nonatomic, readonly) NSTextField *optionKeySendsLabel;
@property(nonatomic, readonly) NSPopUpButton *leftOptionKeyButton;
@property(nonatomic, readonly) NSButton *leftOptionKeyChangeable;
@property(nonatomic, readonly) NSTextField *rightOptionKeySendsLabel;
@property(nonatomic, readonly) NSPopUpButton *rightOptionKeyButton;
@property(nonatomic, readonly) NSButton *rightOptionKeyChangeable;
@property(nonatomic, readonly) NSTextField *leftControlLabel;
@property(nonatomic, readonly) NSButton *leftControlButton;
@property(nonatomic, readonly) NSTextField *rightControlLabel;
@property(nonatomic, readonly) NSButton *rightControlButton;
@property(nonatomic, readonly) NSTextField *leftCommandLabel;
@property(nonatomic, readonly) NSButton *leftCommandButton;
@property(nonatomic, readonly) NSTextField *rightCommandLabel;
@property(nonatomic, readonly) NSButton *rightCommandButton;
@property(nonatomic, readonly) NSTextField *functionLabel;
@property(nonatomic, readonly) NSButton *functionButton;
@property(nonatomic, readonly) NSButton *applicationKeypadAllowed;
@property(nonatomic, readonly) NSButton *useLibTickit;
@property(nonatomic, readonly) NSButton *allowModifyOtherKeys;
@property(nonatomic, readonly) NSButton *movementKeysScrollOutsideInteractiveApps;
@property(nonatomic, readonly) NSButton *treatOptionAsAlt;
@property(nonatomic, readonly) NSView *hotKeyContainerView;
@property(nonatomic, readonly) NSButton *hasHotkey;
@property(nonatomic, readonly) NSButton *configureHotKey;
@property(nonatomic, readonly) NSButton *deleteSendsCtrlHButton;
@property(nonatomic, readonly) NSButton *repairKeyMappingsButton;
@property(nonatomic, readonly) iTermKeyMappingViewController *keyMappingViewController;

@property(nonatomic, strong) IBOutlet NSTextField *keyReportingLabel;
@property(nonatomic, strong) IBOutlet NSButton *csiuHelpButton;
@property(nonatomic, strong) IBOutlet NSView *controlRemapHelpButton;
@property(nonatomic, strong) IBOutlet NSTextField *keyBehaviorLabel;
@property(nonatomic, strong) IBOutlet NSButton *optionAsMetaHelpButton;
@property(nonatomic, strong) IBOutlet NSTextField *hotkeyWindowLabel;

- (void)layoutSubviewsForEditCurrentSessionMode;
- (IBAction)openHotKeyPanel:(id)sender;

@end
