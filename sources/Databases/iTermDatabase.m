//
//  iTermDatabase.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/28/20.
//

#import "iTermDatabase.h"

#import "DebugLogging.h"
#import "NSArray+iTerm.h"
#import "NSDate+iTerm.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermUserDefaults.h"
#import <sqlite3.h>
#import <string.h>

static NSString *const iTermSqliteDatabaseErrorDomain = @"iTermSqliteDatabase";

@interface iTermSqliteDatabaseImpl ()
- (void)recordSqliteError;
- (void)unregisterResultSet:(id)resultSet;
@end

@interface iTermSqliteResultSet : NSObject<iTermDatabaseResultSet>
- (instancetype)initWithStatement:(sqlite3_stmt *)stmt
                         database:(iTermSqliteDatabaseImpl *)db NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@end

@implementation iTermSqliteResultSet {
    sqlite3_stmt *_stmt;
    __weak iTermSqliteDatabaseImpl *_db;
    NSDictionary<NSString *, NSNumber *> *_columnNameToIndex;
    BOOL _closed;
}

- (instancetype)initWithStatement:(sqlite3_stmt *)stmt
                         database:(iTermSqliteDatabaseImpl *)db {
    self = [super init];
    if (self) {
        _stmt = stmt;
        _db = db;
    }
    return self;
}

- (void)dealloc {
    [self close];
}

- (void)close {
    if (_closed) {
        return;
    }
    _closed = YES;
    if (_stmt != NULL) {
        sqlite3_finalize(_stmt);
        _stmt = NULL;
    }
    [_db unregisterResultSet:self];
}

- (BOOL)next {
    if (_closed || _stmt == NULL) {
        return NO;
    }
    const int rc = sqlite3_step(_stmt);
    if (rc == SQLITE_ROW) {
        return YES;
    }
    if (rc != SQLITE_DONE) {
        [_db recordSqliteError];
    }
    [self close];
    return NO;
}

- (int)columnIndexForName:(NSString *)columnName {
    if (_stmt == NULL || columnName.length == 0) {
        return -1;
    }
    if (!_columnNameToIndex) {
        const int columnCount = sqlite3_column_count(_stmt);
        NSMutableDictionary<NSString *, NSNumber *> *map = [NSMutableDictionary dictionaryWithCapacity:(NSUInteger)columnCount];
        for (int i = 0; i < columnCount; i++) {
            const char *rawName = sqlite3_column_name(_stmt, i);
            if (rawName) {
                NSString *key = [[NSString stringWithUTF8String:rawName] lowercaseString];
                if (key) {
                    map[key] = @(i);
                }
            }
        }
        _columnNameToIndex = [map copy];
    }
    NSNumber *indexNumber = _columnNameToIndex[[columnName lowercaseString]];
    if (!indexNumber) {
        DLog(@"Column named '%@' not found in result set", columnName);
        return -1;
    }
    return indexNumber.intValue;
}

- (BOOL)isValidColumnIndex:(int)idx {
    return _stmt != NULL && idx >= 0 && idx < sqlite3_column_count(_stmt);
}

- (NSString * _Nullable)stringForColumn:(NSString *)columnName {
    const int idx = [self columnIndexForName:columnName];
    if (![self isValidColumnIndex:idx] || sqlite3_column_type(_stmt, idx) == SQLITE_NULL) {
        return nil;
    }
    const char *text = (const char *)sqlite3_column_text(_stmt, idx);
    if (!text) {
        return nil;
    }
    const int length = sqlite3_column_bytes(_stmt, idx);
    return [[NSString alloc] initWithBytes:text
                                    length:(NSUInteger)length
                                  encoding:NSUTF8StringEncoding];
}

- (long long)longLongIntForColumn:(NSString *)columnName {
    const int idx = [self columnIndexForName:columnName];
    if (![self isValidColumnIndex:idx]) {
        return 0;
    }
    return sqlite3_column_int64(_stmt, idx);
}

- (int)intForColumn:(NSString *)columnName {
    const int idx = [self columnIndexForName:columnName];
    if (![self isValidColumnIndex:idx]) {
        return 0;
    }
    return sqlite3_column_int(_stmt, idx);
}

- (BOOL)boolForColumn:(NSString *)columnName {
    return [self intForColumn:columnName] != 0;
}

- (NSData * _Nullable)dataForColumn:(NSString *)columnName {
    const int idx = [self columnIndexForName:columnName];
    if (![self isValidColumnIndex:idx] || sqlite3_column_type(_stmt, idx) == SQLITE_NULL) {
        return nil;
    }
    const int length = sqlite3_column_bytes(_stmt, idx);
    if (length == 0) {
        return [NSData data];
    }
    const void *bytes = sqlite3_column_blob(_stmt, idx);
    if (!bytes) {
        return nil;
    }
    return [NSData dataWithBytes:bytes length:(NSUInteger)length];
}

- (NSDate * _Nullable)dateForColumn:(NSString *)columnName {
    const int idx = [self columnIndexForName:columnName];
    if (![self isValidColumnIndex:idx] || sqlite3_column_type(_stmt, idx) == SQLITE_NULL) {
        return nil;
    }
    return [NSDate dateWithTimeIntervalSince1970:sqlite3_column_double(_stmt, idx)];
}

@end

@implementation iTermSqliteDatabaseImpl {
    sqlite3 *_db;
    BOOL _isMemory;
    NSURL *_url;
    NSFileHandle *_advisoryLock;
    NSString *_lockName;
    NSHashTable<iTermSqliteResultSet *> *_openResultSets;
    NSError *_lastError;
}

@synthesize timeoutHandler;

+ (instancetype)inMemoryDatabase {
    return [[self alloc] initWithURL:[NSURL URLWithString:@"file::memory:"] lockName:nil];
}

+ (NSArray<NSURL *> *)allURLsForDatabaseAt:(NSURL *)url {
    return [@[
        url,
        [url.URLByDeletingPathExtension URLByAppendingPathExtension:@"sqlite-shm"] ?: [NSNull null],
        [url.URLByDeletingPathExtension URLByAppendingPathExtension:@"sqlite-wal"] ?: [NSNull null],
    ] arrayByRemovingNulls];
}

+ (void)touchWithPrivateUnixPermissions:(NSURL *)url {
    if (!url.path) {
        return;
    }
    int fd;
    do {
        fd = open(url.path.UTF8String, O_WRONLY | O_CREAT, 0600);
    } while (fd == -1 && (errno == EAGAIN || errno == EINTR));
    if (fd >= 0) {
        close(fd);
    }
}

- (instancetype)initWithURL:(NSURL *)url {
    return [self initWithURL:url lockName:@"lock"];
}

- (instancetype)initWithURL:(NSURL *)url lockName:(NSString * _Nullable)lockName {
    self = [super init];
    if (self) {
        _isMemory = [url.absoluteString hasPrefix:@"file::memory:"];
        if (!_isMemory) {
            for (NSURL *fileURL in [iTermSqliteDatabaseImpl allURLsForDatabaseAt:url]) {
                [iTermSqliteDatabaseImpl touchWithPrivateUnixPermissions:fileURL];
            }
        }
        _url = url;
        _lockName = [lockName copy];
        _openResultSets = [NSHashTable weakObjectsHashTable];
    }
    return self;
}

- (void)dealloc {
    [self close];
}

- (void)unregisterResultSet:(id)resultSet {
    if ([resultSet isKindOfClass:[iTermSqliteResultSet class]]) {
        [_openResultSets removeObject:(iTermSqliteResultSet *)resultSet];
    }
}

- (void)recordSqliteError {
    if (_db != NULL) {
        const char *msg = sqlite3_errmsg(_db);
        NSString *message = msg ? [NSString stringWithUTF8String:msg] : @"SQLite error";
        _lastError = [NSError errorWithDomain:iTermSqliteDatabaseErrorDomain
                                         code:sqlite3_errcode(_db)
                                     userInfo:@{ NSLocalizedDescriptionKey: message ?: @"SQLite error" }];
    }
}

- (NSError *)notOpenError {
    return [NSError errorWithDomain:iTermSqliteDatabaseErrorDomain
                               code:SQLITE_MISUSE
                           userInfo:@{ NSLocalizedDescriptionKey: @"Database is not open" }];
}

- (void)unlink {
    assert(_db == NULL);
    if (!self.url || _isMemory) {
        return;
    }
    NSError *error = nil;
    NSArray<NSURL *> *urls = [iTermSqliteDatabaseImpl allURLsForDatabaseAt:self.url];
    for (NSURL *url in urls) {
        if (![[NSFileManager defaultManager] removeItemAtURL:url
                                                       error:&error]) {
            RLog(@"Failed to unlink %@: %@", url.path, error);
        }
    }
}

- (int)bindObject:(id)obj toColumn:(int)idx inStatement:(sqlite3_stmt *)stmt {
    if (!obj || obj == [NSNull null]) {
        return sqlite3_bind_null(stmt, idx);
    }
    if ([obj isKindOfClass:[NSData class]]) {
        NSData *data = (NSData *)obj;
        const void *bytes = data.bytes;
        if (!bytes) {
            // Pass a non-NULL pointer for empty NSData so SQLite binds an empty blob rather than NULL.
            bytes = "";
        }
        return sqlite3_bind_blob(stmt, idx, bytes, (int)data.length, SQLITE_TRANSIENT);
    }
    if ([obj isKindOfClass:[NSDate class]]) {
        return sqlite3_bind_double(stmt, idx, [(NSDate *)obj timeIntervalSince1970]);
    }
    if ([obj isKindOfClass:[NSNumber class]]) {
        NSNumber *number = (NSNumber *)obj;
        if (CFGetTypeID((__bridge CFTypeRef)number) == CFBooleanGetTypeID()) {
            return sqlite3_bind_int(stmt, idx, number.boolValue ? 1 : 0);
        }
        const char *objCType = number.objCType;
        if (strcmp(objCType, @encode(char)) == 0 ||
            strcmp(objCType, @encode(unsigned char)) == 0 ||
            strcmp(objCType, @encode(short)) == 0 ||
            strcmp(objCType, @encode(unsigned short)) == 0 ||
            strcmp(objCType, @encode(int)) == 0 ||
            strcmp(objCType, @encode(BOOL)) == 0) {
            return sqlite3_bind_int(stmt, idx, number.intValue);
        }
        if (strcmp(objCType, @encode(unsigned int)) == 0 ||
            strcmp(objCType, @encode(long)) == 0 ||
            strcmp(objCType, @encode(unsigned long)) == 0 ||
            strcmp(objCType, @encode(long long)) == 0 ||
            strcmp(objCType, @encode(unsigned long long)) == 0) {
            return sqlite3_bind_int64(stmt, idx, number.longLongValue);
        }
        if (strcmp(objCType, @encode(float)) == 0 ||
            strcmp(objCType, @encode(double)) == 0) {
            return sqlite3_bind_double(stmt, idx, number.doubleValue);
        }
    }
    const char *utf8 = [obj description].UTF8String;
    return sqlite3_bind_text(stmt, idx, utf8 ?: "", -1, SQLITE_TRANSIENT);
}

- (nullable sqlite3_stmt *)prepareAndBindSQL:(NSString *)sql
                                   arguments:(NSArray *)arguments
                                       error:(out NSError * _Nullable __autoreleasing *)error {
    if (_db == NULL) {
        _lastError = [self notOpenError];
        if (error) {
            *error = _lastError;
        }
        return NULL;
    }

    sqlite3_stmt *stmt = NULL;
    const int prepareRC = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (prepareRC != SQLITE_OK) {
        [self recordSqliteError];
        RLog(@"DB prepare error (%@): %@", sql, _lastError);
        if (error) {
            *error = _lastError;
        }
        if (stmt != NULL) {
            sqlite3_finalize(stmt);
        }
        return NULL;
    }

    const int expectedCount = sqlite3_bind_parameter_count(stmt);
    if ((int)arguments.count != expectedCount) {
        _lastError = [NSError errorWithDomain:iTermSqliteDatabaseErrorDomain
                                         code:SQLITE_RANGE
                                     userInfo:@{ NSLocalizedDescriptionKey:
                                                     [NSString stringWithFormat:@"Expected %d SQL parameters, got %lu",
                                                      expectedCount, (unsigned long)arguments.count] }];
        RLog(@"DB bind count mismatch (%@): %@", sql, _lastError);
        if (error) {
            *error = _lastError;
        }
        sqlite3_finalize(stmt);
        return NULL;
    }

    for (int i = 0; i < expectedCount; i++) {
        const int bindRC = [self bindObject:arguments[(NSUInteger)i] toColumn:(i + 1) inStatement:stmt];
        if (bindRC != SQLITE_OK) {
            [self recordSqliteError];
            RLog(@"DB bind error (%@): %@", sql, _lastError);
            if (error) {
                *error = _lastError;
            }
            sqlite3_finalize(stmt);
            return NULL;
        }
    }

    if (error) {
        *error = nil;
    }
    return stmt;
}

- (NSArray *)collectArgumentsFromVAList:(va_list)args count:(int)count {
    if (count <= 0) {
        return @[];
    }
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:(NSUInteger)count];
    for (int i = 0; i < count; i++) {
        id arg = va_arg(args, id);
        [result addObject:(arg ?: [NSNull null])];
    }
    return result;
}

- (nullable sqlite3_stmt *)prepareSQL:(NSString *)sql
                               vaList:(va_list)args
                        collectedArgs:(out NSArray * _Nullable __autoreleasing *)collectedArgsOut
                                error:(out NSError * _Nullable __autoreleasing *)error {
    if (_db == NULL) {
        _lastError = [self notOpenError];
        if (error) {
            *error = _lastError;
        }
        return NULL;
    }

    sqlite3_stmt *stmt = NULL;
    const int prepareRC = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (prepareRC != SQLITE_OK) {
        [self recordSqliteError];
        RLog(@"DB prepare error (%@): %@", sql, _lastError);
        if (error) {
            *error = _lastError;
        }
        if (stmt != NULL) {
            sqlite3_finalize(stmt);
        }
        return NULL;
    }

    const int paramCount = sqlite3_bind_parameter_count(stmt);
    NSArray *arguments = [self collectArgumentsFromVAList:args count:paramCount];
    for (int i = 0; i < paramCount; i++) {
        const int bindRC = [self bindObject:arguments[(NSUInteger)i] toColumn:(i + 1) inStatement:stmt];
        if (bindRC != SQLITE_OK) {
            [self recordSqliteError];
            RLog(@"DB bind error (%@): %@", sql, _lastError);
            if (error) {
                *error = _lastError;
            }
            sqlite3_finalize(stmt);
            return NULL;
        }
    }
    if (collectedArgsOut) {
        *collectedArgsOut = arguments;
    }
    if (error) {
        *error = nil;
    }
    return stmt;
}

- (BOOL)stepAndFinalizeUpdateStatement:(sqlite3_stmt *)stmt
                                 error:(out NSError * _Nullable __autoreleasing *)error {
    int rc;
    do {
        rc = sqlite3_step(stmt);
    } while (rc == SQLITE_ROW);

    const BOOL ok = (rc == SQLITE_DONE);
    if (!ok) {
        [self recordSqliteError];
        if (error) {
            *error = _lastError;
        }
    } else if (error) {
        *error = nil;
    }
    sqlite3_finalize(stmt);
    return ok;
}

- (BOOL)executeUpdate:(NSString *)sql, ... {
    va_list args;
    va_start(args, sql);
    NSArray *arguments = nil;
    NSError *error = nil;
    sqlite3_stmt *stmt = [self prepareSQL:sql vaList:args collectedArgs:&arguments error:&error];
    va_end(args);

    if (!stmt) {
        return NO;
    }
    const BOOL result = [self stepAndFinalizeUpdateStatement:stmt error:&error];
    if (!result && error) {
        XLog(@"%@ failed: %@", sql, error);
    }
    if (gDebugLogging) {
        [self logStatement:sql arguments:arguments ?: @[]];
    }
    return result;
}

- (BOOL)executeUpdate:(NSString *)sql withNonOptionalArguments:(NSArray *)arguments {
    NSError *error = nil;
    return [self executeUpdate:sql withNonOptionalArguments:arguments error:&error];
}

- (BOOL)executeUpdate:(nonnull NSString *)sql
withNonOptionalArguments:(nonnull NSArray *)arguments
                error:(out NSError * _Nullable __autoreleasing * _Nullable)error {
    NSError *localError = nil;
    sqlite3_stmt *stmt = [self prepareAndBindSQL:sql arguments:arguments error:&localError];
    if (!stmt) {
        if (error) {
            *error = localError;
        }
        return NO;
    }
    const BOOL result = [self stepAndFinalizeUpdateStatement:stmt error:&localError];
    if (!result && localError) {
        XLog(@"%@ failed: %@", sql, localError);
    }
    if (error) {
        *error = localError;
    }
    if (gDebugLogging) {
        [self logStatement:sql arguments:arguments];
    }
    return result;
}

- (NSNumber * _Nullable)lastInsertRowId {
    if (_db == NULL) {
        return nil;
    }
    const int64_t rowid = sqlite3_last_insert_rowid(_db);
    if (!rowid) {
        return nil;
    }
    return @(rowid);
}

- (NSString *)formatSQL:(NSString *)sql arguments:(NSArray *)arguments {
    NSMutableString *formattedSQL = [sql mutableCopy];
    NSUInteger count = arguments.count;
    NSUInteger index = 0;

    NSRange searchRange = NSMakeRange(0, formattedSQL.length);
    while (index < count) {
        NSRange range = [formattedSQL rangeOfString:@"?" options:0 range:searchRange];
        if (range.location == NSNotFound) {
            break;
        }

        id argument = arguments[index++];
        NSString *replacement;

        if ([argument isKindOfClass:[NSString class]]) {
            replacement = [NSString stringWithFormat:@"“%@”", argument];
        } else if ([argument isKindOfClass:[NSNumber class]]) {
            replacement = [argument stringValue];
        } else if ([argument isKindOfClass:[NSNull class]]) {
            replacement = @"NULL";
        } else {
            replacement = [NSString stringWithFormat:@"“%@”", argument];
        }

        [formattedSQL replaceCharactersInRange:range withString:replacement];
        searchRange.location = range.location + replacement.length;
        searchRange.length = formattedSQL.length - searchRange.location;
    }

    return formattedSQL;
}

- (void)logStatement:(NSString *)sql arguments:(NSArray *)arguments {
    if (!gDebugLogging) {
        return;
    }

    // Format the SQL statement with arguments
    NSString *statement = [self formatSQL:sql arguments:arguments];

    DebugLogImpl(__FILE__,
                 __LINE__,
                 __FUNCTION__,
                 statement);
}

- (id<iTermDatabaseResultSet> _Nullable)executeQuery:(NSString *)sql, ... {
    va_list args;
    va_start(args, sql);
    NSArray *arguments = nil;
    NSError *error = nil;
    sqlite3_stmt *stmt = [self prepareSQL:sql vaList:args collectedArgs:&arguments error:&error];
    va_end(args);

    if (!stmt) {
        return nil;
    }
    iTermSqliteResultSet *result = [[iTermSqliteResultSet alloc] initWithStatement:stmt database:self];
    [_openResultSets addObject:result];

    if (gDebugLogging) {
        [self logStatement:sql arguments:arguments ?: @[]];
    }

    return result;
}

- (id<iTermDatabaseResultSet> _Nullable)executeQuery:(NSString *)sql withNonOptionalArguments:(NSArray *)arguments {
    NSError *error = nil;
    return [self executeQuery:sql withNonOptionalArguments:arguments error:&error];
}

- (id<iTermDatabaseResultSet> _Nullable)executeQuery:(nonnull NSString *)sql
                            withNonOptionalArguments:(nonnull NSArray *)arguments
                                               error:(NSError * _Nullable __autoreleasing * _Nullable)error {
    NSError *localError = nil;
    sqlite3_stmt *stmt = [self prepareAndBindSQL:sql arguments:arguments error:&localError];
    if (!stmt) {
        if (error) {
            *error = localError;
        }
        return nil;
    }
    iTermSqliteResultSet *result = [[iTermSqliteResultSet alloc] initWithStatement:stmt database:self];
    [_openResultSets addObject:result];

    if (error) {
        *error = nil;
    }
    if (gDebugLogging) {
        [self logStatement:sql arguments:arguments];
    }
    return result;
}

typedef enum {
    iTermDatabaseIntegrityCheckStateQuerying,
    iTermDatabaseIntegrityCheckStateFinished,
    iTermDatabaseIntegrityCheckStateInterrupted
} iTermDatabaseIntegrityCheckState;

- (void)integrityCheckDidTimeOut:(NSObject *)lock state:(iTermDatabaseIntegrityCheckState *)statePtr {
    RLog(@"integrityCheckDidTimeOut");
    if (!self.timeoutHandler) {
        DLog(@"There is no timeout handler");
        return;
    }

    @synchronized(lock) {
        if (*statePtr != iTermDatabaseIntegrityCheckStateQuerying) {
            DLog(@"Timeout check running after completion");
            return;
        }
        DLog(@"Timeout check running while still querying");
    }

    RLog(@"Invoke timeout handler");
    if (!self.timeoutHandler()) {
        RLog(@"User declined to delete the db");
        return;
    }

    @synchronized(lock) {
        if (*statePtr != iTermDatabaseIntegrityCheckStateQuerying) {
            RLog(@"Succeeded on second chance");
            return;
        }
        RLog(@"Interrupt db check");
        if (_db != NULL) {
            sqlite3_interrupt(_db);
        }
        DLog(@"state<-interrupted");
        *statePtr = iTermDatabaseIntegrityCheckStateInterrupted;
    }
}

- (BOOL)passesIntegrityCheck {
    assert(!_lockName || _advisoryLock != nil);

    if (![iTermAdvancedSettingsModel performSQLiteIntegrityCheck]) {
        return YES;
    }

    NSString *checkType = arc4random_uniform(100) == 0 ? @"integrity_check" : @"quick_check";
    NSObject *lock = [[NSObject alloc] init];
    __block iTermDatabaseIntegrityCheckState state = iTermDatabaseIntegrityCheckStateQuerying;
    __weak __typeof(self) weakSelf = self;
    // After a clean shutdown the WAL has been checkpointed and the db vacuumed,
    // so the integrity check should finish quickly. After a crash the check can
    // take much longer, so extend the timeout to avoid false-alarming the user
    // with the "taking a long time" dialog on every post-crash launch.
    //
    // We also extend the timeout shortly after boot: at login the system is busy
    // restoring every app's windows and disk I/O is saturated, which can make even
    // a healthy database's check exceed the normal timeout. Issue 11809.
    const BOOL recentlyBooted = [NSDate it_timeSinceBoot] < 10 * 60;
    const NSTimeInterval timeout = ([iTermUserDefaults lastShutdownWasClean] && !recentlyBooted) ? 10 : 120;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [weakSelf integrityCheckDidTimeOut:lock state:&state];
    });
    DLog(@"Begin pragma");
    id<iTermDatabaseResultSet> results = [self executeQuery:[NSString stringWithFormat:@"pragma %@", checkType]];
    DLog(@"Returned from pragma");
    NSString *value = nil;
    DLog(@"Begin results.next");
    if ([results next]) {
        DLog(@"Returned from results.next");
        value = [results stringForColumn:checkType];
    } else {
        RLog(@"%@ check failed - no next result", checkType);
    }
    BOOL failed = NO;
    @synchronized(lock) {
        DLog(@"Check state");
        switch (state) {
            case iTermDatabaseIntegrityCheckStateQuerying:
                DLog(@"state<-finished");
                state = iTermDatabaseIntegrityCheckStateFinished;
                break;
            case iTermDatabaseIntegrityCheckStateFinished:
                assert(NO);
            case iTermDatabaseIntegrityCheckStateInterrupted:
                DLog(@"interrupted. set failed<-YES");
                failed = YES;
                break;
        }
    }
    [results close];
    if (failed || ![value isEqualToString:@"ok"]) {
        RLog(@"%@ check failed: %@", checkType, value);
        return NO;
    }
    return YES;
}

- (BOOL)open {
    DLog(@"Open");
    assert(!_lockName || _advisoryLock != nil);
    if (_db != NULL) {
        return YES;
    }
    const char *path = _isMemory ? ":memory:" : _url.path.fileSystemRepresentation;
    const int rc = sqlite3_open(path, &_db);
    if (rc != SQLITE_OK) {
        if (_db != NULL) {
            [self recordSqliteError];
            RLog(@"Failed to open db: %@", _lastError);
            sqlite3_close(_db);
            _db = NULL;
        } else {
            _lastError = [NSError errorWithDomain:iTermSqliteDatabaseErrorDomain
                                             code:rc
                                         userInfo:@{ NSLocalizedDescriptionKey: @"Failed to allocate SQLite handle" }];
            RLog(@"Failed to open db: %@", _lastError);
        }
        return NO;
    }
    if (![self passesIntegrityCheck]) {
        [self close];
        return NO;
    }

    DLog(@"Opened db and passed integrity check.");
    return YES;
}

- (BOOL)close {
    DLog(@"Close");
    NSArray<iTermSqliteResultSet *> *openSets = [_openResultSets allObjects];
    for (iTermSqliteResultSet *resultSet in openSets) {
        [resultSet close];
    }
    [_openResultSets removeAllObjects];
    if (_db == NULL) {
        return YES;
    }
    int rc = sqlite3_close(_db);
    if (rc == SQLITE_BUSY) {
        rc = sqlite3_close_v2(_db);
    }
    if (rc != SQLITE_OK) {
        [self recordSqliteError];
    }
    _db = NULL;
    return rc == SQLITE_OK;
}

- (void)unlock {
    if (!_lockName) {
        return;
    }
    [_advisoryLock closeFile];
    _advisoryLock = nil;
}

- (NSString *)advisoryLockPath {
    if (!_lockName) {
        return nil;
    }
    NSURL *url = [_url.URLByDeletingLastPathComponent URLByAppendingPathComponent:_lockName];
    return url.path;
}

- (BOOL)lock {
    if (!_lockName) {
        return YES;
    }
    [_advisoryLock closeFile];
    _advisoryLock = nil;

    int fd;
    do {
        DLog(@"Attempting to lock %@", self.advisoryLockPath);
        fd = open(self.advisoryLockPath.UTF8String, O_CREAT | O_TRUNC | O_EXLOCK | O_NONBLOCK, 0600);
    } while (fd < 0 && errno == EINTR);
    if (fd >= 0) {
        RLog(@"Lock acquired");
        _advisoryLock = [[NSFileHandle alloc] initWithFileDescriptor:fd closeOnDealloc:YES];
        return YES;
    } else {
        RLog(@"Failed: %s", strerror(errno));
    }
    return NO;
}

- (NSError *)lastError {
    if (_db != NULL) {
        [self recordSqliteError];
    }
    return _lastError ?: [self notOpenError];
}

- (void)beginDeferredTransaction {
    [self executeUpdate:@"BEGIN DEFERRED TRANSACTION"];
}

- (void)commit {
    [self executeUpdate:@"COMMIT TRANSACTION"];
}

- (void)rollback {
    [self executeUpdate:@"ROLLBACK TRANSACTION"];
}

- (BOOL)transaction:(BOOL (^ NS_NOESCAPE)(void))block {
    if (![self executeUpdate:@"BEGIN DEFERRED TRANSACTION"]) {
        return NO;
    }
    DLog(@"Begin transaction");
    BOOL result;
    if (block()) {
        DLog(@"Commit");
        result = [self executeUpdate:@"COMMIT TRANSACTION"];
        if (!result) {
            RLog(@"error in commit: %@", self.lastError);
        }
    } else {
        DLog(@"Rollback: %@", self.lastError);
        [self executeUpdate:@"ROLLBACK TRANSACTION"];
        result = NO;
    }
    return result;
}

- (nonnull NSURL *)url {
    return _url;
}

@end
