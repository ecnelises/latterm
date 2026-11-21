//
//  iTermStatusBarActionComponent.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/22/19.
//

#import "iTermStatusBarActionComponent.h"
#import "DebugLogging.h"
#import "iTermActionsModel.h"
#import "iTermSwiftyString.h"
#import "NSArray+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSImage+iTerm.h"
#import "NSString+CommonAdditions.h"

static NSString *const iTermStatusBarActionKey = @"action";

@implementation iTermStatusBarActionComponent {
    NSString *_value;
    iTermSwiftyString *_swiftyString;
}

- (nullable NSArray<NSString *> *)stringVariants {
    if (!_value) {
        return @[];
    }
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    static NSRegularExpression *horizontalWhitespaceRegex;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        horizontalWhitespaceRegex = [NSRegularExpression regularExpressionWithPattern:@"\\h+"
                                                                              options:0
                                                                                error:nil];
    });
    __block NSUInteger lastLocation = 0;
    const NSUInteger totalLength = _value.length;
    [horizontalWhitespaceRegex enumerateMatchesInString:_value
                                                options:0
                                                  range:NSMakeRange(0, totalLength)
                                             usingBlock:^(NSTextCheckingResult * _Nullable match, NSMatchingFlags flags, BOOL * _Nonnull stop) {
        if (!match) {
            return;
        }
        const NSRange tokenRange = NSMakeRange(lastLocation, match.range.location - lastLocation);
        [result addObject:[self->_value substringToIndex:NSMaxRange(tokenRange)]];
        lastLocation = NSMaxRange(match.range);
    }];
    if (lastLocation < totalLength) {
        [result addObject:[_value substringToIndex:totalLength]];
    }
    return result;
}

- (void)setStringValue:(NSString *)value {
    _value = [value copy];
    [self updateTextFieldIfNeeded];
}

- (NSArray<iTermStatusBarComponentKnob *> *)statusBarComponentKnobs {
    iTermStatusBarComponentKnob *actionKnob =
    [[iTermStatusBarComponentKnob alloc] initWithLabelText:@"Action"
                                                      type:iTermStatusBarComponentKnobTypeAction
                                               placeholder:nil
                                              defaultValue:nil
                                                       key:iTermStatusBarActionKey];
    return [@[ actionKnob, [super statusBarComponentKnobs] ] flattenedArray];
}

- (NSDictionary *)actionDictionary {
    return self.configuration[iTermStatusBarComponentConfigurationKeyKnobValues][iTermStatusBarActionKey];
}

- (iTermAction *)action {
    return [[iTermAction alloc] initWithDictionary:self.actionDictionary];
}

- (void)updateTitleInButton {
    if (_swiftyString) {
        _swiftyString.swiftyString = self.action.title;
        return;
    }
    __weak __typeof(self) weakSelf = self;
    NSString *expression = self.action.title.copy ?: @"";
    _swiftyString = [[iTermSwiftyString alloc] initWithString:expression
                                                        scope:self.scope
                                           sideEffectsAllowed:false
                                                     observer:^(NSString * _Nonnull newValue, NSError *error) {
        if (error != nil) {
            DLog(@"Error while evaluating %@ in status bar action button: %@", expression, error);
            return [NSString stringWithFormat:@"🐞 %@", error.localizedDescription];
        }
        [weakSelf setStringValue:newValue];
        return newValue;
    }];
}

- (NSString *)statusBarComponentShortDescription {
    return @"Custom Action";
}

- (BOOL)statusBarComponentCanStretch {
    return YES;
}

- (NSString *)statusBarComponentDetailedDescription {
    return @"Adds a button that performs a user-configurable action, similar to a key binding.";
}

- (id)statusBarComponentExemplarWithBackgroundColor:(NSColor *)backgroundColor
                                          textColor:(NSColor *)textColor {
    NSDictionary *dict = self.actionDictionary;
    if (dict.count) {
        return self.action.title;
    } else {
        return @"Custom Action";
    }
}

- (void)setDelegate:(id<iTermStatusBarComponentDelegate> _Nullable)delegate {
    [super setDelegate:delegate];
    [self updateTitleInButton];
}

- (nullable NSImage *)statusBarComponentIcon {
    return [NSImage it_cacheableImageNamed:@"StatusBarIconAction" forClass:[self class]];
}

- (NSString *)statusBarComponentCopyableString {
    return nil;
}

- (BOOL)statusBarComponentHandlesClicks {
    return YES;
}

- (BOOL)statusBarComponentIsEmpty {
    return NO;
}

- (void)statusBarComponentDidClickWithView:(NSView *)view {
    if (self.actionDictionary) {
        [self.delegate statusBarComponentPerformAction:self.action];
    }
}

@end

@implementation iTermStatusBarActionMenuComponent

- (NSString *)statusBarComponentCopyableString {
    return nil;
}

- (nullable NSImage *)statusBarComponentIcon {
    return [NSImage it_cacheableImageNamed:@"StatusBarIconAction" forClass:[self class]];
}

- (NSString *)statusBarComponentShortDescription {
    return @"Actions Menu";
}

- (NSString *)statusBarComponentDetailedDescription {
    return @"When clicked, opens a menu of actions. Actions are like custom key bindings, but without a keystroke attached.";
}

- (id)statusBarComponentExemplarWithBackgroundColor:(NSColor *)backgroundColor
                                          textColor:(NSColor *)textColor {
    return @"Action…";
}

- (BOOL)statusBarComponentCanStretch {
    return YES;
}

- (nullable NSString *)stringValue {
    return @"Perform Action…";
}

- (nullable NSString *)stringValueForCurrentWidth {
    return self.stringValue;
}

- (nullable NSArray<NSString *> *)stringVariants {
    return @[ self.stringValue ];
}

- (BOOL)statusBarComponentHandlesClicks {
    return YES;
}

- (BOOL)statusBarComponentIsEmpty {
    return [[[iTermActionsModel sharedInstance] actions] count] == 0;
}

- (void)statusBarComponentDidClickWithView:(NSView *)view {
    [self openMenuWithView:view];
}

- (void)statusBarComponentMouseDownWithView:(NSView *)view {
    [self openMenuWithView:view];
}

- (BOOL)statusBarComponentHandlesMouseDown {
    return YES;
}

- (void)openMenuWithView:(NSView *)view {
    NSView *containingView = view.superview;

    NSMenu *menu = [[NSMenu alloc] init];
    for (iTermAction *action in [[iTermActionsModel sharedInstance] actions]) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:action.title action:@selector(performAction:) keyEquivalent:@""];
        item.identifier = [@(action.identifier) stringValue];
        item.target = self;
        [menu addItem:item];
    }

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Edit Actions…" action:@selector(editActions:) keyEquivalent:@""];
    item.target = self;
    [menu addItem:item];

    [menu popUpMenuPositioningItem:menu.itemArray.firstObject atLocation:NSMakePoint(0, 0) inView:containingView];
}

- (void)performAction:(id)sender {
    NSMenuItem *menuItem = [NSMenuItem castFrom:sender];
    if (!menuItem) {
        return;
    }
    iTermAction *action = [[iTermActionsModel sharedInstance] actionWithIdentifier:[menuItem.identifier integerValue]];
    if (!action) {
        return;
    }
    [self.delegate statusBarComponentPerformAction:action];
}

- (void)editActions:(id)sender {
    [self.delegate statusBarComponentEditActions:self];
}

@end
