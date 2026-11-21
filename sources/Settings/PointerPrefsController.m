//
//  PointerPrefsController.m
//  iTerm
//
//  Created by George Nachman on 11/7/11.
//  Copyright (c) 2011 George Nachman. All rights reserved.
//

#import "FutureMethods.h"
#import "ITAddressBookMgr.h"
#import "NSPopUpButton+iTerm.h"
#import "NSTextField+iTerm.h"
#import "EventMonitorView.h"
#import "PointerController.h"
#import "PointerPrefsController.h"
#import "PreferencePanel.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermApplicationDelegate.h"
#import "iTermFunctionCallTextFieldDelegate.h"
#import "iTermPasteSpecialViewController.h"
#import "iTermUserDefaults.h"
#import "iTermWarning.h"

static NSString *kPointerActionsKey = @"PointerActions";  // Used in NSUserDefaults
static NSString *kActionKey = @"Action";  // Used within values
static NSString *kArgumentKey = @"Argument";  // Used within values
static NSString *kVersionKey = @"Version";
static NSString *kCommandKeyChar = @"c";
static NSString *kOptionKeyChar = @"o";
static NSString *kShiftKeyChar = @"s";
static NSString *kControlKeyChar = @"^";

#define kLeftButton 0
#define kRightButton 1
#define kMiddleButton 2

static const int kMinGestureTag = 10;
#define kThreeFingerTapGestureTag 10
#define kThreeFingerSwipeRightGestureTag 11
#define kThreeFingerSwipeLeftGestureTag 12
#define kThreeFingerSwipeUpGestureTag 13
#define kThreeFingerSwipeDownGestureTag 14
#define kForceTouchSingleClickTag 15

static NSString *kButtonSchema = @"Button";  // First field of action key
static NSString *kGestureSchema = @"Gesture";  // First field of action key

NSString *kForceTouchSingleClick = @"ForceTouchSingleClick";  // Single finger force touch
NSString *kThreeFingerClickGesture = @"ThreeFingerClick";  // Second field of action key (gesture type)
NSString *kThreeFingerSwipeRight = @"ThreeFingerSwipeRight";  // Second field of action key (gesture type)
NSString *kThreeFingerSwipeLeft = @"ThreeFingerSwipeLeft";  // Second field of action key (gesture type)
NSString *kThreeFingerSwipeUp = @"ThreeFingerSwipeUp";  // Second field of action key (gesture type)
NSString *kThreeFingerSwipeDown = @"ThreeFingerSwipeDown";  // Second field of action key (gesture type)

NSString *kPasteFromClipboardPointerAction = @"kPasteFromClipboardPointerAction";
NSString *kPasteFromSelectionPointerAction = @"kPasteFromSelectionPointerAction";
NSString *kOpenTargetPointerAction = @"kOpenTargetPointerAction";
NSString *kOpenTargetInBackgroundPointerAction = @"kOpenTargetInBackgroundPointerAction";
NSString *kSmartSelectionPointerAction = @"kSmartSelectionPointerAction";
NSString *kSmartSelectionIgnoringNewlinesPointerAction = @"kSmartSelectionIgnoringNewlinesPointerAction";
NSString *kContextMenuPointerAction = @"kContextMenuPointerAction";
NSString *kNextTabPointerAction = @"kNextTabPointerAction";
NSString *kPrevTabPointerAction = @"kPrevTabPointerAction";
NSString *kNextWindowPointerAction = @"kNextWindowPointerAction";
NSString *kPrevWindowPointerAction = @"kPrevWindowPointerAction";
NSString *kMovePanePointerAction = @"kMovePanePointerAction";
NSString *kSendEscapeSequencePointerAction = @"kSendEscapeSequencePointerAction";
NSString *kSendHexCodePointerAction = @"kSendHexCodePointerAction";
NSString *kSendTextPointerAction = @"kSendTextPointerAction";
NSString *kInvokeScriptFunction = @"kInvokeScriptFunction";
NSString *kSelectPaneLeftPointerAction = @"kSelectPaneLeftPointerAction";
NSString *kSelectPaneRightPointerAction = @"kSelectPaneRightPointerAction";
NSString *kSelectPaneAbovePointerAction = @"kSelectPaneAbovePointerAction";
NSString *kSelectPaneBelowPointerAction = @"kSelectPaneBelowPointerAction";
NSString *kNewWindowWithProfilePointerAction = @"kNewWindowWithProfilePointerAction";
NSString *kNewTabWithProfilePointerAction = @"kNewTabWithProfilePointerAction";
NSString *kNewVerticalSplitWithProfilePointerAction = @"kNewVerticalSplitWithProfilePointerAction";
NSString *kNewHorizontalSplitWithProfilePointerAction = @"kNewHorizontalSplitWithProfilePointerAction";
NSString *kSelectNextPanePointerAction = @"kSelectNextPanePointerAction";
NSString *kSelectPreviousPanePointerAction = @"kSelectPreviousPanePointerAction";
NSString *kExtendSelectionPointerAction = @"kExtendSelectionPointerAction";
NSString *kQuickLookAction = @"kQuickLookAction";
NSString *kIgnoreAction = @"kIgnoreAction";
NSString *kSelectMenuItemPointerAction = @"kSelectMenuItemPointerAction";
NSString *kCopyLinkAddressPointerAction = @"kCopyLinkAddressPointerAction";
NSString *kCopyOrPastePointerAction = @"kCopyOrPastePointerAction";

typedef enum {
    kNoArg,
    kEscPlusArg,
    kHexCodeArg,
    kTextArg,
    kProfileArg,
    kAdvancedPasteArg,
    kMenuItemArg,
    kScriptFunctionArg
} ArgumentType;

@interface NSString (PointerPrefsController)
- (NSComparisonResult)comparePointerActions:(NSString *)other;
@end

@interface NSDictionary (PointerPrefsController)
- (NSComparisonResult)comparePointerPrefsValue:(NSDictionary *)other;
@end

@interface PointerPrefsController (Private)
+ (NSDictionary *)dictForAction:(NSString *)action;
+ (NSString *)modCharsForMask:(int)modifiers;
+ (int)maskForModChars:(NSString *)modChars;
+ (NSString *)keyForButton:(int)button clicks:(int)clicks modifiers:(int)modifiers;
+ (NSString *)keyForGesture:(NSString *)gestureDescription modifiers:(int)modifiers;
+ (BOOL)keyIsButton:(NSString *)key;
+ (NSArray *)buttonKeyComponents:(NSString *)key;
+ (NSArray *)gestureKeyComponents:(NSString *)key;
+ (int)buttonForKey:(NSString *)key;
+ (int)numClicksForKey:(NSString *)key;
+ (NSString *)localizedNumClicks:(int)n;
+ (NSString *)localizedButtonNameForButtonNumber:(int)n;
+ (NSString *)localizedGestureNameForGestureIdentifier:(NSString *)ident;
+ (NSString *)localizedModifiers:(int)keyMods;
+ (NSDictionary *)localizedActionMap;
+ (NSString *)localizedActionForDict:(NSDictionary *)dict;
+ (NSString *)localizedActionForKey:(NSString *)key;
+ (NSString *)gestureIdentifierForKey:(NSString *)key;
+ (int)modifiersForKey:(NSString *)key;
+ (NSDictionary *)defaultActions;
+ (NSDictionary *)settings;
+ (void)setSettings:(NSDictionary *)newSettings;
+ (NSArray *)sortedKeys;
+ (NSString *)keyForRowIndex:(int)rowIndex;
+ (int)tagForGestureIdentifier:(NSString *)ident;
- (BOOL)okShouldBeEnabled;
- (void)editKey:(NSString *)key;
+ (BOOL)keyIsThreeFingerTap:(NSString *)key;
@end

@interface PointerPrefsController () <NSTableViewDataSource, NSTableViewDelegate>
@end

@implementation PointerPrefsController {
    IBOutlet NSTableView *tableView_;
    IBOutlet NSTableColumn *buttonColumn_;
    IBOutlet NSTableColumn *actionColumn_;

    IBOutlet NSPanel *panel_;
    IBOutlet NSTextField *editButtonLabel_;
    IBOutlet NSPopUpButton *editButton_;
    IBOutlet NSTextField *editModifiersLabel_;
    IBOutlet NSButton *editModifiersCommand_;
    IBOutlet NSButton *editModifiersOption_;
    IBOutlet NSButton *editModifiersShift_;
    IBOutlet NSButton *editModifiersControl_;
    IBOutlet NSTextField *editActionLabel_;
    IBOutlet NSPopUpButton *editAction_;
    IBOutlet NSTextField *editClickTypeLabel_;
    IBOutlet NSPopUpButton *editClickType_;
    IBOutlet NSTextField *editArgumentLabel_;
    IBOutlet NSPopUpButton *editArgumentButton_;
    IBOutlet NSTextField *editArgumentField_;

    IBOutlet NSButton *ok_;
    IBOutlet NSButton *remove_;
    NSButton *_addButton;
    NSButton *_editButton;
    NSButton *_loadDefaultsButton;
    __weak NSView *_bindingsContainer;
    iTermPasteSpecialViewController *_pasteSpecialViewController;
    IBOutlet NSView *_pasteSpecialViewContainer;

    IBOutlet iTermMenuItemPopupView *_menuItemPopupView;

    iTermFunctionCallTextFieldDelegate *_invocationDelegate;

    NSRect _initialFrame;
    NSRect _initialPasteContainerFrame;

    NSString *origKey_;
    int version_;
    BOOL _configured;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    tableView_.delegate = nil;
    tableView_.dataSource = nil;
}

+ (NSDictionary *)dictForAction:(NSString *)action {
    return [NSDictionary dictionaryWithObject:action forKey:kActionKey];
}

+ (NSString *)modCharsForMask:(int)modifiers
{
    NSMutableString *modStr = [NSMutableString string];
    if (modifiers & NSEventModifierFlagCommand) {
        [modStr appendString:kCommandKeyChar];
    }
    if (modifiers & NSEventModifierFlagOption) {
        [modStr appendString:kOptionKeyChar];
    }
    if (modifiers & NSEventModifierFlagShift) {
        [modStr appendString:kShiftKeyChar];
    }
    if (modifiers & NSEventModifierFlagControl) {
        [modStr appendString:kControlKeyChar];
    }
    return modStr;
}

+ (int)maskForModChars:(NSString *)modChars
{
    int mask = 0;
    if ([modChars rangeOfString:kCommandKeyChar].location != NSNotFound) {
        mask |= NSEventModifierFlagCommand;
    }
    if ([modChars rangeOfString:kOptionKeyChar].location != NSNotFound) {
        mask |= NSEventModifierFlagOption;
    }
    if ([modChars rangeOfString:kShiftKeyChar].location != NSNotFound) {
        mask |= NSEventModifierFlagShift;
    }
    if ([modChars rangeOfString:kControlKeyChar].location != NSNotFound) {
        mask |= NSEventModifierFlagControl;
    }
    return mask;
}

+ (NSString *)keyForButton:(int)button clicks:(int)clicks modifiers:(int)modifiers
{
    NSString *modStr = [PointerPrefsController modCharsForMask:modifiers];
    return [NSString stringWithFormat:@"%@,%d,%d,%@,", kButtonSchema, button, clicks, modStr];
}

+ (NSString *)keyForGesture:(NSString *)gestureDescription modifiers:(int)modifiers
{
    return [NSString stringWithFormat:@"%@,%@,%@,",
                kGestureSchema,
                gestureDescription,
                [PointerPrefsController modCharsForMask:modifiers]];
}

+ (BOOL)keyIsButton:(NSString *)key
{
    return [key hasPrefix:kButtonSchema];
}

+ (BOOL)keyIsThreeFingerTap:(NSString *)key
{
    if (![key hasPrefix:kGestureSchema]) {
        return NO;
    }
    NSArray *components = [PointerPrefsController gestureKeyComponents:key];
    NSString *gesture = [components objectAtIndex:1];
    return [gesture isEqualToString:kThreeFingerClickGesture];
}

+ (NSArray *)buttonKeyComponents:(NSString *)key
{
    // Parse string like "Button,1,2,cso,freeform text"
    // Field 1: "Button"
    // Field 2: Button number (0-maxint)
    // Field 3: Number of clicks (0-4)
    // Field 4: Modifiers mask, including c, o, s, and ^ optionally (cmd, opt, shift, ctrl).
    // Field 5: Arbitrary textual parameter [may be empty]
    NSArray *a = [key componentsSeparatedByString:@","];
    if (a.count == 5 && [[a objectAtIndex:0] isEqualToString:kButtonSchema]) {
        return a;
    } else {
        return nil;
    }
}

+ (NSArray *)gestureKeyComponents:(NSString *)key
{
    // Parse string like "Gesture,Three Finger Click,cso,free form text"
    // Field 1: "Gesture"
    // Field 2: Gesture identifier string
    // Field 3: Modifiers mask, including c, o, s, and ^ optionally (cmd, opt, shift, ctrl).
    // Field 4: Arbitrary textual parameter [may be empty]
    NSArray *a = [key componentsSeparatedByString:@","];
    if (a.count == 4 && [[a objectAtIndex:0] isEqualToString:kGestureSchema]) {
        return a;
    } else {
        return nil;
    }
}

+ (int)buttonForKey:(NSString *)key
{
    NSArray *parts = [PointerPrefsController buttonKeyComponents:key];
    if (parts) {
        return [[parts objectAtIndex:1] intValue];
    } else {
        return -1;
    }
}

+ (int)numClicksForKey:(NSString *)key
{
    NSArray *parts = [PointerPrefsController buttonKeyComponents:key];
    if (parts) {
        return [[parts objectAtIndex:2] intValue];
    } else {
        return -1;
    }
}

+ (NSString *)localizedNumClicks:(int)n
{
    switch (n) {
        case 1:
            return NSLocalizedString(@"single click", @"Mouse button or gesture");
        case 2:
            return NSLocalizedString(@"double click", @"Mouse button or gesture");
        case 3:
            return NSLocalizedString(@"triple click", @"Mouse button or gesture");
        case 4:
            return NSLocalizedString(@"quad click", @"Mouse button or gesture");
        default:
            return NSLocalizedString(@"(error)", @"Mouse button or gesture");  // shouldn't happen
    }
}

+ (NSString *)localizedButtonNameForButtonNumber:(int)n
{
    switch (n) {
        case -1:
            return NSLocalizedString(@"Unknown button", @"Mouse button or gesture");
        case kLeftButton:
            return NSLocalizedString(@"Left button", @"Mouse button or gesture");
        case kRightButton:
            return NSLocalizedString(@"Right button", @"Mouse button or gesture");
        case kMiddleButton:
            return NSLocalizedString(@"Middle button", @"Mouse button or gesture");
        default:
            return [NSString stringWithFormat:NSLocalizedString(@"Button #%d", @"Mouse button or gesture"), n+1];
    }
}

+ (NSDictionary *)gestureNamesDict
{
    NSDictionary *names = @{ kThreeFingerClickGesture: NSLocalizedString(@"Three-finger Tap", @"Mouse button or gesture"),
                             kThreeFingerSwipeRight: NSLocalizedString(@"Three-finger Swipe Right", @"Mouse button or gesture"),
                             kThreeFingerSwipeLeft: NSLocalizedString(@"Three-finger Swipe Left", @"Mouse button or gesture"),
                             kThreeFingerSwipeUp: NSLocalizedString(@"Three-finger Swipe Up", @"Mouse button or gesture"),
                             kThreeFingerSwipeDown: NSLocalizedString(@"Three-finger Swipe Down", @"Mouse button or gesture"),
                             kForceTouchSingleClick: NSLocalizedString(@"Force Touch Single Click", @"Mouse button or gesture") };
    return names;
}

+ (NSString *)localizedGestureNameForGestureIdentifier:(NSString *)ident
{
    NSDictionary *names = [PointerPrefsController gestureNamesDict];
    NSString *name = [names objectForKey:ident];
    if (name) {
        return name;
    } else {
        // Shouldn't happen
        return ident;
    }
}

+ (int)tagForGestureIdentifier:(NSString *)ident
{
    NSArray *keys = @[ kThreeFingerClickGesture,
                       kThreeFingerSwipeRight,
                       kThreeFingerSwipeLeft,
                       kThreeFingerSwipeUp,
                       kThreeFingerSwipeDown,
                       kForceTouchSingleClick ];

    NSUInteger i = [keys indexOfObject:ident];
    if (i == NSNotFound) {
        return -1;
    }
    return i + kMinGestureTag;
}

+ (NSString *)actionWithLocalizedName:(NSString *)localizedName
{
    NSDictionary *actionMap = [PointerPrefsController localizedActionMap];
    for (NSString *action in actionMap) {
        NSString *curName = [actionMap objectForKey:action];
        if ([curName isEqualToString:localizedName]) {
            return action;
        }
    }
    return [NSString stringWithFormat:@"Bad name: %@", localizedName];
}

+ (NSString *)gestureIdentifierForTag:(int)tag
{
    switch (tag) {
        case kThreeFingerTapGestureTag:
            return kThreeFingerClickGesture;
        case kThreeFingerSwipeRightGestureTag:
            return kThreeFingerSwipeRight;
        case kThreeFingerSwipeLeftGestureTag:
            return kThreeFingerSwipeLeft;
        case kThreeFingerSwipeUpGestureTag:
            return kThreeFingerSwipeUp;
        case kThreeFingerSwipeDownGestureTag:
            return kThreeFingerSwipeDown;
        case kForceTouchSingleClickTag:
            return kForceTouchSingleClick;
        default:
            return [NSString stringWithFormat:@"Bad tag %d", tag];
    }
}

+ (NSString *)localizedModifiers:(int)keyMods {
    return [NSString stringForModifiersWithMask:keyMods];
}

+ (NSDictionary *)localizedActionMap
{
    NSDictionary *names = [NSDictionary dictionaryWithObjectsAndKeys:
                           NSLocalizedString(@"Ignore", @"Pointer action"), kIgnoreAction,
                           NSLocalizedString(@"Invoke Script Function…", @"Pointer action"), kInvokeScriptFunction,
                           NSLocalizedString(@"Paste from Clipboard…", @"Pointer action"), kPasteFromClipboardPointerAction,
                           NSLocalizedString(@"Paste from Selection…", @"Pointer action"), kPasteFromSelectionPointerAction,
                           NSLocalizedString(@"Extend Selection", @"Pointer action"), kExtendSelectionPointerAction,
                           NSLocalizedString(@"Open URL/Semantic History", @"Pointer action"), kOpenTargetPointerAction,
                           NSLocalizedString(@"Open URL in background", @"Pointer action"), kOpenTargetInBackgroundPointerAction,
                           NSLocalizedString(@"Smart Selection", @"Pointer action"), kSmartSelectionPointerAction,
                           NSLocalizedString(@"Smart Selection Ignoring Newlines", @"Pointer action"), kSmartSelectionIgnoringNewlinesPointerAction,
                           NSLocalizedString(@"Open Context Menu", @"Pointer action"), kContextMenuPointerAction,
                           NSLocalizedString(@"Next Tab", @"Pointer action"), kNextTabPointerAction,
                           NSLocalizedString(@"Previous Tab", @"Pointer action"), kPrevTabPointerAction,
                           NSLocalizedString(@"Next Window", @"Pointer action"), kNextWindowPointerAction,
                           NSLocalizedString(@"Previous Window", @"Pointer action"), kPrevWindowPointerAction,
                           NSLocalizedString(@"Move Pane", @"Pointer action"), kMovePanePointerAction,
                           NSLocalizedString(@"Send Escape Sequence…", @"Pointer action"), kSendEscapeSequencePointerAction,
                           NSLocalizedString(@"Send Hex Code…", @"Pointer action"), kSendHexCodePointerAction,
                           NSLocalizedString(@"Send Text…", @"Pointer action"), kSendTextPointerAction,
                           NSLocalizedString(@"Select Pane Left", @"Pointer action"), kSelectPaneLeftPointerAction,
                           NSLocalizedString(@"Select Pane Right", @"Pointer action"), kSelectPaneRightPointerAction,
                           NSLocalizedString(@"Select Pane Above", @"Pointer action"), kSelectPaneAbovePointerAction,
                           NSLocalizedString(@"Select Pane Below", @"Pointer action"), kSelectPaneBelowPointerAction,
                           NSLocalizedString(@"New Window With Profile…", @"Pointer action"), kNewWindowWithProfilePointerAction,
                           NSLocalizedString(@"New Tab With Profile…", @"Pointer action"), kNewTabWithProfilePointerAction,
                           NSLocalizedString(@"New Vertical Split With Profile…", @"Pointer action"), kNewVerticalSplitWithProfilePointerAction,
                           NSLocalizedString(@"New Horizontal Split With Profile…", @"Pointer action"), kNewHorizontalSplitWithProfilePointerAction,
                           NSLocalizedString(@"QuickLook", @"Pointer action"), kQuickLookAction,
                           NSLocalizedString(@"Select Menu Item", @"Pointer action"), kSelectMenuItemPointerAction,
                           NSLocalizedString(@"Copy Link Address", @"Pointer action"), kCopyLinkAddressPointerAction,
                           NSLocalizedString(@"Select Next Pane", @"Pointer action"), kSelectNextPanePointerAction,
                           NSLocalizedString(@"Select Previous Pane", @"Pointer action"), kSelectPreviousPanePointerAction,
                           NSLocalizedString(@"Copy or Paste", @"Pointer action"), kCopyOrPastePointerAction,
                           nil];
    return names;
}

+ (ArgumentType)argumentTypeForAction:(NSString *)action
{
    NSDictionary *args = [NSDictionary dictionaryWithObjectsAndKeys:
                          @(kEscPlusArg), kSendEscapeSequencePointerAction,
                          @(kHexCodeArg), kSendHexCodePointerAction,
                          @(kTextArg), kSendTextPointerAction,
                          @(kScriptFunctionArg), kInvokeScriptFunction,
                          @(kProfileArg), kNewWindowWithProfilePointerAction,
                          @(kProfileArg), kNewTabWithProfilePointerAction,
                          @(kProfileArg), kNewVerticalSplitWithProfilePointerAction,
                          @(kProfileArg), kNewHorizontalSplitWithProfilePointerAction,
                          @(kAdvancedPasteArg), kPasteFromClipboardPointerAction,
                          @(kAdvancedPasteArg), kPasteFromSelectionPointerAction,
                          @(kMenuItemArg), kSelectMenuItemPointerAction,
                          nil];
    NSNumber *n = [args objectForKey:action];
    if (n) {
        return (ArgumentType) [n intValue];
    } else {
        return (ArgumentType) kNoArg;
    }
}

+ (NSString *)localizedActionForDict:(NSDictionary *)dict
{
    NSDictionary *names = [PointerPrefsController localizedActionMap];
    NSString *action = [dict objectForKey:kActionKey];
    NSString *name = nil;
    if (action) {
        name = [names objectForKey:action];
    }
    if (!name) {
        name = NSLocalizedString(@"(Unknown)", @"Unknown pointer action");
    }
    return name;
}

+ (NSString *)formattedLocalizedActionForDict:(NSDictionary *)dict {
    NSDictionary *names = [PointerPrefsController localizedActionMap];
    NSString *action = [dict objectForKey:kActionKey];
    NSString *argument = [dict objectForKey:kArgumentKey];
    NSString *name = nil;
    if (action) {
        name = [names objectForKey:action];
    }
    if (!name) {
        name = NSLocalizedString(@"(Unknown)", @"Unknown pointer action");
    }
    if (action) {
        switch ([PointerPrefsController argumentTypeForAction:action]) {
            case kNoArg:
                break;
            case kEscPlusArg:
                return [name stringByReplacingOccurrencesOfString:@"…"
                                                       withString:[NSString stringWithFormat:@" Esc + %@", argument]];
            case kHexCodeArg:
            case kTextArg:
            case kScriptFunctionArg:
                return [name stringByReplacingOccurrencesOfString:@"…"
                                                       withString:[NSString stringWithFormat:@" “%@”", argument]];
            case kProfileArg: {
                NSString *bookmarkName = [[[ProfileModel sharedInstance] bookmarkWithGuid:argument] objectForKey:KEY_NAME];
                if (!bookmarkName) {
                    bookmarkName = @"?";
                }
                return [name stringByReplacingOccurrencesOfString:@"…"
                                                       withString:[NSString stringWithFormat:@" “%@”", bookmarkName]];
            }
            case kAdvancedPasteArg: {
                if (argument.length) {
                    return [NSString stringWithFormat:@"%@: %@",
                            [name stringByReplacingOccurrencesOfString:@"…" withString:@""],
                            [iTermPasteSpecialViewController descriptionForCodedSettings:argument]];
                }
                break;
            }
            case kMenuItemArg: {
                NSArray *parts = [argument componentsSeparatedByString:@"\n"];
                NSString *title = parts.firstObject;
                if (!title.length) {
                    break;
                }
                return [NSString stringWithFormat:NSLocalizedString(@"Select Menu Item “%@”", @"Pointer action"), title];
            }
        }
    }

    return name;
}

+ (NSString *)localizedActionForKey:(NSString *)key
{
    NSDictionary *dict = [[PointerPrefsController settings] objectForKey:key];
    return [PointerPrefsController localizedActionForDict:dict];
}

+ (NSString *)gestureIdentifierForKey:(NSString *)key
{
    NSArray *parts = [PointerPrefsController gestureKeyComponents:key];
    if (parts) {
        return [parts objectAtIndex:1];
    } else {
        return nil;
    }
}

+ (int)modifiersForKey:(NSString *)key
{
    NSArray *parts;
    int i;
    if ([PointerPrefsController keyIsButton:key]) {
        parts = [PointerPrefsController buttonKeyComponents:key];
        i = 3;
    } else {
        parts = [PointerPrefsController gestureKeyComponents:key];
        i = 2;
    }
    if (parts) {
        return [PointerPrefsController maskForModChars:[parts objectAtIndex:i]];
    } else {
        return 0;
    }
}

+ (NSDictionary *)defaultSettings
{
    NSString* plistFile = [[NSBundle bundleForClass:[self class]] pathForResource:@"DefaultPointerActions"
                                                                           ofType:@"plist"];
    return [NSDictionary dictionaryWithContentsOfFile:plistFile];
}

+ (NSDictionary *)defaultActions
{
    NSMutableDictionary *temp = [NSMutableDictionary dictionaryWithDictionary:[PointerPrefsController defaultSettings]];
    if ([iTermPreferences boolForKey:kPreferenceKeyThreeFingerEmulatesMiddle]) {
        // Find all actions that use middle button and add corresponding three-finger gesture.
        for (NSString *key in [temp allKeys]) {
            if ([PointerPrefsController keyIsButton:key] &&
                [PointerPrefsController buttonForKey:key] == kMiddleButton) {
                NSDictionary *middleAction = [temp objectForKey:key];
                NSString *gestureKey = [PointerPrefsController keyForGesture:kThreeFingerClickGesture
                                                                   modifiers:[PointerPrefsController modifiersForKey:key]];
                [temp setObject:middleAction forKey:gestureKey];
            }
        }
    }
    return temp;
}

+ (NSDictionary *)settings
{
    NSDictionary *dict = [[iTermUserDefaults userDefaults] dictionaryForKey:kPointerActionsKey];
    if (!dict) {
        dict = [PointerPrefsController defaultActions];
        [[iTermUserDefaults userDefaults] setObject:dict forKey:kPointerActionsKey];
    }
    return dict;
}

+ (void)setSettings:(NSDictionary *)newSettings
{
    [[iTermUserDefaults userDefaults] setObject:newSettings forKey:kPointerActionsKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:kPointerPrefsChangedNotification
                                                        object:nil];
}

+ (NSArray *)sortedKeys
{
//    NSArray *keys = [[PointerPrefsController settings] keysSortedByValueUsingSelector:@selector(comparePointerPrefsValue:)];
    NSArray *keys = [[[PointerPrefsController settings] allKeys] sortedArrayUsingSelector:@selector(comparePointerActions:)];
    return keys;
}

- (NSView *)createBindingsView {
    NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 891, 334)];
    container.identifier = @"PointerBindingsCustomView";

    iTermSettingsEmbeddedScrollView *scrollView = [[iTermSettingsEmbeddedScrollView alloc] initWithFrame:NSMakeRect(20, 49, 851, 285)];
    scrollView.borderType = NSBezelBorder;
    scrollView.hasVerticalScroller = YES;
    scrollView.hasHorizontalScroller = NO;
    scrollView.autohidesScrollers = YES;
    scrollView.drawsBackground = YES;

    NSTableView *tableView = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 849, 283)];
    tableView.headerView = nil;
    tableView.allowsColumnReordering = NO;
    tableView.allowsMultipleSelection = NO;
    tableView.allowsExpansionToolTips = YES;

    NSTableColumn *actionCol = [[NSTableColumn alloc] initWithIdentifier:@"action"];
    actionCol.width = 525.5;
    actionCol.editable = NO;
    actionCol.headerCell.title = NSLocalizedString(@"Action", @"Pointer bindings column");
    [tableView addTableColumn:actionCol];

    NSTableColumn *buttonCol = [[NSTableColumn alloc] initWithIdentifier:@"button"];
    buttonCol.width = 279.5;
    buttonCol.editable = NO;
    buttonCol.headerCell.title = NSLocalizedString(@"Mouse Button/Trackpad Gesture", @"Pointer bindings column");
    [tableView addTableColumn:buttonCol];

    tableView.dataSource = self;
    tableView.delegate = self;
    scrollView.documentView = tableView;
    [container addSubview:scrollView];

    NSButton *addButton = [iTermSettingsControlFactory pushButton:@"Add" target:self action:@selector(add:)];
    addButton.imagePosition = NSNoImage;
    [container addSubview:addButton];

    NSButton *removeButton = [iTermSettingsControlFactory pushButton:@"Remove" target:self action:@selector(remove:)];
    removeButton.imagePosition = NSNoImage;
    [container addSubview:removeButton];

    NSButton *loadDefaultsButton = [iTermSettingsControlFactory pushButton:@"Load Defaults" target:self action:@selector(loadDefaults:)];
    loadDefaultsButton.imagePosition = NSNoImage;
    [container addSubview:loadDefaultsButton];

    tableView_ = tableView;
    actionColumn_ = actionCol;
    buttonColumn_ = buttonCol;
    _addButton = addButton;
    remove_ = removeButton;
    _loadDefaultsButton = loadDefaultsButton;

    // Build Edit Pointer Setting sheet panel programmatically.
    NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(196, 132, 451, 246)
                                                styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
                                                  backing:NSBackingStoreBuffered
                                                    defer:YES];
    panel.releasedWhenClosed = NO;
    NSView *panelContent = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 451, 246)];
    panel.contentView = panelContent;

    editButtonLabel_ = [iTermSettingsControlFactory label:@"Button/Gesture:"];
    editButtonLabel_.frame = NSMakeRect(17, 209, 100, 16);
    [panelContent addSubview:editButtonLabel_];

    editButton_ = [iTermSettingsControlFactory popupButtonWithPullsDown:NO
                                                                  width:306
                                                                 target:self
                                                                 action:@selector(buttonOrGestureChanged:)
                                                                  items:@[
        @[ @"Right Button", @1 ],
        @[ @"Middle Button", @2 ],
        @[ @"Button #4", @3 ],
        @[ @"Button #5", @4 ],
        @[ @"Button #6", @5 ],
        @[ @"Button #7", @6 ],
        @[ @"---" ],
        @[ @"Three-finger Tap", @10 ],
        @[ @"Three-finger Swipe Right", @11 ],
        @[ @"Three-finger Swipe Left", @12 ],
        @[ @"Three-finger Swipe Up", @13 ],
        @[ @"Three-finger Swipe Down", @14 ],
        @[ @"---" ],
        @[ @"Force Touch", @15 ]
    ]];
    editButton_.frame = NSMakeRect(127, 202, 306, 26);
    [panelContent addSubview:editButton_];

    editClickTypeLabel_ = [iTermSettingsControlFactory label:@"Click Type:"];
    editClickTypeLabel_.frame = NSMakeRect(49, 181, 71, 16);
    [panelContent addSubview:editClickTypeLabel_];

    editClickType_ = [iTermSettingsControlFactory popupButtonWithPullsDown:NO
                                                                     width:306
                                                                    target:self
                                                                    action:@selector(clicksChanged:)
                                                                     items:@[
        @[ @"Single Click", @1 ],
        @[ @"Double Click", @2 ],
        @[ @"Triple Click", @3 ],
        @[ @"Quad Click", @4 ]
    ]];
    editClickType_.frame = NSMakeRect(127, 174, 306, 26);
    [panelContent addSubview:editClickType_];

    editModifiersLabel_ = [iTermSettingsControlFactory label:@"Modifiers:"];
    editModifiersLabel_.frame = NSMakeRect(56, 156, 65, 16);
    [panelContent addSubview:editModifiersLabel_];

    editModifiersCommand_ = [iTermSettingsControlFactory checkbox:@"⌘" target:nil action:nil toolTip:nil];
    editModifiersCommand_.frame = NSMakeRect(128, 153, 42, 18);
    [panelContent addSubview:editModifiersCommand_];

    editModifiersOption_ = [iTermSettingsControlFactory checkbox:@"⌥" target:nil action:nil toolTip:nil];
    editModifiersOption_.frame = NSMakeRect(174, 153, 42, 18);
    [panelContent addSubview:editModifiersOption_];

    editModifiersShift_ = [iTermSettingsControlFactory checkbox:@"⇧" target:nil action:nil toolTip:nil];
    editModifiersShift_.frame = NSMakeRect(223, 153, 42, 18);
    [panelContent addSubview:editModifiersShift_];

    editModifiersControl_ = [iTermSettingsControlFactory checkbox:@"^" target:nil action:nil toolTip:nil];
    editModifiersControl_.frame = NSMakeRect(268, 153, 42, 18);
    [panelContent addSubview:editModifiersControl_];

    EventMonitorView *eventMonitor = [[EventMonitorView alloc] initWithFrame:NSMakeRect(130, 118, 300, 29)
                                                                pointerPrefs:self];
    [panelContent addSubview:eventMonitor];

    editActionLabel_ = [iTermSettingsControlFactory label:@"Action:"];
    editActionLabel_.frame = NSMakeRect(74, 93, 47, 16);
    [panelContent addSubview:editActionLabel_];

    editAction_ = [iTermSettingsControlFactory popupButtonWithPullsDown:NO
                                                                  width:308
                                                                 target:self
                                                                 action:@selector(actionChanged:)
                                                                  items:@[]];
    editAction_.frame = NSMakeRect(125, 86, 308, 26);
    [panelContent addSubview:editAction_];

    editArgumentLabel_ = [iTermSettingsControlFactory label:@"Argument:"];
    editArgumentLabel_.frame = NSMakeRect(55, 63, 68, 16);
    [panelContent addSubview:editArgumentLabel_];

    editArgumentButton_ = [iTermSettingsControlFactory popupButtonWithPullsDown:NO
                                                                          width:308
                                                                         target:nil
                                                                         action:nil
                                                                          items:@[]];
    editArgumentButton_.frame = NSMakeRect(126, 57, 308, 26);
    editArgumentButton_.hidden = YES;
    [panelContent addSubview:editArgumentButton_];

    editArgumentField_ = [iTermSettingsControlFactory textFieldWithPlaceholder:nil
                                                                         width:302
                                                                        target:nil
                                                                        action:nil
                                                                      delegate:nil];
    editArgumentField_.frame = NSMakeRect(128, 60, 302, 22);
    [panelContent addSubview:editArgumentField_];

    _pasteSpecialViewContainer = [[NSView alloc] initWithFrame:NSMakeRect(130, 60, 300, 21)];
    _pasteSpecialViewContainer.hidden = YES;
    [panelContent addSubview:_pasteSpecialViewContainer];

    _menuItemPopupView = [[iTermMenuItemPopupView alloc] initWithFrame:NSMakeRect(125, 60, 308, 23)];
    _menuItemPopupView.hidden = YES;
    [panelContent addSubview:_menuItemPopupView];

    NSButton *cancelButton = [iTermSettingsControlFactory pushButton:@"Cancel" target:self action:@selector(cancel:)];
    cancelButton.keyEquivalent = @"\033";
    cancelButton.frame = NSMakeRect(272, 12, 82, 32);
    [panelContent addSubview:cancelButton];

    ok_ = [iTermSettingsControlFactory pushButton:@"OK" target:self action:@selector(ok:)];
    ok_.keyEquivalent = @"\r";
    ok_.frame = NSMakeRect(354, 12, 82, 32);
    [panelContent addSubview:ok_];

    panel_ = panel;
    [self configurePointerBindings];
    return container;
}

- (void)awakeFromNib
{
    [self configurePointerBindings];
}

- (void)configurePointerBindings
{
    if (_configured) {
        return;
    }
    _configured = YES;
    [tableView_ setDoubleAction:@selector(tableViewRowDoubleClicked:)];
    [tableView_ setTarget:self];
    tableView_.columnAutoresizingStyle = NSTableViewUniformColumnAutoresizingStyle;
    tableView_.usesAlternatingRowBackgroundColors = YES;
    tableView_.rowHeight = 22;
    for (NSTableColumn *column in tableView_.tableColumns) {
        column.resizingMask = NSTableColumnAutoresizingMask | NSTableColumnUserResizingMask;
    }

    NSScrollView *oldScrollView = tableView_.enclosingScrollView;
    NSView *container = oldScrollView.superview;
    _bindingsContainer = container;
    container.identifier = @"PointerBindingsCustomView";
    container.autoresizesSubviews = NO;
    container.postsFrameChangedNotifications = YES;
    if (container) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(bindingsContainerFrameDidChange:)
                                                     name:NSViewFrameDidChangeNotification
                                                   object:container];
    }

    if (oldScrollView && ![oldScrollView isKindOfClass:[iTermSettingsEmbeddedScrollView class]]) {
        iTermSettingsEmbeddedScrollView *embedded = [[iTermSettingsEmbeddedScrollView alloc] initWithFrame:oldScrollView.frame];
        embedded.borderType = NSBezelBorder;
        embedded.hasVerticalScroller = YES;
        embedded.hasHorizontalScroller = NO;
        embedded.autohidesScrollers = YES;
        embedded.drawsBackground = YES;
        [tableView_ removeFromSuperview];
        embedded.documentView = tableView_;
        [oldScrollView removeFromSuperview];
        [container addSubview:embedded];
    }

    for (NSView *view in container.subviews) {
        if (![view isKindOfClass:NSButton.class]) { continue; }
        NSButton *button = (NSButton *)view;
        const BOOL add = button.action == @selector(add:);
        const BOOL remove = button.action == @selector(remove:);
        if (add || remove) {
            button.image = nil;
            button.imagePosition = NSNoImage;
            button.title = add ? NSLocalizedString(@"Add", @"Mouse binding action") : NSLocalizedString(@"Remove", @"Mouse binding action");
            button.bezelStyle = NSBezelStyleRounded;
            if (add) {
                _addButton = button;
            } else {
                remove_ = button;
            }
        } else if (button.action == @selector(loadDefaults:)) {
            button.bezelStyle = NSBezelStyleRounded;
            _loadDefaultsButton = button;
        }
    }

    if (!_editButton && container) {
        NSButton *editButton = [[NSButton alloc] initWithFrame:NSZeroRect];
        editButton.title = NSLocalizedString(@"Edit…", @"Mouse binding action");
        editButton.bezelStyle = NSBezelStyleRounded;
        editButton.imagePosition = NSNoImage;
        editButton.font = _addButton.font ?: [NSFont systemFontOfSize:[NSFont systemFontSize]];
        editButton.target = self;
        editButton.action = @selector(editSelected:);
        [container addSubview:editButton];
        _editButton = editButton;
    }

    [self updateActionButtonStates];
    [self layoutBindingsContainer];
    [self normalizeEditPanelLayout];

    NSArray *actions = [[[PointerPrefsController localizedActionMap] allValues] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    [editAction_ addItemsWithTitles:actions];
}

- (void)updateActionButtonStates {
    const BOOL selected = [tableView_ numberOfSelectedRows] > 0;
    self.hasSelection = selected;
    _editButton.enabled = selected;
    remove_.enabled = selected;
}

- (void)bindingsContainerFrameDidChange:(NSNotification *)notification {
    [self layoutBindingsContainer];
}

- (void)layoutBindingsContainer {
    NSView *container = _bindingsContainer ?: tableView_.enclosingScrollView.superview;
    NSScrollView *scrollView = tableView_.enclosingScrollView;
    if (!container || !scrollView) {
        return;
    }
    const CGFloat width = MAX(180, NSWidth(container.bounds));
    const CGFloat height = MAX(140, NSHeight(container.bounds));
    const CGFloat buttonHeight = 28;
    const CGFloat gap = 8;

    NSArray<NSButton *> *leftButtons = @[];
    NSMutableArray<NSButton *> *tempLeft = [NSMutableArray array];
    for (id candidate in @[_addButton ?: [NSNull null], _editButton ?: [NSNull null], remove_ ?: [NSNull null]]) {
        if ([candidate isKindOfClass:NSButton.class]) {
            [tempLeft addObject:candidate];
        }
    }
    leftButtons = tempLeft;

    CGFloat leftX = 0;
    for (NSButton *button in leftButtons) {
        const CGFloat btnW = MAX(68, ceil(button.fittingSize.width) + 12);
        button.frame = NSMakeRect(leftX, 0, btnW, buttonHeight);
        button.autoresizingMask = NSViewMaxXMargin | NSViewMaxYMargin;
        leftX += btnW + gap;
    }

    CGFloat buttonAreaHeight = buttonHeight;
    if (_loadDefaultsButton) {
        const CGFloat defaultsW = MIN(width, MAX(96, ceil(_loadDefaultsButton.fittingSize.width) + 12));
        if (leftX + 4 + defaultsW <= width) {
            _loadDefaultsButton.frame = NSMakeRect(width - defaultsW, 0, defaultsW, buttonHeight);
        } else {
            // Stack left buttons above Load Defaults in ultra-narrow viewports.
            for (NSButton *button in leftButtons) {
                NSRect f = button.frame;
                f.origin.y = buttonHeight + 6;
                button.frame = f;
            }
            _loadDefaultsButton.frame = NSMakeRect(0, 0, defaultsW, buttonHeight);
            buttonAreaHeight = buttonHeight * 2 + 6;
        }
        _loadDefaultsButton.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin;
    }

    const CGFloat tableY = buttonAreaHeight + 10;
    const CGFloat tableH = MAX(80, height - tableY);
    scrollView.frame = NSMakeRect(0, tableY, width, tableH);
    scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
}

- (void)normalizeEditPanelLayout {
    NSView *content = panel_.contentView;
    if (!content) {
        return;
    }
    const CGFloat labelX = 16;
    const CGFloat labelW = 104;
    const CGFloat controlX = 128;
    const CGFloat controlW = MAX(220, NSWidth(content.bounds) - controlX - 20);

    for (NSTextField *label in @[editButtonLabel_ ?: [NSNull null],
                                 editClickTypeLabel_ ?: [NSNull null],
                                 editModifiersLabel_ ?: [NSNull null],
                                 editActionLabel_ ?: [NSNull null],
                                 editArgumentLabel_ ?: [NSNull null]]) {
        if (![label isKindOfClass:NSTextField.class]) { continue; }
        label.alignment = NSTextAlignmentRight;
        NSRect f = label.frame;
        f.origin.x = labelX;
        f.size.width = labelW;
        label.frame = f;
    }

    for (NSView *ctrl in @[editButton_ ?: [NSNull null],
                           editClickType_ ?: [NSNull null],
                           editAction_ ?: [NSNull null],
                           editArgumentButton_ ?: [NSNull null],
                           editArgumentField_ ?: [NSNull null],
                           _pasteSpecialViewContainer ?: [NSNull null],
                           _menuItemPopupView ?: [NSNull null]]) {
        if (![ctrl isKindOfClass:NSView.class]) { continue; }
        NSRect f = ctrl.frame;
        f.origin.x = controlX;
        f.size.width = controlW;
        ctrl.frame = f;
    }

    for (NSView *sub in content.subviews) {
        if ([NSStringFromClass(sub.class) isEqualToString:@"EventMonitorView"]) {
            NSRect f = sub.frame;
            f.origin.x = controlX;
            f.size.width = controlW;
            sub.frame = f;
        }
    }
}

+ (NSString *)keyForRowIndex:(int)rowIndex
{
    NSArray *sortedKeys = [PointerPrefsController sortedKeys];
    NSString *key = [sortedKeys objectAtIndex:rowIndex];
    return key;
}

+ (NSString *)argumentWithButton:(int)buttonNumber
                       numClicks:(int)numClicks
                       modifiers:(int)modMask {
    NSString *key = [PointerPrefsController keyForButton:buttonNumber
                                                  clicks:numClicks
                                               modifiers:modMask];
    NSDictionary *settings = [PointerPrefsController settings];
    NSDictionary *setting = [settings objectForKey:key];
    return [setting objectForKey:kArgumentKey];
}

+ (BOOL)useCompatibilityEscapingWithButton:(int)buttonNumber
                                 numClicks:(int)numClicks
                                 modifiers:(int)modMask {
    NSString *key = [PointerPrefsController keyForButton:buttonNumber
                                                  clicks:numClicks
                                               modifiers:modMask];
    NSDictionary *settings = [PointerPrefsController settings];
    NSDictionary *setting = [settings objectForKey:key];
    return [[setting objectForKey:kVersionKey] intValue] == 0;
}

+ (NSString *)actionWithButton:(int)buttonNumber
                     numClicks:(int)numClicks
                     modifiers:(int)modMask
{
    NSString *key = [PointerPrefsController keyForButton:buttonNumber
                                                  clicks:numClicks
                                               modifiers:modMask];
    DLog(@"Look up key %@", key);
    NSDictionary *settings = [PointerPrefsController settings];
    NSDictionary *setting = [settings objectForKey:key];
    NSString *action = [setting objectForKey:kActionKey];
    return action;
}

+ (NSString *)actionForTapWithTouches:(int)numTouches
                            modifiers:(int)modMask
{
    NSString *gesture = @"";
    if (numTouches == 3) {
        gesture = kThreeFingerClickGesture;
    } else {
        return nil;
    }
    return [PointerPrefsController actionForGesture:gesture modifiers:modMask];
}

+ (NSString *)argumentForTapWithTouches:(int)numTouches
                              modifiers:(int)modMask
{
    NSString *gesture = @"";
    if (numTouches == 3) {
        gesture = kThreeFingerClickGesture;
    } else {
        return nil;
    }
    return [PointerPrefsController argumentForGesture:gesture modifiers:modMask];
}

+ (BOOL)useCompatibilityEscapingForTapWithTouches:(int)numTouches
                                        modifiers:(int)modMask {
    NSString *gesture = @"";
    if (numTouches == 3) {
        gesture = kThreeFingerClickGesture;
    } else {
        return NO;
    }
    return [PointerPrefsController useCompatibilityEscapingForGesture:gesture modifiers:modMask];
}

+ (NSString *)actionForGesture:(NSString *)gesture
                     modifiers:(int)modMask {
    NSString *key;
    key = [PointerPrefsController keyForGesture:gesture
                                      modifiers:modMask];
    DLog(@"Look up action for gesture %@", key);
    NSDictionary *settings = [PointerPrefsController settings];
    NSDictionary *setting = [settings objectForKey:key];
    return [setting objectForKey:kActionKey];
}

+ (BOOL)useCompatibilityEscapingForGesture:(NSString *)gesture
                                 modifiers:(int)modMask {
    NSString *key;
    key = [PointerPrefsController keyForGesture:gesture
                                      modifiers:modMask];
    DLog(@"Look up use compatibility escaping for gesture %@", key);
    NSDictionary *settings = [PointerPrefsController settings];
    NSDictionary *setting = [settings objectForKey:key];
    return [[setting objectForKey:kVersionKey] intValue] == 0;
}

+ (NSString *)argumentForGesture:(NSString *)gesture
                       modifiers:(int)modMask {
    NSString *key;
    key = [PointerPrefsController keyForGesture:gesture
                                      modifiers:modMask];
    NSDictionary *settings = [PointerPrefsController settings];
    NSDictionary *setting = [settings objectForKey:key];
    return [setting objectForKey:kArgumentKey];
}

+ (BOOL)compatibilityEscapingForGesture:(NSString *)gesture
                              modifiers:(NSEventModifierFlags)modMask {
    NSString *key;
    key = [PointerPrefsController keyForGesture:gesture
                                      modifiers:modMask];
    NSDictionary *settings = [PointerPrefsController settings];
    NSDictionary *setting = [settings objectForKey:key];
    return [[setting objectForKey:kVersionKey] intValue] == 0;
}

+ (BOOL)haveThreeFingerTapEvents
{
    for (NSString *key in [PointerPrefsController sortedKeys]) {
        if ([PointerPrefsController keyIsThreeFingerTap:key]) {
            return YES;
        }
    }
    return NO;
}

#pragma mark NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView
{
    return [[PointerPrefsController settings] count];
}

+ (NSString *)localizedButton:(int)buttonNumber numClicks:(int)clicks modifiers:(int)modFlags
{
    NSString *button = [PointerPrefsController localizedButtonNameForButtonNumber:buttonNumber];
    NSString *numClicks = [PointerPrefsController localizedNumClicks:clicks];
    NSString *modifiers = [PointerPrefsController localizedModifiers:modFlags];
    if ([modifiers length]) {
        modifiers = [modifiers stringByAppendingString:@" + "];
    }
    return [NSString stringWithFormat:@"%@%@ %@", modifiers, button, numClicks];
}

+ (NSString *)localizedButtonKey:(NSString *)key
{
    return [PointerPrefsController localizedButton:[PointerPrefsController buttonForKey:key]
                                         numClicks:[PointerPrefsController numClicksForKey:key]
                                         modifiers:[PointerPrefsController modifiersForKey:key]];
}

- (void)setModifierButtons:(int)modMask
{
    [editModifiersCommand_ setState:(modMask & NSEventModifierFlagCommand) ? NSControlStateValueOn : NSControlStateValueOff];
    [editModifiersOption_ setState:(modMask & NSEventModifierFlagOption) ? NSControlStateValueOn : NSControlStateValueOff];
    [editModifiersShift_ setState:(modMask & NSEventModifierFlagShift) ? NSControlStateValueOn : NSControlStateValueOff];
    [editModifiersControl_ setState:(modMask & NSEventModifierFlagControl) ? NSControlStateValueOn : NSControlStateValueOff];
}

- (void)setButtonNumber:(int)buttonNumber clickCount:(int)clickCount modifiers:(int)modMask
{
    DLog(@"PointerPrefsController setButtonNumber:%d clickCount:%d modifiers:0x%x",
         buttonNumber, clickCount, modMask);
    if (buttonNumber >= 1 && clickCount > 0 && clickCount < 5) {
        [editButton_ selectItemWithTag:buttonNumber];
        [editClickType_ selectItemWithTag:clickCount];
        [self setModifierButtons:modMask];
        [self buttonOrGestureChanged:nil];
    }
}

- (void)setGesture:(NSString *)gesture modifiers:(int)modMask
{
    [editButton_ selectItemWithTag:[PointerPrefsController tagForGestureIdentifier:gesture]];
    [self setModifierButtons:modMask];
    [self buttonOrGestureChanged:nil];
}

- (id)tableView:(NSTableView *)aTableView
    objectValueForTableColumn:(NSTableColumn *)aTableColumn
    row:(NSInteger)rowIndex {
    NSString *key = [PointerPrefsController keyForRowIndex:rowIndex];
    NSDictionary *action = [[PointerPrefsController settings] objectForKey:key];
    BOOL isButton = [PointerPrefsController keyIsButton:key];

    if (aTableColumn == buttonColumn_) {
        if (isButton) {
            return [PointerPrefsController localizedButtonKey:key];
        } else {
            NSString *modifiers = [PointerPrefsController localizedModifiers:[PointerPrefsController modifiersForKey:key]];
            if ([modifiers length]) {
                modifiers = [modifiers stringByAppendingString:@" + "];
            }
            NSString *gesture = [PointerPrefsController localizedGestureNameForGestureIdentifier:[PointerPrefsController gestureIdentifierForKey:key]];
            return [NSString stringWithFormat:@"%@%@", modifiers, gesture];
        }
    } else {
        // Action
        return [PointerPrefsController formattedLocalizedActionForDict:action];
    }
}

- (BOOL)okShouldBeEnabled
{
    if (![editButton_ selectedItem]) {
        return NO;
    }
    if (![editAction_ selectedItem]) {
        return NO;
    }
    if ([editButton_ selectedTag] >= kMinGestureTag) {
        // Gesture
        return YES;
    } else {
        // Button
        return [editClickType_ selectedItem] != nil;
    }
}

+ (NSString *)actionForKey:(NSString *)key {
    NSDictionary *setting = [[PointerPrefsController settings] objectForKey:key];
    return [setting objectForKey:kActionKey];
}

+ (NSString *)argumentForKey:(NSString *)key {
    NSDictionary *setting = [[PointerPrefsController settings] objectForKey:key];
    return [setting objectForKey:kArgumentKey];
}

+ (BOOL)useCompatibilityEscapingForKey:(NSString *)key {
    NSDictionary *setting = [[PointerPrefsController settings] objectForKey:key];
    return [[setting objectForKey:kVersionKey] intValue] == 0;
}

- (void)updateArgumentFieldsForAction:(NSString *)actionIdent argument:(NSString *)currentArg
{
    if (NSEqualRects(NSZeroRect, _initialFrame)) {
        _initialFrame = _pasteSpecialViewContainer.window.frame;
        _initialPasteContainerFrame = _pasteSpecialViewContainer.frame;
    }
    ArgumentType argType = kNoArg;
    if (actionIdent) {
        argType = [PointerPrefsController argumentTypeForAction:actionIdent];
    }
    switch (argType) {
        case kNoArg:
            [editArgumentLabel_ setHidden:YES];
            [editArgumentField_ setHidden:YES];
            [editArgumentButton_ setHidden:YES];
            _menuItemPopupView.hidden = YES;
            _pasteSpecialViewContainer.hidden = YES;
            break;

        case kEscPlusArg:
            [editArgumentLabel_ setHidden:NO];
            [editArgumentField_ setHidden:NO];
            [editArgumentField_ setEnabled:YES];
            [editArgumentButton_ setHidden:YES];
            _menuItemPopupView.hidden = YES;
            [editArgumentLabel_ setStringValue:NSLocalizedString(@"Esc +", @"Pointer argument label")];
            [[editArgumentField_ cell] setPlaceholderString:NSLocalizedString(@"Characters to send", @"Pointer argument placeholder")];
            [editArgumentField_ setStringValue:currentArg];
            [editArgumentField_ setRefusesFirstResponder:NO];
            [editArgumentField_ setSelectable:YES];
            _pasteSpecialViewContainer.hidden = YES;
            editArgumentField_.delegate = nil;
            break;

        case kHexCodeArg:
            [editArgumentLabel_ setHidden:NO];
            [editArgumentField_ setHidden:NO];
            [editArgumentField_ setEnabled:YES];
            [editArgumentButton_ setHidden:YES];
            _menuItemPopupView.hidden = YES;
            [editArgumentLabel_ setStringValue:NSLocalizedString(@"Hex codes:", @"Pointer argument label")];
            [[editArgumentField_ cell] setPlaceholderString:NSLocalizedString(@"ex: 0x7f 0x20", @"Pointer argument placeholder")];
            [editArgumentField_ setStringValue:currentArg];
            _pasteSpecialViewContainer.hidden = YES;
            editArgumentField_.delegate = nil;
            break;

        case kTextArg:
            [editArgumentLabel_ setHidden:NO];
            [editArgumentField_ setHidden:NO];
            [editArgumentField_ setEnabled:YES];
            [editArgumentButton_ setHidden:YES];
            _menuItemPopupView.hidden = YES;
            [editArgumentLabel_ setStringValue:NSLocalizedString(@"Text:", @"Pointer argument label")];
            [[editArgumentField_ cell] setPlaceholderString:NSLocalizedString(@"Enter value to send", @"Pointer argument placeholder")];
            [editArgumentField_ setStringValue:currentArg];
            _pasteSpecialViewContainer.hidden = YES;
            editArgumentField_.delegate = nil;
            break;

        case kScriptFunctionArg:
            [editArgumentLabel_ setHidden:NO];
            [editArgumentField_ setHidden:NO];
            [editArgumentField_ setEnabled:YES];
            [editArgumentButton_ setHidden:YES];
            _menuItemPopupView.hidden = YES;
            [editArgumentLabel_ setStringValue:NSLocalizedString(@"Function:", @"Pointer argument label")];
            [[editArgumentField_ cell] setPlaceholderString:NSLocalizedString(@"Enter function invocation", @"Pointer argument placeholder")];
            [editArgumentField_ setStringValue:currentArg];
            _pasteSpecialViewContainer.hidden = YES;
            _invocationDelegate = [[iTermFunctionCallTextFieldDelegate alloc] initWithPathSource:[iTermVariableHistory pathSourceForContext:iTermVariablesSuggestionContextSession]
                                                                                     passthrough:nil
                                                                                   functionsOnly:YES];
            editArgumentField_.delegate = _invocationDelegate;
            break;

        case kProfileArg:
            [editArgumentLabel_ setHidden:NO];
            [editArgumentField_ setHidden:YES];
            [editArgumentButton_ setHidden:NO];
            _menuItemPopupView.hidden = YES;
            [editArgumentLabel_ setStringValue:NSLocalizedString(@"Profile:", @"Pointer argument label")];
            [editArgumentButton_ populateWithProfilesSelectingGuid:currentArg];
            _pasteSpecialViewContainer.hidden = YES;
            break;

        case kAdvancedPasteArg:
            editArgumentLabel_.hidden = YES;
            editArgumentField_.hidden = YES;
            editArgumentButton_.hidden = YES;
            _pasteSpecialViewContainer.hidden = NO;
            _menuItemPopupView.hidden = YES;
            [self configurePasteSpecialWithArgument:currentArg];
            break;

        case kMenuItemArg: {
            editArgumentLabel_.hidden = YES;
            editArgumentField_.hidden = YES;
            editArgumentButton_.hidden = YES;
            _pasteSpecialViewContainer.hidden = YES;
            _menuItemPopupView.hidden = NO;
            [_menuItemPopupView reloadData];
            NSArray<NSString *> *parts = [currentArg componentsSeparatedByString:@"\n"];
            if (parts.count > 0) {
                (void)[_menuItemPopupView selectItemWithIdentifier:parts.firstObject];
            }
            break;
        }

    }
    [self updateWindowFrame];
}

- (void)loadKeyIntoEditPane:(NSString *)key
{
    int modMask;
    if (key) {
        modMask = [PointerPrefsController modifiersForKey:key];
    } else {
        modMask = 0;
    }
    NSString *localizedAction = @"";
    if (key) {
        localizedAction = [PointerPrefsController localizedActionForKey:key];
    }
    NSString *actionIdent = [PointerPrefsController actionForKey:key];
    NSString *currentArg = [PointerPrefsController argumentForKey:key];
    [self updateArgumentFieldsForAction:actionIdent argument:currentArg];

    [editModifiersCommand_ setState:(modMask & NSEventModifierFlagCommand) ? NSControlStateValueOn : NSControlStateValueOff];
    [editModifiersOption_ setState:(modMask & NSEventModifierFlagOption) ? NSControlStateValueOn : NSControlStateValueOff];
    [editModifiersShift_ setState:(modMask & NSEventModifierFlagShift) ? NSControlStateValueOn : NSControlStateValueOff];
    [editModifiersControl_ setState:(modMask & NSEventModifierFlagControl) ? NSControlStateValueOn : NSControlStateValueOff];
    [editAction_ selectItemWithTitle:localizedAction];
    BOOL isButton = !key || [PointerPrefsController keyIsButton:key];
    if (isButton) {
        int button = key ? [PointerPrefsController buttonForKey:key] : 2;
        int numClicks = key ? [PointerPrefsController numClicksForKey:key] : 1;

        [editButton_ selectItemWithTag:button];
        [editClickType_ selectItemWithTag:numClicks];
    } else {
        NSString *gestureIdent = [PointerPrefsController gestureIdentifierForKey:key];
        [editButton_ selectItemWithTag:[PointerPrefsController tagForGestureIdentifier:gestureIdent]];
        [editClickType_ selectItem:nil];
    }
    origKey_ = key;
    if (key) {
        version_ = [PointerPrefsController useCompatibilityEscapingForKey:key] ? 0 : 1;
    } else {
        version_ = 1;
    }
    [self buttonOrGestureChanged:nil];
    [ok_ setEnabled:[self okShouldBeEnabled]];
}

- (IBAction)buttonOrGestureChanged:(id)sender
{
    if ([editButton_ selectedTag] >= kMinGestureTag) {
        editClickTypeLabel_.labelEnabled = NO;
        [editClickType_ setEnabled:NO];
    } else {
        editClickTypeLabel_.labelEnabled = YES;
        [editClickType_ setEnabled:YES];
    }
}

#pragma mark NSTableViewDelegate

- (BOOL)tableView:(NSTableView *)aTableView
    shouldEditTableColumn:(NSTableColumn *)aTableColumn
              row:(NSInteger)rowIndex
{
    return NO;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
    [self updateActionButtonStates];
    const NSInteger rowIndex = [tableView_ selectedRow];

    if (self.hasSelection && rowIndex >= 0) {
        NSString *key = [PointerPrefsController keyForRowIndex:(int)rowIndex];
        NSDictionary *action = [[PointerPrefsController settings] objectForKey:key];

        if ([PointerPrefsController keyIsButton:key]) {
            [editButton_ selectItemWithTag:[PointerPrefsController buttonForKey:key]];
        } else {
            NSString *gestureIdent = [PointerPrefsController gestureIdentifierForKey:key];
            [editButton_ selectItemWithTag:[PointerPrefsController tagForGestureIdentifier:gestureIdent]];
        }
        [editAction_ selectItemWithTitle:[PointerPrefsController localizedActionForDict:action]];

        int modflags = [PointerPrefsController modifiersForKey:key];
        [editModifiersCommand_ setState:(modflags & NSEventModifierFlagCommand) ? NSControlStateValueOn : NSControlStateValueOff];
        [editModifiersOption_ setState:(modflags & NSEventModifierFlagOption) ? NSControlStateValueOn : NSControlStateValueOff];
        [editModifiersShift_ setState:(modflags & NSEventModifierFlagShift) ? NSControlStateValueOn : NSControlStateValueOff];
        [editModifiersControl_ setState:(modflags & NSEventModifierFlagControl) ? NSControlStateValueOn : NSControlStateValueOff];
    }
    editButtonLabel_.labelEnabled = self.hasSelection;
    editModifiersLabel_.labelEnabled = self.hasSelection;
    editActionLabel_.labelEnabled = self.hasSelection;
}

- (IBAction)editSelected:(id)sender
{
    [self tableViewRowDoubleClicked:sender];
}

- (void)tableViewRowDoubleClicked:(id)sender
{
    if ([tableView_ selectedRow] >= 0) {
        NSString *key = [PointerPrefsController keyForRowIndex:[tableView_ selectedRow]];
        [self editKey:key];
    }
}

- (void)editKey:(NSString *)key {
    [self loadKeyIntoEditPane:key];
    __weak __typeof(self) weakSelf = self;
    [[[PreferencePanel sharedInstance] window] beginSheet:panel_
                                        completionHandler:^(NSModalResponse returnCode) {
                                            __strong __typeof(weakSelf) strongSelf = self;
                                            if (strongSelf) {
                                                [strongSelf->panel_ close];
                                            }
                                        }];
}

- (IBAction)ok:(id)sender {
    NSMutableDictionary *temp = [NSMutableDictionary dictionaryWithDictionary:[PointerPrefsController settings]];
    if (origKey_) {
        [temp removeObjectForKey:origKey_];
    }
    NSString *theAction = [PointerPrefsController actionWithLocalizedName:[[editAction_ selectedItem] title]];
    NSMutableDictionary *newValue = [NSMutableDictionary dictionaryWithObject:theAction
                                                                       forKey:kActionKey];
    newValue[kVersionKey] = @(version_);
    if (![editArgumentField_ isHidden]) {
        [newValue setObject:[editArgumentField_ stringValue]
                     forKey:kArgumentKey];
    } else if (![editArgumentButton_ isHidden]) {
        if ([PointerPrefsController argumentTypeForAction:theAction] == kProfileArg) {
            NSString *profileName = [[editArgumentButton_ selectedItem] title];
            NSString *guid = [[[ProfileModel sharedInstance] bookmarkWithName:profileName] objectForKey:KEY_GUID];
            if (guid) {
                [newValue setObject:guid forKey:kArgumentKey];
            } else {
                [newValue setObject:@"" forKey:kArgumentKey];
            }
        } else {
            [newValue setObject:[[editArgumentButton_ selectedItem] title]
                         forKey:kArgumentKey];
        }
    } else if (!_pasteSpecialViewContainer.isHidden) {
        if ([PointerPrefsController argumentTypeForAction:theAction] == kAdvancedPasteArg) {
            [newValue setObject:[_pasteSpecialViewController stringEncodedSettings] ?: @""
                         forKey:kArgumentKey];
        }
    } else if (!_menuItemPopupView.isHidden) {
        newValue[kArgumentKey] = [NSString stringWithFormat:@"%@\n%@", _menuItemPopupView.selectedIdentifier, _menuItemPopupView.selectedTitle];
    }
    NSString *newKey;
    int modMask = 0;
    if ([editModifiersCommand_ state] == NSControlStateValueOn) {
        modMask |= NSEventModifierFlagCommand;
    }
    if ([editModifiersOption_ state] == NSControlStateValueOn) {
        modMask |= NSEventModifierFlagOption;
    }
    if ([editModifiersShift_ state] == NSControlStateValueOn) {
        modMask |= NSEventModifierFlagShift;
    }
    if ([editModifiersControl_ state] == NSControlStateValueOn) {
        modMask |= NSEventModifierFlagControl;
    }
    if ([editButton_ selectedTag] >= kMinGestureTag) {
        // Gesture
        newKey = [PointerPrefsController keyForGesture:[PointerPrefsController gestureIdentifierForTag:[editButton_ selectedTag]]
                                             modifiers:modMask];
    } else {
        // Button
        newKey = [PointerPrefsController keyForButton:[editButton_ selectedTag]
                                               clicks:[editClickType_ selectedTag]
                                            modifiers:modMask];
    }
    [temp setObject:newValue forKey:newKey];
    [PointerPrefsController setSettings:temp];
    [tableView_ reloadData];
    [self updateActionButtonStates];
    [[[PreferencePanel sharedInstance] window] endSheet:panel_];
}

- (IBAction)cancel:(id)sender {
    [[[PreferencePanel sharedInstance] window] endSheet:panel_];
}

- (IBAction)add:(id)sender
{
    [self editKey:nil];
}

- (IBAction)remove:(id)sender
{
    if ([tableView_ selectedRow] >= 0) {
        NSString *key = [PointerPrefsController keyForRowIndex:(int)[tableView_ selectedRow]];
        NSMutableDictionary *temp = [NSMutableDictionary dictionaryWithDictionary:[PointerPrefsController settings]];
        if (key) {
            [temp removeObjectForKey:key];
            [PointerPrefsController setSettings:temp];
        }
        [tableView_ reloadData];
        [self updateActionButtonStates];
    }
}

- (IBAction)actionChanged:(id)sender
{
    [ok_ setEnabled:[self okShouldBeEnabled]];
    NSString *actionIdent = [PointerPrefsController actionWithLocalizedName:[[editAction_ selectedItem] title]];
    [self updateArgumentFieldsForAction:actionIdent
                               argument:@""];
}

- (IBAction)clicksChanged:(id)sender
{
    [ok_ setEnabled:[self okShouldBeEnabled]];
}

- (IBAction)loadDefaults:(id)sender
{
    const iTermWarningSelection selection =
        [iTermWarning showWarningWithTitle:NSLocalizedString(@"Replace all pointer bindings with the default set?", @"Pointer bindings reset prompt")
                                   actions:@[
                                       NSLocalizedString(@"Restore Defaults", @"Pointer bindings reset confirm"),
                                       NSLocalizedString(@"Cancel", @"Cancel")
                                   ]
                                 accessory:nil
                                identifier:@"NoSyncConfirmLoadDefaultPointerBindings"
                               silenceable:kiTermWarningTypePermanentlySilenceable
                                   heading:NSLocalizedString(@"Restore Default Bindings", @"Pointer bindings reset heading")
                                    window:tableView_.window];
    if (selection != kiTermWarningSelection0) {
        return;
    }
    [PointerPrefsController setSettings:[PointerPrefsController defaultActions]];
    [tableView_ reloadData];
    [self updateActionButtonStates];
}

- (void)configurePasteSpecialWithArgument:(NSString *)parameterValue {
    _pasteSpecialViewController = [[iTermPasteSpecialViewController alloc] init];
    [_pasteSpecialViewController applyTerminalLayout];

    // Set a few defaults; otherwise everything is reasonable.
    _pasteSpecialViewController.numberOfSpacesPerTab = [iTermPreferences intForKey:kPreferenceKeyPasteSpecialSpacesPerTab];
    _pasteSpecialViewController.shouldRemoveNewlines = NO;
    _pasteSpecialViewController.shouldBase64Encode = NO;
    _pasteSpecialViewController.shouldWaitForPrompt = NO;
    _pasteSpecialViewController.shouldEscapeShellCharsWithBackslash = NO;
    if (parameterValue.length > 0) {
        [_pasteSpecialViewController loadSettingsFromString:parameterValue];
    }
    _pasteSpecialViewController.view.frame = _pasteSpecialViewController.view.bounds;
    NSRect theFrame = _pasteSpecialViewContainer.frame;
    CGFloat originalHeight = theFrame.size.height;
    theFrame.size = _pasteSpecialViewController.view.bounds.size;
    theFrame.origin.y -= (theFrame.size.height - originalHeight);
    _pasteSpecialViewContainer.frame = theFrame;
    [_pasteSpecialViewContainer addSubview:_pasteSpecialViewController.view];
}

- (void)updateWindowFrame {
    NSRect frame;
    if (_pasteSpecialViewContainer.isHidden) {
        frame = _initialFrame;
    } else {
        frame = _initialFrame;
        NSSize desiredSize = _pasteSpecialViewController.view.frame.size;
        frame.size.width += desiredSize.width - _initialPasteContainerFrame.size.width;
        frame.size.height += desiredSize.height - _initialPasteContainerFrame.size.height;
    }
    [_pasteSpecialViewContainer.window setFrame:frame display:YES animate:YES];
}

@end

@implementation NSString (PointerPrefsController)

- (NSComparisonResult)comparePointerActions:(NSString *)other
{
    BOOL selfIsButton = [PointerPrefsController keyIsButton:self];
    BOOL otherIsButton = [PointerPrefsController keyIsButton:other];
    if (selfIsButton != otherIsButton) {
        // Compare dissimilar types
        if (selfIsButton) {
            return NSOrderedDescending;
        } else {
            return NSOrderedAscending;
        }
    }
    if (selfIsButton) {
        // Compare buttons
        NSArray *selfParts = [PointerPrefsController buttonKeyComponents:self];
        NSArray *otherParts = [PointerPrefsController buttonKeyComponents:other];
        if (!selfParts && !otherParts) {
            return NSOrderedSame;
        } else if (!selfParts && otherParts) {
            return NSOrderedAscending;
        } else if (selfParts && !otherParts) {
            return NSOrderedDescending;
        }
        NSComparisonResult result;
        result = [[NSNumber numberWithInt:[[selfParts objectAtIndex:1] intValue]] compare:[NSNumber numberWithInt:[[otherParts objectAtIndex:1] intValue]]];
        if (result != NSOrderedSame) {
            return result;
        }
        result = [[NSNumber numberWithInt:[[selfParts objectAtIndex:2] intValue]] compare:[NSNumber numberWithInt:[[otherParts objectAtIndex:2] intValue]]];
        if (result != NSOrderedSame) {
            return result;
        }
        result = [[selfParts objectAtIndex:3] compare:[otherParts objectAtIndex:3]];
        if (result != NSOrderedSame) {
            return result;
        }
        result = [[selfParts objectAtIndex:4] compare:[otherParts objectAtIndex:4]];
        return result;
    } else {
        // Compare gestures
        NSArray *selfParts = [PointerPrefsController gestureKeyComponents:self];
        NSArray *otherParts = [PointerPrefsController gestureKeyComponents:other];
        if (!selfParts && !otherParts) {
            return NSOrderedSame;
        } else if (!selfParts && otherParts) {
            return NSOrderedAscending;
        } else if (selfParts && !otherParts) {
            return NSOrderedDescending;
        }
        NSComparisonResult result;
        NSString *selfIdent = [PointerPrefsController localizedGestureNameForGestureIdentifier:[selfParts objectAtIndex:1]];
        NSString *otherIdent = [PointerPrefsController localizedGestureNameForGestureIdentifier:[otherParts objectAtIndex:1]];
        result = [selfIdent localizedCaseInsensitiveCompare:otherIdent];
        if (result != NSOrderedSame) {
            return result;
        }
        result = [[selfParts objectAtIndex:2] compare:[otherParts objectAtIndex:2]];
        if (result != NSOrderedSame) {
            return result;
        }
        result = [[selfParts objectAtIndex:3] compare:[otherParts objectAtIndex:3]];
        return result;
    }
}

@end

@implementation NSDictionary (PointerPrefsController)

- (NSComparisonResult)comparePointerPrefsValue:(NSDictionary *)other
{
    NSString *selfAction = [PointerPrefsController localizedActionForDict:self];
    NSString *otherAction = [PointerPrefsController localizedActionForDict:other];
    return [selfAction localizedCaseInsensitiveCompare:otherAction];
}

@end
