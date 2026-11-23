//
//  iTermThreadSafety.m
//  iTerm2
//
//  Created by George Nachman on 3/14/20.
//

#import "iTermThreadSafety.h"

#import "DebugLogging.h"
#import "NSArray+iTerm.h"
#import "NSObject+iTerm.h"

#define CHECK_DOUBLE_INVOKES BETA

@interface iTermSynchronizedState()
@property (atomic) BOOL ready;
@end

@implementation iTermSynchronizedState

- (instancetype)initWithQueue:(dispatch_queue_t)queue {
    self = [super init];
    if (self) {
        _queue = queue;
    }
    return self;
}

- (id)state {
    [self check];
    return self;
}

- (void)check {
    if (self.ready) {
        dispatch_assert_queue(self.queue);
    }
}

@end

@implementation iTermMainThreadState
+ (instancetype)uncheckedSharedInstance {
    static iTermMainThreadState *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[iTermMainThreadState alloc] initWithQueue:dispatch_get_main_queue()];
    });
    return instance;
}

+ (instancetype)sharedInstance {
    dispatch_assert_queue(dispatch_get_main_queue());
    return [self uncheckedSharedInstance];
}
@end

#if CHECK_DOUBLE_INVOKES
// Weak references to all iTermThread objects.
NSPointerArray *gThreads;
#endif

@implementation iTermThread {
    iTermSynchronizedState *_state;
    NSMutableArray *_deferred;
#if CHECK_DOUBLE_INVOKES
    NSArray<NSString *> *_stacks;
#endif
}

+ (instancetype)main {
    static iTermThread *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] initWithQueue:dispatch_get_main_queue()
                              stateFactory:
                ^iTermSynchronizedState * _Nullable(dispatch_queue_t  _Nonnull queue) {
            return [iTermMainThreadState uncheckedSharedInstance];
        }];
    });
    return instance;
}

+ (instancetype)withLabel:(NSString *)label
             stateFactory:(iTermThreadStateFactoryBlockType)stateFactory {
    return [[self alloc] initWithLabel:label stateFactory:stateFactory];
}

#if CHECK_DOUBLE_INVOKES
+ (iTermThread *)currentThread {
    @synchronized (gThreads) {
        for (iTermThread *thread in gThreads.allObjects) {
            if ([thread isCurrentQueue]) {
                return thread;
            }
        }
    }
    return nil;
}
#endif

- (instancetype)initWithQueue:(dispatch_queue_t)queue
                 stateFactory:(iTermThreadStateFactoryBlockType)stateFactory {
    self = [super init];
    if (self) {
        _queue = queue;
        dispatch_queue_set_specific(queue, &_queue, (void *)&_queue, NULL);
        _state = stateFactory(queue);
        _state.ready = YES;
#if CHECK_DOUBLE_INVOKES
        _stacks = @[];
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            gThreads = [NSPointerArray weakObjectsPointerArray];
        });
        @synchronized (gThreads) {
            [gThreads addPointer:(__bridge void *)self];
        }
#endif
    }
    return self;
}

+ (NSString *)uniqueQueueLabelWithName:(NSString *)label {
    static _Atomic int threadNumber;
    int i = threadNumber++;
    return [NSString stringWithFormat:@"%@.%d", label, i];
}

- (instancetype)initWithLabel:(NSString *)label
                 stateFactory:(iTermThreadStateFactoryBlockType)stateFactory {
    NSString *queueLabel = [iTermThread uniqueQueueLabelWithName:label];
    dispatch_queue_t queue = dispatch_queue_create(queueLabel.UTF8String, DISPATCH_QUEUE_SERIAL);
    return [self initWithQueue:queue stateFactory:stateFactory];
}

- (void)dealloc {
    dispatch_queue_set_specific(_queue, &_queue, NULL, NULL);
    assert(!_deferred);
}

- (BOOL)isCurrentQueue {
    return dispatch_get_specific(&_queue) == (void *)&_queue;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p queue=%@>",
            NSStringFromClass(self.class), self, _queue];
}

- (NSString *)label {
    return [NSString stringWithUTF8String:dispatch_queue_get_label(_queue)];
}

#if CHECK_DOUBLE_INVOKES
- (NSString *)stack {
    return [_stacks componentsJoinedByString:@"\n\n"];
}

- (NSArray<NSString *> *)currentStacks {
    NSArray *frames = [[NSThread callStackSymbols] subarrayFromIndex:1];
    frames = [@[ self.label ] arrayByAddingObjectsFromArray:frames];
    NSString *stack = [frames componentsJoinedByString:@"\n"];
    return [@[stack] arrayByAddingObjectsFromArray:_stacks];
}

- (NSString *)currentStack {
    return [self.currentStacks componentsJoinedByString:@"\n\n"];
}
#endif

- (void)performDeferredBlocksAfter:(void (^ NS_NOESCAPE)(void))block {
    @synchronized(self) {
        assert(!_deferred);
        _deferred = [NSMutableArray array];
    }
    block();
    while (YES) {
        NSArray *blocks = nil;
        @synchronized (self) {
            blocks = [_deferred copy];
            [_deferred removeAllObjects];
            if (blocks.count == 0) {
                _deferred = nil;
                break;
            }
        }
        for (void (^block)(id) in blocks) {
            [self dispatchSync:^(id  _Nullable state) {
                block(state);
            }];
        }
    }
}

- (void)dispatchAsync:(void (^)(id))block {
    @synchronized (self) {
        if (_deferred) {
            [_deferred addObject:[block copy]];
            return;
        }
    }
#if CHECK_DOUBLE_INVOKES
    NSArray *stacks = [[iTermThread currentThread] currentStacks] ?: @[ [[NSThread callStackSymbols]  componentsJoinedByString:@"\n"] ];
#endif
    dispatch_async(_queue, ^{
#if CHECK_DOUBLE_INVOKES
        NSArray *saved = self->_stacks;
        self->_stacks = stacks;
#endif
        [self check];
        block(self->_state);
#if CHECK_DOUBLE_INVOKES
        self->_stacks = saved;
#endif
    });
}

- (void)dispatchSync:(void (^ NS_NOESCAPE)(id))block {
    dispatch_assert_queue_not(_queue);
    dispatch_sync(_queue, ^{
        [self check];
        block(self->_state);
    });
}

- (void)dispatchRecursiveSync:(void (^ NS_NOESCAPE)(id))block {
    if ([self isCurrentQueue]) {
        [self check];
        block(_state);
    } else {
        [self dispatchSync:block];
    }
}

- (iTermCallback *)newCallbackWithBlock:(void (^)(id, id))callback {
    return [iTermCallback onThread:self block:callback];
}

- (iTermCallback *)newCallbackWithWeakTarget:(id)target selector:(SEL)selector userInfo:(id)userInfo {
    __weak id weakTarget = target;
    return [self newCallbackWithBlock:^(id  _Nonnull state, id  _Nullable value) {
        [weakTarget it_performNonObjectReturningSelector:selector
                                              withObject:state
                                                  object:value
                                                  object:userInfo];
    }];
}

- (void)check {
    dispatch_assert_queue(_queue);
}

@end

@implementation iTermCallback {
    void (^_block)(id, id);
    dispatch_group_t _group;
#if CHECK_DOUBLE_INVOKES
    NSString *_invokeStack;
    NSString *_creationStack;
    int _magic;
    NSMutableString *_debugInfo;
#endif
}

+ (instancetype)onThread:(iTermThread *)thread block:(void (^)(id, id))block {
    return [[self alloc] initWithThread:thread block:block];
}

- (instancetype)initWithThread:(iTermThread *)thread block:(void (^)(id, id))block {
    self = [super init];
    if (self) {
        _thread = thread;
        _block = [block copy];
        _group = dispatch_group_create();
        dispatch_group_enter(_group);
#if CHECK_DOUBLE_INVOKES
        _debugInfo = [[NSMutableString alloc] init];
        _magic = 0xdeadbeef;
        _creationStack = [[[NSThread callStackSymbols] componentsJoinedByString:@"\n"] copy];
#endif
    }
    return self;
}

#if CHECK_DOUBLE_INVOKES
- (void)dealloc {
    assert(_magic == 0xdeadbeef);
    _magic = 0;
}
#endif

- (void)finishWithState:(iTermSynchronizedState *)state object:(id)object callerStack:(NSString *)stack {
    [_thread check];
#if CHECK_DOUBLE_INVOKES
    ITAssertWithMessage(!_invokeStack, @"Previously invoked from:\n%@\n\nNow invoked from:\n%@\n\nCreated from:\n%@\n%@",
                        _invokeStack, stack, _creationStack, _debugInfo);
    _invokeStack = [stack copy];
#endif
#if DEBUG
    if (self.trace) {
        DLog(@"Callback on %@ from %@", _thread.label, stack);
    }
#endif
    _block(state, object);
    dispatch_group_leave(_group);
}

- (NSString *)callerStack {
#if CHECK_DOUBLE_INVOKES
    return [[iTermThread currentThread] currentStack] ?: [[NSThread callStackSymbols] componentsJoinedByString:@"\n"];
#else
    return nil;
#endif
}

- (void)invokeWithObject:(id)object {
    NSString *stack = self.callerStack;
    [_thread dispatchAsync:^(iTermSynchronizedState *state) {
        [self finishWithState:state object:object callerStack:stack];
    }];
}

- (void)invokeMaybeImmediatelyWithObject:(id)object {
    NSString *stack = self.callerStack;
    [_thread dispatchRecursiveSync:^(iTermSynchronizedState *state) {
        [self finishWithState:state object:object callerStack:stack];
    }];
}

- (void)waitUntilInvoked {
    dispatch_group_wait(_group, DISPATCH_TIME_FOREVER);
}

- (void)addDebugInfo:(NSString *)debugInfo {
#if CHECK_DOUBLE_INVOKES
    [_debugInfo appendString:debugInfo];
    [_debugInfo appendString:@"\n"];
#endif
}

@end

@implementation iTermThreadChecker {
    __weak iTermThread *_thread;
}

- (instancetype)initWithThread:(iTermThread *)thread {
    self = [super init];
    if (self) {
        _thread = thread;
    }
    return self;
}

- (void)check {
    [_thread check];
}

@end
