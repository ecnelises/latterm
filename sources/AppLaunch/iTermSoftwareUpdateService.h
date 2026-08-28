//
//  iTermSoftwareUpdateService.h
//  iTerm2
//

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const iTermSoftwareUpdateWillRestartNotification;

@protocol iTermSoftwareUpdateDriver <NSObject>

@property(nonatomic, readonly) BOOL automaticallyChecksForUpdates;
@property(nonatomic, readonly) NSNotificationName willRestartNotification;

- (void)checkForUpdates:(nullable id)sender;
- (BOOL)isUpdaterOwnedWindowController:(NSWindowController *)windowController;
- (NSComparisonResult)compareVersion:(NSString *)version toVersion:(NSString *)otherVersion;

@end

@interface iTermSoftwareUpdateService : NSObject

@property(class, nonatomic, readonly) iTermSoftwareUpdateService *sharedInstance;
@property(nonatomic, readonly) BOOL automaticallyChecksForUpdates;
@property(nonatomic, readonly, getter=isRestarting) BOOL restarting;

- (instancetype)initWithDriver:(id<iTermSoftwareUpdateDriver>)driver NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (void)checkForUpdates:(nullable id)sender;
- (BOOL)isUpdaterOwnedWindowController:(nullable NSWindowController *)windowController;
- (BOOL)isVersion:(NSString *)version newerThan:(NSString *)otherVersion;
- (void)configureFeedURL:(NSURL *)feedURL alternateAppName:(nullable NSString *)alternateAppName;

@end


NS_ASSUME_NONNULL_END
