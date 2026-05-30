import SwiftUI
import Observation
import AppKit
import ApplicationServices

extension Notification.Name {
    static let stackerActiveStackCountDidChange = Notification.Name("stackerActiveStackCountDidChange")
    static let stackerSidebarSnapshotDidChange = Notification.Name("stackerSidebarSnapshotDidChange")
    static let stackerFrontmostApplicationDidChange = Notification.Name("stackerFrontmostApplicationDidChange")
    static let stackerSelectTargetApplication = Notification.Name("stackerSelectTargetApplication")
    static let stackerAutoStackApplication = Notification.Name("stackerAutoStackApplication")
    static let stackerMoveWindowInStack = Notification.Name("stackerMoveWindowInStack")
    static let stackerReorderWindowsInStack = Notification.Name("stackerReorderWindowsInStack")
    static let stackerAddWindowToStack = Notification.Name("stackerAddWindowToStack")
    static let stackerRemoveWindowFromStack = Notification.Name("stackerRemoveWindowFromStack")
    static let stackerFocusApplicationStack = Notification.Name("stackerFocusApplicationStack")
    static let stackerFocusWindowInStack = Notification.Name("stackerFocusWindowInStack")
    static let stackerRefreshApplications = Notification.Name("stackerRefreshApplications")
    static let stackerReadSelectedWindows = Notification.Name("stackerReadSelectedWindows")
    static let stackerResetSelectedStack = Notification.Name("stackerResetSelectedStack")
    static let stackerResetApplicationStack = Notification.Name("stackerResetApplicationStack")
    static let stackerToggleApplicationOverlayVisibility = Notification.Name("stackerToggleApplicationOverlayVisibility")
    static let stackerOverlayVisibilityDidChange = Notification.Name("stackerOverlayVisibilityDidChange")
    static let stackerOverlayPaletteDidChange = Notification.Name("stackerOverlayPaletteDidChange")
    static let stackerOverlayAppearanceDidChange = Notification.Name("stackerOverlayAppearanceDidChange")
    static let stackerOverlayPlacementDidChange = Notification.Name("stackerOverlayPlacementDidChange")
    static let stackerResetApplicationOverlayPosition = Notification.Name("stackerResetApplicationOverlayPosition")
    static let stackerDegradedStackCountDidChange = Notification.Name("stackerDegradedStackCountDidChange")
    static let stackerRetryDegradedStacks = Notification.Name("stackerRetryDegradedStacks")
    static let stackerAppWillTerminate = Notification.Name("stackerAppWillTerminate")
    static let stackerAccessibilityTrustDidChange = Notification.Name("stackerAccessibilityTrustDidChange")
}

enum StackerPresentation {
    case window
    case popover
}

struct TargetApplication: Equatable {
    let name: String
    let bundleIdentifier: String?
    let processIdentifier: pid_t
    let windowCount: Int
}

struct WindowFetchResult {
    let windows: [AXUIElement]
    let error: AXError
}

struct WindowListResult {
    let windows: [AXUIElement]
    let error: AXError
}

struct FocusedApplicationProbe {
    let element: AXUIElement
    let processIdentifier: pid_t
}

struct WindowChoice: Identifiable {
    let id: UInt
    let title: String
    let window: AXUIElement?
    let scriptIndex: Int?
    var isSelected = false

    init(
        id: UInt,
        title: String,
        window: AXUIElement?,
        scriptIndex: Int?,
        isSelected: Bool = false
    ) {
        self.id = id
        self.title = title
        self.window = window
        self.scriptIndex = scriptIndex
        self.isSelected = isSelected
    }
}

enum WindowChoiceID {
    static func script(processIdentifier: pid_t, windowIndex: Int) -> UInt {
        (UInt(UInt32(bitPattern: processIdentifier)) << 32) | UInt(UInt32(windowIndex))
    }
}

struct ScriptWindowState {
    let index: Int
    let title: String
    let frame: CGRect
}

struct SidebarAppSnapshot {
    let name: String
    let bundleIdentifier: String?
    let processIdentifier: pid_t
    let windowCount: Int
    let widgetHidden: Bool
}

struct SidebarActiveStackSnapshot {
    let appName: String
    let bundleIdentifier: String?
    let processIdentifier: pid_t
    let titles: [String]
    let activeWindows: [SidebarWindowSnapshot]
    let inactiveWindows: [SidebarWindowSnapshot]
    let widgetHidden: Bool
    let overlayHealth: StackOverlayHealth
}

struct SidebarWindowSnapshot: Identifiable {
    let id: UInt
    let title: String
    let accent: StackPillAccent?
}

struct SidebarSnapshot {
    let apps: [SidebarAppSnapshot]
    let activeStacks: [SidebarActiveStackSnapshot]
    let activeTitles: [String]
    let activeWindows: [SidebarWindowSnapshot]
    let inactiveWindows: [SidebarWindowSnapshot]
    let availableWindowTitles: [String]
    let isSelectingWindows: Bool
    let selectedPID: pid_t?
    let selectedName: String
}

final class ActiveStackSession: Identifiable {
    let id = UUID()
    let app: TargetApplication
    let controller: WindowStackController
    let overlayController: StackOverlayPanelController
    var windowIDs: Set<UInt>
    var windowOrder: [UInt]
    var windowTitles: [String]
    var availableWindowChoices: [WindowChoice]
    var windowAccentStyles: [UInt: StackPillAccent]
    var overlayDisplayMode: StackOverlayDisplayMode
    var overlayLabelMode: StackOverlayLabelMode
    var overlayDensityMode: StackOverlayDensityMode
    var overlayPlacementPreference: StackOverlayPlacementPreference
    var overlayDockPosition: StackOverlayDockPosition
    var overlayHealth: StackOverlayHealth

    init(
        app: TargetApplication,
        controller: WindowStackController,
        overlayController: StackOverlayPanelController,
        windowIDs: Set<UInt>,
        windowOrder: [UInt],
        windowTitles: [String],
        availableWindowChoices: [WindowChoice],
        windowAccentStyles: [UInt: StackPillAccent],
        overlayDisplayMode: StackOverlayDisplayMode,
        overlayLabelMode: StackOverlayLabelMode,
        overlayDensityMode: StackOverlayDensityMode,
        overlayPlacementPreference: StackOverlayPlacementPreference = .automatic,
        overlayDockPosition: StackOverlayDockPosition,
        overlayHealth: StackOverlayHealth = .visible
    ) {
        self.app = app
        self.controller = controller
        self.overlayController = overlayController
        self.windowIDs = windowIDs
        self.windowOrder = windowOrder
        self.windowTitles = windowTitles
        self.availableWindowChoices = availableWindowChoices
        self.windowAccentStyles = windowAccentStyles
        self.overlayDisplayMode = overlayDisplayMode
        self.overlayLabelMode = overlayLabelMode
        self.overlayDensityMode = overlayDensityMode
        self.overlayPlacementPreference = overlayPlacementPreference
        self.overlayDockPosition = overlayDockPosition
        self.overlayHealth = overlayHealth
    }
}
