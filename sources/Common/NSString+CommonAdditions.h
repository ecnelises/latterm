//
//  NSString+CommonAdditions.h
//  iTerm2
//
//  Created by George Nachman on 2/24/22.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSString (CommonAdditions)

- (NSString *)stringByRemovingEnclosingBrackets;
- (NSString *)stringByDroppingLastCharacters:(NSInteger)count;

#pragma mark - Regular Expressions (Cached NSRegularExpression)

- (BOOL)isMatchedByRegex:(nullable NSString *)regex;
- (NSRange)rangeOfRegex:(nullable NSString *)regex;
- (NSRange)rangeOfRegex:(nullable NSString *)regex
                options:(NSRegularExpressionOptions)options
                inRange:(NSRange)range
                capture:(NSInteger)capture
                  error:(NSError * _Nullable * _Nullable)error;

- (nullable NSString *)stringByMatching:(nullable NSString *)regex;
- (nullable NSString *)stringByMatching:(nullable NSString *)regex capture:(NSInteger)capture;

- (NSString *)stringByReplacingOccurrencesOfRegex:(nullable NSString *)regex
                                       withString:(nullable NSString *)replacement;

- (NSArray<NSString *> *)componentsSeparatedByRegex:(nullable NSString *)regex;

- (NSArray<NSString *> *)captureComponentsMatchedByRegex:(nullable NSString *)regex;
- (nullable NSArray<NSString *> *)captureComponentsMatchedByRegex:(nullable NSString *)regex
                                                          options:(NSRegularExpressionOptions)options
                                                            range:(NSRange)range
                                                            error:(NSError * _Nullable * _Nullable)error;

- (NSArray<NSArray<NSString *> *> *)arrayOfCaptureComponentsMatchedByRegex:(nullable NSString *)regex;

@end

NS_ASSUME_NONNULL_END
