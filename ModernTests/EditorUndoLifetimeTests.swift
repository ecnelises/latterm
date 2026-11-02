import XCTest
@testable import iTerm2SharedARC

private final class PrivateUndoTextView: NSTextView {
    let privateStack = UndoManager()
    override var undoManager: UndoManager? { privateStack }
}

final class EditorUndoLifetimeTests: XCTestCase {
    func testDetachingEditorScrubsWindowTextStorageActions() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
                              styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let editor = NSTextView(frame: window.contentView!.bounds)
        editor.allowsUndo = true
        window.contentView!.addSubview(editor)
        let manager = window.undoManager!
        manager.groupsByEvent = false
        manager.beginUndoGrouping()
        manager.registerUndo(withTarget: editor.textStorage!,
                             selector: #selector(NSTextStorage.setAttributedString(_:)),
                             object: NSAttributedString(string: "old"))
        manager.endUndoGrouping()
        XCTAssertTrue(manager.canUndo)
        editor.removeFromSuperview()
        XCTAssertFalse(manager.canUndo)
    }

    func testDetachingEditorPreservesItsPrivateUndoStack() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
                              styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let editor = PrivateUndoTextView(frame: window.contentView!.bounds)
        editor.allowsUndo = true
        window.contentView!.addSubview(editor)
        editor.privateStack.registerUndo(withTarget: editor.textStorage!) { storage in
            storage.setAttributedString(NSAttributedString(string: "old"))
        }
        editor.removeFromSuperview()
        XCTAssertTrue(editor.privateStack.canUndo)
        editor.privateStack.removeAllActions()
    }

    func testCanceledValueAnimationDoesNotDeliverQueuedCompletion() {
        var completed = false
        let animation = ValueAnimation(from: 0, to: 1, duration: 1, apply: { _ in },
                                       completion: { completed = true })
        animation.currentProgress = 1
        animation.stop()
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async {
            XCTAssertFalse(completed)
            drained.fulfill()
        }
        wait(for: [drained], timeout: 2)
    }
}
