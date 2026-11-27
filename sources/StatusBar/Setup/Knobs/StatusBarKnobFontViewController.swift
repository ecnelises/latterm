//
//  StatusBarKnobFontViewController.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/26/21.
//

import Foundation
import BetterFontPicker

@objc(iTermStatusBarKnobFontViewController)
class StatusBarKnobFontViewController: NSViewController {
    private var affordance: BetterFontPicker.FontPickerCompositeView!
    private var checkbox: NSButton!
    private var font: NSFont? {
        get {
            if checkbox.state == .on {
                return affordance.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
            }
            return nil
        }
        set {
            if let font = newValue {
                checkbox.state = .on
                affordance.font = font
                affordance.isHidden = false
            } else {
                checkbox.state = .off
                affordance.isHidden = true
            }
        }
    }

    convenience init() {
        self.init(nibName: nil, bundle: nil)
    }

    override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 702, height: 27))
        root.autoresizesSubviews = false

        let picker = BetterFontPicker.FontPickerCompositeView(frame: NSRect(x: 271, y: 0, width: 431, height: 25))
        let button = NSButton(checkboxWithTitle: "", target: self, action: #selector(checkboxChanged(_:)))
        button.frame = NSRect(x: 0, y: 5, width: 272, height: 16)
        button.alignment = .right
        button.state = .on

        root.addSubview(picker)
        root.addSubview(button)

        affordance = picker
        checkbox = button
        view = root
    }

    @objc func checkboxChanged(_ sender: NSButton) {
        if checkbox.state == .on {
            affordance.isHidden = false
        } else {
            affordance.isHidden = true
        }
    }
}

extension StatusBarKnobFontViewController: iTermStatusBarKnobViewController {
    func setDescription(_ description: String, placeholder _: String) {
        checkbox.title = description
        sizeToFit()
    }

    func controlOffset() -> CGFloat {
        return NSMinX(affordance.frame)
    }

    func sizeToFit() {
        checkbox.sizeToFit()
        let margin = CGFloat(8.0)
        view.frame = NSRect(x: view.frame.minX,
                            y: view.frame.minY,
                            width: checkbox.frame.width + margin + affordance.frame.width,
                            height: affordance.frame.height + CGFloat(2.0))
        checkbox.frame = NSRect(x: 0,
                                y: (affordance.frame.height - checkbox.frame.height) / CGFloat(2.0) + CGFloat(1.5),
                                width: checkbox.frame.width,
                                height: checkbox.frame.height)
        affordance.frame = NSRect(x: checkbox.frame.maxX + margin,
                                  y: 0,
                                  width: affordance.frame.width,
                                  height: affordance.frame.height)
    }

    func setHelp(_ url: URL) {
    }

    func value() -> Any {
        let theFont = font
        return theFont?.stringValue ?? ""
    }

    func setValue(_ value: Any) {
        if let stringValue = value as? String,
            !stringValue.isEmpty {
            let fontValue = stringValue.fontValue(withLigaturesEnabled: true)
            font = fontValue
            affordance.isHidden = false
            return
        }
        font = nil
    }
}
