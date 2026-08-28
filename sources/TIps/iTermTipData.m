//
//  iTermTipData.m
//  iTerm2
//
//  Created by George Nachman on 6/19/15.
//
//

#import "iTermTipData.h"
#import "iTermTip.h"
#import "iTerm2SharedARC-Swift.h"

@implementation iTermTipData

+ (BOOL)it_shouldHideTipWithIdentifier:(NSString *)identifier details:(NSDictionary *)details {
    static NSSet<NSString *> *blockedIdentifiers;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        blockedIdentifiers = [NSSet setWithArray:@[
            @"0000",
            @"0003",
            @"0008",
            @"0010",
            @"0012",
            @"0039",
            @"0040",
            @"0053",
            @"0079",
            @"0084",
            @"0094",
            @"0104",
            @"0105",
            @"0122",
            @"0123",
        ]];
    });
    if ([blockedIdentifiers containsObject:identifier]) {
        return YES;
    }

    NSString *title = details[kTipTitleKey] ?: @"";
    NSString *body = details[kTipBodyKey] ?: @"";
    NSString *url = details[kTipUrlKey] ?: @"";
    NSArray<NSString *> *needles = @[
        @"Shell Integration",
        @"shell integration",
        @"Claude Code",
        @"Web Browser",
        @"browser sessions",
        @"browser session",
        @"documentation-web",
        @"SSH Integration",
        @"ssh Integration",
        @"SSH File Browser",
        @"shell_integration.html",
    ];
    for (NSString *needle in needles) {
        if ([title containsString:needle] || [body containsString:needle] || [url containsString:needle]) {
            return YES;
        }
    }
    return NO;
}

+ (NSDictionary *)allTips {
  // The keys in this dictionary are saved in user defaults and should not be changed or
  // recycled, or users will see the same tip more than once.
  NSDictionary *tips = @{
    // Big new features
            @"000": @{ kTipTitleKey: @"Tip of the Day",
                        kTipBodyKey: @"This window shows the Latterm tip of the day. It’ll appear every 24 hours to let you know about new features and hidden secrets. Hit “More Options” to view more tips or to stop getting them altogether." },
            @"0001": @{ kTipTitleKey: @"Timestamps",
                         kTipBodyKey: @"“View > Show Timestamps” shows the time (and date, if appropriate) when each line was last modified." },

            @"0002": @{ kTipTitleKey: @"Password Manager",
                        kTipBodyKey: @"Did you know Latterm has a password manager? Open it with “Window > Password Manager.” You can define a Trigger to open it for you at a password prompt in “Settings > Profiles > Advanced > Triggers.”" },
            @"0004": @{ kTipTitleKey: @"Undo Close",
                        kTipBodyKey: @"If you close a session, tab, or window by accident you can undo it with “Edit > Undo” (⌘Z). By default you have five seconds to undo, but you can adjust that timeout in “Settings > Profiles > Session.”" },

            @"0005": @{ kTipTitleKey: @"Annotations",
                         kTipBodyKey: @"Want to mark up your scrollback history? Right click on a selection and choose “Annotate Selection” to add a personal note to it. Use “View > Show Annotations” to show or hide them, and look in “Edit > Marks and Annotations” for more things you can do." },

            @"0006": @{ kTipTitleKey: @"Copy with Styles",
                         kTipBodyKey: @"Copy a selection with ⌥⌘C to include styles such as colors and fonts. You can make this the default action for Copy in “Settings > Advanced.”" },
            @"0007": @{ kTipTitleKey: @"Inline Images",
                        kTipBodyKey: @"Latterm can display images (even animated GIFs) inline.",
                        kTipUrlKey: @"https://iterm2.com/images.html" },

            @"0011" : @{ kTipTitleKey: @"Dynamic Profiles",
                         kTipBodyKey: @"Dynamic Profiles let you store your profiles as one or more JSON files. It’s great for batch creating and editing profiles.",
                         kTipUrlKey: @"https://iterm2.com/dynamic-profiles.html" },

            @"0012" : @{ kTipTitleKey: @"Advanced Paste",
                         kTipBodyKey: @"“Edit > Paste Special > Advanced Paste” lets you preview and edit text before you paste. You get to tweak options, like how to handle control codes, or even to base-64 encode before pasting." },

            @"0013" : @{ kTipTitleKey: @"Zoom",
                         kTipBodyKey: @"Ever wanted to focus on a block of lines without distraction, or limit Find to a single command’s output? Select the lines and choose “View > Zoom In on Selection.” The session’s contents will be temporarily replaced with the selection. Press “esc” to unzoom." },

    // Big but not new features
            @"0014": @{ kTipTitleKey: @"Semantic History",
                         kTipBodyKey: @"The “Semantic History” feature allows you to ⌘-click on a file or URL to open it.", },

            @"0015": @{ kTipTitleKey: @"Tmux Integration",
                        kTipBodyKey: @"If you use tmux, try running “tmux -CC” to get Latterm’s tmux integration mode. The tmux windows show up as native Latterm windows, and you can use Latterm’s keyboard shortcuts. It even works over ssh!",
                        kTipUrlKey: @"https://gitlab.com/gnachman/iterm2/wikis/TmuxIntegration" },

            @"0016": @{ kTipTitleKey: @"Triggers",
                        kTipBodyKey: @"Latterm can automatically perform actions you define when text matching a regular expression is received. For example, you can highlight text or show an alert box. Set it up in “Settings > Profiles > Advanced > Triggers.”",
                        kTipUrlKey: @"https://www.iterm2.com/documentation-triggers.html" },

            @"0017": @{ kTipTitleKey: @"Smart Selection",
                        kTipBodyKey: @"Quadruple click to perform Smart Selection. It figures out if you’re selecting a URL, filename, email address, etc. based on prioritized regular expressions.",
                        kTipUrlKey: @"https://www.iterm2.com/smartselection.html" },

            @"0018": @{ kTipTitleKey: @"Instant Replay",
                        kTipBodyKey: @"Press ⌥⌘B to step back in time in a terminal window. Use arrow keys to go frame by frame. Hold ⇧ and press arrow keys to go faster." },

            @"0019": @{ kTipTitleKey: @"Hotkey Window",
                        kTipBodyKey: @"You can have a terminal window open with a keystroke, even while in other apps. Click “Create a Dedicated Hotkey Window” in “Settings > Keys.”" },

    // Small things
            @"0020": @{ kTipTitleKey: @"Hotkey Window",
                        kTipBodyKey: @"Hotkey windows can stay open after losing focus. Turn it on in “Window > Pin Hotkey Window.”" },

            @"0021": @{ kTipTitleKey: @"Cursor Guide",
                        kTipBodyKey: @"The cursor guide is a horizontal line that follows your cursor. You can turn it on in “Settings > Profiles > Colors” or toggle it with the ⌥⌘; shortcut." },  // TODO Add learn more for escape sequence

            @"0023": @{ kTipTitleKey: @"Cursor Blink Rate",
                         kTipBodyKey: @"You can configure how quickly the cursor blinks in “Settings > Advanced.”" },

            @"0027": @{ kTipTitleKey: @"Bells",
                        kTipBodyKey: @"The dock icon shows a count of the number of bells rung and notifications posted since the app was last active." },

            @"0029": @{ kTipTitleKey: @"Find Your Cursor",
                        kTipBodyKey: @"Press ⌘/ to locate your cursor. It’s fun!" },

            @"0030": @{ kTipTitleKey: @"Customize Smart Selection",
                        kTipBodyKey: @"You can edit Smart Selection regular expressions in “Settings > Profiles > Advanced > Smart Selection.”",
                        kTipUrlKey: @"https://www.iterm2.com/smartselection.html" },

            @"0031": @{ kTipTitleKey: @"Smart Selection Actions",
                        kTipBodyKey: @"Assign an action to a Smart Selection rule in “Settings > Profiles > Advanced > Smart Selection > Edit Actions.” They go in the context menu and override semantic history on ⌘-click.",
                        kTipUrlKey: @"https://www.iterm2.com/smartselection.html" },

            @"0032": @{ kTipTitleKey: @"Visual Bell",
                        kTipBodyKey: @"If you want the visual bell to flash the whole screen instead of show a bell icon, you can turn that on in “Settings > Advanced.”" },

            @"0033": @{ kTipTitleKey: @"Tab Menu",
                        kTipBodyKey: @"Right click on a tab to change its color, close tabs after it, or to close all other tabs." },

            @"0034": @{ kTipTitleKey: @"Tags",
                        kTipBodyKey: @"You can assign tags to your profiles, and by clicking “Tags>” anywhere you see a list of profiles you can browse those tags." },

            @"0035": @{ kTipTitleKey: @"Tag Hierarchy",
                        kTipBodyKey: @"If you put a slash in a profile’s tag, that implicitly defines a hierarchy. You can see it in the Profiles menu as nested submenus." },

            @"0036": @{ kTipTitleKey: @"Downloads",
                        kTipBodyKey: @"Latterm can download files by base-64 encoding them. Click “Learn More” to download a shell script that makes it easy.",
                        kTipUrlKey: @"https://iterm2.com/download.sh" },

            @"0041": @{ kTipTitleKey: @"Paste File as Base64",
                        kTipBodyKey: @"Copy a file to the pasteboard in Finder and then use “Edit > Paste Special > Paste File Base64-Encoded” for easy uploads of binary files. Use ”base64 -D” (or -d on Linux) on the remote host to decode it." },

            @"0042": @{ kTipTitleKey: @"Split Panes",
                        kTipBodyKey: @"You can split a tab into multiple panes with ⌘D and ⇧⌘D." },

            @"0043": @{ kTipTitleKey: @"Adjust Split Panes",
                        kTipBodyKey: @"Resize split panes with the keyboard using ^⌘-Arrow Key." },

            @"0045": @{ kTipTitleKey: @"Edge Windows",
                        kTipBodyKey: @"You can tell your profile to create windows that are attached to one edge of the screen in “Settings > Profiles > Window.” You can resize them by dragging the edges." },

            @"0046": @{ kTipTitleKey: @"Tab Color",
                        kTipBodyKey: @"You can assign colors to tabs in “Settings > Profiles > Colors,” or in the View menu." },

            @"0047": @{ kTipTitleKey: @"Rectangular Selection",
                        kTipBodyKey: @"Hold ⌥⌘ while dragging to make a rectangular selection." },

            @"0048": @{ kTipTitleKey: @"Multiple Selection",
                        kTipBodyKey: @"Hold ⌘ while dragging to make multiple discontinuous selections." },

            @"0049": @{ kTipTitleKey: @"Dragging Panes",
                        kTipBodyKey: @"Hold ⇧⌥⌘ and drag a session into another session to create or change split panes." },

            @"0050": @{ kTipTitleKey: @"Cursor Boost",
                        kTipBodyKey: @"Adjust Cursor Boost in “Settings > Profiles > Colors” to make all colors more muted, except the cursor. Use a bright white cursor and it pops!" },

            @"0051": @{ kTipTitleKey: @"Minimum Contrast",
                        kTipBodyKey: @"Adjust “Minimum Contrast” in “Settings > Profiles > Colors” to ensure text is always legible regardless of text/background color combination." },

            @"0052": @{ kTipTitleKey: @"Tabs",
                        kTipBodyKey: @"Normally, new tabs appear at the end of the tab bar. There’s a setting in “Settings > Advanced” to place them next to your current tab." },

            @"0053": @{ kTipTitleKey: @"Base Conversion",
                        kTipBodyKey: @"Right-click on a number and the context menu shows it converted to hex or decimal as appropriate." },

            @"0054": @{ kTipTitleKey: @"Saved Searches",
                        kTipBodyKey: @"In “Settings > Keys” you can assign a keystroke to a search for a regular expression with the “Find Regular Expression…” action." },

            @"0055": @{ kTipTitleKey: @"Find URLs",
                        kTipBodyKey: @"Search for URLs using “Edit > Find > Find URLs.” Navigate search results with ⌘G and ⇧⌘G. Open the current selection with ⌥⌘O." },

            @"0056": @{ kTipTitleKey: @"Triggers",
                        kTipBodyKey: @"The “instant” checkbox in a Trigger allows it to fire while the cursor is on the same line as the text that matches your regular expression." },
            @"0057": @{ kTipTitleKey: @"Soft Boundaries",
                        kTipBodyKey: @"Turn on “Edit > Selection Respects Soft Boundaries” to recognize split pane dividers in programs like vi, emacs, and tmux so you can select multiple lines of text." },

            @"0058": @{ kTipTitleKey: @"Select Without Dragging",
                        kTipBodyKey: @"Single click where you want to start a selection and ⇧-click where you want it to end to select text without dragging." },

            @"0059" : @{ kTipTitleKey: @"Smooth Window Resizing",
                         kTipBodyKey: @"Hold ^ while resizing a window and it won’t snap to the character grid: you can make it any size you want." },

            @"0060" : @{ kTipTitleKey: @"Pasting Tabs",
                         kTipBodyKey: @"If you paste text containing tabs, you’ll be asked if you want to convert them to spaces. It’s handy at the shell prompt to avoid triggering filename completion." },

            @"0061" : @{ kTipTitleKey: @"Bell Silencing",
                         kTipBodyKey: @"Did you know? If the bell rings too often, you’ll be asked if you’d like to silence it temporarily. Latterm cares about your comfort." },

            @"0062" : @{ kTipTitleKey: @"Profile Search",
                         kTipBodyKey: @"Every list of profiles has a search field (e.g., in ”Settings > Profiles.”) You can use various operators to restrict your search query. Click “Learn More” for all the details.",
                         kTipUrlKey: @"https://iterm2.com/search_syntax.html" },

            @"0063": @{ kTipTitleKey: @"Color Schemes",
                        kTipBodyKey: @"The online color gallery features over one hundred beautiful color schemes you can download.",
                        kTipUrlKey: @"https://www.iterm2.com/colorgallery"},

            @"0064": @{ kTipTitleKey: @"ASCII/Non-Ascii Fonts",
                        kTipBodyKey: @"You can have a separate font for ASCII versus non-ASCII text. Enable it in “Settings > Profiles > Text.”" },

            @"0065": @{ kTipTitleKey: @"Coprocesses",
                        kTipBodyKey: @"A coprocess is a job, such as a shell script, that has a special relationship with a particular Latterm session. All output in a terminal window (that is, what you see on the screen) is also input to the coprocess. All output from the coprocess acts like text that the user is typing at the keyboard.",
                        kTipUrlKey: @"https://iterm2.com/coprocesses.html" },

            @"0066": @{ kTipTitleKey: @"Touch Bar Customization",
                        kTipBodyKey: @"You can customize the touch bar by selecting “View > Customize Touch Bar.” You can add a tab bar for full-screen mode, a user-customizable status button, and you can even define your own touch bar buttons in Settings > Keys." },

            @"0067": @{ kTipTitleKey: @"Ligatures",
                        kTipBodyKey: @"If you use a font that supports ligatures, you can enable ligature support in Settings > Profiles > Text." },

            @"0068": @{ kTipTitleKey: @"Floating Hotkey Window",
                        kTipBodyKey: @"New in 3.1: You can configure your hotkey window to appear over other apps’ full screen windows. Turn on “Floating Window” in “Settings > Profiles > Keys > Customize Hotkey Window.”" },

            @"0069": @{ kTipTitleKey: @"Multiple Hotkey Windows",
                        kTipBodyKey: @"New in 3.1: You can have multiple hotkey windows. Each profile can have one or more hotkeys." },

            @"0070": @{ kTipTitleKey: @"Double-Tap Hotkey",
                        kTipBodyKey: @"New in 3.1: You can configure a hotkey window to open on double-tap of a modifier in “Settings > Profiles > Keys > Customize Hotkey Window.”" },

            @"0071": @{ kTipTitleKey: @"Buried Sessions",
                        kTipBodyKey: @"You can “bury” a session with “Session > Bury Session.” It remains hidden until you restore it by selecting it from “Session > Buried Sessions > Your session.”" },

            @"0072": @{ kTipTitleKey: @"Python API",
                        kTipBodyKey: @"You can add custom behavior to Latterm using the Python API.",
                        kTipUrlKey: @"https://iterm2.com/python-api" },

            @"0073": @{ kTipTitleKey: @"Status Bar",
                        kTipBodyKey: @"You can add a configurable status bar to your terminal windows.",
                        kTipUrlKey: @"https://iterm2.com/3.3/documentation-status-bar.html" },

            @"0074": @{ kTipTitleKey: @"Minimal Theme",
                        kTipBodyKey: @"Try the “Minimal” and “Compact” themes to reduce visual clutter. You can set it in “Settings > Appearance > General.”" },

            @"0076": @{ kTipTitleKey: @"Session Titles",
                        kTipBodyKey: @"You can configure which elements are present in session titles in “Settings > Profiles > General > Title.”" },

            @"0077": @{ kTipTitleKey: @"Tab Icons",
                        kTipBodyKey: @"Tabs can show an icon indicating the current application. Configure it in “Settings > Profiles > General > Icon.”" },

            @"0078": @{ kTipTitleKey: @"Drag Window by Tab",
                        kTipBodyKey: @"Hold ⌥ while dragging a tab to move the window. This is useful in the Compact and Minimal themes, which have a very small area for dragging the window." },

            @"0079": @{ kTipTitleKey: @"Composer",
                        kTipBodyKey: @"Press ⇧⌘. to open the Composer. It gives you a scratchpad to edit a command before sending it to the shell." },
            
            @"0081": @{ kTipTitleKey: @"Composer Power Features",
                        kTipBodyKey: @"The composer supports multiple cursors. It also has the ability to send just one command out of a list, making it easy to walk through a list of commands one-by-one. Click the help button in the composer for details." },

            @"0082": @{ kTipTitleKey: @"Render Selection",
                        kTipBodyKey: @"Transform selected text into a readable view with the “Render Selection” command. Markdown and JSON receive specialized formatting, and horizontal scrolling makes log navigation easier." },

            @"0087": @{ kTipTitleKey: @"Named Marks",
                        kTipBodyKey: @"Navigate your command history effortlessly with “named marks” by assigning names to lines in the terminal." },

            @"0088": @{ kTipTitleKey: @"Font Assignments",
                        kTipBodyKey: @"You can assign specific fonts to Unicode ranges. Use 'Settings > Profiles > Text > Manage Special Exceptions' to manage it and to install a huge set of Powerline symbols." },

            @"0089": @{ kTipTitleKey: @"Disable Transparency",
                        kTipBodyKey: @"Maintain clarity in your active window while enjoying transparency in background windows by using 'View > Disable transparency in key window'." },

            @"0090": @{ kTipTitleKey: @"Leader Shortcut",
                        kTipBodyKey: @"Create two-keystroke shortcuts with a “leader”: a special keystroke that precedes a custom key binding." },

            @"0091": @{ kTipTitleKey: @"Sequence Binding",
                        kTipBodyKey: @"Execute a series of actions in order with a single shortcut using “sequence” key bindings." },

            @"0092": @{ kTipTitleKey: @"Export/Import Settings",
                        kTipBodyKey: @"Easily backup or transfer your Latterm settings using the Export/Import feature in “Settings > General > Settings”." },

            @"0093": @{ kTipTitleKey: @"Multi-Session Bindings",
                        kTipBodyKey: @"Apply key bindings uniformly across multiple sessions for consistent control in different tabs or windows." },

            @"0094": @{ kTipTitleKey: @"Inject Trigger",
                        kTipBodyKey: @"Simulate terminal input as if it were output from a running app with the “Inject” trigger." },

            @"0095": @{ kTipTitleKey: @"Trigger Status Bar",
                        kTipBodyKey: @"Easily manage your triggers using the new Triggers status bar component." },

            @"0096": @{ kTipTitleKey: @"Session Size in Tab",
                        kTipBodyKey: @"Display session size directly in tab titles for convenient at-a-glance information." },

            @"0097": @{ kTipTitleKey: @"Advanced Snippet Editing",
                        kTipBodyKey: @"Edit snippets in Advanced Paste by holding the ⌥ key, or open them in the composer with ⇧." },

            @"0098": @{ kTipTitleKey: @"HTML Logs",
                        kTipBodyKey: @"Save your terminal logs in HTML format for enhanced readability and sharing capabilities." },

            @"0099": @{ kTipTitleKey: @"ASCIICast Logs",
                        kTipBodyKey: @"Create and play back terminal recordings with ASCIICast logs, compatible with asciinema." },

            @"0100": @{ kTipTitleKey: @"Timestamped Logs",
                        kTipBodyKey: @"Include timestamps in your logs for better tracking and event correlation." },

            @"0101": @{ kTipTitleKey: @"LastPass & 1Password",
                        kTipBodyKey: @"Utilize LastPass or 1Password with the password manager by configuring it in the menu next to the search field." },

            @"0102": @{ kTipTitleKey: @"Password Manager Access",
                        kTipBodyKey: @"Access your password manager without authentication by adjusting the settings via the menu next to its search field." },

            @"0103": @{ kTipTitleKey: @"Password Generation",
                        kTipBodyKey: @"Generate strong, secure passwords using the password manager’s new password generation feature." },

            @"0106": @{ kTipTitleKey: @"Command Prompt Info",
                        kTipBodyKey: @"Get detailed information about commands by ⌘-clicking on the command prompt." },

            @"0107": @{ kTipTitleKey: @"tmux Integration",
                        kTipBodyKey: @"Use tmux integration for automatic key bindings that emulate tmux’s shortcuts, configurable via the Leader settings." },

            @"0108": @{ kTipTitleKey: @"tmux Clipboard Mirroring",
                        kTipBodyKey: @"Sync your tmux paste buffer with the local clipboard for seamless integration (requires tmux 3.4)." },

            @"0109": @{ kTipTitleKey: @"Multi-Cursor in Composer",
                        kTipBodyKey: @"Enhance your editing in the Composer with multiple cursors, created using ^⇧-up/down or ⌥-drag." },

            @"0110": @{ kTipTitleKey: @"Advanced Paste from Composer",
                        kTipBodyKey: @"Move content from the Composer to the Advanced Paste window with ⌥⌘V for additional editing options." },

            @"0111": @{ kTipTitleKey: @"Composer Search",
                        kTipBodyKey: @"Search within the Composer using ⌘F to quickly find specific text." },

            @"0112": @{ kTipTitleKey: @"Resize Composer",
                        kTipBodyKey: @"Adjust the Composer’s height to suit your needs by dragging its bottom edge." },

            @"0113": @{ kTipTitleKey: @"Explain Command",
                        kTipBodyKey: @"Learn more about your commands by ⌘-clicking in the Composer to open them in explainshell.com." },

            @"0114": @{ kTipTitleKey: @"Quick Command Send",
                        kTipBodyKey: @"Quickly send and remove commands in the Composer using ⌥⇧-enter." },

            @"0115": @{ kTipTitleKey: @"Queue Commands",
                        kTipBodyKey: @"Queue up a command in the Composer to be sent after the current command finishes with ⌥-Enter." },

            @"0116": @{ kTipTitleKey: @"Draggable Tip Window",
                        kTipBodyKey: @"Reposition the Tip of the Day window conveniently on your screen, as it is now draggable." },

            @"0119": @{ kTipTitleKey: @"Adjacent Timestamps",
                        kTipBodyKey: @"Timestamps can now be shown next to terminal content instead of overlapping. Configure it in “Settings > Profiles > Session > Timestamps”. Right-click on any line and select “Set Baseline for Relative Timestamps” to see time elapsed between lines." },

            @"0120": @{ kTipTitleKey: @"Pretty-Print JSON",
                        kTipBodyKey: @"Select a block of JSON text and choose “Edit > Replace Selection > Replace with Pretty-Printed JSON” to make it readable. Perfect for debugging API responses and log files." },

            @"0121": @{ kTipTitleKey: @"Command Palette",
                        kTipBodyKey: @"Open Quickly (⇧⌘O) is now a command palette! Just type the name of a menu item to activate it." },

// IMPORTANT: When updating this, also update it2tip
            };
  NSMutableDictionary *filteredTips = [NSMutableDictionary dictionary];
  [tips enumerateKeysAndObjectsUsingBlock:^(NSString *identifier, NSDictionary *details, BOOL *stop) {
      if (![self it_shouldHideTipWithIdentifier:identifier details:details]) {
          filteredTips[identifier] = details;
      }
  }];
  return filteredTips;
}

@end
