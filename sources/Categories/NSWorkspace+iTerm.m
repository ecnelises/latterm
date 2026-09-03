//
//  NSWorkspace+iTerm.m
//  iTerm2
//
//  Created by George Nachman on 5/11/15.
//
//

#import "NSWorkspace+iTerm.h"

#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermMalloc.h"

@implementation NSWorkspace (iTerm)

- (NSString *)temporaryFileNameWithPrefix:(NSString *)prefix suffix:(NSString *)suffix {
    NSString *template = [NSString stringWithFormat:@"%@XXXXXX%@", prefix ?: @"", suffix ?: @""];
    NSString *tempFileTemplate =
    [NSTemporaryDirectory() stringByAppendingPathComponent:template];
    const char *tempFileTemplateCString =
    [tempFileTemplate fileSystemRepresentation];
    char *tempFileNameCString = (char *)iTermMalloc(strlen(tempFileTemplateCString) + 1);
    strcpy(tempFileNameCString, tempFileTemplateCString);
    int fileDescriptor = mkstemps(tempFileNameCString, suffix.length);

    if (fileDescriptor == -1) {
        XLog(@"mkstemps failed with template %s: %s", tempFileNameCString, strerror(errno));
        free(tempFileNameCString);
        return nil;
    }
    close(fileDescriptor);
    NSString *filename = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:tempFileNameCString
                                                                                     length:strlen(tempFileNameCString)];
    free(tempFileNameCString);
    return filename;
}

- (BOOL)it_securityAgentIsActive {
    NSRunningApplication *activeApplication = [[NSWorkspace sharedWorkspace] frontmostApplication];
    NSString *bundleIdentifier = activeApplication.bundleIdentifier;
    return [bundleIdentifier isEqualToString:@"com.apple.SecurityAgent"];
}

- (void)it_openURL:(NSURL *)url {
    [self it_openURL:url configuration:[NSWorkspaceOpenConfiguration configuration]];
}

- (void)it_openURL:(NSURL *)url
     configuration:(NSWorkspaceOpenConfiguration *)configuration {
    RLog(@"%@", url);
    if (!url) {
        return;
    }
    if (![@[ @"http", @"https", @"ftp" ] containsObject:url.scheme.lowercaseString]) {
        [self openURL:url configuration:configuration completionHandler:nil];
        return;
    }
    [self it_openURLWithDefaultBrowser:url
                         configuration:configuration
                            completion:^(NSRunningApplication *app, NSError *error) {}];
}

- (void)it_openURLWithDefaultBrowser:(NSURL *)url
                       configuration:(NSWorkspaceOpenConfiguration *)configuration
                          completion:(void (^)(NSRunningApplication *app, NSError *error))completion {
    NSString *bundleID = [iTermAdvancedSettingsModel browserBundleID];
    if ([bundleID stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]].length == 0) {
        // No custom app configured in advanced settings so use the systemwide default.
        RLog(@"Empty custom bundle ID “%@”", bundleID);
        [self openURL:url configuration:configuration completionHandler:^(NSRunningApplication *app, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(app, error);
            });
        }];
        return;
    }
    NSURL *appURL = [self URLForApplicationWithBundleIdentifier:bundleID];
    if (!appURL) {
        // The custom app configured in advanced settings isn't installed. Use the sytemwide default.
        RLog(@"No url for bundle ID %@", bundleID);
        [self openURL:url configuration:configuration completionHandler:^(NSRunningApplication *app, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(app, error);
            });
        }];
        return;
    }

    // Open with the advanced-settings-configured default browser.
    RLog(@"Open %@ with %@", url, appURL);
    [self openURLs:@[ url ]
      withApplicationAtURL:appURL
             configuration:configuration
         completionHandler:^(NSRunningApplication *app, NSError *error) {
        if (error) {
            // That didn't work so just use the default browser
            return [self openURL:url configuration:configuration completionHandler:completion];
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(app, error);
            });
        }
    }];
}

- (void)it_asyncOpenURL:(NSURL *)url
          configuration:(NSWorkspaceOpenConfiguration *)configuration
             completion:(void (^)(NSRunningApplication *app, NSError *error))completion {
    DLog(@"%@", url);
    if (!url) {
        return;
    }
    if (![@[ @"http", @"https", @"ftp" ] containsObject:url.scheme.lowercaseString]) {
        [self openURL:url configuration:configuration completionHandler:^(NSRunningApplication *app, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(app, error);
            });
        }];
        return;
    }
    [self it_openURLWithDefaultBrowser:url
                         configuration:configuration
                            completion:completion];
}

static NSMutableSet<NSString * > *urlTokens;

- (NSString *)it_newToken {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        urlTokens = [NSMutableSet set];
    });
    NSString *token = [[NSUUID UUID] UUIDString];
    [urlTokens addObject:token];
    return token;
}

- (BOOL)it_checkToken:(NSString *)token {
    if (![urlTokens containsObject:token]) {
        return NO;
    }
    [urlTokens removeObject:token];
    return YES;
}

- (void)it_revealInFinder:(NSString *)path {
    NSURL *finderURL = [[NSWorkspace sharedWorkspace] URLForApplicationWithBundleIdentifier:@"com.apple.finder"];
    if (!finderURL) {
        RLog(@"Can't find Finder");
        return;
    }
    [[NSWorkspace sharedWorkspace] openURLs:@[ [NSURL fileURLWithPath:path] ]
                       withApplicationAtURL:finderURL
                              configuration:[NSWorkspaceOpenConfiguration configuration]
                          completionHandler:nil];
}

@end
