import XCTest
@testable import iTerm2SharedARC

final class SessionViewTests: XCTestCase {
    private let dismemberScrollViewKey = "DismemberScrollView"
    private var savedDismemberScrollView: Any?

    override func setUp() {
        super.setUp()
        savedDismemberScrollView = iTermUserDefaults.userDefaults().object(forKey: dismemberScrollViewKey)
    }

    override func tearDown() {
        let defaults = iTermUserDefaults.userDefaults()
        if let savedDismemberScrollView {
            defaults.set(savedDismemberScrollView, forKey: dismemberScrollViewKey)
        } else {
            defaults.removeObject(forKey: dismemberScrollViewKey)
        }
        iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        super.tearDown()
    }

    func testScrollerRemainsContainedWithoutLegacyPreference() throws {
        iTermUserDefaults.userDefaults().removeObject(forKey: dismemberScrollViewKey)
        try assertScrollerRemainsContained()
    }

    func testScrollerRemainsContainedWithLegacyPreferenceEnabled() throws {
        iTermUserDefaults.userDefaults().set(true, forKey: dismemberScrollViewKey)
        try assertScrollerRemainsContained()
    }

    private func assertScrollerRemainsContained(file: StaticString = #filePath,
                                                line: UInt = #line) throws {
        iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        let sessionView = SessionView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        let scrollView = try XCTUnwrap(sessionView.scrollview, file: file, line: line)
        let scroller = try XCTUnwrap(scrollView.verticalScroller, file: file, line: line)
        XCTAssertTrue(scroller.isDescendant(of: scrollView), file: file, line: line)

        for style: NSScroller.Style in [.legacy, .overlay, .legacy] {
            scrollView.scrollerStyle = style
            scrollView.tile()
            XCTAssertTrue(scrollView.verticalScroller === scroller, file: file, line: line)
            XCTAssertTrue(scroller.isDescendant(of: scrollView), file: file, line: line)
            XCTAssertEqual(scroller.scrollerStyle, style, file: file, line: line)
        }
    }
}

final class ToolWrapperLifetimeTests: XCTestCase {
    func testNamedWrapperIsReleasedWithoutShutdown() throws {
        let wrapperClass = try XCTUnwrap(NSClassFromString("iTermToolWrapper") as? NSView.Type)
        weak var weakWrapper: NSView?
        autoreleasepool {
            let wrapper = wrapperClass.init(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
            wrapper.setValue("Profiles", forKey: "name")
            weakWrapper = wrapper
            XCTAssertTrue(wrapper.subviews.compactMap { $0 as? NSTextField }
                .contains { $0.stringValue == "Profiles" })
        }
        XCTAssertNil(weakWrapper)
    }
}
