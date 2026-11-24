//
//  URLIDNTests.swift
//  ModernTests
//

import XCTest
@testable import iTerm2SharedARC

final class URLIDNTests: XCTestCase {
    func testASCIIHostnamePassesThroughUnchanged() {
        XCTAssertEqual(NSURL.idnEncodedHostname("example.com"), "example.com")
        XCTAssertEqual(NSURL.idnDecodedHostname("example.com"), "example.com")
    }

    func testIDNEncodeAndDecodeRoundTrips() {
        let cases: [(unicode: String, punycode: String)] = [
            ("中国.icom.museum", "xn--fiqs8s.icom.museum"),
            ("á中国.icom.museum", "xn--1ca0960bnsf.icom.museum"),
            ("例え.jp", "xn--r8jz45g.jp"),
            ("münchen.de", "xn--mnchen-3ya.de"),
        ]
        for (unicode, punycode) in cases {
            XCTAssertEqual(NSURL.idnEncodedHostname(unicode), punycode)
            XCTAssertEqual(NSURL.idnDecodedHostname(punycode), unicode)
        }
        XCTAssertEqual(NSURL.idnDecodedHostname("XN--FIQS8S.icom.museum"), "中国.icom.museum")
        XCTAssertEqual(NSURL.idnDecodedHostname("XN--FIQS8S.ICOM.MUSEUM"), "中国.ICOM.MUSEUM")
        XCTAssertEqual(NSURL.idnDecodedHostname("XN--1CA0960BNSF.icom.museum"), "á中国.icom.museum")
        XCTAssertEqual(NSURL.idnDecodedHostname("XN--R8JZ45G.jp"), "例え.jp")
        XCTAssertEqual(NSURL.idnDecodedHostname("XN--mnchen-3YA.de"), "münchen.de")
    }

    func testURLHelpersTransformHostnameOnly() {
        XCTAssertEqual(
            NSURL.idnEncodedURL("https://中国.icom.museum/路径?q=中"),
            "https://xn--fiqs8s.icom.museum/路径?q=中"
        )
        XCTAssertEqual(
            NSURL.idnDecodedURL("https://xn--fiqs8s.icom.museum/path"),
            "https://中国.icom.museum/path"
        )
    }

    func testInvalidPunycodePassesThroughUnchanged() {
        XCTAssertEqual(NSURL.idnDecodedHostname("xn--"), "xn--")
        XCTAssertEqual(NSURL.idnDecodedHostname("xn--abc-"), "xn--abc-")
        XCTAssertEqual(NSURL.idnDecodedHostname("xn--!invalid!.com"), "xn--!invalid!.com")
    }
}
