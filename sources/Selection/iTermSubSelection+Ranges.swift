import Foundation

extension iTermSubSelection {
    // A column window clips the first and last rows and repeats its full width on intermediate rows.
    @objc(enumerateAbsoluteRangesInAbsWindowedRange:block:)
    static func enumerateRanges(in range: VT100GridAbsWindowedRange, _ visit: (VT100GridAbsCoordRange) -> Void) {
        let columns = range.columnWindow
        guard columns.length > 0 else {
            visit(range.coordRange)
            return
        }
        var x = VT100GridAbsWindowedRangeStart(range).x
        var y = range.coordRange.start.y
        let last = VT100GridAbsWindowedRangeEnd(range)
        while y < last.y {
            visit(VT100GridAbsCoordRangeMake(x, y, columns.location + columns.length, y))
            x = columns.location
            y += 1
        }
        visit(VT100GridAbsCoordRangeMake(x, last.y, last.x, last.y))
    }

    @objc(nonwindowedComponentsWithWidth:)
    func nonwindowedComponents(width: Int32) -> [iTermSubSelection] {
        guard selectionMode != .kiTermSelectionModeBox, absRange.columnWindow.length > 0 else { return [self] }
        var components = [iTermSubSelection]()
        Self.enumerateRanges(in: absRange) { range in
            let component = iTermSubSelection(absRange: VT100GridAbsWindowedRangeMake(range, 0, 0),
                                              mode: selectionMode, width: width)
            component.connected = true
            components.append(component)
        }
        components.last?.connected = false
        return components
    }
}
