import AppKit
import SwiftUI

// Task-oriented navigation independent of the legacy controller boundaries.
enum ProfileTask: String, CaseIterable, Identifiable {
    case launch, appearance, input, session, automation
    var id: String { rawValue }
    var title: String {
        switch self {
        case .launch: return NSLocalizedString("Startup", comment: "Profile task")
        case .appearance: return NSLocalizedString("Appearance", comment: "Profile task")
        case .input: return NSLocalizedString("Input", comment: "Profile task")
        case .session: return NSLocalizedString("Session", comment: "Profile task")
        case .automation: return NSLocalizedString("Automation", comment: "Profile task")
        }
    }
    var summary: String {
        switch self {
        case .launch: return NSLocalizedString("Name, command, and working directory", comment: "Profile task summary")
        case .appearance: return NSLocalizedString("Colors, typography, and window appearance", comment: "Profile task summary")
        case .input: return NSLocalizedString("Keyboard behavior and mouse reporting", comment: "Profile task summary")
        case .session: return NSLocalizedString("History, notifications, and session lifecycle", comment: "Profile task summary")
        case .automation: return NSLocalizedString("Triggers, automatic switching, and file actions", comment: "Profile task summary")
        }
    }
}

struct WorkspaceProfile: Identifiable, Equatable {
    let id: String
    let name: String
}

struct ProfileTaskSection: Identifiable {
    let section: ProfileSectionCard
    let task: ProfileTask
    let source: Int
    let advanced: Bool
    var id: UUID { section.rows[0].id }
}

final class ProfileWorkspaceModel: ObservableObject {
    @Published var profiles: [WorkspaceProfile] = []
    @Published var selectedProfile = ""
    @Published var task: ProfileTask = .launch
    @Published var sections: [ProfileTaskSection] = []
    @Published var revision = 0
    @Published var editingSession = false
    @Published var isDefault = false
    @Published var showAdvanced = false
    @Published var revealRow: UUID?
    var onSelect: ((String) -> Void)?
    var onAdd: (() -> Void)?
    var onDuplicate: (() -> Void)?
    var onRemove: (() -> Void)?
    var onDefault: (() -> Void)?
    var onCopy: (() -> Void)?
    var moreActions: [NSMenuItem] = []

    func refresh(pages: [(Int, ProfileFormDocumentView)]) {
        var updated: [ProfileTaskSection] = []
        for (source, page) in pages {
            page.usesWorkspacePresentation = true
            for (index, section) in page.formSections.enumerated() {
                func add(_ rows: [ProfileFormRow], title: String, task: ProfileTask, advanced: Bool = false) {
                    guard !rows.isEmpty else { return }
                    let group = ProfileSectionCard(title: title, rows: rows)
                    updated.append(ProfileTaskSection(section: group, task: task, source: source, advanced: advanced))
                }
                if source == 0 && index == 0 && !editingSession && section.rows.count >= 6 {
                    add([section.rows[0], section.rows[2]], title: NSLocalizedString("Name & Tags", comment: "Profile task group"), task: .launch)
                    add([section.rows[1]], title: NSLocalizedString("Profile Shortcut", comment: "Profile task group"), task: .input)
                    add(Array(section.rows.dropFirst(3)), title: NSLocalizedString("Tab Identity", comment: "Profile task group"), task: .appearance)
                    continue
                }
                if source == 1 && index == 1 && section.rows.count > 6 {
                    add(Array(section.rows.prefix(6)), title: NSLocalizedString("Basic Colors", comment: "Profile task group"), task: .appearance)
                    add(Array(section.rows.dropFirst(6)), title: NSLocalizedString("Additional Colors", comment: "Profile task group"), task: .appearance, advanced: true)
                    continue
                }
                if source == 4 && index == 4 {
                    add(Array(section.rows.prefix(1)), title: NSLocalizedString("Environment", comment: "Profile task group"), task: .launch)
                    add(Array(section.rows.dropFirst()), title: NSLocalizedString("Prompt Metadata and tmux", comment: "Profile task group"), task: .automation, advanced: true)
                    continue
                }
                if source == 5 && index == 3 {
                    add(Array(section.rows.prefix(3)), title: NSLocalizedString("Progress Bars", comment: "Profile task group"), task: .appearance)
                    add(Array(section.rows.dropFirst(3)), title: NSLocalizedString("Password Manager", comment: "Profile task group"), task: .automation)
                    continue
                }
                if source == 5 && index == 1 {
                    add(Array(section.rows.prefix(4)), title: NSLocalizedString("Logging", comment: "Profile task group"), task: .session)
                    add(Array(section.rows.dropFirst(4)), title: NSLocalizedString("Archiving", comment: "Profile task group"), task: .session)
                    continue
                }
                if source == 7 && index == 0 {
                    add(Array(section.rows.prefix(1)), title: NSLocalizedString("Triggers", comment: "Profile task group"), task: .automation)
                    add(Array(section.rows.dropFirst()), title: NSLocalizedString("Smart Selection", comment: "Profile task group"), task: .input)
                    continue
                }
                let task: ProfileTask
                switch source {
                case 0: task = !editingSession && index == 1 ? .appearance : .launch
                case 1, 2: task = .appearance
                case 3: task = index == 2 ? .launch : .appearance
                case 5: task = index == 2 ? .appearance : .session
                case 4: task = index == 2 ? .input : .session
                case 6: task = .input
                default: task = source == 7 ? .automation : .session
                }
                let advanced = (source == 1 && (index == 2 || index == 3)) ||
                    (source == 2 && index == 3) || (source == 4 && index == 1) ||
                    (source == 5 && index == 4)
                updated.append(ProfileTaskSection(section: section, task: task, source: source, advanced: advanced))
            }
        }
        let originalRows = pages.flatMap { $0.1.formSections.flatMap(\.rows) }.map(\.id)
        let regroupedRows = updated.flatMap { $0.section.rows }.map(\.id)
        it_assert(originalRows.count == regroupedRows.count && Set(originalRows) == Set(regroupedRows),
                  "Every profile editor must appear exactly once in the task workspace")
        for (source, page) in pages { page.workspaceGroups = updated.filter { $0.source == source } }
        sections = updated
        prepareEditors()
        revision += 1
    }

    func prepareEditors() {
        for record in sections {
            let visible = record.task == task && (!record.advanced || showAdvanced) && record.section.isFormVisible
            for row in record.section.rows { row.prepareForRendering(inVisibleSection: visible) }
        }
    }

    @discardableResult
    func reveal(_ control: NSView) -> Bool {
        for record in sections {
            for row in record.section.rows where row.allViews.contains(where: { $0 === control || control.isDescendant(of: $0) }) {
                task = record.task
                if record.advanced { showAdvanced = true }
                prepareEditors()
                revealRow = row.id
                revision += 1
                return true
            }
        }
        return false
    }
}

struct ProfileWorkspace: View {
    @ObservedObject var model: ProfileWorkspaceModel

    var body: some View {
        GeometryReader { geometry in
            let safeWidth = max(0, geometry.size.width)
            let safeHeight = max(0, geometry.size.height)
            let horizontalInset: CGFloat = model.editingSession ? 20 : 32
            let availableWidth = max(0, safeWidth - horizontalInset * 2)
            let cardWidth = min(availableWidth, ProfileFormMetrics.maxFormWidth)
            let primarySections = model.sections.filter {
                $0.task == model.task && !$0.advanced && $0.section.isFormVisible
            }
            let advancedSections = model.sections.filter {
                $0.task == model.task && $0.advanced && $0.section.isFormVisible
            }

            if safeWidth > horizontalInset * 2 + 40 && safeHeight > 0 {
                VStack(alignment: .leading, spacing: 0) {
                    profileToolbar(compact: availableWidth < 460)
                        .frame(width: cardWidth, alignment: .leading)
                        .padding(.horizontal, horizontalInset)
                        .padding(.top, model.editingSession ? 16 : 2)
                        .padding(.bottom, 12)
                    Divider()
                        .padding(.horizontal, horizontalInset)
                    VStack(alignment: .leading, spacing: 6) {
                        taskNavigation(compact: availableWidth < 400)
                        Text(model.task.summary)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(width: cardWidth, alignment: .leading)
                    .padding(.horizontal, horizontalInset)
                    .padding(.top, 12)
                    .padding(.bottom, 10)

                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 22) {
                                ForEach(primarySections) { record in
                                    ProfileSwiftUISection(section: record.section,
                                                          cardWidth: cardWidth,
                                                          revision: model.revision)
                                }
                                if !advancedSections.isEmpty {
                                    DisclosureGroup(isExpanded: $model.showAdvanced) {
                                        VStack(alignment: .leading, spacing: 22) {
                                            ForEach(advancedSections) { record in
                                                ProfileSwiftUISection(section: record.section,
                                                                      cardWidth: cardWidth,
                                                                      revision: model.revision)
                                            }
                                        }
                                        .padding(.top, 12)
                                    } label: {
                                        Text(NSLocalizedString("Advanced Options", comment: "Profile disclosure"))
                                            .font(.system(size: 13, weight: .semibold))
                                    }
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 14)
                                    .frame(width: cardWidth, alignment: .leading)
                                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.08)))
                                }
                            }
                            .frame(width: cardWidth, alignment: .leading)
                            .padding(.horizontal, horizontalInset)
                            .padding(.top, 8)
                            .padding(.bottom, 28)
                            .frame(width: max(safeWidth, cardWidth + horizontalInset * 2), alignment: .topLeading)
                        }
                        .onChange(of: model.revealRow) { _, row in
                            if let row { proxy.scrollTo(row, anchor: .center) }
                        }
                    }
                }
                .frame(width: safeWidth, height: safeHeight, alignment: .topLeading)
                .background(Color(nsColor: .windowBackgroundColor))
            } else {
                Color(nsColor: .windowBackgroundColor)
                    .frame(width: safeWidth, height: safeHeight)
            }
        }
        .onChange(of: model.task) { _, _ in
            model.revealRow = nil
            model.prepareEditors()
            model.revision += 1
        }
        .onChange(of: model.showAdvanced) { _, _ in model.prepareEditors(); model.revision += 1 }
        .onChange(of: model.selectedProfile) { _, guid in model.onSelect?(guid) }
    }

    @ViewBuilder private func taskNavigation(compact: Bool) -> some View {
        if compact {
            Picker(NSLocalizedString("Settings", comment: "Profile task picker"), selection: $model.task) {
                ForEach(ProfileTask.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
            .fixedSize()
        } else {
            Picker(NSLocalizedString("Settings", comment: "Profile task picker"), selection: $model.task) {
                ForEach(ProfileTask.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(maxWidth: 460, alignment: .leading)
        }
    }

    private func profileToolbar(compact: Bool) -> some View {
        Group {
            if model.editingSession {
                HStack {
                    Text(NSLocalizedString("Current Session", comment: "Profile heading")).font(.headline)
                    Spacer()
                    Button(NSLocalizedString("Copy to Profile…", comment: "Profile action")) { model.onCopy?() }
                }
            } else {
                HStack(spacing: 10) {
                    Picker(NSLocalizedString("Profile", comment: "Profile selector"), selection: $model.selectedProfile) {
                        ForEach(model.profiles) { Text($0.name).tag($0.id) }
                    }
                    .labelsHidden()
                    .frame(width: compact ? 180 : 220)
                    .accessibilityIdentifier("WorkspaceProfilePicker")

                    if model.isDefault {
                        Text(NSLocalizedString("Default Profile", comment: "Profile status"))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.quaternary, in: Capsule())
                    }

                    Spacer(minLength: 8)

                    Button {
                        model.onAdd?()
                    } label: {
                        Image(systemName: SFSymbol.plus.rawValue)
                    }
                    .buttonStyle(.borderless)
                    .help(NSLocalizedString("New Profile", comment: "Profile action"))

                    Menu {
                        Button(NSLocalizedString("New Profile", comment: "Profile action")) { model.onAdd?() }
                        Button(NSLocalizedString("Duplicate Profile", comment: "Profile action")) { model.onDuplicate?() }
                        if !model.isDefault {
                            Button(NSLocalizedString("Set as Default", comment: "Profile action")) { model.onDefault?() }
                        }
                        Divider()
                        ForEach(model.moreActions.indices, id: \.self) { index in
                            let item = model.moreActions[index]
                            if item.isSeparatorItem { Divider() }
                            else if let action = item.action {
                                Button(item.title) { NSApp.sendAction(action, to: item.target, from: item) }
                                    .disabled(!item.isEnabled)
                            }
                        }
                        Divider()
                        Button(NSLocalizedString("Delete Profile…", comment: "Profile action"), role: .destructive) { model.onRemove?() }
                            .disabled(model.profiles.count < 2)
                    } label: {
                        Image(systemName: SFSymbol.ellipsisCircle.rawValue)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help(NSLocalizedString("More profile actions", comment: "Profile actions"))
                }
            }
        }
    }
}
