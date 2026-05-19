import SwiftUI
import Observation
import AppKit
import ApplicationServices

struct ContentView: View {
    let presentation: StackerPresentation

    @State private var workspaceController = StackerWorkspaceController()
    @State private var sessionStore = StackerSessionStore()
    @State private var sessionCoordinator = StackerSessionCoordinator()
    @State private var runtimeCoordinator = StackRuntimeCoordinator()
    @State private var frontmostCoordinator = StackerFrontmostCoordinator()
    @State private var workflowCoordinator = StackerWorkflowCoordinator()
    private let sidebarSnapshotBuilder = SidebarSnapshotBuilder()
    @State private var eventCoordinator = StackerEventCoordinator()
    @State private var combineOverlayController = CombineOverlayPanelController()

    init(presentation: StackerPresentation = .window) {
        self.presentation = presentation
    }

    private var eligibleApplications: [TargetApplication] {
        get { workspaceController.eligibleApplications }
        nonmutating set { workspaceController.eligibleApplications = newValue }
    }

    private var selectedTargetPID: pid_t? {
        get { workspaceController.selectedTargetPID }
        nonmutating set { workspaceController.selectedTargetPID = newValue }
    }

    private var targetApplication: TargetApplication? {
        get { workspaceController.targetApplication }
        nonmutating set { workspaceController.targetApplication = newValue }
    }

    private var appName: String? {
        get { workspaceController.appName }
        nonmutating set { workspaceController.appName = newValue }
    }

    private var targetPID: pid_t? {
        get { workspaceController.targetPID }
        nonmutating set { workspaceController.targetPID = newValue }
    }

    private var availableWindows: [WindowChoice] {
        get { workspaceController.availableWindows }
        nonmutating set { workspaceController.availableWindows = newValue }
    }

    private var isSelectingWindows: Bool {
        get { workspaceController.isSelectingWindows }
        nonmutating set { workspaceController.isSelectingWindows = newValue }
    }

    private var isLoadingWindows: Bool {
        get { workspaceController.isLoadingWindows }
        nonmutating set { workspaceController.isLoadingWindows = newValue }
    }

    private var showAccessibilityAlert: Bool {
        get { workspaceController.showAccessibilityAlert }
        nonmutating set { workspaceController.showAccessibilityAlert = newValue }
    }

    private var errorMessage: String? {
        get { workspaceController.errorMessage }
        nonmutating set { workspaceController.errorMessage = newValue }
    }

    private var debugMessages: [String] {
        get { workspaceController.debugMessages }
        nonmutating set { workspaceController.debugMessages = newValue }
    }

    private var hasRequestedAccessibilityPrompt: Bool {
        get { workspaceController.hasRequestedAccessibilityPrompt }
        nonmutating set { workspaceController.hasRequestedAccessibilityPrompt = newValue }
    }

    private var accessibilityTrusted: Bool {
        get { workspaceController.accessibilityTrusted }
        nonmutating set { workspaceController.accessibilityTrusted = newValue }
    }

    private var pendingAutoStackPID: pid_t? {
        get { workspaceController.pendingAutoStackPID }
        nonmutating set { workspaceController.pendingAutoStackPID = newValue }
    }

    private var frontmostEligiblePID: pid_t? {
        get { workspaceController.frontmostEligiblePID }
        nonmutating set { workspaceController.frontmostEligiblePID = newValue }
    }

    private var groupedTitles: [String] {
        get { sessionStore.groupedTitles }
        nonmutating set { sessionStore.groupedTitles = newValue }
    }

    private var activeWindowIDs: Set<UInt> {
        get { sessionStore.activeWindowIDs }
        nonmutating set { sessionStore.activeWindowIDs = newValue }
    }

    private var activeWindowOrder: [UInt] {
        get { sessionStore.activeWindowOrder }
        nonmutating set { sessionStore.activeWindowOrder = newValue }
    }

    private var activeStackSessions: [ActiveStackSession] {
        get { sessionStore.activeStackSessions }
        nonmutating set { sessionStore.activeStackSessions = newValue }
    }

    private var availableWindowsBinding: Binding<[WindowChoice]> {
        Binding(
            get: { availableWindows },
            set: { availableWindows = $0 }
        )
    }

    var body: some View {
        contentBody
            .padding()
            .frame(minWidth: presentation == .popover ? 320 : 420, maxWidth: .infinity, alignment: .leading)
            .onAppear(perform: handleAppear)
            .onChange(of: selectedTargetPID) { _, newValue in
                guard let newValue else { return }
                prepareForTargetSwitch(to: newValue)
                workflowCoordinator.handleSelectedTargetChange(
                    newValue: newValue,
                    eligibleApplications: eligibleApplications,
                    pendingAutoStackPID: pendingAutoStackPID,
                    setTargetApplication: { targetApplication = $0 },
                    setAppName: { appName = $0 },
                    setTargetPID: { targetPID = $0 },
                    syncCurrentStackState: syncCurrentStackState,
                    loadFrontmostAppWindows: loadFrontmostAppWindows,
                    clearPendingAutoStackPID: { pendingAutoStackPID = nil },
                    autoStackLoadedWindows: autoStackLoadedWindows
                )
            }
            .onChange(of: groupedTitles) { _, newValue in
                postSidebarSnapshot()
            }
            .onChange(of: activeStackSessions.count) { _, _ in
                postActiveStackCount()
                postSidebarSnapshot()
                syncCombineOverlay()
            }
            .onChange(of: eligibleApplications) { _, _ in
                postSidebarSnapshot()
                syncCombineOverlay()
            }
            .onChange(of: targetPID) { _, _ in
                postSidebarSnapshot()
            }
            .onReceive(NotificationCenter.default.publisher(for: .stackerOverlayPaletteDidChange)) { _ in
                applyCurrentWidgetPalette()
            }
            .onReceive(NotificationCenter.default.publisher(for: .stackerOverlayAppearanceDidChange)) { _ in
                applyCurrentWidgetAppearance()
            }
            .onReceive(NotificationCenter.default.publisher(for: .stackerOverlayPlacementDidChange)) { _ in
                applyCurrentWidgetPlacement()
            }
            .onDisappear(perform: handleDisappear)
            .alert(isPresented: Binding(
                get: { showAccessibilityAlert },
                set: { showAccessibilityAlert = $0 }
            )) {
                Alert(
                    title: Text("Accessibility Permission Required"),
                    message: Text("Stacker needs Accessibility permission to inspect browser windows and keep them synchronized."),
                    primaryButton: .default(Text("Open System Settings"), action: openAccessibilitySettings),
                    secondaryButton: .cancel()
                )
            }
            .alert(isPresented: errorAlertBinding) {
                Alert(
                    title: Text("Stacker Error"),
                    message: Text(errorMessage ?? ""),
                    dismissButton: .cancel()
                )
            }
            .task {
                await handleInitialLoad()
            }
    }

    private var contentBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !accessibilityTrusted {
                permissionBanner
            }
            centerHeader
            if presentation == .popover {
                appPickerSection
                statusSection
            } else {
                workspaceHeaderSection
            }

            if isSelectingWindows {
                windowSelectionSection
            } else if !groupedTitles.isEmpty {
                activeStackSection
            } else {
                emptyStateSection
            }

            centerActions
        }
    }

    private var centerHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(presentation == .popover ? "Stacker" : "Window Stacks")
                .font(presentation == .popover ? .headline : .title2.weight(.semibold))

            Text(presentation == .popover
                 ? "Switch between open browser windows from one widget."
                 : "Turn browser window switching on, tune the widget, and jump between open windows.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var permissionBanner: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "hand.raised.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(Color.orange)

            VStack(alignment: .leading, spacing: 6) {
                Text("Accessibility access is still needed")
                    .font(.subheadline.weight(.semibold))
                Text("Approve Stacker in System Settings so the switcher can inspect browser windows and keep them aligned.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                Button("Open Settings") {
                    openAccessibilitySettings()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("Check Again") {
                    accessibilityTrusted = workspaceController.isAccessibilityTrusted()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(14)
        .background(cardBackground)
    }

    @ViewBuilder
    private var workspaceHeaderSection: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(appName ?? "Open Browser Windows")
                    .font(.title3.weight(.semibold))
                Text(targetApplication == nil
                     ? "Open at least two windows in a supported browser, then refresh."
                     : "Stacker uses the browser windows that are already open. Pick the windows you want in the switcher.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                if let targetApplication {
                    Label("\(targetApplication.windowCount) windows", systemImage: "square.on.square")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.accentColor.opacity(0.12))
                        )
                }

                if !groupedTitles.isEmpty || isSelectingWindows {
                    Button("Clear") {
                        clearCurrentWorkspace(resetWindowOrder: false)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    @ViewBuilder
    private var appPickerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Browsers")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(appName ?? "Open a supported browser with at least two windows.")
                        .font(.subheadline.weight(.medium))
                }

                Spacer()

                Button("Refresh") {
                    Task { @MainActor in
                        await loadEligibleApplications()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if eligibleApplications.isEmpty {
                Text("No supported browser windows available.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(eligibleApplications, id: \.processIdentifier) { app in
                            let isSelected = app.processIdentifier == selectedTargetPID
                            let secondaryColor = isSelected ? Color.primary.opacity(0.8) : Color.secondary
                            let fillColor = isSelected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.04)
                            let strokeColor = isSelected ? Color.accentColor.opacity(0.55) : Color.primary.opacity(0.08)

                            Button {
                                selectedTargetPID = app.processIdentifier
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(app.name)
                                        .font(.subheadline.weight(.semibold))
                                    Text("\(app.windowCount) windows")
                                        .font(.caption)
                                        .foregroundStyle(secondaryColor)
                                }
                                .frame(width: 150, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(fillColor)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(strokeColor, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(cardBackground)
    }

    @ViewBuilder
    private var statusSection: some View {
        HStack(spacing: 12) {
            miniStatusCard(
                title: "Selected",
                value: appName ?? "None"
            )
            miniStatusCard(
                title: "Windows",
                value: "\(availableWindows.count)"
            )
            miniStatusCard(
                title: "Linked",
                value: "\(activeWindowIDs.count)"
            )
        }
    }

    private var windowSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Choose Browser Windows")
                        .font(.headline)
                    Text("Pick the open browser windows that should share one desktop slot.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(availableWindows.filter(\.isSelected).count) selected")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.accentColor.opacity(0.12))
                    )
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(availableWindowsBinding) { $window in
                        Toggle(isOn: $window.isSelected) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(window.title)
                                    .font(.subheadline.weight(.medium))
                                Text("Include this browser window in the switcher")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.checkbox)
                        .padding(12)
                        .background(cardBackground)
                    }
                }
            }
            .frame(maxHeight: 260)

            Button("Create Window Switcher") {
                let selectedWindows = availableWindows.filter(\.isSelected)
                startStack(with: selectedWindows)
            }
            .buttonStyle(.borderedProminent)
            .disabled(availableWindows.filter(\.isSelected).count < 2)
        }
    }

    private var emptyStateSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No Active Window Switcher")
                .font(.headline)
            Text(targetApplication == nil
                 ? (presentation == .popover ? "Open at least two browser windows, then refresh." : "Open a supported browser with two or more windows to start.")
                 : "Stacker will load open browser windows automatically. Once they appear, pick the ones you want linked together.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var centerActions: some View {
        HStack {
            if isLoadingWindows {
                ProgressView("Reading browser windows...")
                    .controlSize(.small)
            }

            Spacer()

            if presentation == .popover, !groupedTitles.isEmpty || isSelectingWindows {
                Button("Clear") {
                    clearCurrentWorkspace()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func miniStatusCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.weight(.semibold))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(cardBackground)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.84),
                        Color(red: 0.94, green: 0.97, blue: 1.0).opacity(0.72)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.22), Color.clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .padding(1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
    }

    private var activeWindows: [WindowChoice] {
        sessionStore.activeWindows(from: availableWindows)
    }

    private var inactiveWindows: [WindowChoice] {
        sessionStore.inactiveWindows(from: availableWindows)
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func handleAppear() {
        startTrackingActiveApplications()
        startTrackingSystemWake()
        startSidebarObservers()
        startCombineOverlay()
        refreshAccessibilityState()
        showAccessibilityAlert = false
    }

    private func handleDisappear() {
        combineOverlayController.close()
        stopTrackingActiveApplications()
        stopTrackingSystemWake()
        stopSidebarObservers()
    }

    @MainActor
    private func handleInitialLoad() async {
        await loadEligibleApplications()
        refreshAccessibilityState()
        postSidebarSnapshot()
    }

    private func refreshAccessibilityState() {
        accessibilityTrusted = workspaceController.isAccessibilityTrusted()
    }

    private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    private var currentStackSession: ActiveStackSession? {
        sessionStore.currentStackSession(for: targetPID)
    }

    @ViewBuilder
    private var activeStackSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Active Window Switcher")
                .font(.subheadline.weight(.semibold))

            Text("Open browser windows stay aligned while you move or resize any one of them.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ForEach(Array(activeWindows.enumerated()), id: \.element.id) { index, window in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(window.title)
                        Text("Position \(index + 1)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        moveActiveWindow(window.id, by: -1)
                    } label: {
                        Image(systemName: "arrow.up")
                    }
                    .buttonStyle(.borderless)
                    .disabled(index == 0)

                    Button {
                        moveActiveWindow(window.id, by: 1)
                    } label: {
                        Image(systemName: "arrow.down")
                    }
                    .buttonStyle(.borderless)
                    .disabled(index == activeWindows.count - 1)

                    Button("Remove") {
                        removeWindowFromActiveStack(window.id)
                    }
                    .buttonStyle(.borderless)
                }
            }

            if !inactiveWindows.isEmpty {
                Divider()

                Text("Available Browser Windows")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(inactiveWindows) { window in
                    HStack {
                        Text(window.title)
                        Spacer()
                        Button("Add") {
                            addWindowToActiveStack(window.id)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
    }

    private func startStack(with windows: [WindowChoice]) {
        guard let targetPID, let targetApplication else { return }
        guard let session = runtimeCoordinator.buildSession(
            targetPID: targetPID,
            targetApplication: targetApplication,
            appName: appName ?? "",
            windows: windows,
            existingSession: currentStackSession,
            availableWindows: availableWindows,
            onError: { errorMessage = $0 },
            onDebug: appendDebug,
            overlayHandlers: makeOverlayHandlers(for: targetApplication.processIdentifier)
        ) else { return }

        storeStackSession(session)
        syncSelectionState()
        isSelectingWindows = false
    }

    private func storeStackSession(_ session: ActiveStackSession) {
        session.overlayController.onHealthChanged = { [session] health in
            DispatchQueue.main.async {
                session.overlayHealth = health
                postSidebarSnapshot()
            }
        }
        session.controller.onGroupedWindowsChanged = { [session] remainingWindows in
            DispatchQueue.main.async {
                handleClosedWindows(for: session, remainingWindows: remainingWindows)
            }
        }
        sessionStore.store(session, availableWindows: &availableWindows, refreshOverlay: refreshOverlay)
        postActiveStackCount()
        postSidebarSnapshot()
        syncCombineOverlay()
    }

    private func removeCurrentStackSession(resetWindowOrder: Bool = true) {
        guard let targetPID else { return }
        removeStackSession(for: targetPID)
        if resetWindowOrder {
            activeWindowOrder = []
        }
    }

    private func clearCurrentWorkspace(resetWindowOrder: Bool = true) {
        removeCurrentStackSession(resetWindowOrder: resetWindowOrder)
        availableWindows = []
        isSelectingWindows = false
        groupedTitles = []
        activeWindowIDs = []
        errorMessage = nil
        restoreSelectedApplicationContext()
    }

    private func restoreSelectedApplicationContext() {
        if let selectedTargetPID,
           let selectedApp = eligibleApplications.first(where: { $0.processIdentifier == selectedTargetPID }) {
            prepareForTargetSwitch(to: selectedApp.processIdentifier)
            targetApplication = selectedApp
            appName = selectedApp.name
            targetPID = selectedApp.processIdentifier
        } else {
            targetApplication = nil
            appName = nil
            targetPID = nil
        }
    }

    private func prepareForTargetSwitch(to pid: pid_t) {
        guard targetPID != pid else { return }
        availableWindows = []
        isSelectingWindows = false
        groupedTitles = []
        activeWindowIDs = []
        activeWindowOrder = []
        errorMessage = nil
    }

    private func removeStackSession(for pid: pid_t) {
        _ = sessionStore.removeSession(for: pid, targetPID: targetPID, availableWindows: &availableWindows)
        postActiveStackCount()
        postSidebarSnapshot()
        syncCombineOverlay()
    }

    private func syncCurrentStackState() {
        sessionStore.syncCurrentStackState(targetPID: targetPID, availableWindows: &availableWindows)
    }

    private func handleClosedWindows(for session: ActiveStackSession, remainingWindows: [WindowChoice]) {
        let remainingIDs = Set(remainingWindows.map(\.id))
        let removedIDs = session.windowIDs.subtracting(remainingIDs)

        guard !removedIDs.isEmpty || remainingWindows.count != session.windowOrder.count else {
            return
        }

        availableWindows.removeAll { removedIDs.contains($0.id) }
        session.availableWindowChoices.removeAll { removedIDs.contains($0.id) }
        session.windowAccentStyles = session.windowAccentStyles.filter { remainingIDs.contains($0.key) }
        session.windowOrder = remainingWindows.map(\.id)
        session.windowIDs = remainingIDs
        session.windowTitles = remainingWindows.map(\.title)

        if remainingWindows.count < 2 {
            removeStackSession(for: session.app.processIdentifier)
            return
        }

        if targetPID == session.app.processIdentifier {
            groupedTitles = session.windowTitles
            activeWindowIDs = session.windowIDs
            activeWindowOrder = session.windowOrder
            syncSelectionState()
        }

        refreshOverlay(for: session)
        postSidebarSnapshot()
        syncCombineOverlay()
    }

    private func postActiveStackCount() {
        let count = activeStackSessions.count
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .stackerActiveStackCountDidChange,
                object: nil,
                userInfo: ["count": count]
            )
        }
    }

    private func addWindowToActiveStack(_ id: UInt) {
        activeWindowIDs.insert(id)
        if !activeWindowOrder.contains(id) {
            activeWindowOrder.append(id)
        }
        let windows = windows(for: activeWindowOrder)
        startStack(with: windows)
    }

    private func removeWindowFromActiveStack(_ id: UInt) {
        separateWindowFromStack(id)
        activeWindowIDs.remove(id)
        activeWindowOrder.removeAll { $0 == id }
        let windows = windows(for: activeWindowOrder)
        if windows.count < 2 {
            removeCurrentStackSession()
            groupedTitles = windows.map(\.title)
            activeWindowIDs = Set(windows.map(\.id))
            activeWindowOrder = windows.map(\.id)
            syncSelectionState()
            if windows.isEmpty {
                isSelectingWindows = false
            }
            return
        }
        startStack(with: windows)
    }

    private func moveActiveWindow(_ id: UInt, by offset: Int) {
        guard let currentIndex = activeWindowOrder.firstIndex(of: id) else { return }
        let newIndex = currentIndex + offset
        guard activeWindowOrder.indices.contains(newIndex) else { return }

        var reordered = activeWindowOrder
        let movedID = reordered.remove(at: currentIndex)
        reordered.insert(movedID, at: newIndex)
        activeWindowOrder = reordered
        startStack(with: windows(for: reordered))
    }

    private func syncSelectionState() {
        sessionStore.syncSelectionState(availableWindows: &availableWindows)
    }

    private func refreshOverlay(for session: ActiveStackSession) {
        runtimeCoordinator.refreshOverlay(for: session)
    }

    private func applyCurrentWidgetPalette() {
        activeStackSessions.forEach { session in
            runtimeCoordinator.applyCurrentDotPalette(to: session)
            refreshOverlay(for: session)
        }
        postSidebarSnapshot()
    }

    private func applyCurrentWidgetAppearance() {
        activeStackSessions.forEach { session in
            runtimeCoordinator.applyCurrentAppearance(to: session)
            refreshOverlay(for: session)
        }
        postSidebarSnapshot()
    }

    private func applyCurrentWidgetPlacement() {
        let preference = StackOverlayPlacementPreferenceStore.current()
        activeStackSessions.forEach { session in
            session.overlayPlacementPreference = preference
            if let dockPosition = preference.dockPosition {
                session.overlayDockPosition = dockPosition
            }
            refreshOverlay(for: session)
        }
        postSidebarSnapshot()
    }

    private func windows(for ids: [UInt]) -> [WindowChoice] {
        ids.compactMap { id in
            availableWindows.first(where: { $0.id == id })
        }
    }

    private func makeOverlayHandlers(for sessionPID: pid_t) -> StackOverlayCoordinatorHandlers {
        StackOverlayCoordinatorHandlers(
            onSelect: { [weak sessionStore] id in
                sessionStore?.activeStackSessions.first(where: { $0.app.processIdentifier == sessionPID })?.controller.focusWindow(withID: id)
            },
            onDisplayModeChanged: { newMode in
                updateOverlayDisplayMode(for: sessionPID, mode: newMode)
            },
            onLabelModeChanged: { newMode in
                updateOverlayLabelMode(for: sessionPID, mode: newMode)
            },
            onDensityModeChanged: { newMode in
                updateOverlayDensityMode(for: sessionPID, mode: newMode)
            },
            onPlacementPreferenceChanged: { preference in
                updateOverlayPlacementPreference(for: sessionPID, preference: preference)
            },
            onDockPositionChanged: { newPosition in
                updateOverlayDockPosition(for: sessionPID, position: newPosition)
            },
            onAddWindow: { id in
                addWindowToSession(for: sessionPID, id: id)
            },
            onOpenEditor: {
                NotificationCenter.default.post(
                    name: .stackerSelectTargetApplication,
                    object: nil,
                    userInfo: ["pid": sessionPID]
                )
                StackerAppWindowActions.openMainWindow()
            },
            onHideWidget: {
                let session = activeStackSessions.first(where: { $0.app.processIdentifier == sessionPID })
                let bundleIdentifier = session?.app.bundleIdentifier ?? targetApplication?.bundleIdentifier
                let resolvedAppName = session?.app.name ?? appName ?? "Stack"

                OverlayAppVisibilityPreference.setHidden(
                    true,
                    bundleIdentifier: bundleIdentifier,
                    appName: resolvedAppName
                )
                NotificationCenter.default.post(
                    name: .stackerToggleApplicationOverlayVisibility,
                    object: nil,
                    userInfo: [
                        "bundleIdentifier": bundleIdentifier ?? "",
                        "appName": resolvedAppName,
                        "pid": sessionPID
                    ]
                )
            },
            onFocusStack: {
                focusApplicationStack(for: sessionPID)
            },
            onTurnOff: {
                removeStackSession(for: sessionPID)
            },
            onMove: { id, offset in
                moveWindowInSession(for: sessionPID, id: id, by: offset)
            },
            onReorder: { sourceID, targetID in
                reorderWindowInSession(for: sessionPID, sourceID: sourceID, before: targetID)
            },
            onRemove: { id in
                removeWindowFromSession(for: sessionPID, id: id)
            }
        )
    }

    private func displayTitle(for id: UInt, titles: [String], order: [UInt]) -> String {
        StackWindowFormatter.displayTitle(for: id, titles: titles, order: order)
    }

    private func moveWindowInSession(for pid: pid_t, id: UInt, by offset: Int) {
        sessionCoordinator.moveWindowInSession(
            store: sessionStore,
            targetPID: targetPID,
            pid: pid,
            id: id,
            offset: offset,
            refreshOverlay: refreshOverlay,
            syncSelectionState: syncSelectionState,
            postSidebarSnapshot: postSidebarSnapshot,
            syncCombineOverlay: syncCombineOverlay
        )
    }

    private func reorderWindowInSession(for pid: pid_t, sourceID: UInt, before targetID: UInt) {
        sessionCoordinator.reorderWindowInSession(
            store: sessionStore,
            targetPID: targetPID,
            pid: pid,
            sourceID: sourceID,
            targetWindowID: targetID,
            refreshOverlay: refreshOverlay,
            syncSelectionState: syncSelectionState,
            postSidebarSnapshot: postSidebarSnapshot,
            syncCombineOverlay: syncCombineOverlay
        )
    }

    private func reorderWindowsInSession(for pid: pid_t, orderedIDs: [UInt]) {
        sessionCoordinator.reorderWindowsInSession(
            store: sessionStore,
            targetPID: targetPID,
            pid: pid,
            orderedIDs: orderedIDs,
            refreshOverlay: refreshOverlay,
            syncSelectionState: syncSelectionState,
            postSidebarSnapshot: postSidebarSnapshot,
            syncCombineOverlay: syncCombineOverlay
        )
    }

    private func addWindowToSession(for pid: pid_t, id: UInt) {
        sessionCoordinator.addWindowToSession(
            store: sessionStore,
            targetPID: targetPID,
            pid: pid,
            id: id,
            combineOverlayController: combineOverlayController,
            refreshOverlay: refreshOverlay,
            syncSelectionState: syncSelectionState,
            postSidebarSnapshot: postSidebarSnapshot,
            syncCombineOverlay: syncCombineOverlay
        )
    }

    private func removeWindowFromSession(for pid: pid_t, id: UInt) {
        sessionCoordinator.removeWindowFromSession(
            store: sessionStore,
            targetPID: targetPID,
            pid: pid,
            id: id,
            removeStackSession: removeStackSession,
            refreshOverlay: refreshOverlay,
            syncSelectionState: syncSelectionState,
            postSidebarSnapshot: postSidebarSnapshot,
            syncCombineOverlay: syncCombineOverlay,
            showAddBackOverlay: showAddBackOverlay(for:)
        )
    }

    private func updateOverlayDisplayMode(for pid: pid_t, mode: StackOverlayDisplayMode) {
        sessionCoordinator.updateOverlayDisplayMode(
            store: sessionStore,
            pid: pid,
            mode: mode,
            refreshOverlay: refreshOverlay,
            postSidebarSnapshot: postSidebarSnapshot
        )
    }

    private func updateOverlayLabelMode(for pid: pid_t, mode: StackOverlayLabelMode) {
        sessionCoordinator.updateOverlayLabelMode(
            store: sessionStore,
            pid: pid,
            mode: mode,
            refreshOverlay: refreshOverlay,
            postSidebarSnapshot: postSidebarSnapshot
        )
    }

    private func updateOverlayDensityMode(for pid: pid_t, mode: StackOverlayDensityMode) {
        sessionCoordinator.updateOverlayDensityMode(
            store: sessionStore,
            pid: pid,
            mode: mode,
            refreshOverlay: refreshOverlay,
            postSidebarSnapshot: postSidebarSnapshot
        )
    }

    private func updateOverlayPlacementPreference(for pid: pid_t, preference: StackOverlayPlacementPreference) {
        sessionCoordinator.updateOverlayPlacementPreference(
            store: sessionStore,
            pid: pid,
            preference: preference,
            refreshOverlay: refreshOverlay,
            postSidebarSnapshot: postSidebarSnapshot
        )
    }

    private func updateOverlayDockPosition(for pid: pid_t, position: StackOverlayDockPosition) {
        sessionCoordinator.updateOverlayDockPosition(
            store: sessionStore,
            pid: pid,
            position: position,
            refreshOverlay: refreshOverlay,
            postSidebarSnapshot: postSidebarSnapshot
        )
    }

    private func focusApplicationStack(for pid: pid_t) {
        guard let session = activeStackSessions.first(where: { $0.app.processIdentifier == pid }) else { return }
        runtimeCoordinator.focusApplicationStack(
            session: session,
            selectTargetPID: { selectedTargetPID = $0 },
            setTargetApplication: { targetApplication = $0 },
            setAppName: { appName = $0 },
            setTargetPID: { targetPID = $0 },
            syncCurrentStackState: syncCurrentStackState
        )
    }

    private func resetOverlayPosition(for pid: pid_t) {
        guard let session = activeStackSessions.first(where: { $0.app.processIdentifier == pid }) else { return }
        session.overlayController.resetPosition()
        session.overlayHealth = session.overlayController.currentHealth
        postSidebarSnapshot()
    }

    private func separateWindowFromStack(_ id: UInt) {
        guard let window = availableWindows.first(where: { $0.id == id }) else { return }

        if let axWindow = window.window,
           let position = axWindow.position,
           let size = axWindow.size {
            let newPosition = CGPoint(x: position.x + 56, y: position.y - 56)
            axWindow.set(position: newPosition)
            axWindow.set(size: size)
            return
        }

        if let scriptIndex = window.scriptIndex, let targetPID {
            let currentStates = WindowScriptBridge.fetchWindows(forProcessIdentifier: targetPID, windowIndices: [scriptIndex])
            if let state = currentStates.first {
                let newFrame = CGRect(
                    x: state.frame.origin.x + 56,
                    y: state.frame.origin.y - 56,
                    width: state.frame.size.width,
                    height: state.frame.size.height
                )
                _ = WindowScriptBridge.setFrame(newFrame, forWindowIndex: scriptIndex, processIdentifier: targetPID)
            }
        }
    }

    private func autoStackLoadedWindows() {
        workflowCoordinator.autoStackLoadedWindows(
            availableWindows: &availableWindows,
            setErrorMessage: { errorMessage = $0 },
            startStack: { startStack(with: $0) }
        )
    }

    private func postSidebarSnapshot() {
        let snapshot = sidebarSnapshotBuilder.makeSnapshot(
            eligibleApplications: eligibleApplications,
            activeStackSessions: activeStackSessions,
            groupedTitles: groupedTitles,
            activeWindows: activeWindows,
            inactiveWindows: inactiveWindows,
            availableWindows: availableWindows,
            isSelectingWindows: isSelectingWindows,
            targetPID: targetPID,
            appName: appName,
            displayTitle: { id, titles, order in
                displayTitle(for: id, titles: titles, order: order)
            }
        )
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .stackerSidebarSnapshotDidChange,
                object: snapshot
            )
        }
    }

    private func appendDebug(_ message: String) {
        let timestamp = Date.now.formatted(date: .omitted, time: .standard)
        let entry = "[\(timestamp)] \(message)"
        debugMessages.append(entry)
        if debugMessages.count > 40 {
            debugMessages.removeFirst(debugMessages.count - 40)
        }
    }

    private func postFrontmostApplicationDidChange(_ app: NSRunningApplication?) {
        NotificationCenter.default.post(
            name: .stackerFrontmostApplicationDidChange,
            object: nil,
            userInfo: [
                "pid": Int(app?.processIdentifier ?? 0),
                "bundleIdentifier": app?.bundleIdentifier ?? ""
            ]
        )
    }

    private func startTrackingActiveApplications() {
        eventCoordinator.startTrackingActiveApplications { app in
            updateTrackedApplication(from: app)
        }
    }

    private func startSidebarObservers() {
        eventCoordinator.startSidebarObservers(
            handlers: StackerSidebarEventHandlers(
                onSelectTargetApplication: { pid in
                    if selectedTargetPID == pid {
                        Task { @MainActor in
                            await loadFrontmostAppWindows()
                        }
                    }
                    selectedTargetPID = pid
                },
                onAutoStackApplication: { pid in
                    pendingAutoStackPID = pid
                    selectedTargetPID = pid

                    if targetPID == pid {
                        Task { @MainActor in
                            await loadFrontmostAppWindows()
                            if pendingAutoStackPID == pid {
                                pendingAutoStackPID = nil
                                autoStackLoadedWindows()
                            }
                        }
                    }
                },
                onRefreshApplications: {
                    Task { @MainActor in
                        await loadEligibleApplications()
                        await loadFrontmostAppWindows()
                    }
                },
                onReadSelectedWindows: {
                    Task { @MainActor in
                        await loadFrontmostAppWindows()
                    }
                },
                onResetSelectedStack: {
                    removeCurrentStackSession()
                    groupedTitles = []
                    activeWindowIDs = []
                    syncSelectionState()
                },
                onResetApplicationStack: { pid in
                    removeStackSession(for: pid)
                },
                onToggleApplicationOverlayVisibility: { bundleIdentifier, appName in
                    NotificationCenter.default.post(name: .stackerOverlayVisibilityDidChange, object: nil)
                    postSidebarSnapshot()
                    if let session = activeStackSessions.first(where: {
                        OverlayAppVisibilityPreference.appIdentifier(bundleIdentifier: $0.app.bundleIdentifier, appName: $0.app.name) == OverlayAppVisibilityPreference.appIdentifier(bundleIdentifier: bundleIdentifier, appName: appName)
                    }) {
                        refreshOverlay(for: session)
                    }
                },
                onMoveWindowInStack: { pid, windowID, direction in
                    moveWindowInSession(for: pid, id: windowID, by: direction)
                },
                onReorderWindowsInStack: { pid, windowIDs in
                    reorderWindowsInSession(for: pid, orderedIDs: windowIDs)
                },
                onAddWindowToStack: { pid, windowID in
                    addWindowToSession(for: pid, id: windowID)
                },
                onRemoveWindowFromStack: { pid, windowID in
                    removeWindowFromSession(for: pid, id: windowID)
                },
                onFocusApplicationStack: { pid in
                    focusApplicationStack(for: pid)
                },
                onResetApplicationOverlayPosition: { pid in
                    resetOverlayPosition(for: pid)
                }
            )
        )
    }

    private func stopTrackingActiveApplications() {
        eventCoordinator.stopTrackingActiveApplications()
    }

    private func startTrackingSystemWake() {
        eventCoordinator.startTrackingSystemWake {
            handleSystemWake()
        }
    }

    private func stopTrackingSystemWake() {
        eventCoordinator.stopTrackingSystemWake()
    }

    private func stopSidebarObservers() {
        eventCoordinator.stopSidebarObservers()
    }

    private func handleSystemWake() {
        Task { @MainActor in
            errorMessage = nil
            appendDebug("System wake detected; refreshing browser windows.")
            try? await Task.sleep(for: .milliseconds(900))
            await refreshBrowserSessionsAfterWake()
        }
    }

    @MainActor
    private func refreshBrowserSessionsAfterWake() async {
        refreshAccessibilityState()
        guard workspaceController.isAccessibilityTrusted() else {
            showAccessibilityAlert = true
            return
        }

        let previousSelectedPID = selectedTargetPID
        let sessionsToRefresh = activeStackSessions.filter { $0.app.isSupportedBrowser }

        await loadEligibleApplications()

        for session in sessionsToRefresh {
            guard let refreshedApp = eligibleApplications.first(where: { $0.processIdentifier == session.app.processIdentifier }) else {
                removeStackSession(for: session.app.processIdentifier)
                continue
            }

            let outcome = await WindowDiscoveryService(log: appendDebug).loadWindows(for: refreshedApp)
            let refreshedWindows = orderedWindowsAfterWake(
                previousTitles: session.windowTitles,
                previousScriptIndices: session.controller.groupedWindowChoices(in: session.windowOrder).compactMap(\.scriptIndex),
                refreshedWindows: outcome.availableWindows
            )

            if refreshedWindows.count < 2 {
                if let error = outcome.errorMessage,
                   WindowDiscoveryService.isTransientDiscoveryErrorForMessage(error) {
                    markStackDegraded(for: session.app.processIdentifier, reason: error)
                } else {
                    removeStackSession(for: session.app.processIdentifier)
                }
                continue
            }

            if session.app.processIdentifier == targetPID {
                availableWindows = outcome.availableWindows
            }

            guard let rebuiltSession = runtimeCoordinator.buildSession(
                targetPID: refreshedApp.processIdentifier,
                targetApplication: refreshedApp,
                appName: refreshedApp.name,
                windows: refreshedWindows,
                existingSession: session,
                availableWindows: outcome.availableWindows,
                onError: { appendDebug("Wake refresh skipped transient window error: \($0)") },
                onDebug: appendDebug,
                overlayHandlers: makeOverlayHandlers(for: refreshedApp.processIdentifier)
            ) else {
                continue
            }

            storeStackSession(rebuiltSession)
        }

        if let previousSelectedPID,
           eligibleApplications.contains(where: { $0.processIdentifier == previousSelectedPID }) {
            selectedTargetPID = previousSelectedPID
        }

        restoreSelectedApplicationContext()
        syncCurrentStackState()
        syncCombineOverlay()
        postSidebarSnapshot()
    }

    private func orderedWindowsAfterWake(
        previousTitles: [String],
        previousScriptIndices: [Int],
        refreshedWindows: [WindowChoice]
    ) -> [WindowChoice] {
        guard !refreshedWindows.isEmpty else { return [] }

        var remaining = refreshedWindows
        var ordered: [WindowChoice] = []

        for scriptIndex in previousScriptIndices {
            guard let matchIndex = remaining.firstIndex(where: { $0.scriptIndex == scriptIndex }) else { continue }
            ordered.append(remaining.remove(at: matchIndex))
        }

        for title in previousTitles {
            guard let matchIndex = remaining.firstIndex(where: { $0.title == title }) else { continue }
            ordered.append(remaining.remove(at: matchIndex))
        }

        ordered.append(contentsOf: remaining)
        return ordered
    }

    private func startCombineOverlay() {
        combineOverlayController.startTracking {
            frontmostEligibleWindowFrame()
        }
        syncCombineOverlay()
    }

    private func updateTrackedApplication(from app: NSRunningApplication?) {
        frontmostCoordinator.updateTrackedApplication(
            app: app,
            workspaceController: workspaceController,
            activeStackSessions: activeStackSessions,
            selectedTargetPID: selectedTargetPID,
            groupedTitles: groupedTitles,
            isSelectingWindows: isSelectingWindows,
            postFrontmostNotification: postFrontmostApplicationDidChange,
            syncCombineOverlay: syncCombineOverlay,
            loadEligibleApplications: loadEligibleApplications,
            refreshOverlay: refreshOverlay,
            selectOverlayWindow: { session, windowID in
                session.overlayController.selectWindow(windowID)
            },
            setSelectedTargetPID: { selectedTargetPID = $0 },
            setTargetApplication: { targetApplication = $0 },
            setAppName: { appName = $0 },
            setTargetPID: { targetPID = $0 },
            syncCurrentStackState: syncCurrentStackState,
            eligibleApplicationsProvider: { eligibleApplications }
        )
    }

    @MainActor
    private func loadEligibleApplications() async {
        await workspaceController.loadEligibleApplications(activeStackSessions: activeStackSessions)
        if let selectedTargetPID,
           let selectedApp = eligibleApplications.first(where: { $0.processIdentifier == selectedTargetPID }) {
            prepareForTargetSwitch(to: selectedApp.processIdentifier)
            targetApplication = selectedApp
            appName = selectedApp.name
            targetPID = selectedApp.processIdentifier
            syncCurrentStackState()
        } else if let firstApp = eligibleApplications.first {
            prepareForTargetSwitch(to: firstApp.processIdentifier)
            selectedTargetPID = firstApp.processIdentifier
            targetApplication = firstApp
            appName = firstApp.name
            targetPID = firstApp.processIdentifier
            syncCurrentStackState()
        } else {
            selectedTargetPID = nil
            restoreSelectedApplicationContext()
            groupedTitles = []
            activeWindowIDs = []
            errorMessage = nil
        }

        syncCombineOverlay()
    }

    private func syncCombineOverlay() {
        frontmostCoordinator.syncCombineOverlay(
            frontmostApp: NSWorkspace.shared.frontmostApplication,
            frontmostEligiblePID: frontmostEligiblePID,
            eligibleApplications: eligibleApplications,
            activeStackSessions: activeStackSessions,
            combineOverlayController: combineOverlayController,
            showAddBackOverlay: showAddBackOverlay(for:),
            frontmostEligibleWindowFrame: frontmostEligibleWindowFrame,
            triggerCombine: triggerCombine
        )
    }

    private func showAddBackOverlay(for session: ActiveStackSession) {
        guard let fallbackWindow = session.availableWindowChoices.first else {
            combineOverlayController.clear()
            return
        }

        combineOverlayController.update(
            appPID: session.app.processIdentifier,
            appBundleIdentifier: session.app.bundleIdentifier,
            appName: session.app.name,
            style: .addBack(
                title: fallbackWindow.title
            ),
            frameProvider: { [session] in
                guard let focusedWindow = StackOverlayTargeting.focusedAddBackWindow(in: session) else { return nil }
                return StackOverlayTargeting.focusedFrameForWindowChoice(
                    focusedWindow,
                    appPID: session.app.processIdentifier,
                    appName: session.app.name
                )
            }
        ) { [session] in
            guard let focusedWindow = StackOverlayTargeting.focusedAddBackWindow(in: session) else { return }
            addWindowToSession(for: session.app.processIdentifier, id: focusedWindow.id)
        }
    }

    private func triggerCombine(for pid: pid_t) {
        workflowCoordinator.triggerCombine(
            pid: pid,
            targetPID: targetPID,
            setPendingAutoStackPID: { pendingAutoStackPID = $0 },
            setSelectedTargetPID: { selectedTargetPID = $0 },
            loadFrontmostAppWindows: loadFrontmostAppWindows,
            clearPendingAutoStackPID: { pendingAutoStackPID = nil },
            autoStackLoadedWindows: autoStackLoadedWindows
        )
    }

    private func frontmostEligibleWindowFrame() -> CGRect? {
        guard let pid = frontmostEligiblePID else {
            return nil
        }
        return StackOverlayTargeting.frontmostEligibleWindowFrame(for: pid, activeStackSessions: activeStackSessions)
    }

    @MainActor
    private func runningApplication(for targetApplication: TargetApplication) -> NSRunningApplication? {
        NSRunningApplication(processIdentifier: targetApplication.processIdentifier)
    }

    @MainActor
    private func loadFrontmostAppWindows() async {
        guard workspaceController.isAccessibilityTrusted() else {
            showAccessibilityAlert = true
            return
        }

        isLoadingWindows = true
        defer { isLoadingWindows = false }

        errorMessage = nil
        debugMessages = []

        guard let targetApplication else {
            errorMessage = "No supported browser is available yet. Open at least two browser windows, then refresh Stacker."
            return
        }

        appName = targetApplication.name
        targetPID = targetApplication.processIdentifier
        let outcome = await WindowDiscoveryService(log: appendDebug).loadWindows(for: targetApplication)
        availableWindows = outcome.availableWindows
        syncSelectionState()
        isSelectingWindows = outcome.shouldEnterSelectionMode

        if let error = outcome.errorMessage {
            let isTransient = WindowDiscoveryService.isTransientDiscoveryErrorForMessage(error)

            if let existingSession = activeStackSessions.first(where: { $0.app.processIdentifier == targetApplication.processIdentifier }),
               isTransient {
                markStackDegraded(for: targetApplication.processIdentifier, reason: error)
            } else {
                errorMessage = error
            }
        }
    }

    private func markStackDegraded(for pid: pid_t, reason: String) {
        guard let session = activeStackSessions.first(where: { $0.app.processIdentifier == pid }) else { return }

        appendDebug("Marking stack degraded for \(session.app.name): \(reason)")

        session.overlayHealth = .degraded
        // Hide the widget for this degraded stack
        runtimeCoordinator.refreshOverlay(for: session)   // will respect health

        // Notify menu bar / sidebar that something needs attention
        postActiveStackCount()
        postSidebarSnapshot()
        syncCombineOverlay()
    }
}

#Preview {
    ContentView()
}
