import XCTest
@testable import iTerm2SharedARC

final class WindowNumberAllocatorTests: XCTestCase {
    func testLiveWindowsReceiveDistinctSequentialNumbers() {
        let allocator = TemporaryNumberAllocator()
        XCTAssertEqual((0..<100).map { _ in allocator.allocateNumber() }, Array(Int32(0)..<100))
    }

    func testClosingWindowsReusesLowestHoleBeforeGrowing() {
        let allocator = TemporaryNumberAllocator()
        let numbers = (0..<5).map { _ in allocator.allocateNumber() }
        allocator.deallocateNumber(numbers[3])
        allocator.deallocateNumber(numbers[1])
        XCTAssertEqual(allocator.allocateNumber(), 1)
        XCTAssertEqual(allocator.allocateNumber(), 3)
        XCTAssertEqual(allocator.allocateNumber(), 5)
    }

    func testClosingEveryWindowResetsSequence() {
        let allocator = TemporaryNumberAllocator()
        let numbers = (0..<5).map { _ in allocator.allocateNumber() }
        for number in numbers.reversed() {
            allocator.deallocateNumber(number)
        }
        XCTAssertEqual(allocator.allocateNumber(), 0)
        XCTAssertEqual(allocator.allocateNumber(), 1)
    }

    func testUnknownAndRepeatedReleasesDoNotAffectLiveNumbers() {
        let allocator = TemporaryNumberAllocator()
        XCTAssertEqual(allocator.allocateNumber(), 0)
        XCTAssertEqual(allocator.allocateNumber(), 1)
        allocator.deallocateNumber(-1)
        allocator.deallocateNumber(.max)
        allocator.deallocateNumber(20)
        XCTAssertEqual(allocator.allocateNumber(), 2)
        allocator.deallocateNumber(1)
        allocator.deallocateNumber(1)
        XCTAssertEqual(allocator.allocateNumber(), 1)
        XCTAssertEqual(allocator.allocateNumber(), 3)
    }

    func testProfilesHaveIndependentSequencesAndReuse() {
        let allocator = PerKeyNumberAllocator()
        XCTAssertEqual(allocator.allocate(forKey: "profile-a"), 0)
        XCTAssertEqual(allocator.allocate(forKey: "profile-a"), 1)
        XCTAssertEqual(allocator.allocate(forKey: "profile-b"), 0)
        allocator.deallocate(0, forKey: "profile-a")
        XCTAssertEqual(allocator.allocate(forKey: "profile-b"), 1)
        XCTAssertEqual(allocator.allocate(forKey: "profile-a"), 0)
        XCTAssertEqual(allocator.allocate(forKey: "profile-a"), 2)
    }

    func testReleaseForUnknownProfileDoesNotReserveOrReleaseOtherNumbers() {
        let allocator = PerKeyNumberAllocator()
        XCTAssertEqual(allocator.allocate(forKey: "existing"), 0)
        allocator.deallocate(0, forKey: "missing")
        XCTAssertEqual(allocator.allocate(forKey: "existing"), 1)
        XCTAssertEqual(allocator.allocate(forKey: "missing"), 0)
        // Empty keys are valid, independent scopes too.
        XCTAssertEqual(allocator.allocate(forKey: ""), 0)
        XCTAssertEqual(allocator.allocate(forKey: "missing"), 1)
    }

    func testLegacyAndPerProfileAllocationsStayIndependent() {
        let legacy = TemporaryNumberAllocator()
        let profiles = PerKeyNumberAllocator()
        XCTAssertEqual(legacy.allocateNumber(), 0)
        XCTAssertEqual(profiles.allocate(forKey: "profile"), 0)
        XCTAssertEqual(legacy.allocateNumber(), 1)
        profiles.deallocate(0, forKey: "profile")
        XCTAssertEqual(legacy.allocateNumber(), 2)
        XCTAssertEqual(profiles.allocate(forKey: "profile"), 0)
    }

    func testObjectiveCRuntimeContractAndSingletonRemainAvailable() {
        XCTAssertTrue(NSClassFromString("TemporaryNumberAllocator") === TemporaryNumberAllocator.self)
        XCTAssertTrue(TemporaryNumberAllocator.sharedInstance() === TemporaryNumberAllocator.sharedInstance())
        let allocator = TemporaryNumberAllocator()
        XCTAssertTrue(allocator.responds(to: NSSelectorFromString("allocateNumber")))
        XCTAssertTrue(allocator.responds(to: NSSelectorFromString("deallocateNumber:")))
    }
}
