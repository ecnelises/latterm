//
//  iTermWebViewWrapperView.m
//  iTerm2
//
//  Created by George Nachman on 11/3/15.
//
//

#import "iTermWebViewWrapperViewController.h"

#import "iTermAdvancedSettingsModel.h"
#import "iTermFlippedView.h"
#import "NSWorkspace+iTerm.h"
#import <WebKit/WebKit.h>

@interface iTermWebViewWrapperViewController ()
@property(nonatomic, strong) WKWebView *webView;
@property(nonatomic, copy) NSURL *backupURL;
@end

@implementation iTermWebViewWrapperViewController

- (instancetype)initWithWebView:(WKWebView *)webView backupURL:(NSURL *)backupURL {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        self.webView = webView;
        self.backupURL = backupURL;
    }
    return self;
}

- (void)loadView {
    self.view = [[iTermFlippedView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600)];
    self.view.autoresizesSubviews = YES;

    CGFloat y;
    if (_backupURL != nil) {
        NSButton *button = [[NSButton alloc] init];
        [button setButtonType:NSButtonTypeMomentaryPushIn];
        [button setTarget:self];
        [button setAction:@selector(openInBrowserButtonPressed:)];
        [button setTitle:[NSString stringWithFormat:@"Open in %@", [self browserName]]];
        [button setBezelStyle:NSBezelStyleTexturedRounded];
        [button sizeToFit];
        NSRect frame = button.frame;
        frame.origin.x = self.view.frame.origin.x + 8;
        frame.origin.y = 8;
        button.frame = frame;
        button.autoresizingMask = NSViewMaxXMargin | NSViewMaxYMargin;
        [self.view addSubview:button];
        y = NSMaxY(frame) + 8;
    } else {
        y = 0;
    }

    const NSRect frame = NSMakeRect(0, y, self.view.frame.size.width, self.view.frame.size.height - y);
    self.webView.frame = frame;
    self.webView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self.view addSubview:self.webView];
}

- (void)openInBrowserButtonPressed:(id)sender {
    NSURL *URL = self.webView.URL ?: self.backupURL;
    if ([URL isEqual:[NSURL URLWithString:@"about:blank"]]) {
        URL = self.backupURL;
    }
    [[NSWorkspace sharedWorkspace] it_openURL:URL];
}

- (NSString *)browserName {
    CFErrorRef error;
    NSURL *URL = self.webView.URL ?: [NSURL URLWithString:@"http://example.com"];
    NSURL *appUrl = (__bridge_transfer NSURL *)LSCopyDefaultApplicationURLForURL((__bridge CFURLRef)URL,
                                                                                 kLSRolesAll,
                                                                                 &error);
    if (appUrl) {
        NSString *name = nil;
        [appUrl getResourceValue:&name forKey:NSURLLocalizedNameKey error:NULL];
        if (name) {
            return name;
        }
    }
    return @"Default Browser";
}

- (void)terminateWebView {
    [_webView stopLoading];
    [_webView loadHTMLString:@"<html/>" baseURL:nil];
}

@end

@implementation iTermWebViewFactory

+ (instancetype)sharedInstance {
    static id instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (WKWebView *)webView {
    WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];

    NSString *webUserAgent = [iTermAdvancedSettingsModel webUserAgent];
    if (!webUserAgent.length) {
        configuration.applicationNameForUserAgent = @"Latterm";
    }

    WKPreferences *prefs = [[WKPreferences alloc] init];
    prefs.javaScriptCanOpenWindowsAutomatically = NO;
    configuration.preferences = prefs;
    configuration.websiteDataStore = [WKWebsiteDataStore defaultDataStore];
    WKWebView *webView = [[WKWebView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600)
                                                 configuration:configuration];
    if (webUserAgent.length) {
        webView.customUserAgent = webUserAgent;
    }
    return webView;
}

@end
