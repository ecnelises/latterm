#import <XCTest/XCTest.h>
#import <ColorPicker/ColorPicker.h>

@interface NSObject (ColorPickerResourceTests)
- (NSImage *)cpk_imageNamed:(NSString *)name;
+ (instancetype)sharedInstance;
- (NSString *)nameForColor:(NSColor *)color;
@end

// App-owned subclasses must resolve resources in the package, not the app bundle.
@interface TestPackagedColorWell : CPKColorWell
@end
@implementation TestPackagedColorWell
@end

@interface ColorPickerPackageTests : XCTestCase
@end

@implementation ColorPickerPackageTests

- (void)testPackagedResources {
    NSBundle *app = NSBundle.mainBundle;
    NSURL *url = [app URLForResource:@"ColorPicker_ColorPicker" withExtension:@"bundle"];
    XCTAssertNotNil(url);
    NSBundle *resources = url ? [NSBundle bundleWithURL:url] : nil;
    XCTAssertNotNil([resources URLForResource:@"colors" withExtension:@"txt"]);

    TestPackagedColorWell *well = [[TestPackagedColorWell alloc] initWithFrame:NSMakeRect(0, 0, 44, 24)
                                                                colorSpace:NSColorSpace.sRGBColorSpace];
    for (NSString *name in @[@"ActiveEscapeHatch", @"ActiveEyedropper", @"Add", @"EscapeHatch", @"Eyedropper",
                            @"HSB", @"NoColor", @"RGB", @"Remove", @"SelectedColorIndicator",
                            @"SelectionIndicator", @"SwatchCheckerboard"]) {
        XCTAssertNotNil([resources URLForResource:name withExtension:@"png"], @"%@", name);
        XCTAssertNotNil([resources URLForResource:[name stringByAppendingString:@"@2x"] withExtension:@"png"], @"%@", name);
        NSImage *image = [well cpk_imageNamed:name];
        XCTAssertNotNil(image, @"%@", name);
        XCTAssertEqual(image.representations.count, 2, @"%@", name);
        XCTAssertGreaterThan(image.size.width, 1, @"%@", name);
        XCTAssertGreaterThan(image.size.height, 1, @"%@", name);
    }
}

- (void)testPickerLoadsAndPreservesColorAndAlpha {
    NSColor *color = [NSColor colorWithSRGBRed:0.2 green:0.4 blue:0.6 alpha:0.5];
    __block NSColor *lastSelection = nil;
    CPKMainViewController *picker = [[CPKMainViewController alloc]
        initWithBlock:^(NSColor *selected) { lastSelection = selected; }
        useSystemColorPicker:^{}
        color:color
        options:CPKMainViewControllerOptionsAlpha | CPKMainViewControllerOptionsNoColor
        colorSpace:NSColorSpace.sRGBColorSpace];
    XCTAssertNotNil(picker.view);
    XCTAssertGreaterThan(picker.view.subviews.count, 0);
    XCTAssertEqualWithAccuracy(picker.selectedColor.alphaComponent, 0.5, 0.001);
    NSColor *replacement = [NSColor colorWithSRGBRed:0.7 green:0.3 blue:0.1 alpha:0.25];
    [picker selectColor:replacement];
    XCTAssertEqualWithAccuracy(picker.selectedColor.redComponent, 0.7, 0.001);
    XCTAssertEqualWithAccuracy(picker.selectedColor.alphaComponent, 0.25, 0.001);
    XCTAssertEqualObjects(lastSelection, picker.selectedColor);
}

- (void)testColorNameDatabaseLoadsFromPackage {
    Class namerClass = NSClassFromString(@"CPKColorNamer");
    XCTAssertNotNil(namerClass);
    id namer = [namerClass sharedInstance];
    XCTAssertNotNil(namer);
    XCTAssertEqualObjects([namer nameForColor:[NSColor colorWithSRGBRed:1 green:0 blue:0 alpha:1]], @"Red");
    XCTAssertEqualObjects([namer nameForColor:[NSColor colorWithSRGBRed:1 green:0 blue:0 alpha:0.5]], @"Red (50%)");
}

@end
