import AppKit
import CoreGraphics

enum StackOverlayHealth: String {
    case visible
    case hidden
    case clamped
    case missingAnchor
    case minimizedOrFullscreen
    case permissionBlocked
    case unsupportedState

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
        case .permissionBlocked:
            return "Needs Attention"
        case .unsupportedState:
            return "Unsupported State"
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
        case .permissionBlocked:
            return "Accessibility permission is required to keep this stack attached."
        case .unsupportedState:
            return "This window state is outside v1 support."
        }
    }

    var isAttentionState: Bool {
        switch self {
        case .clamped, .missingAnchor, .permissionBlocked:
            return true
        case .visible, .hidden, .minimizedOrFullscreen, .unsupportedState:
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
}

struct WindowAttachmentEngine {
    var edgeInset: CGFloat = 18
    var screenInset: CGFloat = 12
    var sideGap: CGFloat = 0
    var topGap: CGFloat = 0
    var bottomGap: CGFloat = 0

    func resolve(
        state: StackOverlayAttachmentState,
        panelSize: CGSize,
        panelFrame: CGRect,
        placementPreference: StackOverlayPlacementPreference,
        preferredDockPosition: StackOverlayDockPosition,
        horizontalOffset: CGFloat,
        verticalOffset: CGFloat
    ) -> StackOverlayResolvedAttachment {
        let fallbackDockPosition = placementPreference.dockPosition ?? preferredDockPosition
        guard state.health == .visible || state.health == .clamped else {
            return StackOverlayResolvedAttachment(
                health: state.health,
                anchorFrame: state.anchorFrame.map(convertAXFrameToScreenCoordinates),
                visibleFrame: nil,
                origin: nil,
                dockPosition: fallbackDockPosition,
                horizontalSide: .left
            )
        }

        guard let rawAnchorFrame = state.anchorFrame else {
            return StackOverlayResolvedAttachment(
                health: .missingAnchor,
                anchorFrame: nil,
                visibleFrame: nil,
                origin: nil,
                dockPosition: fallbackDockPosition,
                horizontalSide: .left
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
                horizontalSide: .left
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
            horizontalSide: horizontalSide
        )
    }

    func convertAXFrameToScreenCoordinates(_ frame: CGRect) -> CGRect {
        let primaryMaxY = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.maxY
            ?? NSScreen.main?.frame.maxY

        if let primaryMaxY {
            let converted = CGRect(
                x: frame.origin.x,
                y: primaryMaxY - frame.origin.y - frame.size.height,
                width: frame.size.width,
                height: frame.size.height
            )
            if NSScreen.screens.contains(where: { $0.frame.intersects(converted) }) {
                return converted
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

        if placementPreference == .automatic {
            let rankedPositions: [(StackOverlayDockPosition, CGFloat)] = [
                (.right, availableRight),
                (.left, availableLeft),
                (.bottom, availableBottom),
                (.top, availableTop)
            ]
            return rankedPositions.max { lhs, rhs in lhs.1 < rhs.1 }?.0 ?? preferredDockPosition
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

        let rankedPositions: [(StackOverlayDockPosition, CGFloat)] = [
            (.top, availableTop),
            (.bottom, availableBottom),
            (.left, availableLeft),
            (.right, availableRight)
        ]
        return rankedPositions.max { lhs, rhs in lhs.1 < rhs.1 }?.0 ?? requestedPosition
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
}
