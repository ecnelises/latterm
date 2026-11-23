#import <XCTest/XCTest.h>
#import "iTermFileDescriptorMultiClientState.h"
#import "iTermThreadSafety.h"

@interface CheckedConnectionState : iTermFileDescriptorMultiClientState
@property (nonatomic) NSUInteger checkCount;
@end

@implementation CheckedConnectionState
- (void)check {
    [super check];
    self.checkCount++;
}
@end

@interface ThreadCallbackLifetimeTests : XCTestCase
@end

@implementation ThreadCallbackLifetimeTests

- (void)testStateCanBeHandedOffAndChecksReadsAndWritesOnReturn {
    dispatch_queue_t queue = dispatch_queue_create("latterm.tests.connection-state", DISPATCH_QUEUE_SERIAL);
    iTermThread *thread = [[iTermThread alloc] initWithQueue:queue stateFactory:^iTermSynchronizedState *(dispatch_queue_t owner) {
        return [[CheckedConnectionState alloc] initWithQueue:owner];
    }];
    __block CheckedConnectionState *handedOff;
    [thread dispatchSync:^(CheckedConnectionState *state) {
        handedOff = state;
    }];
    iTermCallback *callback = [thread newCallbackWithBlock:^(CheckedConnectionState *state, id value) {
        XCTAssertEqual(value, state);
        NSUInteger checks = state.checkCount;
        state.serverPID = 42;
        XCTAssertGreaterThan(state.checkCount, checks);
        checks = state.checkCount;
        XCTAssertEqual(state.serverPID, 42);
        XCTAssertGreaterThan(state.checkCount, checks);
    }];
    [callback invokeMaybeImmediatelyWithObject:handedOff];
}

- (void)testRecursiveCallbackUsesItsOwningQueueWhenLabelsMatch {
    dispatch_queue_t sender = dispatch_queue_create("latterm.callback", DISPATCH_QUEUE_SERIAL);
    dispatch_queue_t receiver = dispatch_queue_create("latterm.callback", DISPATCH_QUEUE_SERIAL);
    iTermThread *thread = [[iTermThread alloc] initWithQueue:receiver stateFactory:^iTermSynchronizedState *(dispatch_queue_t owner) {
        return [[iTermSynchronizedState alloc] initWithQueue:owner];
    }];
    __block NSInteger deliveries = 0;
    dispatch_sync(sender, ^{
        iTermCallback *callback = [thread newCallbackWithBlock:^(iTermSynchronizedState *state, id value) {
            dispatch_assert_queue(receiver);
            XCTAssertEqual(state.state, state);
            [thread dispatchRecursiveSync:^(id nestedState) {
                XCTAssertEqual(nestedState, state);
                deliveries++;
            }];
        }];
        [callback invokeMaybeImmediatelyWithObject:nil];
    });
    XCTAssertEqual(deliveries, 1);
}

- (void)testDeferringWorkDoesNotKeepTheQueueOwnerAliveAfterItDrains {
    __weak iTermThread *weakThread;
    __block NSInteger calls = 0;
    @autoreleasepool {
        iTermThread *thread = [iTermThread withLabel:@"latterm.tests.deferred"
                                       stateFactory:^iTermSynchronizedState *(dispatch_queue_t queue) {
            return [[iTermSynchronizedState alloc] initWithQueue:queue];
        }];
        weakThread = thread;
        [thread performDeferredBlocksAfter:^{
            [thread dispatchAsync:^(id state) {
                [state check];
                calls++;
            }];
            XCTAssertEqual(calls, 0);
        }];
        XCTAssertEqual(calls, 1);
    }
    XCTAssertNil(weakThread);
}

- (void)testQueuedInvocationKeepsCallbackAndPayloadAliveUntilDelivery {
    dispatch_queue_t queue = dispatch_queue_create("latterm.tests.callback", DISPATCH_QUEUE_SERIAL);
    iTermThread *thread = [[iTermThread alloc] initWithQueue:queue stateFactory:^iTermSynchronizedState *(dispatch_queue_t owner) {
        return [[iTermSynchronizedState alloc] initWithQueue:owner];
    }];
    XCTestExpectation *delivered = [self expectationWithDescription:@"callback delivered"];
    dispatch_suspend(queue);
    __weak iTermCallback *weakCallback;
    __weak NSObject *weakValue;
    @autoreleasepool {
        NSObject *value = [[NSObject alloc] init];
        weakValue = value;
        __weak NSObject *expectedValue = value;
        iTermCallback *callback = [thread newCallbackWithBlock:^(iTermSynchronizedState *state, id result) {
            dispatch_assert_queue(queue);
            XCTAssertEqual(state.state, state);
            XCTAssertEqual(result, expectedValue);
            [delivered fulfill];
        }];
        weakCallback = callback;
        [callback invokeWithObject:value];
    }
    XCTAssertNotNil(weakCallback);
    XCTAssertNotNil(weakValue);
    dispatch_resume(queue);
    [self waitForExpectations:@[delivered] timeout:10];
    dispatch_sync(queue, ^{});
    XCTAssertNil(weakCallback);
    XCTAssertNil(weakValue);
}

@end
