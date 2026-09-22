//
//  iTermPreferencesSearchEngineResultsWindowController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/28/19.
//

#import "iTermPreferencesSearchEngineResultsWindowController.h"

@interface iTermPreferencesSearchEngineResultsWindowController ()<NSTableViewDelegate, NSTableViewDataSource>

@end

@implementation iTermPreferencesSearchEngineResultsWindowController {
    IBOutlet NSTableView *_tableView;
    IBOutlet NSVisualEffectView *_visualEffectView;
    BOOL _updatingDocuments;
}

- (void)windowDidLoad {
    _visualEffectView.material = NSVisualEffectMaterialContentBackground;
    self.window.opaque = NO;
    self.window.backgroundColor = [NSColor clearColor];
    _tableView.rowHeight = 52;
    _tableView.intercellSpacing = NSMakeSize(0, 2);
    _tableView.accessibilityLabel = NSLocalizedString(@"Settings search results", @"Settings search");
    _tableView.accessibilityIdentifier = @"SettingsSearchResults";
    [self updateFrameAndAlpha];
}

- (void)setDocuments:(NSArray<iTermPreferencesSearchDocument *> *)documents {
    (void)self.window;
    _updatingDocuments = YES;
    [_tableView deselectAll:nil];
    _documents = [documents copy];
    [_tableView reloadData];
    _updatingDocuments = NO;
    [self updateFrameAndAlpha];
    [_tableView scrollRowToVisible:0];
}

- (CGFloat)preferredWindowHeight {
    NSInteger rows = MAX(1, _documents.count);
    const NSInteger MAX_ROWS = 8;
    const NSInteger rowsToShow = MIN(rows, MAX_ROWS);
    CGFloat desiredTableViewHeight = (_tableView.rowHeight + _tableView.intercellSpacing.height) * rowsToShow;
    NSScrollView *scrollView = _tableView.enclosingScrollView;
    const CGFloat desiredContentHeight = [NSScrollView frameSizeForContentSize:NSMakeSize(100, desiredTableViewHeight)
                                                       horizontalScrollerClass:nil
                                                         verticalScrollerClass:scrollView.verticalScroller.class
                                                                    borderType:scrollView.borderType
                                                                   controlSize:NSControlSizeRegular
                                                                 scrollerStyle:scrollView.scrollerStyle].height;
    return [NSPanel frameRectForContentRect:NSMakeRect(0, 0, 100, desiredContentHeight)
                                 styleMask:self.window.styleMask].size.height;
}

- (void)positionRelativeToSearchRect:(NSRect)searchRect visibleFrame:(NSRect)visibleFrame {
    const NSRect available = NSInsetRect(visibleFrame, 12, 12);
    const CGFloat desiredHeight = [self preferredWindowHeight];
    const CGFloat belowTop = MIN(NSMaxY(available), MAX(NSMinY(available), NSMinY(searchRect) - 6));
    const CGFloat aboveBottom = MIN(NSMaxY(available), MAX(NSMinY(available), NSMaxY(searchRect) + 6));
    const CGFloat roomBelow = belowTop - NSMinY(available);
    const CGFloat roomAbove = NSMaxY(available) - aboveBottom;
    const CGFloat minimumUsefulHeight = MIN(desiredHeight, 2 * (_tableView.rowHeight + _tableView.intercellSpacing.height));
    const BOOL below = roomBelow >= minimumUsefulHeight || roomBelow >= roomAbove;
    const CGFloat height = MIN(desiredHeight, below ? roomBelow : roomAbove);
    const CGFloat width = MIN(560, NSWidth(available));
    const CGFloat x = MAX(NSMinX(available), MIN(NSMinX(searchRect), NSMaxX(available) - width));
    const CGFloat y = below ? belowTop - height : aboveBottom;
    [self.window setFrame:NSMakeRect(x, y, width, height) display:YES];
}

- (void)updateFrameAndAlpha {
    NSRect frame = self.window.frame;
    const CGFloat desiredHeight = [self preferredWindowHeight];
    const BOOL wasVisible = (self.window.alphaValue == 1);
    if (frame.size.height != desiredHeight) {
        CGFloat changeInHeight = desiredHeight - frame.size.height;
        frame.size.height = desiredHeight;
        frame.origin.y -= changeInHeight;

        [self.window setFrame:frame display:YES animate:NO];
    }
    if (!wasVisible) {
        self.window.alphaValue = 1;
    }
}

- (iTermPreferencesSearchDocument *)selectedDocument {
    NSInteger row = _tableView.selectedRow;
    if (row < 0 || row >= self.documents.count) {
        return  nil;
    } else {
        return self.documents[row];
    }
}
#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return MAX(1, _documents.count);
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    NSTableCellView *cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, tableColumn.width, 52)];
    const BOOL empty = self.documents.count == 0;
    iTermPreferencesSearchDocument *document = empty ? nil : self.documents[row];
    NSString *title = empty ? NSLocalizedString(@"No matching settings", @"Settings search empty state") : document.displayName;
    NSString *detail = empty ? NSLocalizedString(@"Try a shorter word or a different setting name.", @"Settings search empty state") :
        [[document.pathComponents arrayByAddingObject:document.scope] componentsJoinedByString:@" › "];
    NSTextField *label = [NSTextField labelWithString:title];
    label.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    label.frame = NSMakeRect(12, 28, tableColumn.width - 24, 18);
    label.autoresizingMask = NSViewWidthSizable;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    [cell addSubview:label];
    cell.textField = label;
    NSTextField *path = [NSTextField labelWithString:detail];
    path.font = [NSFont systemFontOfSize:11];
    path.textColor = NSColor.secondaryLabelColor;
    path.frame = NSMakeRect(12, 8, tableColumn.width - 24, 16);
    path.autoresizingMask = NSViewWidthSizable;
    path.lineBreakMode = NSLineBreakByTruncatingTail;
    [cell addSubview:path];
    cell.toolTip = [NSString stringWithFormat:@"%@\n%@", title, detail];
    cell.accessibilityLabel = [NSString stringWithFormat:@"%@, %@", title, detail];
    return cell;
}

#pragma mark - NSTableViewDelegate

- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row {
    return row >= 0 && row < self.documents.count;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    iTermPreferencesSearchDocument *document = self.selectedDocument;
    if (!_updatingDocuments && document) {
        [self.delegate preferencesSearchEngineResultsDidSelectDocument:document];
    }
}

#pragma mark - Actions

- (IBAction)action:(id)sender {
    NSInteger row = _tableView.selectedRow;
    if (row >= 0 && row < self.documents.count) {
        [self.delegate preferencesSearchEngineResultsDidActivateDocument:self.documents[row]];
    }
}

- (void)moveDown:(id)sender {
    NSInteger row = _tableView.selectedRow + 1;
    if (row < _documents.count) {
        [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
        [_tableView scrollRowToVisible:row];
    }
}

- (void)moveUp:(id)sender {
    NSInteger row = _tableView.selectedRow - 1;
    if (row >= 0) {
        [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
        [_tableView scrollRowToVisible:row];
    }
}

- (void)insertNewline:(nullable id)sender {
    if (!self.selectedDocument && self.documents.count) {
        [self moveDown:sender];
    }
    [self action:sender];
}

@end
