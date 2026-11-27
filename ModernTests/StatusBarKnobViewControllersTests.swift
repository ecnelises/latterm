//
//  StatusBarKnobViewControllersTests.swift
//  ModernTests
//

import Cocoa
import XCTest
@testable import iTerm2SharedARC

@MainActor
final class StatusBarKnobViewControllersTests: XCTestCase {
    func testCheckboxKnobViewControllerLoadsWithoutXIB() {
        let vc = iTermStatusBarKnobCheckboxViewController()
        _ = vc.view
        vc.setDescription("Show icon", placeholder: "")
        vc.setValue(NSNumber(value: true))
        XCTAssertEqual((vc.value() as? NSNumber)?.boolValue, true)
        vc.setValue(NSNumber(value: false))
        XCTAssertEqual((vc.value() as? NSNumber)?.boolValue, false)
        XCTAssertEqual(vc.controlOffset(), 0)
        XCTAssertGreaterThan(vc.view.frame.width, 0)
        XCTAssertGreaterThan(vc.view.frame.height, 0)
    }

    func testColorKnobViewControllerLoadsWithoutXIB() {
        let vc = iTermStatusBarKnobColorViewController()
        _ = vc.view
        vc.setDescription("Tint:", placeholder: "")
        let inputColor = NSColor(srgbRed: 0.2, green: 0.4, blue: 0.8, alpha: 1.0)
        vc.setValue(inputColor.dictionaryValue)
        XCTAssertNotNil(vc.value())
        XCTAssertGreaterThan(vc.controlOffset(), 0)
        XCTAssertGreaterThan(vc.view.frame.width, 0)
        XCTAssertGreaterThan(vc.view.frame.height, 0)
    }

    func testFontKnobViewControllerLoadsWithoutXIB() {
        let vc = StatusBarKnobFontViewController()
        _ = vc.view
        vc.setDescription("Custom font", placeholder: "")
        vc.setValue("")
        XCTAssertEqual(vc.value() as? String, "")
        let menlo = NSFont(name: "Menlo", size: 12) ?? NSFont.systemFont(ofSize: 12)
        vc.setValue(menlo.stringValue)
        XCTAssertFalse((vc.value() as? String ?? "").isEmpty)
        XCTAssertGreaterThan(vc.controlOffset(), 0)
        XCTAssertGreaterThan(vc.view.frame.width, 0)
        XCTAssertGreaterThan(vc.view.frame.height, 0)
    }

    func testTextKnobViewControllerLoadsWithoutXIB() throws {
        let vc = try XCTUnwrap(iTermStatusBarKnobTextViewController())
        _ = vc.view
        vc.setDescription("Format:", placeholder: "Enter format")
        vc.setValue("hello" as NSString)
        XCTAssertEqual(vc.value() as? String, "hello")
        XCTAssertGreaterThan(vc.controlOffset(), 0)
        XCTAssertGreaterThan(vc.view.frame.width, 0)
        XCTAssertGreaterThan(vc.view.frame.height, 0)
    }

    func testNumericKnobViewControllerLoadsWithoutXIB() throws {
        let vc = iTermStatusBarKnobNumericViewController()
        _ = vc.view
        vc.setDescription("Interval:", placeholder: "")
        vc.setValue(NSNumber(value: 42.5))
        let number = try XCTUnwrap(vc.value() as? NSNumber)
        XCTAssertEqual(number.doubleValue, 42.5, accuracy: 0.0001)
        XCTAssertGreaterThan(vc.controlOffset(), 0)
        XCTAssertGreaterThan(vc.view.frame.width, 0)
        XCTAssertGreaterThan(vc.view.frame.height, 0)
    }
}
