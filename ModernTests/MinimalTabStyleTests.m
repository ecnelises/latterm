#import <XCTest/XCTest.h>
#import "PSMMinimalTabStyle.h"

@interface PSMMinimalTabStyle (DrawingTests)
- (void)drawOutlineAroundVerticalTabBar:(PSMTabBarControl *)bar;
- (NSColor *)backgroundColorSelected:(BOOL)selected highlightAmount:(CGFloat)highlightAmount;
@end

@interface MinimalStyleTestBar : PSMTabBarControl
@property(nonatomic, copy) NSArray<PSMTabBarCell *> *testCells;
@end
@implementation MinimalStyleTestBar
- (NSArray *)cells { return self.testCells ?: @[]; }
@end

@interface MinimalStyleTestOptions : NSObject<PSMTabBarControlDelegate, PSMMinimalTabStyleDelegate>
@property(nonatomic) BOOL mergeFirstTab;
@property(nonatomic) CGFloat outlineStrength;
@property(nonatomic) CGFloat dimming;
@end
@implementation MinimalStyleTestOptions
- (void)tabView:(NSTabView *)tabView updateStateForTabViewItem:(NSTabViewItem *)item {}
- (BOOL)tabViewShouldAllowDragOnAddTabButton:(NSTabView *)tabView { return NO; }
- (NSColor *)minimalTabStyleBackgroundColor {
    return [NSColor colorWithSRGBRed:0.2 green:0.2 blue:0.2 alpha:1];
}
- (id)tabView:(PSMTabBarControl *)bar valueOfOption:(PSMTabBarControlOptionKey)option {
    if ([option isEqual:PSMTabBarControlOptionMinimalStyleTreatLeftInsetAsPartOfFirstTab]) {
        return @(self.mergeFirstTab);
    }
    if ([option isEqual:PSMTabBarControlOptionColoredMinimalOutlineStrength]) {
        return @(self.outlineStrength);
    }
    if ([option isEqual:PSMTabBarControlOptionDimmingAmount]) { return @(self.dimming); }
    if ([option isEqual:PSMTabBarControlOptionMinimalBackgroundAlphaValue]) { return @1; }
    if ([option isEqual:PSMTabBarControlOptionMinimalStyleBackgroundColorDifference]) { return @0.1; }
    if ([option isEqual:PSMTabBarControlOptionMinimalNonSelectedColoredTabAlpha]) { return @0.5; }
    return nil;
}
@end

@interface MinimalTabStyleTests : XCTestCase
@end
@implementation MinimalTabStyleTests

- (NSBitmapImageRep *)renderAtScale:(NSInteger)scale draw:(void (^)(void))draw {
    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                    pixelsWide:100 * scale
                                                                    pixelsHigh:100 * scale
                                                                 bitsPerSample:8
                                                               samplesPerPixel:4
                                                                      hasAlpha:YES
                                                                      isPlanar:NO
                                                                colorSpaceName:NSDeviceRGBColorSpace
                                                                   bytesPerRow:0
                                                                  bitsPerPixel:0];
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
    NSAffineTransform *transform = [NSAffineTransform transform];
    [transform scaleBy:scale];
    [transform concat];
    [[NSColor blackColor] set];
    NSRectFill(NSMakeRect(0, 0, 100, 100));
    draw();
    [NSGraphicsContext restoreGraphicsState];
    return bitmap;
}

- (MinimalStyleTestBar *)barAtPosition:(PSMTabPosition)position selectedIndex:(NSInteger)selectedIndex {
    // A nonzero window origin must not affect drawing in local coordinates.
    MinimalStyleTestBar *bar = [[MinimalStyleTestBar alloc] initWithFrame:NSMakeRect(317, 43, 100, 100)];
    bar.tabLocation = position;
    bar.orientation = PSMTabBarVerticalOrientation;
    bar.height = 20;
    NSMutableArray *cells = [NSMutableArray array];
    for (NSInteger index = 0; index < 3; index++) {
        PSMTabBarCell *cell = [[PSMTabBarCell alloc] initWithControlView:bar];
        cell.frame = NSMakeRect(0, 10 + index * 20, 100, 20);
        cell.state = index == selectedIndex ? NSControlStateValueOn : NSControlStateValueOff;
        [cells addObject:cell];
    }
    bar.testCells = cells;
    return bar;
}

- (void)testVerticalBackgroundHasNoContrastingEdgeRails {
    MinimalStyleTestOptions *options = [[MinimalStyleTestOptions alloc] init];
    for (NSNumber *position in @[@(PSMTab_LeftTab), @(PSMTab_RightTab)]) {
        MinimalStyleTestBar *bar = [self barAtPosition:position.intValue selectedIndex:1];
        bar.delegate = options;
        PSMMinimalTabStyle *style = [[PSMMinimalTabStyle alloc] init];
        style.tabBar = bar;
        style.delegate = options;
        style.orientation = PSMTabBarVerticalOrientation;
        for (NSNumber *dim in @[@0, @0.4]) {
            options.dimming = dim.doubleValue;
            for (NSNumber *selected in @[@NO, @YES]) {
                for (id color in @[[NSNull null], [NSColor blueColor]]) {
                    for (NSInteger scale = 1; scale <= 2; scale++) {
                        NSBitmapImageRep *bitmap = [self renderAtScale:scale draw:^{
                            [style drawCellBackgroundSelected:selected.boolValue
                                                       inRect:NSMakeRect(0, 0, 100, 100)
                                                 withTabColor:color == [NSNull null] ? nil : color
                                              highlightAmount:0
                                                   horizontal:NO];
                        }];
                        NSColor *middle = [bitmap colorAtX:50 * scale y:50 * scale];
                        XCTAssertEqualObjects([bitmap colorAtX:0 y:50 * scale], middle);
                        XCTAssertEqualObjects([bitmap colorAtX:100 * scale - 1 y:50 * scale], middle);
                    }
                }
            }
        }
    }
}

- (void)testVerticalOutlineMirrorsAtContentEdgeAndLeavesSelectedTabOpen {
    MinimalStyleTestOptions *options = [[MinimalStyleTestOptions alloc] init];
    for (NSNumber *strength in @[@0.1, @0.6]) {
        options.outlineStrength = strength.doubleValue;
        for (NSInteger scale = 1; scale <= 2; scale++) {
            for (NSNumber *position in @[@(PSMTab_LeftTab), @(PSMTab_RightTab)]) {
                MinimalStyleTestBar *bar = [self barAtPosition:position.intValue selectedIndex:1];
                bar.delegate = options;
                PSMMinimalTabStyle *style = [[PSMMinimalTabStyle alloc] init];
                style.tabBar = bar;
                style.delegate = options;
                NSBitmapImageRep *bitmap = [self renderAtScale:scale draw:^{
                    [style drawOutlineAroundVerticalTabBar:bar];
                }];
                const NSInteger inner = position.intValue == PSMTab_LeftTab ? 100 * scale - 1 : 0;
                const NSInteger outer = position.intValue == PSMTab_LeftTab ? 0 : 100 * scale - 1;
                // Bitmap rows run opposite the unflipped drawing coordinates.
                const NSInteger above = 80 * scale;
                const NSInteger selected = 60 * scale;
                const NSInteger below = 20 * scale;
                XCTAssertGreaterThan([bitmap colorAtX:inner y:above].redComponent, 0);
                XCTAssertGreaterThan([bitmap colorAtX:inner y:below].redComponent, 0);
                XCTAssertEqualWithAccuracy([bitmap colorAtX:inner y:selected].redComponent, 0, 0.001);
                XCTAssertEqualWithAccuracy([bitmap colorAtX:outer y:above].redComponent, 0, 0.001);
                // The outline consumes exactly one point, even with stronger dimming contrast.
                const NSInteger next = position.intValue == PSMTab_LeftTab ? 99 * scale - 1 : scale;
                XCTAssertEqualWithAccuracy([bitmap colorAtX:next y:above].redComponent, 0, 0.001);
            }
        }
    }
}

- (void)testFirstTabInsetAndOverflowOutline {
    MinimalStyleTestOptions *options = [[MinimalStyleTestOptions alloc] init];
    options.outlineStrength = 1;
    options.mergeFirstTab = YES;
    MinimalStyleTestBar *bar = [self barAtPosition:PSMTab_RightTab selectedIndex:0];
    bar.delegate = options;
    PSMMinimalTabStyle *style = [[PSMMinimalTabStyle alloc] init];
    style.tabBar = bar;
    style.delegate = options;
    NSBitmapImageRep *merged = [self renderAtScale:1 draw:^{ [style drawOutlineAroundVerticalTabBar:bar]; }];
    XCTAssertEqualWithAccuracy([merged colorAtX:0 y:95].redComponent, 0, 0.001);
    XCTAssertGreaterThan([merged colorAtX:0 y:20].redComponent, 0);

    options.mergeFirstTab = NO;
    bar.testCells.firstObject.isInOverflowMenu = YES;
    NSBitmapImageRep *overflow = [self renderAtScale:1 draw:^{ [style drawOutlineAroundVerticalTabBar:bar]; }];
    XCTAssertGreaterThan([overflow colorAtX:0 y:50].redComponent, 0);
    XCTAssertEqualWithAccuracy([overflow colorAtX:0 y:10].redComponent, 0, 0.001);
}
@end
