//
//  iTermGitClient.m
//  pidinfo
//
//  Created by George Nachman on 1/11/21.
//

#import "iTermGitClient.h"

#import "iTermGitState.h"

#include <mach/mach_time.h>

static double iTermGitClientTimeSinceBoot(void) {
    const uint64_t elapsed = mach_absolute_time();
    mach_timebase_info_data_t timebase;
    mach_timebase_info(&timebase);
    const double nanoseconds = (double)elapsed * timebase.numer / timebase.denom;
    return nanoseconds / 1.0e9;
}

static NSArray<NSData *> *iTermGitNullSeparatedFields(NSData *data) {
    NSMutableArray<NSData *> *fields = [NSMutableArray array];
    const unsigned char *bytes = data.bytes;
    NSUInteger start = 0;
    for (NSUInteger i = 0; i < data.length; i++) {
        if (bytes[i] == 0) {
            [fields addObject:[data subdataWithRange:NSMakeRange(start, i - start)]];
            start = i + 1;
        }
    }
    if (start < data.length) {
        [fields addObject:[data subdataWithRange:NSMakeRange(start, data.length - start)]];
    }
    return fields;
}

static NSString *iTermGitStringFromData(NSData *data) {
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

static NSString *iTermGitTrimmedStringFromData(NSData *data) {
    return [iTermGitStringFromData(data)
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static iTermGitFileChangeKind iTermGitChangeKindForCode(unsigned char code,
                                                        BOOL worktree) {
    switch (code) {
        case 'M':
            return iTermGitFileChangeKindModified;
        case 'A':
            return iTermGitFileChangeKindAdded;
        case 'D':
            return iTermGitFileChangeKindDeleted;
        case 'R':
        case 'C':
            return iTermGitFileChangeKindRenamed;
        case 'T':
            return iTermGitFileChangeKindTypeChange;
        case '?':
            return worktree ? iTermGitFileChangeKindUntracked : iTermGitFileChangeKindNone;
        default:
            return iTermGitFileChangeKindNone;
    }
}

static BOOL iTermGitStatusIsConflicted(unsigned char indexCode,
                                       unsigned char worktreeCode) {
    if (indexCode == 'U' || worktreeCode == 'U') {
        return YES;
    }
    return ((indexCode == 'A' && worktreeCode == 'A') ||
            (indexCode == 'D' && worktreeCode == 'D'));
}

@interface iTermGitClient ()
@property (nonatomic, readwrite, copy) NSString *path;
@property (nonatomic, readwrite, getter=isValid) BOOL valid;
@end

@implementation iTermGitClient

- (instancetype)initWithRepoPath:(NSString *)path {
    self = [super init];
    if (self) {
        _path = [path copy];
        int status = 0;
        NSData *output = [self runArguments:@[ @"rev-parse", @"--is-inside-work-tree" ]
                                      status:&status];
        _valid = (status == 0 &&
                  [[iTermGitTrimmedStringFromData(output) lowercaseString]
                      isEqualToString:@"true"]);
    }
    return self;
}

- (NSData *)runArguments:(NSArray<NSString *> *)arguments status:(int *)status {
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/git"];

    NSMutableArray<NSString *> *allArguments =
        [@[ @"-C", self.path,
            @"-c", @"core.quotepath=false" ] mutableCopy];
    [allArguments addObjectsFromArray:arguments];
    task.arguments = allArguments;

    NSMutableDictionary<NSString *, NSString *> *environment =
        [NSProcessInfo.processInfo.environment mutableCopy];
    for (NSString *key in environment.allKeys) {
        if ([key hasPrefix:@"Malloc"] ||
            [key hasPrefix:@"DYLD_"] ||
            [key hasPrefix:@"NSZombie"] ||
            [key hasPrefix:@"ASAN_"]) {
            [environment removeObjectForKey:key];
        }
    }
    environment[@"GIT_OPTIONAL_LOCKS"] = @"0";
    environment[@"GIT_TERMINAL_PROMPT"] = @"0";
    environment[@"LC_ALL"] = @"C";
    task.environment = environment;

    NSPipe *outputPipe = [NSPipe pipe];
    task.standardOutput = outputPipe;
    task.standardError = NSFileHandle.fileHandleWithNullDevice;

    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        if (status) {
            *status = -1;
        }
        return [NSData data];
    }

    NSData *output = [outputPipe.fileHandleForReading readDataToEndOfFile];
    [task waitUntilExit];
    if (status) {
        *status = task.terminationStatus;
    }
    return output;
}

- (NSString *)stringForArguments:(NSArray<NSString *> *)arguments
                           status:(int *)status {
    return iTermGitTrimmedStringFromData([self runArguments:arguments status:status]);
}

- (NSString *)branch {
    int status = 0;
    NSString *branch = [self stringForArguments:@[ @"symbolic-ref", @"-q", @"--short", @"HEAD" ]
                                           status:&status];
    if (status == 0 && branch.length > 0) {
        return branch;
    }
    NSString *oid = [self stringForArguments:@[ @"rev-parse", @"--verify", @"HEAD" ]
                                        status:&status];
    return (status == 0 && oid.length > 0) ? oid : nil;
}

- (BOOL)getAhead:(NSInteger *)ahead behind:(NSInteger *)behind {
    int status = 0;
    NSString *counts = [self stringForArguments:@[ @"rev-list",
                                                    @"--left-right",
                                                    @"--count",
                                                    @"HEAD...@{u}" ]
                                          status:&status];
    if (status != 0) {
        return NO;
    }
    NSArray<NSString *> *parts =
        [counts componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    NSMutableArray<NSString *> *numbers = [NSMutableArray array];
    for (NSString *part in parts) {
        if (part.length > 0) {
            [numbers addObject:part];
        }
    }
    if (numbers.count != 2) {
        return NO;
    }
    if (ahead) {
        *ahead = numbers[0].integerValue;
    }
    if (behind) {
        *behind = numbers[1].integerValue;
    }
    return YES;
}

- (BOOL)populateStatusCountsOnState:(iTermGitState *)state {
    int status = 0;
    NSData *output = [self runArguments:@[ @"status",
                                           @"--porcelain=v1",
                                           @"-z",
                                           @"--untracked-files=all",
                                           @"--ignore-submodules=all",
                                           @"--no-renames" ]
                                     status:&status];
    if (status != 0) {
        return NO;
    }
    NSArray<NSData *> *records = iTermGitNullSeparatedFields(output);
    NSInteger untracked = 0;
    NSInteger deleted = 0;
    NSInteger count = 0;
    for (NSData *record in records) {
        if (record.length < 3) {
            continue;
        }
        const unsigned char *bytes = record.bytes;
        count += 1;
        if (bytes[0] == '?' && bytes[1] == '?') {
            untracked += 1;
        }
        if (bytes[1] == 'D') {
            deleted += 1;
        }
    }
    state.dirty = (count > 0);
    state.adds = untracked;
    state.deletes = deleted;
    return YES;
}

- (BOOL)populateHeadFileStatusesOnState:(iTermGitState *)state {
    int status = 0;
    NSData *output = [self runArguments:@[ @"status",
                                           @"--porcelain=v1",
                                           @"-z",
                                           @"--untracked-files=no",
                                           @"--ignore-submodules=all",
                                           @"--renames" ]
                                     status:&status];
    if (status != 0) {
        return NO;
    }
    NSArray<NSData *> *records = iTermGitNullSeparatedFields(output);
    NSMutableArray<iTermGitFileStatus *> *result = [NSMutableArray array];
    for (NSUInteger i = 0; i < records.count; i++) {
        NSData *record = records[i];
        if (record.length < 3) {
            continue;
        }
        const unsigned char *bytes = record.bytes;
        const unsigned char indexCode = bytes[0];
        const unsigned char worktreeCode = bytes[1];
        NSData *pathData = [record subdataWithRange:NSMakeRange(3, record.length - 3)];
        NSString *path = iTermGitStringFromData(pathData);
        const BOOL hasRenamePath = (indexCode == 'R' || indexCode == 'C' ||
                                    worktreeCode == 'R' || worktreeCode == 'C');
        if (hasRenamePath && i + 1 < records.count) {
            i += 1;
        }
        if (!path) {
            continue;
        }

        iTermGitFileStatus *fileStatus = [[iTermGitFileStatus alloc] init];
        fileStatus.path = path;
        fileStatus.indexStatus = iTermGitChangeKindForCode(indexCode, NO);
        fileStatus.workdirStatus = iTermGitChangeKindForCode(worktreeCode, YES);
        if (iTermGitStatusIsConflicted(indexCode, worktreeCode)) {
            fileStatus.workdirStatus = iTermGitFileChangeKindConflicted;
        }
        if (fileStatus.indexStatus != iTermGitFileChangeKindNone ||
            fileStatus.workdirStatus != iTermGitFileChangeKindNone) {
            [result addObject:fileStatus];
        }
    }
    state.fileStatuses = result;
    return YES;
}

- (BOOL)populateFileStatusesAgainstBase:(NSString *)gitBase
                                onState:(iTermGitState *)state {
    int status = 0;
    NSString *treeSpec = [gitBase stringByAppendingString:@"^{tree}"];
    [self runArguments:@[ @"rev-parse", @"--verify", treeSpec ] status:&status];
    if (status != 0) {
        return NO;
    }
    NSData *output = [self runArguments:@[ @"diff",
                                           @"--name-status",
                                           @"-z",
                                           @"--find-renames",
                                           @"--ignore-submodules=all",
                                           gitBase,
                                           @"--" ]
                                     status:&status];
    if (status != 0) {
        return NO;
    }

    NSArray<NSData *> *fields = iTermGitNullSeparatedFields(output);
    NSMutableArray<iTermGitFileStatus *> *result = [NSMutableArray array];
    for (NSUInteger i = 0; i < fields.count;) {
        NSString *statusString = iTermGitStringFromData(fields[i++]);
        if (statusString.length == 0 || i >= fields.count) {
            break;
        }
        const unichar code = [statusString characterAtIndex:0];
        NSString *path = iTermGitStringFromData(fields[i++]);
        if ((code == 'R' || code == 'C') && i < fields.count) {
            path = iTermGitStringFromData(fields[i++]);
        }
        if (!path) {
            continue;
        }
        iTermGitFileChangeKind kind = iTermGitChangeKindForCode((unsigned char)code, YES);
        if (code == 'U') {
            kind = iTermGitFileChangeKindConflicted;
        }
        if (kind == iTermGitFileChangeKindNone ||
            kind == iTermGitFileChangeKindUntracked) {
            continue;
        }
        iTermGitFileStatus *fileStatus = [[iTermGitFileStatus alloc] init];
        fileStatus.path = path;
        fileStatus.workdirStatus = kind;
        [result addObject:fileStatus];
    }
    state.fileStatuses = result;
    return YES;
}

- (NSDictionary<NSString *, NSNumber *> *)diffKindsWithStatus:(int *)status {
    NSData *output = [self runArguments:@[ @"diff",
                                           @"--name-status",
                                           @"-z",
                                           @"--find-renames",
                                           @"--ignore-submodules=all",
                                           @"HEAD",
                                           @"--" ]
                                     status:status];
    if (status && *status != 0) {
        return nil;
    }
    NSArray<NSData *> *fields = iTermGitNullSeparatedFields(output);
    NSMutableDictionary<NSString *, NSNumber *> *result = [NSMutableDictionary dictionary];
    for (NSUInteger i = 0; i < fields.count;) {
        NSString *statusString = iTermGitStringFromData(fields[i++]);
        if (statusString.length == 0 || i >= fields.count) {
            break;
        }
        const unichar code = [statusString characterAtIndex:0];
        NSString *path = iTermGitStringFromData(fields[i++]);
        if ((code == 'R' || code == 'C') && i < fields.count) {
            path = iTermGitStringFromData(fields[i++]);
        }
        if (path) {
            result[path] = @(code);
        }
    }
    return result;
}

- (BOOL)populateDiffStatsOnState:(iTermGitState *)state {
    int status = 0;
    NSDictionary<NSString *, NSNumber *> *kinds = [self diffKindsWithStatus:&status];
    if (status != 0 || !kinds) {
        return NO;
    }

    NSInteger filesAdded = state.adds;
    NSInteger filesDeleted = 0;
    NSInteger filesModified = 0;
    for (NSNumber *value in kinds.allValues) {
        switch (value.unsignedCharValue) {
            case 'A':
                filesAdded += 1;
                break;
            case 'D':
                filesDeleted += 1;
                break;
            case 'M':
            case 'R':
            case 'C':
            case 'T':
                filesModified += 1;
                break;
            default:
                break;
        }
    }

    NSData *output = [self runArguments:@[ @"diff",
                                           @"--numstat",
                                           @"-z",
                                           @"--find-renames",
                                           @"--ignore-submodules=all",
                                           @"HEAD",
                                           @"--" ]
                                     status:&status];
    if (status != 0) {
        return NO;
    }
    NSInteger linesInserted = 0;
    NSInteger linesDeleted = 0;
    NSArray<NSData *> *fields = iTermGitNullSeparatedFields(output);
    for (NSUInteger i = 0; i < fields.count;) {
        NSString *header = iTermGitStringFromData(fields[i++]);
        if (!header) {
            continue;
        }
        NSArray<NSString *> *parts = [header componentsSeparatedByString:@"\t"];
        if (parts.count < 3) {
            continue;
        }
        NSString *path = parts[2];
        if (path.length == 0 && i + 1 < fields.count) {
            i += 1;
            path = iTermGitStringFromData(fields[i++]);
        }
        const unsigned char code = kinds[path].unsignedCharValue;
        if (code != 'M' && code != 'R' && code != 'C' && code != 'T') {
            continue;
        }
        if (![parts[0] isEqualToString:@"-"]) {
            linesInserted += parts[0].integerValue;
        }
        if (![parts[1] isEqualToString:@"-"]) {
            linesDeleted += parts[1].integerValue;
        }
    }

    state.filesAdded = filesAdded;
    state.filesDeleted = filesDeleted;
    state.filesModified = filesModified;
    state.linesInserted = linesInserted;
    state.linesDeleted = linesDeleted;
    return YES;
}

- (iTermGitRepoState)repoState {
    int status = 0;
    NSString *gitDirectory = [self stringForArguments:@[ @"rev-parse", @"--absolute-git-dir" ]
                                                status:&status];
    if (status != 0 || gitDirectory.length == 0) {
        return iTermGitRepoStateNone;
    }
    NSFileManager *fileManager = NSFileManager.defaultManager;
    BOOL (^exists)(NSString *) = ^BOOL(NSString *relativePath) {
        return [fileManager fileExistsAtPath:
            [gitDirectory stringByAppendingPathComponent:relativePath]];
    };
    if (exists(@"MERGE_HEAD")) {
        return iTermGitRepoStateMerge;
    }
    if (exists(@"REVERT_HEAD")) {
        return iTermGitRepoStateRevert;
    }
    if (exists(@"CHERRY_PICK_HEAD")) {
        return iTermGitRepoStateCherrypick;
    }
    NSString *sequencerTodoPath =
        [gitDirectory stringByAppendingPathComponent:@"sequencer/todo"];
    NSData *sequencerTodoData = [fileManager contentsAtPath:sequencerTodoPath];
    NSString *sequencerTodo = sequencerTodoData
        ? iTermGitStringFromData(sequencerTodoData)
        : nil;
    __block iTermGitRepoState sequencerState = iTermGitRepoStateNone;
    [sequencerTodo enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
        NSString *trimmed =
            [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (trimmed.length == 0 || [trimmed hasPrefix:@"#"]) {
            return;
        }
        sequencerState = [trimmed hasPrefix:@"revert "]
            ? iTermGitRepoStateRevert
            : iTermGitRepoStateCherrypick;
        *stop = YES;
    }];
    if (sequencerState != iTermGitRepoStateNone) {
        return sequencerState;
    }
    if (exists(@"BISECT_LOG")) {
        return iTermGitRepoStateBisect;
    }
    if (exists(@"rebase-merge") || exists(@"rebase-apply/rebasing")) {
        return iTermGitRepoStateRebase;
    }
    if (exists(@"rebase-apply")) {
        return iTermGitRepoStateApply;
    }
    return iTermGitRepoStateNone;
}

- (NSArray<NSString *> *)recentBranchesWithLimit:(NSInteger)limit {
    if (!self.valid || limit <= 0) {
        return @[];
    }
    int status = 0;
    NSString *countArgument = [NSString stringWithFormat:@"--count=%@", @(limit)];
    NSString *output = [self stringForArguments:@[ @"for-each-ref",
                                                   countArgument,
                                                   @"--sort=-committerdate",
                                                   @"--format=%(refname:short)",
                                                   @"refs/heads/" ]
                                         status:&status];
    if (status != 0) {
        return nil;
    }
    NSMutableArray<NSString *> *branches = [NSMutableArray array];
    [output enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
        if (line.length > 0) {
            [branches addObject:line];
        }
    }];
    return branches;
}

@end

@implementation iTermGitState (GitClient)

+ (instancetype)gitStateForRepoAtPath:(NSString *)path {
    return [self gitStateForRepoAtPath:path includeDiffStats:NO];
}

+ (instancetype)gitStateForRepoAtPath:(NSString *)path
                     includeDiffStats:(BOOL)includeDiffStats {
    return [self gitStateForRepoAtPath:path
                               gitBase:nil
                      includeDiffStats:includeDiffStats];
}

+ (instancetype)gitStateForRepoAtPath:(NSString *)path
                              gitBase:(NSString *)gitBase
                     includeDiffStats:(BOOL)includeDiffStats {
    iTermGitClient *client = [[iTermGitClient alloc] initWithRepoPath:path];
    if (!client.valid) {
        return nil;
    }

    NSString *branch = client.branch;
    if (!branch) {
        return nil;
    }

    iTermGitState *state = [[iTermGitState alloc] init];
    state.creationTime = iTermGitClientTimeSinceBoot();
    state.branch = branch;

    NSInteger ahead = 0;
    NSInteger behind = 0;
    if ([client getAhead:&ahead behind:&behind]) {
        state.ahead = [@(ahead) stringValue];
        state.behind = [@(behind) stringValue];
    } else {
        state.ahead = @"";
        state.behind = @"";
    }

    if (![client populateStatusCountsOnState:state]) {
        return nil;
    }
    if (includeDiffStats) {
        [client populateHeadFileStatusesOnState:state];
        [client populateDiffStatsOnState:state];
    }
    if (includeDiffStats &&
        gitBase.length > 0 &&
        ![gitBase isEqualToString:@"HEAD"]) {
        [client populateFileStatusesAgainstBase:gitBase onState:state];
    }
    state.repoState = client.repoState;
    return state;
}

@end
