import XCTest
@testable import Stacker

final class WindowAttachmentEngineTests: XCTestCase {

    func testIsMaximizedLikeWhenAnchorFillsVisibleFrame() {
        let visible = CGRect(x: 0, y: 100, width: 1000, height: 800)
        let anchor = CGRect(x: 0, y: 100, width: 995, height: 795)

        XCTAssertTrue(WindowAttachmentEngine.isMaximizedLike(anchorFrame: anchor, visibleFrame: visible))
    }

    func testIsMaximizedLikeFalseForWindowedAnchor() {
        let visible = CGRect(x: 0, y: 100, width: 1000, height: 800)
        let anchor = CGRect(x: 120, y: 200, width: 700, height: 500)

        XCTAssertFalse(WindowAttachmentEngine.isMaximizedLike(anchorFrame: anchor, visibleFrame: visible))
    }

    func testIsMaximizedLikeFalseWhenNotIntersectingVisibleFrame() {
        let visible = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let anchor = CGRect(x: 2000, y: 2000, width: 900, height: 700)

        XCTAssertFalse(WindowAttachmentEngine.isMaximizedLike(anchorFrame: anchor, visibleFrame: visible))
    }

    func testClampedFloatingOriginStaysInsideAnchor() {
        let engine = WindowAttachmentEngine()
        let anchor = CGRect(x: 100, y: 200, width: 1200, height: 900)
        let panelSize = CGSize(width: 180, height: 42)

        let origin = engine.clampedFloatingOrigin(
            for: anchor,
            panelSize: panelSize,
            horizontalOffset: 500,
            verticalOffset: -500
        )

        XCTAssertGreaterThanOrEqual(origin.x, anchor.minX + WindowAttachmentEngine.floatingDefaultInset)
        XCTAssertLessThanOrEqual(origin.x + panelSize.width, anchor.maxX - WindowAttachmentEngine.floatingDefaultInset)
        XCTAssertGreaterThanOrEqual(origin.y, anchor.minY + WindowAttachmentEngine.floatingDefaultInset)
        XCTAssertLessThanOrEqual(origin.y + panelSize.height, anchor.maxY - WindowAttachmentEngine.floatingDefaultInset)
    }

    func testLayerZeroWindowCoveringPanelOccludesOverlay() {
        XCTAssertTrue(
            isCovered(
                records: [
                    record(pid: otherPID, layer: 0, frame: CGRect(x: 110, y: 510, width: 180, height: 80)),
                    record(pid: appPID, layer: 0, frame: anchorFrame)
                ]
            )
        )
    }

    func testNonZeroLayerUtilityWindowCoveringPanelOccludesOverlay() {
        XCTAssertTrue(
            isCovered(
                records: [
                    record(pid: otherPID, ownerName: "Screenshot", layer: 25, frame: CGRect(x: 110, y: 510, width: 180, height: 80)),
                    record(pid: appPID, layer: 0, frame: anchorFrame)
                ],
                frontmostPID: otherPID
            )
        )
    }

    func testScreenSizedCaptureOverlayDoesNotOccludeAfterBrowserRefocus() {
        XCTAssertFalse(
            isCovered(
                records: [
                    record(pid: otherPID, ownerName: "Screenshot", layer: 25, frame: screenFrame),
                    record(pid: appPID, layer: 0, frame: anchorFrame)
                ],
                frontmostPID: appPID
            )
        )
    }

    func testScreenSizedCaptureOverlayOccludesWhileCaptureUtilityFrontmost() {
        XCTAssertTrue(
            isCovered(
                records: [
                    record(pid: otherPID, ownerName: "Screenshot", layer: 25, frame: screenFrame),
                    record(pid: appPID, layer: 0, frame: anchorFrame)
                ],
                frontmostPID: otherPID
            )
        )
    }

    func testScreenshotThumbnailOverPanelOccludesEvenWhenBrowserFrontmost() {
        XCTAssertTrue(
            isCovered(
                records: [
                    record(pid: otherPID, ownerName: "screencaptureui", layer: 25, frame: CGRect(x: 110, y: 510, width: 180, height: 80)),
                    record(pid: appPID, layer: 0, frame: anchorFrame)
                ],
                frontmostPID: appPID
            )
        )
    }

    func testScreenshotThumbnailAwayFromPanelDoesNotOcclude() {
        XCTAssertFalse(
            isCovered(
                records: [
                    record(pid: otherPID, ownerName: "screencaptureui", layer: 25, frame: CGRect(x: 900, y: 50, width: 180, height: 80)),
                    record(pid: appPID, layer: 0, frame: anchorFrame)
                ],
                frontmostPID: appPID
            )
        )
    }

    func testStackerOwnedWindowsDoNotOccludeOverlay() {
        XCTAssertFalse(
            isCovered(
                records: [
                    record(pid: currentPID, ownerName: "Screenshot", layer: 25, frame: CGRect(x: 110, y: 510, width: 180, height: 80)),
                    record(pid: appPID, layer: 0, frame: anchorFrame)
                ]
            )
        )
    }

    func testAnchorBrowserWindowDoesNotOccludeOverlay() {
        XCTAssertFalse(
            isCovered(
                records: [
                    record(pid: appPID, layer: 0, frame: anchorFrame)
                ]
            )
        )
    }

    func testSmallNoiseWindowsDoNotOccludeOverlay() {
        XCTAssertFalse(
            isCovered(
                records: [
                    record(pid: otherPID, ownerName: "Screenshot", layer: 25, frame: CGRect(x: 120, y: 520, width: 20, height: 20)),
                    record(pid: appPID, layer: 0, frame: anchorFrame)
                ]
            )
        )
    }

    func testNonZeroSystemChromeDoesNotOccludeOverlay() {
        XCTAssertFalse(
            isCovered(
                records: [
                    record(pid: otherPID, ownerName: "Window Server", layer: 25, frame: CGRect(x: 0, y: 500, width: 1200, height: 80)),
                    record(pid: appPID, layer: 0, frame: anchorFrame)
                ]
            )
        )
    }

    func testNonOverlappingWindowsDoNotOccludeOverlay() {
        XCTAssertFalse(
            isCovered(
                records: [
                    record(pid: otherPID, layer: 0, frame: CGRect(x: 700, y: 700, width: 180, height: 80)),
                    record(pid: appPID, layer: 0, frame: anchorFrame)
                ]
            )
        )
    }

    private var currentPID: pid_t { 10 }
    private var appPID: pid_t { 20 }
    private var otherPID: pid_t { 30 }
    private var screenFrame: CGRect { CGRect(x: 0, y: 0, width: 1200, height: 800) }
    private var anchorFrame: CGRect { CGRect(x: 100, y: 100, width: 500, height: 400) }
    private var panelFrame: CGRect { CGRect(x: 120, y: 520, width: 160, height: 44) }

    private func record(pid: pid_t, ownerName: String? = nil, layer: Int, frame: CGRect) -> StackOverlayWindowRecord {
        StackOverlayWindowRecord(ownerPID: pid, ownerName: ownerName, layer: layer, frame: frame)
    }

    private func isCovered(records: [StackOverlayWindowRecord], frontmostPID: pid_t? = nil) -> Bool {
        StackOverlayOcclusion.isCoveredByHigherWindow(
            records: records,
            currentPID: currentPID,
            frontmostPID: frontmostPID,
            appPID: appPID,
            anchorFrame: anchorFrame,
            panelFrame: panelFrame,
            placementMode: .edgeDocked,
            screenFrames: [screenFrame]
        )
    }
}
