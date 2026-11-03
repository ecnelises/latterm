//
//  iTermEditKeyActionWindowController.m
//  iTerm
//
//  Created by George Nachman on 4/7/14.
//
//

#import "iTermEditKeyActionWindowController.h"

#import "DebugLogging.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermActionsModel.h"
#import "iTermFunctionCallTextFieldDelegate.h"
#import "iTermKeystrokeFormatter.h"
#import "iTermPasteSpecialViewController.h"
#import "iTermPreferences.h"
#import "iTermShortcutInputView.h"
#import "iTermVariableScope.h"
#import "NSArray+iTerm.h"
#import "NSPopUpButton+iTerm.h"
#import "NSScreen+iTerm.h"
#import "NSTextField+iTerm.h"
#import "NSView+iTerm.h"
#import "RegexKitLite.h"

@import SearchableComboListView;

const CGFloat sideMarginWidth = 40;

@interface iTermEditKeyActionDetailView: NSView
@end

@implementation iTermEditKeyActionDetailView

- (NSView *)hitTest:(NSPoint)point {
    NSView *subview = [super hitTest:point];
    if (subview == self) {
        return nil;
    }
    return subview;
}
@end

@interface iTermEditKeyActionWindowConfiguration: NSObject
@property (nonatomic, readonly) BOOL applyHidden;
@property (nonatomic, readonly) BOOL parameterHidden;
@property (nonatomic, readonly) NSString *helpString;
@property (nonatomic, readonly) BOOL parameterLabelHidden;
@property (nonatomic, readonly) BOOL profilePopupHidden;
@property (nonatomic, readonly) BOOL selectionMovementUnitHidden;
@property (nonatomic, readonly) BOOL profileLabelHidden;
@property (nonatomic, readonly) BOOL menuToSelectPopupHidden;
@property (nonatomic, readonly) BOOL settingToTogglePopupHidden;
@property (nonatomic, readonly) BOOL shortcutFieldDisableKeyRemapping;
@property (nonatomic, readonly) BOOL colorPresetsLabelHidden;
@property (nonatomic, readonly) BOOL colorPresetsPopupHidden;
@property (nonatomic, readonly) BOOL pasteSpecialHidden;
@property (nonatomic, readonly) BOOL snippetsHidden;
@property (nonatomic, readonly) BOOL showSecondary;
@property (nonatomic, readonly) NSString *parameterPlaceholder;
@property (nonatomic, readonly) NSString *parameterLabel;
@property (nonatomic, readonly) iTermFunctionCallTextFieldDelegate *parameterDelegate;
@property (nonatomic, readonly) NSString *parameterValue;
@end

@implementation iTermEditKeyActionWindowConfiguration

- (instancetype)initWithTag:(int)tag
       functionCallDelegate:(iTermFunctionCallTextFieldDelegate *)functionCallDelegate
 interpolatedStringDelegate:(iTermFunctionCallTextFieldDelegate *)interpolatedStringDelegate
                    context:(iTermVariablesSuggestionContext)context {
    self = [super init];
    if (self) {
        _parameterHidden = YES;
        _helpString = nil;
        _parameterLabelHidden = YES;
        _profilePopupHidden = YES;
        _selectionMovementUnitHidden = YES;
        _profileLabelHidden = YES;
        _menuToSelectPopupHidden = YES;
        _settingToTogglePopupHidden = YES;
        _shortcutFieldDisableKeyRemapping = NO;
        _colorPresetsLabelHidden = YES;
        _colorPresetsPopupHidden = YES;
        _pasteSpecialHidden = YES;
        _snippetsHidden = YES;
        _showSecondary = NO;
        _applyHidden = YES;

        switch (tag) {
            case KEY_ACTION_SEND_SNIPPET:
                _snippetsHidden = NO;
                _parameterValue = @"";
                _applyHidden = NO;
                break;

            case KEY_ACTION_COMPOSE:
                _parameterHidden = NO;
                _parameterPlaceholder = NSLocalizedString(@"Text for composer", @"Key binding action editor");
                break;

            case KEY_ACTION_HEX_CODE:
                _parameterHidden = NO;
                _parameterPlaceholder = NSLocalizedString(@"ex: 0x7f 0x20", @"Key binding action editor");
                _applyHidden = NO;
                break;

            case KEY_ACTION_VIM_TEXT:
            case KEY_ACTION_VIM_TEXT_NO_BROADCAST:
                _parameterHidden = NO;
                _helpString = NSLocalizedString(@"Special characters are:\n* \\<1-to-3-digit octal>\n* \\x<1 or 2 digit hex>\n* \\u<4 digit hex>\n* \\b for backspace\n* \\e for esc\n* \\f for formfeed\n* \\n for newline and \\r for return\n* \\t for tab\n* \\\\ and \\\" for literal \\ and \"\n* <C-x> for control key\n* <M-x> for meta key.", @"Key binding action editor");
                _parameterPlaceholder = NSLocalizedString(@"Enter value to send. Click help button for special characters.", @"Key binding action editor");
                _applyHidden = NO;
                break;

            case KEY_ACTION_TEXT:
                _parameterHidden = NO;
                _parameterPlaceholder = NSLocalizedString(@"Enter value to send", @"Key binding action editor");
                _applyHidden = NO;
                break;

            case KEY_ACTION_RUN_COPROCESS:
                _parameterHidden = NO;
                _parameterPlaceholder = NSLocalizedString(@"Enter command to run", @"Key binding action editor");
                _applyHidden = NO;
                break;

            case KEY_ACTION_SEND_TMUX_COMMAND:
                _parameterHidden = NO;
                _parameterPlaceholder = NSLocalizedString(@"Enter tmux command", @"Key binding action editor");
                break;

            case KEY_ACTION_SELECT_MENU_ITEM:
                _parameterPlaceholder = NSLocalizedString(@"Enter name of menu item", @"Key binding action editor");
                _menuToSelectPopupHidden = NO;
                _parameterValue = @"";
                break;

            case KEY_ACTION_ESCAPE_SEQUENCE:
                _parameterHidden = NO;
                _parameterPlaceholder = NSLocalizedString(@"characters to send", @"Key binding action editor");
                _parameterLabelHidden = NO;
                _parameterLabel = NSLocalizedString(@"Esc+", @"Key binding action editor");
                _applyHidden = NO;
                break;

            case KEY_ACTION_SPLIT_VERTICALLY_WITH_PROFILE:
            case KEY_ACTION_SPLIT_HORIZONTALLY_WITH_PROFILE:
            case KEY_ACTION_NEW_TAB_WITH_PROFILE:
            case KEY_ACTION_NEW_WINDOW_WITH_PROFILE:
                _profileLabelHidden = NO;
                _profilePopupHidden = NO;
                _parameterValue = @"";
                break;

            case KEY_ACTION_SET_PROFILE:
                _profileLabelHidden = NO;
                _profilePopupHidden = NO;
                _parameterValue = @"";
                _applyHidden = NO;
                break;

            case KEY_ACTION_LOAD_COLOR_PRESET:
                _colorPresetsLabelHidden = NO;
                _colorPresetsPopupHidden = NO;
                _parameterValue = @"";
                _applyHidden = NO;
                break;

            case KEY_ACTION_DO_NOT_REMAP_MODIFIERS:
                _shortcutFieldDisableKeyRemapping = YES;
                _parameterValue = @"";
                _helpString = NSLocalizedString(@"This action lets you exempt a keystroke from modifier remapping. For example, if you remap ⌘ to ⌥ but you want ⌘-Tab to work as though ⌘ were unmapped just for that keystroke, you would use this action and set the keyboard shortcut to ⌘-Tab", @"Key binding action editor");
                _parameterValue = @"";
                break;

            case KEY_ACTION_REMAP_LOCALLY:
                _shortcutFieldDisableKeyRemapping = YES;
                _parameterValue = @"";
                _helpString = NSLocalizedString(@"This action applies modifier remapping but prevents other programs from seeing the keystroke. For example, if you've swapped ⌘ and ^ and want physical ^-tab to switch tabs in Latterm instead of triggering the app switcher: bind ^-tab to this action. The system won't see the remapped ⌘-tab (so no app switcher), but Latterm receives it and can switch tabs.", @"Key binding action editor");
                _parameterValue = @"";
                break;

            case KEY_ACTION_BYPASS:
                _helpString = NSLocalizedString(@"Prevents the keystroke from being sent to the terminal while allowing macOS to handle it normally. For example, if F1 triggers a macOS Shortcut, binding F1 to Bypass Terminal stops it from sending a control sequence to the terminal but still lets the system shortcut work.", @"Key binding action editor");
                break;

            case KEY_ACTION_IGNORE:
                _helpString = NSLocalizedString(@"Prevents the keystroke from having any effect within Latterm. Modifier remapping remains unaffected.", @"Key binding action editor");
                break;

            case KEY_ACTION_NEXT_MRU_TAB:
                _parameterValue = @"";
                _helpString = NSLocalizedString(@"Switches tabs in most-recently-used order, like ⌘-Tab in macOS. Hold a modifier and tap repeatedly to walk back through tab history; release the modifier to commit your selection. A single tap with no modifier held jumps to the previously-selected tab, so binding this to a plain key acts as a toggle between the two most recent tabs.", @"Key binding action editor");
                break;

            case KEY_ACTION_PREVIOUS_MRU_TAB:
                _parameterValue = @"";
                _helpString = NSLocalizedString(@"Switches tabs in reverse most-recently-used order. Hold a modifier and tap repeatedly to walk forward through tab history (oldest first); release the modifier to commit your selection. A single tap with no modifier held jumps to the least-recently-used tab.", @"Key binding action editor");
                break;

            case KEY_ACTION_FIND_REGEX:
                _parameterHidden = NO;
                _parameterPlaceholder = NSLocalizedString(@"Regular Expression", @"Key binding action editor");
                _applyHidden = NO;
                break;

            case KEY_ACTION_COPY_MODE:
                _parameterHidden = NO;
                _parameterPlaceholder = NSLocalizedString(@"Copy Mode Commands", @"Key binding action editor");
                _applyHidden = NO;
                _helpString = NSLocalizedString(@"Enter copy mode commands to move cursor, toggle selection, and so on. This key binding enters Copy Mode and then acts as though you had pressed the keys listed here. [See a list of all the commands](https://iterm2.com/documentation-copymode.html). Use vim syntax for control, option, and function keys (e.g., `<C-x>` or `<Up>`).", @"Key binding action editor");
                break;

            case KEY_ACTION_TOGGLE_SETTING:
                _parameterPlaceholder = NSLocalizedString(@"Enter name of menu item", @"Key binding action editor");
                _settingToTogglePopupHidden = NO;
                _parameterValue = @"";
                break;

            case KEY_ACTION_INVOKE_SCRIPT_FUNCTION:
                _parameterHidden = NO;
                _parameterPlaceholder = NSLocalizedString(@"Function Call", @"Key binding action editor");
                if (functionCallDelegate) {
                    _parameterDelegate = functionCallDelegate;
                } else {
                    _parameterDelegate =
                    [[iTermFunctionCallTextFieldDelegate alloc] initWithPathSource:[iTermVariableHistory pathSourceForContext:context]
                                                                       passthrough:nil
                                                                     functionsOnly:YES];
                }
                _applyHidden = NO;
                break;

            case KEY_ACTION_PASTE_SPECIAL_FROM_SELECTION:
            case KEY_ACTION_PASTE_SPECIAL:
                _pasteSpecialHidden = NO;
                _parameterValue = @"";
                _applyHidden = NO;
                break;

            case KEY_ACTION_MOVE_END_OF_SELECTION_LEFT:
            case KEY_ACTION_MOVE_END_OF_SELECTION_RIGHT:
            case KEY_ACTION_MOVE_START_OF_SELECTION_LEFT:
            case KEY_ACTION_MOVE_START_OF_SELECTION_RIGHT:
                _parameterValue = @"";
                _selectionMovementUnitHidden = NO;
                _parameterValue = @"";
                break;

            case KEY_ACTION_SEQUENCE:
                _showSecondary = YES;
                _parameterValue = @"";
                break;

            case KEY_ACTION_COPY_INTERPOLATED_STRING:
                _parameterHidden = NO;
                _parameterPlaceholder = NSLocalizedString(@"Enter interpolated string (evaluated in session context)", @"Key binding action editor");
                if (interpolatedStringDelegate) {
                    _parameterDelegate = interpolatedStringDelegate;
                } else {
                    _parameterDelegate =
                    [[iTermFunctionCallTextFieldDelegate alloc] initWithPathSource:[iTermVariableHistory pathSourceForContext:context]
                                                                       passthrough:nil
                                                                     functionsOnly:NO];
                }
                _helpString = NSLocalizedString(@"You can use this to copy information about the current session to the clipboard. [Learn more about interpolated strings](https://iterm2.com/documentation-scripting-fundamentals.html)", @"Key binding action editor");
                break;

            case KEY_ACTION_SCROLL_END:
            case KEY_ACTION_SCROLL_HOME:
            case KEY_ACTION_SCROLL_LINE_DOWN:
            case KEY_ACTION_SCROLL_LINE_UP:
            case KEY_ACTION_SCROLL_PAGE_DOWN:
            case KEY_ACTION_SCROLL_PAGE_UP:
            case KEY_ACTION_SEND_C_H_BACKSPACE:
            case KEY_ACTION_SEND_C_QM_BACKSPACE:
            case KEY_ACTION_DECREASE_HEIGHT:
            case KEY_ACTION_INCREASE_HEIGHT:
            case KEY_ACTION_DECREASE_WIDTH:
            case KEY_ACTION_INCREASE_WIDTH:
            case KEY_ACTION_TOGGLE_MOUSE_REPORTING:
            case KEY_ACTION_PASTE_OR_SEND:
            case KEY_ACTION_ALERT_ON_NEXT_MARK:
            case KEY_ACTION_COPY_OR_SEND:
                _parameterValue = @"";
                break;

            default:
                _parameterValue = @"";
                break;
        }
    }
    return self;
}

@end

@interface iTermEditKeyActionWindowController () <
    iTermKeyActionSequenceTableViewControllerDelegate,
    iTermPasteSpecialViewControllerDelegate,
    iTermSearchableComboViewDelegate,
    iTermShortcutInputViewDelegate,
    NSTextFieldDelegate>

@property(nonatomic, assign) BOOL ok;

@end

@implementation iTermEditKeyActionWindowController {
    IBOutlet NSView *_detail;
    IBOutlet NSView *_secondaryComboViewContainer;
    IBOutlet NSTextField *_secondaryActionLabel;
    IBOutlet NSView *_sequenceContainer;
    iTermSearchableComboView *_secondaryComboView;
    IBOutlet iTermKeyActionSequenceTableViewController *_sequenceTableViewController;

    IBOutlet iTermShortcutInputView *_shortcutField;
    IBOutlet NSTextField *_keyboardShortcutLabel;
    IBOutlet NSTextField *_actionTitleField;
    IBOutlet NSView *_comboViewContainer;
    iTermSearchableComboView *_comboView;
    IBOutlet NSTextField *_parameter;
    IBOutlet NSTextField *_parameterLabel;
    IBOutlet NSPopUpButton *_profilePopup;
    IBOutlet NSPopUpButton *_selectionMovementUnit;
    IBOutlet iTermMenuItemPopupView *_menuToSelectPopup;
    IBOutlet iTermSettingPopupView *_settingToTogglePopup;
    IBOutlet NSTextField *_profileLabel;
    IBOutlet NSTextField *_colorPresetsLabel;
    IBOutlet NSPopUpButton *_colorPresetsPopup;
    IBOutlet NSPopUpButton *_snippetsPopup;
    IBOutlet NSView *_pasteSpecialViewContainer;
    IBOutlet NSButton *_okButton;
    NSPopUpButton *_applyButton;
    IBOutlet NSButton *_helpButton;
    IBOutlet NSTextField *_errorLabel;
    iTermEditKeyActionWindowConfiguration *_config;

    iTermPasteSpecialViewController *_pasteSpecialViewController;
    iTermFunctionCallTextFieldDelegate *_functionCallDelegate;
    iTermFunctionCallTextFieldDelegate *_interpolatedStringDelegate;
    iTermFunctionCallTextFieldDelegate *_labelDelegate;
}

- (instancetype)initWithContext:(iTermVariablesSuggestionContext)context
                           mode:(iTermEditKeyActionWindowControllerMode)mode {
    self = [super initWithWindowNibPath:[iTermSettingsLocalization nibPath:@"iTermEditKeyActionWindowController"] owner:self];
    if (self) {
        _suggestContext = context;
        _mode = mode;
    }
    return self;
}

- (NSArray<iTermSearchableComboViewGroup *> *)groupsForPrimary:(BOOL)primary {
    NSArray<iTermSearchableComboViewGroup *> *groups = @[
        [[iTermSearchableComboViewGroup alloc] initWithLabel:NSLocalizedString(@"General", @"Key binding action group") items:[@[
            primary ? [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Ignore", @"Key binding action") tag:KEY_ACTION_IGNORE] : [NSNull null],
            primary ? [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Bypass Terminal", @"Key binding action") tag:KEY_ACTION_BYPASS] : [NSNull null],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Select Menu Item…", @"Key binding action") tag:KEY_ACTION_SELECT_MENU_ITEM],
        ] arrayByRemovingNulls]]
    ];
    if (self.mode == iTermEditKeyActionWindowControllerModeKeyboardShortcut) {
        groups = [groups arrayByAddingObjectsFromArray:[@[
            primary ? [[iTermSearchableComboViewGroup alloc] initWithLabel:NSLocalizedString(@"Modifier Remapping", @"Key binding action group") items:@[
                [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Do Not Remap Modifiers", @"Key binding action") tag:KEY_ACTION_DO_NOT_REMAP_MODIFIERS],
                [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Remap Modifiers in Latterm Only", @"Key binding action") tag:KEY_ACTION_REMAP_LOCALLY],
            ]] : [NSNull null],
            [[iTermSearchableComboViewGroup alloc] initWithLabel:NSLocalizedString(@"Recent Tabs", @"Key binding action group") items:@[
                [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Cycle Tabs Forward", @"Keyboard shortcut") tag:KEY_ACTION_NEXT_MRU_TAB],
                [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Cycle Tabs Backward", @"Keyboard shortcut") tag:KEY_ACTION_PREVIOUS_MRU_TAB],
            ]],
        ] arrayByRemovingNulls]];
    }

    groups = [groups arrayByAddingObjectsFromArray:[@[
        [[iTermSearchableComboViewGroup alloc] initWithLabel:NSLocalizedString(@"Miscellaneous", @"Key binding action group") items:[@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Run Coprocess", @"Key binding action") tag:KEY_ACTION_RUN_COPROCESS],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Start Instant Replay", @"Key binding action") tag:KEY_ACTION_IR_BACKWARD],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Undo", @"Key binding action") tag:KEY_ACTION_UNDO],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Send tmux Command", @"Key binding action") tag:KEY_ACTION_SEND_TMUX_COMMAND],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Alert on Next Mark", @"Key binding action") tag:KEY_ACTION_ALERT_ON_NEXT_MARK],
        ] arrayByRemovingNulls]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:NSLocalizedString(@"New Tab or Window", @"Key binding action group") items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"New Window with Profile", @"Key binding action") tag:KEY_ACTION_NEW_WINDOW_WITH_PROFILE],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"New Tab with Profile", @"Key binding action") tag:KEY_ACTION_NEW_TAB_WITH_PROFILE],
        [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Duplicate Tab", @"Key binding action") tag:KEY_ACTION_DUPLICATE_TAB],
        ]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:NSLocalizedString(@"Split", @"Key binding action group") items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Split Horizontally with Profile", @"Key binding action") tag:KEY_ACTION_SPLIT_HORIZONTALLY_WITH_PROFILE],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Split Vertically with Profile", @"Key binding action") tag:KEY_ACTION_SPLIT_VERTICALLY_WITH_PROFILE],
        ]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:NSLocalizedString(@"Profile", @"Key binding action group") items:[@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Change Profile", @"Key binding action") tag:KEY_ACTION_SET_PROFILE],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Load Color Preset", @"Key binding action") tag:KEY_ACTION_LOAD_COLOR_PRESET],
        ] arrayByRemovingNulls]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:NSLocalizedString(@"Navigate Tabs", @"Key binding action group") items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Next Tab", @"Keyboard shortcut") tag:KEY_ACTION_NEXT_SESSION],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Previous Tab", @"Keyboard shortcut") tag:KEY_ACTION_PREVIOUS_SESSION],
        ]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:NSLocalizedString(@"Reorder Tabs", @"Key binding action group") items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Move Tab Left", @"Keyboard shortcut") tag:KEY_ACTION_MOVE_TAB_LEFT],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Move Tab Right", @"Keyboard shortcut") tag:KEY_ACTION_MOVE_TAB_RIGHT],
        ]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:NSLocalizedString(@"Navigate Windows", @"Key binding action group") items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Next Window", @"Keyboard shortcut") tag:KEY_ACTION_NEXT_WINDOW],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Previous Window", @"Keyboard shortcut") tag:KEY_ACTION_PREVIOUS_WINDOW],
        ]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:NSLocalizedString(@"Navigate Panes", @"Key binding action group") items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Next Pane", @"Keyboard shortcut") tag:KEY_ACTION_NEXT_PANE],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Previous Pane", @"Keyboard shortcut") tag:KEY_ACTION_PREVIOUS_PANE],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Select Split Pane Above", @"Key binding action") tag:KEY_ACTION_SELECT_PANE_ABOVE],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Select Split Pane Below", @"Key binding action") tag:KEY_ACTION_SELECT_PANE_BELOW],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Select Split Pane On Left", @"Key binding action") tag:KEY_ACTION_SELECT_PANE_LEFT],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Select Split Pane On Right", @"Key binding action") tag:KEY_ACTION_SELECT_PANE_RIGHT],
        ]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:NSLocalizedString(@"Resize Pane", @"Key binding action group") items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Decrease Height", @"Key binding action") tag:KEY_ACTION_DECREASE_HEIGHT],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Increase Height", @"Key binding action") tag:KEY_ACTION_INCREASE_HEIGHT],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Decrease Width", @"Key binding action") tag:KEY_ACTION_DECREASE_WIDTH],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Increase Width", @"Key binding action") tag:KEY_ACTION_INCREASE_WIDTH],
        ]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:NSLocalizedString(@"Scroll", @"Key binding action group") items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Scroll to End", @"Key binding action") tag:KEY_ACTION_SCROLL_END],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Scroll to Top", @"Key binding action") tag:KEY_ACTION_SCROLL_HOME],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Scroll One Line Down", @"Keyboard shortcut") tag:KEY_ACTION_SCROLL_LINE_DOWN],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Scroll One Line Up", @"Keyboard shortcut") tag:KEY_ACTION_SCROLL_LINE_UP],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Scroll One Page Down", @"Keyboard shortcut") tag:KEY_ACTION_SCROLL_PAGE_DOWN],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Scroll One Page Up", @"Keyboard shortcut") tag:KEY_ACTION_SCROLL_PAGE_UP],
        ]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:NSLocalizedString(@"Split Panes", @"Key binding action group") items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Swap With Split Pane Above", @"Key binding action") tag:KEY_ACTION_SWAP_PANE_ABOVE],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Swap With Split Pane Below", @"Key binding action") tag:KEY_ACTION_SWAP_PANE_BELOW],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Swap With Split Pane on Left", @"Key binding action") tag:KEY_ACTION_SWAP_PANE_LEFT],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Swap With Split Pane on Right", @"Key binding action") tag:KEY_ACTION_SWAP_PANE_RIGHT],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Swap With Next Pane", @"Key binding action") tag:KEY_ACTION_SWAP_WITH_NEXT_PANE],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Swap With Previous Pane", @"Key binding action") tag:KEY_ACTION_SWAP_WITH_PREVIOUS_PANE],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Move Session to Split Pane", @"Key binding action") tag:KEY_ACTION_MOVE_TO_SPLIT_PANE],
        ]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:NSLocalizedString(@"Send Keystrokes", @"Key binding action group") items:[@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Send ^H Backspace", @"Key binding action") tag:KEY_ACTION_SEND_C_H_BACKSPACE],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Send ^? Backspace", @"Key binding action") tag:KEY_ACTION_SEND_C_QM_BACKSPACE],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Send Escape Sequence", @"Key binding action") tag:KEY_ACTION_ESCAPE_SEQUENCE],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Send Hex Code", @"Key binding action") tag:KEY_ACTION_HEX_CODE],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Send Text", @"Key binding action") tag:KEY_ACTION_TEXT],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Send Text with “vim” Special Chars", @"Key binding action") tag:KEY_ACTION_VIM_TEXT],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Send Text without Broadcasting", @"Key binding action") tag:KEY_ACTION_VIM_TEXT_NO_BROADCAST],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Send Snippet", @"Key binding action") tag:KEY_ACTION_SEND_SNIPPET],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Compose…", @"Key binding action") tag:KEY_ACTION_COMPOSE],
        ] arrayByRemovingNulls]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:NSLocalizedString(@"Search", @"Key binding action group") items:[@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Find Regular Expression…", @"Key binding action") tag:KEY_ACTION_FIND_REGEX],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Find Again Down", @"Key binding action") tag:KEY_FIND_AGAIN_DOWN],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Find Again Up", @"Key binding action") tag:KEY_FIND_AGAIN_UP],
        ] arrayByRemovingNulls]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:NSLocalizedString(@"Pasteboard", @"Key binding action group") items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Paste…", @"Key binding action") tag:KEY_ACTION_PASTE_SPECIAL],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Paste from Selection…", @"Key binding action") tag:KEY_ACTION_PASTE_SPECIAL_FROM_SELECTION],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Copy or Send ^C", @"Key binding action") tag:KEY_ACTION_COPY_OR_SEND],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Paste or Send ^V", @"Key binding action") tag:KEY_ACTION_PASTE_OR_SEND],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Copy Interpolated String", @"Key binding action") tag:KEY_ACTION_COPY_INTERPOLATED_STRING],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Copy Mode Commands", @"Key binding action") tag:KEY_ACTION_COPY_MODE],
        ]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:NSLocalizedString(@"Toggles", @"Key binding action group") items:[@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Toggle Fullscreen", @"Key binding action") tag:KEY_ACTION_TOGGLE_FULLSCREEN],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Toggle Pin Hotkey Window", @"Key binding action") tag:KEY_ACTION_TOGGLE_HOTKEY_WINDOW_PINNING],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Toggle Mouse Reporting", @"Key binding action") tag:KEY_ACTION_TOGGLE_MOUSE_REPORTING],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Toggle Setting", @"Key binding action") tag:KEY_ACTION_TOGGLE_SETTING],
        ] arrayByRemovingNulls]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:NSLocalizedString(@"Selection", @"Key binding action group") items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Move Start of Selection Back", @"Key binding action") tag:KEY_ACTION_MOVE_START_OF_SELECTION_LEFT],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Move Start of Selection Forward", @"Key binding action") tag:KEY_ACTION_MOVE_START_OF_SELECTION_RIGHT],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Move End of Selection Back", @"Key binding action") tag:KEY_ACTION_MOVE_END_OF_SELECTION_LEFT],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Move End of Selection Forward", @"Key binding action") tag:KEY_ACTION_MOVE_END_OF_SELECTION_RIGHT],
        ]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:NSLocalizedString(@"Scripting", @"Key binding action group") items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Invoke Script Function…", @"Key binding action") tag:KEY_ACTION_INVOKE_SCRIPT_FUNCTION],
        ]],

        primary ? [[iTermSearchableComboViewGroup alloc] initWithLabel:NSLocalizedString(@"Composition", @"Key binding action group") items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedString(@"Sequence…", @"Key binding action") tag:KEY_ACTION_SEQUENCE],
        ]] : [NSNull null],
    ] arrayByRemovingNulls]];
    return groups;
}

- (void)windowDidLoad
{
    [super windowDidLoad];

    _sequenceTableViewController.delegate = self;
    _menuToSelectPopup.delegate = self;
    _settingToTogglePopup.delegate = self;

    switch (self.mode) {
        case iTermEditKeyActionWindowControllerModeKeyboardShortcut:
            break;
        case iTermEditKeyActionWindowControllerModeUnbound:
            _actionTitleField.placeholderString = self.titleIsInterpolated ? NSLocalizedString(@"Title (Interpolated String)", @"Key binding action editor") : NSLocalizedString(@"Title", @"Key binding action editor");
            break;
    }

    _comboView = [[iTermSearchableComboView alloc] initWithGroups:[self groupsForPrimary:YES]
                                                     defaultTitle:NSLocalizedString(@"Select Action…", @"Key binding action editor")];
    [_comboViewContainer addSubview:_comboView];
    _comboView.frame = _comboViewContainer.bounds;
    _comboView.delegate = self;

    _secondaryComboView = [[iTermSearchableComboView alloc] initWithGroups:[self groupsForPrimary:NO]
                                                              defaultTitle:NSLocalizedString(@"Select Action…", @"Key binding action editor")];
    [_secondaryComboViewContainer addSubview:_secondaryComboView];
    _secondaryComboView.frame = _secondaryComboViewContainer.bounds;
    _secondaryComboView.delegate = self;

    // For some reason, the first item is checked by default. Make sure every
    // item is unchecked before making a selection.
    NSString *formattedString = @"";
    if (self.currentKeystroke) {
        formattedString = [iTermKeystrokeFormatter stringForKeystroke:self.currentKeystroke];
    }
    _shortcutField.stringValue = formattedString;
    _actionTitleField.stringValue = self.label ?: @"";
    _okButton.enabled = [self shouldEnableOK];
    (void)[_comboView selectItemWithTag:self.action];

    _applyButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_applyButton addItemWithTitle:NSLocalizedString(@"Apply to current session", @"Key binding action scope")];
    _applyButton.menu.itemArray.lastObject.tag = iTermActionApplyModeCurrentSession;
    [_applyButton addItemWithTitle:NSLocalizedString(@"Apply to all sessions", @"Key binding action scope")];
    _applyButton.menu.itemArray.lastObject.tag = iTermActionApplyModeAllSessions;
    [_applyButton addItemWithTitle:NSLocalizedString(@"Apply to all sessions except current", @"Key binding action scope")];
    _applyButton.menu.itemArray.lastObject.tag = iTermActionApplyModeUnfocusedSessions;
    [_applyButton addItemWithTitle:NSLocalizedString(@"Apply to all sessions in window", @"Key binding action scope")];
    _applyButton.menu.itemArray.lastObject.tag = iTermActionApplyModeAllInWindow;
    [_applyButton addItemWithTitle:NSLocalizedString(@"Apply to all sessions in tab", @"Key binding action scope")];
    _applyButton.menu.itemArray.lastObject.tag = iTermActionApplyModeAllInTab;
    [_applyButton addItemWithTitle:NSLocalizedString(@"Apply to broadcasted-to sessions", @"Key binding action scope")];
    _applyButton.menu.itemArray.lastObject.tag = iTermActionApplyModeBroadcasting;

    _applyButton.target = self;
    _applyButton.action = @selector(parameterDidChange:);
    [_detail addSubview:_applyButton];

    [self loadParameter:self.parameterValue
                 action:self.action
              applyMode:self.applyMode
              secondary:NO];
}

- (void)loadParameter:(NSString *)parameterValue
               action:(KEY_ACTION)action
            applyMode:(iTermActionApplyMode)applyMode
            secondary:(BOOL)secondary {
    _parameter.stringValue = parameterValue ?: @"";
    if (action == KEY_ACTION_SELECT_MENU_ITEM) {
        [_menuToSelectPopup reloadData];
        NSArray *parts = [parameterValue ?: @"" componentsSeparatedByString:@"\n"];
        if (parts.count < 2) {
            [_menuToSelectPopup selectItemWithTitle:parameterValue ?: @""];
        } else {
            if (![_menuToSelectPopup selectItemWithIdentifier:parts[1]]) {
                [_menuToSelectPopup selectItemWithTitle:parts.firstObject];
            }
        }
    } else if (action == KEY_ACTION_TOGGLE_SETTING) {
        [_settingToTogglePopup reloadData];
        [_settingToTogglePopup selectItemWithIdentifier:parameterValue ?: @""];
    }

    if (_pasteSpecialViewController == nil) {
        _pasteSpecialViewController = [[iTermPasteSpecialViewController alloc] init];
        [_pasteSpecialViewController applyTerminalLayout];
    }

    [self updateViewsAnimated:NO secondary:secondary];

    if (!_profilePopup.isHidden) {
        [_profilePopup populateWithProfilesSelectingGuid:parameterValue ?: @""];
    }
    if (!_colorPresetsPopup.isHidden) {
        [_colorPresetsPopup loadColorPresetsSelecting:parameterValue ?: @""];
    }
    if (!_snippetsPopup.isHidden) {
        [_snippetsPopup populateWithSnippetsSelectingActionKey:parameterValue ?: @""];
    }
    if (!_selectionMovementUnit.isHidden) {
        [_selectionMovementUnit selectItemWithTag:[parameterValue ?: @"" integerValue]];
    }
    if (!_secondaryComboViewContainer.isHidden && !secondary) {
        [_sequenceTableViewController setActions:[parameterValue ?: @"" keyBindingActionsFromSequenceParameter]];
    }
    if (self.action == KEY_ACTION_PASTE_SPECIAL ||
        self.action == KEY_ACTION_PASTE_SPECIAL_FROM_SELECTION) {
        [_pasteSpecialViewController loadSettingsFromString:parameterValue ?: @""];
    } else {
        // Set a few defaults; otherwise everything is reasonable.
        _pasteSpecialViewController.numberOfSpacesPerTab = [iTermPreferences intForKey:kPreferenceKeyPasteSpecialSpacesPerTab];
        _pasteSpecialViewController.shouldRemoveNewlines = NO;
        _pasteSpecialViewController.shouldBase64Encode = NO;
        _pasteSpecialViewController.shouldWaitForPrompt = NO;
        _pasteSpecialViewController.shouldEscapeShellCharsWithBackslash = NO;
    }
    _pasteSpecialViewController.view.frame = _pasteSpecialViewController.view.bounds;
    _pasteSpecialViewController.delegate = self;
    NSRect theFrame = _pasteSpecialViewContainer.frame;
    CGFloat originalHeight = theFrame.size.height;
    theFrame.size = _pasteSpecialViewController.view.bounds.size;
    theFrame.origin.y -= (theFrame.size.height - originalHeight);
    _pasteSpecialViewContainer.frame = theFrame;
    if (_pasteSpecialViewController.view.superview == nil) {
        [_pasteSpecialViewContainer addSubview:_pasteSpecialViewController.view];
    }
    _applyMode = applyMode;
    [_applyButton selectItemWithTag:applyMode];
    [self updateError];
}

- (void)setAction:(KEY_ACTION)keyAction parameter:(NSString *)parameter applyMode:(iTermActionApplyMode)applyMode {
    [self setAction:keyAction];
    _parameterValue = [parameter copy];
    _applyMode = applyMode;
}

- (void)setAction:(int)action {
    if (action == KEY_ACTION_IR_FORWARD) {
        action = KEY_ACTION_IGNORE;
    }
    _action = action;
}

- (iTermAction *)unboundAction {
    return [[iTermAction alloc] initWithTitle:self.label
                                       action:self.action
                                    parameter:self.parameterValue
                                     escaping:self.escaping
                                    applyMode:self.applyMode
                                      version:[iTermAction currentVersion]];
}

#pragma mark - iTermShortcutInputViewDelegate

// Note: This is called directly by iTermHotKeyController when the action requires key remapping
// to be disabled so the shortcut can be input properly. In this case, |view| will be nil.
- (void)shortcutInputView:(iTermShortcutInputView *)view didReceiveKeyPressEvent:(NSEvent *)event {
    self.currentKeystroke = view.shortcut.keystroke;
    _okButton.enabled = [self shouldEnableOK];
}

- (void)setMode:(iTermEditKeyActionWindowControllerMode)mode {
    assert(NO);
}

#pragma mark - Private

- (void)updateViewsAnimated:(BOOL)animated secondary:(BOOL)secondary {
    switch (self.mode) {
        case iTermEditKeyActionWindowControllerModeUnbound:
            _keyboardShortcutLabel.stringValue = NSLocalizedString(@"Title:", @"Key binding action editor");
            if (self.titleIsInterpolated) {
                if (!_labelDelegate) {
                    _labelDelegate = [[iTermFunctionCallTextFieldDelegate alloc] initWithPathSource:[iTermVariableHistory pathSourceForContext:iTermVariablesSuggestionContextSession]
                                                                                        passthrough:self
                                                                                      functionsOnly:NO];
                }
                _actionTitleField.delegate = _labelDelegate;
            } else {
                _actionTitleField.delegate = self;
            }
            _actionTitleField.hidden = NO;
            _shortcutField.hidden = YES;
            break;
        case iTermEditKeyActionWindowControllerModeKeyboardShortcut:
            _keyboardShortcutLabel.stringValue = NSLocalizedString(@"Keyboard Shortcut:", @"Key binding action editor");
            _actionTitleField.hidden = YES;
            _shortcutField.hidden = NO;
            break;
    }

    const int tag = secondary ? _secondaryComboView.selectedTag : _comboView.selectedTag;
    iTermEditKeyActionWindowConfiguration *config = [[iTermEditKeyActionWindowConfiguration alloc] initWithTag:tag
                                                                                          functionCallDelegate:_functionCallDelegate
                                                                                    interpolatedStringDelegate:_interpolatedStringDelegate
                                                                                                       context:_suggestContext];
    _config = config;
    if (config.parameterPlaceholder) {
        [_parameter.cell setPlaceholderString:config.parameterPlaceholder];
    }
    if (config.parameterLabel) {
        _parameterLabel.stringValue = config.parameterLabel;
    }
    if (config.parameterValue) {
        _parameter.stringValue = config.parameterValue;
    }
    if (config.parameterDelegate.functionsOnly) {
        _functionCallDelegate = config.parameterDelegate;
        _functionCallDelegate.passthrough = self;
    } else {
        _functionCallDelegate = nil;
    }
    if (config.parameterDelegate && !config.parameterDelegate.functionsOnly) {
        _interpolatedStringDelegate = config.parameterDelegate;
        _interpolatedStringDelegate.passthrough = self;
    } else {
        _interpolatedStringDelegate = nil;
    }
    _parameter.delegate = config.parameterDelegate ?: self;
    [_parameter setHidden:config.parameterHidden];
    _helpButton.hidden = config.helpString == nil;
    [_parameterLabel setHidden:config.parameterLabelHidden];
    [_profilePopup setHidden:config.profilePopupHidden];
    if (!config.profilePopupHidden) {
        [_profilePopup populateWithProfilesSelectingGuid:config.parameterValue ?: @""];
    }
    [_selectionMovementUnit setHidden:config.selectionMovementUnitHidden];
    [_profileLabel setHidden:config.profileLabelHidden];
    [_menuToSelectPopup setHidden:config.menuToSelectPopupHidden];
    [_settingToTogglePopup setHidden:config.settingToTogglePopupHidden];
    _shortcutField.disableKeyRemapping = config.shortcutFieldDisableKeyRemapping;
    [_colorPresetsLabel setHidden:config.colorPresetsLabelHidden];
    [_colorPresetsPopup setHidden:config.colorPresetsPopupHidden];
    [_snippetsPopup setHidden:config.snippetsHidden];
    [self setPasteSpecialHidden:config.pasteSpecialHidden];
    if (!secondary) {
        if (config.showSecondary) {
            NSRect frame = _detail.frame;
            frame.origin.x = NSMaxX(_sequenceContainer.frame) + 8;
            _detail.frame = frame;

        } else {
            NSRect frame = _detail.frame;
            frame.origin.x = NSMinX(_sequenceContainer.frame);
            _detail.frame = frame;
        }
        _sequenceContainer.hidden = !config.showSecondary;
        _secondaryActionLabel.hidden = !config.showSecondary;
        _secondaryComboViewContainer.hidden = !config.showSecondary;
    }
    if (_sequenceTableViewController.hasSelection) {
        (void)[_secondaryComboView selectItemWithTag:_sequenceTableViewController.selectedItem.keyAction];
    }
    _secondaryActionLabel.labelEnabled = _sequenceTableViewController.hasSelection;
    _secondaryComboView.enabled = _sequenceTableViewController.hasSelection;
    if (!_sequenceTableViewController.hasSelection) {
        (void)[_secondaryComboView selectItemWithTag:-1];
    }
    _applyButton.hidden = config.applyHidden;
    if (config.applyHidden) {
        [_applyButton selectItemWithTag:iTermActionApplyModeCurrentSession];
    } else {
        [_applyButton sizeToFit];
        NSRect applyButtonFrame = _applyButton.frame;
        applyButtonFrame.origin.x = [self desiredMinXForApplyButton];
        applyButtonFrame.origin.y = [self desiredYOriginForApplyButton];
        applyButtonFrame.size.width = _comboViewContainer.frame.size.width;
        _applyButton.frame = applyButtonFrame;
        _applyButton.autoresizingMask = 0;
    }
    [self updateFrameAnimated:animated];
}

- (CGFloat)desiredMinXForApplyButton {
    return NSMinX(_shortcutField.frame) - NSMinX(_keyboardShortcutLabel.frame) - 4;
}

- (CGFloat)desiredYOriginForApplyButton {
    NSView *lowestView = [[[_detail subviews] filteredArrayUsingBlock:^BOOL(__kindof NSView *view) {
        return !view.isHidden && view != _applyButton;
    }] minWithBlock:^NSComparisonResult(__kindof NSView *lhs, __kindof NSView *rhs) {
        return [@(NSMinY(lhs.frame)) compare:@(NSMinY(rhs.frame))];
    }];
    CGFloat bottom;
    if (lowestView) {
        bottom = NSMinY(lowestView.frame);
    } else {
        NSRect actionFrame = [_detail convertRect:_comboViewContainer.bounds fromView:_comboViewContainer];
        bottom = NSMinY(actionFrame);
    }
    return bottom - _applyButton.frame.size.height - 4;
}

- (BOOL)anyAccessoryVisible {
    return (!_sequenceContainer.isHidden ||
            [self anyNonSequenceAccessoryVisible]);
}

- (BOOL)anyNonSequenceAccessoryVisible {
    return (!_parameter.isHidden ||
            !_profilePopup.isHidden ||
            !_menuToSelectPopup.isHidden ||
            !_settingToTogglePopup.isHidden ||
            !_colorPresetsPopup.isHidden ||
            !_snippetsPopup.isHidden ||
            !_pasteSpecialViewContainer.isHidden ||
            !_parameterLabel.isHidden ||
            !_selectionMovementUnit.isHidden);
}

- (void)updateFrameAnimated:(BOOL)animated {
    NSRect rect = self.window.frame;
    rect.size = [self desiredSize];
    if (animated) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.window setFrame:rect display:YES animate:YES];
        });
    } else {
        [self.window setFrame:rect display:YES animate:NO];
    }
}

//    Side margin                     Side margin
//    |                               |
//   |-|                             |-|
//   +---------------------------------+
//   |                                 |
//   |  Keyboard shortcut: [        ]  |
//   |             Action: [v Popup ]  |  _
//   |         Basic Accessory         |  _|-- Basic accessory height
//   |                                 |
//   |                  [Cancel] [OK]  |
//   +---------------------------------+
//      |---------------------------|
//      Normal width excluding margins
//
//   +---------------------------------+  -
//   |                                 |  |
//   |  Keyboard shortcut: [        ]  |  |
//   |             Action: [v Popup ]  |  |-- Height excluding accessory
//   |                                 |  |
//   |                   [Cancel] [OK] |  |
//   +---------------------------------+  -

- (NSSize)desiredSize {
    return NSMakeSize(self.desiredWidthExcludingMargins + sideMarginWidth,
                      self.desiredHeight);
}

- (CGFloat)desiredWidthExcludingMargins {
    CGFloat normalWidthExcludingMargins = 402;
    if (!_helpButton.isHidden) {
        normalWidthExcludingMargins += _helpButton.frame.size.width + 6;
    }
    if (!_secondaryComboViewContainer.isHidden) {
        return NSMaxX(_detail.frame) - NSMinX(_sequenceContainer.frame);
    }
    if (!_pasteSpecialViewContainer.hidden) {
        return MAX(normalWidthExcludingMargins,
                   _pasteSpecialViewController.view.frame.size.width);
    }
    if (!_parameter.isHidden) {
        return NSMaxX(_parameter.frame);
    }
    return normalWidthExcludingMargins;
}

- (CGFloat)desiredHeight {
    const CGFloat heightExcludingAccessory = 126;
    return heightExcludingAccessory + [self accessoryHeight];
}

- (CGFloat)accessoryHeight {
    CGFloat height = 0;
    if (!_applyButton.isHidden) {
        height += _applyButton.frame.size.height + 4;
    }
    if (![self anyAccessoryVisible]) {
        return height;
    }
    if (!_sequenceContainer.isHidden) {
        height += MAX(NSHeight(_sequenceContainer.frame), self.nonSequenceAccessoryHeight);
        return height;
    }
    return height + [self nonSequenceAccessoryHeight];
}

- (CGFloat)nonSequenceAccessoryHeight {
    if (![self anyNonSequenceAccessoryVisible]) {
        return 0;
    }
    if (!_parameter.isHidden) {
        if (_errorLabel.isHidden) {
            return NSHeight(_parameter.frame);
        } else {
            return NSMaxY(_parameter.frame) - NSMinY(_errorLabel.frame);
        }
    }
    if (!_pasteSpecialViewContainer.isHidden) {
        return _pasteSpecialViewController.view.frame.size.height;
    }
    const CGFloat basicAccessoryHeight = 31;
    return basicAccessoryHeight;
}

- (void)setPasteSpecialHidden:(BOOL)hidden {
    _pasteSpecialViewContainer.hidden = hidden;
}

- (BOOL)shouldEnableOK {
    switch (self.mode) {
        case iTermEditKeyActionWindowControllerModeUnbound:
            break;
        case iTermEditKeyActionWindowControllerModeKeyboardShortcut:
            if (!self.currentKeystroke) {
                return NO;
            }
            break;
    }
    return YES;
}

#pragma mark - Actions

- (IBAction)help:(id)sender {
    [[NSView castFrom:sender] it_showWarningWithMarkdown:_config.helpString];
}


- (IBAction)parameterDidChange:(id)sender {
    if (!_secondaryComboViewContainer.isHidden) {
        [_sequenceTableViewController reloadCurrentItem:[self secondaryAction]];
    }
    [self updateError];
}

- (IBAction)ok:(id)sender {
    switch (self.mode) {
        case iTermEditKeyActionWindowControllerModeUnbound:
            self.label = _actionTitleField.stringValue ?: @"";
            break;
        case iTermEditKeyActionWindowControllerModeKeyboardShortcut:
            if (!self.currentKeystroke) {
                DLog(@"Beep: no key combo");
                NSBeep();
                return;
            }
            break;
    }

    const KEY_ACTION keyAction = _comboView.selectedTag;
    const BOOL secondary = !_secondaryComboViewContainer.hidden;
    const BOOL hasApplyMode = !secondary && !_applyButton.isHidden;
    [self setAction:keyAction
          parameter:[self parameterValueForAction:keyAction]
          applyMode:hasApplyMode ? _applyButton.selectedTag : iTermActionApplyModeCurrentSession];

    self.ok = YES;
    [self.window.sheetParent endSheet:self.window];
}

- (NSString *)parameterValueForAction:(KEY_ACTION)action {
    switch (action) {
        case KEY_ACTION_SELECT_MENU_ITEM:
            if (_menuToSelectPopup.selectedIdentifier.length) {
              return [NSString stringWithFormat:@"%@\n%@",
                      _menuToSelectPopup.selectedTitle, _menuToSelectPopup.selectedIdentifier ?: @""];
            } else {
                return _menuToSelectPopup.selectedTitle;
            }
        case KEY_ACTION_TOGGLE_SETTING:
            return _settingToTogglePopup.selectedIdentifier;

        case KEY_ACTION_SPLIT_HORIZONTALLY_WITH_PROFILE:
        case KEY_ACTION_SPLIT_VERTICALLY_WITH_PROFILE:
        case KEY_ACTION_NEW_TAB_WITH_PROFILE:
        case KEY_ACTION_NEW_WINDOW_WITH_PROFILE:
        case KEY_ACTION_SET_PROFILE:
            return [[_profilePopup selectedItem] representedObject];

        case KEY_ACTION_LOAD_COLOR_PRESET:
            return [[_colorPresetsPopup selectedItem] title];

        case KEY_ACTION_SEND_SNIPPET:
            return [[_snippetsPopup selectedItem] representedObject];

        case KEY_ACTION_PASTE_SPECIAL_FROM_SELECTION:
        case KEY_ACTION_PASTE_SPECIAL:
            return [_pasteSpecialViewController stringEncodedSettings];

        case KEY_ACTION_MOVE_END_OF_SELECTION_LEFT:
        case KEY_ACTION_MOVE_END_OF_SELECTION_RIGHT:
        case KEY_ACTION_MOVE_START_OF_SELECTION_LEFT:
        case KEY_ACTION_MOVE_START_OF_SELECTION_RIGHT:
            return [@(_selectionMovementUnit.selectedTag) description];

        case KEY_ACTION_COMPOSE:
        default:
            return [_parameter stringValue];

        case KEY_ACTION_SEQUENCE:
            return [NSString parameterForKeyBindingActionSequence:_sequenceTableViewController.actions];
    }
    return @"";
}

- (IBAction)cancel:(id)sender {
    self.ok = NO;
    [self.window.sheetParent endSheet:self.window];
}

#pragma mark - iTermSearchableComboViewDelegate

- (iTermKeyBindingAction *)secondaryAction {
    const KEY_ACTION action = _secondaryComboView.selectedTag;
    return [iTermKeyBindingAction withAction:action
                                   parameter:[self parameterValueForAction:action]
                                    escaping:self.escaping
                                   applyMode:_applyButton.isHidden ? iTermActionApplyModeCurrentSession : _applyButton.selectedTag];
}

- (void)searchableComboView:(iTermSearchableComboView *)view didSelectItem:(iTermSearchableComboViewItem *)didSelectItem {
    if (view == _comboView) {
        _parameterValue = @"";
    }
    if (view == _comboView || view == _secondaryComboView) {
        NSString *guid = [[_profilePopup selectedItem] representedObject];
        [_profilePopup populateWithProfilesSelectingGuid:guid];
        [_colorPresetsPopup loadColorPresetsSelecting:_colorPresetsPopup.selectedItem.representedObject];
        [_snippetsPopup populateWithSnippetsSelectingActionKey:_snippetsPopup.selectedItem.representedObject];
        [_menuToSelectPopup reloadData];
        [_settingToTogglePopup reloadData];
        const BOOL secondary = (view == _secondaryComboView);
        if (secondary) {
            [_sequenceTableViewController setActionForCurrentItem:view.selectedTag];
        }
        [self updateViewsAnimated:YES secondary:secondary];
        if (!_secondaryComboViewContainer.isHidden) {
            [_sequenceTableViewController reloadCurrentItem:[self secondaryAction]];
        }
    } else if (view == _menuToSelectPopup.comboView && view != nil) {
        [_sequenceTableViewController reloadCurrentItem:[self secondaryAction]];
    } else if (view == _settingToTogglePopup.comboView && view != nil) {
        [_sequenceTableViewController reloadCurrentItem:[self secondaryAction]];
    }
    [self updateError];
}

- (void)updateSyntaxErrorsForCopyMode {
    iTermVimKeyParser *parser = [[iTermVimKeyParser alloc] initWithString:_parameter.stringValue];
    NSError *error = nil;
    [parser eventsWithError:&error];
    if (error) {
        self.error = error.localizedDescription;
    } else {
        self.error = nil;
    }
}

- (void)setError:(NSString *)errorString {
    if (!errorString) {
        _errorLabel.hidden = YES;

        NSRect frame = _parameter.frame;
        const CGFloat maxY = NSMaxY(_parameter.frame);
        frame.origin.y = NSMinY(_errorLabel.frame);
        frame.size.height = maxY - NSMinY(frame);
        _parameter.frame = frame;
    } else {
        _errorLabel.stringValue = errorString;
        _errorLabel.hidden = NO;

        NSRect frame = _parameter.frame;
        const CGFloat maxY = NSMaxY(_parameter.frame);
        frame.origin.y = NSMaxY(_errorLabel.frame) + 4;
        frame.size.height = maxY - NSMinY(frame);
        _parameter.frame = frame;
    }
}
#pragma mark - NSTextEditing

- (void)controlTextDidChange:(NSNotification *)notification {
    _okButton.enabled = [self shouldEnableOK];
    if (!_secondaryComboViewContainer.isHidden) {
        [_sequenceTableViewController reloadCurrentItem:[self secondaryAction]];
    }
    [self updateError];
}

- (void)updateError {
    if (_secondaryComboViewContainer.isHidden) {
        const KEY_ACTION action = _comboView.selectedTag;
        if (action == KEY_ACTION_COPY_MODE) {
            [self updateSyntaxErrorsForCopyMode];
        } else {
            self.error = nil;
        }
    } else {
        const KEY_ACTION action = _secondaryComboView.selectedTag;
        if (action == KEY_ACTION_COPY_MODE) {
            [self updateSyntaxErrorsForCopyMode];
        } else {
            self.error = nil;
        }
    }
}

#pragma mark - iTermKeyActionSequenceTableViewControllerDelegate

- (void)keyActionSequenceTableViewController:(iTermKeyActionSequenceTableViewController *)sender
                          selectionDidChange:(iTermKeyBindingAction *)action {
    [self updateViewsAnimated:NO secondary:YES];
    [self loadParameter:action.parameter
                 action:action.keyAction
              applyMode:action.applyMode
              secondary:YES];
}

- (void)keyActionSequenceTableViewControllerDidChange:(iTermKeyActionSequenceTableViewController *)sender
                                              actions:(NSArray<iTermKeyBindingAction *> * _Nonnull)actions {
    if (sender.hasSelection) {
        iTermKeyBindingAction *action = sender.selectedItem;
        [self loadParameter:action.parameter
                     action:action.keyAction
                  applyMode:_applyMode
                  secondary:YES];
    } else {
        [self updateViewsAnimated:NO secondary:YES];
    }
}

#pragma mark - iTermPasteSpecialViewControllerDelegate

- (void)pasteSpecialViewSpeedDidChange {
    [self parameterDidChange:nil];
}

- (void)pasteSpecialTransformDidChange {
    [self parameterDidChange:nil];
}

@end
