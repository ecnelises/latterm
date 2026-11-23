// Rows emitted by tmux list commands. Some tmux versions emit literal backslash-t separators.
import Foundation

@objc(TSVDocument)
final class TmuxTable: NSObject {
    @objc let records: [[String]]
    private let fieldIndices: [String: Int]

    init(response: String, fields: [String], workAroundTabBug: Bool) {
        fieldIndices = Dictionary(fields.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { _, last in last })
        records = (response as NSString).components(separatedBy: "\n").compactMap { line in
            var cells = (line as NSString).components(separatedBy: "\t")
            if workAroundTabBug && cells.count == 1 {
                cells = (line as NSString).components(separatedBy: "\\t")
            }
            return cells.count >= fields.count ? cells : nil
        }
    }

    @objc(valueInRecord:forField:)
    func value(in record: [String], forField field: String) -> String? {
        guard let index = fieldIndices[field], record.indices.contains(index) else { return nil }
        return record[index]
    }

    override var debugDescription: String { (records as NSArray).description }
}

extension NSString {
    @objc(tsvDocumentWithFields:workAroundTabBug:)
    func tmuxTable(fields: [String], workAroundTabBug: Bool) -> TmuxTable {
        TmuxTable(response: self as String, fields: fields, workAroundTabBug: workAroundTabBug)
    }
}
