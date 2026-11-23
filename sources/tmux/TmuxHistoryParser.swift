// Decode tmux capture-pane output using the terminal's normal rendition and character-width rules.
import Foundation

@objc(TmuxHistoryParser)
final class TmuxHistoryParser: NSObject {
    @objc(sharedInstance) static let shared = TmuxHistoryParser()

    @objc(parseDumpHistoryResponse:ambiguousIsDoubleWidth:unicodeVersion:alternateScreen:rtlFound:)
    func parse(_ response: String?, ambiguousIsDoubleWidth: Bool, unicodeVersion: Int, alternateScreen: Bool,
               rtlFound: UnsafeMutablePointer<ObjCBool>?) -> [Data]? {
        rtlFound?.pointee = false
        guard let response, !response.isEmpty else { return [] }
        let terminal = VT100Terminal()
        terminal.tmuxMode = true
        terminal.encoding = String.Encoding.utf8.rawValue
        var rows = [Data]()
        for line in (response as NSString).components(separatedBy: "\n") {
            let bytes = Data(line.utf8)
            guard let length = Int32(exactly: bytes.count) else { return nil }
            bytes.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
                if let base = buffer.baseAddress {
                    terminal.parser.putStreamData(base.assumingMemoryBound(to: CChar.self), length: length)
                }
            }
            var vector = CVector()
            CVectorCreate(&vector, 100)
            defer { CVectorReleaseObjectsAndDestroy(vector) }
            _ = terminal.parser.addParsedTokens(to: &vector)
            var row = Data()
            for index in 0..<vector.count {
                let token = CVectorGetVT100Token(&vector, index)
                terminal.execute(token)
                var text = token.isStringType ? token.string : nil
                if text == nil && (token.type == VT100_ASCIISTRING || token.type == VT100_MIXED_ASCII_CR_LF || token.type == VT100_GANG) {
                    text = token.stringForAsciiData()
                }
                guard let text, !text.isEmpty else { continue }
                // Each UTF-16 code unit consumes at most two terminal cells.
                withUnsafeTemporaryAllocation(of: screen_char_t.self, capacity: text.utf16.count * 2) { cells in
                    var count: Int32 = 0
                    var rtl: ObjCBool = false
                    StringToScreenChars(text, cells.baseAddress, terminal.foregroundColorCode, terminal.backgroundColorCode,
                                        &count, ambiguousIsDoubleWidth, nil, nil, .none, unicodeVersion, alternateScreen, &rtl)
                    if rtl.boolValue { rtlFound?.pointee = true }
                    if token.isAscii && terminal.charset != 0 { ConvertCharsToGraphicsCharset(cells.baseAddress, count) }
                    let bytes = UnsafeRawBufferPointer(cells).prefix(Int(count) * MemoryLayout<screen_char_t>.stride)
                    row.append(contentsOf: bytes)
                }
            }
            rows.append(row)
        }
        return rows
    }
}
