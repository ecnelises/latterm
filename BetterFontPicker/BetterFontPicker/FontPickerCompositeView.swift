//
//  FontPickerCompositeView.swift
//  BetterFontPicker
//
//  Created by George Nachman on 4/9/19.
//  Copyright © 2019 George Nachman. All rights reserved.
//

import Cocoa

@objc(BFPCompositeViewDelegate)
public protocol FontPickerCompositeViewDelegate: NSObjectProtocol {
    func fontPickerCompositeView(_ view: FontPickerCompositeView,
                                 didSelectFont font: NSFont)
}

@objc(BFPCompositeView)
public class FontPickerCompositeView: NSView, AffordanceDelegate, FontFamilyMemberPickerViewDelegate, SizePickerViewDelegate, OptionsButtonControllerDelegate {
    @objc public weak var delegate: FontPickerCompositeViewDelegate?
    private var accessories: [NSView] = []
    @objc public let affordance = Affordance()
    private var optionsButtonController: OptionsButtonController? = OptionsButtonController()
    var memberPicker: FontFamilyMemberPickerView? = FontFamilyMemberPickerView()
    var sizePicker: SizePickerView? = SizePickerView()
    @objc private(set) public var horizontalSpacing: SizePickerView? = nil
    @objc private(set) public var verticalSpacing: SizePickerView? = nil
    @objc var options: Set<Int> {
        return optionsButtonController?.options ?? Set()
    }

    @objc(BFPCompositeViewMode)
    public enum Mode: Int {
        case normal
        case fixedPitch
    }

    @objc public var mode: Mode = .normal {
        didSet {
            switch mode {
            case .normal:
                affordance.vc.systemFontDataSources = [SystemFontsDataSource()]
            case .fixedPitch:
                affordance.vc.systemFontDataSources = [
                    SystemFontsDataSource(filter: .fixedPitch),
                    SystemFontsDataSource(filter: .variablePitch) ]
            }
        }
    }
    @objc public var font: NSFont? {
        set {
            let temp = delegate
            delegate = nil
            if let font = newValue, let familyName = font.familyName {
                affordance.familyName = familyName
                memberPicker?.set(member: font.fontName)
                sizePicker?.size = Double(font.pointSize)
                updateOptionsMenu()
                optionsButtonController?.set(font: font)
            }
            delegate = temp
        }
        get {
            guard let memberPicker = memberPicker else {
                guard let familyName = affordance.familyName else {
                    return nil
                }
                return NSFont(name: familyName,
                              size: CGFloat(sizePicker?.size ?? 12))
            }
            guard let name = memberPicker.selectedFontName else {
                return nil
            }
            let size = CGFloat(sizePicker?.size ?? 12)
            let settings = optionsButtonController?.featureSettings ?? []
            if settings.isEmpty {
                return NSFont(name: name, size: size)
            }
            var descriptor = NSFontDescriptor(name: name, size: size)
            descriptor = descriptor.addingAttributes([.featureSettings: settings])
            return NSFont(descriptor: descriptor, size: size)
        }
    }
    public init(font: NSFont) {
        super.init(frame: NSRect.zero)
        postInit()
        self.font = font
    }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        postInit()
    }

    public required init?(coder decoder: NSCoder) {
        super.init(coder: decoder)
        postInit()
    }

    private func postInit() {
        affordance.delegate = self
        memberPicker?.delegate = self
        sizePicker?.delegate = self
        sizePicker?.clamp(min: 1, max: 256)
        addSubview(affordance)
        if let memberPicker = memberPicker {
            addSubview(memberPicker)
            affordance.memberPicker = memberPicker
        }
        if let sizePicker = sizePicker {
            addSubview(sizePicker)
        }
        layoutSubviews()
    }

    public override func resizeSubviews(withOldSize oldSize: NSSize) {
        layoutSubviews()
    }

    @objc public func removeSizePicker() {
        if let sizePicker = sizePicker {
            sizePicker.removeFromSuperview()
            self.sizePicker = nil
            invalidateIntrinsicContentSize()
            layoutSubviews()
            superview?.needsLayout = true
        }
    }

    @objc public func removeMemberPicker() {
        if let memberPicker = memberPicker {
            memberPicker.removeFromSuperview()
            self.memberPicker?.delegate = nil
            self.memberPicker = nil
            invalidateIntrinsicContentSize()
            layoutSubviews()
            superview?.needsLayout = true
        }
    }

    @objc public var hasOptionsButton: Bool {
        return optionsButtonController != nil
    }

    @objc public func removeOptionsButton() {
        let i = accessories.firstIndex { view -> Bool in
            guard let wrapper = view as? AccessoryWrapper,
                  let optionsButton = optionsButtonController?.optionsButton else {
                return false
            }
            return wrapper.child == optionsButton
        }
        if let i {
            accessories[i].removeFromSuperview()
            accessories.remove(at: i)
        }
        optionsButtonController = nil
        updateOptionsMenu()
        invalidateIntrinsicContentSize()
        superview?.needsLayout = true
    }

    @objc public func addOptionsButton() {
        guard let font else {
            return
        }
        optionsButtonController = OptionsButtonController()
        // Build the menu first so the family-change reset doesn't clobber the
        // state we are about to load from the font.
        updateOptionsMenu()
        optionsButtonController?.set(font: font)
    }

    private func temporarilyRemoveOptionsButton() {
        if let i = indexOfOptionsButton {
            accessories[i].removeFromSuperview()
            accessories.remove(at: i)
            optionsButtonController?.delegate = nil
            invalidateIntrinsicContentSize()
            layoutSubviews()
            superview?.needsLayout = true
        }
    }

    private func imageViewForImage(withName name: String) -> NSImageView {
        let bundle = FontPickerResources.bundle
        if let image = bundle.image(forResource: NSImage.Name(name)) {
            return NSImageView(image: image)
        } else {
            return NSImageView(image: NSImage(size: NSSize(width: 1, height: 1)))
        }
    }

    @objc(addHorizontalSpacingAccessoryWithInitialValue:)
    public func addHorizontalSpacingAccessory(_ initialValue: Double) -> SizePickerView {
        let view = SizePickerView()
        view.clamp(min: 1, max: 200)
        horizontalSpacing = view
        view.size = initialValue
        let imageView = imageViewForImage(withName: "HorizontalSpacingIcon")
        imageView.image?.isTemplate = true
        imageView.contentTintColor = NSColor.labelColor
        add(accessory: imageView)
        add(accessory: view)
        return view
    }

    @objc(addVerticalSpacingAccessoryWithInitialValue:)
    public func addVerticalSpacingAccessory(_ initialValue: Double) -> SizePickerView {
        let view = SizePickerView()
        view.clamp(min: 1, max: 200)
        verticalSpacing = view
        view.size = initialValue
        let imageView = imageViewForImage(withName: "VerticalSpacingIcon")
        imageView.image?.isTemplate = true
        imageView.contentTintColor = NSColor.labelColor
        add(accessory: imageView)
        add(accessory: view)
        return view
    }

    public func add(accessory view: NSView) {
        accessories.append(view)
        ensureAccessoryOrder()
        addSubview(view)
        invalidateIntrinsicContentSize()
        layoutSubviews()
        superview?.needsLayout = true
    }

    private func ensureAccessoryOrder() {
        guard let i = indexOfOptionsButton, i != accessories.count - 1 else {
            return
        }
        // Move options button to end.
        let button = accessories[i]
        accessories.remove(at: i)
        accessories.append(button)
    }

    private struct LayoutGeometry {
        static let margin: CGFloat = 4.0
        static let pairSpacing: CGFloat = 3.0
        static let clusterSpacing: CGFloat = 8.0
        static let rowSpacing: CGFloat = 6.0
        static let primaryRowHeight: CGFloat = 27.0
        static let accessoryRowHeight: CGFloat = 25.0
        static let minSingleRowAffordanceWidth: CGFloat = 160.0
    }

    private func accessoryClusters() -> [[NSView]] {
        var clusters: [[NSView]] = []
        var i = 0
        while i < accessories.count {
            let current = accessories[i]
            if current is NSImageView,
               i + 1 < accessories.count,
               !(accessories[i + 1] is NSImageView) {
                clusters.append([current, accessories[i + 1]])
                i += 2
            } else {
                clusters.append([current])
                i += 1
            }
        }
        return clusters
    }

    private func clusterWidth(_ cluster: [NSView]) -> CGFloat {
        guard !cluster.isEmpty else { return 0 }
        let itemsWidth = cluster.reduce(CGFloat(0)) { $0 + max(0, $1.fittingSize.width) }
        return itemsWidth + CGFloat(cluster.count - 1) * LayoutGeometry.pairSpacing
    }

    private func accessoryRows(maxWidth: CGFloat) -> [[[NSView]]] {
        let clusters = accessoryClusters()
        guard !clusters.isEmpty else { return [] }
        let limit = max(1, maxWidth)
        var rows: [[[NSView]]] = [[]]
        var currentWidth: CGFloat = 0
        for cluster in clusters {
            let w = clusterWidth(cluster)
            if !rows[rows.count - 1].isEmpty && currentWidth + LayoutGeometry.clusterSpacing + w > limit {
                rows.append([cluster])
                currentWidth = w
            } else {
                if !rows[rows.count - 1].isEmpty {
                    currentWidth += LayoutGeometry.clusterSpacing
                }
                rows[rows.count - 1].append(cluster)
                currentWidth += w
            }
        }
        return rows
    }

    private func pickerWidths(forWidth width: CGFloat) -> (member: CGFloat, size: CGFloat) {
        let baseMember: CGFloat = memberPicker == nil ? 0 : 100.0
        let baseSize: CGFloat = sizePicker == nil ? 0 : 54.0
        let gaps = CGFloat((memberPicker == nil ? 0 : 1) + (sizePicker == nil ? 0 : 1)) * LayoutGeometry.margin
        if width <= 0 {
            return (baseMember, baseSize)
        }
        // Preserve generous affordance space before shrinking secondary pickers.
        let minAffordance: CGFloat = min(96.0, max(40.0, width * 0.42))
        let availableForPickers = max(0, width - minAffordance - gaps)
        var sizeW = min(baseSize, availableForPickers)
        var memberW = min(baseMember, max(0, availableForPickers - sizeW))
        if memberPicker != nil && sizePicker != nil && memberW + sizeW > availableForPickers {
            sizeW = min(baseSize, max(42.0, availableForPickers * 0.38))
            memberW = max(0, availableForPickers - sizeW)
        }
        return (floor(memberW), floor(sizeW))
    }

    private func singleRowAccessoriesWidth() -> CGFloat {
        let clusters = accessoryClusters()
        guard !clusters.isEmpty else { return 0 }
        let itemsTotal = clusters.reduce(CGFloat(0)) { $0 + clusterWidth($1) }
        return itemsTotal + CGFloat(clusters.count - 1) * LayoutGeometry.clusterSpacing
    }

    private func canFitSingleRow(width: CGFloat) -> Bool {
        if accessories.isEmpty {
            return true
        }
        let pickers = pickerWidths(forWidth: width)
        let primaryFixed = pickers.member + pickers.size
        var fixedGaps: CGFloat = 0
        if memberPicker != nil { fixedGaps += LayoutGeometry.margin }
        if sizePicker != nil { fixedGaps += LayoutGeometry.margin }
        let accessoriesWidth = singleRowAccessoriesWidth()
        let accessoryLeadGap = LayoutGeometry.clusterSpacing
        let needed = LayoutGeometry.minSingleRowAffordanceWidth + fixedGaps + primaryFixed + accessoryLeadGap + accessoriesWidth
        return width >= needed
    }

    @objc public func preferredHeight(forWidth width: CGFloat) -> CGFloat {
        if accessories.isEmpty || canFitSingleRow(width: width) {
            return LayoutGeometry.primaryRowHeight
        }
        let rows = accessoryRows(maxWidth: width)
        let extraRows = CGFloat(rows.count)
        return LayoutGeometry.primaryRowHeight + extraRows * (LayoutGeometry.rowSpacing + LayoutGeometry.accessoryRowHeight)
    }

    public override var intrinsicContentSize: NSSize {
        let w = bounds.width > 0 ? bounds.width : 360.0
        return NSSize(width: NSView.noIntrinsicMetric, height: preferredHeight(forWidth: w))
    }

    private func layoutSubviews() {
        let width = bounds.width
        let height = bounds.height
        guard width > 0 else { return }

        let useSingleRow = accessories.isEmpty || canFitSingleRow(width: width) || height < (LayoutGeometry.primaryRowHeight + LayoutGeometry.rowSpacing + 18.0)
        let pickers = pickerWidths(forWidth: width)
        var fixedGaps: CGFloat = 0
        if memberPicker != nil { fixedGaps += LayoutGeometry.margin }
        if sizePicker != nil { fixedGaps += LayoutGeometry.margin }

        let accessoriesWidth = useSingleRow && !accessories.isEmpty ? (LayoutGeometry.clusterSpacing + singleRowAccessoriesWidth()) : 0
        let remainingForAffordance = width - pickers.member - pickers.size - fixedGaps - accessoriesWidth
        let affordanceWidth = max(24.0, floor(remainingForAffordance))

        // AppKit coordinates here are non-flipped (y = 0 at bottom), so the primary row sits at the top.
        let primaryY = accessories.isEmpty || useSingleRow
            ? max(0, floor((height - LayoutGeometry.primaryRowHeight) / 2.0))
            : max(0, height - LayoutGeometry.primaryRowHeight)

        var x: CGFloat = 0
        affordance.frame = NSRect(x: x, y: primaryY + 1, width: affordanceWidth, height: 25)
        x += affordanceWidth

        if let memberPicker {
            x += LayoutGeometry.margin
            memberPicker.frame = NSRect(x: x, y: primaryY + 1, width: pickers.member, height: 25)
            x += pickers.member
        }
        if let sizePicker {
            x += LayoutGeometry.margin
            sizePicker.frame = NSRect(x: x, y: primaryY, width: pickers.size, height: 27)
            x += pickers.size
        }

        guard !accessories.isEmpty else { return }

        if useSingleRow {
            layoutAccessoryRow(accessoryClusters(),
                               startX: x + LayoutGeometry.clusterSpacing,
                               rowY: primaryY,
                               rowHeight: LayoutGeometry.primaryRowHeight,
                               maxX: width)
        } else {
            let rows = accessoryRows(maxWidth: width)
            var currentY = primaryY - LayoutGeometry.rowSpacing - LayoutGeometry.accessoryRowHeight
            for row in rows {
                layoutAccessoryRow(row,
                                   startX: 0,
                                   rowY: max(0, currentY),
                                   rowHeight: LayoutGeometry.accessoryRowHeight,
                                   maxX: width)
                currentY -= (LayoutGeometry.rowSpacing + LayoutGeometry.accessoryRowHeight)
            }
        }
    }

    private func layoutAccessoryRow(_ clusters: [[NSView]],
                                    startX: CGFloat,
                                    rowY: CGFloat,
                                    rowHeight: CGFloat,
                                    maxX: CGFloat) {
        var x = startX
        for (clusterIndex, cluster) in clusters.enumerated() {
            if clusterIndex > 0 {
                x += LayoutGeometry.clusterSpacing
            }
            for (itemIndex, accessory) in cluster.enumerated() {
                if itemIndex > 0 {
                    x += LayoutGeometry.pairSpacing
                }
                if let wrapper = accessory as? AccessoryWrapper {
                    wrapper.layoutSubviews(containerHeight: rowHeight)
                }
                let size = accessory.fittingSize
                let clampedWidth = max(0, min(size.width, maxX - x))
                let itemHeight = accessory is AccessoryWrapper ? rowHeight : min(rowHeight, max(16.0, size.height))
                let itemY = rowY + floor((rowHeight - itemHeight) / 2.0)
                accessory.frame = NSRect(x: x, y: itemY, width: clampedWidth, height: itemHeight)
                x += clampedWidth
            }
        }
    }

    public func affordance(_ affordance: Affordance, didSelectFontFamily fontFamily: String) {
        // Rebuild the options menu first so stale stylistic-alt and calt
        // state from the previous family is cleared before we hand the
        // delegate a font built from feature settings.
        updateOptionsMenu()
        if let font = font {
            delegate?.fontPickerCompositeView(self, didSelectFont: font)
        }
    }

    private var indexOfOptionsButton: Int? {
        guard let optionsButton = optionsButtonController?.optionsButton else {
            return nil
        }
        return accessories.firstIndex { view in
            (view as? AccessoryWrapper)?.subviews.first === optionsButton
        }
    }

    private var haveAddedOptionsButton: Bool {
        return indexOfOptionsButton != nil
    }

    private func updateOptionsMenu() {
        guard let optionsButton = optionsButtonController?.optionsButton else {
            return
        }
        if let optionsButtonController, optionsButtonController.set(familyName: affordance.familyName) {
            if !haveAddedOptionsButton {
                optionsButton.sizeToFit()
                optionsButtonController.delegate = self
                let wrapper = AccessoryWrapper(optionsButton, height: bounds.height)
                add(accessory: wrapper)
            } else {
                invalidateIntrinsicContentSize()
                layoutSubviews()
                superview?.needsLayout = true
            }
            return
        }
        temporarilyRemoveOptionsButton()
    }

    public func fontFamilyMemberPickerView(_ fontFamilyMemberPickerView: FontFamilyMemberPickerView,
                                           didSelectFontName name: String) {
        if let font = font {
            delegate?.fontPickerCompositeView(self, didSelectFont: font)
        }
    }

    public func sizePickerView(_ sizePickerView: SizePickerView,
                               didChangeSizeTo size: Double) {
        if let font = font {
            delegate?.fontPickerCompositeView(self, didSelectFont: font)
        }
    }

    func optionsDidChange(_ controller: OptionsButtonController) {
        if let font = font {
            delegate?.fontPickerCompositeView(self, didSelectFont: font)
        }
    }
}

