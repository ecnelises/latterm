//
//  ProfilesGeneralPreferencesViewController.h
//  iTerm
//
//  Created by George Nachman on 4/11/14.
//
//

#import "iTermProfilePreferencesBaseViewController.h"

@protocol iTermSessionScope;
@class iTermVariableScope;
@class ProfileListView;

@protocol ProfilesGeneralPreferencesViewControllerDelegate <NSObject>

- (void)profilesGeneralPreferencesNameWillChange;

// This should be called only for "edit info" dialogs when the name field resigns first responder.
- (void)profilesGeneralPreferencesNameDidEndEditing;

- (void)profilesGeneralPreferencesNameDidChange;

- (void)profilesGeneralPreferencesSessionHotkeyDidChange;

- (iTermVariableScope<iTermSessionScope> *)profilesGeneralPreferencesScope;
- (IBAction)copyToProfile:(id)sender;
@end

@interface ProfilesGeneralPreferencesViewController : iTermProfilePreferencesBaseViewController

@property(nonatomic, weak) IBOutlet id<ProfilesGeneralPreferencesViewControllerDelegate> profileDelegate;
@property(nonatomic, readonly) NSTextField *profileNameField;
@property(nonatomic, readonly) NSTextField *profileNameFieldForEditCurrentSession;
@property(nonatomic, readonly) NSString *selectedGuid;

@property(nonatomic, readonly) NSTextField *profileNameFieldLabel;
@property(nonatomic, readonly) NSTextField *shortcutLabel;
@property(nonatomic, readonly) NSPopUpButton *profileShortcut;
@property(nonatomic, readonly) NSTextField *tagsLabel;
@property(nonatomic, readonly) NSTokenField *tagsTokenField;
@property(nonatomic, readonly) NSTextField *subtitleLabel;
@property(nonatomic, readonly) NSTextField *subtitleText;
@property(nonatomic, readonly) NSView *tallTabBarRequestView;
@property(nonatomic, readonly) NSTextField *iconLabel;
@property(nonatomic, readonly) NSPopUpButton *icon;
@property(nonatomic, readonly) NSImageView *imageWell;
@property(nonatomic, readonly) NSTextField *badgeLabel;
@property(nonatomic, readonly) NSTextField *badgeText;
@property(nonatomic, readonly) NSButton *editBadgeButton;
@property(nonatomic, readonly) NSTextField *titleSettingsLabel;
@property(nonatomic, readonly) NSPopUpButton *titleSettings;
@property(nonatomic, readonly) NSButton *customTitleHelp;
@property(nonatomic, readonly) NSButton *allowTitleSetting;
@property(nonatomic, readonly) NSTextField *commandLabel;
@property(nonatomic, readonly) NSPopUpButton *commandType;
@property(nonatomic, readonly) NSTextField *customCommand;
@property(nonatomic, readonly) NSButton *configureSSHButton;
@property(nonatomic, readonly) NSButton *runCommandInLoginShell;
@property(nonatomic, readonly) NSImageView *commandWarningImageView;
@property(nonatomic, readonly) NSTextField *sendTextAtStartLabel;
@property(nonatomic, readonly) NSTextField *sendTextAtStart;
@property(nonatomic, readonly) NSTextField *directoryLabel;
@property(nonatomic, readonly) NSMatrix *initialDirectoryType;
@property(nonatomic, readonly) NSTextField *customDirectory;
@property(nonatomic, readonly) NSButton *editAdvancedConfigButton;
@property(nonatomic, readonly) NSTextField *schemesLabel;
@property(nonatomic, readonly) NSPopUpButton *urlSchemes;

@property(nonatomic, readonly) NSView *editCurrentSessionView;
@property(nonatomic, readonly) NSButton *locked;
@property(nonatomic, readonly) NSTextField *badgeTextForEditCurrentSession;
@property(nonatomic, readonly) NSPopUpButton *titleSettingsForEditCurrentSession;
@property(nonatomic, readonly) NSTextField *tabTitle;
@property(nonatomic, readonly) NSTextField *windowTitle;
@property(nonatomic, readonly) ProfileListView *profiles;
@property(nonatomic, readonly) NSButton *copySettingsToProfile;
@property(nonatomic, readonly) NSButton *copyProfileToSession;
@property(nonatomic, readonly) NSView *sessionHotkeyInputView;
@property(nonatomic, readonly) NSButton *preventAutomaticProfileSwitching;
@property(nonatomic, strong) IBOutlet NSTextField *editSessionNameLabel;
@property(nonatomic, strong) IBOutlet NSTextField *editSessionBadgeLabel;
@property(nonatomic, strong) IBOutlet NSTextField *editSessionTitleLabel;
@property(nonatomic, strong) IBOutlet NSTextField *editSessionTabTitleLabel;
@property(nonatomic, strong) IBOutlet NSTextField *editSessionWindowTitleLabel;
@property(nonatomic, strong) IBOutlet NSTextField *editSessionHotkeyLabel;

- (void)organizeSettingsForm;
- (void)layoutSubviewsForEditCurrentSessionMode;
- (void)updateShortcutTitles;
- (void)windowWillClose;

@end
