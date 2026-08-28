//
//  iTermSoftwareUpdateService.m
//  iTerm2
//

#import "iTermSoftwareUpdateService.h"

#import "DebugLogging.h"
#import "iTermUserDefaults.h"

@import Sparkle;

NSNotificationName const iTermSoftwareUpdateWillRestartNotification =
    @"iTermSoftwareUpdateWillRestartNotification";

@interface iTermSparkleUpdateDriver : NSObject<iTermSoftwareUpdateDriver, SPUUpdaterDelegate>

@property(nonatomic, strong) SPUStandardUpdaterController *updaterController;
@property(nonatomic, copy, nullable) NSString *feedURLString;

@end

@implementation iTermSparkleUpdateDriver

- (instancetype)init {
    self = [super init];
    if (self) {
        NSUserDefaults *defaults = [iTermUserDefaults userDefaults];
        [defaults removeObjectForKey:@"SUFeedAlternateAppNameKey"];
        _updaterController =
            [[SPUStandardUpdaterController alloc] initWithUpdaterDelegate:self
                                                      userDriverDelegate:nil];
        [_updaterController.updater clearFeedURLFromUserDefaults];
    }
    return self;
}

- (BOOL)automaticallyChecksForUpdates {
    return self.updaterController.updater.automaticallyChecksForUpdates;
}

- (NSNotificationName)willRestartNotification {
    return SUUpdaterWillRestartNotification;
}

- (void)checkForUpdates:(id)sender {
    [self.updaterController checkForUpdates:sender];
}

- (BOOL)isUpdaterOwnedWindowController:(NSWindowController *)windowController {
    NSBundle *controllerBundle = [NSBundle bundleForClass:windowController.class];
    NSBundle *updaterBundle = [NSBundle bundleForClass:SPUStandardUpdaterController.class];
    return [controllerBundle.bundlePath isEqualToString:updaterBundle.bundlePath];
}

- (void)configureFeedURL:(NSURL *)feedURL {
    self.feedURLString = feedURL.absoluteString;
    [self.updaterController.updater resetUpdateCycle];
}

- (nullable NSString *)feedURLStringForUpdater:(SPUUpdater *)updater {
    return self.feedURLString;
}

@end

@interface iTermSoftwareUpdateService ()

@property(nonatomic, strong) id<iTermSoftwareUpdateDriver> driver;
@property(nonatomic, readwrite, getter=isRestarting) BOOL restarting;

@end

@implementation iTermSoftwareUpdateService

+ (instancetype)sharedInstance {
    static iTermSoftwareUpdateService *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] initWithDriver:[[iTermSparkleUpdateDriver alloc] init]];
    });
    return instance;
}

- (instancetype)initWithDriver:(id<iTermSoftwareUpdateDriver>)driver {
    self = [super init];
    if (self) {
        _driver = driver;
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(updateDriverWillRestart:)
                                                     name:driver.willRestartNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (BOOL)automaticallyChecksForUpdates {
    return self.driver.automaticallyChecksForUpdates;
}

- (void)checkForUpdates:(id)sender {
    DLog(@"Checking for application updates");
    [self.driver checkForUpdates:sender];
}

- (BOOL)isUpdaterOwnedWindowController:(NSWindowController *)windowController {
    if (!windowController) {
        return NO;
    }
    return [self.driver isUpdaterOwnedWindowController:windowController];
}

- (void)configureFeedURL:(NSURL *)feedURL {
    [self.driver configureFeedURL:feedURL];
}

- (void)updateDriverWillRestart:(NSNotification *)notification {
    if (self.restarting) {
        return;
    }
    DLog(@"Application updater will restart the app");
    self.restarting = YES;
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermSoftwareUpdateWillRestartNotification
                                                        object:self];
}

@end
