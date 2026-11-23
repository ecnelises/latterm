//
//  MutableArrayOfWeakObjects.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/21/24.
//

import Foundation
import Synchronization

@objc(iTermAtomicMutableArrayOfWeakObjects)
final class AtomicMutableArrayOfWeakObjects: NSObject, LineBlockClientList {
    private let storage = Synchronization.Mutex<[WeakBox<AnyObject>]>([])

    @objc(array)
    static func makeArray() -> AtomicMutableArrayOfWeakObjects {
        AtomicMutableArrayOfWeakObjects()
    }

    @objc var strongObjects: [Any] {
        storage.withLock { boxes in
            boxes.compactMap { $0.value }
        }
    }

    @objc var count: Int {
        storage.withLock { $0.count }
    }

    @objc(addObject:)
    func append(_ object: Any) {
        storage.withLock { boxes in
            boxes.append(WeakBox(object as AnyObject))
        }
    }

    @objc(removeAllObjects)
    func removeAll() {
        storage.withLock { boxes in
            boxes.removeAll(keepingCapacity: false)
        }
    }

    @objc(removeObjectsPassingTest:)
    func removeObjects(passingTest predicate: (Any?) -> Bool) {
        storage.withLock { boxes in
            boxes.removeAll { box in
                predicate(box.value)
            }
        }
    }

    @objc func prune() {
        storage.withLock { boxes in
            boxes.removeAll { $0.value == nil }
        }
    }

    @objc(compactMap:)
    func compactMap(_ transform: (Any) -> AnyObject?) -> AtomicMutableArrayOfWeakObjects {
        let result = AtomicMutableArrayOfWeakObjects()
        for item in strongObjects {
            if let mapped = transform(item) {
                result.append(mapped)
            }
        }
        return result
    }
}

@objc(iTermMutableArrayOfWeakObjects)
class MutableArrayOfWeakObjects: NSObject {
    private var array = [WeakBox<NSObject>]()

    @objc var isEmpty: Bool {
        return array.isEmpty || !array.anySatisfies { $0.value != nil }
    }
    @objc var strongObjects: [NSObject] {
        return array.compactMap { $0.value }
    }

    @objc(removeObjectsPassingTest:)
    func removeAll(where closure: (NSObject) -> (Bool)) {
        array.removeAll { box in
            if let value = box.value {
                return closure(value)
            }
            return true
        }
    }

    @objc(removeAllObjects)
    func removeAll() {
        array = []
    }

    @objc(addObject:)
    func append(_ object: NSObject) {
        array.append(WeakBox(object))
    }

    @objc var count: Int {
        array.count
    }

    @objc
    func prune() {
        array.removeAll { box in
            box.value == nil
        }
    }

    @objc(compactMap:)
    func compactMap(_ closure: (NSObject) -> (NSObject?)) -> MutableArrayOfWeakObjects {
        let result = MutableArrayOfWeakObjects()
        for box in array {
            if let value = box.value, let mapped = closure(value) {
                result.append(mapped)
            }
        }
        return result
    }

    @objc(firstObjectPassingTest:)
    func first(where closure: (NSObject) -> (Bool)) -> NSObject? {
        return array.first { box in
            guard let obj = box.value else {
                return false
            }
            return closure(obj)
        }?.value
    }

    @objc(lastObjectPassingTest:)
    func last(where closure: (NSObject) -> (Bool)) -> NSObject? {
        return array.last { box in
            guard let obj = box.value else {
                return false
            }
            return closure(obj)
        }?.value
    }
}

