//
//  iTermCharacterParts.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/15/17.
//

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

extern const int iTermTextureMapMaxCharacterParts;
extern const int iTermTextureMapMiddleCharacterPart;

enum {
    iTermCharacterPartEncodingRadius = 15,
    iTermCharacterPartEncodingStride = iTermCharacterPartEncodingRadius * 2 + 1,
};

NS_INLINE int iTermImagePartDX(int part) {
    return (part % iTermCharacterPartEncodingStride) - iTermCharacterPartEncodingRadius;
}

NS_INLINE int iTermImagePartDY(int part) {
    return (part / iTermCharacterPartEncodingStride) - iTermCharacterPartEncodingRadius;
}

NS_INLINE int iTermImagePartFromDeltas(int dx, int dy) {
    return (dx + iTermCharacterPartEncodingRadius) + (dy + iTermCharacterPartEncodingRadius) * iTermCharacterPartEncodingStride;
}

#if __cplusplus
}
#endif

