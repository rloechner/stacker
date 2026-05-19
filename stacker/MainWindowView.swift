import SwiftUI
import UniformTypeIdentifiers

struct MainWindowView: View {
    fileprivate struct EditorWindowSnapshot: Identifiable {
        let id: Int
        let title: String
        let accent: StackPillAccent?
    }

    private struct ActiveStackViewSnapshot {
        let appName: String
        let bundleIdentifier: String?
        let pid: Int32
        let titles: [String]
        let activeWindows: [EditorWindowSnapshot]
        let inactiveWindows: [EditorWindowSnapshot]
        let widgetHidden: Bool
        let overlayHealth: StackOverlayHealth
    }

    private struct AppSnapshot: Identifiable {
        let name: String
        let bundleIdentifier: String?
        let pid: Int32
        let windowCount: Int
        let widgetHidden: Bool
        let groupedCount: Int
        let isActive: Bool
        let overlayHealth: StackOverlayHealth?

        var id: Int32 { pid }

        var statusTitle: String {
            guard isActive else { return "Ready" }
            if widgetHidden { return StackOverlayHealth.hidden.surfaceTitle }
            return (overlayHealth ?? .visible).surfaceTitle
        }

        var statusMessage: String {
            guard isActive else {
                return "Browser windows are ready to become a switcher."
            }
            if widgetHidden {
                return StackOverlayHealth.hidden.surfaceMessage
            }
            return (overlayHealth ?? .visible).surfaceMessage
        }

        var statusTint: Color {
            switch statusTitle {
            case "Live":
                return .green
            case "Hidden":
                return .secondary
            case "Ready":
                return .accentColor
            default:
                return .orange
            }
        }

        var canResetMarkerPosition: Bool {
            guard isActive else { return false }
            return overlayHealth == .clamped || overlayHealth == .missingAnchor
        }
    }

    @State private var appTiles: [(name: String, bundleIdentifier: String?, pid: Int32, windowCount: Int, widgetHidden: Bool)] = []
    @State private var activeStacks: [ActiveStackViewSnapshot] = []
    @State private var selectedPID: Int32?
    @State private var expandedPID: Int32?
    @State private var selectedActiveWindows: [EditorWindowSnapshot] = []
    @State private var selectedInactiveWindows: [EditorWindowSnapshot] = []
    @State private var draggingLinkedWindowID: Int?
    private let settingsSelectionID = Int32.min

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            detailPane
        }
        .frame(minWidth: 560, minHeight: 420)   // Tight utility size
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    MainWindowViewActions.refreshApplications()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Refresh open browser windows")
            }
        }
        .onAppear {
            MainWindowViewActions.refreshApplications()
            MainWindowViewActions.readSelectedWindows()
        }
        .onChange(of: expandedPID) { _, newValue in
            guard newValue != settingsSelectionID else { return }
            guard let newValue, let app = apps.first(where: { $0.pid == newValue }) else { return }
            MainWindowViewActions.selectApplication(app.pid, focusStack: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: .stackerSidebarSnapshotDidChange)) { notification in
            guard let snapshot = notification.object as? SidebarSnapshot else { return }
            apply(snapshot: snapshot)
        }
    }
}

private extension MainWindowView {
    private var apps: [AppSnapshot] {
        let stackLookup = Dictionary(uniqueKeysWithValues: activeStacks.map { ($0.pid, $0) })

        var merged = appTiles.map { app in
            let stack = stackLookup[app.pid]
            return AppSnapshot(
                name: app.name,
                bundleIdentifier: app.bundleIdentifier,
                pid: app.pid,
                windowCount: app.windowCount,
                widgetHidden: app.widgetHidden,
                groupedCount: stack?.titles.count ?? 0,
                isActive: stack != nil,
                overlayHealth: stack?.overlayHealth
            )
        }

        for stack in activeStacks where !merged.contains(where: { $0.pid == stack.pid }) {
            merged.append(
                AppSnapshot(
                    name: stack.appName,
                    bundleIdentifier: stack.bundleIdentifier,
                    pid: stack.pid,
                    windowCount: stack.titles.count,
                    widgetHidden: stack.widgetHidden,
                    groupedCount: stack.titles.count,
                    isActive: true,
                    overlayHealth: stack.overlayHealth
                )
            )
        }

        return merged.sorted { lhs, rhs in
            if lhs.isActive != rhs.isActive {
                return lhs.isActive && !rhs.isActive
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private var selectedApp: AppSnapshot? {
        guard let expandedPID, expandedPID != settingsSelectionID else { return nil }
        return apps.first(where: { $0.pid == expandedPID })
    }

    var sidebar: some View {
        List(selection: $expandedPID) {
            Section("Stacker") {
                HStack(spacing: 10) {
                    Image(systemName: "gearshape")
                        .foregroundStyle(.secondary)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Settings")
                            .lineLimit(1)
                        Text("Appearance, widget, shortcut")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .tag(settingsSelectionID)
            }

            Section("Browsers") {
                if apps.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("No Browser Windows Ready", systemImage: "square.stack.3d.up.slash")
                        Text("Open at least two windows in a supported browser.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                } else {
                    ForEach(apps) { app in
                        sidebarRow(for: app)
                            .tag(app.pid)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Stacker")
    }

    private func sidebarRow(for app: AppSnapshot) -> some View {
        HStack(spacing: 6) {
            Image(systemName: app.isActive ? "circle.fill" : "circle")
                .font(.system(size: 7, weight: .semibold))
                .foregroundStyle(app.statusTint)
                .frame(width: 12)

            Text(app.name)
                .font(.callout)
                .lineLimit(1)

            Spacer(minLength: 2)

            if app.widgetHidden {
                Image(systemName: "eye.slash")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .help("Widget hidden")
            }

            // Only the arrow brings the real browser app to the front.
            // Clicking the row itself only opens it inside the Stacker admin.
            if app.isActive {
                Button {
                    if let runningApp = NSRunningApplication(processIdentifier: app.pid) {
                        runningApp.activate(options: [])
                    }
                } label: {
                    Image(systemName: "arrow.up.forward")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Bring this browser to the front")
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .contextMenu {
            Button(app.isActive ? "Focus Switcher" : "Turn On Switcher") {
                if app.isActive {
                    MainWindowViewActions.focusApplicationStack(app.pid)
                } else {
                    MainWindowViewActions.autoStackApplication(app.pid)
                }
            }

            Button("Refresh Browsers") {
                MainWindowViewActions.refreshApplications()
            }
        }
    }

    private func sidebarDetail(for app: AppSnapshot) -> String {
        if app.isActive {
            return "\(app.groupedCount) linked, \(app.statusTitle.lowercased())"
        }
        return "\(app.windowCount) browser windows ready"
    }

    @ViewBuilder
    var detailPane: some View {
        if expandedPID == settingsSelectionID {
            ScrollView {
                OverlayShortcutSettingsView()
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .navigationTitle("Settings")
        } else {
            ScrollView {
                if let selectedApp {
                    VStack(alignment: .leading, spacing: 10) {
                        detailHeader(for: selectedApp)

                        if selectedPID != selectedApp.pid {
                            loadingSection
                        } else {
                            statusSection(for: selectedApp)
                            if selectedApp.isActive {
                                linkedWindowsSection(for: selectedApp)
                            }
                            availableWindowsSection(for: selectedApp)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: 720, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                } else {
                    ContentUnavailableView(
                        "Open Browser Windows",
                        systemImage: "person.2.crop.square.stack",
                        description: Text("Open two or more windows in Chrome, Brave, Safari, Edge, or Firefox, then refresh Stacker.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 320)
                }
            }
            .navigationTitle(selectedApp?.name ?? "Window Switcher")
        }
    }

    private func detailHeader(for app: AppSnapshot) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: app.isActive ? "rectangle.3.group.bubble.left.fill" : "rectangle.3.group")
                .font(.system(size: 20, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(app.statusTint)
                .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(app.name)
                        .font(.largeTitle.weight(.semibold))
                        .lineLimit(1)

                    statusPill(app.statusTitle, tint: app.statusTint)
                }

                Text(app.isActive ? app.statusMessage : "Turn on the switcher to link open browser windows and show the widget.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func statusSection(for app: AppSnapshot) -> some View {
        GroupBox {
            HStack(spacing: 12) {
                metric("Windows", value: "\(app.windowCount)", systemImage: "macwindow")
                metric("Linked", value: "\(selectedActiveWindows.count)", systemImage: "link")
                metric("Available", value: "\(selectedInactiveWindows.count)", systemImage: "plus.rectangle.on.rectangle")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()
                .padding(.vertical, 4)

            HStack(spacing: 10) {
                Button {
                    toggleWidgetVisibility(forBundleIdentifier: app.bundleIdentifier, appName: app.name, pid: app.pid)
                } label: {
                    Label(app.widgetHidden ? "Show Widget" : "Hide Widget", systemImage: app.widgetHidden ? "eye" : "eye.slash")
                }

                if app.canResetMarkerPosition {
                    Button {
                        MainWindowViewActions.resetOverlayPosition(app.pid)
                    } label: {
                        Label("Reset Widget", systemImage: "arrow.uturn.backward")
                    }
                }

                Spacer()

                if app.isActive {
                    Button(role: .destructive) {
                        MainWindowViewActions.resetApplicationStack(app.pid)
                    } label: {
                        Label("Turn Off", systemImage: "power")
                    }
                } else {
                    Button {
                        MainWindowViewActions.autoStackApplication(app.pid)
                    } label: {
                        Label("Turn On", systemImage: "bolt.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        } label: {
            Label("Switcher", systemImage: app.isActive ? "switch.2" : "power")
        }
    }

    private var loadingSection: some View {
        GroupBox {
            HStack(spacing: 12) {
                ProgressView()
                    .controlSize(.small)
                Text("Reading open browser windows...")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Loading", systemImage: "hourglass")
        }
    }

    private func linkedWindowsSection(for app: AppSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("IN STACK")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .padding(.top, 4)

            if selectedActiveWindows.isEmpty {
                emptySectionText("No windows in this stack.")
            } else {
                ForEach(Array(selectedActiveWindows.enumerated()), id: \.element.id) { index, window in
                    linkedWindowRow(window, index: index, pid: app.pid)
                }
            }
        }
    }

    private func availableWindowsSection(for app: AppSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("OTHER OPEN WINDOWS")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .padding(.top, 6)

            if selectedInactiveWindows.isEmpty {
                emptySectionText(availableWindowsEmptyText(for: app))
            } else {
                ForEach(Array(selectedInactiveWindows.enumerated()), id: \.element.id) { index, window in
                    if index > 0 { Divider() }
                    availableWindowRow(window, app: app)
                }
            }
        }
    }

    private func availableWindowsEmptyText(for app: AppSnapshot) -> String {
        if app.isActive {
            return "No additional browser windows are available right now."
        }

        if app.windowCount > 0 {
            return "\(app.windowCount) open browser windows will be included when the switcher turns on."
        }

        return "Open at least two browser windows, then refresh Stacker."
    }

    private func linkedWindowRow(_ window: EditorWindowSnapshot, index: Int, pid: Int32) -> some View {
        let isFront = index == 0
        let accentTint = window.accent?.tint ?? (isFront ? Color.accentColor : Color.secondary)

        return HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .frame(width: 14)

            StackBadgeView(
                token: "\(index + 1)",
                tint: accentTint,
                selected: isFront,
                diameter: 30
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(window.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)

                Text(isFront ? "Front browser window" : "Linked browser window")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button(role: .destructive) {
                MainWindowViewActions.removeWindowFromStack(pid: pid, windowID: window.id)
            } label: {
                Label("Remove", systemImage: "minus.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Remove this window from the stack")
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onDrag {
            draggingLinkedWindowID = window.id
            return NSItemProvider(object: "\(window.id)" as NSString)
        }
        .onDrop(
            of: [.text],
            delegate: LinkedWindowDropDelegate(
                targetWindow: window,
                windows: $selectedActiveWindows,
                draggingWindowID: $draggingLinkedWindowID,
                pid: pid
            )
        )
    }

    private func availableWindowRow(_ window: EditorWindowSnapshot, app: AppSnapshot) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "macwindow")
                .foregroundStyle(.secondary)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(window.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(app.isActive ? "Available to add" : "Will be included when the switcher turns on")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if app.isActive {
                Button {
                    MainWindowViewActions.addWindowToStack(pid: app.pid, windowID: window.id)
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 10)
    }

    private func metric(_ title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.headline.weight(.semibold))
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 110, alignment: .leading)
    }

    private func statusPill(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary, in: Capsule(style: .continuous))
    }

    private func emptySectionText(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }

    func apply(snapshot: SidebarSnapshot) {
        appTiles = snapshot.apps.map { app in
            (name: app.name, bundleIdentifier: app.bundleIdentifier, pid: app.processIdentifier, windowCount: app.windowCount, widgetHidden: app.widgetHidden)
        }

        activeStacks = snapshot.activeStacks.map { stack in
            ActiveStackViewSnapshot(
                appName: stack.appName,
                bundleIdentifier: stack.bundleIdentifier,
                pid: stack.processIdentifier,
                titles: stack.titles,
                activeWindows: stack.activeWindows.map { window in
                    EditorWindowSnapshot(id: Int(window.id), title: window.title, accent: window.accent)
                },
                inactiveWindows: stack.inactiveWindows.map { window in
                    EditorWindowSnapshot(id: Int(window.id), title: window.title, accent: window.accent)
                },
                widgetHidden: stack.widgetHidden,
                overlayHealth: stack.overlayHealth
            )
        }

        selectedPID = snapshot.selectedPID
        applySelectedWindows(from: snapshot)

        let knownPIDs = Set(snapshot.apps.map(\.processIdentifier) + snapshot.activeStacks.map(\.processIdentifier))
        if let expandedPID, expandedPID != settingsSelectionID, !knownPIDs.contains(expandedPID) {
            self.expandedPID = nil
        }
        if self.expandedPID == nil {
            self.expandedPID = snapshot.selectedPID ?? snapshot.activeStacks.first?.processIdentifier ?? snapshot.apps.first?.processIdentifier ?? settingsSelectionID
        }
    }

    private func applySelectedWindows(from snapshot: SidebarSnapshot) {
        let preferredPID = expandedPID == settingsSelectionID ? snapshot.selectedPID : expandedPID ?? snapshot.selectedPID
        if let preferredPID,
           let activeStack = activeStacks.first(where: { $0.pid == preferredPID }) {
            selectedActiveWindows = activeStack.activeWindows
            selectedInactiveWindows = activeStack.inactiveWindows
            return
        }

        guard snapshot.selectedPID == preferredPID else {
            selectedActiveWindows = []
            selectedInactiveWindows = []
            return
        }

        selectedActiveWindows = snapshot.activeWindows.map { window in
            EditorWindowSnapshot(id: Int(window.id), title: window.title, accent: window.accent)
        }
        selectedInactiveWindows = snapshot.inactiveWindows.map { window in
            EditorWindowSnapshot(id: Int(window.id), title: window.title, accent: window.accent)
        }
    }

    func toggleWidgetVisibility(forBundleIdentifier bundleIdentifier: String?, appName: String, pid: Int32) {
        _ = OverlayAppVisibilityPreference.toggle(bundleIdentifier: bundleIdentifier, appName: appName)
        MainWindowViewActions.toggleApplicationOverlayVisibility(bundleIdentifier: bundleIdentifier, appName: appName, pid: pid)
    }
}

private struct LinkedWindowDropDelegate: DropDelegate {
    let targetWindow: MainWindowView.EditorWindowSnapshot
    @Binding var windows: [MainWindowView.EditorWindowSnapshot]
    @Binding var draggingWindowID: Int?
    let pid: Int32

    func dropEntered(info: DropInfo) {
        guard let draggingWindowID,
              draggingWindowID != targetWindow.id,
              let sourceIndex = windows.firstIndex(where: { $0.id == draggingWindowID }),
              let targetIndex = windows.firstIndex(where: { $0.id == targetWindow.id }) else {
            return
        }

        withAnimation(.default) {
            let movedWindow = windows.remove(at: sourceIndex)
            windows.insert(movedWindow, at: targetIndex)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        MainWindowViewActions.reorderWindowsInStack(
            pid: pid,
            windowIDs: windows.map(\.id)
        )
        draggingWindowID = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}
