import XCTest
@testable import Stacker

final class BrowserSupportTests: XCTestCase {

    // MARK: - Browser matching

    func testBrowserMatchingByBundleIdentifier() {
        XCTAssertEqual(
            BrowserSupport.browser(bundleIdentifier: "com.google.Chrome", name: nil),
            .chrome
        )
        XCTAssertEqual(
            BrowserSupport.browser(bundleIdentifier: "com.brave.Browser", name: nil),
            .brave
        )
        XCTAssertEqual(
            BrowserSupport.browser(bundleIdentifier: "com.apple.Safari", name: nil),
            .safari
        )
        XCTAssertEqual(
            BrowserSupport.browser(bundleIdentifier: "com.microsoft.edgemac", name: nil),
            .edge
        )
        XCTAssertEqual(
            BrowserSupport.browser(bundleIdentifier: "org.mozilla.firefox", name: nil),
            .firefox
        )
        XCTAssertNil(BrowserSupport.browser(bundleIdentifier: "com.unknown.App", name: nil))
    }

    func testBrowserMatchingByNormalizedNameFallback() {
        // Name fallback when bundle ID is missing or unknown
        XCTAssertEqual(
            BrowserSupport.browser(bundleIdentifier: nil, name: "Brave Browser"),
            .brave
        )
        XCTAssertEqual(
            BrowserSupport.browser(bundleIdentifier: "unknown.bundle", name: "Google Chrome"),
            .chrome
        )
        XCTAssertEqual(
            BrowserSupport.browser(bundleIdentifier: nil, name: "SAFARI"),
            .safari
        )
        XCTAssertEqual(
            BrowserSupport.browser(bundleIdentifier: nil, name: "  Microsoft Edge  "),
            .edge
        )
        XCTAssertNil(BrowserSupport.browser(bundleIdentifier: nil, name: "Random App"))
    }

    // MARK: - Window title normalization (exercises internal separator & browser name logic)

    func testWindowTitleNormalizationStripsBrowserSuffixAndPrefix() {
        let chromeApp = TargetApplication(
            name: "Google Chrome",
            bundleIdentifier: "com.google.Chrome",
            processIdentifier: 12345,
            windowCount: 2
        )

        // Suffix form with em-dash
        XCTAssertEqual(
            BrowserSupport.windowTitle(for: chromeApp, rawTitle: "My Document — Google Chrome", fallbackIndex: 1),
            "My Document"
        )

        // Prefix form with regular dash
        XCTAssertEqual(
            BrowserSupport.windowTitle(for: chromeApp, rawTitle: "Google Chrome - Another Page", fallbackIndex: 2),
            "Another Page"
        )

        // En-dash variant and multi-part
        XCTAssertEqual(
            BrowserSupport.windowTitle(for: chromeApp, rawTitle: "Foo – Bar – Chrome", fallbackIndex: 3),
            "Bar"
        )
    }

    func testWindowTitleFallbackWhenEmptyOrUnknown() {
        let edgeApp = TargetApplication(
            name: "Microsoft Edge",
            bundleIdentifier: "com.microsoft.edgemac",
            processIdentifier: 67890,
            windowCount: 1
        )

        // Empty / whitespace title falls back to "Edge Window N"
        XCTAssertEqual(
            BrowserSupport.windowTitle(for: edgeApp, rawTitle: "   ", fallbackIndex: 7),
            "Edge Window 7"
        )

        // Non-matching title is returned as-is
        let unknown = TargetApplication(
            name: "Some Other",
            bundleIdentifier: "com.other",
            processIdentifier: 111,
            windowCount: 0
        )
        XCTAssertEqual(
            BrowserSupport.windowTitle(for: unknown, rawTitle: "Just a Title", fallbackIndex: 0),
            "Just a Title"
        )
    }
}
