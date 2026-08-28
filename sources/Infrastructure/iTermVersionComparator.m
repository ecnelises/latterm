//
//  iTermVersionComparator.m
//  iTerm2
//

#import "iTermVersionComparator.h"

typedef NS_ENUM(NSInteger, iTermVersionPartType) {
    iTermVersionPartTypeNumber,
    iTermVersionPartTypeString,
    iTermVersionPartTypeSeparator,
};

static iTermVersionPartType iTermVersionTypeOfCharacter(unichar character) {
    if ([[NSCharacterSet decimalDigitCharacterSet] characterIsMember:character]) {
        return iTermVersionPartTypeNumber;
    }
    if ([[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:character] ||
        [[NSCharacterSet punctuationCharacterSet] characterIsMember:character]) {
        return iTermVersionPartTypeSeparator;
    }
    return iTermVersionPartTypeString;
}

static NSArray<NSString *> *iTermVersionParts(NSString *version) {
    if (version.length == 0) {
        return @[];
    }

    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    NSUInteger start = 0;
    iTermVersionPartType currentType = iTermVersionTypeOfCharacter([version characterAtIndex:0]);
    for (NSUInteger i = 1; i < version.length; i++) {
        const iTermVersionPartType nextType = iTermVersionTypeOfCharacter([version characterAtIndex:i]);
        if (nextType != currentType || currentType == iTermVersionPartTypeSeparator) {
            [parts addObject:[version substringWithRange:NSMakeRange(start, i - start)]];
            start = i;
            currentType = nextType;
        }
    }
    [parts addObject:[version substringFromIndex:start]];
    return parts;
}

static NSString *iTermNormalizedNumber(NSString *number) {
    NSUInteger firstNonzero = 0;
    while (firstNonzero < number.length && [number characterAtIndex:firstNonzero] == '0') {
        firstNonzero++;
    }
    if (firstNonzero == number.length) {
        return @"0";
    }
    return [number substringFromIndex:firstNonzero];
}

static NSComparisonResult iTermCompareNumbers(NSString *number, NSString *otherNumber) {
    NSString *normalized = iTermNormalizedNumber(number);
    NSString *otherNormalized = iTermNormalizedNumber(otherNumber);
    if (normalized.length < otherNormalized.length) {
        return NSOrderedAscending;
    }
    if (normalized.length > otherNormalized.length) {
        return NSOrderedDescending;
    }
    return [normalized compare:otherNormalized options:NSLiteralSearch];
}

static NSComparisonResult iTermCompareVersionParts(NSString *part, NSString *otherPart) {
    const iTermVersionPartType type = iTermVersionTypeOfCharacter([part characterAtIndex:0]);
    const iTermVersionPartType otherType = iTermVersionTypeOfCharacter([otherPart characterAtIndex:0]);
    if (type == otherType) {
        if (type == iTermVersionPartTypeNumber) {
            return iTermCompareNumbers(part, otherPart);
        }
        if (type == iTermVersionPartTypeString) {
            return [part compare:otherPart];
        }
        return NSOrderedSame;
    }

    if (type == iTermVersionPartTypeString) {
        return NSOrderedAscending;
    }
    if (otherType == iTermVersionPartTypeString) {
        return NSOrderedDescending;
    }
    return type == iTermVersionPartTypeNumber ? NSOrderedDescending : NSOrderedAscending;
}

@implementation iTermVersionComparator

+ (NSComparisonResult)compareVersion:(NSString *)version
                           toVersion:(NSString *)otherVersion {
    NSArray<NSString *> *parts = iTermVersionParts(version);
    NSArray<NSString *> *otherParts = iTermVersionParts(otherVersion);
    const NSUInteger commonCount = MIN(parts.count, otherParts.count);
    for (NSUInteger i = 0; i < commonCount; i++) {
        const NSComparisonResult result = iTermCompareVersionParts(parts[i], otherParts[i]);
        if (result != NSOrderedSame) {
            return result;
        }
    }

    if (parts.count == otherParts.count) {
        return NSOrderedSame;
    }

    const BOOL firstIsLonger = parts.count > otherParts.count;
    NSString *extraPart = firstIsLonger ? parts[commonCount] : otherParts[commonCount];
    const BOOL extraPartIsPrerelease =
        iTermVersionTypeOfCharacter([extraPart characterAtIndex:0]) == iTermVersionPartTypeString;
    if (firstIsLonger == extraPartIsPrerelease) {
        return NSOrderedAscending;
    }
    return NSOrderedDescending;
}

@end
