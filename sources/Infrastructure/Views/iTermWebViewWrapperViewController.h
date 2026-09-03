//
//  iTermWebViewWrapperView.h
//  iTerm2
//
//  Created by George Nachman on 11/3/15.
//
//

#import <Cocoa/Cocoa.h>

@class WKWebView;

@interface iTermWebViewWrapperViewController : NSViewController

- (instancetype)initWithWebView:(WKWebView *)webView backupURL:(NSURL *)backupURL;

- (void)terminateWebView;

@end

@interface iTermWebViewFactory : NSObject
+ (instancetype)sharedInstance;
- (WKWebView *)webView;
@end
