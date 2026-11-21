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

- (instancetype)initWithFrame:(NSRect)frameRect tabView:(NSView *)tabView {
    self = [super initWithFrame:frameRect];
    if (self) {
        _tabView = tabView;
    }
    return self;
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
