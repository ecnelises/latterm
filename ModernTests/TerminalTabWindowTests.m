#import <XCTest/XCTest.h>
#import "iTermRootTerminalView.h"
#import "iTermTabBarControlView.h"
#import "ITAddressBookMgr.h"
#import "ProfileModel.h"
#import "PseudoTerminal.h"
#import "PTYSession.h"
#import "PTYTab.h"
#import "SessionView.h"
#import "PSMTabBarCell.h"
#import "PSMTabStyle.h"
#import "iTerm2SharedARC-Swift.h"

/// Drive the source and destination callbacks without taking control of the system pointer.
@interface TabDragProbe : NSObject
@property(nonatomic) BOOL animatesToStartingPositionsOnCancelOrFail;
@property(nonatomic, strong) NSPasteboard *draggingPasteboard;
@property(nonatomic, weak) id draggingSource;
@property(nonatomic) NSPoint draggingLocation;
@end
@implementation TabDragProbe
@end

@interface TrackingTabBar : TerminalTabBarView
@property(nonatomic, strong) TabDragProbe *probe;
@end
@implementation TrackingTabBar
- (NSDraggingSession *)beginDraggingSessionWithItems:(NSArray<NSDraggingItem *> *)items
                                              event:(NSEvent *)event
                                             source:(id<NSDraggingSource>)source {
    self.probe = [[TabDragProbe alloc] init];
    self.probe.draggingSource = source;
    self.probe.draggingPasteboard = [NSPasteboard pasteboardWithUniqueName];
    [self.probe.draggingPasteboard writeObjects:@[items.firstObject.item]];
    return (NSDraggingSession *)(id)self.probe;
}
@end

@interface DetachingPaneDelegate : NSObject<PSMTabBarControlDelegate>
@property(nonatomic, strong) NSTabViewItem *replacement;
@end
@implementation DetachingPaneDelegate
- (void)tabView:(NSTabView *)tabs updateStateForTabViewItem:(NSTabViewItem *)item {}
- (BOOL)tabViewShouldAllowDragOnAddTabButton:(NSTabView *)tabs { return NO; }
- (BOOL)tabView:(NSTabView *)tabs shouldAcceptDragFromSender:(id<NSDraggingInfo>)sender { return YES; }
- (NSDragOperation)tabView:(NSTabView *)tabs draggingEnteredTabBarForSender:(id<NSDraggingInfo>)sender {
    return NSDragOperationMove;
}
- (id)tabView:(TerminalTabBarView *)bar valueOfOption:(PSMTabBarControlOptionKey)option { return nil; }
- (NSTabViewItem *)tabView:(NSTabView *)tabs unknownObjectWasDropped:(id<NSDraggingInfo>)sender {
    [tabs removeTabViewItem:tabs.tabViewItems.firstObject];
    self.replacement = [[NSTabViewItem alloc] initWithIdentifier:nil];
    return self.replacement;
}
@end

@interface TerminalTabWindowTests : XCTestCase
@end
@implementation TerminalTabWindowTests
- (void)testTitlebarHostsTheSameContainerAndReturnsItToTheRoot {
    NSRect rect = NSMakeRect(0, 0, 640, 400);
    iTermRootTerminalView *root = [[iTermRootTerminalView alloc] initWithFrame:rect
                                                                        color:NSColor.windowBackgroundColor
                                                               tabBarDelegate:nil
                                                                     delegate:nil];
    NSWindow *window = [[NSWindow alloc] initWithContentRect:rect styleMask:NSWindowStyleMaskTitled
                                                     backing:NSBackingStoreBuffered defer:NO];
    window.contentView = root;
    iTermTabBarControlView *container = root.tabBarControl;
    XCTAssertTrue([container isKindOfClass:TerminalTabContainerView.class]);
    NSTitlebarAccessoryViewController *accessory = [[NSTitlebarAccessoryViewController alloc] init];
    accessory.view = [root borrowTabBarControl];
    [window addTitlebarAccessoryViewController:accessory];
    XCTAssertEqual(accessory.view, container);
    XCTAssertEqual(container.window, window);
    [window removeTitlebarAccessoryViewControllerAtIndex:0];
    [root returnTabBarControlView:container];
    XCTAssertTrue([container isDescendantOf:root]);
    XCTAssertEqual(container.tabView.delegate, container);
}

- (void)testPaneDropKeepsItsPositionWhenTheSourceTabDisappears {
    NSRect frame = NSMakeRect(0, 0, 600, 32);
    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame styleMask:NSWindowStyleMaskTitled
                                                     backing:NSBackingStoreBuffered defer:NO];
    TerminalTabBarView *bar = [[TerminalTabBarView alloc] initWithFrame:frame];
    window.contentView = bar;
    bar.tabView = [[NSTabView alloc] initWithFrame:frame];
    bar.tabView.delegate = bar;
    DetachingPaneDelegate *delegate = [[DetachingPaneDelegate alloc] init];
    bar.delegate = delegate;
    for (NSUInteger i = 0; i < 3; i++) {
        [bar.tabView addTabViewItem:[[NSTabViewItem alloc] initWithIdentifier:nil]];
    }
    [bar update:NO];
    NSTabViewItem *second = bar.tabView.tabViewItems[1];
    NSTabViewItem *third = bar.tabView.tabViewItems[2];
    NSRect last = [(PSMTabBarCell *)bar.cells[2] frame];
    TabDragProbe *probe = [[TabDragProbe alloc] init];
    probe.draggingSource = window;
    probe.draggingPasteboard = [NSPasteboard pasteboardWithUniqueName];
    [probe.draggingPasteboard setString:@"" forType:iTermMovePaneDragType];
    probe.draggingLocation = [bar convertPoint:NSMakePoint(NSMinX(last) + 1, NSMidY(last)) toView:nil];
    XCTAssertTrue([bar performDragOperation:(id<NSDraggingInfo>)probe]);
    XCTAssertEqualObjects(bar.tabView.tabViewItems, (@[second, delegate.replacement, third]));
    XCTAssertEqual(bar.tabView.selectedTabViewItem, delegate.replacement);
    [probe.draggingPasteboard releaseGlobally];
}

- (void)testDroppingPinnedSinglePaneAtFarEndKeepsItsTabInPinnedSection {
    Profile *profile = [[ProfileModel sharedInstance] defaultBookmark];
    PseudoTerminal *term = [[PseudoTerminal alloc] initWithSmartLayout:NO
                                                            windowType:WINDOW_TYPE_NORMAL
                                                       savedWindowType:WINDOW_TYPE_NORMAL
                                                            percentage:(iTermPercentage){0, 0}
                                                                screen:-1
                                                               profile:profile];
    for (int i = 0; i < 3; i++) {
        PTYSession *pane = [[PTYSession alloc] initSynthetic:NO];
        pane.profile = profile;
        [term setupSession:pane withSize:NULL];
        [term insertSession:pane atIndex:i];
    }
    PTYTab *pinned = term.tabs.firstObject;
    pinned.pinned = YES;
    TerminalTabBarView *bar = term.tabBarControl;
    [bar update:NO];
    MovePaneController *controller = [MovePaneController sharedInstance];
    [controller movePane:pinned.activeSession];
    TabDragProbe *probe = [[TabDragProbe alloc] init];
    probe.draggingSource = pinned.activeSession.view;
    probe.draggingLocation = [bar convertPoint:NSMakePoint(NSMaxX(bar.bounds), NSMaxY(bar.bounds)) toView:nil];
    probe.draggingPasteboard = [NSPasteboard pasteboardWithUniqueName];
    [probe.draggingPasteboard setString:@"" forType:iTermMovePaneDragType];
    XCTAssertTrue([bar performDragOperation:(id<NSDraggingInfo>)probe]);
    XCTAssertEqualObjects(term.tabs.firstObject, pinned);
    XCTAssertTrue([bar isPinnedForTabViewItem:pinned.tabViewItem]);
    XCTAssertEqual(term.tabs.count, 3u);
    [probe.draggingPasteboard releaseGlobally];
    [controller exitMovePaneMode];
    [term.window close];
}

- (void)testDraggingUsesLocalItemIdentityAndRespectsPinnedBoundary {
    NSRect frame = NSMakeRect(0, 0, 600, 32);
    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame styleMask:NSWindowStyleMaskTitled
                                                     backing:NSBackingStoreBuffered defer:NO];
    TrackingTabBar *bar = [[TrackingTabBar alloc] initWithFrame:frame];
    window.contentView = bar;
    bar.tabView = [[NSTabView alloc] initWithFrame:frame];
    bar.tabView.delegate = bar;
    for (NSString *label in @[@"Pinned", @"First", @"Second"]) {
        NSTabViewItem *item = [[NSTabViewItem alloc] initWithIdentifier:nil];
        item.label = label;
        [bar.tabView addTabViewItem:item];
    }
    NSTabViewItem *pinned = bar.tabView.tabViewItems[0];
    NSTabViewItem *moved = bar.tabView.tabViewItems[2];
    [bar setIsPinned:YES forTabViewItem:pinned];
    [bar update:NO];
    NSEvent *event = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDragged location:NSMakePoint(300, 10)
                                   modifierFlags:0 timestamp:0 windowNumber:window.windowNumber
                                         context:nil eventNumber:0 clickCount:1 pressure:1];
    TerminalTabDrag *drag = TerminalTabDrag.shared;
    [drag beginFrom:bar cell:bar.cells[2] event:event];
    XCTAssertTrue(drag.isDragging);
    XCTAssertTrue(bar.probe.animatesToStartingPositionsOnCancelOrFail);
    XCTAssertEqual(drag.item, moved);
    bar.probe.draggingLocation = [bar convertPoint:NSMakePoint(1, 8) toView:nil];
    id<NSDraggingInfo> info = (id)bar.probe;
    bar.probe.draggingSource = window;
    XCTAssertEqual([bar draggingEntered:info], NSDragOperationNone);
    bar.probe.draggingSource = bar;
    XCTAssertEqual([bar draggingEntered:info], NSDragOperationMove);
    XCTAssertTrue([bar performDragOperation:info]);
    [drag endAt:NSZeroPoint operation:NSDragOperationMove];
    XCTAssertFalse(drag.isDragging);
    XCTAssertEqual(bar.tabView.tabViewItems[0], pinned);
    XCTAssertEqual(bar.tabView.tabViewItems[1], moved);
    XCTAssertEqual(bar.tabView.selectedTabViewItem, moved);
    [bar.probe.draggingPasteboard releaseGlobally];
}
@end
