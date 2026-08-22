// Implements the Autocomplete UI. It grabs the word behind the cursor and opens a popup window with
// likely suffixes. Selecting one appends it, and you can search the list Quicksilver-style.

#import <Cocoa/Cocoa.h>
#import "iTermPopupWindowController.h"
#import "PTYSession.h"
#import "LineBuffer.h"

@interface AutocompleteView : iTermPopupWindowController

- (void)onOpen;
- (void)refresh;
- (void)onClose;
- (void)rowSelected:(id)sender;
- (void)more;
- (void)less;

@end
