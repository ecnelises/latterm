import AppKit

// NIB-owned implementation; callers use NSTableCellView and the input delegate.
@objc(iTermAdditionalHotKeyTableCellView)
private final class iTermAdditionalHotKeyTableCellView: NSTableCellView, iTermShortcutInputViewDelegate {
    @IBOutlet private weak var shortcutInput: iTermShortcutInputView?
    @IBOutlet private weak var duplicateWarning: NSView?
    private var rowValue: iTermAdditionalHotKeyObjectValue?

    override func awakeFromNib() {
        super.awakeFromNib()
        shortcutInput?.purpose = "as a hotkey"
        shortcutInput?.shortcutDelegate = self
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { shortcutInput?.backgroundStyle = backgroundStyle }
    }

    override var objectValue: Any? {
        get { rowValue }
        set {
            rowValue = newValue as? iTermAdditionalHotKeyObjectValue
            shortcutInput?.stringValue = rowValue?.shortcut?.stringValue ?? ""
            updateDuplicateWarning()
        }
    }

    func shortcutInputView(_ view: iTermShortcutInputView!, didReceiveKeyPress event: NSEvent!) {
        // Mutate the shared shortcut so the sheet's model sees edits and clears.
        rowValue?.shortcut?.setFrom(event)
        updateDuplicateWarning()
    }

    private func updateDuplicateWarning() {
        duplicateWarning?.isHidden = !(rowValue?.isDuplicate ?? false)
    }
}
