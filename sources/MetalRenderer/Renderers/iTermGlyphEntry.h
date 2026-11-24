//
//  iTermGlyphEntry.h
//  iTerm2
//
//  Created by George Nachman on 12/22/17.
//

#import <Metal/Metal.h>
#import <stdlib.h>
#import "GlyphKey.h"
#import "iTermTexturePage.h"

NS_ASSUME_NONNULL_BEGIN

typedef struct {
    int part;
    iTermGlyphKey key;
    __unsafe_unretained iTermTexturePage *page;
    int index;
    BOOL isEmoji;
    MTLOrigin origin;
} iTermGlyphEntry;

typedef struct {
    iTermGlyphEntry *_Nullable entries;
    size_t count;
    size_t capacity;
} iTermGlyphEntryList;

NS_INLINE iTermGlyphEntryList *iTermGlyphEntryListCreate(size_t initialCapacity) {
    iTermGlyphEntryList *list = (iTermGlyphEntryList *)calloc(1, sizeof(iTermGlyphEntryList));
    if (initialCapacity > 0) {
        list->entries = (iTermGlyphEntry *)malloc(initialCapacity * sizeof(iTermGlyphEntry));
        list->capacity = initialCapacity;
    }
    return list;
}

NS_INLINE void iTermGlyphEntryListDestroy(iTermGlyphEntryList * _Nullable list) {
    if (!list) {
        return;
    }
    free(list->entries);
    free(list);
}

NS_INLINE void iTermGlyphEntryListAppend(iTermGlyphEntryList *list, iTermGlyphEntry entry) {
    if (list->count == list->capacity) {
        const size_t newCapacity = list->capacity > 0 ? list->capacity * 2 : 4;
        list->entries = (iTermGlyphEntry *)realloc(list->entries, newCapacity * sizeof(iTermGlyphEntry));
        list->capacity = newCapacity;
    }
    list->entries[list->count++] = entry;
}

NS_ASSUME_NONNULL_END
