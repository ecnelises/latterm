import Foundation

// Returns the lowest unused nonnegative number. Like its window-placement
// callers, this allocator is confined to the main thread.
@objc(TemporaryNumberAllocator)
final class TemporaryNumberAllocator: NSObject {
    private static let shared = TemporaryNumberAllocator()
    private var numbers: Set<Int32> = []

    @objc static func sharedInstance() -> TemporaryNumberAllocator { shared }

    @objc func allocateNumber() -> Int32 {
        var number: Int32 = 0
        while numbers.contains(number) {
            number += 1
        }
        numbers.insert(number)
        return number
    }

    @objc func deallocateNumber(_ number: Int32) {
        numbers.remove(number)
    }
}
