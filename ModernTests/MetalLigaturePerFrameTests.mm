//
//  MetalLigaturePerFrameTests.mm
//  ModernTests
//
//  Tests C++ GlyphKey hashing/equality and iTermMetalPerFrameState row glyph generation
//  with GPU ligatures, per-language customBaselineOffset, and box-cursor splitting.
//

#import <Cocoa/Cocoa.h>
#import <CoreText/CoreText.h>
#import <Metal/Metal.h>
#import <XCTest/XCTest.h>
#import <objc/runtime.h>

#include <functional>
#include <vector>

#import "GlyphKey.h"
#import "NSFont+iTerm.h"
#import "PTYFontInfo.h"
#import "PTYSession.h"
#import "PTYTextView.h"
#import "ProfileModel.h"
#import "iTermAttributedStringBuilder.h"
#import "iTermData.h"
#import "iTermMetalGlyphKey.h"
#import "iTermPreferences.h"
#import "iTermProfilePreferences.h"
#import "iTermTextDrawingHelper.h"
#import "iTermTextRendererCommon.h"

// Forward declarations for classes whose public headers pull in iTerm2SharedARC-Swift.h.
@interface iTermHeadlessWindowController : NSObject <iTermWindowController>
- (instancetype)initWithFrame:(NSRect)frame;
@end

@interface PTYSession (MetalGlueTesting)
- (CGContextRef)metalGlueContext;
- (CGContextRef)metalGlueContextDoubleWidth;
@end

@interface iTermMetalPerFrameState : NSObject
- (instancetype)initWithTextView:(PTYTextView *)textView
                          screen:(VT100Screen *)screen
                            glue:(id)glue
                         context:(CGContextRef)context
              doubleWidthContext:(CGContextRef)doubleWidthContext
         attributedStringBuilder:(iTermAttributedStringBuilder *)attributedStringBuilder
                  rowOutputCache:(id)rowOutputCache;

- (void)metalGetGlyphKeysData:(iTermGlyphKeyData *)glyphKeysData
                glyphKeyCount:(out NSUInteger *)glyphKeyCountPtr
                   attributes:(iTermMetalGlyphAttributes *)attributes
                    imageRuns:(NSMutableArray *)imageRuns
               kittyImageRuns:(NSMutableArray *)kittyImageRuns
                   background:(iTermMetalBackgroundColorRLE *)backgrounds
                     rleCount:(int *)rleCount
                    markStyle:(out int *)markStylePtr
                   hoverState:(out BOOL *)hoverStatePtr
                lineStyleMark:(out BOOL *)lineStyleMarkPtr
      lineStyleMarkRightInset:(out int *)lineStyleMarkRightInset
                          row:(int)row
                        width:(int)width
                     bidiInfo:(id)bidiInfo
               drawableGlyphs:(int *)drawableGlyphsPtr
                         date:(out NSDate **)date
               belongsToBlock:(out BOOL *)belongsToBlock
  hasUnderlineOrStrikethrough:(out BOOL *)hasUnderlineOrStrikethroughPtr;
@end

@interface iTermMetalGlue : NSObject
@property (nonatomic, strong) PTYTextView *textView;
@property (nonatomic, strong) VT100Screen *screen;
@property (nonatomic, weak) id delegate;
- (iTermAttributedStringBuilder *)newAttributedStringBuilder;
@end

@interface LigatureTestKeyWindow : NSWindow
@end

@implementation LigatureTestKeyWindow
- (BOOL)isKeyWindow {
    return YES;
}
@end

static struct objc_method_description LigatureFindProtocolMethod(Protocol *proto, SEL sel) {
    struct objc_method_description empty = { NULL, NULL };
    if (!proto) {
        return empty;
    }
    struct objc_method_description d = protocol_getMethodDescription(proto, sel, YES, YES);
    if (d.name) {
        return d;
    }
    d = protocol_getMethodDescription(proto, sel, NO, YES);
    if (d.name) {
        return d;
    }
    unsigned int count = 0;
    Protocol * __unsafe_unretained *list = protocol_copyProtocolList(proto, &count);
    for (unsigned int i = 0; i < count; i++) {
        d = LigatureFindProtocolMethod(list[i], sel);
        if (d.name) {
            break;
        }
    }
    free(list);
    return d;
}

@interface LigatureTestActiveTabDelegate : NSObject
@property (nonatomic, strong) id parentWindow;
@end

@implementation LigatureTestActiveTabDelegate
- (BOOL)sessionIsActiveInTab:(PTYSession *)session {
    return YES;
}
- (id)realParentWindow {
    return nil;
}
- (BOOL)respondsToSelector:(SEL)aSelector {
    if ([super respondsToSelector:aSelector]) {
        return YES;
    }
    return LigatureFindProtocolMethod(@protocol(PTYSessionDelegate), aSelector).name != NULL;
}
- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector {
    NSMethodSignature *sig = [super methodSignatureForSelector:aSelector];
    if (sig) {
        return sig;
    }
    struct objc_method_description d = LigatureFindProtocolMethod(@protocol(PTYSessionDelegate), aSelector);
    return d.types ? [NSMethodSignature signatureWithObjCTypes:d.types] : nil;
}
- (void)forwardInvocation:(NSInvocation *)invocation {
    NSUInteger len = invocation.methodSignature.methodReturnLength;
    if (len > 0) {
        std::vector<char> zero(len, 0);
        [invocation setReturnValue:zero.data()];
    }
}
@end

@interface MetalLigaturePerFrameTests : XCTestCase
@end

@implementation MetalLigaturePerFrameTests

- (void)testDecomposedGlyphKeyIncludesAntiAliasAndPositionInEqualityAndHash {
    iTermMetalGlyphKey rawAliased = {};
    rawAliased.type = iTermMetalGlyphTypeDecomposed;
    rawAliased.payload.decomposed.fontID = 7;
    rawAliased.payload.decomposed.glyphNumber = 42;
    rawAliased.payload.decomposed.fakeBold = 0;
    rawAliased.payload.decomposed.fakeItalic = 0;
    rawAliased.payload.decomposed.antiAlias = 0;
    rawAliased.payload.decomposed.position = NSMakePoint(0, 1.5);
    rawAliased.typeface = iTermMetalGlyphKeyTypefaceRegular;
    rawAliased.thinStrokes = NO;
    rawAliased.lineAttribute = iTermLineAttributeSingleWidth;

    iTermMetalGlyphKey rawAntialiased = rawAliased;
    rawAntialiased.payload.decomposed.antiAlias = 1;

    iTermMetalGlyphKey rawShiftedBaseline = rawAliased;
    rawShiftedBaseline.payload.decomposed.position = NSMakePoint(0, 0.0);

    iTerm2::GlyphKey keyAliased(&rawAliased);
    iTerm2::GlyphKey keyAliasedCopy(&rawAliased);
    iTerm2::GlyphKey keyAntialiased(&rawAntialiased);
    iTerm2::GlyphKey keyShifted(&rawShiftedBaseline);

    XCTAssertTrue(keyAliased == keyAliasedCopy);
    XCTAssertEqual(keyAliased.get_hash(), keyAliasedCopy.get_hash());

    XCTAssertFalse(keyAliased == keyAntialiased,
                   @"Decomposed GlyphKey must distinguish aliased vs antialiased rasterization");
    XCTAssertNotEqual(keyAliased.get_hash(), keyAntialiased.get_hash());

    XCTAssertFalse(keyAliased == keyShifted,
                   @"Decomposed GlyphKey must distinguish customBaselineOffset position shifts");
    XCTAssertNotEqual(keyAliased.get_hash(), keyShifted.get_hash());
}

- (void)testPerFrameStateLigaturesBaselineOffsetAndBoxCursorSplitting {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    NSScreen *screen = [NSScreen mainScreen];
    Profile *baseProfile = [[ProfileModel sharedInstance] defaultProfile];
    if (!device || !screen || !baseProfile) {
        return;
    }

    NSString *guid = [NSString stringWithFormat:@"test-perframe-ligatures-%@", [NSUUID UUID].UUIDString];
    NSMutableDictionary *mutableProfile = [baseProfile mutableCopy];
    mutableProfile[KEY_GUID] = guid;
    mutableProfile[KEY_NAME] = @"PerFrame Ligatures Test";
    NSString *normalFontSpec = [NSFont fontWithName:@"JetBrainsMono-Regular" size:13]
        ? @"JetBrainsMono-Regular 13"
        : @"Menlo-Regular 13";
    mutableProfile[KEY_NORMAL_FONT] = normalFontSpec;
    mutableProfile[KEY_NON_ASCII_FONT] = @"PingFangSC-Regular 13";
    mutableProfile[KEY_USE_NONASCII_FONT] = @YES;
    mutableProfile[KEY_ASCII_LIGATURES] = @YES;
    mutableProfile[KEY_NON_ASCII_LIGATURES] = @YES;
    mutableProfile[KEY_CURSOR_TYPE] = @(CURSOR_BOX);
    // FontTable.Config v3 JSON with Simplified Chinese rule carrying +1.5pt customBaselineOffset
    mutableProfile[KEY_FONT_CONFIG] = @"{\"version\":3,\"entries\":[],\"languageRules\":[{\"script\":\"zh-Hans\",\"fontName\":\"PingFangSC-Regular\",\"scalePercent\":100,\"baselineOffset\":1.5,\"enabled\":true}]}";

    const BOOL savedUseMetal = [iTermPreferences boolForKey:kPreferenceKeyUseMetal];
    const BOOL savedBidi = [iTermPreferences boolForKey:kPreferenceKeyBidi];
    [iTermPreferences setBool:YES forKey:kPreferenceKeyUseMetal];
    [iTermPreferences setBool:NO forKey:kPreferenceKeyBidi];

    @try {
        const NSSize frameSize = NSMakeSize(640, 320);
        PTYSession *session = [[PTYSession alloc] initSynthetic:YES];
        session.profile = mutableProfile;
        iTermHeadlessWindowController *parent = [[iTermHeadlessWindowController alloc] initWithFrame:NSMakeRect(0, 0, frameSize.width, frameSize.height)];
        LigatureTestActiveTabDelegate *tabDelegate = [[LigatureTestActiveTabDelegate alloc] init];
        tabDelegate.parentWindow = parent;
        session.delegate = (id<PTYSessionDelegate>)tabDelegate;
        [session setScreenSize:frameSize parent:parent];
        [session setPreferencesFromAddressBookEntry:mutableProfile];
        [session loadInitialColorTableAndResetCursorGuide];

        LigatureTestKeyWindow *window = [[LigatureTestKeyWindow alloc] initWithContentRect:NSMakeRect(screen.frame.origin.x, screen.frame.origin.y, frameSize.width, frameSize.height)
                                                                                 styleMask:NSWindowStyleMaskTitled
                                                                                   backing:NSBackingStoreBuffered
                                                                                     defer:NO
                                                                                    screen:screen];
        window.contentView = (NSView *)session.view;
        [window orderFront:nil];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];

        // Inject ASCII + "!==" ligature + CJK character at column 8, moving cursor to row 1 so row 0 has no cursor first.
        NSData *payload = [@"abc !== 中\r\nnext" dataUsingEncoding:NSUTF8StringEncoding];
        [session injectData:payload];
        [session.screen performBlockWithJoinedThreads:^(VT100Terminal *t, VT100ScreenMutableState *ms, id<VT100ScreenDelegate> d) {}];

        XCTAssertTrue([session willEnableMetal]);

        iTermMetalGlue *glue = [[iTermMetalGlue alloc] init];
        glue.textView = session.textview;
        glue.screen = session.screen;
        glue.delegate = session;

        const int width = session.screen.width;
        XCTAssertTrue(session.textview.drawingHelperIsValid);
        session.textview.drawingHelper.isCursorVisible = YES;
        session.textview.drawingHelper.shouldDrawFilledInCursor = YES;

        iTermMetalPerFrameState *stateNoCursor = [[iTermMetalPerFrameState alloc] initWithTextView:session.textview
                                                                                            screen:session.screen
                                                                                              glue:glue
                                                                                           context:session.metalGlueContext
                                                                                doubleWidthContext:session.metalGlueContextDoubleWidth
                                                                           attributedStringBuilder:[glue newAttributedStringBuilder]
                                                                                    rowOutputCache:nil];
        XCTAssertNotNil(stateNoCursor);

        iTermGlyphKeyData *keysNoCursor = [iTermGlyphKeyData dataOfLength:(NSUInteger)(width * 2) * sizeof(iTermMetalGlyphKey)];
        NSUInteger keyCountNoCursor = 0;
        std::vector<iTermMetalGlyphAttributes> attrsNoCursor(width);
        std::vector<iTermMetalBackgroundColorRLE> rlesNoCursor(width);
        int rleCountNoCursor = 0;
        int markStyle = 0;
        BOOL hoverState = NO;
        BOOL lineStyleMark = NO;
        int rightInset = 0;
        int drawableGlyphsNoCursor = 0;
        NSDate *rowDate = nil;
        BOOL belongsToBlock = NO;
        BOOL hasUnderline = NO;

        [stateNoCursor metalGetGlyphKeysData:keysNoCursor
                               glyphKeyCount:&keyCountNoCursor
                                  attributes:attrsNoCursor.data()
                                   imageRuns:[NSMutableArray array]
                              kittyImageRuns:[NSMutableArray array]
                                  background:rlesNoCursor.data()
                                    rleCount:&rleCountNoCursor
                                   markStyle:&markStyle
                                  hoverState:&hoverState
                               lineStyleMark:&lineStyleMark
                     lineStyleMarkRightInset:&rightInset
                                         row:0
                                       width:width
                                    bidiInfo:nil
                              drawableGlyphs:&drawableGlyphsNoCursor
                                        date:&rowDate
                              belongsToBlock:&belongsToBlock
                 hasUnderlineOrStrikethrough:&hasUnderline];

        XCTAssertGreaterThan(keyCountNoCursor, 0u);
        XCTAssertGreaterThan(drawableGlyphsNoCursor, 0,
                             @"drawableGlyphs must be tracked when emitting decomposed/ligature strings");
        XCTAssertLessThanOrEqual((NSUInteger)drawableGlyphsNoCursor, keyCountNoCursor,
                                 @"drawableGlyphs must never exceed glyphKeyCount");

        const iTermMetalGlyphKey *bufNoCursor = keysNoCursor.basePointer;
        BOOL foundCJKWithCustomBaseline = NO;
        for (NSUInteger i = 0; i < keyCountNoCursor; i++) {
            if (bufNoCursor[i].logicalIndex == 8 && bufNoCursor[i].type == iTermMetalGlyphTypeDecomposed) {
                foundCJKWithCustomBaseline = YES;
                XCTAssertEqualWithAccuracy(bufNoCursor[i].payload.decomposed.position.y, 1.5, 0.01,
                                           @"CJK decomposed glyph must include LanguageFontRule +1.5pt customBaselineOffset");
            }
        }
        XCTAssertTrue(foundCJKWithCustomBaseline, @"Expected decomposed CJK glyph key at column 8");

        // Move opaque BOX cursor onto row 0, column 5 (1-based: CSI 1;6H -> middle '=' of "!==" at cols 4,5,6).
        [session injectData:[@"\x1b[1;6H" dataUsingEncoding:NSUTF8StringEncoding]];
        [session.screen performBlockWithJoinedThreads:^(VT100Terminal *t, VT100ScreenMutableState *ms, id<VT100ScreenDelegate> d) {}];

        XCTAssertTrue(session.textview.drawingHelperIsValid);
        session.textview.drawingHelper.isCursorVisible = YES;
        session.textview.drawingHelper.shouldDrawFilledInCursor = YES;

        iTermMetalPerFrameState *stateWithCursor = [[iTermMetalPerFrameState alloc] initWithTextView:session.textview
                                                                                              screen:session.screen
                                                                                                glue:glue
                                                                                             context:session.metalGlueContext
                                                                                  doubleWidthContext:session.metalGlueContextDoubleWidth
                                                                             attributedStringBuilder:[glue newAttributedStringBuilder]
                                                                                      rowOutputCache:nil];
        XCTAssertNotNil(stateWithCursor);

        iTermGlyphKeyData *keysWithCursor = [iTermGlyphKeyData dataOfLength:(NSUInteger)(width * 2) * sizeof(iTermMetalGlyphKey)];
        NSUInteger keyCountWithCursor = 0;
        std::vector<iTermMetalGlyphAttributes> attrsWithCursor(width);
        std::vector<iTermMetalBackgroundColorRLE> rlesWithCursor(width);
        int rleCountWithCursor = 0;
        int drawableGlyphsWithCursor = 0;

        [stateWithCursor metalGetGlyphKeysData:keysWithCursor
                                 glyphKeyCount:&keyCountWithCursor
                                    attributes:attrsWithCursor.data()
                                     imageRuns:[NSMutableArray array]
                                kittyImageRuns:[NSMutableArray array]
                                    background:rlesWithCursor.data()
                                      rleCount:&rleCountWithCursor
                                     markStyle:&markStyle
                                    hoverState:&hoverState
                                 lineStyleMark:&lineStyleMark
                       lineStyleMarkRightInset:&rightInset
                                           row:0
                                         width:width
                                      bidiInfo:nil
                                drawableGlyphs:&drawableGlyphsWithCursor
                                          date:&rowDate
                                belongsToBlock:&belongsToBlock
                   hasUnderlineOrStrikethrough:&hasUnderline];

        const iTermMetalGlyphKey *bufWithCursor = keysWithCursor.basePointer;
        int col5Count = 0;
        for (NSUInteger i = 0; i < keyCountWithCursor; i++) {
            if (bufWithCursor[i].logicalIndex == 5) {
                col5Count++;
                if (bufWithCursor[i].type == iTermMetalGlyphTypeDecomposed) {
                    NSFont *font = [NSFont it_fontWithMetalID:bufWithCursor[i].payload.decomposed.fontID];
                    XCTAssertNotNil(font);
                    unichar eqChar = '=';
                    CGGlyph eqGlyph = 0;
                    XCTAssertTrue(CTFontGetGlyphsForCharacters((__bridge CTFontRef)font, &eqChar, &eqGlyph, 1));
                    XCTAssertEqual(bufWithCursor[i].payload.decomposed.glyphNumber, eqGlyph,
                                   @"Opaque box cursor on middle cell of '!==' must split the ligature to show '='");
                } else {
                    XCTAssertEqual(bufWithCursor[i].payload.regular.code, '=');
                }
            }
        }
        XCTAssertEqual(col5Count, 1, @"Column 5 under box cursor must emit its own isolated glyph key");
        XCTAssertFalse(simd_equal(attrsWithCursor[5].foregroundColor, attrsWithCursor[6].foregroundColor),
                       @"Cursor cell must receive cursor text color while adjacent '=' keeps normal foreground color");

        [window orderOut:nil];
    } @finally {
        [iTermPreferences setBool:savedUseMetal forKey:kPreferenceKeyUseMetal];
        [iTermPreferences setBool:savedBidi forKey:kPreferenceKeyBidi];
    }
}

@end
