//
//  NSWorkspace+iTerm.m
//  iTerm2
//
//  Created by George Nachman on 5/11/15.
//
//

#import "NSWorkspace+iTerm.h"

#import "DebugLogging.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermMalloc.h"
#import "iTermWarning.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

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

- (void)it_openURL:(NSURL *)url
            target:target
             style:(iTermOpenStyle)style
            window:(NSWindow *)window {
    [self it_openURL:url
              target:target
       configuration:[NSWorkspaceOpenConfiguration configuration]
               style:style
              window:window];
}

- (BOOL)it_urlIsWeb:(NSURL *)url {
    if (!url) {
        return NO;
    }
    if (![@[ @"http", @"https", @"ftp", @"file" ] containsObject:url.scheme]) {
        // The browser configured in advanced settings and the built-in browser don't handle this scheme.
        return NO;
    }
    return YES;
}

// A very weak check of whether the URL is openable by the built-in browser. This can be used to
// check if it's worth nagging the user to install the plugin to open this URL.
- (BOOL)it_localBrowserCouldHypotheticallyHandleURL:(NSURL *)url {
    return NO;
}

// Is this URL one that would open locally, or would request consent to open locally?
- (BOOL)it_urlIsConditionallyLocallyOpenable:(NSURL *)url {
    DLog(@"%@", url);
    if (![self it_urlIsWeb:url]) {
        return NO;
    }
    if (![self it_localBrowserCouldHypotheticallyHandleURL:url]) {
        return NO;
    }
    if ([self it_isDefaultBrowserForWebURL:url]) {
        return YES;
    }
    return [self it_tryToOpenURLLocallyDespiteNotBeingDefaultBrowser:url
                                                              target:nil
                                                       configuration:nil
                                                               style:iTermOpenStyleTab
                                                            testOnly:YES
                                                              window:nil];
}

- (BOOL)it_urlIsLocallyOpenableWithUpsell:(NSURL *)url {
    DLog(@"%@", url);
    if (![self it_urlIsWeb:url]) {
        return NO;
    }
    if (![self it_localBrowserCouldHypotheticallyHandleURL:url]) {
        return NO;
    }
    return [self it_tryToOpenURLLocallyDespiteNotBeingDefaultBrowser:url
                                                              target:nil
                                                       configuration:nil
                                                               style:iTermOpenStyleTab
                                                            testOnly:YES
                                                              window:nil];
}

// A high-confidence check of whether we'd open this URL ourselves.
// Assumes a web URL (see it_urlIsWeb:).
- (BOOL)it_isDefaultBrowserForWebURL:(NSURL *)url {
    return NO;
}

- (void)it_openURL:(NSURL *)url
            target:(NSString *)target
     configuration:(NSWorkspaceOpenConfiguration *)configuration
             style:(iTermOpenStyle)style
            window:(NSWindow *)window {
    [self it_openURL:url
              target:target
       configuration:configuration
               style:style
              upsell:YES
              window:window];
}


- (BOOL)it_localBrowserIsCompatibleWithFileURL:(NSURL *)url {
    NSString *ext = url.pathExtension;
    if (ext.length == 0) {
        return NO;
    }

    UTType *type = [UTType typeWithFilenameExtension:ext];
    if (!type) {
        return NO;
    }

    // Core web formats
    return ([type conformsToType:UTTypeHTML] ||
            [type conformsToType:UTTypeXML] ||
            [type conformsToType:[UTType typeWithIdentifier:@"public.svg-image"]] ||
            [type conformsToType:[UTType typeWithIdentifier:@"public.css"]] ||
            [type conformsToType:[UTType typeWithIdentifier:@"com.netscape.javascript-source"]] ||
            [type conformsToType:UTTypePDF] ||

            // Images
            [type conformsToType:UTTypePNG] ||
            [type conformsToType:UTTypeJPEG] ||
            [type conformsToType:UTTypeGIF] ||
            [type conformsToType:[UTType typeWithIdentifier:@"org.webmproject.webp"]] ||
            [type conformsToType:[UTType typeWithIdentifier:@"public.heic"]]);
}

- (BOOL)it_tryToOpenFileURLLocally:(NSURL *)url
                     configuration:(NSWorkspaceOpenConfiguration *)configuration
                             style:(iTermOpenStyle)style
                            upsell:(BOOL)upsell
                            window:(NSWindow *)window
                        completion:(void (^)(NSRunningApplication *app, NSError *error))completion {
    if (![self it_localBrowserIsCompatibleWithFileURL:url]) {
        return NO;
    }

    return [self it_tryToOpenURLLocally:url
                                 target:nil
                          configuration:configuration
                                  style:style
                                 upsell:upsell
                                 window:window];
}

- (BOOL)it_openIfNonWebURL:(NSURL *)url
             configuration:(NSWorkspaceOpenConfiguration *)configuration
                     style:(iTermOpenStyle)style
                    upsell:(BOOL)upsell
                    window:(NSWindow *)window
                completion:(void (^)(NSRunningApplication *app, NSError *error))completion {
    if ([@[ @"http", @"https", @"ftp" ] containsObject:url.scheme]) {
        return NO;
    }
    if ([url.scheme isEqualToString:@"file"]) {
        // Some files could usefully be opened locally, like PDFs.
        if ([self it_tryToOpenFileURLLocally:url
                               configuration:configuration
                                       style:style
                                      upsell:upsell
                                      window:window
                                  completion:completion]) {
            return YES;
        }
    }
    DLog(@"Non-web scheme");
    [self openURL:url
    configuration:configuration
completionHandler:^(NSRunningApplication *app, NSError *error) {
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(app, error);
            });
        }
    }];
    return YES;
}

- (void)it_openURL:(NSURL *)url
            target:(NSString *)target
     configuration:(NSWorkspaceOpenConfiguration *)configuration
             style:(iTermOpenStyle)style
            upsell:(BOOL)upsell
            window:(NSWindow *)window {
    RLog(@"%@", url);
    if (!url) {
        return;
    }
    if ([self it_openIfNonWebURL:url configuration:configuration style:style upsell:upsell window:window completion:nil]) {
        return;
    }

    if ([self it_tryToOpenURLLocally:url target:target configuration:configuration style:style upsell:upsell window:window]) {
        return;
    }

    [self it_openURLWithDefaultBrowser:url
                         configuration:configuration
                            completion:^(NSRunningApplication *app, NSError *error) {}];
}

- (BOOL)it_tryToOpenURLLocally:(NSURL *)url
                        target:(NSString *)target
                 configuration:(NSWorkspaceOpenConfiguration *)configuration
                         style:(iTermOpenStyle)style
                        upsell:(BOOL)upsell
                        window:(NSWindow *)window {
    return NO;
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
                 target:(NSString *)target
          configuration:(NSWorkspaceOpenConfiguration *)configuration
                  style:(iTermOpenStyle)style
                 upsell:(BOOL)upsell
                 window:(NSWindow *)window
             completion:(void (^)(NSRunningApplication *app, NSError *error))completion {
    DLog(@"%@", url);
    if (!url) {
        return;
    }
    if ([self it_openIfNonWebURL:url
                   configuration:configuration
                           style:style
                          upsell:upsell
                          window:window
                      completion:completion]) {
        return;
    }
    if ([self it_tryToOpenURLLocally:url target:target configuration:configuration style:style upsell:upsell window:window]) {
        completion([NSRunningApplication currentApplication], nil);
        return;
    }
    [self it_openURLWithDefaultBrowser:url
                         configuration:configuration
                            completion:completion];
}

- (BOOL)it_isDefaultAppForURL:(NSURL *)url {
    if (!url) {
        return NO;
    }

    // Ask NSWorkspace for the app that would open it
    NSURL *appURL = [[NSWorkspace sharedWorkspace] URLForApplicationToOpenURL:url];

    // Extract its bundle ID
    if (appURL != nil) {
        NSBundle *bundle = [NSBundle bundleWithURL:appURL];
        NSString *bundleID = bundle.bundleIdentifier;
        return [bundleID isEqual:NSBundle.mainBundle.bundleIdentifier];
    }
    return NO;
}

// In test-only mode, returns whether the URL could be opened locally if the
// user were hypothetically to consent should consent be needed.
- (BOOL)it_tryToOpenURLLocallyDespiteNotBeingDefaultBrowser:(NSURL *)url
                                                     target:(NSString *)target
                                              configuration:(NSWorkspaceOpenConfiguration *)configuration
                                                      style:(iTermOpenStyle)style
                                                   testOnly:(BOOL)testOnly
                                                     window:(NSWindow *)window {
    return NO;
}

- (BOOL)it_openURLLocally:(NSURL *)url
                   target:(NSString *)target
            configuration:(NSWorkspaceOpenConfiguration *)configuration
                openStyle:(iTermOpenStyle)openStyle {
    return [[iTermController sharedInstance] openURL:url
                                              target:target
                                           openStyle:openStyle
                                              select:configuration.activates];
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
