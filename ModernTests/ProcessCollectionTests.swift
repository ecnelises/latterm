//
//  ProcessCollectionTests.swift
//  ModernTests
//

import XCTest
@testable import iTerm2SharedARC

final class ProcessCollectionTests: XCTestCase {
    private final class FakeProcessDataSource: NSObject, ProcessDataSource {
        var foregroundPIDs = Set<pid_t>()

        func nameOfProcess(withPid pid: pid_t,
                           isForeground: UnsafeMutablePointer<ObjCBool>) -> String? {
            isForeground.pointee = ObjCBool(foregroundPIDs.contains(pid))
            return "process-\(pid)"
        }

        func commandLineArguments(forProcess pid: pid_t,
                                  execName: AutoreleasingUnsafeMutablePointer<NSString>?) -> [String]? {
            return ["process-\(pid)"]
        }

        func startTime(forProcess pid: pid_t) -> Date? {
            return nil
        }

        func ttyRdev(forFileDescriptor fd: Int32, ofProcess pid: pid_t) -> dev_t {
            return 0
        }
    }

    private typealias Node = (pid: pid_t, parentPID: pid_t, isForeground: Bool)

    private func makeCollection(_ nodes: [Node]) -> ProcessCollection {
        let dataSource = FakeProcessDataSource()
        dataSource.foregroundPIDs = Set(nodes.compactMap { node in
            node.isForeground ? node.pid : nil
        })
        let collection = ProcessCollection(dataSource: dataSource)
        for node in nodes {
            collection.addProcess(withProcessID: node.pid, parentProcessID: node.parentPID)
        }
        collection.commit()
        return collection
    }

    func testIndependentTreesFindTheirDeepestForegroundJobs() {
        let collection = makeCollection([
            (2, 1, false),
            (3, 2, true),
            (10, 9, false),
            (11, 10, true),
        ])

        XCTAssertEqual(collection.info(forProcessID: 2)?.deepestForegroundJob?.processID, 3)
        XCTAssertEqual(collection.info(forProcessID: 11)?.deepestForegroundJob?.processID, 11)
    }

    func testDeepestForegroundJobAcrossBranches() {
        let collection = makeCollection([
            (1, 0, false),
            (2, 1, false),
            (3, 1, false),
            (4, 3, true),
            (5, 1, false),
            (6, 5, false),
            (8, 6, true),
        ])

        XCTAssertEqual(collection.info(forProcessID: 1)?.deepestForegroundJob?.processID, 8)
        XCTAssertNil(collection.info(forProcessID: 2)?.deepestForegroundJob)
        XCTAssertEqual(collection.info(forProcessID: 3)?.deepestForegroundJob?.processID, 4)
        XCTAssertEqual(collection.info(forProcessID: 4)?.deepestForegroundJob?.processID, 4)
        XCTAssertEqual(collection.info(forProcessID: 5)?.deepestForegroundJob?.processID, 8)
        XCTAssertEqual(collection.info(forProcessID: 6)?.deepestForegroundJob?.processID, 8)
        XCTAssertEqual(collection.info(forProcessID: 8)?.deepestForegroundJob?.processID, 8)
    }

    func testTreeWithoutForegroundJobsReturnsNil() {
        let collection = makeCollection([
            (1, 0, false),
            (2, 1, false),
            (3, 1, false),
            (4, 3, false),
            (5, 1, false),
            (6, 5, false),
            (8, 6, false),
        ])

        for pid in [1, 2, 3, 4, 5, 6, 8] as [pid_t] {
            XCTAssertNil(collection.info(forProcessID: pid)?.deepestForegroundJob)
        }
    }

    func testCycleInvalidatesOnlyBranchesThatReachIt() {
        let collection = makeCollection([
            (1, 8, false),
            (2, 1, false),
            (3, 1, false),
            (4, 3, true),
            (5, 1, false),
            (6, 5, false),
            (8, 6, true),
        ])

        XCTAssertNil(collection.info(forProcessID: 1)?.deepestForegroundJob)
        XCTAssertNil(collection.info(forProcessID: 2)?.deepestForegroundJob)
        XCTAssertEqual(collection.info(forProcessID: 3)?.deepestForegroundJob?.processID, 4)
        XCTAssertEqual(collection.info(forProcessID: 4)?.deepestForegroundJob?.processID, 4)
        XCTAssertNil(collection.info(forProcessID: 5)?.deepestForegroundJob)
        XCTAssertNil(collection.info(forProcessID: 6)?.deepestForegroundJob)
        XCTAssertNil(collection.info(forProcessID: 8)?.deepestForegroundJob)
    }

    func testNestedForegroundJobsPreferTheDeepestOne() {
        let collection = makeCollection([
            (1, 0, false),
            (2, 1, true),
            (3, 2, true),
        ])

        XCTAssertEqual(collection.info(forProcessID: 1)?.deepestForegroundJob?.processID, 3)
    }
}
