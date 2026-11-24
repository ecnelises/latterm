//
//  iTermAdvancedGPUSettingsViewController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/18/18.
//

#import "iTermAdvancedGPUSettingsViewController.h"

#import <Metal/Metal.h>

@interface iTermAdvancedGPUSettingsViewController ()

@end

@implementation iTermAdvancedGPUSettingsViewController

- (void)loadView {
    NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 390, 139)];

    NSButton *disableWhenDisconnected = [NSButton checkboxWithTitle:@"Disable GPU renderer when disconnected from power"
                                                             target:nil
                                                             action:nil];
    disableWhenDisconnected.frame = NSMakeRect(18, 103, 354, 18);
    [container addSubview:disableWhenDisconnected];
    self.disableWhenDisconnected = disableWhenDisconnected;

    NSButton *disableInLowPowerMode = [NSButton checkboxWithTitle:@"Disable GPU renderer in low power mode"
                                                           target:nil
                                                           action:nil];
    disableInLowPowerMode.frame = NSMakeRect(18, 81, 354, 18);
    [container addSubview:disableInLowPowerMode];
    self.disableInLowPowerMode = disableInLowPowerMode;

    NSButton *preferIntegratedGPU = [NSButton checkboxWithTitle:@"Prefer integrated to discrete GPU"
                                                         target:nil
                                                         action:nil];
    preferIntegratedGPU.frame = NSMakeRect(18, 59, 354, 18);
    [container addSubview:preferIntegratedGPU];
    self.preferIntegratedGPU = preferIntegratedGPU;

    self.view = container;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    NSArray<id<MTLDevice>> *devices = MTLCopyAllDevices();

    BOOL foundLowPower = NO;
    BOOL foundHighPower = NO;
    for (id<MTLDevice> device in devices) {
        if (device.isLowPower) {
            foundLowPower = YES;
        } else {
            foundHighPower = YES;
        }
    }

    self.preferIntegratedGPU.enabled = (foundLowPower && foundHighPower);
    self.disableInLowPowerMode.enabled = YES;
}

@end

@implementation iTermAdvancedGPUSettingsWindowController

- (instancetype)init {
    return [self initWithWindow:nil];
}

- (instancetype)initWithWindowNibName:(NSNibName)windowNibName {
    return [self initWithWindow:nil];
}

- (instancetype)initWithWindow:(NSWindow *)window {
    self = [super initWithWindow:window];
    if (self) {
        if (!self.viewController) {
            self.viewController = [[iTermAdvancedGPUSettingsViewController alloc] init];
        }
    }
    return self;
}

- (NSNibName)windowNibName {
    return @"iTermAdvancedGPUSettingsWindowController";
}

- (void)loadWindow {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 390, 139)
                                                   styleMask:NSWindowStyleMaskTitled
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"Window";
    window.restorable = NO;
    window.releasedWhenClosed = NO;

    if (!self.viewController) {
        self.viewController = [[iTermAdvancedGPUSettingsViewController alloc] init];
    }
    NSView *contentView = window.contentView;
    NSView *vcView = self.viewController.view;
    vcView.frame = contentView.bounds;
    [contentView addSubview:vcView];

    NSButton *cancelButton = [NSButton buttonWithTitle:@"Cancel"
                                                target:self
                                                action:@selector(cancel:)];
    cancelButton.keyEquivalent = @"\033";
    cancelButton.frame = NSMakeRect(220, 13, 82, 32);
    [contentView addSubview:cancelButton];

    NSButton *okButton = [NSButton buttonWithTitle:@"OK"
                                            target:self
                                            action:@selector(ok:)];
    okButton.keyEquivalent = @"\r";
    okButton.frame = NSMakeRect(306, 13, 66, 32);
    [contentView addSubview:okButton];

    self.window = window;
}

- (IBAction)ok:(id)sender {
    [self.window.sheetParent endSheet:self.window
                           returnCode:NSModalResponseOK];
}

- (IBAction)cancel:(id)sender {
    [self.window.sheetParent endSheet:self.window
                           returnCode:NSModalResponseCancel];
}

@end
