//
//  SCPFile.m
//  iTerm
//
//  Created by George Nachman on 12/21/13.
//
//

#import "SCPFile.h"
#import "iTermUserDefaults.h"

#include <sys/stat.h>

#import "DebugLogging.h"
#import "ITAddressBookMgr.h"
#import "NSData+iTerm.h"
#import "NSFileManager+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSStringITerm.h"
#import "NSWorkspace+iTerm.h"
#import "ProfileModel.h"
#import "iTermOpenDirectory+MainApp.h"
#import "iTermSlowOperationGateway.h"
#import "iTermWarning.h"

static NSString *const kSCPFileErrorDomain = @"com.googlecode.iterm2.SCPFile";
static NSString *const SCPFileKnownHostsUserDefaultsKey = @"NoSyncKnownHosts";

static NSError *SCPFileError(NSString *description) {
    return [NSError errorWithDomain:kSCPFileErrorDomain
                               code:1
                           userInfo:@{ NSLocalizedDescriptionKey: description ?: @"Secure copy failed" }];
}

static NSString *SCPQuoteConfigPath(NSString *path) {
    NSString *escaped = [path stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
    return [NSString stringWithFormat:@"\"%@\"", escaped];
}

@interface iTermAuthSock : NSObject
@property (nonatomic, readonly, nullable) NSString *authSock;
+ (instancetype)sharedInstance;
@end

@implementation iTermAuthSock {
    NSString *_authSock;
    dispatch_group_t _group;
}

+ (instancetype)sharedInstance {
    static iTermAuthSock *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (NSString *)authSock {
    NSString *existing = NSProcessInfo.processInfo.environment[@"SSH_AUTH_SOCK"];
    if (existing.length > 0) {
        return existing;
    }
    Profile *profile = [[ProfileModel sharedInstance] defaultBookmark];
    NSString *shell = [ITAddressBookMgr customShellForProfile:profile] ?: [iTermOpenDirectory userShell] ?: @"/bin/bash";
    dispatch_group_t group;
    BOOL request = NO;
    @synchronized(self) {
        if (_authSock) {
            return _authSock;
        }
        if (!_group) {
            _group = dispatch_group_create();
            request = YES;
        }
        group = _group;
    }
    if (request) {
        dispatch_group_enter(group);
        DLog(@"Try to get the value of $SSH_AUTH_SOCK");
        [[iTermSlowOperationGateway sharedInstance] exfiltrateEnvironmentVariableNamed:@"SSH_AUTH_SOCK"
                                                                                 shell:shell
                                                                            completion:^(NSString * _Nullable value) {
            @synchronized(self) {
                self->_authSock = [value copy];
            }
            dispatch_group_leave(group);
            DLog(@"Value is %@", value);
        }];
    }
    dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)));
    @synchronized(self) {
        return _authSock;
    }
}

@end

@interface SCPFile ()
@property(atomic, assign) BOOL stopped;
@property(atomic, copy) NSString *error;
@property(atomic, copy) NSString *destination;
@property(nonatomic, strong) dispatch_queue_t queue;
@property(atomic, strong, nullable) NSTask *runningTask;
@property(atomic, copy, nullable) NSString *askpassDirectory;
@end

@implementation SCPFile {
    BOOL _downloading;
    dispatch_queue_t _queue;
    NSString *_tempArchivePath;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _queue = dispatch_queue_create("com.googlecode.iterm2.SCPFile", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)setQueue:(dispatch_queue_t)queue {
    @synchronized(self) {
        _queue = queue;
    }
}

- (dispatch_queue_t)queue {
    @synchronized(self) {
        return _queue;
    }
}

- (NSString *)displayName {
    return [NSString stringWithFormat:@"Secure copy\nUser name: %@\nHost: %@\nFile: %@",
            _path.username, _path.hostname, _path.path];
}

- (NSString *)shortName {
    return [[self.path.path pathComponents] lastObject];
}

- (NSString *)subheading {
    if (self.path.username.length > 0) {
        return [NSString stringWithFormat:@"%@@%@:%@", self.path.username, self.path.hostname, self.path.path];
    }
    return [NSString stringWithFormat:@"%@:%@", self.path.hostname, self.path.path];
}

+ (NSString *)fileNameForPath:(NSString *)path {
    NSArray<NSString *> *components = [path pathComponents];
    if (!components.count) {
        return nil;
    }
    return [components lastObject];
}

- (NSString *)authRequestor {
    if (_path.username.length > 0) {
        return [NSString stringWithFormat:@"%@@%@", _path.username, _path.hostname];
    }
    return _path.hostname;
}

- (NSString *)protocolName {
    return @"secure copy";
}

- (NSString *)hostname {
    NSArray<NSString *> *hostComponents = [self.path.hostname componentsSeparatedByString:@":"];
    const NSInteger components = [hostComponents count];

    if (components == 2) {
        return hostComponents[0];
    } else if (components >= 4 &&
               [hostComponents[0] hasPrefix:@"["] &&
               [hostComponents[components - 2] hasSuffix:@"]"]) {
        hostComponents = [hostComponents subarrayWithRange:NSMakeRange(0, components - 1)];
        NSString *bracketedHostname = [hostComponents componentsJoinedByString:@":"];
        return [bracketedHostname substringWithRange:NSMakeRange(1, bracketedHostname.length - 2)];
    }

    return self.path.hostname;
}

- (nullable NSNumber *)explicitPort {
    NSArray<NSString *> *hostComponents = [self.path.hostname componentsSeparatedByString:@":"];
    const NSInteger components = [hostComponents count];
    if (components == 2 ||
        (components >= 4 &&
         [hostComponents[0] hasPrefix:@"["] &&
         [hostComponents[components - 2] hasSuffix:@"]"])) {
        NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
        formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US"];
        NSNumber *parsed = [formatter numberFromString:[hostComponents lastObject]];
        if (parsed.intValue > 0 && parsed.intValue <= 65535) {
            return parsed;
        }
    }
    return nil;
}

- (int)port {
    return [self explicitPort].intValue ?: 22;
}

- (NSURL *)sourceURL {
    NSURLComponents *components = [[NSURLComponents alloc] init];
    components.scheme = @"ssh";
    components.host = [self hostname];
    if (self.path.username.length > 0) {
        components.user = self.path.username;
    }
    NSNumber *explicitPort = [self explicitPort];
    if (explicitPort) {
        components.port = explicitPort;
    }
    components.path = [self.path.path hasPrefix:@"/"]
        ? self.path.path
        : [@"/" stringByAppendingString:(self.path.path ?: @"")];
    return components.URL;
}

- (NSString *)remoteTargetSpec {
    NSString *host = [self hostname] ?: @"";
    const BOOL isIPv6 = [host containsString:@":"];
    NSString *formattedHost = isIPv6 ? [NSString stringWithFormat:@"[%@]", host] : host;
    NSString *userPrefix = self.path.username.length > 0
        ? [NSString stringWithFormat:@"%@@", self.path.username]
        : @"";
    return [NSString stringWithFormat:@"%@%@:%@", userPrefix, formattedHost, self.path.path ?: @""];
}

// Don't call this on the main thread!
- (NSString *)keyboardInteractiveRequest:(NSString *)prompt {
    __block NSString *value = nil;
    dispatch_group_t group = dispatch_group_create();
    dispatch_group_enter(group);
    dispatch_async(dispatch_get_main_queue(), ^{
        [[FileTransferManager sharedInstance] transferrableFile:self
                                              interactivePrompt:prompt
                                                     completion:^(NSString *result) {
            value = [result copy];
            dispatch_group_leave(group);
        }];
    });
    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    return value;
}

- (void)performOnMainThread:(void (^ NS_NOESCAPE)(void))block {
    dispatch_group_t group = dispatch_group_create();
    dispatch_group_enter(group);
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSTimer scheduledTimerWithTimeInterval:0 repeats:NO block:^(NSTimer * _Nonnull timer) {
            block();
            dispatch_group_leave(group);
        }];
    });
    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
}

- (NSString *)tempFileName {
    return [NSString stringWithFormat:@".iTerm2.%@", [NSString uuid]];
}

- (nullable NSString *)createAskpassDirectoryWithHelperPath:(NSString * _Nullable * _Nonnull)helperPathOut
                                             mergedSSHConfig:(NSString * _Nullable * _Nonnull)sshConfigOut {
    NSString *templateStr = [NSTemporaryDirectory() stringByAppendingPathComponent:@"latterm-scp.XXXXXX"];
    NSMutableData *buf = [[templateStr dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
    char nullByte = '\0';
    [buf appendBytes:&nullByte length:1];
    char *created = mkdtemp(buf.mutableBytes);
    if (!created) {
        return nil;
    }
    chmod(created, S_IRWXU);
    NSString *dir = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:created
                                                                                length:strlen(created)];
    NSString *scriptPath = [dir stringByAppendingPathComponent:@"askpass.sh"];
    NSString *script =
        @"#!/bin/sh\n"
        @"DIR=\"$LATTERM_ASKPASS_DIR\"\n"
        @"[ -n \"$DIR\" ] || exit 1\n"
        @"printf '%s' \"$1\" > \"$DIR/prompt.tmp\" && /bin/mv \"$DIR/prompt.tmp\" \"$DIR/prompt\"\n"
        @"while [ ! -f \"$DIR/reply\" ] && [ ! -f \"$DIR/cancel\" ]; do\n"
        @"  /bin/sleep 0.05\n"
        @"done\n"
        @"if [ -f \"$DIR/cancel\" ]; then\n"
        @"  /bin/rm -f \"$DIR/cancel\"\n"
        @"  exit 1\n"
        @"fi\n"
        @"/bin/cat \"$DIR/reply\"\n"
        @"/bin/rm -f \"$DIR/reply\"\n";

    NSError *writeErr = nil;
    if (![script writeToFile:scriptPath atomically:YES encoding:NSUTF8StringEncoding error:&writeErr]) {
        [[NSFileManager defaultManager] removeItemAtPath:dir error:nil];
        return nil;
    }
    chmod(scriptPath.fileSystemRepresentation, S_IRWXU);
    *helperPathOut = scriptPath;

    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *appSupportConfig = [[fm applicationSupportDirectory] stringByAppendingPathComponent:@"ssh_config"];
    if (appSupportConfig.length > 0 && [fm fileExistsAtPath:appSupportConfig]) {
        NSMutableArray<NSString *> *includes = [NSMutableArray array];
        [includes addObject:[NSString stringWithFormat:@"Include %@", SCPQuoteConfigPath(appSupportConfig)]];
        NSString *userConfig = [@"~/.ssh/config" stringByExpandingTildeInPath];
        if (userConfig.length > 0 && [fm fileExistsAtPath:userConfig]) {
            [includes addObject:[NSString stringWithFormat:@"Include %@", SCPQuoteConfigPath(userConfig)]];
        }
        if ([fm fileExistsAtPath:@"/etc/ssh/ssh_config"]) {
            [includes addObject:@"Include \"/etc/ssh/ssh_config\""];
        } else if ([fm fileExistsAtPath:@"/etc/ssh_config"]) {
            [includes addObject:@"Include \"/etc/ssh_config\""];
        }
        NSString *mergedPath = [dir stringByAppendingPathComponent:@"ssh_config"];
        NSString *mergedContent = [[includes componentsJoinedByString:@"\n"] stringByAppendingString:@"\n"];
        if ([mergedContent writeToFile:mergedPath atomically:YES encoding:NSUTF8StringEncoding error:nil]) {
            chmod(mergedPath.fileSystemRepresentation, S_IRUSR | S_IWUSR);
            *sshConfigOut = mergedPath;
        }
    }

    return dir;
}

- (void)writeAskpassReply:(nullable NSString *)reply inDirectory:(NSString *)dir {
    if (!reply || self.stopped) {
        NSString *cancelPath = [dir stringByAppendingPathComponent:@"cancel"];
        [@"" writeToFile:cancelPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        return;
    }
    NSString *tmpReply = [dir stringByAppendingPathComponent:@"reply.tmp"];
    NSString *finalReply = [dir stringByAppendingPathComponent:@"reply"];
    NSData *payload = [[reply stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
    if ([payload writeToFile:tmpReply options:NSDataWritingAtomic error:nil]) {
        chmod(tmpReply.fileSystemRepresentation, S_IRUSR | S_IWUSR);
        [[NSFileManager defaultManager] moveItemAtPath:tmpReply toPath:finalReply error:nil];
    } else {
        NSString *cancelPath = [dir stringByAppendingPathComponent:@"cancel"];
        [@"" writeToFile:cancelPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
}

- (void)handlePendingAskpassPromptInDirectory:(NSString *)dir {
    NSString *promptPath = [dir stringByAppendingPathComponent:@"prompt"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:promptPath]) {
        return;
    }
    NSString *prompt = [NSString stringWithContentsOfFile:promptPath
                                                 encoding:NSUTF8StringEncoding
                                                    error:nil] ?: @"Password:";
    [[NSFileManager defaultManager] removeItemAtPath:promptPath error:nil];

    if (self.stopped) {
        [self writeAskpassReply:nil inDirectory:dir];
        return;
    }

    if ([prompt localizedCaseInsensitiveContainsString:@"(yes/no"]) {
        __block BOOL confirmed = NO;
        NSString *title = [NSString stringWithFormat:@"Confirm Connection to %@", [self hostname]];
        [self performOnMainThread:^{
            confirmed = [[FileTransferManager sharedInstance] transferrableFile:self
                                                                          title:title
                                                                 confirmMessage:prompt];
        }];
        if (confirmed && !self.stopped) {
            [self writeAskpassReply:@"yes" inDirectory:dir];
        } else {
            self.stopped = YES;
            [self writeAskpassReply:nil inDirectory:dir];
        }
        return;
    }

    NSString *answer = [self keyboardInteractiveRequest:prompt];
    if (!answer || self.stopped) {
        self.stopped = YES;
        [self writeAskpassReply:nil inDirectory:dir];
        return;
    }
    [self writeAskpassReply:answer inDirectory:dir];
}

- (BOOL)runSCPDownload:(BOOL)isDownload
             localFile:(NSString *)localFile
                 error:(NSError * _Nullable * _Nonnull)errorOut {
    NSString *askpassHelper = nil;
    NSString *mergedSSHConfig = nil;
    NSString *askpassDir = [self createAskpassDirectoryWithHelperPath:&askpassHelper
                                                      mergedSSHConfig:&mergedSSHConfig];
    if (!askpassDir || !askpassHelper) {
        if (errorOut) {
            *errorOut = SCPFileError(@"Could not initialize authentication helper");
        }
        return NO;
    }
    self.askpassDirectory = askpassDir;

    NSMutableArray<NSString *> *args = [NSMutableArray arrayWithObjects:@"-p", @"-q", nil];
    if (mergedSSHConfig) {
        [args addObjectsFromArray:@[ @"-F", mergedSSHConfig ]];
    }
    if (self.path.username.length > 0) {
        // Explicit port when encoded in hostname (e.g. host:2222 or [::1]:2222).
    }
    NSNumber *explicitPort = [self explicitPort];
    if (explicitPort) {
        [args addObjectsFromArray:@[ @"-P", explicitPort.stringValue ]];
    }
    [args addObjectsFromArray:@[ @"-o", @"BatchMode=no", @"--" ]];
    if (isDownload) {
        [args addObjectsFromArray:@[ [self remoteTargetSpec], localFile ]];
    } else {
        [args addObjectsFromArray:@[ localFile, [self remoteTargetSpec] ]];
    }

    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/scp"];
    task.arguments = args;
    task.standardInput = [NSFileHandle fileHandleWithNullDevice];
    NSPipe *stderrPipe = [NSPipe pipe];
    task.standardOutput = [NSFileHandle fileHandleWithNullDevice];
    task.standardError = stderrPipe;

    NSMutableDictionary<NSString *, NSString *> *env =
        [NSProcessInfo.processInfo.environment mutableCopy] ?: [NSMutableDictionary dictionary];
    env[@"SSH_ASKPASS"] = askpassHelper;
    env[@"SSH_ASKPASS_REQUIRE"] = @"force";
    env[@"LATTERM_ASKPASS_DIR"] = askpassDir;
    if (!env[@"DISPLAY"]) {
        env[@"DISPLAY"] = @"latterm:0";
    }
    if (!env[@"SSH_AUTH_SOCK"]) {
        NSString *sock = [[iTermAuthSock sharedInstance] authSock];
        if (sock.length > 0) {
            env[@"SSH_AUTH_SOCK"] = sock;
        }
    }
    task.environment = env;

    dispatch_semaphore_t exitSemaphore = dispatch_semaphore_create(0);
    task.terminationHandler = ^(NSTask * _Nonnull finishedTask) {
        dispatch_semaphore_signal(exitSemaphore);
    };

    NSError *launchError = nil;
    if (![task launchAndReturnError:&launchError]) {
        task.terminationHandler = nil;
        self.askpassDirectory = nil;
        [[NSFileManager defaultManager] removeItemAtPath:askpassDir error:nil];
        if (errorOut) {
            *errorOut = launchError ?: SCPFileError(@"Failed to launch /usr/bin/scp");
        }
        return NO;
    }
    self.runningTask = task;

    NSUInteger lastReportedBytes = 0;
    const int64_t pollIntervalNs = 50 * (int64_t)NSEC_PER_MSEC;
    while (YES) {
        if (self.stopped) {
            [self writeAskpassReply:nil inDirectory:askpassDir];
            [task terminate];
            break;
        }
        [self handlePendingAskpassPromptInDirectory:askpassDir];
        if (isDownload) {
            NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:localFile error:nil];
            NSUInteger currentBytes = [attrs fileSize];
            if (currentBytes != lastReportedBytes) {
                lastReportedBytes = currentBytes;
                self.bytesTransferred = currentBytes;
                [self performOnMainThread:^{
                    if (!self.stopped) {
                        [[FileTransferManager sharedInstance] transferrableFileProgressDidChange:self];
                    }
                }];
            }
        }
        if (dispatch_semaphore_wait(exitSemaphore, dispatch_time(DISPATCH_TIME_NOW, pollIntervalNs)) == 0) {
            break;
        }
    }

    [task waitUntilExit];
    self.runningTask = nil;
    self.askpassDirectory = nil;

    NSData *stderrData = [[stderrPipe fileHandleForReading] readDataToEndOfFile];
    [[NSFileManager defaultManager] removeItemAtPath:askpassDir error:nil];

    if (self.stopped) {
        if (errorOut) {
            *errorOut = SCPFileError(@"Canceled by user");
        }
        return NO;
    }

    if (task.terminationStatus != 0) {
        NSString *stderrText = [[[NSString alloc] initWithData:stderrData encoding:NSUTF8StringEncoding]
                                stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *message = stderrText.length > 0
            ? stderrText
            : (isDownload ? @"Download failed" : @"Upload failed");
        if (errorOut) {
            *errorOut = SCPFileError(message);
        }
        return NO;
    }

    if (isDownload) {
        NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:localFile error:nil];
        NSUInteger finalBytes = [attrs fileSize];
        self.bytesTransferred = finalBytes;
        self.fileSize = (NSInteger)finalBytes;
    } else {
        self.bytesTransferred = (NSUInteger)MAX((NSInteger)0, self.fileSize);
    }
    [self performOnMainThread:^{
        if (!self.stopped) {
            [[FileTransferManager sharedInstance] transferrableFileProgressDidChange:self];
        }
    }];
    return YES;
}

// This runs on _queue.
- (void)performTransferWrapper:(BOOL)isDownload {
    [self performTransfer:isDownload];

    if (_tempArchivePath) {
        DLog(@"Cleaning up temp archive: %@", _tempArchivePath);
        [[NSFileManager defaultManager] removeItemAtPath:_tempArchivePath error:nil];
        _tempArchivePath = nil;
    }
}

- (void)performTransfer:(BOOL)isDownload {
    NSString *baseName = [[self class] fileNameForPath:self.path.path];
    RLog(@"performTransfer download=%@ path=%@ baseName=%@", @(isDownload), self.path, baseName);
    if (!baseName) {
        self.error = [NSString stringWithFormat:@"Invalid path: %@", self.path.path];
        [self performOnMainThread:^{
            [[FileTransferManager sharedInstance] transferrableFile:self
                                     didFinishTransmissionWithError:SCPFileError(@"Invalid filename")];
        }];
        return;
    }

    NSURL *url = [self sourceURL];
    if (isDownload) {
        NSString *downloadDirectory = [[NSFileManager defaultManager] downloadsDirectory];
        NSString *tempfile = downloadDirectory
            ? [downloadDirectory stringByAppendingPathComponent:[self tempFileName]]
            : nil;
        if (!tempfile) {
            self.error = [NSString stringWithFormat:@"Downloads folder not writable. Tried %@", downloadDirectory];
            [self performOnMainThread:^{
                [[FileTransferManager sharedInstance] transferrableFile:self
                                         didFinishTransmissionWithError:SCPFileError(@"Downloads folder not writable")];
            }];
            return;
        }

        // Create and quarantine the destination file before any remote bytes are written.
        if (![[NSData data] writeToFile:tempfile options:NSDataWritingAtomic error:nil]) {
            self.error = [NSString stringWithFormat:@"Downloads folder not writable. Tried %@", downloadDirectory];
            [self performOnMainThread:^{
                [[FileTransferManager sharedInstance] transferrableFile:self
                                         didFinishTransmissionWithError:SCPFileError(@"Downloads folder not writable")];
            }];
            return;
        }
        chmod(tempfile.fileSystemRepresentation, S_IRUSR | S_IWUSR);
        if (![self quarantine:tempfile sourceURL:url]) {
            NSError *rmError = nil;
            const BOOL removed = [[NSFileManager defaultManager] removeItemAtPath:tempfile error:&rmError];
            if (!removed || rmError) {
                [self performOnMainThread:^{
                    [self failedToRemoveUnquarantinedFileAt:tempfile];
                }];
            }
            self.error = @"Quarantine Error";
            [self performOnMainThread:^{
                [[FileTransferManager sharedInstance] transferrableFile:self
                                         didFinishTransmissionWithError:SCPFileError(@"Quarantine Error")];
            }];
            return;
        }

        self.destination = tempfile;
        self.fileSize = -1;
        self.status = kTransferrableFileStatusTransferring;

        NSError *transferError = nil;
        const BOOL ok = [self runSCPDownload:YES localFile:tempfile error:&transferError];
        __block NSError *error = nil;
        __block NSString *finalDestination = nil;

        if (ok) {
            if (![self quarantine:tempfile sourceURL:url]) {
                NSError *rmError = nil;
                const BOOL removed = [[NSFileManager defaultManager] removeItemAtPath:tempfile error:&rmError];
                if (!removed || rmError) {
                    [self performOnMainThread:^{
                        [self failedToRemoveUnquarantinedFileAt:tempfile];
                    }];
                }
                self.error = @"Quarantine Error";
                error = SCPFileError(@"Quarantine Error");
            } else {
                [self performOnMainThread:^{
                    finalDestination = [self finalDestinationForPath:baseName
                                                destinationDirectory:downloadDirectory
                                                              prompt:YES];
                    if ([[NSFileManager defaultManager] fileExistsAtPath:finalDestination]) {
                        [[NSFileManager defaultManager] replaceItemAtURL:[NSURL fileURLWithPath:finalDestination]
                                                           withItemAtURL:[NSURL fileURLWithPath:tempfile]
                                                          backupItemName:nil
                                                                 options:0
                                                        resultingItemURL:nil
                                                                   error:&error];
                    } else {
                        [[NSFileManager defaultManager] moveItemAtPath:tempfile
                                                                toPath:finalDestination
                                                                 error:&error];
                    }
                }];
                if (error) {
                    self.error = error.localizedDescription;
                }
                [[NSFileManager defaultManager] removeItemAtPath:tempfile error:NULL];
                self.destination = finalDestination;
            }
        } else {
            [[NSFileManager defaultManager] removeItemAtPath:tempfile error:NULL];
            if (self.stopped) {
                [self performOnMainThread:^{
                    [[FileTransferManager sharedInstance] transferrableFileDidStopTransfer:self];
                }];
                return;
            }
            self.error = transferError.localizedDescription.length > 0
                ? transferError.localizedDescription
                : @"Download failed";
            error = transferError ?: SCPFileError(@"Download failed");
        }

        [self performOnMainThread:^{
            if (!error) {
                self.localPath = finalDestination;
            }
            [[FileTransferManager sharedInstance] transferrableFile:self
                                     didFinishTransmissionWithError:error];
        }];
        if (!error && self.successor) {
            SCPFile *scpSuccessor = (SCPFile *)self.successor;
            scpSuccessor.queue = self.queue;
            [scpSuccessor performTransferWrapper:isDownload];
        }
    } else {
        self.status = kTransferrableFileStatusTransferring;
        RLog(@"Upload “%@” to “%@”", [self localPath], self.path.path);
        NSError *transferError = nil;
        const BOOL ok = [self runSCPDownload:NO localFile:[self localPath] error:&transferError];
        NSError *error = nil;
        if (!ok) {
            if (self.stopped) {
                [self performOnMainThread:^{
                    [[FileTransferManager sharedInstance] transferrableFileDidStopTransfer:self];
                }];
                return;
            }
            self.error = transferError.localizedDescription.length > 0
                ? transferError.localizedDescription
                : @"Upload failed";
            error = transferError ?: SCPFileError(@"Upload failed");
        }
        [self performOnMainThread:^{
            [[FileTransferManager sharedInstance] transferrableFile:self
                                     didFinishTransmissionWithError:error];
        }];
        if (!error && self.successor) {
            SCPFile *scpSuccessor = (SCPFile *)self.successor;
            scpSuccessor.queue = self.queue;
            [scpSuccessor performTransferWrapper:isDownload];
        }
    }
}

- (NSString *)userHostPort {
    if (self.path.username.length > 0) {
        return [NSString stringWithFormat:@"%@@%@:%@", self.path.username, self.hostname, @(self.port)];
    }
    return [NSString stringWithFormat:@"%@:%@", self.hostname, @(self.port)];
}

- (BOOL)hostnameIsKnown {
    return [[[iTermUserDefaults userDefaults] objectForKey:SCPFileKnownHostsUserDefaultsKey]
            containsObject:self.userHostPort];
}

- (BOOL)shouldConnectToNewHostname {
    const iTermWarningSelection selection =
        [iTermWarning showWarningWithTitle:[NSString stringWithFormat:@"Connect to %@?", self.userHostPort]
                                   actions:@[ @"OK", @"Cancel" ]
                                 accessory:nil
                                identifier:[@"NoSyncConnectTo_" stringByAppendingString:self.userHostPort]
                               silenceable:kiTermWarningTypePermanentlySilenceable
                                   heading:@"Connect to New Host?"
                                    window:nil];
    return selection == kiTermWarningSelection0;
}

- (void)addKnownHost {
    NSArray<NSString *> *hosts = [[iTermUserDefaults userDefaults] objectForKey:SCPFileKnownHostsUserDefaultsKey] ?: @[];
    hosts = [hosts arrayByAddingObject:self.userHostPort];
    [[iTermUserDefaults userDefaults] setObject:hosts forKey:SCPFileKnownHostsUserDefaultsKey];
}

- (void)download {
    _downloading = YES;
    self.status = kTransferrableFileStatusStarting;
    [[[FileTransferManager sharedInstance] files] addObject:self];
    [[FileTransferManager sharedInstance] transferrableFileDidStartTransfer:self];

    if (!self.hasPredecessor) {
        if (![self hostnameIsKnown]) {
            if (![self shouldConnectToNewHostname]) {
                self.error = @"Canceled by user";
                [[FileTransferManager sharedInstance] transferrableFile:self
                                         didFinishTransmissionWithError:SCPFileError(@"Canceled by user")];
                return;
            }
            [self addKnownHost];
        }
        dispatch_async(self.queue, ^{
            [self performTransferWrapper:YES];
        });
    }
}

- (NSDictionary *)archiveDirectoryIfNeededWithAttributes:(NSDictionary *)attrs {
    NSString *fileType = attrs[NSFileType];
    if (![fileType isEqualToString:NSFileTypeDirectory]) {
        return attrs;
    }

    DLog(@"Uploading directory as tgz: %@", self.localPath);

    NSError *error = nil;
    _tempArchivePath = [NSData temporaryTGZArchiveOfDirectory:self.localPath error:&error];
    if (!_tempArchivePath) {
        self.error = error.localizedDescription;
        [[FileTransferManager sharedInstance] transferrableFile:self
                                 didFinishTransmissionWithError:error];
        return nil;
    }

    self.localPath = _tempArchivePath;
    self.path.path = [self.path.path stringByAppendingString:@".tgz"];

    return [[NSFileManager defaultManager] attributesOfItemAtPath:self.localPath error:nil];
}

- (void)upload {
    _downloading = NO;
    self.status = kTransferrableFileStatusStarting;

    NSError *attributesError = nil;
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:self.localPath
                                                                           error:&attributesError];
    if (attributesError) {
        RLog(@"Failed to get attributes for %@: %@", self.localPath, attributesError);
        self.error = [NSString stringWithFormat:@"Cannot read file: %@", attributesError.localizedDescription];
        [[FileTransferManager sharedInstance] transferrableFile:self
                                 didFinishTransmissionWithError:attributesError];
        return;
    }

    attrs = [self archiveDirectoryIfNeededWithAttributes:attrs];
    if (!attrs) {
        return;
    }

    self.fileSize = [attrs fileSize];
    DLog(@"upload: localPath=%@ fileSize=%@", self.localPath, @(self.fileSize));

    [[[FileTransferManager sharedInstance] files] addObject:self];
    [[FileTransferManager sharedInstance] transferrableFileDidStartTransfer:self];

    if (!self.hasPredecessor) {
        if (![self hostnameIsKnown]) {
            if (![self shouldConnectToNewHostname]) {
                self.error = @"Canceled by user";
                [[FileTransferManager sharedInstance] transferrableFile:self
                                         didFinishTransmissionWithError:SCPFileError(@"Canceled by user")];
                return;
            }
            [self addKnownHost];
        }
        dispatch_async(self.queue, ^{
            [self performTransferWrapper:NO];
        });
    }
}

- (BOOL)isDownloading {
    return _downloading;
}

- (void)stop {
    [[FileTransferManager sharedInstance] transferrableFileWillStop:self];
    self.stopped = YES;
    NSString *askpassDir = self.askpassDirectory;
    if (askpassDir.length > 0) {
        NSString *cancelPath = [askpassDir stringByAppendingPathComponent:@"cancel"];
        [@"" writeToFile:cancelPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
    NSTask *task = self.runningTask;
    if (task.isRunning) {
        [task terminate];
    }
}

@end
