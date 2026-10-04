//
//  ArrangementPreviewView.m
//  iTerm
//
//  Created by George Nachman on 8/6/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import "ArrangementPreviewView.h"
#import "NSAppearance+iTerm.h"
#import "PseudoTerminal.h"

@implementation ArrangementPreviewView

- (void)setArrangement:(NSArray*)arrangement {
    arrangement_ = [arrangement copy];
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
    dirtyRect = NSIntersectionRect(dirtyRect, self.bounds);
    [NSColor.controlBackgroundColor setFill];
    NSRectFill(dirtyRect);
    if (arrangement_.count == 0) {
        NSString *message = NSLocalizedString(@"Select a saved window layout to see its preview.", @"Empty layout preview");
        NSDictionary *attributes = @{NSFontAttributeName: [NSFont systemFontOfSize:13],
                                     NSForegroundColorAttributeName: NSColor.secondaryLabelColor};
        NSRect textRect = NSInsetRect(self.bounds, 20, 20);
        textRect.origin.y = MAX(20, (NSHeight(self.bounds) - 40) / 2);
        textRect.size.height = 40;
        [message drawInRect:textRect withAttributes:attributes];
        return;
    }

    NSArray *screens = [NSScreen screens];
    CGFloat xMax = 0, yMax = 0;
    CGFloat xMin = 0, yMin = 0;
    for (NSScreen *screen in screens) {
        NSRect frame = [screen frame];
        CGFloat x = frame.origin.x + frame.size.width;
        CGFloat y = frame.origin.y + frame.size.height;
        xMax = MAX(xMax, x);
        yMax = MAX(yMax, y);
        xMin = MIN(xMin, frame.origin.x);
        yMin = MIN(yMin, frame.origin.y);
    }

    double xScale = [self frame].size.width / (xMax - xMin);
    double yScale = [self frame].size.height / (yMax - yMin);
    double scale = MIN(xScale, yScale);
    double yCorrection = MAX(0, ([self frame].size.height - (yMax - yMin) * scale) / 2);
    double xCorrection = MAX(0, ([self frame].size.width - (xMax - xMin) * scale) / 2);

    NSMutableArray *screenFrames = [NSMutableArray array];
    for (NSScreen *screen in screens) {
        NSRect frame = [screen frame];

        NSRect rect = NSMakeRect((frame.origin.x - xMin) * scale + xCorrection,
                                 (yMax - frame.size.height - frame.origin.y) * scale + yCorrection,
                                 frame.size.width * scale,
                                 frame.size.height * scale);
        [[NSColor blackColor] set];
        NSFrameRect(rect);

        rect.origin.x++;
        rect.origin.y++;
        rect.size.width -= 2;
        rect.size.height -= 2;
        [[NSColor colorWithCalibratedRed:0.270 green:0.545 blue:0.811 alpha:1] set];
        NSRectFill(rect);

        [screenFrames addObject:[NSValue valueWithRect:rect]];
    }

    for (NSDictionary* terminalArrangement in arrangement_) {
        [PseudoTerminal drawArrangementPreview:terminalArrangement
                                  screenFrames:screenFrames
                                          dark:self.effectiveAppearance.it_isDark];
    }
}

- (BOOL)isFlipped
{
    return YES;
}

@end
