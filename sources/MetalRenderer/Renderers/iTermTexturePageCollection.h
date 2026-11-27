//
//  iTermTexturePageCollection.h
//  iTerm2
//
//  Created by George Nachman on 12/22/17.
//

#import <Metal/Metal.h>
#import "iTermGlyphEntry.h"
#import "iTermMetalBufferPool.h"
#import "iTermTexturePage.h"

NS_ASSUME_NONNULL_BEGIN

// Holds a collection of iTermTexturePages. Provides an interface for finding an
// iTermGlyphEntryList for an iTermGlyphKey, adding a new glyph, and pruning disused
// texture pages.
@interface iTermTexturePageCollection : NSObject

@property (nonatomic, readonly) vector_uint2 cellSize;
@property (nonatomic, readonly) NSUInteger pageCount;

- (instancetype)initWithDevice:(id<MTLDevice>)device
                      cellSize:(vector_uint2)cellSize
                  pageCapacity:(int)pageCapacity
          maximumNumberOfPages:(int)maximumNumberOfPages NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

// Returns NULL if no entries exist for this glyph key.
- (const iTermGlyphEntryList * _Nullable)findEntriesForGlyphKey:(iTermGlyphKey)glyphKey;

// Adds glyph entries for a glyph key, allocating new texture pages as needed.
- (iTermGlyphEntryList * _Nullable)addEntriesForColumn:(int)column
                                              glyphKey:(iTermGlyphKey)glyphKey
                                               context:(iTermMetalBufferPoolContext *)context
                                               creator:(NSDictionary<NSNumber *, iTermCharacterBitmap *> *(NS_NOESCAPE ^)(int, BOOL *))creator;

// Discard least-recently used texture pages.
- (void)pruneIfNeeded;
- (void)pruneToMaximumPages:(int)maxPages;
- (void)removeAll;

@end

NS_ASSUME_NONNULL_END
