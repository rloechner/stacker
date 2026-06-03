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
}
