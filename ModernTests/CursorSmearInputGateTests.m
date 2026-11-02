#import <XCTest/XCTest.h>
#import "PTYTextView.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermUserDefaults.h"

@interface PTYTextView (InputGateTesting)
- (BOOL)smearGateIsOpen;
@end

@interface CursorInputDelegate : NSObject
@property(nonatomic) NSTimeInterval elapsed;
@property(nonatomic) BOOL interactive;
@end
@implementation CursorInputDelegate
- (NSTimeInterval)textViewTimeSinceLastUserInput { return self.elapsed; }
- (BOOL)textViewInInteractiveApplication { return self.interactive; }
@end

@interface CursorSmearInputGateTests : XCTestCase
@end
@implementation CursorSmearInputGateTests
- (void)setUp {
    [super setUp];
    NSUserDefaults *defaults = [iTermUserDefaults userDefaults];
    id previous = [defaults objectForKey:@"CursorAnimationInputWindow"];
    [defaults setObject:@1 forKey:@"CursorAnimationInputWindow"];
    [iTermAdvancedSettingsModel loadAdvancedSettingsFromUserDefaults];
    [self addTeardownBlock:^{
        [defaults setObject:previous forKey:@"CursorAnimationInputWindow"];
        [iTermAdvancedSettingsModel loadAdvancedSettingsFromUserDefaults];
    }];
}
- (void)testBackgroundRedrawDoesNotSmearButRecentInputDoes {
    PTYTextView *view = [[PTYTextView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
    CursorInputDelegate *delegate = [[CursorInputDelegate alloc] init];
    view.delegate = (id)delegate;
    view.animateMovement = YES;
    view.animateMovementOnlyInInteractiveApps = NO;
    delegate.elapsed = INFINITY;
    XCTAssertFalse([view smearGateIsOpen]);
    delegate.elapsed = 0;
    XCTAssertTrue([view smearGateIsOpen]);
    delegate.elapsed = 2;
    XCTAssertFalse([view smearGateIsOpen]);
    view.delegate = nil;
}
- (void)testInteractiveRestrictionStillApplies {
    PTYTextView *view = [[PTYTextView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
    CursorInputDelegate *delegate = [[CursorInputDelegate alloc] init];
    view.delegate = (id)delegate;
    view.animateMovement = YES;
    view.animateMovementOnlyInInteractiveApps = YES;
    delegate.elapsed = 0;
    XCTAssertFalse([view smearGateIsOpen]);
    delegate.interactive = YES;
    XCTAssertTrue([view smearGateIsOpen]);
    view.delegate = nil;
}
@end
