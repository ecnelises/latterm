//
//  LineBufferSorting.h
//  Latterm
//

#import <Foundation/Foundation.h>
#import "LineBufferHelpers.h"
#import "VT100GridTypes.h"

#if __cplusplus
extern "C"
#endif
int *SortedPositionsFromResultRanges(NSArray<ResultRange *> *ranges, BOOL includeEnds);
