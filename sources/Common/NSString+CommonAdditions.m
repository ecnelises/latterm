//
//  NSString+CommonAdditions.m
//  iTerm2
//
//  Created by George Nachman on 2/24/22.
//

#import "NSString+CommonAdditions.h"

static NSRegularExpression * _Nullable iTermCachedRegularExpression(NSString * _Nullable pattern,
                                                                    NSRegularExpressionOptions options,
                                                                    NSError * _Nullable * _Nullable error) {
    if (!pattern || pattern.length == 0) {
        return nil;
    }
    static NSCache<NSString *, NSRegularExpression *> *cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [[NSCache alloc] init];
        cache.countLimit = 256;
    });
    NSString *cacheKey = options == 0
        ? pattern
        : [NSString stringWithFormat:@"%lu:%@", (unsigned long)options, pattern];
    NSRegularExpression *cached = [cache objectForKey:cacheKey];
    if (cached) {
        return cached;
    }
    NSError *compileError = nil;
    NSRegularExpression *compiled = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                              options:options
                                                                                error:&compileError];
    if (compiled) {
        [cache setObject:compiled forKey:cacheKey];
    } else if (error) {
        *error = compileError;
    }
    return compiled;
}

static NSArray<NSString *> *iTermCaptureArrayFromMatch(NSString *subject, NSTextCheckingResult *match) {
    const NSUInteger count = match.numberOfRanges;
    NSMutableArray<NSString *> *captures = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger idx = 0; idx < count; idx++) {
        const NSRange range = [match rangeAtIndex:idx];
        if (range.location == NSNotFound || range.length == 0) {
            [captures addObject:@""];
        } else {
            [captures addObject:[subject substringWithRange:range]];
        }
    }
    return captures;
}

@implementation NSString (CommonAdditions)

- (NSString *)stringByRemovingEnclosingBrackets {
    if (self.length < 2) {
        return self;
    }
    NSString *trimmed = [self stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSArray *pairs = @[ @[ @"(", @")" ],
                        @[ @"<", @">" ],
                        @[ @"[", @"]" ],
                        @[ @"{", @"}", ],
                        @[ @"\'", @"\'" ],
                        @[ @"\"", @"\"" ] ];
    for (NSArray *pair in pairs) {
        if ([trimmed hasPrefix:pair[0]] && [trimmed hasSuffix:pair[1]]) {
            return [[self substringWithRange:NSMakeRange(1, self.length - 2)] stringByRemovingEnclosingBrackets];
        }
    }
    return self;
}

- (NSString *)stringByDroppingLastCharacters:(NSInteger)count {
    if (count >= self.length) {
        return @"";
    }
    if (count <= 0) {
        return self;
    }
    return [self substringWithRange:NSMakeRange(0, self.length - count)];
}

#pragma mark - Regular Expressions

- (BOOL)isMatchedByRegex:(NSString *)regex {
    return [self rangeOfRegex:regex].location != NSNotFound;
}

- (NSRange)rangeOfRegex:(NSString *)regex {
    return [self rangeOfRegex:regex
                      options:0
                      inRange:NSMakeRange(0, self.length)
                      capture:0
                        error:nil];
}

- (NSRange)rangeOfRegex:(NSString *)regex
                options:(NSRegularExpressionOptions)options
                inRange:(NSRange)range
                capture:(NSInteger)capture
                  error:(NSError **)error {
    if (!regex) {
        return NSMakeRange(NSNotFound, 0);
    }
    if (range.location == NSNotFound || NSMaxRange(range) > self.length || capture < 0) {
        return NSMakeRange(NSNotFound, 0);
    }
    if (regex.length == 0) {
        return capture == 0 ? NSMakeRange(range.location, 0) : NSMakeRange(NSNotFound, 0);
    }
    NSRegularExpression *compiled = iTermCachedRegularExpression(regex, options, error);
    if (!compiled) {
        return NSMakeRange(NSNotFound, 0);
    }
    NSTextCheckingResult *match = [compiled firstMatchInString:self options:0 range:range];
    if (!match || (NSUInteger)capture >= match.numberOfRanges) {
        return NSMakeRange(NSNotFound, 0);
    }
    return [match rangeAtIndex:(NSUInteger)capture];
}

- (NSString *)stringByMatching:(NSString *)regex {
    return [self stringByMatching:regex capture:0];
}

- (NSString *)stringByMatching:(NSString *)regex capture:(NSInteger)capture {
    const NSRange matchedRange = [self rangeOfRegex:regex
                                            options:0
                                            inRange:NSMakeRange(0, self.length)
                                            capture:capture
                                              error:nil];
    if (matchedRange.location == NSNotFound) {
        return nil;
    }
    return [self substringWithRange:matchedRange];
}

- (NSString *)stringByReplacingOccurrencesOfRegex:(NSString *)regex
                                       withString:(NSString *)replacement {
    if (!regex || regex.length == 0) {
        return self;
    }
    NSRegularExpression *compiled = iTermCachedRegularExpression(regex, 0, nil);
    if (!compiled) {
        return self;
    }
    return [compiled stringByReplacingMatchesInString:self
                                              options:0
                                                range:NSMakeRange(0, self.length)
                                         withTemplate:replacement ?: @""];
}

- (NSArray<NSString *> *)componentsSeparatedByRegex:(NSString *)regex {
    if (self.length == 0) {
        return @[];
    }
    if (!regex || regex.length == 0) {
        return @[ [self copy] ];
    }
    NSRegularExpression *compiled = iTermCachedRegularExpression(regex, 0, nil);
    if (!compiled) {
        return @[ [self copy] ];
    }
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    __block NSUInteger lastLocation = 0;
    [compiled enumerateMatchesInString:self
                               options:0
                                 range:NSMakeRange(0, self.length)
                            usingBlock:^(NSTextCheckingResult * _Nullable match, NSMatchingFlags flags, BOOL * _Nonnull stop) {
        if (!match) {
            return;
        }
        const NSRange matchRange = match.range;
        if (matchRange.length == 0 && matchRange.location == lastLocation) {
            return;
        }
        const NSRange segmentRange = NSMakeRange(lastLocation, matchRange.location - lastLocation);
        [parts addObject:[self substringWithRange:segmentRange]];
        lastLocation = NSMaxRange(matchRange);
    }];
    if (lastLocation < self.length) {
        [parts addObject:[self substringFromIndex:lastLocation]];
    }
    while (parts.count > 0 && parts.lastObject.length == 0) {
        [parts removeLastObject];
    }
    return parts;
}

- (NSArray<NSString *> *)captureComponentsMatchedByRegex:(NSString *)regex {
    return [self captureComponentsMatchedByRegex:regex
                                         options:0
                                           range:NSMakeRange(0, self.length)
                                           error:nil] ?: @[];
}

- (NSArray<NSString *> *)captureComponentsMatchedByRegex:(NSString *)regex
                                                 options:(NSRegularExpressionOptions)options
                                                   range:(NSRange)range
                                                   error:(NSError **)error {
    if (!regex || range.location == NSNotFound || NSMaxRange(range) > self.length) {
        return nil;
    }
    if (regex.length == 0) {
        return @[ @"" ];
    }
    NSRegularExpression *compiled = iTermCachedRegularExpression(regex, options, error);
    if (!compiled) {
        return nil;
    }
    NSTextCheckingResult *match = [compiled firstMatchInString:self options:0 range:range];
    if (!match) {
        return @[];
    }
    return iTermCaptureArrayFromMatch(self, match);
}

- (NSArray<NSArray<NSString *> *> *)arrayOfCaptureComponentsMatchedByRegex:(NSString *)regex {
    if (!regex || regex.length == 0) {
        return @[];
    }
    NSRegularExpression *compiled = iTermCachedRegularExpression(regex, 0, nil);
    if (!compiled) {
        return @[];
    }
    NSMutableArray<NSArray<NSString *> *> *results = [NSMutableArray array];
    [compiled enumerateMatchesInString:self
                               options:0
                                 range:NSMakeRange(0, self.length)
                            usingBlock:^(NSTextCheckingResult * _Nullable match, NSMatchingFlags flags, BOOL * _Nonnull stop) {
        if (match) {
            [results addObject:iTermCaptureArrayFromMatch(self, match)];
        }
    }];
    return results;
}

@end
