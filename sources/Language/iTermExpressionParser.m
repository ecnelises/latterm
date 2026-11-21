//
//  iTermExpressionParser.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/20/18.
//

#import "iTermExpressionParser.h"
#import "iTermExpressionParser+Private.h"

#import "iTerm2SharedARC-Swift.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermParsedExpression+Tests.h"
#import "iTermScriptFunctionCall+Private.h"
#import "iTermScriptFunctionCall.h"
#import "iTermSwiftyStringParser.h"
#import "iTermVariableReference.h"
#import "iTermVariableScope.h"
#import "NSArray+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSStringITerm.h"

@implementation iTermFunctionArgument
@end

@implementation iTermExpressionParser {
    NSString *_start;
    iTermVariableScope *_scope;
}

+ (NSString *)signatureForFunctionCallInvocation:(NSString *)invocation
                                           error:(out NSError *__autoreleasing *)error {
    iTermVariableRecordingScope *permissiveScope = [[iTermVariableRecordingScope alloc] initWithScope:[[iTermVariableScope alloc] init]];
    permissiveScope.neverReturnNil = YES;
    iTermParsedExpression *expression = [[iTermExpressionParser callParser] parse:invocation
                                                                            scope:permissiveScope];
    switch (expression.expressionType) {
        case iTermParsedExpressionTypeArrayLookup:
        case iTermParsedExpressionTypeVariableReference:
        case iTermParsedExpressionTypeSubexpression:
        case iTermParsedExpressionTypeIndirectValue:
        case iTermParsedExpressionTypeReference:
        case iTermParsedExpressionTypeString:
        case iTermParsedExpressionTypeArrayOfExpressions:
        case iTermParsedExpressionTypeArrayOfValues:
            if (error) {
                *error = [NSError errorWithDomain:@"com.iterm2.call"
                                             code:3
                                         userInfo:@{ NSLocalizedDescriptionKey: @"Expected function call, not a value" }];
            }
            return nil;

        case iTermParsedExpressionTypeError:
            if (error) {
                *error = expression.error;
            }
            return nil;

        case iTermParsedExpressionTypeFunctionCall:
            return expression.functionCall.signature;

        case iTermParsedExpressionTypeFunctionCalls:
            if (error) {
                *error = [NSError errorWithDomain:@"com.iterm2.call"
                                             code:3
                                         userInfo:@{ NSLocalizedDescriptionKey: @"Expected single function call" }];
            }
            return nil;

        case iTermParsedExpressionTypeNil:
            if (error) {
                *error = [NSError errorWithDomain:@"com.iterm2.call"
                                             code:3
                                         userInfo:@{ NSLocalizedDescriptionKey: @"Expected function call, not nil" }];
            }
            return nil;
        case iTermParsedExpressionTypeInterpolatedString:
            if (error) {
                *error = [NSError errorWithDomain:@"com.iterm2.call"
                                             code:3
                                         userInfo:@{ NSLocalizedDescriptionKey: @"Expected function call, not an interpolated string" }];
            }
            return nil;
    }
    ITAssertWithMessage(NO, @"Unexpected expression type");
    return nil;
}

+ (instancetype)expressionParser {
    static iTermExpressionParser *sCachedInstance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sCachedInstance = [[iTermExpressionParser alloc] initWithStart:@"expression"];
    });
    return sCachedInstance;
}

+ (instancetype)callParser {
    static iTermExpressionParser *sCachedInstance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sCachedInstance = [[iTermExpressionParser alloc] initWithStart:@"callsequence"];
    });
    return sCachedInstance;
}

- (instancetype)initWithStart:(NSString *)start {
    self = [super init];
    if (self) {
        _start = [start copy];
    }
    return self;
}

- (iTermParsedExpression *)callSequenceWithCalls:(NSArray<iTermScriptFunctionCall *> *)calls {
    return [[iTermParsedExpression alloc] initWithFunctionCalls:calls];
}

- (iTermParsedExpression *)buildFunctionCallParsedExpressionWithFqName:(NSString *)fqName
                                                                  args:(NSArray<iTermFunctionArgument *> *)argsArray {
    NSString *name;
    NSString *namespace;
    iTermFunctionCallSplitFullyQualifiedName(fqName, &namespace, &name);
    iTermScriptFunctionCall *call = [[iTermScriptFunctionCall alloc] init];
    call.name = name;
    call.namespace = namespace;
    for (iTermFunctionArgument *arg in argsArray) {
        if (arg.expression.expressionType == iTermParsedExpressionTypeError) {
            return [[iTermParsedExpression alloc] initWithError:arg.expression.error];
        }
        [call addParameterWithName:arg.name
                  parsedExpression:arg.expression];
    }
    return [[iTermParsedExpression alloc] initWithFunctionCall:call];
}

- (iTermFunctionArgument *)newFunctionArgumentWithName:(NSString *)name
                                            expression:(iTermParsedExpression *)expression
                                       passByReference:(BOOL)passByReference {
    iTermFunctionArgument *arg = [[iTermFunctionArgument alloc] init];
    arg.name = name;
    arg.expression = expression;
    arg.passByReference = passByReference;
    return arg;
}

- (iTermParsedExpression *)parsedExpressionWithReferenceToPath:(NSString *)path {
    if (![_scope userWritableContainerExistsForPath:path]) {
        return [[iTermParsedExpression alloc] initWithErrorCode:3 reason:[NSString stringWithFormat:@"Can’t form reference to non-existent or read-only container for variable %@", path]];
    }
    iTermVariableReference *ref = [[iTermVariableReference alloc] initWithPath:path
                                                                        vendor:_scope];
    return [[iTermParsedExpression alloc] initWithReference:ref];
}

- (iTermParsedExpression *)parsedExpressionWithIndirectValue:(iTermIndirectValue *)indirectValue {
    if (indirectValue.error) {
        return [[iTermParsedExpression alloc] initWithErrorCode:3 reason:indirectValue.error];
    }

    if ([indirectValue.value conformsToProtocol:@protocol(iTermExpressionParserPlaceholder)]) {
        return [[iTermParsedExpression alloc] initWithPlaceholder:(id<iTermExpressionParserPlaceholder>)indirectValue.value
                                                         optional:YES];
    }

    // The 'null' literal is a valid Nil expression with no fallback error.
    if ([indirectValue.path isEqualToString:@"null"] && indirectValue.value == nil) {
        return [[iTermParsedExpression alloc] initWithExpressionType:iTermParsedExpressionTypeNil
                                                              object:nil
                                                            optional:NO];
    }

    // For undefined variables, set a fallback error but do NOT auto-optionalize.
    // The user must write "var?" explicitly to treat undefined as null.
    // The ConditionalExpression '?' rule will optionalize when appropriate.
    NSString *fallbackError = [NSString stringWithFormat:@"Reference to undefined variable \"%@\". Change it to \"%@?\" to treat the undefined value as null.", indirectValue.path, indirectValue.path];
    return [[iTermParsedExpression alloc] initWithObject:indirectValue.value
                                              errorReason:fallbackError];
}

+ (iTermParsedExpression *)parsedExpressionWithInterpolatedStringParts:(NSArray<iTermParsedExpression *> *)interpolatedParts {
    NSArray<iTermParsedExpression *> *coalesced =
    [interpolatedParts reduceWithFirstValue:@[]
                                      block:
     ^id(NSArray<iTermParsedExpression *> *arraySoFar, iTermParsedExpression *expression) {
         if (expression.expressionType == iTermParsedExpressionTypeString &&
             arraySoFar.lastObject &&
             arraySoFar.lastObject.expressionType == iTermParsedExpressionTypeString) {
             NSString *concatenated = [arraySoFar.lastObject.string stringByAppendingString:expression.string];
             iTermParsedExpression *combined = [[iTermParsedExpression alloc] initWithString:concatenated];
             return [[arraySoFar subarrayToIndex:arraySoFar.count - 1] arrayByAddingObject:combined];
         }
         return [arraySoFar arrayByAddingObject:expression];
     }];
    return [[iTermParsedExpression alloc] initWithInterpolatedStringParts:coalesced];
}

- (iTermParsedExpression *)parsedExpressionWithInterpolatedString:(NSString *)swifty {
    return [self.class parsedExpressionWithInterpolatedString:swifty scope:_scope];
}

+ (iTermParsedExpression *)parsedExpressionWithInterpolatedString:(NSString *)swifty
                                                            scope:(iTermVariableScope *)scope {
    return [self parsedExpressionWithInterpolatedString:swifty escapingFunction:nil scope:scope strict:NO];
}

+ (iTermParsedExpression *)parsedExpressionWithInterpolatedString:(NSString *)swifty
                                                 escapingFunction:(NSString *(^)(NSString *string))escapingFunction
                                                            scope:(iTermVariableScope *)scope
                                                           strict:(BOOL)strict {
    __block BOOL allLiterals = YES;
    __block NSError *error = nil;
    NSMutableArray *interpolatedParts = [NSMutableArray array];
    [swifty enumerateSwiftySubstrings:^(NSUInteger index, NSString *substring, BOOL isLiteral, BOOL *stop) {
        if (isLiteral) {
            NSString *escapedString = [substring it_stringByExpandingBackslashEscapedCharacters];
            [interpolatedParts addObject:[[iTermParsedExpression alloc] initWithString:escapedString]];
            return;
        }
        allLiterals = NO;

        iTermExpressionParser *parser = [[iTermExpressionParser alloc] initWithStart:@"expression"];
        iTermParsedExpression *expression = [parser parse:substring
                                                    scope:scope];
        if (expression.expressionType == iTermParsedExpressionTypeString && escapingFunction) {
            NSString *escapedString = escapingFunction(expression.string);
            [interpolatedParts addObject:[[iTermParsedExpression alloc] initWithString:escapedString]];
            return;
        }
        if (!strict &&
            [iTermAdvancedSettingsModel laxNilPolicyInInterpolatedStrings] &&
            expression.expressionType == iTermParsedExpressionTypeError) {
            iTermParsedExpression *expressionWithPlaceholders = [parser parse:substring
                                                                        scope:[[iTermVariablePlaceholderScope alloc] init]];
            if ([expressionWithPlaceholders.object conformsToProtocol:@protocol(iTermExpressionParserPlaceholder)]) {
                expression = [[iTermParsedExpression alloc] initWithString:@""];
            }
        }
        [interpolatedParts addObject:expression];
        if (expression.expressionType == iTermParsedExpressionTypeError) {
            error = expression.error;
            *stop = YES;
            return;
        }
    }];

    if (error) {
        return [[iTermParsedExpression alloc] initWithError:error];
    }

    if (allLiterals) {
        return [[iTermParsedExpression alloc] initWithString:[swifty it_stringByExpandingBackslashEscapedCharacters]];
    }
    return [self parsedExpressionWithInterpolatedStringParts:interpolatedParts];
}

- (iTermIndirectValue *)indirectValueWithPath:(NSString *)path
                                        index:(iTermSubexpression *)indexExpression {
    if ([path isEqualToString:@"null"] && !indexExpression) {
        return [[iTermIndirectValue alloc] initWithPath:path];
    }
    if (_scope.usePlaceholders) {
        id placeholder;
        if (indexExpression) {
            placeholder = [[iTermExpressionParserArrayDereferencePlaceholder alloc] initWithPath:path
                                                                                 indexExpression:indexExpression];
        } else {
            placeholder = [[iTermExpressionParserVariableReferencePlaceholder alloc] initWithPath:path];
        }
        return [[iTermIndirectValue alloc] initWithValue:placeholder
                                                    path:path];
    }
    id untypedValue = [_scope valueForVariableName:path];
    if (!untypedValue) {
        return [[iTermIndirectValue alloc] initWithPath:path];
    }

    if (!indexExpression) {
        return [[iTermIndirectValue alloc] initWithValue:untypedValue path:path];
    }

    NSArray *array = [NSArray castFrom:untypedValue];
    if (!array) {
        NSString *reason = [NSString stringWithFormat:@"Variable “%@” is of type %@, not array", path, NSStringFromClass([untypedValue class])];
        return [[iTermIndirectValue alloc] initWithError:reason path:path];
    }

    if (indexExpression.requiresAsyncEvaluation) {
        return [[iTermIndirectValue alloc] initWithArray:array indexExpression:indexExpression];
    } else {
        NSError *error;
        NSNumber *indexValue = [indexExpression synchronousValueWithSideEffectsAllowed:NO scope:_scope error:&error];
        if (error) {
            NSString *reason = [NSString stringWithFormat:@"Error evaluating index expression: %@", error.localizedDescription];
            return [[iTermIndirectValue alloc] initWithError:reason path:path];
        }
        const NSInteger index = indexValue.integerValue;
        if (index < 0 || index >= array.count) {
            NSString *reason = [NSString stringWithFormat:@"Index %@ out of range of “%@”, which has %@ value%@", @(index), path, @(array.count), array.count == 1 ? @"" : @"s"];
            return [[iTermIndirectValue alloc] initWithError:reason path:path];
        }
        return [[iTermIndirectValue alloc] initWithValue:array[index] path:path];
    }
}

- (iTermParsedExpression *)parse:(NSString *)invocation scope:(iTermVariableScope *)scope {
    if (!invocation) {
        NSError *error = [NSError errorWithDomain:@"com.iterm2.parser"
                                             code:2
                                         userInfo:@{ NSLocalizedDescriptionKey: @"Syntax error" }];
        return [[iTermParsedExpression alloc] initWithError:error];
    }
    _scope = scope;
    return [iTermNativeExpressionCore parseInvocation:invocation start:_start parserOwner:self];
}

@end
