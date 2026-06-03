import AppKit
import CoreGraphics

enum StackOverlayPlacementMode: Equatable {
    case edgeDocked
    case floatingInWindow
}

enum StackOverlayHealth: String {
    case visible
    case hidden
    case clamped
    case missingAnchor
    case minimizedOrFullscreen
    case floatingOnMaximized
    case permissionBlocked
    case unsupportedState
    case degraded

    var surfaceTitle: String {
        switch self {
        case .visible:
            return "Live"
        case .hidden:
            return "Hidden"
        case .clamped:
            return "Needs Attention"
        case .missingAnchor:
            return "Needs Attention"
        case .minimizedOrFullscreen:
            return "Unsupported State"
        case .floatingOnMaximized:
            return "Floating"
        case .permissionBlocked:
            return "Needs Attention"
        case .unsupportedState:
            return "Unsupported State"
        case .degraded:
            return "Paused"
        }
    }

    var surfaceMessage: String {
        switch self {
        case .visible:
            return "This stack is live. Move or resize any member and the others follow."
        case .hidden:
            return "This stack is live, but its marker is hidden."
        case .clamped:
            return "The stack marker was kept inside the visible screen area."
        case .missingAnchor:
            return "Stacker cannot find the active window to place the marker."
        case .minimizedOrFullscreen:
            return "The active stack window is minimized or fullscreen, which is outside v1 support."
        case .floatingOnMaximized:
            return "The switcher is floating inside the maximized browser window. Drag it to move."
        case .permissionBlocked:
            return "Accessibility permission is required to keep this stack attached."
        case .unsupportedState:
            return "This window state is outside v1 support."
        case .degraded:
            return "Stacker lost contact with the browser windows. The stack is paused."
        }
    }

    var isAttentionState: Bool {
        switch self {
        case .clamped, .missingAnchor, .permissionBlocked, .degraded:
            return true
        case .visible, .hidden, .minimizedOrFullscreen, .floatingOnMaximized, .unsupportedState:
            return false
        }
    }

    var isWidgetDisplayed: Bool {
        switch self {
        case .visible, .clamped, .floatingOnMaximized:
            return true
        case .hidden, .missingAnchor, .minimizedOrFullscreen, .permissionBlocked, .unsupportedState, .degraded:
            return false
        }
    }
}

struct StackOverlayAttachmentState {
    let health: StackOverlayHealth
    let anchorFrame: CGRect?

    static func visible(anchorFrame: CGRect) -> StackOverlayAttachmentState {
        StackOverlayAttachmentState(health: .visible, anchorFrame: anchorFrame)
    }

    static let hidden = StackOverlayAttachmentState(health: .hidden, anchorFrame: nil)
    static let missingAnchor = StackOverlayAttachmentState(health: .missingAnchor, anchorFrame: nil)
    static let minimizedOrFullscreen = StackOverlayAttachmentState(health: .minimizedOrFullscreen, anchorFrame: nil)
    static let permissionBlocked = StackOverlayAttachmentState(health: .permissionBlocked, anchorFrame: nil)
    static let unsupportedState = StackOverlayAttachmentState(health: .unsupportedState, anchorFrame: nil)
}

struct StackOverlayResolvedAttachment {
    let health: StackOverlayHealth
    let anchorFrame: CGRect?
    let visibleFrame: CGRect?
    let origin: CGPoint?
    let dockPosition: StackOverlayDockPosition
    let horizontalSide: StackOverlayHorizontalSide
    let placementMode: StackOverlayPlacementMode
}

struct WindowAttachmentEngine {
    var edgeInset: CGFloat = 18
    var screenInset: CGFloat = 12
    var sideGap: CGFloat = 0
    var topGap: CGFloat = 0
    var bottomGap: CGFloat = 0
    static let floatingDefaultInset: CGFloat = 14
    static let maximizedFillThreshold: CGFloat = 0.92
    private static let unsetHorizontalOffsetSentinel: CGFloat = -100_000

    /// True when the anchor nearly fills the screen visible area (green-button maximize), not Spaces fullscreen.
    static func isMaximizedLike(anchorFrame: CGRect, visibleFrame: CGRect) -> Bool {
        let intersection = anchorFrame.intersection(visibleFrame)
        guard intersection.width > 0, intersection.height > 0 else { return false }

        let visibleArea = max(1, visibleFrame.width * visibleFrame.height)
        let intersectionArea = intersection.width * intersection.height
        guard intersectionArea / visibleArea >= maximizedFillThreshold else { return false }

        let widthRatio = intersection.width / max(1, visibleFrame.width)
        let heightRatio = intersection.height / max(1, visibleFrame.height)
        return widthRatio >= maximizedFillThreshold && heightRatio >= maximizedFillThreshold
    }

    func resolve(
        state: StackOverlayAttachmentState,
        panelSize: CGSize,
        panelFrame: CGRect,
        placementPreference: StackOverlayPlacementPreference,
        preferredDockPosition: StackOverlayDockPosition,
        horizontalOffset: CGFloat,
        verticalOffset: CGFloat,
        floatingHorizontalOffset: CGFloat = 0,
        floatingVerticalOffset: CGFloat = 0
    ) -> StackOverlayResolvedAttachment {
        let fallbackDockPosition = placementPreference.dockPosition ?? preferredDockPosition
        guard state.health == .visible || state.health == .clamped else {
            return StackOverlayResolvedAttachment(
                health: state.health,
                anchorFrame: state.anchorFrame.map(convertAXFrameToScreenCoordinates),
                visibleFrame: nil,
                origin: nil,
                dockPosition: fallbackDockPosition,
                horizontalSide: .left,
                placementMode: .edgeDocked
            )
        }

        guard let rawAnchorFrame = state.anchorFrame else {
            return StackOverlayResolvedAttachment(
                health: .missingAnchor,
                anchorFrame: nil,
                visibleFrame: nil,
                origin: nil,
                dockPosition: fallbackDockPosition,
                horizontalSide: .left,
                placementMode: .edgeDocked
            )
        }

        let anchorFrame = convertAXFrameToScreenCoordinates(rawAnchorFrame)
        guard let visibleFrame = referenceVisibleFrame(for: anchorFrame, panelFrame: panelFrame) else {
            return StackOverlayResolvedAttachment(
                health: .unsupportedState,
                anchorFrame: anchorFrame,
                visibleFrame: nil,
                origin: nil,
                dockPosition: fallbackDockPosition,
                horizontalSide: .left,
                placementMode: .edgeDocked
            )
        }

        if !hasVisibleRoomForWidget(anchorFrame: anchorFrame, visibleFrame: visibleFrame, panelSize: panelSize),
           MaximizedWindowOverlayPreference.isEnabled,
           Self.isMaximizedLike(anchorFrame: anchorFrame, visibleFrame: visibleFrame) {
            let floatingDockPosition = MaximizedWindowOverlayPreference.orientation.dockPosition
            let origin = clampedFloatingOrigin(
                for: anchorFrame,
                panelSize: panelSize,
                horizontalOffset: floatingHorizontalOffset,
                verticalOffset: floatingVerticalOffset
            )
            return StackOverlayResolvedAttachment(
                health: .floatingOnMaximized,
                anchorFrame: anchorFrame,
                visibleFrame: visibleFrame,
                origin: origin,
                dockPosition: floatingDockPosition,
                horizontalSide: .left,
                placementMode: .floatingInWindow
            )
        }

        guard hasVisibleRoomForWidget(anchorFrame: anchorFrame, visibleFrame: visibleFrame, panelSize: panelSize) else {
            return StackOverlayResolvedAttachment(
                health: .hidden,
                anchorFrame: anchorFrame,
                visibleFrame: visibleFrame,
                origin: nil,
                dockPosition: fallbackDockPosition,
                horizontalSide: .left,
                placementMode: .edgeDocked
            )
        }

        let dockPosition = resolvedDockPosition(
            for: anchorFrame,
            visibleFrame: visibleFrame,
            panelSize: panelSize,
            placementPreference: placementPreference,
            preferredDockPosition: preferredDockPosition
        )
        let proposedOrigin = proposedOrigin(
            for: anchorFrame,
            panelSize: panelSize,
            dockPosition: dockPosition,
            horizontalOffset: horizontalOffset,
            verticalOffset: verticalOffset
        )
        let (origin, didClamp) = clampedOrigin(
            proposedOrigin: proposedOrigin,
            panelSize: panelSize,
            visibleFrame: visibleFrame,
            dockPosition: dockPosition
        )
        let horizontalSide: StackOverlayHorizontalSide = origin.x + panelSize.width / 2 < anchorFrame.midX ? .left : .right

        return StackOverlayResolvedAttachment(
            health: didClamp ? .clamped : .visible,
            anchorFrame: anchorFrame,
            visibleFrame: visibleFrame,
            origin: origin,
            dockPosition: dockPosition,
            horizontalSide: horizontalSide,
            placementMode: .edgeDocked
        )
    }

    private func effectiveFloatingHorizontalOffset(_ horizontalOffset: CGFloat) -> CGFloat {
        horizontalOffset <= Self.unsetHorizontalOffsetSentinel + 1 ? 0 : horizontalOffset
    }

    func clampedFloatingOrigin(
        for anchorFrame: CGRect,
        panelSize: CGSize,
        horizontalOffset: CGFloat,
        verticalOffset: CGFloat
    ) -> CGPoint {
        let inset = Self.floatingDefaultInset
        let extraX = effectiveFloatingHorizontalOffset(horizontalOffset)
        let proposed = CGPoint(
            x: anchorFrame.minX + inset + extraX,
            y: anchorFrame.minY + inset + verticalOffset
        )
        return CGPoint(
            x: min(max(proposed.x, anchorFrame.minX + inset), anchorFrame.maxX - panelSize.width - inset),
            y: min(max(proposed.y, anchorFrame.minY + inset), anchorFrame.maxY - panelSize.height - inset)
        )
    }

    func convertAXFrameToScreenCoordinates(_ frame: CGRect) -> CGRect {
        // macOS Accessibility/System Events coordinates use a top-left global origin
        // based on the primary display. AppKit screen coordinates use the same global
        // X axis but a bottom-left Y axis. Always start with the primary-display
        // transform; using the destination screen's maxY breaks side-by-side displays
        // with different heights, because the AX Y offset still includes the taller
        // primary display's coordinate space.
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return frame }

        let primaryMaxY = screens.first(where: { $0.frame.origin == .zero })?.frame.maxY
            ?? NSScreen.main?.frame.maxY
            ?? screens.map(\.frame.maxY).max()
            ?? 0

        let primaryConverted = CGRect(
            x: frame.origin.x,
            y: primaryMaxY - frame.origin.y - frame.size.height,
            width: frame.size.width,
            height: frame.size.height
        )

        if screens.contains(where: { $0.frame.intersects(primaryConverted) }) {
            return primaryConverted
        }

        // Last-ditch fallback for unusual coordinate reports: try each screen maxY and
        // pick the first candidate that lands on a real screen.
        for screen in screens {
            let candidate = CGRect(
                x: frame.origin.x,
                y: screen.frame.maxY - frame.origin.y - frame.size.height,
                width: frame.size.width,
                height: frame.size.height
            )
            if screens.contains(where: { $0.frame.intersects(candidate) }) {
                return candidate
            }
        }

        return frame
    }

    private func referenceVisibleFrame(for anchorFrame: CGRect, panelFrame: CGRect) -> CGRect? {
        if let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(anchorFrame) }) {
            return screen.visibleFrame
        }

        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchorFrame) }) {
            return screen.visibleFrame
        }

        if let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(panelFrame) }) {
            return screen.visibleFrame
        }

        return nil
    }

    /// Returns true if the left or right side rails have enough vertical travel
    /// to make a side-attached widget practically usable. For very tall (full-height)
    /// windows this returns false so we avoid placing the widget on left/right where
    /// it has almost no room to slide and perimeter dragging becomes jarring.
    private func isSideRailViable(for anchorFrame: CGRect, visibleFrame: CGRect, panelSize: CGSize) -> Bool {
        let minY = anchorFrame.minY + edgeInset
        let maxY = max(minY, anchorFrame.maxY - panelSize.height - edgeInset)
        let verticalTravel = max(0, maxY - minY)
        // Require roughly 1.7x the widget's own height of vertical travel.
        // This catches "full height or nearly full height" browser windows.
        return verticalTravel >= panelSize.height * 1.7
    }

    private func hasVisibleRoomForWidget(anchorFrame: CGRect, visibleFrame: CGRect, panelSize: CGSize) -> Bool {
        let availableTop = visibleFrame.maxY - anchorFrame.maxY
        let availableBottom = anchorFrame.minY - visibleFrame.minY
        let availableLeft = anchorFrame.minX - visibleFrame.minX
        let availableRight = visibleFrame.maxX - anchorFrame.maxX
        let sideRailViable = isSideRailViable(for: anchorFrame, visibleFrame: visibleFrame, panelSize: panelSize)

        if availableTop >= panelSize.height + topGap {
            return true
        }
        if availableBottom >= panelSize.height + bottomGap {
            return true
        }
        if sideRailViable,
           availableLeft >= panelSize.width + sideGap || availableRight >= panelSize.width + sideGap {
            return true
        }
        return false
    }

    private func resolvedDockPosition(
        for anchorFrame: CGRect,
        visibleFrame: CGRect,
        panelSize: CGSize,
        placementPreference: StackOverlayPlacementPreference,
        preferredDockPosition: StackOverlayDockPosition
    ) -> StackOverlayDockPosition {
        let availableTop = visibleFrame.maxY - anchorFrame.maxY
        let availableBottom = anchorFrame.minY - visibleFrame.minY
        let availableLeft = anchorFrame.minX - visibleFrame.minX
        let availableRight = visibleFrame.maxX - anchorFrame.maxX
        let topFits = availableTop >= panelSize.height + topGap
        let bottomFits = availableBottom >= panelSize.height + bottomGap
        let leftFits = availableLeft >= panelSize.width + sideGap
        let rightFits = availableRight >= panelSize.width + sideGap

        let sideRailViable = isSideRailViable(for: anchorFrame, visibleFrame: visibleFrame, panelSize: panelSize)

        if placementPreference == .automatic {
            // For automatic placement, strongly prefer top/bottom. Only consider left/right
            // when the window has enough vertical travel to make side rails actually usable.
            var candidates: [(StackOverlayDockPosition, CGFloat)] = [
                (.bottom, availableBottom),
                (.top, availableTop)
            ]
            if sideRailViable {
                candidates.append(contentsOf: [
                    (.right, availableRight),
                    (.left, availableLeft)
                ])
            }
            return candidates.max { lhs, rhs in lhs.1 < rhs.1 }?.0 ?? preferredDockPosition
        }

        let requestedPosition = placementPreference.dockPosition ?? preferredDockPosition
        let preferredFits: Bool = switch requestedPosition {
        case .top:
            topFits
        case .bottom:
            bottomFits
        case .left:
            leftFits
        case .right:
            rightFits
        }

        if preferredFits {
            return requestedPosition
        }

        for fallback in requestedPosition.fallbackOrder {
            switch fallback {
            case .top where topFits:
                return .top
            case .bottom where bottomFits:
                return .bottom
            case .left where leftFits:
                return .left
            case .right where rightFits:
                return .right
            default:
                continue
            }
        }

        // Final fallback: again prefer top/bottom for tall windows
        var fallbackCandidates: [(StackOverlayDockPosition, CGFloat)] = [
            (.top, availableTop),
            (.bottom, availableBottom)
        ]
        if sideRailViable {
            fallbackCandidates.append(contentsOf: [
                (.left, availableLeft),
                (.right, availableRight)
            ])
        }
        return fallbackCandidates.max { lhs, rhs in lhs.1 < rhs.1 }?.0 ?? requestedPosition
    }

    private func proposedOrigin(
        for anchorFrame: CGRect,
        panelSize: CGSize,
        dockPosition: StackOverlayDockPosition,
        horizontalOffset: CGFloat,
        verticalOffset: CGFloat
    ) -> CGPoint {
        switch dockPosition {
        case .top:
            return CGPoint(
                x: clampedAttachmentX(
                    proposedX: anchorFrame.midX - panelSize.width / 2 + horizontalOffset,
                    anchorFrame: anchorFrame,
                    panelSize: panelSize
                ),
                y: anchorFrame.maxY + topGap
            )
        case .bottom:
            return CGPoint(
                x: clampedAttachmentX(
                    proposedX: anchorFrame.midX - panelSize.width / 2 + horizontalOffset,
                    anchorFrame: anchorFrame,
                    panelSize: panelSize
                ),
                y: anchorFrame.minY - panelSize.height - bottomGap
            )
        case .left:
            return CGPoint(
                x: anchorFrame.minX - panelSize.width - sideGap,
                y: clampedAttachmentY(
                    proposedY: anchorFrame.maxY - panelSize.height - edgeInset + verticalOffset,
                    anchorFrame: anchorFrame,
                    panelSize: panelSize
                )
            )
        case .right:
            return CGPoint(
                x: anchorFrame.maxX + sideGap,
                y: clampedAttachmentY(
                    proposedY: anchorFrame.maxY - panelSize.height - edgeInset + verticalOffset,
                    anchorFrame: anchorFrame,
                    panelSize: panelSize
                )
            )
        }
    }

    private func clampedAttachmentX(proposedX: CGFloat, anchorFrame: CGRect, panelSize: CGSize) -> CGFloat {
        let minX = anchorFrame.minX + edgeInset
        let maxX = max(minX, anchorFrame.maxX - panelSize.width - edgeInset)
        return min(max(proposedX, minX), maxX)
    }

    private func clampedAttachmentY(proposedY: CGFloat, anchorFrame: CGRect, panelSize: CGSize) -> CGFloat {
        let minY = anchorFrame.minY + edgeInset
        let maxY = max(minY, anchorFrame.maxY - panelSize.height - edgeInset)
        return min(max(proposedY, minY), maxY)
    }

    private func clampedOrigin(
        proposedOrigin: CGPoint,
        panelSize: CGSize,
        visibleFrame: CGRect,
        dockPosition: StackOverlayDockPosition
    ) -> (CGPoint, Bool) {
        let minX = visibleFrame.minX + screenInset
        let maxX = max(minX, visibleFrame.maxX - panelSize.width - screenInset)
        let minY = visibleFrame.minY + screenInset
        let maxY = max(minY, visibleFrame.maxY - panelSize.height - screenInset)
        let dockMinY = visibleFrame.minY
        let dockMaxY = max(dockMinY, visibleFrame.maxY - panelSize.height)
        let proposedY = switch dockPosition {
        case .top, .bottom:
            min(max(proposedOrigin.y, dockMinY), dockMaxY)
        case .left, .right:
            min(max(proposedOrigin.y, minY), maxY)
        }

        let origin = CGPoint(
            x: min(max(proposedOrigin.x, minX), maxX),
            y: proposedY
        )
        return (origin, origin != proposedOrigin)
    }

    /// Preferred initial position for a brand new stack.
    /// Strongly prefers top-left, falling back to left-top for tall windows,
    /// before using general "most space" logic.
    static func preferredInitialDockPositionAndSide(for anchorFrame: CGRect)
        -> (dock: StackOverlayDockPosition, side: StackOverlayHorizontalSide)
    {
        guard let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(anchorFrame) })
            ?? NSScreen.screens.first(where: { $0.frame.intersects(anchorFrame) })
            ?? NSScreen.main else {
            return (.top, .left)
        }

        let visible = screen.visibleFrame
        let topAvailable = visible.maxY - anchorFrame.maxY
        let leftAvailable = anchorFrame.minX - visible.minX
        let isTallWindow = anchorFrame.height > visible.height * 0.82

        if topAvailable >= 36 {
            return (.top, .left)
        }
        if isTallWindow || leftAvailable >= 36 {
            return (.left, .left)
        }
        return (.top, .left)
    }
}
