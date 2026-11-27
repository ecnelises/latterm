//
//  iTermTexturePageCollection.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/26/17.
//

#import "iTermTexturePageCollection.h"

#import "DebugLogging.h"
#import "iTermMalloc.h"
#import <stdlib.h>

@implementation iTermTexturePage {
    BOOL *_emoji;
    iTermGlyphKey *_glyphKeys;
    size_t _glyphKeyCount;
    size_t _glyphKeyCapacity;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device
                      capacity:(int)capacity
                      cellSize:(vector_uint2)cellSize {
    self = [super init];
    if (self) {
        _capacity = capacity;
        _cellSize = cellSize;
        _count = 0;
        _emoji = (BOOL *)iTermCalloc((size_t)MAX(1, capacity), sizeof(BOOL));
        _textureArray = [[iTermTextureArray alloc] initWithTextureWidth:cellSize.x
                                                          textureHeight:cellSize.y
                                                            arrayLength:capacity
                                                            pixelFormat:MTLPixelFormatBGRA8Unorm
                                                                 device:device];
        _atlasSize = simd_make_uint2(_textureArray.atlasSize.width,
                                     _textureArray.atlasSize.height);
        _reciprocalAtlasSize = 1.0f / simd_make_float2(_atlasSize.x, _atlasSize.y);
    }
    return self;
}

- (void)dealloc {
    free(_emoji);
    _emoji = NULL;
    free(_glyphKeys);
    _glyphKeys = NULL;
}

- (int)availableCount {
    return _capacity - _count;
}

- (int)addImage:(iTermCharacterBitmap *)image isEmoji:(BOOL)isEmoji {
    ITExtraDebugAssert(_count < _capacity);
    [_textureArray setSlice:_count withBitmap:image];
    _emoji[_count] = isEmoji;
    return _count++;
}

- (id<MTLTexture>)texture {
    return _textureArray.texture;
}

- (BOOL)isEmojiAtIndex:(int)index {
    return _emoji[index];
}

- (void)recordUse {
    static long long useCount;
    _lastUsed = useCount++;
}

- (void)recordGlyphKey:(iTermGlyphKey)key {
    if (_glyphKeyCount > 0 && iTermGlyphKeyEquals(_glyphKeys[_glyphKeyCount - 1], key)) {
        return;
    }
    if (_glyphKeyCount == _glyphKeyCapacity) {
        const size_t newCap = _glyphKeyCapacity > 0 ? _glyphKeyCapacity * 2 : 16;
        _glyphKeys = (iTermGlyphKey *)iTermRealloc(_glyphKeys, newCap, sizeof(iTermGlyphKey));
        _glyphKeyCapacity = newCap;
    }
    _glyphKeys[_glyphKeyCount++] = key;
}

- (size_t)glyphKeysCount {
    return _glyphKeyCount;
}

- (const iTermGlyphKey *)glyphKeys {
    return _glyphKeys;
}

@end

#pragma mark - Open-Addressing Hash Table for iTermGlyphKey -> iTermGlyphEntryList *

typedef NS_ENUM(uint8_t, iTermGlyphMapSlotState) {
    iTermGlyphMapSlotEmpty = 0,
    iTermGlyphMapSlotOccupied = 1,
    iTermGlyphMapSlotTombstone = 2
};

typedef struct {
    iTermGlyphKey key;
    iTermGlyphEntryList *value;
    iTermGlyphMapSlotState state;
} iTermGlyphMapSlot;

typedef struct {
    iTermGlyphMapSlot *slots;
    size_t capacity;
    size_t count;
    size_t usedCount;  // occupied + tombstones
} iTermGlyphMap;

static void iTermGlyphMapInit(iTermGlyphMap *map, size_t initialCapacity) {
    size_t capacity = 64;
    while (capacity < initialCapacity) {
        capacity *= 2;
    }
    map->slots = (iTermGlyphMapSlot *)iTermCalloc(capacity, sizeof(iTermGlyphMapSlot));
    map->capacity = capacity;
    map->count = 0;
    map->usedCount = 0;
}

static void iTermGlyphMapDestroy(iTermGlyphMap *map) {
    if (map->slots) {
        for (size_t i = 0; i < map->capacity; i++) {
            if (map->slots[i].state == iTermGlyphMapSlotOccupied) {
                iTermGlyphEntryListDestroy(map->slots[i].value);
            }
        }
        free(map->slots);
        map->slots = NULL;
    }
    map->capacity = 0;
    map->count = 0;
    map->usedCount = 0;
}

static void iTermGlyphMapInsertRaw(iTermGlyphMap *map,
                                   iTermGlyphKey key,
                                   iTermGlyphEntryList *value) {
    const size_t mask = map->capacity - 1;
    size_t idx = key.hash & mask;
    size_t firstTombstone = SIZE_MAX;

    while (map->slots[idx].state != iTermGlyphMapSlotEmpty) {
        if (map->slots[idx].state == iTermGlyphMapSlotOccupied) {
            if (iTermGlyphKeyEquals(map->slots[idx].key, key)) {
                iTermGlyphEntryListDestroy(map->slots[idx].value);
                map->slots[idx].value = value;
                return;
            }
        } else if (firstTombstone == SIZE_MAX) {
            firstTombstone = idx;
        }
        idx = (idx + 1) & mask;
    }

    const size_t target = (firstTombstone != SIZE_MAX) ? firstTombstone : idx;
    if (map->slots[target].state == iTermGlyphMapSlotEmpty) {
        map->usedCount += 1;
    }
    map->slots[target].key = key;
    map->slots[target].value = value;
    map->slots[target].state = iTermGlyphMapSlotOccupied;
    map->count += 1;
}

static void iTermGlyphMapRehash(iTermGlyphMap *map, size_t newCapacity) {
    iTermGlyphMapSlot *oldSlots = map->slots;
    const size_t oldCapacity = map->capacity;

    map->slots = (iTermGlyphMapSlot *)iTermCalloc(newCapacity, sizeof(iTermGlyphMapSlot));
    map->capacity = newCapacity;
    map->count = 0;
    map->usedCount = 0;

    for (size_t i = 0; i < oldCapacity; i++) {
        if (oldSlots[i].state == iTermGlyphMapSlotOccupied) {
            iTermGlyphMapInsertRaw(map, oldSlots[i].key, oldSlots[i].value);
        }
    }
    free(oldSlots);
}

static iTermGlyphEntryList *iTermGlyphMapFind(const iTermGlyphMap *map, iTermGlyphKey key) {
    if (!map->slots || map->capacity == 0 || map->count == 0) {
        return NULL;
    }
    const size_t mask = map->capacity - 1;
    size_t idx = key.hash & mask;
    while (map->slots[idx].state != iTermGlyphMapSlotEmpty) {
        if (map->slots[idx].state == iTermGlyphMapSlotOccupied &&
            iTermGlyphKeyEquals(map->slots[idx].key, key)) {
            return map->slots[idx].value;
        }
        idx = (idx + 1) & mask;
    }
    return NULL;
}

static void iTermGlyphMapSet(iTermGlyphMap *map, iTermGlyphKey key, iTermGlyphEntryList *value) {
    if (!map->slots || map->capacity == 0) {
        iTermGlyphMapInit(map, 64);
    } else if ((map->usedCount + 1) * 10 >= map->capacity * 7) {
        const size_t newCapacity = (map->count * 2 > map->capacity / 2)
            ? (map->capacity * 2)
            : map->capacity;
        iTermGlyphMapRehash(map, newCapacity);
    }
    iTermGlyphMapInsertRaw(map, key, value);
}

static void iTermGlyphMapErase(iTermGlyphMap *map, iTermGlyphKey key) {
    if (!map->slots || map->capacity == 0 || map->count == 0) {
        return;
    }
    const size_t mask = map->capacity - 1;
    size_t idx = key.hash & mask;
    while (map->slots[idx].state != iTermGlyphMapSlotEmpty) {
        if (map->slots[idx].state == iTermGlyphMapSlotOccupied &&
            iTermGlyphKeyEquals(map->slots[idx].key, key)) {
            iTermGlyphEntryListDestroy(map->slots[idx].value);
            map->slots[idx].value = NULL;
            map->slots[idx].state = iTermGlyphMapSlotTombstone;
            map->count -= 1;
            return;
        }
        idx = (idx + 1) & mask;
    }
}

#pragma mark - iTermTexturePageCollection

@implementation iTermTexturePageCollection {
    id<MTLDevice> _device;
    int _pageCapacity;
    int _maximumNumberOfPages;
    iTermGlyphMap _pages;
    NSMutableArray<iTermTexturePage *> *_allPages;
    iTermTexturePage *_openPage;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device
                      cellSize:(vector_uint2)cellSize
                  pageCapacity:(int)pageCapacity
          maximumNumberOfPages:(int)maximumNumberOfPages {
    self = [super init];
    if (self) {
        _device = device;
        _cellSize = cellSize;
        _pageCapacity = pageCapacity;
        _maximumNumberOfPages = maximumNumberOfPages;
        iTermGlyphMapInit(&_pages, 256);
        _allPages = [NSMutableArray array];
    }
    return self;
}

- (void)dealloc {
    _openPage = nil;
    [_allPages removeAllObjects];
    iTermGlyphMapDestroy(&_pages);
}

- (const iTermGlyphEntryList *)findEntriesForGlyphKey:(iTermGlyphKey)glyphKey {
    return iTermGlyphMapFind(&_pages, glyphKey);
}

- (iTermGlyphEntryList *)addEntriesForColumn:(int)column
                                    glyphKey:(iTermGlyphKey)glyphKey
                                     context:(iTermMetalBufferPoolContext *)context
                                     creator:(NSDictionary<NSNumber *, iTermCharacterBitmap *> *(NS_NOESCAPE ^)(int, BOOL *))creator {
    BOOL emoji = NO;
    NSDictionary<NSNumber *, iTermCharacterBitmap *> *images = creator(column, &emoji);
    iTermGlyphEntryList *result = iTermGlyphEntryListCreate(images.count);
    iTermGlyphMapSet(&_pages, glyphKey, result);
    for (NSNumber *partNumber in images) {
        iTermCharacterBitmap *image = images[partNumber];
        const iTermGlyphEntry entry = [self internalAddPart:partNumber.intValue
                                                   glyphKey:glyphKey
                                                      image:image
                                                    isEmoji:emoji
                                                    context:context];
        iTermGlyphEntryListAppend(result, entry);
    }
    DLog(@"Added %@. Count is now %@", iTermGlyphKeyDescription(&glyphKey), @(_allPages.count * (NSUInteger)_pageCapacity));
    return result;
}

- (iTermGlyphEntry)internalAddPart:(int)part
                          glyphKey:(iTermGlyphKey)key
                             image:(iTermCharacterBitmap *)image
                           isEmoji:(BOOL)isEmoji
                           context:(iTermMetalBufferPoolContext *)context {
    if (!_openPage) {
        _openPage = [[iTermTexturePage alloc] initWithDevice:_device
                                                    capacity:_pageCapacity
                                                    cellSize:_cellSize];
        [context didAddTextureOfSize:_cellSize.x * _cellSize.y * (uint64_t)_pageCapacity];
        [_allPages addObject:_openPage];
    }

    iTermTexturePage *openPage = _openPage;
    ITExtraDebugAssert(openPage.availableCount > 0);
    const int index = [openPage addImage:image isEmoji:isEmoji];
    [openPage recordGlyphKey:key];
    iTermGlyphEntry entry = {
        .part = part,
        .key = key,
        .page = openPage,
        .index = index,
        .isEmoji = isEmoji,
        .origin = [openPage.textureArray offsetForIndex:index],
    };
    if (openPage.availableCount == 0) {
        _openPage = nil;
    }
    return entry;
}

- (NSUInteger)pageCount {
    return _allPages.count;
}

- (BOOL)isOverMaximumSize {
    return (int)_allPages.count > _maximumNumberOfPages;
}

- (void)pruneIfNeeded {
    [self pruneToMaximumPages:_maximumNumberOfPages];
}

- (void)pruneToMaximumPages:(int)maxPages {
    if (maxPages <= 0) {
        [self removeAll];
        return;
    }
    if ((NSInteger)_allPages.count <= maxPages) {
        DLog(@"Not pruning");
        return;
    }
    ELog(@"Pruning. Have %@ pages. Each page stores up to %@ glyphs. Max pages is %@",
         @(_allPages.count),
         @(_pageCapacity),
         @(maxPages));

    [_allPages sortUsingComparator:^NSComparisonResult(iTermTexturePage *a, iTermTexturePage *b) {
        if (a->_lastUsed < b->_lastUsed) {
            return NSOrderedAscending;
        }
        if (a->_lastUsed > b->_lastUsed) {
            return NSOrderedDescending;
        }
        return NSOrderedSame;
    }];

    const NSUInteger excess = _allPages.count - (NSUInteger)maxPages;
    for (NSUInteger i = 0; i < excess; i++) {
        iTermTexturePage *pageToPrune = _allPages[i];
        if (pageToPrune == _openPage) {
            _openPage = nil;
        }
        const iTermGlyphKey *keys = [pageToPrune glyphKeys];
        const size_t keyCount = [pageToPrune glyphKeysCount];
        for (size_t k = 0; k < keyCount; k++) {
            iTermGlyphMapErase(&_pages, keys[k]);
        }
    }
    [_allPages removeObjectsInRange:NSMakeRange(0, excess)];
}

- (void)removeAll {
    _openPage = nil;
    [_allPages removeAllObjects];
    iTermGlyphMapDestroy(&_pages);
    iTermGlyphMapInit(&_pages, 256);
}

- (void)internalPrune:(iTermTexturePage *)pageToPrune {
    if (pageToPrune == _openPage) {
        _openPage = nil;
    }
    const iTermGlyphKey *keys = [pageToPrune glyphKeys];
    const size_t keyCount = [pageToPrune glyphKeysCount];
    for (size_t i = 0; i < keyCount; i++) {
        iTermGlyphMapErase(&_pages, keys[i]);
    }
    [_allPages removeObjectIdenticalTo:pageToPrune];
}

@end
