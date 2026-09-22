#import <XCTest/XCTest.h>
#import "TmuxLayoutParser.h"

@interface TmuxLayoutParserTest : XCTestCase
@end

@implementation TmuxLayoutParserTest

#pragma mark - bad input must never crash (issue: tmux 3.8 all-floating windows)

// tmux 3.8 emits an empty window_layout/window_visible_layout for a window
// whose panes are all floating. An empty string previously underflowed
// NSMakeRange(5, length - 5) and threw an uncaught NSRangeException. Bad input
// from control mode must degrade to nil, never crash.
- (void)testEmptyLayoutReturnsNil {
    XCTAssertNil([[TmuxLayoutParser sharedInstance] parsedLayoutFromString:@""]);
}

- (void)testShortLayoutsReturnNil {
    // Anything at or below the 5-character header cannot contain a cell.
    XCTAssertNil([[TmuxLayoutParser sharedInstance] parsedLayoutFromString:@"c"]);
    XCTAssertNil([[TmuxLayoutParser sharedInstance] parsedLayoutFromString:@"c195"]);
    XCTAssertNil([[TmuxLayoutParser sharedInstance] parsedLayoutFromString:@"c195,"]);
}

// Every truncation of a real layout string must parse or return nil, never
// crash. This exercises the range/substring math at every boundary.
- (void)testEveryTruncationOfValidLayoutDoesNotCrash {
    NSString *valid = @"c195,80x24,0,0[80x12,0,0,0,80x11,0,13,1]";
    for (NSUInteger i = 0; i <= valid.length; i++) {
        NSString *prefix = [valid substringToIndex:i];
        XCTAssertNoThrow([[TmuxLayoutParser sharedInstance] parsedLayoutFromString:prefix], @"%@", prefix);
    }
}

// Malformed input must not throw. The existing parser may recover a partial tree.
- (void)testMalformedLayoutsDoNotCrash {
    NSArray<NSString *> *malformed = @[
        @"c195,80x24,0,0[80x12,0,0,0",          // unbalanced [
        @"c195,80x24,0,0{80x12,0,0,0",          // unbalanced {
        @"c195,80x24,0,0[80x12,0,0,0]]]]",      // extra closers
        @"c195,80x24,0,0{{{{",                   // only openers
        @"c195,]]]]]]]]",                        // only closers
        @"c195,garbage",                         // non-layout body
        @"c195,80x24,0,0[",                      // opener at end
    ];
    for (NSString *layout in malformed) {
        XCTAssertNoThrow([[TmuxLayoutParser sharedInstance] parsedLayoutFromString:layout], @"%@", layout);
    }
}

// The all-floating case aside, a normal old-format string with the floating
// pane already stripped by tmux must still parse correctly.
- (void)testStrippedFloatLayoutStillParses {
    NSMutableDictionary *tree =
        [[TmuxLayoutParser sharedInstance] parsedLayoutFromString:@"c195,80x24,0,0[80x12,0,0,0,80x11,0,13,1]"];
    XCTAssertNotNil(tree);
    NSArray *panes = [[TmuxLayoutParser sharedInstance] windowPanesInParseTree:tree];
    XCTAssertEqualObjects([NSSet setWithArray:panes], ([NSSet setWithArray:@[@0, @1]]));
}

@end
