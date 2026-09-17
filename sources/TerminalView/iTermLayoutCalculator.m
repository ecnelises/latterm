//
//  iTermLayoutCalculator.m
//  iTerm2
//
//  Created by George Nachman on 2/25/26.
//
//  IMPORTANT: Tab bar overlap handling has two mutually exclusive mechanisms:
//
//  1. shouldLeaveEmptyAreaAtTop (decoration heights approach):
//     - Used during transitional states when tab bar is on loan but not yet an accessory
//     - Adds tab bar height to decorationHeightTop
//     - Applied when the tab bar is hidden
//
//  2. tabViewFrameByShrinkingForFullScreenTabBar (frame shrinking approach):
//     - Used when tab bar IS a titlebar accessory that overlaps content
//     - Shrinks the frame directly by tab bar height
//     - Called after decoration calculation
//
//  These mechanisms are mutually exclusive to avoid double-deduction.
//  When shouldLeaveEmptyAreaAtTop is true, frame shrinking is skipped.
//

#import "iTermLayoutCalculator.h"

// These match the PSMTabBarControl constants
const int kLayoutTabPositionTop = 0;
const int kLayoutTabPositionBottom = 1;
const int kLayoutTabPositionLeft = 2;
const int kLayoutTabPositionRight = 3;

@implementation iTermLayoutCalculator

// Compute the space reserved for decorations once, then carve the status bar
// out of the resulting terminal area. Flashing tabs overlay rather than reserve
// space. An on-loan top tab is accounted for by the fullscreen accessory path.
+ (iTermLayoutOutputs)calculateLayoutWithInputs:(iTermLayoutInputs)inputs {
    iTermLayoutOutputs outputs = {0};
    outputs.decorationHeightTop = inputs.notchInset +
        (inputs.divisionViewVisible ? inputs.divisionViewHeight : 0);
    const CGFloat contentWidth = inputs.contentViewWidth -
        (inputs.shouldShowToolbelt ? inputs.toolbeltWidth : 0);
    CGFloat terminalX = 0;
    CGFloat terminalWidth = contentWidth;

    if (!inputs.tabBarVisible) {
        if (inputs.shouldLeaveEmptyAreaAtTop || inputs.drawWindowTitleInPlaceOfTabBar) {
            outputs.decorationHeightTop += inputs.tabBarHeight;
        }
    } else {
        switch (inputs.tabPosition) {
            case kLayoutTabPositionLeft:
            case kLayoutTabPositionRight: {
                const BOOL onLeft = inputs.tabPosition == kLayoutTabPositionLeft;
                outputs.tabBarFrame = CGRectMake(onLeft ? 0 : contentWidth - inputs.leftTabBarWidth,
                                                 0,
                                                 inputs.leftTabBarWidth,
                                                 inputs.contentViewHeight - outputs.decorationHeightTop);
                if (!inputs.tabBarFlashing) {
                    terminalX = onLeft ? inputs.leftTabBarWidth : 0;
                    terminalWidth -= inputs.leftTabBarWidth;
                }
                break;
            }
            case kLayoutTabPositionBottom:
                outputs.tabBarFrame = CGRectMake(0, 0, contentWidth, inputs.tabBarHeight);
                if (!inputs.tabBarFlashing) {
                    outputs.decorationHeightBottom = inputs.tabBarHeight;
                }
                break;
            case kLayoutTabPositionTop:
            default: {
                if (!inputs.tabBarOnLoan && !inputs.tabBarFlashing) {
                    outputs.decorationHeightTop += inputs.tabBarHeight;
                }
                const CGFloat overlayOffset = (!inputs.tabBarOnLoan && inputs.tabBarFlashing) ?
                    inputs.tabBarHeight : 0;
                outputs.tabBarFrame = CGRectMake(0,
                                                 inputs.contentViewHeight - outputs.decorationHeightTop - overlayOffset,
                                                 contentWidth,
                                                 inputs.tabBarHeight);
                break;
            }
        }
    }

    CGRect terminalFrame = CGRectMake(terminalX,
                                      outputs.decorationHeightBottom,
                                      terminalWidth,
                                      inputs.contentViewHeight - outputs.decorationHeightTop - outputs.decorationHeightBottom);
    // Hidden, on-loan tabs already sit above the status bar. Preserve that
    // ordering during native fullscreen transitions without deducting twice.
    CGRect statusBarContainer = terminalFrame;
    if (!inputs.tabBarVisible) {
        statusBarContainer = [self tabViewFrameByShrinkingForFullScreenTabBar:terminalFrame withInputs:inputs];
    }
    if (inputs.hasStatusBar) {
        const CGFloat statusBarY = inputs.statusBarOnTop ?
            CGRectGetMaxY(statusBarContainer) - inputs.statusBarHeight : CGRectGetMinY(statusBarContainer);
        outputs.statusBarFrame = CGRectMake(CGRectGetMinX(statusBarContainer),
                                           statusBarY,
                                           CGRectGetWidth(statusBarContainer),
                                           inputs.statusBarHeight);
        if (inputs.statusBarOnTop) {
            outputs.decorationHeightTop += inputs.statusBarHeight;
        } else {
            outputs.decorationHeightBottom += inputs.statusBarHeight;
        }
        terminalFrame.origin.y = outputs.decorationHeightBottom;
        terminalFrame.size.height = inputs.contentViewHeight - outputs.decorationHeightTop - outputs.decorationHeightBottom;
    }
    outputs.tabViewFrame = [self tabViewFrameByShrinkingForFullScreenTabBar:terminalFrame withInputs:inputs];
    outputs.toolbeltFrame = [self toolbeltFrameWithInputs:inputs];
    return outputs;
}

#pragma mark - Tab View Frame Shrinking

+ (CGRect)tabViewFrameByShrinkingForFullScreenTabBar:(CGRect)frame
                                          withInputs:(iTermLayoutInputs)inputs {
    // Check if tab bar accessory overlaps content
    if (!inputs.tabBarAccessoryOverlapsContent) {
        return frame;
    }

    // Tab bar must be visible (even when on loan) for shrinking to apply.
    // This handles the case when tab bar shouldn't be visible (e.g., single tab
    // with hide-single-tab enabled) but is still on loan during a transition.
    if (!inputs.tabBarShouldBeAccessory) {
        return frame;
    }

    // Must be in fullscreen or entering fullscreen
    if (!inputs.enteringFullscreen && !inputs.inFullscreen) {
        return frame;
    }

    // Only applies to top tab bar
    if (inputs.tabPosition != kLayoutTabPositionTop) {
        return frame;
    }

    // Flashing tab bar overlaps content
    if (inputs.tabBarFlashing) {
        return frame;
    }

    // A non-loaned tab bar was already accounted for by the layout.
    if (!inputs.tabBarOnLoan) {
        return frame;
    }

    // IMPORTANT: If shouldLeaveEmptyAreaAtTop is true, the shrinking was already
    // applied via decorationHeightTop in the layout calculation. Don't double-apply.
    // This ensures the two mechanisms are mutually exclusive.
    if (inputs.shouldLeaveEmptyAreaAtTop) {
        return frame;
    }

    CGRect tabViewFrame = frame;
    tabViewFrame.size.height -= inputs.tabBarHeight;
    return tabViewFrame;
}

#pragma mark - Toolbelt Frame

+ (CGRect)toolbeltFrameWithInputs:(iTermLayoutInputs)inputs {
    if (!inputs.shouldShowToolbelt) {
        return CGRectZero;
    }

    CGFloat top = inputs.notchInset;
    CGFloat bottom = 0;

    CGRect toolbeltFrame = CGRectMake(
        inputs.contentViewWidth - inputs.toolbeltWidth,
        bottom,
        inputs.toolbeltWidth,
        inputs.contentViewHeight - top - bottom
    );

    // Shrink the toolbelt to account for the tab bar.
    // Use shouldLeaveEmptyAreaAtTop OR frame shrinking, but not both.
    // These mechanisms are mutually exclusive.
    if (inputs.shouldLeaveEmptyAreaAtTop) {
        toolbeltFrame.size.height -= inputs.tabBarHeight;
    } else {
        toolbeltFrame = [self tabViewFrameByShrinkingForFullScreenTabBar:toolbeltFrame
                                                              withInputs:inputs];
    }

    return toolbeltFrame;
}

@end
