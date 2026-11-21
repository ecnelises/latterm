//
//  iTermShortcutsViewController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/7/20.
//

#import "iTermShortcutsViewController.h"

#import "iTermActionsEditingViewController.h"
#import "iTermSizeRememberingView.h"
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
    BOOL _configured;
}

- (void)loadView {
    iTermSizeRememberingView *root = [[iTermSizeRememberingView alloc] initWithFrame:NSMakeRect(0, 0, 892, 394)];
    iTermSettingsTabView *tabs = [iTermSettingsControlFactory sectionTabViewWithFrame:NSMakeRect(13, 10, 866, 390)
                                                                                items:@[
        @[ @"Actions", @"Actions" ],
        @[ @"Snippets", @"Snippets" ]
    ]];
    NSView *actionsWrapper = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 846, 344)];
    NSView *actionsCustomView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 852, 344)];
    actionsCustomView.identifier = @"ActionCustomView";
    [actionsWrapper addSubview:actionsCustomView];
    tabs.tabViewItems[0].view = actionsWrapper;

    NSView *snippetsWrapper = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 846, 344)];
    NSView *snippetsCustomView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 849, 341)];
    snippetsCustomView.identifier = @"SnippetCustomView";
    [snippetsWrapper addSubview:snippetsCustomView];
    tabs.tabViewItems[1].view = snippetsWrapper;

    [root addSubview:tabs];
    _tabView = tabs;
    _actionsView = actionsCustomView;
    _snippetsView = snippetsCustomView;
    _actionsViewController = [[iTermActionsEditingViewController alloc] initWithNibName:nil bundle:nil];
    _snippetsViewController = [[iTermSnippetsEditingViewController alloc] initWithNibName:nil bundle:nil];
    self.view = root;
    [self configureShortcutEditors];
}

- (void)awakeFromNib {
    [self configureShortcutEditors];
}

- (void)configureShortcutEditors {
    if (_configured) {
        return;
    }
    _configured = YES;
    [_actionsViewController defineControlsInContainer:self containerView:_actionsView];
    [_snippetsViewController defineControlsInContainer:self containerView:_snippetsView];
    for (NSViewController *editor in @[_actionsViewController, _snippetsViewController]) {
        NSView *view = editor.view;
        CGFloat leading = CGFLOAT_MAX;
        for (NSView *child in view.subviews) {
            if (!child.isHidden) {
                leading = MIN(leading, NSMinX(child.frame));
            }
        }
        if (leading < CGFLOAT_MAX && leading != 0) {
            for (NSView *child in view.subviews) {
                NSRect f = child.frame;
                f.origin.x -= leading;
                child.frame = f;
            }
        }
        const CGFloat width = NSWidth(view.bounds);
        NSMutableArray<NSButton *> *trailingButtons = [NSMutableArray array];
        for (NSView *child in view.subviews) {
            if ([child isKindOfClass:NSScrollView.class]) {
                NSRect frame = child.frame;
                frame.origin.x = 0;
                frame.size.width = width;
                child.frame = frame;
                child.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
            } else if ([child isKindOfClass:NSSearchField.class]) {
                NSRect frame = child.frame;
                frame.origin.x = 0;
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
