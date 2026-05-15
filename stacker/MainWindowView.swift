import SwiftUI

struct MainWindowView: View {
    private struct EditorWindowSnapshot: Identifiable {
        let id: Int
        let title: String
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
                return "Chrome profile windows are ready to become a switcher."
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
    @State private var activeStacks: [(appName: String, bundleIdentifier: String?, pid: Int32, titles: [String], widgetHidden: Bool, overlayHealth: StackOverlayHealth)] = []
    @State private var selectedPID: Int32?
    @State private var expandedPID: Int32?
    @State private var selectedActiveWindows: [EditorWindowSnapshot] = []
    @State private var selectedInactiveWindows: [EditorWindowSnapshot] = []
    private let settingsSelectionID = Int32.min

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 240, ideal: 270, max: 320)
        } detail: {
            detailPane
        }
        .frame(minWidth: 900, minHeight: 620)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    MainWindowViewActions.refreshApplications()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Refresh open Chrome profile windows")
            }
        }
        .onChange(of: expandedPID) { _, newValue in
            guard newValue != settingsSelectionID else { return }
            guard let newValue, let app = apps.first(where: { $0.pid == newValue }) else { return }
            MainWindowViewActions.selectApplication(app.pid, focusStack: app.isActive)
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

            Section("Chrome") {
                if apps.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("No Profiles Ready", systemImage: "square.stack.3d.up.slash")
                        Text("Open at least two Chrome profile windows.")
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
        HStack(spacing: 10) {
            Image(systemName: app.isActive ? "circle.fill" : "circle")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(app.statusTint)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .lineLimit(1)

                Text(sidebarDetail(for: app))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if app.widgetHidden {
                Image(systemName: "eye.slash")
                    .foregroundStyle(.secondary)
                    .help("Widget hidden")
            }
        }
        .contextMenu {
            Button(app.isActive ? "Focus Switcher" : "Turn On Switcher") {
                if app.isActive {
                    MainWindowViewActions.focusApplicationStack(app.pid)
                } else {
                    MainWindowViewActions.autoStackApplication(app.pid)
                }
            }

            Button("Refresh Chrome") {
                MainWindowViewActions.refreshApplications()
            }
        }
    }

    private func sidebarDetail(for app: AppSnapshot) -> String {
        if app.isActive {
            return "\(app.groupedCount) linked, \(app.statusTitle.lowercased())"
        }
        return "\(app.windowCount) profile windows ready"
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
                    VStack(alignment: .leading, spacing: 14) {
                        detailHeader(for: selectedApp)

                        if selectedPID != selectedApp.pid {
                            loadingSection
                        } else {
                            statusSection(for: selectedApp)
                            if selectedApp.isActive {
                                linkedProfilesSection(for: selectedApp)
                            }
                            availableProfilesSection(for: selectedApp)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: 760, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                } else {
                    ContentUnavailableView(
                        "Open Chrome Profiles",
                        systemImage: "person.2.crop.square.stack",
                        description: Text("Open two or more Chrome profile windows, then refresh Stacker.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 420)
                }
            }
            .navigationTitle(selectedApp?.name ?? "Profile Switcher")
        }
    }

    private func detailHeader(for app: AppSnapshot) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: app.isActive ? "rectangle.3.group.bubble.left.fill" : "rectangle.3.group")
                .font(.system(size: 34, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(app.statusTint)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(app.name)
                        .font(.largeTitle.weight(.semibold))
                        .lineLimit(1)

                    statusPill(app.statusTitle, tint: app.statusTint)
                }

                Text(app.isActive ? app.statusMessage : "Turn on the switcher to link open Chrome profile windows and show the widget.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func statusSection(for app: AppSnapshot) -> some View {
        GroupBox {
            HStack(spacing: 12) {
                metric("Profiles", value: "\(app.windowCount)", systemImage: "person.crop.circle")
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
                Text("Reading open Chrome profile windows...")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Loading", systemImage: "hourglass")
        }
    }

    private func linkedProfilesSection(for app: AppSnapshot) -> some View {
        GroupBox {
            if selectedActiveWindows.isEmpty {
                emptySectionText("No linked profile windows are loaded right now.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(selectedActiveWindows.enumerated()), id: \.element.id) { index, window in
                        if index > 0 { Divider() }
                        linkedProfileRow(window, index: index, pid: app.pid)
                    }
                }
            }
        } label: {
            Label("Linked Profile Windows", systemImage: "rectangle.connected.to.line.below")
        }
    }

    private func availableProfilesSection(for app: AppSnapshot) -> some View {
        GroupBox {
            if selectedInactiveWindows.isEmpty {
                emptySectionText(availableProfilesEmptyText(for: app))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(selectedInactiveWindows.enumerated()), id: \.element.id) { index, window in
                        if index > 0 { Divider() }
                        availableProfileRow(window, app: app)
                    }
                }
            }
        } label: {
            Label(app.isActive ? "Available Profile Windows" : "Ready To Link", systemImage: "square.stack.3d.up")
        }
    }

    private func availableProfilesEmptyText(for app: AppSnapshot) -> String {
        if app.isActive {
            return "No additional profile windows are available right now."
        }

        if app.windowCount > 0 {
            return "\(app.windowCount) open Chrome profile windows will be included when the switcher turns on."
        }

        return "Open at least two Chrome profile windows, then refresh Stacker."
    }

    private func linkedProfileRow(_ window: EditorWindowSnapshot, index: Int, pid: Int32) -> some View {
        let isFront = index == 0

        return HStack(spacing: 12) {
            StackBadgeView(
                token: "\(index + 1)",
                tint: isFront ? .accentColor : .secondary,
                selected: isFront,
                diameter: 30
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(window.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)

                Text(isFront ? "Front profile window" : "Linked profile window")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            rowControls(window: window, index: index, pid: pid)
        }
        .padding(.vertical, 10)
    }

    private func rowControls(window: EditorWindowSnapshot, index: Int, pid: Int32) -> some View {
        HStack(spacing: 4) {
            Button {
                MainWindowViewActions.moveWindowInStack(pid: pid, windowID: window.id, direction: -1)
            } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(index == 0)
            .help("Move up")

            Button {
                MainWindowViewActions.moveWindowInStack(pid: pid, windowID: window.id, direction: 1)
            } label: {
                Image(systemName: "chevron.down")
            }
            .disabled(index >= selectedActiveWindows.count - 1)
            .help("Move down")

            Button(role: .destructive) {
                MainWindowViewActions.removeWindowFromStack(pid: pid, windowID: window.id)
            } label: {
                Image(systemName: "minus.circle")
            }
            .help("Remove from switcher")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .foregroundStyle(.secondary)
    }

    private func availableProfileRow(_ window: EditorWindowSnapshot, app: AppSnapshot) -> some View {
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
            (appName: stack.appName, bundleIdentifier: stack.bundleIdentifier, pid: stack.processIdentifier, titles: stack.titles, widgetHidden: stack.widgetHidden, overlayHealth: stack.overlayHealth)
        }

        selectedPID = snapshot.selectedPID

        selectedActiveWindows = snapshot.activeWindows.map { window in
            EditorWindowSnapshot(id: Int(window.id), title: window.title)
        }
        selectedInactiveWindows = snapshot.inactiveWindows.map { window in
            EditorWindowSnapshot(id: Int(window.id), title: window.title)
        }

        let knownPIDs = Set(snapshot.apps.map(\.processIdentifier) + snapshot.activeStacks.map(\.processIdentifier))
        if let expandedPID, expandedPID != settingsSelectionID, !knownPIDs.contains(expandedPID) {
            self.expandedPID = nil
        }
        if self.expandedPID == nil {
            self.expandedPID = snapshot.selectedPID ?? snapshot.activeStacks.first?.processIdentifier ?? snapshot.apps.first?.processIdentifier ?? settingsSelectionID
        }
    }

    func toggleWidgetVisibility(forBundleIdentifier bundleIdentifier: String?, appName: String, pid: Int32) {
        _ = OverlayAppVisibilityPreference.toggle(bundleIdentifier: bundleIdentifier, appName: appName)
        MainWindowViewActions.toggleApplicationOverlayVisibility(bundleIdentifier: bundleIdentifier, appName: appName, pid: pid)
    }
}
