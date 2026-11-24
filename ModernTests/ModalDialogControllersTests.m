//
//  ModalDialogControllersTests.m
//  ModernTests
//

#import <Cocoa/Cocoa.h>
#import <XCTest/XCTest.h>

#import "iTermAdvancedGPUSettingsViewController.h"
#import "iTermEditSnippetWindowController.h"
#import "iTermParameterPanelWindowController.h"

@interface iTermAdvancedGPUSettingsWindowController (ModalDialogTests)
- (void)ok:(id)sender;
- (void)cancel:(id)sender;
@end

@interface iTermParameterPanelWindowController (ModalDialogTests)
- (void)parameterPanelEnd:(id)sender;
@end

@interface iTermEditSnippetWindowController (ModalDialogTests)
- (void)ok:(id)sender;
- (void)cancel:(id)sender;
@end

@interface ModalDialogControllersTests : XCTestCase
@end

@implementation ModalDialogControllersTests

- (void)testAdvancedGPUSettingsWindowControllerProgrammaticSetup {
    iTermAdvancedGPUSettingsWindowController *controller = [[iTermAdvancedGPUSettingsWindowController alloc] init];
    iTermAdvancedGPUSettingsViewController *vc = controller.viewController;
    XCTAssertNotNil(vc);

    NSWindow *window = controller.window;
    XCTAssertNotNil(window);
    XCTAssertNotNil(vc.disableWhenDisconnected);
    XCTAssertNotNil(vc.disableInLowPowerMode);
    XCTAssertNotNil(vc.preferIntegratedGPU);
    XCTAssertTrue(vc.disableInLowPowerMode.isEnabled);
    XCTAssertEqual(vc.disableWhenDisconnected.superview, vc.view);
    XCTAssertTrue([vc.view isDescendantOf:window.contentView]);

    NSButton *okButton = nil;
    NSButton *cancelButton = nil;
    for (NSView *subview in window.contentView.subviews) {
        if ([subview isKindOfClass:[NSButton class]]) {
            NSButton *btn = (NSButton *)subview;
            if (btn.action == @selector(ok:)) {
                okButton = btn;
            } else if (btn.action == @selector(cancel:)) {
                cancelButton = btn;
            }
        }
    }
    XCTAssertNotNil(okButton);
    XCTAssertNotNil(cancelButton);
    XCTAssertEqualObjects(okButton.keyEquivalent, @"\r");
    XCTAssertEqualObjects(cancelButton.keyEquivalent, @"\033");
}

- (void)testParameterPanelWindowControllerProgrammaticSetupAndActions {
    iTermParameterPanelWindowController *controller = [[iTermParameterPanelWindowController alloc] init];
    NSWindow *window = controller.window;
    XCTAssertNotNil(window);
    XCTAssertEqualObjects(window.title, @"Session Parameter");
    XCTAssertNotNil(controller.parameterPrompt);
    XCTAssertNotNil(controller.parameterName);
    XCTAssertNotNil(controller.parameterValue);
    XCTAssertEqual(window.initialFirstResponder, controller.parameterValue);

    controller.parameterValue.stringValue = @"prod";
    NSButton *cancelButton = nil;
    NSButton *okButton = nil;
    for (NSView *subview in window.contentView.subviews) {
        if ([subview isKindOfClass:[NSButton class]]) {
            NSButton *btn = (NSButton *)subview;
            if (btn.action == @selector(parameterPanelEnd:)) {
                if (btn.tag == 0) {
                    cancelButton = btn;
                } else if (btn.tag == 1) {
                    okButton = btn;
                }
            }
        }
    }
    XCTAssertNotNil(cancelButton);
    XCTAssertNotNil(okButton);
    XCTAssertEqualObjects(cancelButton.keyEquivalent, @"\033");
    XCTAssertEqualObjects(okButton.keyEquivalent, @"\r");

    [controller parameterPanelEnd:cancelButton];
    XCTAssertTrue(controller.canceled);

    [controller parameterPanelEnd:okButton];
    XCTAssertFalse(controller.canceled);
    XCTAssertEqualObjects(controller.parameterValue.stringValue, @"prod");
}

- (void)testEditSnippetWindowControllerProgrammaticSaveAndCancel {
    iTermSnippet *existing = [[iTermSnippet alloc] initWithTitle:@"Deploy"
                                                             value:@"echo hello"
                                                              guid:@"snippet-guid-1"
                                                              tags:@[@"ops/prod"]
                                                          escaping:iTermSendTextEscapingNone
                                                           version:[iTermSnippet currentVersion]];
    NSMutableArray *captured = [NSMutableArray array];
    iTermEditSnippetWindowController *controller =
        [[iTermEditSnippetWindowController alloc] initWithSnippet:existing
                                                       completion:^(iTermSnippet * _Nullable result) {
            [captured addObject:(result ?: [NSNull null])];
        }];
    NSWindow *window = controller.window;
    XCTAssertNotNil(window);
    XCTAssertNotNil(window.contentView);

    NSButton *saveButton = nil;
    NSButton *cancelButton = nil;
    for (NSView *subview in window.contentView.subviews) {
        if ([subview isKindOfClass:[NSButton class]]) {
            NSButton *btn = (NSButton *)subview;
            if (btn.action == @selector(ok:)) {
                saveButton = btn;
            } else if (btn.action == @selector(cancel:)) {
                cancelButton = btn;
            }
        }
    }
    XCTAssertNotNil(saveButton);
    XCTAssertNotNil(cancelButton);
    XCTAssertEqualObjects(cancelButton.keyEquivalent, @"\033");

    [controller ok:saveButton];
    XCTAssertEqual(captured.count, 1u);
    XCTAssertTrue([captured[0] isKindOfClass:[iTermSnippet class]]);
    iTermSnippet *saved = (iTermSnippet *)captured[0];
    XCTAssertEqualObjects(saved.title, @"Deploy");
    XCTAssertEqualObjects(saved.value, @"echo hello");
    XCTAssertEqualObjects(saved.guid, @"snippet-guid-1");
    XCTAssertEqualObjects(saved.tags, @[@"ops/prod"]);
    XCTAssertEqual(saved.escaping, iTermSendTextEscapingNone);

    [controller cancel:cancelButton];
    XCTAssertEqual(captured.count, 2u);
    XCTAssertEqualObjects(captured[1], [NSNull null]);
    XCTAssertNil(controller.snippet);
}

@end
