//
//  iTermURLActionFactory.h
//  iTerm2
//
//  Created by George Nachman on 2/26/17.
//
//

#import <Foundation/Foundation.h>

#import "VT100GridTypes.h"
#import "iTermCancelable.h"

@class iTermTextExtractor;
@protocol iTermObject;
@class iTermSemanticHistoryController;
@class iTermVariableScope;
@class SCPPath;
@class URLAction;
@protocol VT100RemoteHostReading;

NS_ASSUME_NONNULL_BEGIN

@interface iTermURLActionFactory : NSObject<iTermCancelable>

+ (instancetype)urlActionAtCoord:(VT100GridCoord)coord
             respectHardNewlines:(BOOL)respectHardNewlines
                       alternate:(BOOL)alternate
                workingDirectory:(NSString * _Nullable)workingDirectory
                           scope:(iTermVariableScope * _Nullable)scope
                           owner:(id<iTermObject> _Nullable)owner
                      remoteHost:(id<VT100RemoteHostReading> _Nullable)remoteHost
                       selectors:(NSDictionary<NSNumber *, NSString *> *)selectors
                           rules:(NSArray *)rules
                       extractor:(iTermTextExtractor *)extractor
       semanticHistoryController:(iTermSemanticHistoryController *)semanticHistoryController
                     pathFactory:(SCPPath * _Nullable (^)(NSString *, int))pathFactory
                      completion:(void (^)(URLAction * _Nullable))completion;

// Synchronously returns the openable URL at `coord` (with hard newlines stripped
// from wrapped URLs when respectHardNewlines is NO), or nil if the text there does
// not carry a URL scheme the OS can open. This is the URL-detection portion of the
// ⌘-click machinery without the asynchronous filesystem/Semantic History probing, so
// it is suitable for populating a context menu synchronously.
+ (NSURL * _Nullable)openableURLAtCoord:(VT100GridCoord)coord
                    respectHardNewlines:(BOOL)respectHardNewlines
                              extractor:(iTermTextExtractor *)extractor;

// Resolve selected text using the same default scheme as Command-click.
+ (NSURL * _Nullable)urlForUserSuppliedString:(NSString *)string guessingScheme:(BOOL)guessScheme;

@end

NS_ASSUME_NONNULL_END
