//
//  iTermRowOutputCache.h
//  Latterm
//

#import <Foundation/Foundation.h>
#import "iTermRowContentIdentity.h"

typedef struct {
    uint64_t configGeneration;
    iTermRowContentIdentity contentIdentity;
} iTermRowCacheKey;
