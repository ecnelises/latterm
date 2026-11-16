//
//  iTermShortcutsViewController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/7/20.
//

#import "iTermShortcutsViewController.h"

#import "iTermActionsEditingViewController.h"
#import "iTermSnippetsEditingViewController.h"
#import "iTerm2SharedARC-Swift.h"

@interface iTermShortcutsViewController ()

@end

@implementation iTermShortcutsViewController {
    IBOutlet NSTabView *_tabView;
    IBOutlet iTermActionsEditingViewController *_actionsViewController;
    IBOutlet iTermSnippetsEditingViewController *_snippetsViewController;
    IBOutlet NSView *_actionsView;
    IBOutlet NSView *_snippetsView;
}

- (void)awakeFromNib {
    [_actionsViewController defineControlsInContainer:self containerView:_actionsView];
    [_snippetsViewController defineControlsInContainer:self containerView:_snippetsView];
    for (NSViewController *editor in @[_actionsViewController, _snippetsViewController]) {
        NSView *view = editor.view;
        [iTermSettingsFormView alignControlsIn:view];
        const CGFloat width = NSWidth(view.bounds);
        NSMutableArray<NSButton *> *trailingButtons = [NSMutableArray array];
        for (NSView *child in view.subviews) {
            if ([child isKindOfClass:NSScrollView.class]) {
                NSRect frame = child.frame;
                frame.size.width = width;
                child.frame = frame;
                child.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
            } else if ([child isKindOfClass:NSSearchField.class]) {
                NSRect frame = child.frame;
                frame.size.width = MAX(0, width - 36);
                child.frame = frame;
                child.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
            } else if ([child isKindOfClass:NSButton.class] && [(NSButton *)child action] == @selector(help:)) {
                NSRect frame = child.frame;
                frame.origin.x = width - NSWidth(frame);
                child.frame = frame;
                child.autoresizingMask = NSViewMinXMargin | NSViewMinYMargin;
            } else if ([child isKindOfClass:NSButton.class] &&
                       ((child.autoresizingMask & NSViewMinXMargin) != 0 || NSMinX(child.frame) > width * 0.5)) {
                [trailingButtons addObject:(NSButton *)child];
            }
        }
        [trailingButtons sortUsingComparator:^NSComparisonResult(NSButton *a, NSButton *b) {
            return [@(NSMinX(a.frame)) compare:@(NSMinX(b.frame))];
        }];
        CGFloat rightEdge = width;
        for (NSButton *button in trailingButtons.reverseObjectEnumerator) {
            NSRect frame = button.frame;
            frame.origin.x = rightEdge - NSWidth(frame);
            button.frame = frame;
            button.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin;
            rightEdge = NSMinX(frame) - 6;
        }
    }
}

- (NSTabView *)tabView {
    return _tabView;
}

- (CGFloat)minimumWidth {
    return 778;
}

- (NSView *)searchableViewControllerRevealItemForDocument:(iTermPreferencesSearchDocument *)document
                                                 forQuery:(NSString *)query
                                            willChangeTab:(BOOL *)willChangeTab {
    if ([document.identifier isEqualToString:kPreferenceKeyActions]) {
        NSString *identifier = @"Actions";
        *willChangeTab = ![_tabView.selectedTabViewItem.identifier isEqualToString:identifier];
        [_tabView selectTabViewItemWithIdentifier:identifier];
        return _actionsView;
    }
    if ([document.identifier isEqualToString:kPreferenceKeySnippets]) {
        NSString *identifier = @"Snippets";
        *willChangeTab = ![_tabView.selectedTabViewItem.identifier isEqualToString:identifier];
        [_tabView selectTabViewItemWithIdentifier:identifier];
        return _snippetsView;
    }
    return nil;
}


@end
