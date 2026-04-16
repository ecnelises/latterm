import Foundation

@objc(iTermCompletionItem)
class CompletionItem: NSObject {
    @objc(iTermCompletionItemKind) enum Kind: Int {
        case file
        case history
        case command
        case folder
        case navigation
        case bookmark
    }

    @objc let value: String
    @objc let detail: String?
    @objc let kind: Kind

    @objc(initWithValue:detail:kind:)
    init(value: String, detail: String?, kind: Kind) {
        #if DEBUG
        it_assert(!(detail ?? "").contains("<iTermCompletionItem"))
        #endif
        self.value = value
        self.detail = detail
        self.kind = kind
    }

    @objc
    func mapValue(_ closure: (String) -> (String)) -> CompletionItem {
        return CompletionItem(value: closure(value), detail: detail, kind: kind)
    }
}
