import AppKit

@objc(SplitSelectionView)
final class SplitSelectionView: NSView {
    @objc private(set) var mode: SplitSelectionViewMode = .targetMove
    @objc private(set) var half: SplitSessionHalf = .noHalf {
        didSet { if oldValue != half { needsDisplay = true } }
    }

    private weak var delegate: SplitSelectionViewDelegate?
    private weak var session: PTYSession?

    override init(frame: NSRect) {
        super.init(frame: frame)
        alphaValue = 0.9
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    @objc(initWithMode:withFrame:session:delegate:)
    convenience init(mode: SplitSelectionViewMode, frame: NSRect, session: PTYSession?,
                     delegate: SplitSelectionViewDelegate?) {
        self.init(frame: frame)
        self.mode = mode
        self.session = session
        self.delegate = delegate
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        delegate?.didSelectDestinationSession(session, half: half)
    }

    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
    override func mouseExited(with event: NSEvent) { half = .noHalf }

    override func mouseMoved(with event: NSEvent) {
        update(at: convert(event.locationInWindow, from: nil))
    }

    private func distance(to edge: SplitSessionHalf, from point: NSPoint) -> CGFloat {
        switch edge {
        case .westHalf: return point.x - bounds.minX
        case .eastHalf: return bounds.maxX - point.x
        case .southHalf: return point.y - bounds.minY
        case .northHalf: return bounds.maxY - point.y
        default: return .infinity
        }
    }

    @objc(updateAtPoint:) func update(at point: NSPoint) {
        guard mode == .targetMove || mode == .sourceMove else {
            half = .fullPane
            return
        }
        guard bounds.width > 0, bounds.height > 0 else { return }
        let xEdge: SplitSessionHalf = point.x < bounds.midX ? .westHalf : .eastHalf
        let yEdge: SplitSessionHalf = point.y < bounds.midY ? .southHalf : .northHalf
        let dx = distance(to: xEdge, from: point)
        let dy = distance(to: yEdge, from: point)
        let xScore = dx / bounds.width
        let yScore = dy / bounds.height
        // Retain the current target in the center and near the diagonal between two edges.
        let edge = xScore <= yScore ? xEdge : yEdge
        let hysteresis = max(8, 0.05 * min(bounds.width, bounds.height))
        if min(xScore, yScore) < 0.4,
           distance(to: edge, from: point) < distance(to: half, from: point) - hysteresis {
            half = edge
        }
    }

    private var highlight: NSRect {
        switch half {
        case .southHalf: return bounds.divided(atDistance: bounds.height / 2, from: .minYEdge).slice
        case .northHalf: return bounds.divided(atDistance: bounds.height / 2, from: .maxYEdge).slice
        case .westHalf: return bounds.divided(atDistance: bounds.width / 2, from: .minXEdge).slice
        case .eastHalf: return bounds.divided(atDistance: bounds.width / 2, from: .maxXEdge).slice
        case .fullPane: return bounds
        default: return .zero
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        switch mode {
        case .sourceMove, .sourceSwap:
            drawHighlight(bounds,
                          fill: iTermAdvancedSettingsModel.splitPaneSourceFillColor(),
                          fallback: NSColor(calibratedRed: 0, green: 0.5, blue: 0, alpha: 1),
                          border: iTermAdvancedSettingsModel.splitPaneSourceBorderColor(),
                          innerBorder: iTermAdvancedSettingsModel.splitPaneSourceInnerBorderColor())
            drawMessage(mode == .sourceMove ? "Select a destination pane" : "Select pane to swap with", in: bounds)
        case .targetMove, .targetSwap:
            guard half != .noHalf else { return }
            let rect = highlight
            drawHighlight(rect,
                          fill: iTermAdvancedSettingsModel.splitPaneTargetDropFillColor(),
                          fallback: NSColor(calibratedRed: 0.5, green: 0, blue: 0, alpha: 1),
                          border: iTermAdvancedSettingsModel.splitPaneTargetDropBorderColor(),
                          innerBorder: iTermAdvancedSettingsModel.splitPaneTargetDropInnerBorderColor())
            if delegate != nil {
                let message = mode == .targetMove ? "Click to move source pane to this split" : "Click to swap source pane with this one"
                drawMessage(message, in: rect.insetBy(dx: 1, dy: 1))
            }
        case .inspect, .select:
            NSColor(calibratedRed: 0, green: 0.5, blue: 0.25, alpha: 1).setFill()
            bounds.fill()
            drawMessage(mode == .inspect ? "Click to inspect" : "Click to select", in: bounds)
        @unknown default: break
        }
    }

    private func drawHighlight(_ rect: NSRect, fill: String, fallback: NSColor, border: String, innerBorder: String) {
        (NSColor(fromHexString: fill) ?? fallback).setFill()
        rect.fill()
        (NSColor(fromHexString: border) ?? .white).set()
        rect.frame()
        (NSColor(fromHexString: innerBorder) ?? .black).set()
        rect.insetBy(dx: 1, dy: 1).frame()
    }

    private func drawMessage(_ message: String, in frame: NSRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let shadow = NSShadow()
        shadow.shadowColor = .black
        shadow.shadowOffset = .zero
        shadow.shadowBlurRadius = 4
        for size in stride(from: 24, through: 7, by: -1) {
            let text = NSAttributedString(string: message, attributes: [
                .font: NSFont.systemFont(ofSize: CGFloat(size)), .foregroundColor: NSColor.white,
                .paragraphStyle: paragraph, .shadow: shadow
            ])
            let measured = text.size()
            let rect = NSRect(x: frame.minX, y: frame.minY + frame.height * 2 / 3,
                              width: frame.width, height: measured.height)
            if size == 7 || (measured.width <= frame.width && rect.maxY <= frame.maxY) {
                text.draw(with: rect, options: [])
                return
            }
        }
    }
}
