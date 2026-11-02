#import "iTermURLActionFactory.h"

NS_ASSUME_NONNULL_BEGIN
@interface iTermURLActionFactory (Testing)
+ (BOOL)urlHasOpenableScheme:(NSURL *)url;
+ (void)setURLOpenabilityOverrideForTesting:(nullable BOOL (^)(NSURL *url))block;
@end
NS_ASSUME_NONNULL_END
