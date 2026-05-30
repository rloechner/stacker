import SwiftUI
import AppKit
import Combine

struct MenuApplicationSnapshot: Identifiable {
    let id: Int32
    let name: String
    let bundleIdentifier: String?
    let processIdentifier: Int32
    let windowCount: Int
    let isActive: Bool
    let isWidgetHidden: Bool
    let overlayHealth: StackOverlayHealth?

    var statusTitle: String {
        guard isActive else { return "Ready" }
        if isWidgetHidden { return StackOverlayHealth.hidden.surfaceTitle }
        return (overlayHealth ?? .visible).surfaceTitle
    }
}

final class MenuBarStateStore: ObservableObject {
    @Published var eligibleApps: [MenuApplicationSnapshot] = []
    @Published var activeStackCount = 0
    @Published var degradedStackCount = 0
    @Published var overlayHidden = UserDefaults.standard.bool(forKey: OverlayShortcutPreference.hiddenKey)
    @Published var overlayShortcutDescription = ""
    @Published var stackJumpShortcutDescription = ""

    private var latestSnapshot: SidebarSnapshot?
    private var stackCountObserver: NSObjectProtocol?
    private var snapshotObserver: NSObjectProtocol?
    private var defaultsObserver: NSObjectProtocol?

    init() {
        startObservers()
        updateShortcutDescription()
    }

    deinit {
        if let stackCountObserver {
            NotificationCenter.default.removeObserver(stackCountObserver)
        }

        if let snapshotObserver {
            NotificationCenter.default.removeObserver(snapshotObserver)
        }
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
    }

    func openMainWindow() {
        StackerAppWindowActions.openMainWindow()
    }

    func hideMainWindow() {
        StackerAppWindowActions.hideMainWindow()
    }

    func openSettings() {
        StackerAppWindowActions.openSettings()
    }

    func refreshApplications() {
        NotificationCenter.default.post(name: .stackerRefreshApplications, object: nil)
    }

    func toggleApplicationStack(_ app: MenuApplicationSnapshot) {
        let notificationName: Notification.Name = app.isActive
            ? .stackerResetApplicationStack
            : .stackerAutoStackApplication

        NotificationCenter.default.post(
            name: notificationName,
            object: nil,
            userInfo: ["pid": app.processIdentifier]
        )
    }

    func toggleApplicationWidget(_ app: MenuApplicationSnapshot) {
        _ = OverlayAppVisibilityPreference.toggle(bundleIdentifier: app.bundleIdentifier, appName: app.name)
        NotificationCenter.default.post(
            name: .stackerToggleApplicationOverlayVisibility,
            object: nil,
            userInfo: [
                "bundleIdentifier": app.bundleIdentifier ?? "",
                "appName": app.name
            ]
        )
        overlayHidden = UserDefaults.standard.bool(forKey: OverlayShortcutPreference.hiddenKey)
        if let latestSnapshot {
            let updatedSnapshot = SidebarSnapshot(
                apps: latestSnapshot.apps.map { snapshot in
                    guard snapshot.processIdentifier == app.processIdentifier else { return snapshot }
                    return SidebarAppSnapshot(
                        name: snapshot.name,
                        bundleIdentifier: snapshot.bundleIdentifier,
                        processIdentifier: snapshot.processIdentifier,
                        windowCount: snapshot.windowCount,
                        widgetHidden: OverlayAppVisibilityPreference.isHidden(bundleIdentifier: snapshot.bundleIdentifier, appName: snapshot.name)
                    )
                },
                activeStacks: latestSnapshot.activeStacks.map { snapshot in
                    guard snapshot.processIdentifier == app.processIdentifier else { return snapshot }
                    return SidebarActiveStackSnapshot(
                        appName: snapshot.appName,
                        bundleIdentifier: snapshot.bundleIdentifier,
                        processIdentifier: snapshot.processIdentifier,
                        titles: snapshot.titles,
                        activeWindows: snapshot.activeWindows,
                        inactiveWindows: snapshot.inactiveWindows,
                        widgetHidden: OverlayAppVisibilityPreference.isHidden(bundleIdentifier: snapshot.bundleIdentifier, appName: snapshot.appName),
                        overlayHealth: snapshot.overlayHealth
                    )
                },
                activeTitles: latestSnapshot.activeTitles,
                activeWindows: latestSnapshot.activeWindows,
                inactiveWindows: latestSnapshot.inactiveWindows,
                availableWindowTitles: latestSnapshot.availableWindowTitles,
                isSelectingWindows: latestSnapshot.isSelectingWindows,
                selectedPID: latestSnapshot.selectedPID,
                selectedName: latestSnapshot.selectedName
            )
            handleSnapshot(updatedSnapshot)
        }
    }

    func focusApplicationWorkspace(_ app: MenuApplicationSnapshot) {
        NotificationCenter.default.post(
            name: .stackerSelectTargetApplication,
            object: nil,
            userInfo: ["pid": app.processIdentifier]
        )
        openMainWindow()
    }

    func resetApplicationMarker(_ app: MenuApplicationSnapshot) {
        NotificationCenter.default.post(
            name: .stackerResetApplicationOverlayPosition,
            object: nil,
            userInfo: ["pid": app.processIdentifier]
        )
    }

    func toggleOverlayVisibility() {
        overlayHidden = OverlayShortcutState.toggleVisibility()
    }

    private func startObservers() {
        stackCountObserver = NotificationCenter.default.addObserver(
            forName: .stackerActiveStackCountDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            DispatchQueue.main.async {
                self?.activeStackCount = notification.userInfo?["count"] as? Int ?? 0
            }
        }

        snapshotObserver = NotificationCenter.default.addObserver(
            forName: .stackerSidebarSnapshotDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            DispatchQueue.main.async {
                guard let snapshot = notification.object as? SidebarSnapshot else { return }
                self?.handleSnapshot(snapshot)
            }
        }

        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.overlayHidden = UserDefaults.standard.bool(forKey: OverlayShortcutPreference.hiddenKey)
                self?.updateShortcutDescription()
            }
        }
    }

    private func handleSnapshot(_ snapshot: SidebarSnapshot) {
        latestSnapshot = snapshot
        let activePIDs = Set(snapshot.activeStacks.map(\.processIdentifier))
        let activeStackLookup = Dictionary(uniqueKeysWithValues: snapshot.activeStacks.map { ($0.processIdentifier, $0) })
        eligibleApps = snapshot.apps.map { snapshot in
            let activeStack = activeStackLookup[snapshot.processIdentifier]
            return MenuApplicationSnapshot(
                id: snapshot.processIdentifier,
                name: snapshot.name,
                bundleIdentifier: snapshot.bundleIdentifier,
                processIdentifier: snapshot.processIdentifier,
                windowCount: snapshot.windowCount,
                isActive: activePIDs.contains(snapshot.processIdentifier),
                isWidgetHidden: snapshot.widgetHidden,
                overlayHealth: activeStack?.overlayHealth
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        let newDegraded = eligibleApps.filter { $0.isActive && $0.overlayHealth == .degraded }.count
        if newDegraded != degradedStackCount {
            degradedStackCount = newDegraded
            NotificationCenter.default.post(
                name: .stackerDegradedStackCountDidChange,
                object: nil,
                userInfo: ["count": newDegraded]
            )
        }
    }

    private func updateShortcutDescription() {
        overlayShortcutDescription = OverlayShortcutState.shortcutDescription()
        stackJumpShortcutDescription = StackJumpShortcutState.shortcutDescription()
    }
}

struct StackerMenuBarContent: View {
    @ObservedObject var state: MenuBarStateStore

    var body: some View {
        Section {
            Button {
                state.openMainWindow()
            } label: {
                Label("Open Stacker", systemImage: "macwindow")
            }

            Button {
                state.hideMainWindow()
            } label: {
                Label("Hide Stacker", systemImage: "eye.slash")
            }

            Button {
                state.refreshApplications()
            } label: {
                Label("Hard Refresh Browsers", systemImage: "arrow.clockwise")
            }

            Button {
                state.toggleOverlayVisibility()
            } label: {
                Label(state.overlayHidden ? "Show Window Widgets" : "Hide Window Widgets", systemImage: state.overlayHidden ? "eye" : "eye.slash")
            }

            Button {
                state.openSettings()
            } label: {
                Label("Settings…", systemImage: "gearshape")
            }
        }

        Section("Browser Windows") {
            if state.eligibleApps.isEmpty {
                Text("No browser windows")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(state.eligibleApps) { app in
                    Menu {
                        Button {
                            state.toggleApplicationStack(app)
                        } label: {
                            Label(app.isActive ? "Turn Off Switcher" : "Turn On Switcher", systemImage: app.isActive ? "power" : "play.fill")
                        }

                        Button {
                            state.toggleApplicationWidget(app)
                        } label: {
                            Label(app.isWidgetHidden ? "Show Window Widget" : "Hide Window Widget", systemImage: app.isWidgetHidden ? "eye" : "eye.slash")
                        }

                        Button {
                            state.focusApplicationWorkspace(app)
                        } label: {
                            Label("Manage Windows", systemImage: "arrow.up.forward.app")
                        }

                        if app.overlayHealth == .clamped || app.overlayHealth == .missingAnchor {
                            Button {
                                state.resetApplicationMarker(app)
                            } label: {
                                Label("Reset Widget Position", systemImage: "arrow.uturn.backward")
                            }
                        }

                        if app.overlayHealth == .degraded {
                            Button {
                                NotificationCenter.default.post(
                                    name: .stackerRetryDegradedStacks,
                                    object: nil,
                                    userInfo: ["pid": app.processIdentifier]
                                )
                            } label: {
                                Label("Retry Stack", systemImage: "arrow.clockwise")
                            }
                        }

                        Divider()
                        Text("\(app.windowCount) windows")
                            .foregroundStyle(.secondary)
                        if app.isActive {
                            Text(app.statusTitle)
                                .foregroundStyle(.secondary)
                        }
                    } label: {
                        Label {
                            HStack {
                                Text(app.name)
                                Spacer()
                                if app.isActive {
                                    Image(systemName: app.statusTitle == "Live" ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                        .foregroundStyle(app.statusTitle == "Live" ? Color.accentColor : Color.orange)
                                }
                            }
                        } icon: {
                            Image(systemName: app.isActive ? "square.stack.3d.up.fill" : "square.stack.3d.up")
                        }
                    }
                }
            }
        }

        Section("Status") {
            Label(state.activeStackCount == 0 ? "Window Switcher Off" : "Window Switcher On", systemImage: "square.stack.3d.up")
            if state.degradedStackCount > 0 {
                Label("\(state.degradedStackCount) stack(s) need attention", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            if state.overlayHidden {
                Label("Window Widgets Hidden", systemImage: "eye.slash")
                    .foregroundStyle(.secondary)
            }
            Label(state.overlayShortcutDescription, systemImage: "keyboard")
                .foregroundStyle(.secondary)
            if StackJumpShortcutState.isEnabled() {
                Label("Stack jump: \(state.stackJumpShortcutDescription)", systemImage: "number")
                    .foregroundStyle(.secondary)
            }

            if state.degradedStackCount > 0 {
                Button("Retry Failed Stacks") {
                    NotificationCenter.default.post(name: .stackerRetryDegradedStacks, object: nil)
                }
            }
        }

        Section {
            Button("Quit Stacker", role: .destructive) {
                NSApp.terminate(nil)
            }
        }
    }
}

struct StackerMenuBarLabel: View {
    let count: Int
    let degradedCount: Int

    private var menuBarIcon: NSImage {
        // Standard and most reliable way for macOS menu bar apps:
        // Use a dedicated small image asset named "MenuBarIcon" (recommended 18pt or 22pt).
        // This works reliably in both Release and Xcode Debug builds.
        let baseIcon: NSImage

        if let menuIcon = NSImage(named: "MenuBarIcon") {
            baseIcon = menuIcon
        } else if let appIcon = NSImage(named: "AppIcon") {
            baseIcon = appIcon
        } else if let appImage = NSApp.applicationIconImage {
            baseIcon = appImage
        } else {
            baseIcon = NSImage(systemSymbolName: "square.stack.3d.up", accessibilityDescription: "Stacker")!
        }

        // We want the full color version of the icon (not a template/monochrome version)
        baseIcon.isTemplate = false

        // Resize cleanly to menu bar size (18pt is standard)
        let targetSize = NSSize(width: 18, height: 18)
        let resized = NSImage(size: targetSize)
        resized.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        baseIcon.draw(in: NSRect(origin: .zero, size: targetSize))
        resized.unlockFocus()

        return resized
    }

    var body: some View {
        Label {
            Text("\(count)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
        } icon: {
            Image(nsImage: menuBarIcon)
                // Full color app icon (no template) so the real Stacker icon appears in the menu bar
                // .renderingMode(.template) removed because it was making the icon invisible/monochrome in many cases
        }
        .labelStyle(.titleAndIcon)
    }
}
