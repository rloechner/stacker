import AppKit
import CoreGraphics

struct StackOverlayWindowRecord {
    let ownerPID: pid_t
    let ownerName: String?
    let windowName: String?
    let layer: Int
    let frame: CGRect
    let alpha: CGFloat

    init(ownerPID: pid_t, ownerName: String? = nil, windowName: String? = nil, layer: Int, frame: CGRect, alpha: CGFloat = 1) {
        self.ownerPID = ownerPID
        self.ownerName = ownerName
        self.windowName = windowName
        self.layer = layer
        self.frame = frame
        self.alpha = alpha
    }
}

enum StackOverlayOcclusion {
    static func currentWindowRecords() -> [StackOverlayWindowRecord] {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        var records: [StackOverlayWindowRecord] = []
        for windowInfo in windowList {
            if let record = windowRecord(from: windowInfo) {
                records.append(record)
            }
        }
        return records
    }

    static func isCoveredByHigherWindow(
        records: [StackOverlayWindowRecord],
        currentPID: pid_t,
        frontmostPID: pid_t?,
        appPID: pid_t,
        anchorFrame: CGRect,
        panelFrame: CGRect,
        placementMode: StackOverlayPlacementMode,
        screenFrames: [CGRect]? = nil
    ) -> Bool {
        let screenFrames = screenFrames ?? NSScreen.screens.map(\.frame)
        for record in records {
            guard isRelevant(record, currentPID: currentPID) else {
                continue
            }

            if record.ownerPID == appPID && approximatelyMatches(record.frame, anchorFrame) {
                return false
            }

            if record.layer > 0 {
                guard isScreenCaptureUtilityWindow(record) else { continue }

                // The floating post-capture thumbnail is a small panel the user can
                // drag over the widget; it occludes on intersection no matter which
                // app is frontmost (screencaptureui is a UI agent and never reports
                // as the frontmost application).
                if !isScreenSized(record.frame, screenFrames: screenFrames) {
                    if record.frame.intersects(panelFrame) {
                        return true
                    }
                    continue
                }

                // Screen-sized capture chrome (the selection overlay) only counts
                // while the capture utility is actively frontmost; lingering chrome
                // after the browser regains focus must not keep the widget hidden.
                guard record.ownerPID == frontmostPID else { continue }
            }

            if record.frame.intersects(panelFrame) {
                return true
            }

            if placementMode == .edgeDocked,
               intersectionArea(record.frame, anchorFrame) > anchorFrameArea(anchorFrame) * 0.1 {
                return true
            }
        }

        return false
    }

    private static func isRelevant(_ record: StackOverlayWindowRecord, currentPID: pid_t) -> Bool {
        record.ownerPID > 0 &&
        record.ownerPID != currentPID &&
        record.alpha > 0.01 &&
        record.frame.width > 24 &&
        record.frame.height > 24
    }

    private static func isScreenCaptureUtilityWindow(_ record: StackOverlayWindowRecord) -> Bool {
        let searchableText = [record.ownerName, record.windowName]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")

        return searchableText.contains("screenshot") ||
        searchableText.contains("screen shot") ||
        searchableText.contains("screencapture") ||
        searchableText.contains("screen capture")
    }

    private static func isScreenSized(_ frame: CGRect, screenFrames: [CGRect]) -> Bool {
        screenFrames.contains { screenFrame in
            let screenArea = screenFrame.width * screenFrame.height
            guard screenArea > 0 else { return false }
            return intersectionArea(frame, screenFrame) / screenArea > 0.9
        }
    }

    private static func windowRecord(from windowInfo: [String: Any]) -> StackOverlayWindowRecord? {
        guard let ownerPID = pidValue(from: windowInfo[kCGWindowOwnerPID as String]),
              let layer = intValue(from: windowInfo[kCGWindowLayer as String]),
              let frame = appKitFrame(fromCGWindowInfo: windowInfo) else {
            return nil
        }

        let ownerName = windowInfo[kCGWindowOwnerName as String] as? String
        let windowName = windowInfo[kCGWindowName as String] as? String
        let alpha = cgFloatValue(from: windowInfo[kCGWindowAlpha as String]) ?? 1
        return StackOverlayWindowRecord(
            ownerPID: ownerPID,
            ownerName: ownerName,
            windowName: windowName,
            layer: layer,
            frame: frame,
            alpha: alpha
        )
    }

    private static func appKitFrame(fromCGWindowInfo windowInfo: [String: Any]) -> CGRect? {
        guard let bounds = windowInfo[kCGWindowBounds as String] as? NSDictionary,
              let rawFrame = CGRect(dictionaryRepresentation: bounds) else {
            return nil
        }

        let primaryMaxY = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.maxY
            ?? NSScreen.main?.frame.maxY
            ?? NSScreen.screens.map(\.frame.maxY).max()
            ?? 0

        return CGRect(
            x: rawFrame.origin.x,
            y: primaryMaxY - rawFrame.origin.y - rawFrame.height,
            width: rawFrame.width,
            height: rawFrame.height
        )
    }

    private static func approximatelyMatches(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) <= 12 &&
        abs(lhs.minY - rhs.minY) <= 12 &&
        abs(lhs.width - rhs.width) <= 24 &&
        abs(lhs.height - rhs.height) <= 24
    }

    private static func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        return max(0, intersection.width) * max(0, intersection.height)
    }

    private static func anchorFrameArea(_ frame: CGRect) -> CGFloat {
        max(1, frame.width * frame.height)
    }

    private static func pidValue(from value: Any?) -> pid_t? {
        if let pid = value as? pid_t {
            return pid
        }
        if let number = value as? NSNumber {
            return pid_t(number.int32Value)
        }
        if let intValue = value as? Int {
            return pid_t(intValue)
        }
        return nil
    }

    private static func intValue(from value: Any?) -> Int? {
        if let intValue = value as? Int {
            return intValue
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        return nil
    }

    private static func cgFloatValue(from value: Any?) -> CGFloat? {
        if let cgFloat = value as? CGFloat {
            return cgFloat
        }
        if let double = value as? Double {
            return CGFloat(double)
        }
        if let number = value as? NSNumber {
            return CGFloat(number.doubleValue)
        }
        return nil
    }
}
