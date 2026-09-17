//
//  iTermKeyMappingViewController.h
//  iTerm
//
//  Created by George Nachman on 4/7/14.
//
//

#import <Cocoa/Cocoa.h>

#import "iTermKeystroke.h"

@class iTermKeyBindingAction;
@class iTermKeyMappingViewController;
@class iTermPreferencesBaseViewController;

@protocol iTermKeyMappingViewControllerDelegate <NSObject>

- (NSDictionary *)keyMappingDictionary:(iTermKeyMappingViewController *)viewController;

- (NSArray<iTermKeystroke *> *)keyMappingSortedKeystrokes:(iTermKeyMappingViewController *)viewController;

- (void)keyMapping:(iTermKeyMappingViewController *)viewController
     didChangeItem:(iTermKeystroke *)keystroke
           atIndex:(NSInteger)index
          toAction:(iTermKeyBindingAction *)action
        isAddition:(BOOL)addition;

- (void)keyMapping:(iTermKeyMappingViewController *)viewController
  removeKeystrokes:(NSSet<iTermKeystroke *> *)keyCombos;

- (NSArray *)keyMappingPresetNames:(iTermKeyMappingViewController *)viewController;

- (void)keyMapping:(iTermKeyMappingViewController *)viewController
    loadPresetsNamed:(NSString *)presetName;

- (BOOL)keyMapping:(iTermKeyMappingViewController *)viewController shouldImportKeystrokes:(NSSet<iTermKeystroke *> *)keys;

@end

@interface iTermKeyMappingViewController : NSViewController <
    NSTableViewDelegate,
    NSTableViewDataSource>

@property(nonatomic, weak) IBOutlet id<iTermKeyMappingViewControllerDelegate> delegate;
@property(nonatomic, strong) IBOutlet NSView *placeholderView;

- (void)addViewsToSearchIndex:(iTermPreferencesBaseViewController *)vc;
- (NSNumber *)removeBeforeLoading:(NSString *)thing;
- (void)reloadData;

@end
