//
//  iTermFunctionCallSuggester.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/20/18.
//

#import "iTermFunctionCallSuggester.h"

#import "DebugLogging.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermSwiftyStringParser.h"
#import "NSArray+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSObject+iTerm.h"

@implementation iTermFunctionCallSuggester {
@protected
    NSDictionary<NSString *, NSArray<NSString *> *> *_functionSignatures;
    NSSet<NSString *> *(^_pathSource)(NSString *prefix);
    NSString *_prefix;
}

- (instancetype)initWithFunctionSignatures:(NSDictionary<NSString *, NSArray<NSString *> *> *)functionSignatures
                                pathSource:(NSSet<NSString *> *(^)(NSString *prefix))pathSource {
    self = [super init];
    if (self) {
        _functionSignatures = [functionSignatures copy];
        _pathSource = [pathSource copy];
    }
    return self;
}

- (NSString *)grammarStart {
    return @"callsequence";
}

- (NSArray<NSString *> *)suggestionsForString:(NSString *)prefix {
    if ([prefix hasSuffix:@" "]) {
        return @[];
    }
    if (prefix.length == 0) {
        return [self pathsAndFunctionSuggestionsWithPrefix:@"" legalPaths:[_pathSource(@"") allObjects]];
    }
    _prefix = prefix;
    __weak __typeof(self) weakSelf = self;
    id result = [iTermNativeExpressionCore parseForSuggestions:prefix
                                                         start:self.grammarStart
                                                   callBuilder:^id _Nonnull(NSString * _Nonnull funcName, NSDictionary<NSString *, id> * _Nonnull arglist) {
        return [weakSelf callWithName:funcName arglist:arglist] ?: @[];
    }];
    return [self parsedResult:result forString:prefix];
}

- (NSArray<NSString *> *)parsedResult:(id)result forString:(NSString *)prefix {
    return [[NSArray castFrom:result] mapWithBlock:^id(NSString *s) {
        return [prefix stringByAppendingString:s];
    }] ?: @[];
}

#pragma mark - Private

- (NSArray<NSString *> *)usedParameterNamesInPartialArgList:(NSArray *)partialArgList {
    return [partialArgList mapWithBlock:^id(id object) {
        if ([object isEqual:@","]) {
            return nil;
        } else {
            NSDictionary *dict = object;
            return [dict[@"identifier"] stringByAppendingString:@":"];
        }
    }];
}

- (NSArray<NSString *> *)argumentNamesForFunction:(NSString *)function {
    return _functionSignatures[function];
}

#pragma mark - Suggestion Generation

- (NSArray<NSString *> *)suggestionsForFunctionName:(NSString *)prefix {
    NSArray<NSString *> *registeredFunctions = _functionSignatures.allKeys;
    return [[registeredFunctions filteredArrayUsingBlock:^BOOL(NSString *anObject) {
        return [anObject hasPrefix:prefix] || prefix.length == 0;
    }] mapWithBlock:^id(NSString *s) {
        NSString *firstArgName = [[self argumentNamesForFunction:s].firstObject stringByAppendingString:@":"] ?: @")";
        return [NSString stringWithFormat:@"%@(%@",
                [s substringFromIndex:prefix.length],
                firstArgName];
    }];
}

// partialArgList is an array alternating between arg-dicts and @",".
// an arg-dict has an identifier, maybe a colon, and maybe an expression.
- (NSArray<NSString *> *)suggestedNextArgumentForExistingArgs:(NSArray *)partialArgList
                                                     function:(NSString *)function {
    if (partialArgList == nil) {
        // No open paren yet
        return [self suggestionsForFunctionName:function];
    }

    NSArray<NSString *> *usedParameterNames = [self usedParameterNamesInPartialArgList:partialArgList];

    id lastArg = partialArgList.lastObject;
    NSString *prefix;
    if (![lastArg isEqual:@","]) {
        NSDictionary *argDict = lastArg;
        if (argDict[@"colon"]) {
            NSString *nextArgumentName = [[self argumentNamesForFunction:function] objectPassingTest:^BOOL(NSString *element, NSUInteger index, BOOL *stop) {
                return ![usedParameterNames containsObject:[element stringByAppendingString:@":"]];
            }];
            NSArray *suggestions = [self suggestedExpressions:argDict[@"expression"]
                                             nextArgumentName:nextArgumentName
                                             valuesMustBeArgs:YES];
            return suggestions;
        }
        prefix = argDict[@"identifier"] ?: @"";
    } else {
        prefix = @"";
    }

    if (lastArg && ![lastArg isEqual:@","]) {
        usedParameterNames = [usedParameterNames arrayByRemovingLastObject];
    }
    return [self suggestedParameterNamesForFunction:function
                                          excluding:usedParameterNames
                                             prefix:prefix];
}

- (NSArray<NSString *> *)suggestedExpressions:(NSDictionary *)expression
                             nextArgumentName:(NSString *)nextArgumentName
                             valuesMustBeArgs:(BOOL)valuesMustBeArgs {
    if (expression == nil || expression[@"literal"] || expression[@"terminated"]) {
        return @[];
    } else if (expression[@"operator_pending"]) {
        NSArray<NSString *> *legalPaths = [_pathSource(@"") allObjects];
        return [self pathsAndFunctionSuggestionsWithPrefix:@"" legalPaths:legalPaths];
    } else if (expression[@"call"]) {
        return expression[@"call"];
    } else if (expression[@"truncated_interpolation"]) {
        iTermExpressionSuggester *inner = [[iTermExpressionSuggester alloc] initWithFunctionSignatures:_functionSignatures
                                                                                            pathSource:_pathSource];
        return [inner suggestionsForString:expression[@"truncated_interpolation"]];
    } else {
        NSArray<NSString *> *legalPaths = [_pathSource(expression[@"path"]) allObjects];
        const BOOL insideTruncatedArrayLiteral = [expression[@"inside-truncated-array-literal"] boolValue];
        if (valuesMustBeArgs && !insideTruncatedArrayLiteral) {
            if (nextArgumentName == nil) {
                legalPaths = [legalPaths mapWithBlock:^id(NSString *anObject) {
                    if ([anObject hasSuffix:@"."]) {
                        return anObject;
                    }
                    return [anObject stringByAppendingString:@")"];
                }];
            } else {
                legalPaths = [legalPaths mapWithBlock:^id(NSString *anObject) {
                    return [anObject stringByAppendingFormat:@", %@:", nextArgumentName];
                }];
            }
        }
        NSArray<NSString *> *suggestions = [self pathsAndFunctionSuggestionsWithPrefix:expression[@"path"]
                                                                            legalPaths:legalPaths];
        return suggestions;
    }
}

- (NSArray<NSString *> *)pathsAndFunctionSuggestionsWithPrefix:(NSString *)prefix
                                                    legalPaths:(NSArray<NSString *> *)legalPaths {
    NSArray<NSString *> *functionNames = _functionSignatures.allKeys;
    functionNames = [functionNames mapWithBlock:^id(NSString *anObject) {
        NSString *firstArgName = [[self argumentNamesForFunction:anObject].firstObject stringByAppendingString:@":"] ?: @")";
        return [anObject stringByAppendingFormat:@"(%@", firstArgName];
    }];

    NSArray<NSString *> *options = [legalPaths arrayByAddingObjectsFromArray:functionNames];
    return [[options filteredArrayUsingBlock:^BOOL(NSString *anObject) {
        return prefix.length == 0 || [anObject hasPrefix:prefix];
    }] mapWithBlock:^id(NSString *s) {
        return [s substringFromIndex:prefix.length];
    }];
}

- (NSArray<NSString *> *)suggestedParameterNamesForFunction:(NSString *)function
                                                  excluding:(NSArray<NSString *> *)exclusions
                                                     prefix:(NSString *)prefix {
    NSArray<NSString *> *legalNames = [[self argumentNamesForFunction:function] mapWithBlock:^id(NSString *anObject) {
        return [anObject stringByAppendingString:@":"];
    }];
    if (!legalNames) {
        return @[];
    }
    NSArray *suggestions = [[legalNames filteredArrayUsingBlock:^BOOL(NSString *anObject) {
        return ![exclusions containsObject:anObject] && (prefix.length == 0 || [anObject hasPrefix:prefix]);
    }] mapWithBlock:^id(NSString *s) {
        return [s substringFromIndex:prefix.length];
    }];
    return suggestions;
}

- (id)callWithName:(NSString *)function arglist:(id)maybeArglistDict {
    NSDictionary *arglist = [NSDictionary castFrom:maybeArglistDict];
    if (arglist[@"partial-arglist"]) {
        return [self suggestedNextArgumentForExistingArgs:arglist[@"args"]
                                                 function:function];
    }
    return @[];
}

@end

@implementation iTermSwiftyStringSuggester

- (NSString *)grammarStart {
    return @"expression";
}

- (NSArray<NSString *> *)suggestionsForString:(NSString *)prefix {
    if ([prefix hasSuffix:@" "]) {
        return @[];
    }
    _prefix = prefix;

    iTermSwiftyStringParser *parser = [[iTermSwiftyStringParser alloc] initWithString:prefix];
    parser.tolerateTruncation = YES;
    NSInteger index = [parser enumerateSwiftySubstringsWithBlock:nil];
    if (index > prefix.length ||
        index == NSNotFound ||
        !parser.wasTruncated ||
        parser.wasTruncatedInLiteral) {
        return @[];
    }
    NSString *truncatedExpression = [prefix substringFromIndex:index];
    NSArray<NSString *> *undecoratedSuggestions = [super suggestionsForString:truncatedExpression];
    NSArray<NSString *> *allSuggestions = [undecoratedSuggestions mapWithBlock:^id(NSString *tail) {
        return [prefix stringByAppendingString:tail];
    }];
    NSArray<NSString *> *suggestionsUpToFirstPeriod = [allSuggestions mapWithBlock:^id(NSString *string) {
        NSInteger remaining = string.length;
        remaining -= prefix.length;
        if (remaining < 0) {
            return nil;
        }
        NSInteger index = [string rangeOfString:@"." options:0 range:NSMakeRange(prefix.length, remaining)].location;
        if (index == NSNotFound) {
            return string;
        } else {
            return [string substringToIndex:index];
        }
    }];
    return [[suggestionsUpToFirstPeriod sortedArrayUsingSelector:@selector(compare:)] reduceWithFirstValue:@[] block:^id(NSArray *uniqueValues, NSString *string) {
        if (uniqueValues.count < 50 &&
            ![NSObject object:uniqueValues.lastObject isEqualToObject:string]) {
            return [uniqueValues arrayByAddingObject:string];
        } else {
            return uniqueValues;
        }
    }];
}

- (NSArray<NSString *> *)parsedResult:(id)result forString:(NSString *)prefix {
    NSArray<NSString *> *suggestions = [self suggestedExpressions:[NSDictionary castFrom:result]
                                                 nextArgumentName:nil
                                                 valuesMustBeArgs:NO];
    return suggestions;
}

@end


@implementation iTermExpressionSuggester

- (NSString *)grammarStart {
    return @"expression";
}

- (NSArray<NSString *> *)parsedResult:(id)result forString:(NSString *)prefix {
    NSArray<NSString *> *suggestions = [self suggestedExpressions:[NSDictionary castFrom:result]
                                                 nextArgumentName:nil
                                                 valuesMustBeArgs:NO];
    return [suggestions mapWithBlock:^id _Nullable(NSString *suffix) {
        return [prefix stringByAppendingString:suffix];
    }];
}

@end
