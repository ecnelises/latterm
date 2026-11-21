//
//  iTermExpressionParser+Private.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/1/19.
//

#import "iTermExpressionParser.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermFunctionArgument : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) iTermParsedExpression *expression;
@property (nonatomic) BOOL passByReference;
@end

@interface iTermExpressionParser ()

- (iTermParsedExpression *)callSequenceWithCalls:(NSArray<iTermScriptFunctionCall *> *)calls;
- (iTermParsedExpression *)buildFunctionCallParsedExpressionWithFqName:(NSString *)fqName
                                                                  args:(NSArray<iTermFunctionArgument *> *)argsArray
    NS_SWIFT_NAME(buildFunctionCallParsedExpression(fqName:args:));
- (iTermFunctionArgument *)newFunctionArgumentWithName:(NSString *)name
                                            expression:(iTermParsedExpression *)expression
                                       passByReference:(BOOL)passByReference;
- (iTermParsedExpression *)parsedExpressionWithReferenceToPath:(NSString *)path
    NS_SWIFT_NAME(parsedExpression(withReferenceToPath:));
- (iTermParsedExpression *)parsedExpressionWithIndirectValue:(iTermIndirectValue *)indirectValue
    NS_SWIFT_NAME(parsedExpression(with:));
- (iTermParsedExpression *)parsedExpressionWithInterpolatedString:(NSString *)swifty;
- (iTermIndirectValue *)indirectValueWithPath:(NSString *)path
                                        index:(nullable iTermSubexpression *)indexExpression;

@end

NS_ASSUME_NONNULL_END
