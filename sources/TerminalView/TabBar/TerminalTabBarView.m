//
//  TerminalTabBarView.m
//  TerminalTabBarView
//
//  Created by John Pannell on 10/13/05.
//  Copyright 2005 Positive Spin Media. All rights reserved.
//

#import "TerminalTabBarView.h"

#import "DebugLogging.h"
#import "iTerm2SharedARC-Swift.h"
#import "NSBezierPath+iTerm.h"
#import "PSMTabBarCell.h"
#import "PSMOverflowPopUpButton.h"
#import "PSMRolloverButton.h"
#import "PSMTabStyle.h"
#import "PSMYosemiteTabStyle.h"
#import "PTYTask.h"
#import "NSColor+PSM.h"
#import <QuartzCore/QuartzCore.h>


NSPasteboardType const TerminalTabPasteboardType = @"com.latterm.tab-item";
NSString *const kPSMModifierChangedNotification = @"kPSMModifierChangedNotification";
NSString *const kPSMTabModifierKey = @"TabModifier";
NSString *const PSMTabDragDidEndNotification = @"PSMTabDragDidEndNotification";
NSString *const PSMTabDragDidBeginNotification = @"PSMTabDragDidBeginNotification";
const CGFloat kSPMTabBarCellInternalXMargin = 6;
const CGFloat PSMTabBarProgressBarHeight = 2;

const CGFloat kPSMTabBarCellPadding = 4;
const CGFloat kPSMTabBarCellIconPadding = 4;
// fixed size objects
const CGFloat kPSMMinimumTitleWidth = 30;
const CGFloat kPSMTabBarIndicatorWidth = 16.0;
const CGFloat kPSMTabBarIconWidth = 16.0;
const CGSize PSMTabBarGraphicSize = { 16.0, 16.0 };
const CGFloat PSMTabBarGraphicMargin = 2;

PSMTabBarControlOptionKey PSMTabBarControlOptionColoredSelectedTabOutlineStrength = @"PSMTabBarControlOptionColoredSelectedTabOutlineStrength";
PSMTabBarControlOptionKey PSMTabBarControlOptionMinimalStyleBackgroundColorDifference =
    @"PSMTabBarControlOptionMinimalStyleBackgroundColorDifference";
PSMTabBarControlOptionKey PSMTabBarControlOptionMinimalBackgroundAlphaValue =
    @"PSMTabBarControlOptionMinimalBackgroundAlphaValue";
PSMTabBarControlOptionKey PSMTabBarControlOptionMinimalTextLegibilityAdjustment =
    @"PSMTabBarControlOptionMinimalTextLegibilityAdjustment";
PSMTabBarControlOptionKey PSMTabBarControlOptionColoredMinimalOutlineStrength =
    @"PSMTabBarControlOptionColoredMinimalOutlineStrength";
PSMTabBarControlOptionKey PSMTabBarControlOptionColoredUnselectedTabTextProminence = @"PSMTabBarControlOptionColoredUnselectedTabTextProminence";
PSMTabBarControlOptionKey PSMTabBarControlOptionDimmingAmount = @"PSMTabBarControlOptionDimmingAmount";
PSMTabBarControlOptionKey PSMTabBarControlOptionMinimalStyleTreatLeftInsetAsPartOfFirstTab = @"PSMTabBarControlOptionMinimalStyleTreatLeftInsetAsPartOfFirstTab";
PSMTabBarControlOptionKey PSMTabBarControlOptionMinimumSpaceForLabel =
    @"PSMTabBarControlOptionMinimumSpaceForLabel";
PSMTabBarControlOptionKey PSMTabBarControlOptionHighVisibility = @"PSMTabBarControlOptionHighVisibility";
PSMTabBarControlOptionKey PSMTabBarControlOptionColoredDrawBottomLineForHorizontalTabBar =
    @"PSMTabBarControlOptionColoredDrawBottomLineForHorizontalTabBar";
PSMTabBarControlOptionKey PSMTabBarControlOptionFontSizeOverride =
    @"PSMTabBarControlOptionFontSizeOverride";
PSMTabBarControlOptionKey PSMTabBarControlOptionMinimalSelectedTabUnderlineProminence = @"PSMTabBarControlOptionMinimalSelectedTabUnderlineProminence";
PSMTabBarControlOptionKey PSMTabBarControlOptionDragEdgeHeight = @"PSMTabBarControlOptionDragEdgeHeight";
PSMTabBarControlOptionKey PSMTabBarControlOptionAttachedToTitleBar = @"PSMTabBarControlOptionAttachedToTitleBar";
PSMTabBarControlOptionKey PSMTabBarControlOptionHTMLTabTitles = @"PSMTabBarControlOptionHTMLTabTitles";
PSMTabBarControlOptionKey PSMTabBarControlOptionMinimalNonSelectedColoredTabAlpha = @"PSMTabBarControlOptionMinimalNonSelectedColoredTabAlpha";
PSMTabBarControlOptionKey PSMTabBarControlOptionTextColor = @"PSMTabBarControlOptionTextColor";
PSMTabBarControlOptionKey PSMTabBarControlOptionLightModeInactiveTabDarkness = @" PSMTabBarControlOptionLightModeInactiveTabDarkness";
PSMTabBarControlOptionKey PSMTabBarControlOptionDarkModeInactiveTabDarkness = @" PSMTabBarControlOptionDarkModeInactiveTabDarkness";
PSMTabBarControlOptionKey PSMTabBarControlOptionPUAFontProvider = @"PSMTabBarControlOptionPUAFontProvider";

@interface PSMToolTip: NSObject
@property (nonatomic, readonly) NSRect rect;
@property (nonatomic, weak, readonly) id owner;
@property (nonatomic, readonly) void *data;
@property (nonatomic, strong) NSNumber *tag;

+ (instancetype)toolTipWithRect:(NSRect)rect owner:(id)owner userData:(void *)data tag:(NSNumber *)tag;
@end

@implementation PSMToolTip

+ (instancetype)toolTipWithRect:(NSRect)rect owner:(id)owner userData:(void *)data tag:(NSNumber *)tag {
    return [[self alloc] initWithRect:rect owner:owner userData:data tag:tag];
}

- (instancetype)initWithRect:(NSRect)rect owner:(id)owner userData:(void *)data tag:(NSNumber *)tag {
    self = [super init];
    if (self) {
        _rect = rect;
        _owner = owner;
        _data = data;
        _tag = tag;
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p rect=%@ owner=%@ tag=%@>",
            NSStringFromClass([self class]), self, NSStringFromRect(_rect), _owner, _tag];
}
- (BOOL)isEqual:(id)object {
    if (![object isKindOfClass:[PSMToolTip class]]) {
        return NO;
    }
    PSMToolTip *other = object;
    if (!NSEqualRects(self.rect, other.rect)) {
        return NO;
    }
    if (self.owner != other.owner && ![self.owner isEqual:other.owner]) {
        return NO;
    }
    if (self.data != other.data) {
        return NO;
    }
    // Don't compare tags because we might not know what they are yet.
    return YES;
}

@end

@interface TerminalTabBarView ()<PSMTabBarControlProtocol, NSMenuItemValidation, NSViewToolTipOwner>
- (void)removeTabProgressBarForCell:(PSMTabBarCell *)cell;
@end

@implementation TerminalTabBarView {
    // control basics
    NSMutableArray<PSMTabBarCell *> *_cells; // the cells that draw the tabs
    NSButton *_overflowPopUpButton; // for too many tabs
    PSMRolloverButton *_addTabButton;
    // The delegate's last answer to -tabViewShouldShowActivityIndicators:, negated so the default
    // (NO) matches the default answer (YES).
    BOOL _activityIndicatorsHidden;


    // drag and drop
    NSEvent *_lastMouseDownEvent; // keep this for dragging reference
    NSEvent *_lastMiddleMouseDownEvent;
    BOOL _haveInitialDragLocation;
    NSPoint _initialDragLocation;
    BOOL _didDrag;
    BOOL _closeClicked;

    // iTerm2 additions
    NSUInteger _modifier;
    BOOL _hasCloseButton;
    BOOL _needsUpdateAnimate;
    BOOL _needsUpdate;
    NSInteger _preDragSelectedTabIndex;  // or NSNotFound
    NSMapTable<PSMTabBarCell *, NSView *> *_tabProgressBars;
    NSMutableArray<PSMToolTip *> *_tooltips;
    NSInteger _toolTipCoalescing;
}

#pragma mark -
#pragma mark Characteristics

+ (NSBundle *)bundle {
    static NSBundle *bundle = nil;
    if (!bundle) bundle = [NSBundle bundleForClass:[TerminalTabBarView class]];
    return bundle;
}

+ (BOOL)isAnyDragInProgress {
    return TerminalTabDrag.shared.isDragging;
}

- (float)availableCellWidthWithOverflow:(BOOL)withOverflow {
    float width = [self frame].size.width;
    const CGFloat rightMargin = [_style rightMarginForTabBarControlWithOverflow:withOverflow
                                                                   addTabButton:self.showAddTabButton];
    const CGFloat leftMargin = [_style leftMarginForTabBarControl];
    width = width - leftMargin - rightMargin;
    return width;
}

- (NSRect)genericCellRectWithOverflow:(BOOL)withOverflow {
    NSRect aRect = [self frame];
    aRect.origin.x = [_style leftMarginForTabBarControl];
    aRect.origin.y = self.insets.top;
    aRect.size.width = [self availableCellWidthWithOverflow:withOverflow];
    if (_orientation == PSMTabBarHorizontalOrientation) {
        aRect.size.height = self.height - self.insets.top - self.insets.bottom;
    } else {
        aRect.size.height = self.height;
    }
    return aRect;
}

#pragma mark -
#pragma mark Constructor/destructor

- (id)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        // Initialization
        _cells = [[NSMutableArray alloc] initWithCapacity:10];
        const CGFloat defaultHeight = 24;
        _height = defaultHeight;

        // default config
        _orientation = PSMTabBarHorizontalOrientation;
        _allowsBackgroundTabClosing = YES;
        _cellMinWidth = 100;
        _cellMaxWidth = 280;
        _cellOptimumWidth = 130;
        _pinnedTabWidth = [iTermAdvancedSettingsModel pinnedTabWidth];
        _minimumTabDragDistance = 10;
        _hasCloseButton = YES;
        _tabLocation = PSMTab_TopTab;
        if (@available(macOS 26, *)) {
            if (![iTermAdvancedSettingsModel useSequoiaStyleTabs]) {
                _style = [[PSMTahoeTabStyle alloc] init];
            } else {
                _style = [[PSMYosemiteTabStyle alloc] init];
            }
        } else {
            _style = [[PSMYosemiteTabStyle alloc] init];
        }
        _preDragSelectedTabIndex = NSNotFound;
        _tabProgressBars = [NSMapTable strongToStrongObjectsMapTable];

        // the overflow button/menu
        [self setupButtons];

        [self registerForDraggedTypes:[NSArray arrayWithObjects:TerminalTabPasteboardType, nil]];

        // resize
        [self setPostsFrameChangedNotifications:YES];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(frameDidChange:) name:NSViewFrameDidChangeNotification object:self];

        // window status
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(windowStatusDidChange:) name:NSWindowDidBecomeKeyNotification object:[self window]];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(windowStatusDidChange:) name:NSWindowDidResignKeyNotification object:[self window]];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(windowDidMove:) name:NSWindowDidMoveNotification object:[self window]];

        // modifier for changing tabs changed (iTerm2 addon)
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(modifierChanged:)
                                                     name:kPSMModifierChangedNotification
                                                   object:nil];
        _tooltips = [[NSMutableArray alloc] init];
    }
    [self setTarget:self];
    return self;
}

- (void)setupButtons {
    if (@available(macOS 26, *)) {
        if (![iTermAdvancedSettingsModel useSequoiaStyleTabs]) {
            NSRect overflowButtonRect = [_style frameForOverflowButtonWithAddTabButton:self.showAddTabButton
                                                                         enclosureSize:self.frame.size
                                                                        standardHeight:self.height];
            [_overflowPopUpButton removeFromSuperview];
            _overflowPopUpButton = [self.style makeOverflowButtonWithFrame:overflowButtonRect];
            if (_overflowPopUpButton) {
                // configure
                [_overflowPopUpButton setAutoresizingMask:NSViewNotSizable|NSViewMinXMargin];
                _overflowPopUpButton.accessibilityLabel = @"More tabs";
            }

            // new tab button
            NSRect addTabButtonRect = NSMakeRect([self frame].size.width - [_style rightMarginForTabBarControlWithOverflow:YES
                                                                                                              addTabButton:self.showAddTabButton],
                                                 3,
                                                 23,
                                                 22);
            [_addTabButton removeFromSuperview];
            _addTabButton = [_style makeAddTabButtonWithFrame:addTabButtonRect];
            if (_showAddTabButton) {
                [_addTabButton setHidden:NO];
            } else {
                [_addTabButton setHidden:YES];
            }
            [_addTabButton setNeedsDisplay:YES];
            _addTabButton.action = @selector(addTab:);
            _addTabButton.target = self;
            return;
        }
    }
    NSRect overflowButtonRect = NSMakeRect([self frame].size.width - [_style rightMarginForTabBarControlWithOverflow:YES
                                                                                                        addTabButton:self.showAddTabButton] + 1,
                                           0,
                                           [_style rightMarginForTabBarControlWithOverflow:YES
                                                                              addTabButton:self.showAddTabButton] - 1,
                                           [self frame].size.height);
    [_overflowPopUpButton removeFromSuperview];
    _overflowPopUpButton = [[PSMOverflowPopUpButton alloc] initWithFrame:overflowButtonRect pullsDown:YES];
    if (_overflowPopUpButton) {
        // configure
        [_overflowPopUpButton setAutoresizingMask:NSViewNotSizable|NSViewMinXMargin];
        _overflowPopUpButton.accessibilityLabel = @"More tabs";
    }

    NSRect addTabButtonRect = NSMakeRect([self frame].size.width - [_style rightMarginForTabBarControlWithOverflow:YES
                                                                                                      addTabButton:self.showAddTabButton],
                                         3,
                                         23,
                                         22);
    [_addTabButton removeFromSuperview];
    _addTabButton = [[PSMRolloverButton alloc] initWithFrame:addTabButtonRect];
    if (_addTabButton) {
        NSImage *newButtonImage = [_style addTabButtonImage];
        if (newButtonImage) {
            [_addTabButton setUsualImage:newButtonImage];
        }
        newButtonImage = [_style addTabButtonPressedImage];
        if (newButtonImage) {
            [_addTabButton setAlternateImage:newButtonImage];
        }
        newButtonImage = [_style addTabButtonRolloverImage];
        if (newButtonImage) {
            [_addTabButton setRolloverImage:newButtonImage];
        }
        [_addTabButton setTitle:@""];
        [_addTabButton setImagePosition:NSImageOnly];
        [_addTabButton setButtonType:NSButtonTypeMomentaryChange];
        [_addTabButton setBordered:NO];
        [_addTabButton setBezelStyle:NSBezelStyleShadowlessSquare];
        if (_showAddTabButton){
            [_addTabButton setHidden:NO];
        } else {
            [_addTabButton setHidden:YES];
        }
        [_addTabButton setNeedsDisplay:YES];
        _addTabButton.action = @selector(addTab:);
        _addTabButton.target = self;
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];

    // Remove bindings.
    NSArray *temp = [_cells copy];
    for (PSMTabBarCell *cell in temp) {
        [self removeTabForCell:cell];
        cell.controlView = nil;
    }

    for (NSView *progressBar in _tabProgressBars.objectEnumerator) {
        [progressBar removeFromSuperview];
    }

    [self unregisterDraggedTypes];
}

- (void)setHeight:(CGFloat)height {
    _height = height;
}

- (void)sanityCheckFailedWithCallsite:(NSString *)callsite reason:(NSString *)reason {
    ILog(@"Sanity check failed from %@ for reason %@. Cells=%@. tabView.tabViewItems=%@ stack:\n%@",
         callsite,
         reason,
         self.cells,
         self.tabView.tabViewItems,
         [NSThread callStackSymbols]);
}

- (void)sanityCheck:(NSString *)callsite {
    [self sanityCheck:callsite force:NO];
}

- (void)sanityCheck:(NSString *)callsite force:(BOOL)force {
    if (!force && TerminalTabDrag.shared.isDragging) {
        ILog(@"Skip sanity check during drag from callsite %@", callsite);
        return;
    }
    if (self.tabView.tabViewItems.count != self.cells.count) {
        [self sanityCheckFailedWithCallsite:callsite reason:@"count mismatch"];
    } else {
        for (NSInteger i = 0; i < self.cells.count; i++) {
            NSTabViewItem *tabViewItem = self.tabView.tabViewItems[i];
            PSMTabBarCell *cell = self.cells[i];
            if (cell.representedObject != tabViewItem) {
                [self sanityCheckFailedWithCallsite:callsite reason:@"cells[i].representedObject != tabView.tabViewItems[i].representedObject"];
            }
        }
        DLog(@"Sanity check passed. cells=%@. tabView.tabViewITems=%@", self.cells, self.tabView.tabViewItems);
    }
}

#pragma mark -
#pragma mark Accessors

- (NSMutableArray *)cells
{
    return _cells;
}

- (NSEvent *)lastMouseDownEvent
{
    return _lastMouseDownEvent;
}

- (void)setLastMouseDownEvent:(NSEvent *)event
{
    _lastMouseDownEvent = event;
}

- (NSEvent *)lastMiddleMouseDownEvent
{
    return _lastMiddleMouseDownEvent;
}

- (void)setLastMiddleMouseDownEvent:(NSEvent *)event
{
    _lastMiddleMouseDownEvent = event;
}

- (void)setDelegate:(id<PSMTabBarControlDelegate>)object {
    _delegate = object;

    NSMutableArray *types = [NSMutableArray arrayWithObject:TerminalTabPasteboardType];

    //Update the allowed drag types
    if ([[self delegate] respondsToSelector:@selector(allowedDraggedTypesForTabView:)]) {
        [types addObjectsFromArray:[[self delegate] allowedDraggedTypesForTabView:_tabView]];
    }
    [self unregisterDraggedTypes];
    [self registerForDraggedTypes:types];
    _addTabButton.allowDrags = [object tabViewShouldAllowDragOnAddTabButton:_tabView];
}

- (NSString *)styleName {
    return [_style name];
}

- (void)setStyle:(id <PSMTabStyle>)newStyle {
    _style = newStyle;
    _style.tabBar = self;
    
    // restyle add tab button
    if (_addTabButton) {
        [self setupButtons];
    }

    [self update:_automaticallyAnimates];
    [self backgroundColorWillChange];
}

- (void)setOrientation:(PSMTabBarOrientation)value {
    PSMTabBarOrientation lastOrientation = _orientation;
    _orientation = value;

    if (lastOrientation != _orientation) {
        [self update];
    }
}

- (void)setDisableTabClose:(BOOL)value {
    _disableTabClose = value;
    [self setNeedsUpdate:YES animate:YES];
}

- (void)setShowAddTabButton:(BOOL)value {
    _showAddTabButton = value;
    [self setNeedsUpdate:YES];
}

- (void)setCellMinWidth:(int)value {
    _cellMinWidth = value;
    [self setNeedsUpdate:YES animate:YES];
}

- (void)setCellMaxWidth:(int)value {
    _cellMaxWidth = value;
    [self setNeedsUpdate:YES animate:YES];
}

- (void)setCellOptimumWidth:(int)value {
    _cellOptimumWidth = value;
    [self setNeedsUpdate:YES animate:YES];
}

- (void)setSizeCellsToFit:(BOOL)value {
    _sizeCellsToFit = value;
    [self setNeedsUpdate:YES animate:YES];
}

- (void)setStretchCellsToFit:(BOOL)value {
    _stretchCellsToFit = value;
    [self setNeedsUpdate:YES animate:YES];
}

- (PSMRolloverButton *)addTabButton {
    return _addTabButton;
}

- (void)setTabLocation:(int)value {
    _tabLocation = value;
    switch (value) {
        case PSMTab_TopTab:
        case PSMTab_BottomTab:
            [self setOrientation:PSMTabBarHorizontalOrientation];
            break;

        case PSMTab_LeftTab:
        case PSMTab_RightTab:
            [self setOrientation:PSMTabBarVerticalOrientation];
            break;
    }
}

- (void)setAllowsBackgroundTabClosing:(BOOL)value {
    _allowsBackgroundTabClosing = value;
    [self update];
}

- (BOOL)pointIsInEdgeDragArea:(NSPoint)point {
    const CGFloat edgeDragHeight = self.style.edgeDragHeight;
    if (edgeDragHeight <= 0) {
        return NO;
    }
    switch (_tabLocation) {
        case PSMTab_TopTab:
            return (point.y < edgeDragHeight);

        case PSMTab_BottomTab:
            return (point.y > self.bounds.size.height - edgeDragHeight);

        case PSMTab_LeftTab:
        case PSMTab_RightTab:
            break;
    }
    return NO;
}

- (BOOL)wantsMouseDownAtPoint:(NSPoint)point {
    if ([self orientation] == PSMTabBarHorizontalOrientation) {
        if ([self pointIsInEdgeDragArea:point]) {
            return NO;
        }
        if (point.x < self.insets.left) {
            return NO;
        }
        PSMTabBarCell *lastCell = _cells.lastObject;
        if (!lastCell) {
            return NO;
        }
        if (lastCell.isInOverflowMenu) {
            return YES;
        }
        const CGFloat maxX = NSMaxX(lastCell.frame);
        return point.x < maxX;
    } else {
        if (point.y < self.insets.top) {
            return NO;
        }
        PSMTabBarCell *lastCell = _cells.lastObject;
        if (!lastCell) {
            return NO;
        }
        if (lastCell.isInOverflowMenu) {
            return YES;
        }
        const CGFloat maxY = NSMaxY(lastCell.frame);
        return point.y < maxY;
    }
}

#pragma mark -
#pragma mark Functionality

// Returns the leading `length` characters of `title` for the smart-truncation
// heuristic, but first skips a leading run of decoration (whitespace, symbols,
// and punctuation). Some tab titles begin with an animated status glyph, most
// notably a Claude Code spinner such as “⠐ ”, “⠂ ”, or “✳ ” that ticks about
// once a second at an independent phase in each tab. Those glyphs are Unicode
// symbols, so if they were part of the prefix the count of unique prefixes
// would jitter as the spinners drift in and out of phase, flipping the whole
// tab bar between head and tail truncation. Keying off the stable text after
// the decoration keeps the direction steady. Enumerates by composed character
// sequence so a multi-scalar glyph (for example an emoji spinner) is treated as
// a unit rather than half-stripped. Falls back to the raw prefix when the title
// is entirely decoration.
static NSString *PSMSmartTruncationPrefix(NSString *title, NSInteger length) {
    static NSCharacterSet *content;  // the complement of the decoration set
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableCharacterSet *decoration = [[NSMutableCharacterSet alloc] init];
        [decoration formUnionWithCharacterSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        [decoration formUnionWithCharacterSet:[NSCharacterSet symbolCharacterSet]];
        [decoration formUnionWithCharacterSet:[NSCharacterSet punctuationCharacterSet]];
        content = [decoration invertedSet];
    });
    __block NSUInteger start = 0;
    [title enumerateSubstringsInRange:NSMakeRange(0, title.length)
                              options:NSStringEnumerationByComposedCharacterSequences
                           usingBlock:^(NSString *substring, NSRange substringRange, NSRange enclosingRange, BOOL *stop) {
        if ([substring rangeOfCharacterFromSet:content].location != NSNotFound) {
            *stop = YES;
            return;
        }
        start = NSMaxRange(substringRange);
    }];
    const NSUInteger remaining = title.length - start;
    if (remaining == 0) {
        // Nothing but decoration; there is no stable text to key on so fall back
        // to the raw prefix.
        return [title substringToIndex:(NSUInteger)length];
    }
    return [title substringWithRange:NSMakeRange(start, MIN((NSUInteger)length, remaining))];
}

- (NSLineBreakMode)truncationStyle {
    if (_cells.count <= 1 || !self.smartTruncation) {
        return NSLineBreakByTruncatingTail;
    }
    NSCountedSet *prefixCounts = [[NSCountedSet alloc] init];
    NSCountedSet *suffixCounts = [[NSCountedSet alloc] init];
    NSCountedSet *suffixIgnoringParenthesizedPartCounts = [[NSCountedSet alloc] init];
    NSMutableSet *uniqueTitles = [NSMutableSet set];
    static NSInteger const kPrefixOrSuffixLength = 5;
    for (PSMTabBarCell *cell in _cells) {
        NSString *title = [cell title];
        if (title.length < kPrefixOrSuffixLength) {
            continue;
        }
        [uniqueTitles addObject:title];
        NSString *prefix = PSMSmartTruncationPrefix(title, kPrefixOrSuffixLength);
        NSString *suffix = [title substringFromIndex:(NSInteger)title.length - kPrefixOrSuffixLength];
        
        [prefixCounts addObject:prefix];
        [suffixCounts addObject:suffix];

        if (self.ignoreTrailingParentheticalsForSmartTruncation && [title hasSuffix:@")"]) {
            NSInteger openParen = [title rangeOfString:@" (" options:NSBackwardsSearch].location;
            if (openParen != NSNotFound && openParen > kPrefixOrSuffixLength) {
                suffix = [title substringWithRange:NSMakeRange(openParen - kPrefixOrSuffixLength, kPrefixOrSuffixLength)];
                [suffixIgnoringParenthesizedPartCounts addObject:suffix];
            }
        }
    }
    if (uniqueTitles.count == 0) {
        return NSLineBreakByTruncatingTail;
    }

    NSUInteger suffixCount = MAX(suffixCounts.count,
                                 suffixIgnoringParenthesizedPartCounts.count);
    if (prefixCounts.count >= suffixCount) {
        return NSLineBreakByTruncatingTail;
    } else {
        return NSLineBreakByTruncatingHead;
    }
}

- (void)addTabViewItem:(NSTabViewItem *)item atIndex:(NSUInteger)i {
    // create cell
    PSMTabBarCell *cell = [[PSMTabBarCell alloc] initWithControlView:self];
    cell.truncationStyle = [self truncationStyle];
    [cell setRepresentedObject:item];
    [cell setModifierString:[self _modifierString]];

    // add to collection
    [_cells insertObject:cell atIndex:i];

    // bind it up
    [self initializeStateForCell:cell];
    [self bindPropertiesForCell:cell andTabViewItem:item];
}

- (void)addTabViewItem:(NSTabViewItem *)item {
    [self addTabViewItem:item atIndex:[_cells count]];
}

- (void)removeTabForCell:(PSMTabBarCell *)cell {
    // unbind
    [cell unbind:@"title"];

    // remove indicator
    if ([[self subviews] containsObject:[cell indicator]]) {
        [[cell indicator] setDelegate:nil];
        [[cell indicator] removeFromSuperview];
    }
    // remove tracking
    [[NSNotificationCenter defaultCenter] removeObserver:cell];

    [cell removeCloseButtonTrackingRectFrom:self];
    [cell removeCellTrackingRectFrom:self];
    [self removeAllToolTips];
    [self removeTabProgressBarForCell:cell];

    // pull from collection
    [_cells removeObject:cell];
}

- (BOOL)shouldShowCustomProgressBarForTabCell:(PSMTabBarCell *)cell {
    return NO;
}

- (NSView *)customProgressBarViewForTabCell:(PSMTabBarCell *)cell {
    return nil;
}

- (void)configureCustomProgressBarView:(NSView *)view forTabCell:(PSMTabBarCell *)cell {
}

- (void)removeTabProgressBarForCell:(PSMTabBarCell *)cell {
    NSView *progressBar = [_tabProgressBars objectForKey:cell];
    if (!progressBar) {
        return;
    }
    [progressBar removeFromSuperview];
    [_tabProgressBars removeObjectForKey:cell];
}

- (void)syncTabProgressBars {
    NSMutableSet<PSMTabBarCell *> *visibleCells = [NSMutableSet set];
    for (PSMTabBarCell *cell in _cells) {
        if (![self shouldShowCustomProgressBarForTabCell:cell]) {
            [self removeTabProgressBarForCell:cell];
            continue;
        }
        [visibleCells addObject:cell];
        NSView *progressBar = [_tabProgressBars objectForKey:cell];
        if (!progressBar) {
            progressBar = [self customProgressBarViewForTabCell:cell];
            if (!progressBar) {
                continue;
            }
            [_tabProgressBars setObject:progressBar forKey:cell];
        }
        progressBar.frame = [self.style progressBarRectForTabCell:cell];
        [self configureCustomProgressBarView:progressBar forTabCell:cell];
        if ([self.style respondsToSelector:@selector(progressBarClipPathForTabCell:)]) {
            NSBezierPath *clipPath = [self.style progressBarClipPathForTabCell:cell];
            if (clipPath) {
                // Convert the clip path from the tab bar's flipped coordinate
                // system to the progress bar layer's non-flipped coordinate system.
                const NSRect frame = progressBar.frame;
                NSAffineTransformStruct s = {
                    .m11 = 1,
                    .m12 = 0,
                    .m21 = 0,
                    .m22 = -1,
                    .tX = -frame.origin.x,
                    .tY = frame.size.height + frame.origin.y
                };
                NSAffineTransform *transform = [[NSAffineTransform alloc] init];
                [transform setTransformStruct:s];
                NSBezierPath *localPath = [transform transformBezierPath:clipPath];
                CAShapeLayer *mask = [CAShapeLayer layer];
                mask.path = [localPath iterm_CGPath];
                // Even-odd so a clip path with a nested subpath (e.g. the Tahoe
                // ring around the pill) punches out its interior. Harmless for
                // single-subpath clip paths, where it matches nonzero.
                mask.fillRule = kCAFillRuleEvenOdd;
                progressBar.wantsLayer = YES;
                progressBar.layer.mask = mask;
            } else {
                progressBar.layer.mask = nil;
            }
        } else {
            progressBar.layer.mask = nil;
        }
        progressBar.hidden = NO;
        if (progressBar.superview != self) {
            [self addSubview:progressBar];
        }
        cell.indicator.hidden = YES;
        cell.indicator.animate = NO;
        [cell.indicator removeFromSuperview];
    }

    for (PSMTabBarCell *cell in _tabProgressBars.keyEnumerator.allObjects) {
        if (![visibleCells containsObject:cell]) {
            NSView *progressBar = [_tabProgressBars objectForKey:cell];
            [progressBar removeFromSuperview];
            [_tabProgressBars removeObjectForKey:cell];
        }
    }
}

- (void)dragDidFinish {
    _preDragSelectedTabIndex = NSNotFound;
}

- (void)dragWillExitTabBar {
    const NSInteger count = self.tabView.tabViewItems.count;
    if (_preDragSelectedTabIndex == NSNotFound || _preDragSelectedTabIndex < 0 || _preDragSelectedTabIndex >= count) {
        // There is no most-recent. Can we select the next one?
        if (count == 1) {
            // No next one exists.
            return;
        }
        NSInteger currentIndex = [[self tabView] indexOfTabViewItem:self.tabView.selectedTabViewItem];
        if (currentIndex == NSNotFound) {
            // Shouldn't happen
            return;
        }
        NSInteger indexToSelect;
        if (currentIndex + 1 < count) {
            indexToSelect = currentIndex + 1;
        } else {
            indexToSelect = currentIndex - 1;
        }
        [self.tabView selectTabViewItem:self.tabView.tabViewItems[indexToSelect]];
        return;
    }
    [self.tabView selectTabViewItem:self.tabView.tabViewItems[_preDragSelectedTabIndex]];
    _preDragSelectedTabIndex = NSNotFound;
}

#pragma mark -
#pragma mark Hide/Show

- (void)backgroundColorWillChange {
    _overflowPopUpButton.appearance = _style.accessoryAppearance;
    _addTabButton.appearance = _style.accessoryAppearance;
}

#pragma mark -
#pragma mark Drawing

- (BOOL)isFlipped
{
    return YES;
}

// In sonoma, rect can be larger than the bounds and filling can cause other views to be drawn over. WTF
- (void)drawRect:(NSRect)insaneRect {

    const NSRect rect = NSIntersectionRect(self.bounds, insaneRect);
    for (PSMTabBarCell *cell in [self cells]) {
        [cell setIsLast:NO];
    }
    [[[self cells] lastObject] setIsLast:YES];
    [_style drawTabBar:self
                inRect:self.bounds
              clipRect:rect
            horizontal:(_orientation == PSMTabBarHorizontalOrientation)
          withOverflow:_lainOutWithOverflow];

}

- (void)moveTabAtIndex:(NSInteger)sourceIndex toIndex:(NSInteger)destIndex
{
    [TerminalTabOrdering moveIn:self from:sourceIndex to:destIndex];
}

- (void)update {
    [self update:NO];
}

- (void)setFrame:(NSRect)frame {
    [super setFrame:frame];
    [self syncTabProgressBars];
}

- (void)update:(BOOL)animate {
    // Make sure all of our tabs are accounted for before updating.
    if ([_tabView numberOfTabViewItems] != [_cells count]) {
        return;
    }

    [self coalesceToolTipUpdates:^{
        [self reallyUpdate:animate];
    }];
}

- (void)coalesceToolTipUpdates:(void (^)(void))block {
    NSArray<PSMToolTip *> *before = [_tooltips copy];
    _toolTipCoalescing += 1;
    block();
    _toolTipCoalescing -= 1;
    if (_toolTipCoalescing > 0) {
        return;
    }
    if ([_tooltips isEqual:before]) {
        // Copy old objects back so we can have the tags set.
        [_tooltips removeAllObjects];
        [_tooltips addObjectsFromArray:before];
        return;
    }
    [super removeAllToolTips];
    [_tooltips enumerateObjectsUsingBlock:^(PSMToolTip * _Nonnull tip, NSUInteger idx, BOOL * _Nonnull stop) {
        const NSToolTipTag tag = [super addToolTipRect:tip.rect owner:tip.owner userData:tip.data];
        tip.tag = @(tag);
    }];
}

- (void)removeAllToolTips {
    [_tooltips removeAllObjects];
    if (!_toolTipCoalescing) {
        [super removeAllToolTips];
    }
}

- (NSToolTipTag)addToolTipRect:(NSRect)rect owner:(id)owner userData:(nullable void *)data {
    NSNumber *tagNumber = nil;
    if (!_toolTipCoalescing) {
        const NSToolTipTag tag = [super addToolTipRect:rect owner:owner userData:data];
        tagNumber = @(tag);
    }
    [_tooltips addObject:[PSMToolTip toolTipWithRect:rect owner:owner userData:data tag:tagNumber]];
    return tagNumber.integerValue;
}

- (void)removeToolTip:(NSToolTipTag)tag {
    NSUInteger index = [_tooltips indexOfObjectPassingTest:^BOOL(PSMToolTip * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        return obj.tag != nil && obj.tag.integerValue == tag;
    }];
    if (index != NSNotFound) {
        [_tooltips removeObjectAtIndex:index];
    }

    if (!_toolTipCoalescing) {
        [super removeToolTip:tag];
    }
}

- (void)reallyUpdate:(BOOL)animate {
    [self _removeCellTrackingRects];

    NSLineBreakMode truncationStyle = [self truncationStyle];

    // Update cells' settings in case they changed.
    for (PSMTabBarCell *cell in _cells) {
        cell.truncationStyle = truncationStyle;
        cell.hasCloseButton = _hasCloseButton;
        [cell updateForStyle];
        cell.isCloseButtonSuppressed = [self disableTabClose];
        // Remove highlight if cursor is no longer in cell. Could happen if
        // cell moves because of added/removed tab. Tracking rects aren't smart
        // enough to handle this.
        [cell updateHighlight];
        [cell updateIndicators];
    }

    NSArray *regular = [self layoutValuesWithOverflow:NO];
    NSArray *overflow = regular.count == _cells.count ? regular : [self layoutValuesWithOverflow:YES];
    [self finishUpdateWithRegularWidths:regular widthsWithOverflow:overflow];
    [self syncTabProgressBars];
    [self setNeedsDisplay:YES];
}

- (NSArray<NSNumber *> *)layoutValuesWithOverflow:(BOOL)overflow {
    if (_orientation == PSMTabBarHorizontalOrientation) {
        return [TerminalTabLayout widthsForBar:self cells:_cells available:[self availableCellWidthWithOverflow:overflow]];
    }
    return [self verticalOriginsForCells:_cells];
}

- (NSArray<NSNumber *> *)verticalOriginsForCells:(NSArray<PSMTabBarCell *> *)cells {
    return [TerminalTabLayout originsForCount:cells.count top:self.style.topMarginForTabBarControl
                                       height:self.height bottom:NSHeight(self.bounds) showsAddButton:self.showAddTabButton];
}

- (void)removeCell:(PSMTabBarCell *)cell {
    [cell removeCloseButtonTrackingRectFrom:self];
    [cell removeCellTrackingRectFrom:self];
    [self removeTabProgressBarForCell:cell];
    [[self cells] removeObject:cell];
}

- (void)_removeCellTrackingRects {
    // size all cells appropriately and create tracking rects
    // nuke old tracking rects
    int i, cellCount = [_cells count];

    for (i = 0; i < cellCount; i++) {
        id cell = [_cells objectAtIndex:i];
        [cell removeCloseButtonTrackingRectFrom:self];
        [cell removeCellTrackingRectFrom:self];
    }

    //remove all tooltip rects
    [self removeAllToolTips];
}

- (void)finishUpdateWithRegularWidths:(NSArray *)regularWidths
                   widthsWithOverflow:(NSArray *)widthsWithOverflow {
    // Set up overflow menu.
    NSArray *newValues;
    if (_showAddTabButton || regularWidths.count < _cells.count) {
        newValues = widthsWithOverflow;
    } else {
        newValues = regularWidths;
    }
    NSMenu *overflowMenu = [self _setupCells:newValues];

    _lainOutWithOverflow = (overflowMenu != nil || _showAddTabButton);
    if (overflowMenu) {
        [self _setupOverflowMenu:overflowMenu];
    }

    [_overflowPopUpButton setHidden:(overflowMenu == nil)];

    // Set up add tab button.
    if (!overflowMenu && _showAddTabButton) {
        NSRect cellRect = [self genericCellRectWithOverflow:YES];
        cellRect.size = [_addTabButton frame].size;

        if ([self orientation] == PSMTabBarHorizontalOrientation) {
            cellRect = [self.style frameForAddTabButtonWithCellWidths:newValues height:self.bounds.size.height];
        } else {
            cellRect.origin.x = 0;
            cellRect.origin.y = MAX(0, NSHeight(self.bounds) - NSHeight(cellRect));
        }

        [self _setupAddTabButton:cellRect];
    } else {
        [_addTabButton setHidden:YES];
    }
}

- (NSMenu *)_setupCells:(NSArray *)newValues {
    const int cellCount = [_cells count];
    const int numberOfVisibleCells = [newValues count];
    NSRect cellRect = [self genericCellRectWithOverflow:(_showAddTabButton || cellCount > numberOfVisibleCells)];
    const NSRect generic = cellRect;
    NSMenu *overflowMenu = nil;
    const CGFloat intercellSpacing = _style.intercellSpacing;

    // Set up cells with frames and rects
    for (int i = 0; i < cellCount; i++) {
        PSMTabBarCell *cell = [_cells objectAtIndex:i];
        int tabState = 0;
        if (i < numberOfVisibleCells) {
            // set cell frame
            if ([self orientation] == PSMTabBarHorizontalOrientation) {
                cellRect.size.width = [[newValues objectAtIndex:i] floatValue];
            } else {
                cellRect.size.width = [self frame].size.width;
                cellRect.origin.y = [[newValues objectAtIndex:i] floatValue];
                cellRect.origin.x = 0;
            }
            cellRect = [_style adjustedCellRect:cellRect generic:generic];
            [cell setFrame:cellRect];

            // close button tracking rect
            if ([cell hasCloseButton] && !cell.isPinned &&
                ([[cell representedObject] isEqualTo:[_tabView selectedTabViewItem]] ||
                 [self allowsBackgroundTabClosing])) {
                    NSPoint mousePoint =
                    [self convertPoint:[[self window] convertPointFromScreen:[NSEvent mouseLocation]]
                              fromView:nil];
                    NSRect closeRect = [cell closeButtonRectForFrame:cellRect];

                    // Add the tracking rect for the close button highlight.
                    [cell removeCloseButtonTrackingRectFrom:self];
                    [cell setCloseButtonTrackingRect:closeRect userData:nil assumeInside:NO view:self];

                    // highlight the close button if the currently selected tab has the mouse over it
                    // this will happen if the user clicks a close button in a tab and all the tabs are
                    // rearranged
                    if ([[cell representedObject] isEqualTo:[_tabView selectedTabViewItem]] &&
                        [[NSApp currentEvent] type] != NSEventTypeLeftMouseDown &&
                        NSMouseInRect(mousePoint, closeRect, [self isFlipped])) {
                        [cell setCloseButtonOver:YES];
                    }
                } else {
                    [cell setCloseButtonOver:NO];
                }

            // Add entire-tab tracking rect.
            [cell removeCellTrackingRectFrom:self];
            [cell setCellTrackingRect:cellRect userData:nil assumeInside:NO view:self];
            [cell setEnabled:YES];

            //add the tooltip tracking rect
            [self addToolTipRect:cellRect owner:self userData:nil];

            // selected? set tab states...
            if ([[cell representedObject] isEqualTo:[_tabView selectedTabViewItem]]) {
                [cell setState:NSControlStateValueOn];
                tabState |= PSMTab_SelectedMask;
                // previous cell
                if (i > 0) {
                    [[_cells objectAtIndex:i-1] setTabState:([(PSMTabBarCell *)[_cells objectAtIndex:i-1] tabState] | PSMTab_RightIsSelectedMask)];
                }
                // next cell - see below
            } else {
                [cell setState:NSControlStateValueOff];
                // see if prev cell was selected
                if (i > 0) {
                    if ([[_cells objectAtIndex:i-1] state] == NSControlStateValueOn){
                        tabState |= PSMTab_LeftIsSelectedMask;
                    }
                }
            }
            // more tab states
            if (cellCount == 1) {
                tabState |= PSMTab_PositionLeftMask | PSMTab_PositionRightMask | PSMTab_PositionSingleMask;
            } else if (i == 0) {
                tabState |= PSMTab_PositionLeftMask;
            } else if (i-1 == cellCount) {
                tabState |= PSMTab_PositionRightMask;
            }
            [cell setTabState:tabState];
            [cell setIsInOverflowMenu:NO];

            // indicator
            if (![[cell indicator] isHidden]) {
                [[cell indicator] setFrame:[cell indicatorRectForFrame:cellRect]];
                if (![[self subviews] containsObject:[cell indicator]]) {
                    [self addSubview:[cell indicator]];
                    [[cell indicator] setAnimate:YES];
                }
            }

            // next...
            cellRect.origin.x += [[newValues objectAtIndex:i] floatValue] + intercellSpacing;

        } else {
            // set up menu items
            NSMenuItem *menuItem;
            if (overflowMenu == nil) {
                overflowMenu = [[NSMenu alloc] initWithTitle:@"TITLE"];
                if (@available(macOS 26, *)) {
                    // It's not a pulldown menu in 26
                } else {
                    [overflowMenu insertItemWithTitle:@"FIRST" action:nil keyEquivalent:@"" atIndex:0]; // Because the overflowPupUpButton is a pull down menu
                }
            }
            NSString *title = [[cell attributedStringValue] string] ?: @"";
            menuItem = [[NSMenuItem alloc] initWithTitle:title action:@selector(overflowMenuAction:) keyEquivalent:@""];
            [menuItem setTarget:self];
            [menuItem setRepresentedObject:[cell representedObject]];
            [cell setIsInOverflowMenu:YES];
            [[cell indicator] removeFromSuperview];
            if ([[cell representedObject] isEqualTo:[_tabView selectedTabViewItem]]) {
                [menuItem setState:NSControlStateValueOn];
            }

            if ([cell hasIcon]) {
                [menuItem setImage:(NSImage *)[(id)[[cell representedObject] identifier] icon]];
            }

            if ([cell count] > 0) {
                [menuItem setTitle:[[menuItem title] stringByAppendingFormat:@" (%d)", [cell count]]];
            }

            [overflowMenu addItem:menuItem];
        }
    }

    return overflowMenu;
}

- (void)_setupOverflowMenu:(NSMenu *)overflowMenu {
    _overflowPopUpButton.frame = [_style frameForOverflowButtonWithAddTabButton:self.showAddTabButton
                                                                  enclosureSize:self.frame.size
                                                                 standardHeight:self.height];

    if (![[self subviews] containsObject:_overflowPopUpButton]) {
        [self addSubview:_overflowPopUpButton];
    }

    if (overflowMenu) {
        // Have a candidate for new overflow menu. Does it contain the same information as the current one?
        // If they're equal, we don't want to update the menu since this happens several times per second
        // while the user is visiting the menu. But reading it is fine.
        BOOL equal = YES;
        equal = [_overflowPopUpButton menu] && [[_overflowPopUpButton menu] numberOfItems ] == [overflowMenu numberOfItems];
        for (int i = 0; equal && i < [overflowMenu numberOfItems]; i++) {
            NSMenuItem *currentItem = [[_overflowPopUpButton menu] itemAtIndex:i];
            NSMenuItem *newItem = [overflowMenu itemAtIndex:i];
            if (([newItem state] != [currentItem state]) ||
                    ([[newItem title] compare:[currentItem title]] != NSOrderedSame) ||
                    ([newItem image] != [currentItem image])) {
                equal = NO;
            }
        }

        if (!equal) {
            [_overflowPopUpButton setMenu:overflowMenu];
        }
    }
}

- (void)_setupAddTabButton:(NSRect)frame {
    if (![[self subviews] containsObject:_addTabButton]) {
        [self addSubview:_addTabButton];
    }

    if ([_addTabButton isHidden] && _showAddTabButton) {
        [_addTabButton setHidden:NO];
    }

    NSImage *image = [_style addTabButtonImage];
    if (image) {
        [_addTabButton setImage:image];
    }
    [_addTabButton setFrame:frame];
    [_addTabButton setNeedsDisplay:YES];
}

#pragma mark -
#pragma mark Mouse Tracking

- (BOOL)mouseDownCanMoveWindow
{
    return NO;
}

- (BOOL)acceptsFirstMouse:(NSEvent *)theEvent
{
    return YES;
}

- (void)otherMouseDown:(NSEvent *)theEvent {
    if ([theEvent buttonNumber] == 2) {
        [self setLastMiddleMouseDownEvent:theEvent];
    }
}

- (void)mouseDown:(NSEvent *)theEvent {
    _didDrag = NO;

    // keep for dragging
    [self setLastMouseDownEvent:theEvent];
    // what cell?
    NSPoint mousePt = [self convertPoint:[theEvent locationInWindow] fromView:nil];
    NSRect cellFrame;
    PSMTabBarCell *cell = [self cellForPoint:mousePt cellFrame:&cellFrame];
    if (cell) {
        BOOL overClose = NSMouseInRect(mousePt, [cell closeButtonRectForFrame:cellFrame], [self isFlipped]);
        if (overClose &&
            cell.closeButtonVisible &&
            ([self allowsBackgroundTabClosing] || [[cell representedObject] isEqualTo:[_tabView selectedTabViewItem]])) {
            [cell setCloseButtonOver:NO];
            [cell setCloseButtonPressed:YES];
            _closeClicked = YES;
        } else {
            [cell setCloseButtonPressed:NO];
            if ([theEvent clickCount] == 1) {
                const NSEventModifierFlags mask = NSEventModifierFlagOption;
                if (_selectsTabsOnMouseDown && (theEvent.modifierFlags & mask) == 0) {
                    if (cell.state != NSControlStateValueOn) {
                        _preDragSelectedTabIndex = [[self tabView] indexOfTabViewItem:self.tabView.selectedTabViewItem];
                    } else {
                        // Because we always want it to switch tabs, don't save
                        // the index if you're dragging the current tab.
                        _preDragSelectedTabIndex = NSNotFound;
                    }
                    [self tabClick:cell];
                }
            }
        }
        [self setNeedsDisplay:YES];
    }
}

- (void)mouseDragged:(NSEvent *)theEvent {
    if ([self lastMouseDownEvent] == nil) {
        if (!_addTabButton.allowDrags) {
            [super mouseDragged:theEvent];
        }
        return;
    }
    if (!_haveInitialDragLocation) {
        _initialDragLocation = [theEvent locationInWindow];
        _haveInitialDragLocation = YES;
        return;
    }

    NSPoint currentPoint = [self convertPoint:[theEvent locationInWindow] fromView:nil];

    if ([self.delegate respondsToSelector:@selector(tabViewShouldDragWindow:event:)] &&
        [self.delegate tabViewShouldDragWindow:_tabView event:theEvent]) {
        [self.window makeKeyAndOrderFront:nil];
        [self.window performWindowDragWithEvent:theEvent];
        return;
    }

    NSRect cellFrame;
    NSPoint trackingStartPoint = [self convertPoint:_initialDragLocation fromView:nil];
    PSMTabBarCell *cell = [self cellForPoint:trackingStartPoint cellFrame:&cellFrame];
    if (cell) {
        //check to see if the close button was the target in the clicked cell
        //highlight/unhighlight the close button as necessary
        NSRect iconRect = [cell closeButtonRectForFrame:cellFrame];

        if (_closeClicked && NSMouseInRect(trackingStartPoint, iconRect, [self isFlipped]) &&
                ([self allowsBackgroundTabClosing] || [[cell representedObject] isEqualTo:[_tabView selectedTabViewItem]])) {
            [cell setCloseButtonPressed:NSMouseInRect(currentPoint, iconRect, [self isFlipped])];
            [self setNeedsDisplay:YES];
            return;
        }

        float dx = fabs(currentPoint.x - trackingStartPoint.x);
        float dy = fabs(currentPoint.y - trackingStartPoint.y);
        float distance = sqrt(dx * dx + dy * dy);

        if (distance >= self.minimumTabDragDistance && !_didDrag && !TerminalTabDrag.shared.isDragging &&
                [[self delegate] respondsToSelector:@selector(tabView:shouldDragTabViewItem:fromTabBar:)] &&
                [[self delegate] tabView:_tabView shouldDragTabViewItem:[cell representedObject] fromTabBar:self]) {
            _didDrag = YES;
            ILog(@"Start dragging with mouse down event %@ in window %p with frame %@", [self lastMouseDownEvent], self.window, NSStringFromRect(self.window.frame));
            [TerminalTabDrag.shared beginFrom:self cell:cell event:theEvent];
        }
    }
}

- (void)otherMouseUp:(NSEvent *)theEvent
{
    // Middle click closes a tab, even if the click is not on the close button.
    if ([theEvent buttonNumber] == 2) {
        NSPoint mousePt = [self convertPoint:[theEvent locationInWindow] fromView:nil];
        NSRect cellFrame;
        PSMTabBarCell *cell = [self cellForPoint:mousePt cellFrame:&cellFrame];
        NSRect mouseDownCellFrame;
        PSMTabBarCell *mouseDownCell = [self cellForPoint:[self convertPoint:[[self lastMiddleMouseDownEvent] locationInWindow] fromView:nil]
                                                cellFrame:&mouseDownCellFrame];
        if (cell && cell == mouseDownCell) {
            [self closeTabClick:cell button:theEvent.buttonNumber];
        }
    }
}

- (void)mouseUp:(NSEvent *)theEvent {
    _preDragSelectedTabIndex = NSNotFound;
    _haveInitialDragLocation = NO;
    [self handleMouseUp:theEvent];

    _closeClicked = NO;
}

- (void)handleMouseUp:(NSEvent * _Nonnull)theEvent {
    const NSPoint clickPoint = [self convertPoint:[theEvent locationInWindow] fromView:nil];
    NSRect cellFrame;
    PSMTabBarCell *const cell = [self cellForPoint:clickPoint cellFrame:&cellFrame];

    NSRect mouseDownCellFrame;
    PSMTabBarCell *mouseDownCell = [self cellForPoint:[self convertPoint:[[self lastMouseDownEvent] locationInWindow] fromView:nil] cellFrame:&mouseDownCellFrame];
    const NSRect iconRect = [mouseDownCell closeButtonRectForFrame:mouseDownCellFrame];
    const BOOL clickedInCloseButton = NSMouseInRect(clickPoint, iconRect, [self isFlipped]);

    if (clickedInCloseButton &&
        cell.closeButtonVisible &&
        cell.hasCloseButton &&
        [mouseDownCell closeButtonPressed]) {
        // Clicked on close button
        [self closeTabClick:cell button:theEvent.buttonNumber];
        return;
    }

    if (cell == nil && [theEvent clickCount] == 2) {
        [self tabBarDoubleClick];
    }

    const BOOL mouseUpInSameCellAsMouseDown = NSMouseInRect(clickPoint, mouseDownCellFrame, [self isFlipped]);
    const NSPoint trackingStartPoint = [self convertPoint:[[self lastMouseDownEvent] locationInWindow] fromView:nil];
    const BOOL mouseDownWasInCloseButton = NSMouseInRect(trackingStartPoint, [cell closeButtonRectForFrame:cellFrame], [self isFlipped]);
    const BOOL closeButtonDoesNotInterfere = (!mouseDownWasInCloseButton ||
                                              [self disableTabClose] ||
                                              ![self allowsBackgroundTabClosing]);

    if (mouseUpInSameCellAsMouseDown && closeButtonDoesNotInterfere) {
        // Is a valid click on the tab.
        [mouseDownCell setCloseButtonPressed:NO];
        switch (theEvent.clickCount) {
            case 1:
                [self tabClick:cell];
                return;

            case 2:
                [self tabDoubleClick:cell];
                return;

            default:
                return;
        }
    }

    // Weird cases we don't care about, like mouse down in one cell and mouse up in another.
    [mouseDownCell setCloseButtonPressed:NO];
    [self tabNothing:cell];
}

- (NSMenu *)menuForEvent:(NSEvent *)event
{
    NSMenu *menu = nil;
    NSTabViewItem *item = [[self cellForPoint:[self convertPoint:[event locationInWindow] fromView:nil] cellFrame:nil] representedObject];

    if (item && [[self delegate] respondsToSelector:@selector(tabView:menuForTabViewItem:)]) {
        menu = [[self delegate] tabView:_tabView menuForTabViewItem:item];
    }
    else if (!item) {
        // when the "LSUIElement hack" (issue #954) is enabled, the menu bar is inaccessible,
        // so show it as a context menu when right-clicking empty tabBar region
        if ([[[NSBundle mainBundle] infoDictionary] objectForKey:@"LSUIElement"]) {
            menu = [NSApp mainMenu];
        }
    }
    return menu;
}

- (void)resetCursorRects
{
    [super resetCursorRects];
    if ([self orientation] == PSMTabBarVerticalOrientation) {
        NSRect frame = [self frame];
        const CGFloat cursorX = (_tabLocation == PSMTab_RightTab) ? 0 : frame.size.width - 2;
        [self addCursorRect:NSMakeRect(cursorX, 0, 2, frame.size.height) cursor:[NSCursor resizeLeftRightCursor]];
    } else {
        const CGFloat edgeDragHeight = self.style.edgeDragHeight;
        if (edgeDragHeight == 0) {
            return;
        }
        switch (_tabLocation) {
            case PSMTab_TopTab:
                [self addCursorRect:NSMakeRect(0, 0, self.bounds.size.width, edgeDragHeight)
                             cursor:[NSCursor openHandCursor]];
                break;
            case PSMTab_BottomTab:
                [self addCursorRect:NSMakeRect(0,
                                               self.bounds.size.height - edgeDragHeight,
                                               self.bounds.size.width,
                                               edgeDragHeight)
                             cursor:[NSCursor openHandCursor]];
                break;

            case PSMTab_LeftTab:
            case PSMTab_RightTab:
                break;
        }
    }
}

#pragma mark -
#pragma mark Drag and Drop

- (BOOL)shouldDelayWindowOrderingForEvent:(NSEvent *)theEvent
{
    return YES;
}

#pragma mark NSDraggingSource

- (BOOL)ignoreModifierKeysForDraggingSession:(NSDraggingSession *)session { return YES; }

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    return [TerminalTabDrag.shared updateDestination:self sender:sender];
}

- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)sender {
    return [TerminalTabDrag.shared updateDestination:self sender:sender];
}

- (void)draggingExited:(id<NSDraggingInfo>)sender {
    [TerminalTabDrag.shared exitDestination:self];
}

- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)sender {
    return [self draggingUpdated:sender] != NSDragOperationNone;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    return [TerminalTabDrag.shared dropIn:self sender:sender];
}

- (void)draggingSession:(NSDraggingSession *)session endedAtPoint:(NSPoint)point operation:(NSDragOperation)operation {
    _haveInitialDragLocation = NO;
    [TerminalTabDrag.shared endAt:point operation:operation];
}

#pragma mark -
#pragma mark Actions

- (void)overflowMenuAction:(id)sender {
    [_tabView selectTabViewItem:[sender representedObject]];
    [self update];
}

- (void)closeTabClick:(id)sender button:(int)button {
    NSTabViewItem *item = [sender representedObject];



    if ([[self delegate] respondsToSelector:@selector(tabView:shouldCloseTabViewItem:)]){
        if (![[self delegate] tabView:_tabView shouldCloseTabViewItem:item]){
            // fix mouse downed close button
            [sender setCloseButtonPressed:NO];
            return;
        }
    }

    if ([[self delegate] respondsToSelector:@selector(tabView:closeTab:button:)]) {
        [[self delegate] tabView:[self tabView] closeTab:[item identifier] button:button];
    }
}

- (void)tabClick:(id)sender {
    if ([sender representedObject]) {
        [_tabView selectTabViewItem:[sender representedObject]];
        [self update];
    }
}

- (void)tabDoubleClick:(id)sender {
    if ([[self delegate] respondsToSelector:@selector(tabView:doubleClickTabViewItem:)]) {
        [[self delegate] tabView:[self tabView] doubleClickTabViewItem:[sender representedObject]];
    }
}

- (void)tabBarDoubleClick {
    if ([[self delegate] respondsToSelector:@selector(tabViewDoubleClickTabBar:)]) {
        [[self delegate] tabViewDoubleClickTabBar:[self tabView]];
    }
}

- (void)addTab:(id)sender {
    if ([self.delegate respondsToSelector:@selector(tabViewDidClickAddTabButton:)]) {
        [self.delegate tabViewDidClickAddTabButton:self];
    }
}

- (void)tabNothing:(id)sender {
    [self update];  // takes care of highlighting based on state
}

- (BOOL)supportsMultiLineLabels {
    return [_style supportsMultiLineLabels];
}

- (void)frameDidChange:(NSNotification *)notification {
    [self update];
    // trying to address the drawing artifacts for the progress indicators - hackery follows
    // this one fixes the "blanking" effect when the control hides and shows itself
    for (PSMTabBarCell *cell in _cells) {
        [[cell indicator] setAnimate:NO];
        [[cell indicator] setAnimate:YES];
    }
    [self setNeedsDisplay:YES];
}

- (void)viewWillStartLiveResize {
    for (PSMTabBarCell *cell in _cells) {
        [[cell indicator] setAnimate:NO];
    }
    [self setNeedsDisplay:YES];
}

-(void)viewDidEndLiveResize {
    for (PSMTabBarCell *cell in _cells) {
        [[cell indicator] setAnimate:YES];
    }
    [self setNeedsDisplay:YES];
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];

    // Rebuild tracking areas for all visible cells based on their current frames.
    // This ensures tracking areas stay valid after view lifecycle events like
    // moving to a different window, display sleep/wake, etc.
    const NSPoint mousePoint = [self convertPoint:[[self window] convertPointFromScreen:[NSEvent mouseLocation]]
                                         fromView:nil];

    for (PSMTabBarCell *cell in _cells) {
        if ([cell isInOverflowMenu]) {
            continue;
        }

        const NSRect cellFrame = [cell frame];

        // Rebuild cell tracking rect.
        [cell removeCellTrackingRectFrom:self];
        [cell setCellTrackingRect:cellFrame userData:nil assumeInside:NO view:self];

        // Update highlight state based on current mouse position.
        // This clears highlight if cursor is no longer in cell.
        [cell updateHighlight];
        if (NSMouseInRect(mousePoint, cellFrame, [self isFlipped])) {
            [cell setHighlighted:YES];
        }

        // Always remove close button tracking rect first.
        [cell removeCloseButtonTrackingRectFrom:self];

        // Rebuild close button tracking rect if applicable.
        if ([cell hasCloseButton] &&
            ([[cell representedObject] isEqualTo:[_tabView selectedTabViewItem]] ||
             [self allowsBackgroundTabClosing])) {
            const NSRect closeRect = [cell closeButtonRectForFrame:cellFrame];

            [cell setCloseButtonTrackingRect:closeRect userData:nil assumeInside:NO view:self];

            // Update close button highlight state for the selected tab only.
            if ([[cell representedObject] isEqualTo:[_tabView selectedTabViewItem]] &&
                [[NSApp currentEvent] type] != NSEventTypeLeftMouseDown &&
                NSMouseInRect(mousePoint, closeRect, [self isFlipped])) {
                [cell setCloseButtonOver:YES];
            } else {
                [cell setCloseButtonOver:NO];
            }
        } else {
            [cell setCloseButtonOver:NO];
        }
    }

    [self setNeedsDisplay:YES];
}

- (void)windowDidMove:(NSNotification *)aNotification {
    [self setNeedsDisplay:YES];
}

- (void)windowStatusDidChange:(NSNotification *)notification {
    [self setNeedsDisplay:YES];
    [self update];
}

#pragma mark -
#pragma mark Menu Validation

- (BOOL)validateMenuItem:(NSMenuItem *)sender {
    return [[self delegate] respondsToSelector:@selector(tabView:validateOverflowMenuItem:forTabViewItem:)] ?
        [[self delegate] tabView:[self tabView] validateOverflowMenuItem:sender forTabViewItem:[sender representedObject]] : YES;
}

#pragma mark -
#pragma mark NSTabView Delegate

- (void)tabView:(NSTabView *)aTabView willAddTabViewItem:(NSTabViewItem *)tabViewItem {
    if ([[self delegate] respondsToSelector:@selector(tabView:willAddTabViewItem:)]){
        [[self delegate] tabView:aTabView willAddTabViewItem:tabViewItem];
    }
}

- (void)tabView:(NSTabView *)aTabView willInsertTabViewItem:(NSTabViewItem *)tabViewItem atIndex:(int)anIndex {
    if ([[self delegate] respondsToSelector:@selector(tabView:willInsertTabViewItem:atIndex:)]) {
        [[self delegate] tabView:aTabView willInsertTabViewItem:tabViewItem atIndex:anIndex];
    }
}

- (void)tabView:(NSTabView *)aTabView willRemoveTabViewItem:(NSTabViewItem *)tabViewItem {
    if ([[self delegate] respondsToSelector:@selector(tabView:willRemoveTabViewItem:)]) {
        [[self delegate] tabView:aTabView willRemoveTabViewItem:tabViewItem];
    }
}


- (void)tabView:(NSTabView *)aTabView didSelectTabViewItem:(NSTabViewItem *)tabViewItem {
    // here's a weird one - this message is sent before the "aDidChangeNumberOfTabViewItems"
    // message, thus I can end up updating when there are no cells, if no tabs were (yet) present
    if ([_cells count] > 0) {
        [self update];
    }
    if ([[self delegate] respondsToSelector:@selector(tabView:didSelectTabViewItem:)]) {
        [[self delegate] tabView:aTabView didSelectTabViewItem:tabViewItem];
    }

    NSAccessibilityPostNotification(self, NSAccessibilityValueChangedNotification);
}

- (void)tabView:(NSTabView *)tabView doubleClickTabViewItem:(NSTabViewItem *)tabViewItem {
}

- (BOOL)tabView:(NSTabView *)aTabView shouldSelectTabViewItem:(NSTabViewItem *)tabViewItem {
    if ([[self delegate] respondsToSelector:@selector(tabView:shouldSelectTabViewItem:)]) {
        return (BOOL)[[self delegate] tabView:aTabView shouldSelectTabViewItem:tabViewItem];
    } else {
        return YES;
    }
}

- (void)tabView:(NSTabView *)aTabView willSelectTabViewItem:(NSTabViewItem *)tabViewItem {
    if ([[self delegate] respondsToSelector:@selector(tabView:willSelectTabViewItem:)]) {
        [[self delegate] tabView:aTabView willSelectTabViewItem:tabViewItem];
    }
}

- (void)tabViewDidChangeNumberOfTabViewItems:(NSTabView *)aTabView {
    [TerminalTabOrdering synchronize:self with:aTabView];
}

- (NSDragOperation)tabView:(NSTabView *)tabView draggingEnteredTabBarForSender:(id<NSDraggingInfo>)tagViewItem {
    return NSDragOperationNone;
}

- (BOOL)tabView:(NSTabView *)tabView shouldAcceptDragFromSender:(id<NSDraggingInfo>)tagViewItem {
    return NO;
}

- (NSTabViewItem *)tabView:(NSTabView *)tabView unknownObjectWasDropped:(id <NSDraggingInfo>)sender {
    return nil;
}

#pragma mark -
#pragma mark Tooltips

- (NSString *)view:(NSView *)view stringForToolTip:(NSToolTipTag)tag point:(NSPoint)point userData:(void *)userData
{
    // Schedule updating the tooltip window's appearance after it's created
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateTooltipAppearance];
    });

    if ([[self delegate] respondsToSelector:@selector(tabView:toolTipForTabViewItem:)]) {
        return [[self delegate] tabView:[self tabView] toolTipForTabViewItem:[[self cellForPoint:point cellFrame:nil] representedObject]];
    }
    return @"";
}

- (void)updateTooltipAppearance {
    NSAppearance *desiredAppearance = _style.accessoryAppearance;
    if (!desiredAppearance) {
        return;
    }

    // Tooltips just use the system light/dark mode, not that of the view that created them.
    // Since you generally only have one tooltip at a time, go find the one we assume is ours and
    // set its appearance properly.
    for (NSWindow *window in [NSApp windows]) {
        if ([[window className] isEqualToString:@"NSToolTipPanel"]) {
            window.appearance = desiredAppearance;
            break;
        }
    }
}


#pragma mark -
#pragma mark IB Palette

- (NSSize)minimumFrameSizeFromKnobPosition:(int)position {
    return NSMakeSize(100.0, 22.0);
}

- (NSSize)maximumFrameSizeFromKnobPosition:(int)knobPosition {
    return NSMakeSize(10000.0, 22.0);
}

- (void)placeView:(NSRect)newFrame {
    // this is called any time the view is resized in IB
    [self setFrame:newFrame];
    [self update];
}

- (void)changeIdentifier:(id)newIdentifier atIndex:(int)theIndex {
    NSTabViewItem *tabViewItem = [_tabView tabViewItemAtIndex:theIndex];
    assert(tabViewItem);
    for (PSMTabBarCell *cell in _cells) {
        if ([cell representedObject] == tabViewItem) {
            [tabViewItem setIdentifier:newIdentifier];
            return;
        }
    }
    assert(false);
}

#pragma mark -
#pragma mark Convenience

- (PSMTabBarCell *)cellWithIdentifier:(id)identifier {
    for (PSMTabBarCell *cell in _cells) {
        if ([cell.representedObject identifier] == identifier) {
            return cell;
        }
    }
    return nil;
}

- (void)setIsProcessing:(BOOL)isProcessing forTabWithIdentifier:(id)identifier {
    PSMTabBarCell *cell = [self cellWithIdentifier:identifier];
    cell.isProcessing = isProcessing;
}

- (void)setProgress:(PSMProgress)progress forTabWithIdentifier:(id)identifier {
    PSMTabBarCell *cell = [self cellWithIdentifier:identifier];
    cell.progress = progress;
    [self syncTabProgressBars];
}

- (BOOL)isInOverflowMenuForTabWithIdentifier:(id)identifier {
    PSMTabBarCell *cell = [self cellWithIdentifier:identifier];
    return cell.isInOverflowMenu;
}

- (void)graphicDidChangeForTabWithIdentifier:(id)identifier {
    PSMTabBarCell *cell = [self cellWithIdentifier:identifier];
    [self setNeedsDisplayInRect:cell.frame];
}

- (void)setIcon:(NSImage *)icon forTabWithIdentifier:(id)identifier {
    PSMTabBarCell *cell = [self cellWithIdentifier:identifier];
    cell.hasIcon = (icon != nil);
}

- (void)setObjectCount:(NSInteger)objectCount forTabWithIdentifier:(id)identifier {
    PSMTabBarCell *cell = [self cellWithIdentifier:identifier];
    cell.count = objectCount;
}

- (void)initializeStateForCell:(PSMTabBarCell *)cell {
    [[cell indicator] setHidden:YES];
    [cell setHasIcon:NO];
    [cell setCount:0];
}

- (void)bindPropertiesForCell:(PSMTabBarCell *)cell andTabViewItem:(NSTabViewItem *)item {
    // bind my string value to the label on the represented tab
    // cell.title <- item.label
    [cell bind:@"title" toObject:item withKeyPath:@"label" options:nil];
    [_delegate tabView:_tabView updateStateForTabViewItem:item];
}

- (NSMutableArray *)representedTabViewItems {
    NSMutableArray *temp = [NSMutableArray arrayWithCapacity:[_cells count]];
    for (PSMTabBarCell *cell in _cells) {
        if ([cell representedObject]) {
            [temp addObject:[cell representedObject]];
        }
    }
    return temp;
}

- (id)cellForPoint:(NSPoint)point
         cellFrame:(NSRectPointer)outFrame {
    if ([self orientation] == PSMTabBarHorizontalOrientation &&
        !NSPointInRect(point, [self genericCellRectWithOverflow:_lainOutWithOverflow])) {
        return nil;
    }

    int i, cnt = [_cells count];
    for (i = 0; i < cnt; i++) {
        PSMTabBarCell *cell = [_cells objectAtIndex:i];

        if (!cell.isInOverflowMenu && NSPointInRect(point, [cell frame])) {
            if (outFrame) {
                *outFrame = [cell frame];
            }
            return cell;
        }
    }
    return nil;
}

- (int)numberOfVisibleTabs
{
    int i, cellCount = [_cells count];
    for(i = 0; i < cellCount; i++){
        if ([[_cells objectAtIndex:i] isInOverflowMenu]) {
            return i;
        }
    }
    return cellCount;
}

#pragma mark -
#pragma mark Accessibility

- (NSString*)accessibilityRole {
    return NSAccessibilityTabGroupRole;
}

- (NSArray*)accessibilityChildren {
    NSMutableArray *childElements = [NSMutableArray array];
    for (PSMTabBarCell *cell in [_cells objectsAtIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, [self numberOfVisibleTabs])]]) {
        [childElements addObject:cell.element];
    }
    if (![_overflowPopUpButton isHidden]) {
        [childElements addObject:_overflowPopUpButton];
    }
    if (![_addTabButton isHidden]) {
        [childElements addObject:_addTabButton];
    }
    return childElements;
}

- (NSArray*)accessibilityTabs {
    NSMutableArray *tabElements = [NSMutableArray array];
    for (PSMTabBarCell *cell in _cells) {
        [tabElements addObject:cell.element];
    }
    return tabElements;
}

- (id)accessibilityHitTest:(NSPoint)point {
    for (id child in self.accessibilityChildren) {
        if (NSPointInRect(point, [child accessibilityFrame])) {
            return [child accessibilityHitTest:point];
        }
    }
    return self;
}

#pragma mark - iTerm Add On

- (void)setTabColor:(NSColor *)aColor forTabViewItem:(NSTabViewItem *)tabViewItem {
    BOOL updated = NO;

    for (PSMTabBarCell *cell in _cells) {
        if ([cell representedObject] == tabViewItem) {
            if ([cell tabColor] != aColor) {
                updated = YES;
                [cell setTabColor:aColor];
            }
        }
    }

    if (updated) {
        [self update: NO];
    }
}

- (NSColor*)tabColorForTabViewItem:(NSTabViewItem*)tabViewItem {
    for (PSMTabBarCell *cell in _cells) {
        if ([cell representedObject] == tabViewItem) {
            return [cell tabColor];
        }
    }
    return nil;
}

- (void)setIsPinned:(BOOL)pinned forTabViewItem:(NSTabViewItem *)tabViewItem {
    BOOL updated = NO;

    for (PSMTabBarCell *cell in _cells) {
        if ([cell representedObject] == tabViewItem) {
            if ([cell isPinned] != pinned) {
                updated = YES;
                [cell setIsPinned:pinned];
            }
        }
    }

    if (updated) {
        [self update:YES];
    }
}

- (BOOL)isPinnedForTabViewItem:(NSTabViewItem *)tabViewItem {
    for (PSMTabBarCell *cell in _cells) {
        if ([cell representedObject] == tabViewItem) {
            return [cell isPinned];
        }
    }
    return NO;
}

- (void)modifierChanged:(NSNotification *)aNotification {
    NSUInteger mask = ([[[aNotification userInfo] objectForKey:kPSMTabModifierKey] unsignedIntegerValue]);
    if (mask == NSUIntegerMax) {
        mask = 0;
    }
    [self setModifier:mask];
}

- (NSString*)_modifierString {
    NSString *str = @"";
    if (_modifier & NSEventModifierFlagCommand) {
        str = [NSString stringWithFormat:@"⌘%@", str];
    }
    if (_modifier & NSEventModifierFlagShift) {
        str = [NSString stringWithFormat:@"⇧%@", str];
    }
    if (_modifier & NSEventModifierFlagOption) {
        str = [NSString stringWithFormat:@"⌥%@", str];
    }
    if (_modifier & NSEventModifierFlagControl) {
        str = [NSString stringWithFormat:@"^%@", str];
    }
    return str;
}

- (void)setModifier:(NSUInteger)mask {
    _modifier = mask;
    NSString *str = [self _modifierString];

    for (PSMTabBarCell *cell in _cells) {
        [cell setModifierString:str];
    }
    [self setNeedsDisplay:YES];
}

- (void)fillPath:(NSBezierPath*)path {
  [_style fillPath:path];
}

- (NSColor *)accessoryTextColor {
    return [_style accessoryTextColor] ?: [NSColor blackColor];
}

- (BOOL)shouldShowActivityIndicators {
    if ([self.delegate respondsToSelector:@selector(tabViewShouldShowActivityIndicators:)]) {
        return [self.delegate tabViewShouldShowActivityIndicators:_tabView];
    }
    return YES;
}

- (void)updateActivityIndicators {
    const BOOL hidden = ![self shouldShowActivityIndicators];
    if (hidden == _activityIndicatorsHidden) {
        return;
    }
    _activityIndicatorsHidden = hidden;
    for (PSMTabBarCell *cell in _cells) {
        [cell updateIndicators];
    }
    [self update:NO];
}

- (void)setTabsHaveCloseButtons:(BOOL)tabsHaveCloseButtons {
    _hasCloseButton = tabsHaveCloseButtons;

    for (PSMTabBarCell *cell in _cells) {
        [cell setHasCloseButton:tabsHaveCloseButtons];
    }
}

- (void)moveTabAtIndex:(NSInteger)sourceIndex toTabBar:(TerminalTabBarView *)destinationTabBar atIndex:(NSInteger)destinationIndex {
    [TerminalTabOrdering transferFrom:self index:sourceIndex to:destinationTabBar index:destinationIndex];
}

- (void)setNeedsUpdate:(BOOL)needsUpdate {
    [self setNeedsUpdate:needsUpdate animate:NO];
}

- (void)setNeedsUpdate:(BOOL)needsUpdate animate:(BOOL)animate {
    _needsUpdateAnimate |= animate;
    if (_needsUpdate == needsUpdate) {
        return;
    }
    if (!needsUpdate) {
        _needsUpdate = NO;
        return;
    }
    _needsUpdate = YES;
    __weak __typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf updateIfNeeded];
    });
}

- (void)updateIfNeeded {
    if (!_needsUpdate) {
        return;
    }
    _needsUpdate = NO;
    _needsUpdateAnimate = NO;
    [self update];
}


#pragma mark - NSDraggingSource

- (NSDragOperation)draggingSession:(NSDraggingSession *)session sourceOperationMaskForDraggingContext:(NSDraggingContext)context {
    switch (context) {
        case NSDraggingContextWithinApplication:
            return NSDragOperationEvery;

        case NSDraggingContextOutsideApplication:
        default:
            return NSDragOperationNone;
    }
}

#pragma mark - PSMProgressIndicatorDelegate

- (void)progressIndicatorNeedsUpdate {
    [self setNeedsUpdate:YES];
}

@end
