//
//  GeneralPreferencesViewController.m
//  iTerm
//
//  Created by George Nachman on 4/6/14.
//
//

#import "GeneralPreferencesViewController.h"
#import "SFSymbolEnum/SFSymbolEnum.h"
#import "NSImage+iTerm.h"
#import "NSTextField+iTerm.h"
#import "NSWorkspace+iTerm.h"
#import "PasteboardHistory.h"
#import "RegexKitLite.h"
#import "WindowArrangements.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermAPIHelper.h"
#import "iTermAdvancedGPUSettingsViewController.h"
#import "iTermApplicationDelegate.h"
#import "iTermBuriedSessions.h"
#import "iTermHotKeyController.h"
#import "iTermNotificationCenter.h"
#import "iTermPreferenceDidChangeNotification.h"
#import "iTermRemotePreferences.h"
#import "iTermScriptsMenuController.h"
#import "iTermSizeRememberingView.h"
#import "iTermUserDefaults.h"
#import "iTermUserDefaultsObserver.h"
#import "iTermWarning.h"

enum {
    kUseSystemWindowRestorationSettingTag = 0,
    kOpenDefaultWindowArrangementTag = 1,
    kDontOpenAnyWindowsTag= 2
};

@implementation GeneralPreferencesViewController {
    BOOL _awoken;
    // open bookmarks when iterm starts
    IBOutlet NSButton *_openBookmark;
    IBOutlet NSButton *_advancedGPUPrefsButton;

    // Open saved window arrangement at startup
    IBOutlet NSPopUpButton *_openWindowsAtStartup;
    IBOutlet NSTextField *_openWindowsAtStartupLabel;
    IBOutlet NSButton *_alwaysOpenWindowAtStartup;
    IBOutlet NSTextField *_alwaysOpenLegend;
    IBOutlet NSButton *_restoreWindowsToSameSpaces;

    IBOutlet NSMenuItem *_openDefaultWindowArrangementItem;

    // Quit when all windows are closed
    IBOutlet NSButton *_quitWhenAllWindowsClosed;

    // Confirm closing multiple sessions
    IBOutlet id _confirmClosingMultipleSessions;

    // Warn when quitting
    IBOutlet id _promptOnQuit;
    IBOutlet NSButton *_evenIfThereAreNoWindows;

    // Instant replay memory usage.
    IBOutlet NSTextField *_irMemory;
    IBOutlet NSTextField *_irMemoryLabel;

    // Save copy paste history
    IBOutlet NSButton *_savePasteHistory;

    // Use GPU?
    IBOutlet NSButton *_gpuRendering;
    IBOutlet NSButton *_advancedGPU;
    iTermAdvancedGPUSettingsWindowController *_advancedGPUWindowController;

    IBOutlet NSButton *_maximizeThroughput;
    IBOutlet NSButton *_enableAPI;
    IBOutlet NSPopUpButton *_apiPermission;

    // Enable bonjour
    IBOutlet NSButton *_enableBonjour;

    // Load prefs from custom folder
    IBOutlet NSButton *_loadPrefsFromCustomFolder;  // Should load?
    IBOutlet NSTextField *_prefsCustomFolder;  // Path or URL text field
    IBOutlet NSImageView *_prefsDirWarning;  // Image shown when path is not writable
    IBOutlet NSButton *_browseCustomFolder;  // Push button to open file browser
    IBOutlet NSButton *_pushToCustomFolder;  // Push button to copy local to remote
    IBOutlet NSPopUpButton *_saveChanges;  // Save settings to folder when
    IBOutlet NSTextField *_saveChangesLabel;

    IBOutlet NSButton *_useCustomScriptsFolder;
    IBOutlet NSTextField *_customScriptsFolder;
    IBOutlet NSImageView *_customScriptsFolderWarning;
    IBOutlet NSButton *_browseCustomScriptsFolder;

    // Copy to clipboard on selection
    IBOutlet NSButton *_selectionCopiesText;

    // Copy includes trailing newline
    IBOutlet NSButton *_copyLastNewline;

    // Triple click selects full, wrapped lines.
    IBOutlet NSButton *_tripleClickSelectsFullLines;

    // Double click perform smart selection
    IBOutlet NSButton *_doubleClickPerformsSmartSelection;

    // Allow clipboard access by terminal applications
    IBOutlet NSButton *_allowClipboardAccessFromTerminal;

    // Characters considered part of word
    IBOutlet NSTextField *_wordChars;
    IBOutlet NSTextField *_wordCharsRegex;
    IBOutlet NSTextField *_wordCharsLabel;
    IBOutlet NSPopUpButton *_wordMode;

    // Smart window placement
    IBOutlet NSButton *_smartPlacement;
    IBOutlet NSButton *_useAutoSaveFrames;
    IBOutlet NSButton *_rememberPositionOnly;
    IBOutlet NSButton *_defaultPositioning;
    IBOutlet NSView *_placementContainer;

    // Adjust window size when changing font size
    IBOutlet NSButton *_adjustWindowForFontSizeChange;

    // Zoom vertically only
    IBOutlet NSButton *_maxVertically;

    IBOutlet NSButton *_separateWindowTitlePerTab;

    // Lion-style fullscreen
    IBOutlet NSButton *_lionStyleFullscreen;

    // Open tmux windows in [windows, tabs]
    IBOutlet NSButton *_openTmuxWindowsAsTabsInAttachingWindow;
    IBOutlet NSTextField *_whenAttachingTmuxLabel;
    IBOutlet NSPopUpButton *_openUnrecognizedTmuxWindowsIn;

    // Hide the tmux client session
    IBOutlet NSButton *_autoHideTmuxClientSession;
    
    IBOutlet NSButton *_useTmuxProfile;
    IBOutlet NSButton *_useTmuxStatusBar;

    IBOutlet NSTextField *_tmuxPauseModeAgeLimit;
    IBOutlet NSButton *_unpauseTmuxAutomatically;
    IBOutlet NSButton *_tmuxWarnBeforePausing;

    IBOutlet NSButton *_syncTmuxClipboard;

    IBOutlet NSTabView *_tabView;
    NSTabViewItem *_startupClosingTab;

    IBOutlet NSButton *_enterCopyModeAutomatically;
    IBOutlet NSButton *_warningButton;
    iTermUserDefaultsObserver *_observer;

    IBOutlet NSButton *_wrapDroppedFilenamesInQuotesWhenPasting;

    IBOutlet NSPopUpButton *_allowsSendingClipboardContents;
    IBOutlet NSTextField *_allowsSendingClipboardContentsLabel;

    IBOutlet NSButton *_disableConfirmationOnShutdown;

    BOOL _customScriptsFolderDidChange;

    IBOutlet NSButton *_enableRTL;
    IBOutlet NSButton *_sshIntegrationForURLs;
    NSButton *_pythonAPIAuthHelpButton;
    NSButton *_wordCharsHelpButton;
    NSButton *_exportAllButton;
    NSButton *_importAllButton;
    NSButton *_eraseAllButton;
}

- (instancetype)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(savedArrangementChanged:)
                                                     name:kSavedArrangementDidChangeNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(didRevertPythonAuthenticationMethod:)
                                                     name:iTermAPIHelperDidDetectChangeOfPythonAuthMethodNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(updateAlwaysOpenLegend)
                                                     name:iTermSessionBuriedStateChangeTabNotification
                                                   object:nil];
        _observer = [[iTermUserDefaultsObserver alloc] init];
        __weak __typeof(self) weakSelf = self;
        [_observer observeKey:@"NSQuitAlwaysKeepsWindows" block:^{
            [weakSelf updateEnabledState];
        }];

        static iTermUserDefaultsObserver *gRemotePrefsObserver;
        gRemotePrefsObserver = [[iTermUserDefaultsObserver alloc] init];
        [gRemotePrefsObserver observeKey:kPreferenceKeyCustomFolder block:^{
            DLog(@"Remote prefs changed from\n%@", [NSThread callStackSymbols]);
        }];
        [gRemotePrefsObserver observeKey:kPreferenceKeyLoadPrefsFromCustomFolder block:^{
            [weakSelf loadPrefsFromCustomFolderDidChangeByUI:NO];
        }];
    }
    return self;
}

- (void)loadView {
    iTermSizeRememberingView *root = [[iTermSizeRememberingView alloc] initWithFrame:NSMakeRect(0, 0, 788, 556)];
    iTermSettingsTabView *tabs = [iTermSettingsControlFactory sectionTabViewWithFrame:NSMakeRect(0, 3, 775, 559)
                                                                                items:@[
        @[ @"1", @"Startup & Exit" ],
        @[ @"ToolsPerformance", @"Tools & Performance" ],
        @[ @"Selection", @"Selection" ],
        @[ @"Window", @"Window" ],
        @[ @"BackupSync", @"Backup & Sync" ],
        @[ @"tmux", @"tmux" ],
        @[ @"Experimental", @"Experimental" ]
    ]];
    tabs.delegate = self;

    SEL changed = @selector(settingChanged:);
    _openWindowsAtStartupLabel = [iTermSettingsControlFactory label:@"Window restoration policy:"];
    _openWindowsAtStartup = [iTermSettingsControlFactory popupButtonWithPullsDown:NO width:290 target:self action:changed items:@[
        @[ @"Use System Window Restoration Setting", @0 ],
        @[ @"Open Default Window Arrangement", @1 ],
        @[ @"Only Restore Hotkey Window", @2 ]
    ]];
    _openDefaultWindowArrangementItem = [_openWindowsAtStartup.menu itemWithTag:kOpenDefaultWindowArrangementTag];
    _warningButton = [iTermSettingsControlFactory warningButtonWithTarget:self action:@selector(warning:)];
    _openBookmark = [iTermSettingsControlFactory checkbox:@"Open profiles window" target:self action:changed toolTip:nil];
    _restoreWindowsToSameSpaces = [iTermSettingsControlFactory checkbox:@"Restore windows to same Spaces" target:self action:changed toolTip:nil];
    _alwaysOpenWindowAtStartup = [iTermSettingsControlFactory checkbox:@"Always open at least one terminal window at startup" target:self action:changed toolTip:nil];
    _alwaysOpenLegend = [iTermSettingsControlFactory wrappingLabel:@"" smallSecondary:YES];

    _quitWhenAllWindowsClosed = [iTermSettingsControlFactory checkbox:@"Quit when all windows are closed" target:self action:changed toolTip:nil];
    _confirmClosingMultipleSessions = [iTermSettingsControlFactory checkbox:@"Confirm closing multiple sessions" target:self action:changed toolTip:nil];
    _promptOnQuit = [iTermSettingsControlFactory checkbox:@"Confirm “Quit Latterm (⌘Q)”" target:self action:changed toolTip:nil];
    _evenIfThereAreNoWindows = [iTermSettingsControlFactory checkbox:@"Even if there are no windows" target:self action:changed toolTip:nil];
    _disableConfirmationOnShutdown = [iTermSettingsControlFactory checkbox:@"Disable all confirmations on system shutdown, restart, and log out" target:self action:changed toolTip:nil];

    _irMemoryLabel = [iTermSettingsControlFactory label:@"Instant Replay uses "];
    _irMemory = [iTermSettingsControlFactory textFieldWithPlaceholder:nil width:56 target:self action:changed delegate:self];
    _savePasteHistory = [iTermSettingsControlFactory checkbox:@"Save copy/paste history to disk" target:self action:changed toolTip:nil];
    _gpuRendering = [iTermSettingsControlFactory checkbox:@"GPU rendering"
                                                   target:self
                                                   action:changed
                                                  toolTip:@"When enabled, terminals are rendered using the GPU. This improves performance."];
    _advancedGPU = [iTermSettingsControlFactory pushButton:@"Advanced GPU Settings…" target:self action:@selector(advancedGPU:)];
    _advancedGPUPrefsButton = _advancedGPU;
    _maximizeThroughput = [iTermSettingsControlFactory checkbox:@"Maximize throughput at the cost of higher latency" target:self action:changed toolTip:nil];
    _enableAPI = [iTermSettingsControlFactory checkbox:@"Enable Python API" target:self action:changed toolTip:nil];
    _apiPermission = [iTermSettingsControlFactory popupButtonWithPullsDown:NO width:260 target:self action:changed items:@[
        @[ @"Require “Automation” permission", @0 ],
        @[ @"Allow all apps to connect", @1 ]
    ]];
    _pythonAPIAuthHelpButton = [iTermSettingsControlFactory helpButtonWithTarget:self action:@selector(pythonAPIAuthHelp:)];
    _useCustomScriptsFolder = [iTermSettingsControlFactory checkbox:@"Custom Python API Scripts Folder" target:self action:changed toolTip:nil];
    _customScriptsFolder = [iTermSettingsControlFactory textFieldWithPlaceholder:nil width:233 target:nil action:nil delegate:self];
    _customScriptsFolderWarning = [iTermSettingsControlFactory statusImageView];
    _browseCustomScriptsFolder = [iTermSettingsControlFactory pushButton:@"Browse" target:self action:@selector(browseScriptsFolder:)];
    _enableBonjour = [iTermSettingsControlFactory checkbox:@"Add Bonjour hosts to Profiles" target:self action:changed toolTip:nil];

    _selectionCopiesText = [iTermSettingsControlFactory checkbox:@"Copy to clipboard on selection" target:self action:changed toolTip:nil];
    _copyLastNewline = [iTermSettingsControlFactory checkbox:@"Copied text includes trailing newline" target:self action:changed toolTip:nil];
    _allowClipboardAccessFromTerminal = [iTermSettingsControlFactory checkbox:@"Applications in terminal may access clipboard"
                                                                       target:self
                                                                       action:changed
                                                                      toolTip:@"Clipboard access via an escape code poses a security risk if running untrusted applications."];
    _allowsSendingClipboardContentsLabel = [iTermSettingsControlFactory label:@"Allow sending of clipboard contents?"];
    _allowsSendingClipboardContents = [iTermSettingsControlFactory popupButtonWithPullsDown:NO width:140 target:self action:changed items:@[
        @[ @"Ask Each Time", @2 ],
        @[ @"Never", @0 ],
        @[ @"Always", @1 ]
    ]];
    _wordCharsLabel = [iTermSettingsControlFactory label:@"Characters considered part of a word"];
    _wordCharsHelpButton = [iTermSettingsControlFactory popoverHelpButton:@"When you double-click in the terminal, a single word is selected. When your click is on a letter, the word boundary is found by grouping letters adjacent to the click location. You can extend the set of characters that are treated as belonging to a word with this setting.\n\nFor example, if `/` is considered part of a word, then double clicking on a path would select all the path components.\n\nYou can choose to define the characters considered part of a word with a regular expression. Then you can add specific substrings, such as `https://`, if you would prefer double-clicks on URLs to include the scheme. Generally the regular expression you provide will be a sequence of alternates separated by `|`."];
    _wordMode = [iTermSettingsControlFactory popupButtonWithPullsDown:NO width:170 target:self action:changed items:@[
        @[ @"List of Characters", @0 ],
        @[ @"Regular Expression", @1 ]
    ]];
    _wordChars = [iTermSettingsControlFactory textFieldWithPlaceholder:nil width:245 target:self action:changed delegate:self];
    _wordCharsRegex = [iTermSettingsControlFactory textFieldWithPlaceholder:nil width:245 target:self action:changed delegate:self];
    _tripleClickSelectsFullLines = [iTermSettingsControlFactory checkbox:@"Triple-click selects entire wrapped lines"
                                                                  target:self
                                                                  action:changed
                                                                 toolTip:@"If disabled, then triple click selects one line as it appears onscreen."];
    _doubleClickPerformsSmartSelection = [iTermSettingsControlFactory checkbox:@"Double-click performs smart selection" target:self action:changed toolTip:nil];
    _enterCopyModeAutomatically = [iTermSettingsControlFactory checkbox:@"Automatically enter copy mode on Shift+Arrow key with selection"
                                                                 target:self
                                                                 action:changed
                                                                toolTip:@"When this is enabled, shift+arrow key will extend an existing selection. If there is no selection, this has no effect."];
    _wrapDroppedFilenamesInQuotesWhenPasting = [iTermSettingsControlFactory checkbox:@"When pasting a dropped filename, wrap it in double quotes" target:self action:changed toolTip:nil];

    _placementContainer = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 519, 96)];
    _rememberPositionOnly = [iTermSettingsControlFactory radioButton:@"Remember the position of previously closed windows and use size from profile" tag:3 target:self action:changed toolTip:nil];
    _defaultPositioning = [iTermSettingsControlFactory radioButton:@"Let macOS decide the position of new windows and use size from profile" tag:0 target:self action:changed toolTip:nil];
    _useAutoSaveFrames = [iTermSettingsControlFactory radioButton:@"Remember the size and position of previously closed windows" tag:2 target:self action:changed toolTip:nil];
    _smartPlacement = [iTermSettingsControlFactory radioButton:@"Smart Window Placement"
                                                           tag:1
                                                        target:self
                                                        action:changed
                                                       toolTip:@"Smart window placement puts new windows where the most free space is available."];
    [_placementContainer addSubview:_rememberPositionOnly];
    [_placementContainer addSubview:_defaultPositioning];
    [_placementContainer addSubview:_useAutoSaveFrames];
    [_placementContainer addSubview:_smartPlacement];

    _adjustWindowForFontSizeChange = [iTermSettingsControlFactory checkbox:@"Adjust window when changing font size"
                                                                    target:self
                                                                    action:changed
                                                                   toolTip:@"If enabled, changes to font size will try to preserve session dimensions."];
    _adjustWindowForFontSizeChange.identifier = @"adjustWindowForFontSizeChange";
    _maxVertically = [iTermSettingsControlFactory checkbox:@"Zoom maximizes vertically only"
                                                    target:self
                                                    action:changed
                                                   toolTip:@"“Zoom” is the green button."];
    _lionStyleFullscreen = [iTermSettingsControlFactory checkbox:@"Native full screen windows" target:self action:changed toolTip:nil];
    _separateWindowTitlePerTab = [iTermSettingsControlFactory checkbox:@"Each tab may have its own window title" target:self action:changed toolTip:nil];

    _loadPrefsFromCustomFolder = [iTermSettingsControlFactory checkbox:@"Load settings from a custom folder or URL" target:self action:changed toolTip:nil];
    _prefsCustomFolder = [iTermSettingsControlFactory textFieldWithPlaceholder:@"Enter path to folder with settings" width:360 target:nil action:nil delegate:self];
    _prefsDirWarning = [iTermSettingsControlFactory statusImageView];
    _browseCustomFolder = [iTermSettingsControlFactory pushButton:@"Browse" target:self action:@selector(browseCustomFolder:)];
    _saveChangesLabel = [iTermSettingsControlFactory label:@"Save changes"];
    _saveChanges = [iTermSettingsControlFactory popupButtonWithPullsDown:NO width:220 target:self action:changed items:@[
        @[ @"Automatically", @2 ],
        @[ @"Manually", @1 ],
        @[ @"When Quitting", @0 ]
    ]];
    _pushToCustomFolder = [iTermSettingsControlFactory pushButton:@"Save Now" target:self action:@selector(pushToCustomFolder:)];
    _exportAllButton = [iTermSettingsControlFactory pushButton:@"Export All Settings and Data…" target:self action:@selector(exportAllSettingsAndData:)];
    _importAllButton = [iTermSettingsControlFactory pushButton:@"Import All Settings and Data…" target:self action:@selector(importAllSettingsAndData:)];
    _eraseAllButton = [iTermSettingsControlFactory pushButton:@"Erase All Settings and Data…" target:self action:@selector(eraseAllSettingsAndData:)];

    _openTmuxWindowsAsTabsInAttachingWindow = [iTermSettingsControlFactory checkbox:@"Open tmux windows as tabs in the attaching window" target:self action:changed toolTip:nil];
    _whenAttachingTmuxLabel = [iTermSettingsControlFactory label:@"When attaching, open unrecognized windows in"];
    _openUnrecognizedTmuxWindowsIn = [iTermSettingsControlFactory popupButtonWithPullsDown:NO width:180 target:self action:changed items:@[
        @[ @"Windows", @0 ],
        @[ @"Tabs in a new window", @1 ]
    ]];
    _autoHideTmuxClientSession = [iTermSettingsControlFactory checkbox:@"Automatically bury the tmux client session after connecting" target:self action:changed toolTip:nil];
    _useTmuxProfile = [iTermSettingsControlFactory checkbox:@"Use “tmux” profile rather than profile of the connecting session" target:self action:changed toolTip:nil];
    _useTmuxStatusBar = [iTermSettingsControlFactory checkbox:@"Status bar shows tmux status bar content, not native components" target:self action:changed toolTip:nil];
    _tmuxPauseModeAgeLimit = [iTermSettingsControlFactory textFieldWithPlaceholder:nil width:60 target:self action:changed delegate:self];
    _tmuxWarnBeforePausing = [iTermSettingsControlFactory checkbox:@"Warn before pausing" target:self action:changed toolTip:nil];
    _unpauseTmuxAutomatically = [iTermSettingsControlFactory checkbox:@"Unpause automatically" target:self action:changed toolTip:nil];
    _syncTmuxClipboard = [iTermSettingsControlFactory checkbox:@"Mirror tmux paste buffer to local clipboard" target:self action:changed toolTip:nil];

    _enableRTL = [iTermSettingsControlFactory checkbox:@"Enable support for right-to-left scripts" target:self action:changed toolTip:nil];
    _sshIntegrationForURLs = [iTermSettingsControlFactory checkbox:@"Use SSH integration for ssh: URLs" target:self action:changed toolTip:nil];

    [root addSubview:tabs];
    _tabView = tabs;
    self.view = root;
    [self awakeFromNib];
}

- (void)awakeFromNib {
    if (_awoken) {
        // View-based NSTableView lazily unarchives each NSTableCellView prototype
        // from an inline nib using File’s Owner as the nib owner, which causes a
        // second -awakeFromNib on this controller. Idempotency is required.
        return;
    }
    _awoken = YES;

    PreferenceInfo *info;

    __weak __typeof(self) weakSelf = self;
    [self defineControl:_openBookmark
                    key:kPreferenceKeyOpenBookmark
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    info = [self defineControl:_openWindowsAtStartup
                           key:kPreferenceKeyOpenArrangementAtStartup
                   relatedView:_openWindowsAtStartupLabel
                          type:kPreferenceInfoTypeCheckbox
                settingChanged:^(id sender) {
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        switch ([strongSelf->_openWindowsAtStartup selectedTag]) {
            case kUseSystemWindowRestorationSettingTag:
                [strongSelf setBool:NO forKey:kPreferenceKeyOpenArrangementAtStartup];
                [strongSelf setBool:NO forKey:kPreferenceKeyOpenNoWindowsAtStartup];
                break;

            case kOpenDefaultWindowArrangementTag:
                [strongSelf setBool:YES forKey:kPreferenceKeyOpenArrangementAtStartup];
                [strongSelf setBool:NO forKey:kPreferenceKeyOpenNoWindowsAtStartup];
                break;

            case kDontOpenAnyWindowsTag:
                [strongSelf setBool:NO forKey:kPreferenceKeyOpenArrangementAtStartup];
                [strongSelf setBool:YES forKey:kPreferenceKeyOpenNoWindowsAtStartup];
                break;
        }
        [strongSelf updateEnabledState];
    } update:^BOOL{
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return NO;
        }
        if ([strongSelf boolForKey:kPreferenceKeyOpenNoWindowsAtStartup]) {
            [strongSelf->_openWindowsAtStartup selectItemWithTag:kDontOpenAnyWindowsTag];
        } else if ([WindowArrangements count] &&
                   [self boolForKey:kPreferenceKeyOpenArrangementAtStartup]) {
            [strongSelf->_openWindowsAtStartup selectItemWithTag:kOpenDefaultWindowArrangementTag];
        } else {
            [strongSelf->_openWindowsAtStartup selectItemWithTag:kUseSystemWindowRestorationSettingTag];
        }
        [strongSelf updateEnabledState];
        return YES;
    }];
    info.hasDefaultValue = ^BOOL{
        return [weakSelf boolForKey:kPreferenceKeyOpenArrangementAtStartup] == NO && [weakSelf boolForKey:kPreferenceKeyOpenNoWindowsAtStartup] == NO;
    };
    [self updateNonDefaultIndicatorVisibleForInfo:info];

    [_openDefaultWindowArrangementItem setEnabled:[WindowArrangements count] > 0];

    [self defineControl:_restoreWindowsToSameSpaces
                    key:kPreferenceKeyRestoreWindowsToSameSpaces
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_alwaysOpenWindowAtStartup
                    key:kPreferenceKeyAlwaysOpenWindowAtStartup
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];
    [self updateAlwaysOpenLegend];

    [self defineControl:_quitWhenAllWindowsClosed
                    key:kPreferenceKeyQuitWhenAllWindowsClosed
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_confirmClosingMultipleSessions
                    key:kPreferenceKeyConfirmClosingMultipleTabs
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    info = [self defineControl:_promptOnQuit
                           key:kPreferenceKeyPromptOnQuit
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^{
        [weakSelf updateEnabledState];
    };

    [self defineControl:_disableConfirmationOnShutdown
                    key:kPreferenceKeyNeverBlockSystemShutdown
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_evenIfThereAreNoWindows
                    key:kPreferenceKeyPromptOnQuitEvenIfThereAreNoWindows
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    info = [self defineControl:_irMemory
                           key:kPreferenceKeyInstantReplayMemoryMegabytes
                   displayName:@"Instant Replay memory usage limit"
                          type:kPreferenceInfoTypeIntegerTextField];
    info.range = NSMakeRange(0, 1000);

    info = [self defineControl:_savePasteHistory
                           key:kPreferenceKeySavePasteHistory
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];

    info = [self defineControl:_gpuRendering
                           key:kPreferenceKeyUseMetal
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.observer = ^{
        [weakSelf updateAdvancedGPUEnabled];
    };

    info = [self defineControl:_enableAPI
                           key:kPreferenceKeyEnableAPIServer
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.customSettingChangedHandler = ^(id sender) {
        [weakSelf enableAPISettingDidChange];
    };
    [iTermPreferenceDidChangeNotification subscribe:self
                                              block:^(iTermPreferenceDidChangeNotification * _Nonnull notification) {
        if ([notification.key isEqualToString:kPreferenceKeyEnableAPIServer]) {
            __typeof(self) strongSelf = weakSelf;
            if (strongSelf) {
                strongSelf->_enableAPI.state = NSControlStateValueOn;
            }
        }
    }];

    info = [self defineControl:_apiPermission
                           key:kPreferenceKeyAPIAuthentication
                   displayName:@"Authentication method for Python API"
                          type:kPreferenceInfoTypePopup];
    info.syntheticGetter = ^id{
        return @([iTermAPIHelper requireApplescriptAuth] ? 0 : 1);
    };
    info.syntheticSetter = ^(NSNumber *newValue) {
        const BOOL useApplescript = (newValue.intValue == 0);
        [iTermAPIHelper setRequireApplescriptAuth:useApplescript
                                           window:self.view.window];
        [weakSelf updateAPIEnabledState];
    };
    info.shouldBeEnabled = ^BOOL{
        return [weakSelf boolForKey:kPreferenceKeyEnableAPIServer];
    };

    _advancedGPUWindowController = [[iTermAdvancedGPUSettingsWindowController alloc] initWithWindowNibName:@"iTermAdvancedGPUSettingsWindowController"];
    [_advancedGPUWindowController.window orderOut:nil];
    _advancedGPUWindowController.viewController.disableWhenDisconnected.target = self;
    _advancedGPUWindowController.viewController.disableWhenDisconnected.action = @selector(settingChanged:);
    info = [self defineUnsearchableControl:_advancedGPUWindowController.viewController.disableWhenDisconnected
                                       key:kPreferenceKeyDisableMetalWhenUnplugged
                                      type:kPreferenceInfoTypeCheckbox];
    info.observer = ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:iTermMetalSettingsDidChangeNotification object:nil];
    };

    _advancedGPUWindowController.viewController.disableInLowPowerMode.target = self;
    _advancedGPUWindowController.viewController.disableInLowPowerMode.action = @selector(settingChanged:);
    info = [self defineUnsearchableControl:_advancedGPUWindowController.viewController.disableInLowPowerMode
                                       key:kPreferenceKeyDisableInLowPowerMode
                                      type:kPreferenceInfoTypeCheckbox];
    info.observer = ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:iTermMetalSettingsDidChangeNotification object:nil];
    };

    _advancedGPUWindowController.viewController.preferIntegratedGPU.target = self;
    _advancedGPUWindowController.viewController.preferIntegratedGPU.action = @selector(settingChanged:);
    info = [self defineUnsearchableControl:_advancedGPUWindowController.viewController.preferIntegratedGPU
                                       key:kPreferenceKeyPreferIntegratedGPU
                                      type:kPreferenceInfoTypeCheckbox];
    info.observer = ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:iTermMetalSettingsDidChangeNotification object:nil];
    };
    info.onChange = ^{
        [iTermWarning showWarningWithTitle:@"You must restart Latterm for this change to take effect."
                                   actions:@[ @"OK" ]
                                identifier:nil
                               silenceable:kiTermWarningTypePersistent
                                    window:nil];
    };


    [self addViewToSearchIndex:_advancedGPUPrefsButton
                   displayName:@"Advanced GPU settings"
                       phrases:@[ _advancedGPUWindowController.viewController.disableWhenDisconnected.title,
                                  _advancedGPUWindowController.viewController.disableInLowPowerMode.title,
                                  _advancedGPUWindowController.viewController.preferIntegratedGPU.title ]
                           key:nil];

    info = [self defineControl:_maximizeThroughput
                           key:kPreferenceKeyMaximizeThroughput
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.observer = ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:iTermMetalSettingsDidChangeNotification object:nil];
    };

    [self defineControl:_enableBonjour
                    key:kPreferenceKeyAddBonjourHostsToProfiles
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    // ---------------------------------------------------------------------------------------------
    info = [self defineControl:_useCustomScriptsFolder
                           key:kPreferenceKeyUseCustomScriptsFolder
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() {
        [self useCustomScriptsFolderDidChange];
        [weakSelf customScriptsFolderDidChange];
        [weakSelf postCustomScriptsFolderDidChangeNotificationIfNeeded];
    };
    info.observer = ^() { [self updateCustomScriptsFolderViews]; };

    info = [self defineControl:_customScriptsFolder
                           key:kPreferenceKeyCustomScriptsFolder
                   displayName:@"Custom folder for Python API scripts"
                          type:kPreferenceInfoTypeStringTextField];
    info.shouldBeEnabled = ^BOOL() {
        return [iTermPreferences boolForKey:kPreferenceKeyUseCustomScriptsFolder];
    };
    info.onChange = ^() {
        [self updateCustomScriptsFolderViews];
        [weakSelf customScriptsFolderDidChange];
    };
    info.controlTextDidEndEditing = ^(NSNotification *notif) {
        // Post here instead of onChange since a patial path, like "/", would kick off a very slow
        // recursive search for scripts.
        [weakSelf postCustomScriptsFolderDidChangeNotificationIfNeeded];
    };
    [self updateCustomScriptsFolderViews];

    // ---------------------------------------------------------------------------------------------
    info = [self defineControl:_loadPrefsFromCustomFolder
                           key:kPreferenceKeyLoadPrefsFromCustomFolder
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() { [self loadPrefsFromCustomFolderDidChangeByUI:YES]; };
    info.observer = ^() { [self updateRemotePrefsViews]; };

    info = [self defineControl:_saveChanges
                           key:kPreferenceKeyNeverRemindPrefsChangesLostForFileSelection
                   relatedView:_saveChangesLabel
                          type:kPreferenceInfoTypePopup];
    // Called when user interacts with control
    info.customSettingChangedHandler = ^(id sender) {
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        [[iTermUserDefaults userDefaults] setBool:YES forKey:kPreferenceKeyNeverRemindPrefsChangesLostForFileHaveSelection];
        [[iTermUserDefaults userDefaults] setObject:@([strongSelf->_saveChanges selectedTag])
                                                  forKey:kPreferenceKeyNeverRemindPrefsChangesLostForFileSelection];
    };

    // Called on programmatic change (e.g., selecting a different profile. Returns YES to avoid
    // normal code path.
    info.onUpdate = ^BOOL () {
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return NO;
        }
        NSUserDefaults *userDefaults = [iTermUserDefaults userDefaults];
        NSUInteger tag = iTermPreferenceSavePrefsModeNever;
        if ([userDefaults boolForKey:kPreferenceKeyNeverRemindPrefsChangesLostForFileHaveSelection]) {
            tag = [userDefaults integerForKey:kPreferenceKeyNeverRemindPrefsChangesLostForFileSelection];
        }
        [strongSelf->_saveChanges selectItemWithTag:tag];
        return YES;
    };
    info.onUpdate();

    // ---------------------------------------------------------------------------------------------
    info = [self defineUnsearchableControl:_prefsCustomFolder
                                       key:kPreferenceKeyCustomFolder
                                      type:kPreferenceInfoTypeStringTextField];
    info.shouldBeEnabled = ^BOOL() {
        return [iTermPreferences boolForKey:kPreferenceKeyLoadPrefsFromCustomFolder];
    };
    info.onChange = ^() {
        DLog(@"prefsCustomFolder did change");
        [iTermRemotePreferences sharedInstance].customFolderChanged = YES;
        [self updateRemotePrefsViews];
    };
    [self updateRemotePrefsViews];

    // ---------------------------------------------------------------------------------------------
    [self defineControl:_selectionCopiesText
                    key:kPreferenceKeySelectionCopiesText
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_copyLastNewline
                    key:kPreferenceKeyCopyLastNewline
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_allowClipboardAccessFromTerminal
                    key:kPreferenceKeyAllowClipboardAccessFromTerminal
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    info = [self defineControl:_wordMode
                            key:kPreferenceKeyCharactersConsideredPartOfAWordForSelectionMode
                    relatedView:nil
                           type:kPreferenceInfoTypePopup];
    info.observer = ^{
        __strong __typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        BOOL isRegexMode = ([strongSelf unsignedIntegerForKey:kPreferenceKeyCharactersConsideredPartOfAWordForSelectionMode] == iTermSelectionWordModeRegularExpression);
        // Show/hide the appropriate text field based on mode
        strongSelf->_wordChars.hidden = isRegexMode;
        strongSelf->_wordCharsRegex.hidden = !isRegexMode;
        [strongSelf.view it_invalidateProfileFormLayout];
    };

    [self defineControl:_wordChars
                    key:kPreferenceKeyCharactersConsideredPartOfAWordForSelection
            relatedView:_wordCharsLabel
                   type:kPreferenceInfoTypeStringTextField];

    [self defineControl:_wordCharsRegex
                    key:kPreferenceKeyWordSelectionRegexPattern
            relatedView:_wordCharsLabel
                   type:kPreferenceInfoTypeStringTextField];

    // Set initial visibility based on current mode
    {
        BOOL isRegexMode = ([self unsignedIntegerForKey:kPreferenceKeyCharactersConsideredPartOfAWordForSelectionMode] == iTermSelectionWordModeRegularExpression);
        _wordChars.hidden = isRegexMode;
        _wordCharsRegex.hidden = !isRegexMode;
    }

    [self defineControl:_tripleClickSelectsFullLines
                    key:kPreferenceKeyTripleClickSelectsFullWrappedLines
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];
    info = [self defineControl:_doubleClickPerformsSmartSelection
                           key:kPreferenceKeyDoubleClickPerformsSmartSelection
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.observer = ^{
        __strong __typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        BOOL enabled = ![strongSelf boolForKey:kPreferenceKeyDoubleClickPerformsSmartSelection];
        strongSelf->_wordChars.enabled = enabled;
        strongSelf->_wordCharsRegex.enabled = enabled;
        strongSelf->_wordCharsLabel.labelEnabled = enabled;
        strongSelf->_wordMode.enabled = enabled;
    };
    [self defineControl:_enterCopyModeAutomatically
                    key:kPreferenceKeyEnterCopyModeAutomatically
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];
    [self defineControl:_wrapDroppedFilenamesInQuotesWhenPasting
                    key:kPreferenceKeyWrapDroppedFilenamesInQuotesWhenPasting
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    info = [self defineControl:_placementContainer
                           key:kPreferenceKeyWindowPlacement
                   displayName:@"New window placement"
                          type:kPreferenceInfoTypeRadioButton];

    [self defineControl:_adjustWindowForFontSizeChange
                    key:kPreferenceKeyAdjustWindowForFontSizeChange
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_maxVertically
                    key:kPreferenceKeyMaximizeVerticallyOnly
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_lionStyleFullscreen
                    key:kPreferenceKeyLionStyleFullscreen
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_separateWindowTitlePerTab
                    key:kPreferenceKeySeparateWindowTitlePerTab
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    info = [self defineControl:_openTmuxWindowsAsTabsInAttachingWindow
                           key:kPreferenceKeyOpenTmuxWindowsAsTabsInAttachingWindow
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.syntheticGetter = ^id{
        const iTermOpenTmuxWindowsMode mode = (iTermOpenTmuxWindowsMode)[iTermPreferences unsignedIntegerForKey:kPreferenceKeyOpenTmuxWindowsIn];
        return @(mode == kOpenTmuxWindowsAsNativeTabsInExistingWindow);
    };
    info.syntheticSetter = ^(id newValue) {
        __strong __typeof(self) strongSelf = weakSelf;
        if ([NSNumber castFrom:newValue].boolValue) {
            [iTermPreferences setUnsignedInteger:kOpenTmuxWindowsAsNativeTabsInExistingWindow
                                          forKey:kPreferenceKeyOpenTmuxWindowsIn];
        } else if (strongSelf) {
            [iTermPreferences setUnsignedInteger:strongSelf->_openUnrecognizedTmuxWindowsIn.selectedTag
                                          forKey:kPreferenceKeyOpenTmuxWindowsIn];
        }
    };
    info = [self defineControl:_openUnrecognizedTmuxWindowsIn
                           key:kPreferenceKeyOpenUnrecognizedTmuxWindowsIn
                   relatedView:_whenAttachingTmuxLabel
                          type:kPreferenceInfoTypePopup];
    info.syntheticGetter = ^id{
        const iTermOpenTmuxWindowsMode mode = (iTermOpenTmuxWindowsMode)[iTermPreferences unsignedIntegerForKey:kPreferenceKeyOpenTmuxWindowsIn];
        if (mode == kOpenTmuxWindowsAsNativeTabsInExistingWindow) {
            return @(kOpenTmuxWindowsAsNativeTabsInNewWindow);
        }
        return @(mode);
    };
    info.syntheticSetter = ^(id newValue) {
        [iTermPreferences setUnsignedInteger:[NSNumber castFrom:newValue].unsignedIntegerValue
                                      forKey:kPreferenceKeyOpenTmuxWindowsIn];
    };
    info.shouldBeEnabled = ^BOOL{
        const iTermOpenTmuxWindowsMode mode = (iTermOpenTmuxWindowsMode)[iTermPreferences unsignedIntegerForKey:kPreferenceKeyOpenTmuxWindowsIn];
        return (mode != kOpenTmuxWindowsAsNativeTabsInExistingWindow);
    };
    // Depend on the user defaults key, not the phony one, since it uses a User Defaults Observer to cause updates.
    [info addShouldBeEnabledDependencyOnSetting:kPreferenceKeyOpenTmuxWindowsIn
                                     controller:self];
    // This is how it was done before the great refactoring, but I don't see why it's needed.
    info.onChange = ^() { [weakSelf postRefreshNotification]; };
    [self updateEnabledStateForInfo:info];

    [self defineControl:_autoHideTmuxClientSession
                    key:kPreferenceKeyAutoHideTmuxClientSession
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];
    [self defineControl:_useTmuxProfile
                    key:kPreferenceKeyUseTmuxProfile
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];
    [self defineControl:_useTmuxStatusBar
                    key:kPreferenceKeyUseTmuxStatusBar
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_tmuxPauseModeAgeLimit
                    key:kPreferenceKeyTmuxPauseModeAgeLimit
            displayName:@"Pause a tmux pane if it would take more than this many seconds to catch up."
                   type:kPreferenceInfoTypeUnsignedIntegerTextField];
    [self defineControl:_unpauseTmuxAutomatically
                    key:kPreferenceKeyTmuxUnpauseAutomatically
            displayName:nil
                   type:kPreferenceInfoTypeCheckbox];
    [self defineControl:_tmuxWarnBeforePausing
                    key:kPreferenceKeyTmuxWarnBeforePausing
            displayName:nil
                   type:kPreferenceInfoTypeCheckbox];
    [self defineControl:_syncTmuxClipboard
                    key:kPreferenceKeyTmuxSyncClipboard
            displayName:nil
                   type:kPreferenceInfoTypeCheckbox];

    info = [self defineControl:_allowsSendingClipboardContents
                           key:kPreferenceKeyPhonyAllowSendingClipboardContents
                   relatedView:_allowsSendingClipboardContentsLabel
                          type:kPreferenceInfoTypePopup];
    info.syntheticGetter = ^id{
        return @([iTermPasteboardReporter configuration]);
    };
    info.syntheticSetter = ^(NSNumber *newValue) {
        [iTermPasteboardReporter setConfiguration:newValue.intValue];
    };
    PreferenceInfo *allowSendingClipboardInfo = info;

    // ---------------------------------------------------------------------------------------------
    [self defineControl:_enableRTL
                    key:kPreferenceKeyBidi
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];
     [self defineControl:_sshIntegrationForURLs
                     key:kPreferenceKeySshIntegrationForURLs
             relatedView:nil
                    type:kPreferenceInfoTypeCheckbox];

    [self updateEnabledState];
    [self commitControls];
    [self updateValueForInfo:allowSendingClipboardInfo];
    [self organizeStartupAndClosing];
}

// Keep the original controls and preference/search bindings, but show the
// complete start/exit lifecycle together instead of two mostly empty panes.
- (void)organizeStartupAndClosing {
    _startupClosingTab = [_tabView tabViewItemAtIndex:[_tabView indexOfTabViewItemWithIdentifier:@"1"]];
    const NSInteger closingIndex = [_tabView indexOfTabViewItemWithIdentifier:@"2"];
    if (closingIndex != NSNotFound) {
        [_tabView removeTabViewItem:[_tabView tabViewItemAtIndex:closingIndex]];
    }
    _startupClosingTab.label = NSLocalizedString(@"Startup & Exit", @"Settings section");
    [iTermGeneralFormLayout installIn:_tabView controls:@{
        @"openWindowsAtStartupLabel": _openWindowsAtStartupLabel,
        @"openWindowsAtStartup": _openWindowsAtStartup,
        @"warningButton": _warningButton,
        @"openBookmark": _openBookmark,
        @"restoreWindowsToSameSpaces": _restoreWindowsToSameSpaces,
        @"alwaysOpenWindowAtStartup": _alwaysOpenWindowAtStartup,
        @"alwaysOpenLegend": _alwaysOpenLegend,
        @"quitWhenAllWindowsClosed": _quitWhenAllWindowsClosed,
        @"confirmClosingMultipleSessions": _confirmClosingMultipleSessions,
        @"promptOnQuit": _promptOnQuit,
        @"evenIfThereAreNoWindows": _evenIfThereAreNoWindows,
        @"disableConfirmationOnShutdown": _disableConfirmationOnShutdown,
        @"gpuRendering": _gpuRendering,
        @"advancedGPU": _advancedGPU,
        @"maximizeThroughput": _maximizeThroughput,
        @"irMemoryLabel": _irMemoryLabel,
        @"irMemory": _irMemory,
        @"savePasteHistory": _savePasteHistory,
        @"enableAPI": _enableAPI,
        @"apiPermission": _apiPermission,
        @"pythonAPIAuthHelp": _pythonAPIAuthHelpButton ?: [NSButton new],
        @"useCustomScriptsFolder": _useCustomScriptsFolder,
        @"customScriptsFolder": _customScriptsFolder,
        @"customScriptsFolderWarning": _customScriptsFolderWarning,
        @"browseCustomScriptsFolder": _browseCustomScriptsFolder,
        @"enableBonjour": _enableBonjour,
        @"selectionCopiesText": _selectionCopiesText,
        @"copyLastNewline": _copyLastNewline,
        @"allowClipboardAccessFromTerminal": _allowClipboardAccessFromTerminal,
        @"allowsSendingClipboardContentsLabel": _allowsSendingClipboardContentsLabel,
        @"allowsSendingClipboardContents": _allowsSendingClipboardContents,
        @"wordCharsLabel": _wordCharsLabel,
        @"wordCharsHelp": _wordCharsHelpButton ?: [NSButton new],
        @"wordMode": _wordMode,
        @"wordChars": _wordChars,
        @"wordCharsRegex": _wordCharsRegex,
        @"tripleClickSelectsFullLines": _tripleClickSelectsFullLines,
        @"doubleClickPerformsSmartSelection": _doubleClickPerformsSmartSelection,
        @"enterCopyModeAutomatically": _enterCopyModeAutomatically,
        @"wrapDroppedFilenamesInQuotesWhenPasting": _wrapDroppedFilenamesInQuotesWhenPasting,
        @"placementContainer": _placementContainer,
        @"adjustWindowForFontSizeChange": _adjustWindowForFontSizeChange,
        @"maxVertically": _maxVertically,
        @"lionStyleFullscreen": _lionStyleFullscreen,
        @"separateWindowTitlePerTab": _separateWindowTitlePerTab,
        @"loadPrefsFromCustomFolder": _loadPrefsFromCustomFolder,
        @"prefsCustomFolder": _prefsCustomFolder,
        @"prefsDirWarning": _prefsDirWarning,
        @"browseCustomFolder": _browseCustomFolder,
        @"saveChangesLabel": _saveChangesLabel,
        @"saveChanges": _saveChanges,
        @"pushToCustomFolder": _pushToCustomFolder,
        @"exportAllButton": _exportAllButton ?: [NSButton new],
        @"importAllButton": _importAllButton ?: [NSButton new],
        @"eraseAllButton": _eraseAllButton ?: [NSButton new],
        @"openTmuxWindowsAsTabsInAttachingWindow": _openTmuxWindowsAsTabsInAttachingWindow,
        @"whenAttachingTmuxLabel": _whenAttachingTmuxLabel,
        @"openUnrecognizedTmuxWindowsIn": _openUnrecognizedTmuxWindowsIn,
        @"autoHideTmuxClientSession": _autoHideTmuxClientSession,
        @"useTmuxProfile": _useTmuxProfile,
        @"useTmuxStatusBar": _useTmuxStatusBar,
        @"tmuxPauseModeAgeLimit": _tmuxPauseModeAgeLimit,
        @"tmuxWarnBeforePausing": _tmuxWarnBeforePausing,
        @"unpauseTmuxAutomatically": _unpauseTmuxAutomatically,
        @"syncTmuxClipboard": _syncTmuxClipboard,
        @"enableRTL": _enableRTL,
        @"sshIntegrationForURLs": _sshIntegrationForURLs
    }];
}

- (void)resizeWindowForTabViewItem:(NSTabViewItem *)item animated:(BOOL)animated {
    if (item == _startupClosingTab && self.preferencePanel) {
        [self.preferencePanel preferencePanelSetContentSize:NSZeroSize];
        return;
    }
    [super resizeWindowForTabViewItem:item animated:animated];
}

- (void)customScriptsFolderDidChange {
    _customScriptsFolderDidChange = YES;
}

- (void)postCustomScriptsFolderDidChangeNotificationIfNeeded {
    if (_customScriptsFolderDidChange) {
        _customScriptsFolderDidChange = NO;
        [[NSNotificationCenter defaultCenter] postNotificationName:iTermScriptsFolderDidChange object:nil];
    }
}

- (void)windowWillClose {
    [self postCustomScriptsFolderDidChangeNotificationIfNeeded];
}

- (void)willDeselectTab {
    [self postCustomScriptsFolderDidChangeNotificationIfNeeded];
}

- (NSString *)alwaysOpenLegend {
    if ([iTermScriptsMenuController autoLaunchFolderExists]) {
        return @"The presence of auto-launch scripts disables opening a window at startup.";
    }
    if ([[[iTermHotKeyController sharedInstance] profileHotKeys] count] > 0) {
        return @"The existence of hotkey windows disables opening a window at startup.";
    }
    if ([[[iTermBuriedSessions sharedInstance] buriedSessions] count] > 0) {
        return @"The existence of buried sessions disables opening a window at startup.";
    }
    return nil;
}

- (void)updateAlwaysOpenLegend {
    NSString *legend = [self alwaysOpenLegend];
    const BOOL shouldHide = (legend == nil);
    const BOOL changed = (_alwaysOpenLegend.hidden != shouldHide);
    if (shouldHide) {
        _alwaysOpenLegend.hidden = YES;
    } else {
        _alwaysOpenLegend.stringValue = legend;
        _alwaysOpenLegend.hidden = NO;
    }
    if (changed) {
        [self.view it_invalidateProfileFormLayout];
    }
}

- (void)updateAPIEnabledState {
    _enableAPI.state = [self boolForKey:kPreferenceKeyEnableAPIServer];
    [_apiPermission selectItemWithTag:[iTermAPIHelper requireApplescriptAuth] ? 0 : 1];
    [self updateEnabledState];
}

- (BOOL)shouldEnableAlwaysOpenWindowAtStartup {
    if ([self boolForKey:kPreferenceKeyOpenArrangementAtStartup]) {
        return NO;
    }
    if ([self boolForKey:kPreferenceKeyOpenNoWindowsAtStartup]) {
        return NO;
    }
    return YES;
}

- (void)updateEnabledState {
    [super updateEnabledState];
    [_apiPermission selectItemWithTag:[iTermAPIHelper requireApplescriptAuth] ? 0 : 1];
    _evenIfThereAreNoWindows.enabled = [self boolForKey:kPreferenceKeyPromptOnQuit];
    const BOOL useSystemWindowRestoration = (![self boolForKey:kPreferenceKeyOpenArrangementAtStartup] &&
                                             ![self boolForKey:kPreferenceKeyOpenNoWindowsAtStartup]);
    const BOOL systemRestorationEnabled = [[iTermUserDefaults userDefaults] boolForKey:@"NSQuitAlwaysKeepsWindows"];
    _warningButton.hidden = (!useSystemWindowRestoration || systemRestorationEnabled);
    _alwaysOpenWindowAtStartup.enabled = [self shouldEnableAlwaysOpenWindowAtStartup];
    _restoreWindowsToSameSpaces.enabled = systemRestorationEnabled && useSystemWindowRestoration;
}

- (void)updateAdvancedGPUEnabled {
    _advancedGPU.enabled = [self boolForKey:kPreferenceKeyUseMetal];
}

- (BOOL)enableAPISettingDidChange {
    const BOOL result = [self reallyEnableAPISettingDidChange];
    [self updateEnabledState];
    return result;
}

- (BOOL)reallyEnableAPISettingDidChange {
    const BOOL enabled = _enableAPI.state == NSControlStateValueOn;
    if (enabled) {
        // Prompt the user. If they agree, or have permanently agreed, set the user default to YES.
        if ([iTermAPIHelper confirmShouldStartServerAndUpdateUserDefaultsForced:YES]) {
            [iTermAPIHelper sharedInstance];
        } else {
            return NO;
            
        }
    } else {
        [iTermAPIHelper setEnabled:NO];
    }
    if (enabled && ![iTermAPIHelper isEnabled]) {
        _enableAPI.state = NSControlStateValueOff;
        return NO;
    }
    return YES;
}

#pragma mark - Actions

- (IBAction)exportAllSettingsAndData:(id)sender {
    [self showMessage:[iTerm2ImportExport exportAll] title:NSLocalizedString(@"Problem Exporting", @"General settings")];
}

- (IBAction)importAllSettingsAndData:(id)sender {
    [self showMessage:[iTerm2ImportExport importAll] title:NSLocalizedString(@"Problem Importing", @"General settings")];
}

- (IBAction)eraseAllSettingsAndData:(id)sender {
    [self showMessage:[iTerm2ImportExport eraseAllWithWindow:self.view.window]
                title:NSLocalizedString(@"Problem Erasing Settings and Data", @"General settings")];
}

- (void)showMessage:(NSString *)message title:(NSString *)title {
    if (!message) {
        return;
    }
    [iTermWarning showWarningWithTitle:message
                               actions:@[ NSLocalizedString(@"OK", @"General settings") ]
                             accessory:nil
                            identifier:nil
                           silenceable:kiTermWarningTypePersistent
                               heading:title
                                window:self.view.window];
}

- (IBAction)warning:(id)sender {
    NSString *const message = @"System window restoration has been disabled, which prevents Latterm from respecting this setting. Disable ”System Settings > Desktop & Dock > Close windows when quitting an application“ to enable window restoration.";
    NSString *const action = @"Open System Settings";
    NSString *const path = @"/System/Library/PreferencePanes/Dock.prefPane";
    const iTermWarningSelection selection =
    [iTermWarning showWarningWithTitle:message
                               actions:@[ action, @"OK" ]
                             accessory:nil
                            identifier:@"NoSyncWindowRestorationDisabled"
                           silenceable:kiTermWarningTypePersistent
                               heading:@"Window Restoration Disabled"
                                window:self.view.window];
    if (selection == kiTermWarningSelection0) {
        [[NSWorkspace sharedWorkspace] it_openURL:[NSURL fileURLWithPath:path]];
    }
}


- (IBAction)browseCustomFolder:(id)sender {
    [self choosePrefsCustomFolder];
}

- (IBAction)browseScriptsFolder:(id)sender {
    [self chooseCustomScriptsFolder];
}

- (IBAction)pushToCustomFolder:(id)sender {
    [[iTermRemotePreferences sharedInstance] saveLocalUserDefaultsToRemotePrefs];
}

- (IBAction)advancedGPU:(NSView *)sender {
    [self.view.window beginSheet:_advancedGPUWindowController.window completionHandler:^(NSModalResponse returnCode) {
    }];
}

- (IBAction)pythonAPIAuthHelp:(id)sender {
    [[NSWorkspace sharedWorkspace] it_openURL:[NSURL URLWithString:@"https://iterm2.com/python-api-auth.html"]];
}

#pragma mark - Notifications

- (void)savedArrangementChanged:(id)sender {
    PreferenceInfo *info = [self infoForControl:_openWindowsAtStartup];
    [self updateValueForInfo:info];
    [_openDefaultWindowArrangementItem setEnabled:[WindowArrangements count] > 0];
}

// The API helper just noticed that the file's contents changed.
- (void)didRevertPythonAuthenticationMethod:(NSNotification *)notification {
    [self updateAPIEnabledState];
}

- (void)preferenceDidChangeFromOtherPanel:(NSNotification *)notification {
    [self updateAlwaysOpenLegend];
    [super preferenceDidChangeFromOtherPanel:notification];
}


#pragma mark - Remote Prefs

- (void)updateCustomScriptsFolderViews {
    BOOL haveCustomFolder = [iTermPreferences boolForKey:kPreferenceKeyUseCustomScriptsFolder];
    _browseCustomScriptsFolder.enabled = haveCustomFolder;
    _customScriptsFolder.enabled = haveCustomFolder;
    if (haveCustomFolder) {
        _customScriptsFolderWarning.alphaValue = 1;
    } else {
        if (_customScriptsFolder.stringValue.length > 0) {
            _customScriptsFolderWarning.alphaValue = 0.5;
        } else {
            _customScriptsFolderWarning.alphaValue = 0;
        }
    }
    const BOOL locationIsValid = [[NSFileManager defaultManager] customScriptsFolderIsValid:_customScriptsFolder.stringValue];
    _customScriptsFolderWarning.image = locationIsValid ? [NSImage it_imageNamed:@"CheckMark" forClass:self.class] : [NSImage it_imageNamed:@"WarningSign" forClass:self.class];
}

- (void)updateRemotePrefsViews {
    BOOL shouldLoadRemotePrefs =
        [iTermPreferences boolForKey:kPreferenceKeyLoadPrefsFromCustomFolder];
    [_browseCustomFolder setEnabled:shouldLoadRemotePrefs];
    [_prefsCustomFolder setEnabled:shouldLoadRemotePrefs];

    if (shouldLoadRemotePrefs) {
        _prefsDirWarning.alphaValue = 1;
    } else {
        if (_prefsCustomFolder.stringValue.length > 0) {
            _prefsDirWarning.alphaValue = 0.5;
        } else {
            _prefsDirWarning.alphaValue = 0;
        }
    }

    BOOL remoteLocationIsValid = [[iTermRemotePreferences sharedInstance] remoteLocationIsValid];
    _prefsDirWarning.image = remoteLocationIsValid ? [NSImage it_imageNamed:@"CheckMark" forClass:self.class] : [NSImage it_imageNamed:@"WarningSign" forClass:self.class];
    BOOL isValidFile = (shouldLoadRemotePrefs &&
                        remoteLocationIsValid &&
                        ![[iTermRemotePreferences sharedInstance] remoteLocationIsURL]);
    [_saveChanges setEnabled:isValidFile];
    [_saveChangesLabel setLabelEnabled:isValidFile];
    [_pushToCustomFolder setEnabled:isValidFile];
}

- (void)useCustomScriptsFolderDidChange {
    const BOOL newValue = [iTermPreferences boolForKey:kPreferenceKeyUseCustomScriptsFolder];
    [self updateCustomScriptsFolderViews];
    if (newValue) {
        // Just turned it on
        if ([[_customScriptsFolder stringValue] length] == 0) {
            // Filed was initially empty so browse for a dir.
            if ([self chooseCustomScriptsFolder]) {
                [[NSNotificationCenter defaultCenter] postNotificationName:iTermScriptsFolderDidChange object:nil];
            }
        }
    }
    [self updateCustomScriptsFolderViews];
}

- (void)loadPrefsFromCustomFolderDidChangeByUI:(BOOL)byUI {
    BOOL shouldLoadRemotePrefs = [iTermPreferences boolForKey:kPreferenceKeyLoadPrefsFromCustomFolder];
    [self updateRemotePrefsViews];
    if (shouldLoadRemotePrefs && byUI) {
        // Just turned it on.
#if DEBUG
        const BOOL gitlab = [iTermPreferences gitlabURLOnPasteboard] != nil;
#else
        const BOOL gitlab = NO;
#endif
        if ([[_prefsCustomFolder stringValue] length] == 0 && !gitlab) {
            // Field was initially empty so browse for a dir.
            if ([self choosePrefsCustomFolder]) {
                // User didn't hit cancel; if he chose a writable directory, ask if he wants to write to it.
                if ([[iTermRemotePreferences sharedInstance] remoteLocationIsValid]) {
                    NSAlert *alert = [[NSAlert alloc] init];
                    alert.messageText = NSLocalizedString(@"Copy local settings to custom folder now?", @"General settings");
                    [alert addButtonWithTitle:NSLocalizedString(@"Copy", @"General settings")];
                    [alert addButtonWithTitle:NSLocalizedString(@"Don’t Copy", @"General settings")];
                    if ([alert runModal] == NSAlertFirstButtonReturn) {
                        [[iTermRemotePreferences sharedInstance] saveLocalUserDefaultsToRemotePrefs];
                    }
                }
            }
        }
    }
    if (!byUI && (_loadPrefsFromCustomFolder.state == NSControlStateValueOn) != shouldLoadRemotePrefs) {
        _loadPrefsFromCustomFolder.state = shouldLoadRemotePrefs ? NSControlStateValueOn : NSControlStateValueOff;
    }
    [self updateRemotePrefsViews];
}

- (BOOL)chooseCustomScriptsFolder {
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    [panel setCanChooseFiles:NO];
    [panel setCanChooseDirectories:YES];
    [panel setAllowsMultipleSelection:NO];

    if ([panel runModal] == NSModalResponseOK && panel.directoryURL.path) {
        [_customScriptsFolder setStringValue:panel.directoryURL.path];
        [self settingChanged:_customScriptsFolder];
        return YES;
    }  else {
        return NO;
    }
}

- (BOOL)choosePrefsCustomFolder {
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    [panel setCanChooseFiles:NO];
    [panel setCanChooseDirectories:YES];
    [panel setAllowsMultipleSelection:NO];

    if ([panel runModal] == NSModalResponseOK && panel.directoryURL.path) {
        [_prefsCustomFolder setStringValue:panel.directoryURL.path];
        [self settingChanged:_prefsCustomFolder];
        return YES;
    }  else {
        return NO;
    }
}

- (NSTabView *)tabView {
    return _tabView;
}

- (CGFloat)minimumWidth {
    return 598;
}

@end
