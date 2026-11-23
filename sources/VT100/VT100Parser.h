//
//  VT100Parser.h
//  iTerm
//
//  Created by George Nachman on 3/2/14.
//
//

#import <Foundation/Foundation.h>
#import "CVector.h"
#import "VT100Token.h"

@class VT100TmuxParser;

@interface VT100Parser : NSObject

@property(nonatomic, readonly) NSData *streamData;
@property(atomic, assign) NSStringEncoding encoding;
@property(nonatomic, readonly) int streamLength;
@property(atomic) BOOL literalMode;

- (void)putStreamData:(const char *)bytes length:(int)length;
- (void)clearStream;
- (void)forceUnhookDCS:(NSString *)uniqueID;
- (void)startTmuxRecoveryModeWithID:(NSString *)dcsID;
- (void)cancelTmuxRecoveryMode;

// Whether a %exit line inside a %begin/%end block ends tmux mode. Pass NO once the tmux server
// is known to be 1.9 or later; see VT100TmuxParser. Thread-safe.
- (void)setTmuxServerMayOmitEndGuardBeforeExit:(BOOL)mayOmit;

- (NSInteger)startConductorRecoveryModeWithID:(NSString *)dcsID tree:(NSDictionary *)tree;
- (void)cancelConductorRecoveryMode;

// Each appended token holds one reference owned by the vector. Consumers release
// those references with CVectorReleaseObjects before destroying the pointer storage.
//
// Returns the number of bytes of input that were executed excluding inband sigaling (ssh, tmux).
- (int)addParsedTokensToVector:(CVector *)vector;

// Reset all state.
- (void)reset;

// Reset but preserve SSH state.
- (void)resetExceptSSH;

// Push config from mutation thread for pre-converting non-ASCII strings.
// Thread-safe: called from mutation thread, read from parser thread.
- (void)updateStringConversionConfig:(VT100StringConversionConfig)config;

@end
