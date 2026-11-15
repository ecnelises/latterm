import AppKit
import SwiftUI

/// SwiftUI owns the form hierarchy and sizing. Individual AppKit editors retain
/// their target/action and delegate connections to the profile controllers.
struct ProfileSwiftUIForm: View {
    let sections: [ProfileSectionCard]
    let width: CGFloat
    var revision: Int = 0

    var body: some View {
        let safeWidth = max(0, width)
        let cardWidth = min(safeWidth, ProfileFormMetrics.maxFormWidth)
        VStack(alignment: .leading, spacing: 20) {
            ForEach(sections.filter(\.isFormVisible), id: \.self) { section in
                ProfileSwiftUISection(section: section, cardWidth: cardWidth, revision: revision)
            }
        }
        .padding(.vertical, 6)
        .frame(width: cardWidth, alignment: .topLeading)
        .frame(width: safeWidth, alignment: .topLeading)
    }
}

struct ProfileSwiftUISection: View {
    let section: ProfileSectionCard
    let cardWidth: CGFloat
    let revision: Int

    private var compact: Bool { cardWidth < 480 }
    private var labelColumnWidth: CGFloat { cardWidth >= 600 ? 168 : 140 }

    var body: some View {
        let visibleRows = section.rows.filter { $0.currentlyVisible() }
        VStack(alignment: .leading, spacing: 8) {
            if let title = section.titleLabel {
                HStack {
                    Text(title.stringValue).font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 8)
                    if let accessory = section.headerAccessory, !accessory.isHidden {
                        ProfileEditorBridge(editor: accessory)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(visibleRows.enumerated()), id: \.element.id) { index, row in
                    ProfileSwiftUIRow(row: row,
                                      compact: compact,
                                      labelColumnWidth: labelColumnWidth,
                                      revision: revision)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 14)
                        .id(row.id)
                    if index + 1 < visibleRows.count && !row.suppressSeparatorAfter {
                        Divider()
                            .padding(.leading, 14)
                            .opacity(0.65)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.08)))
            if let footer = section.footerLabel {
                Text(footer.stringValue).font(.system(size: 11)).foregroundStyle(.secondary)
                    .padding(.horizontal, 2)
            }
        }
    }
}

struct ProfileSwiftUIRow: View {
    let row: ProfileFormRow
    let compact: Bool
    var labelColumnWidth: CGFloat = 160
    let revision: Int
    private var stacked: Bool { compact || row.fullCardWidth }

    var body: some View {
        Group {
            if stacked {
                VStack(alignment: .leading, spacing: 6) {
                    label
                    content
                }
            } else if row.label != nil {
                HStack(alignment: .top, spacing: 12) {
                    label
                        .frame(width: labelColumnWidth, alignment: .leading)
                    content
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                content
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var label: some View {
        if let label = row.label {
            Text(label.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 3)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            editor
            ForEach(row.helperViews.filter { !$0.isHidden }, id: \.self) { helper in
                ProfileEditorBridge(editor: helper, fillsWidth: true)
            }
        }
        .padding(.leading, row.indent)
    }

    @ViewBuilder private var editor: some View {
        switch row.content {
        case .single(let view, let fills, _, let maxWidth):
            ProfileEditorBridge(editor: view, fillsWidth: fills, revision: revision)
                .frame(maxWidth: maxWidth.isFinite ? maxWidth : .infinity, alignment: .leading)
        case .checkbox(let button, let trailing):
            ProfileFlowLayout {
                ProfileEditorBridge(editor: button, revision: revision)
                ForEach(trailing.filter { !$0.isHidden }, id: \.self) { view in
                    ProfileEditorBridge(editor: view)
                }
            }
        case .wrappingLine(let items):
            ProfileFlowLayout {
                ForEach(items.filter { !$0.view.isHidden }, id: \.view) { item in
                    inlineItem(item)
                }
            }
        case .slider(let container, let minimum, let maximum, let note, let maxWidth):
            VStack(alignment: .leading, spacing: 4) {
                ProfileEditorBridge(editor: container, fillsWidth: true)
                    .frame(maxWidth: maxWidth, alignment: .leading)
                if minimum != nil || maximum != nil {
                    HStack {
                        if let minimum { Text(minimum.stringValue) }
                        Spacer()
                        if let maximum { Text(maximum.stringValue) }
                    }
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .frame(maxWidth: maxWidth)
                }
                if let note, !note.isHidden { ProfileEditorBridge(editor: note, fillsWidth: true) }
            }
        case .fontPicker(let picker):
            ProfileEditorBridge(editor: picker, fillsWidth: true, revision: revision)
        case .note(let field):
            Text(field.stringValue).font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .custom(let views, let layout):
            ProfileCustomEditorBridge(editors: views, compact: stacked, arrange: layout)
        }
    }

    @ViewBuilder private func inlineItem(_ item: ProfileFormInlineItem) -> some View {
        switch item.sizing {
        case .fixed(let width):
            ProfileEditorBridge(editor: item.view, revision: revision).frame(width: width)
        case .natural(_, let maxWidth):
            ProfileEditorBridge(editor: item.view, revision: revision)
                .frame(maxWidth: maxWidth, alignment: .leading)
        case .fill(let minWidth, let maxWidth):
            ProfileEditorBridge(editor: item.view, fillsWidth: true, revision: revision)
                .layoutValue(key: ProfileFlowMinimum.self, value: minWidth)
                .layoutValue(key: ProfileFlowMaximum.self, value: maxWidth)
                .layoutValue(key: ProfileFlowFill.self, value: true)
        }
    }
}

private struct ProfileFlowMinimum: LayoutValueKey { static let defaultValue: CGFloat = 0 }
private struct ProfileFlowMaximum: LayoutValueKey { static let defaultValue: CGFloat = .greatestFiniteMagnitude }
private struct ProfileFlowFill: LayoutValueKey { static let defaultValue = false }

/// Wraps related controls as a unit, distributing spare space to text editors.
private struct ProfileFlowLayout: Layout {
    private func arrange(_ subviews: Subviews, width: CGFloat) -> [(CGRect, Int)] {
        var lines: [[Int]] = [[]]
        var used: CGFloat = 0
        for index in subviews.indices {
            let view = subviews[index]
            let ideal = view.sizeThatFits(.unspecified).width
            let desired = min(width, view[ProfileFlowFill.self] ? view[ProfileFlowMinimum.self] : ideal)
            let gap: CGFloat = lines[lines.count - 1].isEmpty ? 0 : 8
            if used + gap + desired > width && !lines[lines.count - 1].isEmpty {
                lines.append([])
                used = 0
            }
            used += (lines[lines.count - 1].isEmpty ? 0 : 8) + desired
            lines[lines.count - 1].append(index)
        }
        var result: [(CGRect, Int)] = []
        var y: CGFloat = 0
        for line in lines where !line.isEmpty {
            let fixed = line.reduce(CGFloat(0)) { sum, i in
                sum + (subviews[i][ProfileFlowFill.self] ? 0 : min(width, subviews[i].sizeThatFits(.unspecified).width))
            }
            let fillCount = line.filter { subviews[$0][ProfileFlowFill.self] }.count
            let spare = max(0, width - fixed - CGFloat(line.count - 1) * 8)
            var x: CGFloat = 0
            var lineHeight: CGFloat = 0
            for index in line {
                let view = subviews[index]
                let w = view[ProfileFlowFill.self]
                    ? min(view[ProfileFlowMaximum.self], spare / CGFloat(max(1, fillCount)))
                    : min(width, view.sizeThatFits(.unspecified).width)
                let size = view.sizeThatFits(ProposedViewSize(width: w, height: nil))
                result.append((CGRect(x: x, y: y, width: w, height: size.height), index))
                x += w + 8
                lineHeight = max(lineHeight, size.height)
            }
            y += lineHeight + 6
        }
        return result
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        let frames = arrange(subviews, width: width)
        return CGSize(width: width, height: frames.map { $0.0.maxY }.max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (frame, index) in arrange(subviews, width: bounds.width) {
            subviews[index].place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                                  anchor: .topLeading, proposal: ProposedViewSize(frame.size))
        }
    }
}

struct ProfileEditorBridge: NSViewRepresentable {
    let editor: NSView
    var fillsWidth = false
    var revision: Int = 0

    func makeNSView(context: Context) -> ProfileEditorContainer {
        ProfileEditorContainer(editors: [editor])
    }
    func updateNSView(_ view: ProfileEditorContainer, context: Context) { view.install([editor]) }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ProfileEditorContainer, context: Context) -> CGSize? {
        let width = proposal.width ?? 320
        let measured = ProfileFormMeasurement.measureControl(editor, maxWidth: width)
        return CGSize(width: fillsWidth ? width : measured.width, height: measured.height)
    }
}

private struct ProfileCustomEditorBridge: NSViewRepresentable {
    let editors: [NSView]
    let compact: Bool
    let arrange: (CGFloat, CGFloat, CGFloat, Bool) -> CGFloat

    func makeNSView(context: Context) -> ProfileEditorContainer { ProfileEditorContainer(editors: editors, fillsBounds: false) }
    func updateNSView(_ view: ProfileEditorContainer, context: Context) { view.install(editors) }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ProfileEditorContainer, context: Context) -> CGSize? {
        let width = proposal.width ?? 320
        return CGSize(width: width, height: arrange(0, width, 0, compact))
    }
}

final class ProfileEditorContainer: NSView {
    override var isFlipped: Bool { true }
    override var wantsDefaultClipping: Bool { false }
    private var editors: [NSView] = []
    private let fillsBounds: Bool

    init(editors: [NSView], fillsBounds: Bool = true) {
        self.fillsBounds = fillsBounds
        super.init(frame: .zero)
        autoresizesSubviews = false
        install(editors)
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { it_fatalError("init(coder:) is not supported") }

    func install(_ editors: [NSView]) {
        self.editors = editors
        for editor in editors where editor.superview !== self {
            editor.removeFromSuperview()
            editor.autoresizingMask = []
            addSubview(editor)
        }
    }
    override func layout() {
        super.layout()
        if fillsBounds && editors.count == 1 { editors[0].frame = bounds }
    }
}
