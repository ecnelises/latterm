//
//  iTermPIUArray.h
//  iTerm2
//
//  Created by George Nachman on 12/19/17.
//

#import <Foundation/Foundation.h>
#import <stdlib.h>
#import <string.h>
#import "iTermTextRendererCommon.h"

NS_ASSUME_NONNULL_BEGIN

// Maximum number of PIUs in one segment by default.
static const size_t iTermPIUArrayDefaultCapacity = 1024;

// Append-only segmented array of iTermTextPIU structs to avoid huge contiguous allocations.
typedef struct {
    size_t capacity;
    size_t size;
    size_t segmentCount;
    size_t segmentCapacity;
    iTermTextPIU *_Nullable *_Nullable segments;
    size_t *_Nullable segmentSizes;
} iTermTextPIUArray;

NS_INLINE void iTermTextPIUArrayInit(iTermTextPIUArray *array, size_t capacity) {
    memset(array, 0, sizeof(*array));
    array->capacity = capacity > 0 ? capacity : iTermPIUArrayDefaultCapacity;
}

NS_INLINE void iTermTextPIUArrayDestroy(iTermTextPIUArray *array) {
    for (size_t i = 0; i < array->segmentCount; i++) {
        free(array->segments[i]);
    }
    free(array->segments);
    free(array->segmentSizes);
    memset(array, 0, sizeof(*array));
}

NS_INLINE void iTermTextPIUArrayMove(iTermTextPIUArray *dest, iTermTextPIUArray *src) {
    *dest = *src;
    memset(src, 0, sizeof(*src));
}

NS_INLINE void iTermTextPIUArrayAppendSegment(iTermTextPIUArray *array) {
    if (array->capacity == 0) {
        array->capacity = iTermPIUArrayDefaultCapacity;
    }
    if (array->segmentCount == array->segmentCapacity) {
        const size_t newCap = array->segmentCapacity > 0 ? array->segmentCapacity * 2 : 4;
        array->segments = (iTermTextPIU **)realloc(array->segments, newCap * sizeof(iTermTextPIU *));
        array->segmentSizes = (size_t *)realloc(array->segmentSizes, newCap * sizeof(size_t));
        array->segmentCapacity = newCap;
    }
    iTermTextPIU *segment = (iTermTextPIU *)malloc(array->capacity * sizeof(iTermTextPIU));
    array->segments[array->segmentCount] = segment;
    array->segmentSizes[array->segmentCount] = 0;
    array->segmentCount += 1;
}

NS_INLINE iTermTextPIU *iTermTextPIUArrayGetNext(iTermTextPIUArray *array) {
    if (array->segmentCount == 0 ||
        array->segmentSizes[array->segmentCount - 1] == array->capacity) {
        iTermTextPIUArrayAppendSegment(array);
    }
    const size_t last = array->segmentCount - 1;
    const size_t idx = array->segmentSizes[last]++;
    array->size += 1;
    return &array->segments[last][idx];
}

NS_INLINE iTermTextPIU *iTermTextPIUArrayGet(const iTermTextPIUArray *array, size_t index) {
    return &array->segments[index / array->capacity][index % array->capacity];
}

NS_INLINE void iTermTextPIUArrayPushBack(iTermTextPIUArray *array, const iTermTextPIU *piu) {
    memcpy(iTermTextPIUArrayGetNext(array), piu, sizeof(*piu));
}

NS_INLINE size_t iTermTextPIUArraySegmentCount(const iTermTextPIUArray *array) {
    return array->segmentCount;
}

NS_INLINE const iTermTextPIU *iTermTextPIUArraySegmentStart(const iTermTextPIUArray *array, size_t segment) {
    return array->segments[segment];
}

NS_INLINE size_t iTermTextPIUArraySegmentSize(const iTermTextPIUArray *array, size_t segment) {
    return array->segmentSizes[segment];
}

NS_INLINE size_t iTermTextPIUArraySize(const iTermTextPIUArray *array) {
    return array->size;
}

NS_ASSUME_NONNULL_END
