//
//  VT100TmuxParser.m
//  iTerm
//
//  Created by George Nachman on 3/10/14.
//
//

#import "VT100TmuxParser.h"
#import "DebugLogging.h"
#import "NSMutableData+iTerm.h"

#import "iTerm2SharedARC-Swift.h"

@implementation VT100TmuxParser {
    TmuxControlLineState *_controlLines;
    NSMutableData *_line;
}

- (instancetype)init {
    return [self initRecovering:NO];
}

- (instancetype)initInRecoveryMode {
    return [self initRecovering:YES];
}

- (instancetype)initRecovering:(BOOL)recovering {
    self = [super init];
    if (self) {
        _line = [[NSMutableData alloc] init];
        _controlLines = [[TmuxControlLineState alloc] initRecovering:recovering];
        _serverMayOmitEndGuardBeforeExit = YES;
    }
    return self;
}

- (NSString *)hookDescription {
    return @"[TMUX GATEWAY]";
}

- (VT100DCSParserHookResult)handleInput:(iTermParserContext *)context
           support8BitControlCharacters:(BOOL)support8BitControlCharacters
                                  token:(VT100Token *)result {
    int bytesTilNewline = iTermParserNumberOfBytesUntilCharacter(context, '\n');
    if (bytesTilNewline == -1) {
        DLog(@"No newline found.");
        // No newline to be found. Append everything that is available to |_line|.
        int length = iTermParserLength(context);
        [_line appendBytes:iTermParserPeekRawBytes(context, length)
                    length:length
            excludingCharacter:'\r'];
        iTermParserAdvanceMultiple(context, length);
        result->type = VT100_WAIT;
    } else {
        // Append bytes up to the newline, stripping out linefeeds. Consume the newline.
        [_line appendBytes:iTermParserPeekRawBytes(context, bytesTilNewline)
                    length:bytesTilNewline
            excludingCharacter:'\r'];
        iTermParserAdvanceMultiple(context, bytesTilNewline + 1);

        // Tokenize the line, returning if it is a terminator like %exit.
        if ([self processLineIntoToken:result]) {
            return VT100DCSParserHookResultUnhook;
        }
    }
    return VT100DCSParserHookResultCanReadAgain;
}

// Return YES if we should unhook.
- (BOOL)processLineIntoToken:(VT100Token *)result {
    result.savedData = [_line copy];
    NSString *command =
        [[NSString alloc] initWithData:_line encoding:NSUTF8StringEncoding];

    if (!command) {
        // The command was not UTF-8. Unfortunately, this can happen. If tmux has a non-UTF-8
        // character in a pane, it will just output it in capture-pane.
        command = [[NSString alloc] initWithUTF8DataIgnoringErrors:_line];
    }

    [_line setLength:0];
    result.type = [_controlLines classify:command serverMayOmitEndGuardBeforeExit:self.serverMayOmitEndGuardBeforeExit];
    result.string = result.type == VT100_WAIT ? nil : command;
    return result.type == TMUX_EXIT;
}

@end
