//
//  iTermVersionComparator.h
//  iTerm2
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Compares dotted versions, including prerelease suffixes such as "3.7beta1".
@interface iTermVersionComparator : NSObject

+ (NSComparisonResult)compareVersion:(NSString *)version
                           toVersion:(NSString *)otherVersion;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
