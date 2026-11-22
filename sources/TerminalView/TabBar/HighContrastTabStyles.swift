// High-contrast variants of the classic light and dark tab themes.
import AppKit

@objc(PSMDarkHighContrastTabStyle)
final class DarkHighContrastTabStyle: PSMDarkTabStyle {
    override func name() -> String { "Dark High Contrast" }

    private var highVisibility: Bool {
        guard let tabBar else { return false }
        let value = tabBar.delegate?.tabView?(tabBar, valueOfOption: .highVisibility)
        return (value as? NSNumber)?.boolValue ?? false
    }

    override func textColorDefaultSelected(_ selected: Bool, backgroundColor: NSColor?,
                                           windowIsMainAndAppIsActive: Bool) -> NSColor {
        selected && highVisibility ? .black : .white
    }

    override func accessoryTextColor() -> NSColor { .white }

    override func backgroundColorSelected(_ selected: Bool, highlightAmount: CGFloat) -> NSColor {
        let intensity: CGFloat = selected ? (highVisibility ? 0.8 : 0.2) + highlightAmount * 0.05 : 0.03
        return NSColor(calibratedWhite: intensity, alpha: 1)
    }

    override func fontSize() -> CGFloat { 12 }
}

@objc(PSMLightHighContrastTabStyle)
final class LightHighContrastTabStyle: PSMYosemiteTabStyle {
    override func name() -> String { "Light High Contrast" }

    override func textColorDefaultSelected(_ selected: Bool, backgroundColor: NSColor?,
                                           windowIsMainAndAppIsActive: Bool) -> NSColor { .black }

    override func accessoryTextColor() -> NSColor { .black }

    override func backgroundColorSelected(_ selected: Bool, highlightAmount: CGFloat) -> NSColor {
        if selected { return .windowBackgroundColor }
        let intensity = 180 / 255.0 - highlightAmount * 0.1
        return NSColor(srgbRed: intensity, green: intensity, blue: intensity, alpha: 1)
    }

    private var dividerColor: NSColor { NSColor(white: 140 / 255.0, alpha: 1) }

    override func topLineColorSelected(_ selected: Bool) -> NSColor {
        selected ? super.topLineColorSelected(selected) : dividerColor
    }

    override func bottomLineColorSelected(_ selected: Bool) -> NSColor { dividerColor }
    override var tabBarColor: NSColor? { NSColor(calibratedWhite: 0, alpha: 0.3) }
    override func fontSize() -> CGFloat { 12 }
}
