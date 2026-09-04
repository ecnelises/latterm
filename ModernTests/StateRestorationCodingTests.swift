//
//  StateRestorationCodingTests.swift
//  ModernTests
//

import XCTest
@testable import iTerm2SharedARC

final class GraphTableTransformerTests: XCTestCase {
    private func archived(_ dictionary: [String: Any]) throws -> Data {
        try NSKeyedArchiver.archivedData(withRootObject: dictionary,
                                         requiringSecureCoding: true)
    }

    private func row(key: Any,
                     identifier: Any,
                     parent: Int,
                     rowID: Int,
                     data: Data = Data(),
                     generation: Int = 0,
                     hasLargeData: Bool = false) -> [Any] {
        [key, identifier, parent, rowID, data, generation, hasLargeData]
    }

    func testBuildsNestedGraphFromRows() throws {
        let rootPOD: [String: Any] = [
            "string": "value",
            "number": 123,
            "date": Date(timeIntervalSince1970: 1_000_000_000),
            "data": Data("xyz".utf8),
        ]
        let leafPOD = ["leaf": "value"]
        let rows = [
            row(key: "leaf", identifier: "", parent: 3, rowID: 5, data: try archived(leafPOD)),
            row(key: "branch", identifier: "first", parent: 2, rowID: 4),
            row(key: "branch", identifier: "second", parent: 2, rowID: 3),
            row(key: "container", identifier: "", parent: 1, rowID: 2),
            row(key: "", identifier: "", parent: 0, rowID: 1, data: try archived(rootPOD)),
        ]

        let transformer = iTermGraphTableTransformer(nodeRows: rows)
        let root = try XCTUnwrap(transformer.root)
        XCTAssertEqual(root.rowid, 1)
        XCTAssertEqual(root.pod["string"] as? String, "value")
        XCTAssertEqual(root.pod["number"] as? Int, 123)

        let container = try XCTUnwrap(root.childRecord(withKey: "container", identifier: ""))
        XCTAssertEqual(container.graphRecords.count, 2)
        XCTAssertNotNil(container.childRecord(withKey: "branch", identifier: "first"))

        let second = try XCTUnwrap(container.childRecord(withKey: "branch", identifier: "second"))
        let leaf = try XCTUnwrap(second.childRecord(withKey: "leaf", identifier: ""))
        XCTAssertEqual(leaf.pod["leaf"] as? String, "value")
    }

    func testRejectsRowWithMissingFields() {
        let transformer = iTermGraphTableTransformer(nodeRows: [["", ""]])

        XCTAssertNil(transformer.root)
        XCTAssertNotNil(transformer.lastError)
    }

    func testRejectsRowWithMistypedRequiredField() {
        let rows = [row(key: 666, identifier: "", parent: 0, rowID: 1)]
        let transformer = iTermGraphTableTransformer(nodeRows: rows)

        XCTAssertNil(transformer.root)
        XCTAssertNotNil(transformer.lastError)
    }

    func testRejectsMultipleRoots() {
        let rows = [
            row(key: "", identifier: "", parent: 0, rowID: 1),
            row(key: "", identifier: "", parent: 0, rowID: 2),
        ]
        let transformer = iTermGraphTableTransformer(nodeRows: rows)

        XCTAssertNil(transformer.root)
        XCTAssertNotNil(transformer.lastError)
    }

    func testRejectsDanglingParent() {
        let rows = [
            row(key: "", identifier: "", parent: 0, rowID: 1),
            row(key: "child", identifier: "", parent: 666, rowID: 2),
        ]
        let transformer = iTermGraphTableTransformer(nodeRows: rows)

        XCTAssertNil(transformer.root)
        XCTAssertNotNil(transformer.lastError)
    }
}

final class GraphDeltaArrayTests: XCTestCase {
    private func encodeArray(_ encoder: iTermGraphDeltaEncoder,
                             identifiers: [String],
                             generation: Int,
                             valuePrefix: String,
                             callback: (() -> Void)? = nil) {
        encoder.encodeArray(withKey: "items",
                            generation: generation,
                            identifiers: identifiers,
                            options: []) { identifier, index, itemEncoder, _ in
            callback?()
            itemEncoder.encode("\(valuePrefix)_\(identifier)_\(index)", forKey: "value")
            return true
        }
    }

    private func assignRowIDs(_ encoder: iTermGraphDeltaEncoder) {
        var nextRowID = 0
        _ = encoder.enumerateRecords { _, after, _, _, _ in
            guard let after, after.rowid == nil else {
                return
            }
            nextRowID += 1
            after.rowid = NSNumber(value: nextRowID)
        }
    }

    func testUnchangedArrayGenerationSkipsElementEncoding() {
        let initial = iTermGraphDeltaEncoder(previousRevision: nil)
        encodeArray(initial,
                    identifiers: ["one", "two", "three"],
                    generation: 1,
                    valuePrefix: "before")
        assignRowIDs(initial)

        let delta = iTermGraphDeltaEncoder(previousRevision: initial.record)
        var callbackCount = 0
        encodeArray(delta,
                    identifiers: ["one", "two", "three"],
                    generation: 1,
                    valuePrefix: "after") {
            callbackCount += 1
        }

        XCTAssertEqual(callbackCount, 0)
    }

    func testChangedArrayValuesAreEnumeratedAsUpdates() {
        let initial = iTermGraphDeltaEncoder(previousRevision: nil)
        let identifiers = ["one", "two", "three"]
        encodeArray(initial, identifiers: identifiers, generation: 1, valuePrefix: "before")
        assignRowIDs(initial)

        let delta = iTermGraphDeltaEncoder(previousRevision: initial.record)
        encodeArray(delta, identifiers: identifiers, generation: 2, valuePrefix: "after")

        var updatedIdentifiers = Set<String>()
        _ = delta.enumerateRecords { before, after, _, _, _ in
            guard let before, let after,
                  identifiers.contains(after.identifier),
                  !(before.pod as NSDictionary).isEqual(after.pod) else {
                return
            }
            updatedIdentifiers.insert(after.identifier)
            guard let index = identifiers.firstIndex(of: after.identifier) else {
                XCTFail("Unexpected array identifier \(after.identifier)")
                return
            }
            XCTAssertEqual(after.pod["value"] as? String,
                           "after_\(after.identifier)_\(index)")
        }
        XCTAssertEqual(updatedIdentifiers, Set(identifiers))
    }

    func testRemovingFirstArrayElementProducesOneDeletion() {
        let initial = iTermGraphDeltaEncoder(previousRevision: nil)
        encodeArray(initial,
                    identifiers: ["one", "two", "three"],
                    generation: 1,
                    valuePrefix: "value")
        assignRowIDs(initial)

        let delta = iTermGraphDeltaEncoder(previousRevision: initial.record)
        encodeArray(delta,
                    identifiers: ["two", "three"],
                    generation: 2,
                    valuePrefix: "value")

        var deletedIdentifiers = [String]()
        _ = delta.enumerateRecords { before, after, _, _, _ in
            if let before, after == nil {
                deletedIdentifiers.append(before.identifier)
            }
        }
        XCTAssertEqual(deletedIdentifiers, ["one"])
        XCTAssertEqual(delta.record?.propertyListValue as? [String: [[String: String]]],
                       ["items": [["value": "value_two_0"], ["value": "value_three_1"]]])
    }

    func testAppendingArrayElementProducesOneInsertion() {
        let initial = iTermGraphDeltaEncoder(previousRevision: nil)
        encodeArray(initial,
                    identifiers: ["one", "two", "three"],
                    generation: 1,
                    valuePrefix: "value")
        assignRowIDs(initial)

        let delta = iTermGraphDeltaEncoder(previousRevision: initial.record)
        encodeArray(delta,
                    identifiers: ["one", "two", "three", "four"],
                    generation: 2,
                    valuePrefix: "value")

        var insertedIdentifiers = [String]()
        _ = delta.enumerateRecords { before, after, _, _, _ in
            if before == nil, let after, after.key.isEmpty {
                insertedIdentifiers.append(after.identifier)
            }
        }
        XCTAssertEqual(insertedIdentifiers, ["four"])
    }
}
