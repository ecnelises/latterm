//
//  iTermProfilePreferencesTabViewWrapperView.m
//  iTerm2
//
//  Created by George Nachman on 2/9/19.
//

#import "iTermProfilePreferencesTabViewWrapperView.h"

@implementation iTermProfilePreferencesTabViewWrapperView {
    IBOutlet NSView *_tabView;
}

- (void)resizeWithOldSuperviewSize:(NSSize)oldSize {
    [super resizeWithOldSuperviewSize:oldSize];
    [self layoutTabView];
}

- (void)setFrameSize:(NSSize)newSize {
    [super setFrameSize:newSize];
    [self layoutTabView];
}

- (void)layoutTabView {
    _tabView.frame = self.bounds;
    [_tabView setNeedsLayout:YES];
}

@end
