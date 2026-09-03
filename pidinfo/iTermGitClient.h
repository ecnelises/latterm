//
//  iTermGitClient.h
//  pidinfo
//
//  Created by George Nachman on 1/11/21.
//

#import <Foundation/Foundation.h>

#import "iTermGitState.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermGitClient : NSObject

@property (nonatomic, readonly, copy) NSString *path;
@property (nonatomic, readonly, getter=isValid) BOOL valid;

- (instancetype)initWithRepoPath:(NSString *)path NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (NSArray<NSString *> * _Nullable)recentBranchesWithLimit:(NSInteger)limit;

@end

@interface iTermGitState (GitClient)

+ (instancetype _Nullable)gitStateForRepoAtPath:(NSString *)path;

+ (instancetype _Nullable)gitStateForRepoAtPath:(NSString *)path
                                includeDiffStats:(BOOL)includeDiffStats;

+ (instancetype _Nullable)gitStateForRepoAtPath:(NSString *)path
                                         gitBase:(NSString * _Nullable)gitBase
                                includeDiffStats:(BOOL)includeDiffStats;

@end

NS_ASSUME_NONNULL_END
