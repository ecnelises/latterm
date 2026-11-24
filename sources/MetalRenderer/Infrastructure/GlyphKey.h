//
//  GlyphKey.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/19/17.
//

#import <Foundation/Foundation.h>
#import <stdint.h>
#import <string.h>
#import "iTermMetalGlyphKey.h"
#import "NSFont+iTerm.h"

NS_ASSUME_NONNULL_BEGIN

typedef struct {
    iTermMetalGlyphKey repr;
    size_t hash;
} iTermGlyphKey;

NS_INLINE void iTermGlyphKeyHashCombine(size_t *seed, uint64_t value) {
    uint64_t x = value;
    x ^= x >> 30;
    x *= 0xbf58476d1ce4e5b9ULL;
    x ^= x >> 27;
    x *= 0x94d049bb133111ebULL;
    x ^= x >> 31;
    *seed ^= (size_t)x + (size_t)0x9e3779b9 + (*seed << 6) + (*seed >> 2);
}

NS_INLINE uint64_t iTermGlyphKeyDoubleBits(double value) {
    if (value == 0.0) {
        value = 0.0;
    }
    uint64_t bits = 0;
    memcpy(&bits, &value, sizeof(bits));
    return bits;
}

NS_INLINE size_t iTermGlyphKeyComputeHash(const iTermMetalGlyphKey *repr) {
    size_t seed = 0;

    iTermGlyphKeyHashCombine(&seed, (uint64_t)repr->type);
    iTermGlyphKeyHashCombine(&seed, (uint64_t)repr->thinStrokes);
    iTermGlyphKeyHashCombine(&seed, (uint64_t)repr->typeface);
    iTermGlyphKeyHashCombine(&seed, (uint64_t)repr->lineAttribute);
    switch (repr->type) {
        case iTermMetalGlyphTypeRegular:
            // No need to include _repr.drawable because we just skip those glyphs.
            iTermGlyphKeyHashCombine(&seed, (uint64_t)repr->payload.regular.code);
            iTermGlyphKeyHashCombine(&seed, (uint64_t)repr->payload.regular.combiningSuccessor);
            iTermGlyphKeyHashCombine(&seed, (uint64_t)repr->payload.regular.isComplex);
            iTermGlyphKeyHashCombine(&seed, (uint64_t)repr->payload.regular.boxDrawing);
            break;

        case iTermMetalGlyphTypeDecomposed:
            iTermGlyphKeyHashCombine(&seed, (uint64_t)repr->payload.decomposed.fontID);
            iTermGlyphKeyHashCombine(&seed, (uint64_t)repr->payload.decomposed.glyphNumber);
            iTermGlyphKeyHashCombine(&seed, (uint64_t)repr->payload.decomposed.fakeBold);
            iTermGlyphKeyHashCombine(&seed, (uint64_t)repr->payload.decomposed.fakeItalic);
            iTermGlyphKeyHashCombine(&seed, (uint64_t)repr->payload.decomposed.antiAlias);
            iTermGlyphKeyHashCombine(&seed, iTermGlyphKeyDoubleBits(repr->payload.decomposed.position.x));
            iTermGlyphKeyHashCombine(&seed, iTermGlyphKeyDoubleBits(repr->payload.decomposed.position.y));
            break;
    }

    return seed;
}

NS_INLINE iTermGlyphKey iTermGlyphKeyMake(const iTermMetalGlyphKey *repr) {
    iTermGlyphKey key;
    key.repr = *repr;
    key.hash = iTermGlyphKeyComputeHash(repr);
    return key;
}

NS_INLINE BOOL iTermGlyphKeyEquals(iTermGlyphKey a, iTermGlyphKey b) {
    if (a.hash != b.hash) {
        return NO;
    }
    if (a.repr.type != b.repr.type ||
        a.repr.typeface != b.repr.typeface ||
        a.repr.thinStrokes != b.repr.thinStrokes ||
        a.repr.lineAttribute != b.repr.lineAttribute) {
        return NO;
    }

    switch (a.repr.type) {
        case iTermMetalGlyphTypeRegular:
            return (a.repr.payload.regular.code == b.repr.payload.regular.code &&
                    a.repr.payload.regular.combiningSuccessor == b.repr.payload.regular.combiningSuccessor &&
                    a.repr.payload.regular.isComplex == b.repr.payload.regular.isComplex &&
                    a.repr.payload.regular.boxDrawing == b.repr.payload.regular.boxDrawing);
        case iTermMetalGlyphTypeDecomposed:
            return (a.repr.payload.decomposed.fontID == b.repr.payload.decomposed.fontID &&
                    a.repr.payload.decomposed.fakeBold == b.repr.payload.decomposed.fakeBold &&
                    a.repr.payload.decomposed.fakeItalic == b.repr.payload.decomposed.fakeItalic &&
                    a.repr.payload.decomposed.antiAlias == b.repr.payload.decomposed.antiAlias &&
                    a.repr.payload.decomposed.glyphNumber == b.repr.payload.decomposed.glyphNumber &&
                    NSEqualPoints(a.repr.payload.decomposed.position,
                                  b.repr.payload.decomposed.position));
    }
    return NO;
}

NS_INLINE NSString *iTermGlyphKeyDescription(const iTermGlyphKey *key) {
    switch (key->repr.type) {
        case iTermMetalGlyphTypeRegular:
            return [NSString stringWithFormat:@"[GlyphKey regular: code=%@ combiningSuccessor=%@ complex=%@ boxdrawing=%@ thinStrokes=%@ drawable=%@ typeface=%@]",
                    @(key->repr.payload.regular.code),
                    @(key->repr.payload.regular.combiningSuccessor),
                    @(key->repr.payload.regular.isComplex),
                    @(key->repr.payload.regular.boxDrawing),
                    @(key->repr.thinStrokes),
                    @(key->repr.payload.regular.drawable),
                    iTermGlyphTypefaceString(&key->repr)];
        case iTermMetalGlyphTypeDecomposed:
            return [NSString stringWithFormat:@"[GlyphKey decomposed: font=%@ fakeBold=%@ fakeItalic=%@ glyph=%@ thinStrokes=%@ typeface=%@]",
                    [NSFont it_fontWithMetalID:key->repr.payload.decomposed.fontID],
                    @(key->repr.payload.decomposed.fakeBold),
                    @(key->repr.payload.decomposed.fakeItalic),
                    @(key->repr.payload.decomposed.glyphNumber),
                    @(key->repr.thinStrokes),
                    iTermGlyphTypefaceString(&key->repr)];
    }
    return @"[GlyphKey unknown]";
}

NS_ASSUME_NONNULL_END
