//
//  iTermWeakReferenceTest.m
//  ModernTests
//
//  Created by George Nachman on 2/12/16.
//

#import <XCTest/XCTest.h>
#import "iTermSelectorSwizzler.h"
#import "iTermWeakReference.h"
#import <objc/runtime.h>

@interface iTermWeaklyReferenceableObject : NSObject<iTermWeaklyReferenceable>
@end

@implementation iTermWeaklyReferenceableObject

ITERM_WEAKLY_REFERENCEABLE

@end

@interface iTerm2FakeObject : NSObject<iTermWeaklyReferenceable>
@property(nonatomic, assign) int number;
@end

@implementation iTerm2FakeObject
ITERM_WEAKLY_REFERENCEABLE
@end

@interface iTermWeakReferenceTest : XCTestCase

@end

@interface WRTObject : NSObject<iTermWeaklyReferenceable>
@property(nonatomic, unsafe_unretained) iTermWeakReference *reference;
@property(nonatomic, assign) BOOL *okPointer;
@end

@implementation WRTObject

ITERM_WEAKLY_REFERENCEABLE

- (void)dealloc {
    *_okPointer = (_reference && _reference.weaklyReferencedObject == nil);
}

@end

@implementation iTermWeakReferenceTest

- (void)testSimpleCase {
    iTermWeaklyReferenceableObject *weakReference = nil;
    @autoreleasepool {
        iTermWeaklyReferenceableObject *object = [[iTermWeaklyReferenceableObject alloc] init];
        weakReference = [object weakSelf];
        XCTAssert([(id)weakReference weaklyReferencedObject] == object);
        object = nil;
    }
    XCTAssert([(id)weakReference weaklyReferencedObject] == nil);
}

- (void)testWeaklyReferencedObjectMethodBeforeDealloc {
    iTermWeaklyReferenceableObject *object = [[iTermWeaklyReferenceableObject alloc] init];
    iTermWeaklyReferenceableObject<iTermWeakReference> *weakReference = [object weakSelf];
    XCTAssertEqual(weakReference.weaklyReferencedObject, object);
}

- (void)testWeaklyReferencedObjectMethodAfterDealloc {
    iTermWeaklyReferenceableObject<iTermWeakReference> *weakReference = nil;
    @autoreleasepool {
        iTermWeaklyReferenceableObject *object = [[iTermWeaklyReferenceableObject alloc] init];
        weakReference = [object weakSelf];
        object = nil;
    }
    XCTAssertEqual(weakReference.weaklyReferencedObject, nil);
}

- (void)testWeaklyReferencedObjectDoesNotLeak {
    iTermWeaklyReferenceableObject<iTermWeakReference> *weakReference = nil;
    @autoreleasepool {
        iTermWeaklyReferenceableObject *object = [[iTermWeaklyReferenceableObject alloc] init];
        weakReference = [object weakSelf];
        XCTAssertEqual(weakReference.weaklyReferencedObject, object);
        object = nil;
    }
    XCTAssertEqual(weakReference.weaklyReferencedObject, nil);
}

- (void)testTwoWeakRefsToSameObject {
    iTermWeaklyReferenceableObject *weakReference1 = nil;
    iTermWeaklyReferenceableObject *weakReference2 = nil;
    @autoreleasepool {
        iTermWeaklyReferenceableObject *object = [[iTermWeaklyReferenceableObject alloc] init];
        weakReference1 = [object weakSelf];
        weakReference2 = [object weakSelf];

        XCTAssert([(id)weakReference1 weaklyReferencedObject] == object);
        XCTAssert([(id)weakReference2 weaklyReferencedObject] == object);
        object = nil;
    }
    XCTAssert([(id)weakReference1 weaklyReferencedObject] == nil);
    XCTAssert([(id)weakReference2 weaklyReferencedObject] == nil);
}

- (void)testReleaseWeakReferenceBeforeObject {
    iTermWeaklyReferenceableObject *object = [[iTermWeaklyReferenceableObject alloc] init];
    @autoreleasepool {
        iTermWeakReference *weakReference = [[iTermWeakReference alloc] initWithObject:object];
        XCTAssertNotNil(weakReference);
        weakReference = nil;
    }
    XCTAssertNotNil(object);
}

- (void)testReleaseTwoWeakReferencesBeforeObject {
    iTermWeaklyReferenceableObject *object = [[iTermWeaklyReferenceableObject alloc] init];
    @autoreleasepool {
        iTermWeakReference *weakReference1 = [[iTermWeakReference alloc] initWithObject:object];
        iTermWeakReference *weakReference2 = [[iTermWeakReference alloc] initWithObject:object];
        XCTAssertNotNil(weakReference1);
        XCTAssertNotNil(weakReference2);
        weakReference1 = nil;
        weakReference2 = nil;
    }
    XCTAssertNotNil(object);
}

- (void)testNullfiedAtStartOfDealloc {
    BOOL ok = NO;
    WRTObject *ref = nil;
    @autoreleasepool {
        WRTObject *object = [[WRTObject alloc] init];
        object.okPointer = &ok;
        ref = [object weakSelf];
        object.reference = (iTermWeakReference *)ref;
        object = nil;
    }
    XCTAssert(((iTermWeakReference *)ref).weaklyReferencedObject == nil, @"Reference's object not nullified");
    XCTAssert(ok, @"Reference's object nullified after start of object's dealloc");
}

- (void)testProxyForwardsExistingMethods {
    iTerm2FakeObject *fakeObject = [[iTerm2FakeObject alloc] init];
    fakeObject.number = 1234;
    iTerm2FakeObject *ref = [fakeObject weakSelf];
    XCTAssertEqual([ref number], 1234);
}

- (void)testProxyRaisesExceptionOnNonexistentMethods {
    iTerm2FakeObject *fakeObject = [[iTerm2FakeObject alloc] init];
    iTerm2FakeObject *ref = [fakeObject weakSelf];
    BOOL ok = NO;
    @try {
        [ref performSelector:@selector(testProxyRaisesExceptionOnNonexistentMethods)
                  withObject:nil];
    }
    @catch (NSException *e) {
        ok = YES;
    }
    XCTAssertTrue(ok);
}

- (void)testProxyReturnsZeroForFreedObject {
    iTerm2FakeObject *ref = nil;
    @autoreleasepool {
        iTerm2FakeObject *fakeObject = [[iTerm2FakeObject alloc] init];
        fakeObject.number = 1234;
        ref = [fakeObject weakSelf];
        fakeObject = nil;
    }
    int number = [ref number];
    XCTAssertEqual(number, 0);
}

- (void)testRaceConditions {
    dispatch_queue_t q1 = dispatch_queue_create("com.iterm2.WeakReferenceTest1", NULL);
    dispatch_queue_t q2 = dispatch_queue_create("com.iterm2.WeakReferenceTest2", NULL);
    dispatch_group_t startGroup = dispatch_group_create();
    dispatch_group_t doneGroup = dispatch_group_create();

    for (int i = 0; i < 500; i++) {
        __block iTermWeaklyReferenceableObject *object = [[iTermWeaklyReferenceableObject alloc] init];
        __block iTermWeakReference *ref = [[iTermWeakReference alloc] initWithObject:object];

        dispatch_group_enter(startGroup);

        dispatch_group_async(doneGroup, q1, ^{
            dispatch_group_wait(startGroup, DISPATCH_TIME_FOREVER);
            object = nil;
        });

        dispatch_group_async(doneGroup, q2, ^{
            dispatch_group_wait(startGroup, DISPATCH_TIME_FOREVER);
            ref = nil;
        });

        dispatch_group_leave(startGroup);
        dispatch_group_wait(doneGroup, DISPATCH_TIME_FOREVER);
    }
}

- (void)testRespondsToSelector {
    iTerm2FakeObject *fakeObject = [[iTerm2FakeObject alloc] init];
    fakeObject.number = 1234;
    iTerm2FakeObject *ref = [fakeObject weakSelf];
    XCTAssertTrue([ref respondsToSelector:@selector(number)]);
    XCTAssertTrue([ref respondsToSelector:@selector(weaklyReferencedObject)]);
    XCTAssertTrue([ref respondsToSelector:@selector(isEqual:)]);
    XCTAssertFalse([ref respondsToSelector:@selector(testRespondsToSelector)]);
}

@end
