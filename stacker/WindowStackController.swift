import AppKit
import ApplicationServices

final class WindowStackController {
    enum GroupingMode {
        case stack
        case layout
    }

    var groupedTitles: [String] = []
    private(set) var groupingMode: GroupingMode = .stack
    var onError: ((String) -> Void)?
    var onDebug: ((String) -> Void)?
    var onGroupedWindowsChanged: (([WindowChoice]) -> Void)?

    private var groupedWindows: [WindowChoice] = []
    private var observer: AXObserver?
    private var observerRunLoopSourceInstalled = false
    private var isApplyingSync = false
    private var scriptTimer: Timer?
    private var scriptAppName: String?
    private var groupedAppName: String?
    private var appPID: pid_t = 0
    private var groupedScriptIndices: [Int] = []
    private var lastScriptFrames: [Int: CGRect] = [:]
    private var isApplyingScriptSync = false
    private var selectedWindowID: UInt?
    private var frameSyncDebounceTimer: Timer?
    private var pendingAXSyncSourceWindow: AXUIElement?
    private var scriptFrameSyncDebounceTimer: Timer?
    private var pendingScriptSyncFrame: CGRect?
    private var pendingScriptSyncSourceIndex: Int?
    private var relativeAXLayoutFrames: [UInt: CGRect] = [:]
    private var relativeScriptLayoutFrames: [Int: CGRect] = [:]
    private var layoutAnchorWindowID: UInt?
    private var layoutAnchorScriptIndex: Int?
    private var isSyncSuspended = false

    private let followerSyncDebounceInterval: TimeInterval = 0.16

    @discardableResult
    func startGrouping(_ windows: [WindowChoice], pid: pid_t, appName: String) -> Bool {
        stopGrouping()
        appPID = pid
        groupedAppName = appName

        guard windows.count >= 2 else {
            onError?("Select at least two windows to create a stack.")
            return false
        }

        if windows.allSatisfy({ $0.scriptIndex != nil }) {
            return startScriptGrouping(windows, appName: appName)
        }

        groupedWindows = windows
        groupedTitles = windows.map(\.title)
        selectedWindowID = windows.first?.id
        layoutAnchorWindowID = windows.first?.id

        guard let anchorChoice = windows.first,
              let sourceWindow = anchorChoice.window,
              let sourcePosition = sourceWindow.position,
              let sourceSize = sourceWindow.size else {
            onError?("Unable to access the selected anchor window.")
            return false
        }

        let anchorFrame = CGRect(origin: sourcePosition, size: sourceSize)
        let positionedWindows = windows.compactMap { window -> (choice: WindowChoice, element: AXUIElement, frame: CGRect)? in
            guard let axWindow = window.window else { return nil }
            let frame = CGRect(origin: axWindow.position ?? anchorFrame.origin, size: axWindow.size ?? anchorFrame.size)
            return (window, axWindow, frame)
        }
        guard positionedWindows.count >= 2 else {
            onError?("Unable to access enough selected windows.")
            return false
        }

        groupingMode = resolvedGroupingMode(for: positionedWindows.map(\.frame))
        if groupingMode == .layout {
            relativeAXLayoutFrames = relativeFramesByWindowID(from: positionedWindows.map { ($0.choice.id, $0.frame) })
        } else {
            relativeAXLayoutFrames = [:]
        }
        onDebug?("Started \(groupingMode.debugName) grouping for \(appName) windows \(windows.map(\.id))")
        syncFrame(from: sourceWindow)

        var createdObserver: AXObserver?
        let callback: AXObserverCallback = { _, element, notification, refcon in
            guard let refcon else { return }
            let controller = Unmanaged<WindowStackController>.fromOpaque(refcon).takeUnretainedValue()
            controller.handleNotification(for: element, notification: notification as String)
        }

        let result = AXObserverCreate(pid, callback, &createdObserver)
        guard result == .success, let createdObserver else {
            onError?("Unable to watch the selected windows for changes.")
            groupedWindows = []
            groupedTitles = []
            return false
        }

        observer = createdObserver

        let refcon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        for window in windows {
            guard let axWindow = window.window else { continue }
            AXObserverAddNotification(createdObserver, axWindow, kAXMovedNotification as CFString, refcon)
            AXObserverAddNotification(createdObserver, axWindow, kAXResizedNotification as CFString, refcon)
            AXObserverAddNotification(createdObserver, axWindow, kAXWindowMiniaturizedNotification as CFString, refcon)
            AXObserverAddNotification(createdObserver, axWindow, kAXWindowDeminiaturizedNotification as CFString, refcon)
            AXObserverAddNotification(createdObserver, axWindow, kAXUIElementDestroyedNotification as CFString, refcon)
        }

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(createdObserver),
            .defaultMode
        )
        observerRunLoopSourceInstalled = true

        return true
    }

    func stopGrouping(separateWindows: Bool = false) {
        if let observer, observerRunLoopSourceInstalled {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(observer),
                .defaultMode
            )
        }
        observerRunLoopSourceInstalled = false
        observer = nil

        if separateWindows {
            separateGroupedWindows()
        }

        groupedWindows = []
        groupedTitles = []
        scriptTimer?.invalidate()
        scriptTimer = nil
        frameSyncDebounceTimer?.invalidate()
        frameSyncDebounceTimer = nil
        pendingAXSyncSourceWindow = nil
        scriptFrameSyncDebounceTimer?.invalidate()
        scriptFrameSyncDebounceTimer = nil
        pendingScriptSyncFrame = nil
        pendingScriptSyncSourceIndex = nil
        scriptAppName = nil
        groupedAppName = nil
        appPID = 0
        groupedScriptIndices = []
        lastScriptFrames = [:]
        selectedWindowID = nil
        groupingMode = .stack
        relativeAXLayoutFrames = [:]
        relativeScriptLayoutFrames = [:]
        layoutAnchorWindowID = nil
        layoutAnchorScriptIndex = nil
        isSyncSuspended = false
    }

    func setSyncSuspended(_ suspended: Bool) {
        guard isSyncSuspended != suspended else { return }
        isSyncSuspended = suspended

        if suspended {
            frameSyncDebounceTimer?.invalidate()
            frameSyncDebounceTimer = nil
            pendingAXSyncSourceWindow = nil
            scriptFrameSyncDebounceTimer?.invalidate()
            scriptFrameSyncDebounceTimer = nil
            pendingScriptSyncFrame = nil
            pendingScriptSyncSourceIndex = nil
            onDebug?("Suspended stack window syncing during system power transition.")
        } else {
            onDebug?("Resumed stack window syncing after system power transition.")
        }
    }

    private func separateGroupedWindows() {
        if !groupedWindows.isEmpty {
            separateAXWindows()
        } else if scriptAppName != nil, !groupedScriptIndices.isEmpty {
            separateScriptWindows()
        }
    }

    private func separateAXWindows() {
        guard groupingMode == .stack else { return }
        let positionedWindows = groupedWindows.compactMap { window -> (AXUIElement, CGPoint, CGSize)? in
            guard let axWindow = window.window,
                  let position = axWindow.position,
                  let size = axWindow.size else { return nil }
            return (axWindow, position, size)
        }

        guard let anchor = positionedWindows.first else { return }

        for (index, entry) in positionedWindows.enumerated() {
            guard index > 0 else { continue }
            let offset = CGFloat(index) * 36
            let newPosition = CGPoint(x: anchor.1.x + offset, y: anchor.1.y - offset)
            entry.0.set(position: newPosition)
            entry.0.set(size: anchor.2)
        }
    }

    private func separateScriptWindows() {
        guard scriptAppName != nil else { return }
        guard groupingMode == .stack else { return }
        let groupedStates = WindowScriptBridge.fetchWindows(forProcessIdentifier: appPID, windowIndices: groupedScriptIndices)
        guard let anchor = groupedStates.first else { return }

        for (index, state) in groupedStates.enumerated() {
            guard index > 0 else { continue }
            let offset = CGFloat(index) * 36
            let newFrame = CGRect(
                x: anchor.frame.origin.x + offset,
                y: anchor.frame.origin.y - offset,
                width: anchor.frame.size.width,
                height: anchor.frame.size.height
            )
            _ = WindowScriptBridge.setFrame(newFrame, forWindowIndex: state.index, processIdentifier: appPID)
        }
    }

    private func startScriptGrouping(_ windows: [WindowChoice], appName: String) -> Bool {
        let availableStates = WindowScriptBridge.fetchWindows(forProcessIdentifier: appPID)
        let selectedStates = windows.compactMap { window -> ScriptWindowState? in
            guard let scriptIndex = window.scriptIndex else { return nil }
            return availableStates.first { $0.index == scriptIndex }
        }

        guard selectedStates.count >= 2 else {
            onError?("Unable to read the selected windows through System Events.")
            return false
        }

        groupedWindows = windows
        groupedTitles = windows.map(\.title)
        scriptAppName = appName
        groupedScriptIndices = selectedStates.map(\.index)
        lastScriptFrames = Dictionary(uniqueKeysWithValues: selectedStates.map { ($0.index, $0.frame) })
        selectedWindowID = windows.first?.id
        layoutAnchorWindowID = windows.first?.id
        layoutAnchorScriptIndex = selectedStates.first?.index

        let sourceFrame = selectedStates[0].frame
        groupingMode = resolvedGroupingMode(for: selectedStates.map(\.frame))
        if groupingMode == .layout {
            relativeScriptLayoutFrames = relativeFramesByWindowID(from: selectedStates.map { ($0.index, $0.frame) })
            normalizeScriptLayoutAroundAnchor(using: sourceFrame)
        } else {
            relativeScriptLayoutFrames = [:]
            for state in selectedStates.dropFirst() {
                let targetFrame = sourceFrame
                _ = WindowScriptBridge.setFrame(targetFrame, forWindowIndex: state.index, processIdentifier: appPID)
            }
        }

        isApplyingScriptSync = false
        scriptTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            self?.pollScriptWindows()
        }
        if let scriptTimer {
            RunLoop.main.add(scriptTimer, forMode: .common)
        }
        onDebug?("Started System Events \(groupingMode.debugName) syncing for \(appName) windows \(groupedScriptIndices)")
        return true
    }

    private func pollScriptWindows() {
        guard !isSyncSuspended else { return }
        guard !isTargetApplicationHidden() else { return }
        guard !isApplyingScriptSync, let appName = scriptAppName else { return }
        let currentStates = WindowScriptBridge.fetchWindows(forProcessIdentifier: appPID, windowIndices: groupedScriptIndices)
        reconcileScriptWindows(with: currentStates)
        guard !currentStates.isEmpty else { return }

        let groupedStates = currentStates.filter { groupedScriptIndices.contains($0.index) }
        guard groupedStates.count >= 2 else { return }

        var changedState: ScriptWindowState?
        for state in groupedStates {
            if let oldFrame = lastScriptFrames[state.index], oldFrame != state.frame {
                changedState = state
                break
            }
        }

        lastScriptFrames = Dictionary(uniqueKeysWithValues: groupedStates.map { ($0.index, $0.frame) })
        guard let changedState else { return }

        if groupingMode == .layout, changedState.index != layoutAnchorScriptIndex {
            updateSourceScriptLayoutFrame(index: changedState.index, frame: changedState.frame)
            return
        }

        scheduleScriptSync(from: changedState, appName: appName)
    }

    private func handleNotification(for element: AXUIElement, notification: String) {
        guard !isSyncSuspended else { return }
        guard !isTargetApplicationHidden() else { return }
        guard !isApplyingSync else { return }
        if notification == kAXUIElementDestroyedNotification as String {
            reconcileAXWindows()
            return
        }
        if notification == kAXWindowMiniaturizedNotification as String ||
            notification == kAXWindowDeminiaturizedNotification as String {
            if notification == kAXWindowMiniaturizedNotification as String,
               let minimizedChoice = groupedWindows.first(where: { choice in
                   guard let window = choice.window else { return false }
                   return CFHash(window) == CFHash(element)
               }),
               selectedWindowID == minimizedChoice.id {
                selectedWindowID = preferredAnchorWindowID()
            }
            onGroupedWindowsChanged?(groupedWindows)
            return
        }
        guard notification == kAXMovedNotification as String || notification == kAXResizedNotification as String else {
            return
        }

        scheduleAXSync(from: element)
    }

    private func scheduleAXSync(from sourceWindow: AXUIElement) {
        guard !isSyncSuspended else { return }
        pendingAXSyncSourceWindow = sourceWindow
        frameSyncDebounceTimer?.invalidate()
        frameSyncDebounceTimer = Timer.scheduledTimer(withTimeInterval: followerSyncDebounceInterval, repeats: false) { [weak self] _ in
            self?.flushPendingAXSync()
        }
        if let frameSyncDebounceTimer {
            RunLoop.main.add(frameSyncDebounceTimer, forMode: .common)
        }
    }

    private func flushPendingAXSync() {
        frameSyncDebounceTimer?.invalidate()
        frameSyncDebounceTimer = nil
        guard !isSyncSuspended else {
            pendingAXSyncSourceWindow = nil
            return
        }
        guard let sourceWindow = pendingAXSyncSourceWindow else { return }
        pendingAXSyncSourceWindow = nil
        syncFrame(from: sourceWindow)
    }

    private func scheduleScriptSync(from state: ScriptWindowState, appName: String) {
        guard !isSyncSuspended else { return }
        pendingScriptSyncFrame = state.frame
        pendingScriptSyncSourceIndex = state.index
        selectedWindowID = groupedWindows.first(where: { $0.scriptIndex == state.index })?.id ?? selectedWindowID
        scriptFrameSyncDebounceTimer?.invalidate()
        scriptFrameSyncDebounceTimer = Timer.scheduledTimer(withTimeInterval: followerSyncDebounceInterval, repeats: false) { [weak self] _ in
            self?.flushPendingScriptSync(appName: appName)
        }
        if let scriptFrameSyncDebounceTimer {
            RunLoop.main.add(scriptFrameSyncDebounceTimer, forMode: .common)
        }
    }

    private func flushPendingScriptSync(appName: String) {
        scriptFrameSyncDebounceTimer?.invalidate()
        scriptFrameSyncDebounceTimer = nil
        guard !isSyncSuspended else {
            pendingScriptSyncFrame = nil
            pendingScriptSyncSourceIndex = nil
            return
        }
        guard let changedFrame = pendingScriptSyncFrame,
              let sourceIndex = pendingScriptSyncSourceIndex else { return }
        pendingScriptSyncFrame = nil
        pendingScriptSyncSourceIndex = nil

        let groupedStates = WindowScriptBridge.fetchWindows(forProcessIdentifier: appPID, windowIndices: groupedScriptIndices)
        guard groupedStates.count >= 2 else { return }

        isApplyingScriptSync = true
        defer { isApplyingScriptSync = false }

        updateSourceScriptLayoutFrame(index: sourceIndex, frame: changedFrame)
        for state in groupedStates {
            let targetFrame = targetScriptFrame(for: state, sourceIndex: sourceIndex, sourceFrame: changedFrame)
            guard state.frame != targetFrame else { continue }
            let didSet = WindowScriptBridge.setFrame(targetFrame, forWindowIndex: state.index, processIdentifier: appPID)
            if !didSet {
                onError?("Unable to update one of the grouped windows through System Events.")
                break
            }
        }

        lastScriptFrames = Dictionary(uniqueKeysWithValues: groupedStates.map { state in
            (state.index, targetScriptFrame(for: state, sourceIndex: sourceIndex, sourceFrame: changedFrame))
        })
    }

    private func syncFrame(from sourceWindow: AXUIElement) {
        guard !isSyncSuspended else { return }
        guard !isTargetApplicationHidden() else { return }
        reconcileAXWindows()
        guard let position = sourceWindow.position, let size = sourceWindow.size else {
            onError?("Unable to read the source window frame.")
            return
        }

        isApplyingSync = true
        defer { isApplyingSync = false }

        let sourceID = groupedWindows.first(where: { choice in
            guard let axWindow = choice.window else { return false }
            return CFHash(axWindow) == CFHash(sourceWindow)
        })?.id
        selectedWindowID = sourceID ?? selectedWindowID
        let sourceFrame = CGRect(origin: position, size: size)

        if let sourceID {
            updateSourceAXLayoutFrame(id: sourceID, frame: sourceFrame)
        }
        if groupingMode == .layout, sourceID != layoutAnchorWindowID {
            return
        }

        for window in groupedWindows {
            guard let axWindow = window.window else { continue }
            guard CFHash(axWindow) != CFHash(sourceWindow) else { continue }
            let targetFrame = targetAXFrame(for: window.id, sourceID: sourceID, sourceFrame: sourceFrame)
            axWindow.set(position: targetFrame.origin)
            axWindow.set(size: targetFrame.size)
        }
    }

    private func resolvedGroupingMode(for frames: [CGRect]) -> GroupingMode {
        guard frames.count >= 2 else { return .stack }
        let areas = frames.map { max(1, $0.width * $0.height) }
        guard let smallestArea = areas.min(), let largestArea = areas.max() else { return .stack }
        let widths = frames.map(\.width)
        let heights = frames.map(\.height)
        let widthSpread = (widths.max() ?? 0) - (widths.min() ?? 0)
        let heightSpread = (heights.max() ?? 0) - (heights.min() ?? 0)
        let areaRatio = largestArea / smallestArea
        let aspectRatios = frames.map { max(0.1, $0.width) / max(0.1, $0.height) }
        let aspectSpread = abs((aspectRatios.max() ?? 1) - (aspectRatios.min() ?? 1))
        let smallWindowCount = frames.filter { frame in
            frame.width < 520 || frame.height < 420
        }.count

        let hasUtilityStyleWindow = smallWindowCount > 0
        let hasLargeSizeMismatch = areaRatio > 1.9 || widthSpread > 320 || heightSpread > 240
        let hasVeryDifferentShape = aspectSpread > 0.45

        return hasUtilityStyleWindow && (hasLargeSizeMismatch || hasVeryDifferentShape) ? .layout : .stack
    }

    private func relativeFramesByWindowID<ID: Hashable>(from frames: [(ID, CGRect)]) -> [ID: CGRect] {
        guard let anchorFrame = frames.first?.1 else { return [:] }
        return Dictionary(uniqueKeysWithValues: frames.map { id, frame in
            let relativeFrame = CGRect(
                x: frame.origin.x - anchorFrame.origin.x,
                y: frame.origin.y - anchorFrame.origin.y,
                width: frame.width,
                height: frame.height
            )
            return (id, relativeFrame)
        })
    }

    private func updateSourceAXLayoutFrame(id: UInt, frame: CGRect) {
        guard groupingMode == .layout,
              let anchorFrame = currentAXAnchorFrame(),
              var relativeFrame = relativeAXLayoutFrames[id] else { return }
        if id != layoutAnchorWindowID {
            relativeFrame.origin = CGPoint(
                x: frame.origin.x - anchorFrame.origin.x,
                y: frame.origin.y - anchorFrame.origin.y
            )
        }
        relativeFrame.size = frame.size
        relativeAXLayoutFrames[id] = relativeFrame
    }

    private func updateSourceScriptLayoutFrame(index: Int, frame: CGRect) {
        guard groupingMode == .layout,
              let anchorFrame = currentScriptAnchorFrame(),
              var relativeFrame = relativeScriptLayoutFrames[index] else { return }
        if index != layoutAnchorScriptIndex {
            relativeFrame.origin = CGPoint(
                x: frame.origin.x - anchorFrame.origin.x,
                y: frame.origin.y - anchorFrame.origin.y
            )
        }
        relativeFrame.size = frame.size
        relativeScriptLayoutFrames[index] = relativeFrame
    }

    private func targetAXFrame(for id: UInt, sourceID: UInt?, sourceFrame: CGRect) -> CGRect {
        if groupingMode == .stack {
            return sourceFrame
        }

        guard groupingMode == .layout,
              let sourceID,
              let sourceRelativeFrame = relativeAXLayoutFrames[sourceID],
              let targetRelativeFrame = relativeAXLayoutFrames[id] else {
            return sourceFrame
        }

        let anchorOrigin = CGPoint(
            x: sourceFrame.origin.x - sourceRelativeFrame.origin.x,
            y: sourceFrame.origin.y - sourceRelativeFrame.origin.y
        )
        return CGRect(
            x: anchorOrigin.x + targetRelativeFrame.origin.x,
            y: anchorOrigin.y + targetRelativeFrame.origin.y,
            width: targetRelativeFrame.width,
            height: targetRelativeFrame.height
        )
    }

    private func targetScriptFrame(for state: ScriptWindowState, sourceIndex: Int, sourceFrame: CGRect) -> CGRect {
        if groupingMode == .stack {
            return sourceFrame
        }

        guard groupingMode == .layout,
              let sourceRelativeFrame = relativeScriptLayoutFrames[sourceIndex],
              let targetRelativeFrame = relativeScriptLayoutFrames[state.index] else {
            return sourceFrame
        }

        let anchorOrigin = CGPoint(
            x: sourceFrame.origin.x - sourceRelativeFrame.origin.x,
            y: sourceFrame.origin.y - sourceRelativeFrame.origin.y
        )
        return CGRect(
            x: anchorOrigin.x + targetRelativeFrame.origin.x,
            y: anchorOrigin.y + targetRelativeFrame.origin.y,
            width: targetRelativeFrame.width,
            height: targetRelativeFrame.height
        )
    }

    private func normalizeScriptLayoutAroundAnchor(using anchorFrame: CGRect) {
        guard groupingMode == .layout,
              let anchorIndex = layoutAnchorScriptIndex else { return }
        for state in groupedScriptIndices where state != anchorIndex {
            let targetFrame = targetScriptFrame(
                for: ScriptWindowState(index: state, title: "", frame: .zero),
                sourceIndex: anchorIndex,
                sourceFrame: anchorFrame
            )
            _ = WindowScriptBridge.setFrame(targetFrame, forWindowIndex: state, processIdentifier: appPID)
        }
    }

    private func currentAXAnchorFrame() -> CGRect? {
        guard let anchorID = layoutAnchorWindowID,
              let anchorWindow = groupedWindows.first(where: { $0.id == anchorID })?.window,
              let position = anchorWindow.position,
              let size = anchorWindow.size else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    private func currentScriptAnchorFrame() -> CGRect? {
        guard let anchorIndex = layoutAnchorScriptIndex else { return nil }
        return WindowScriptBridge.fetchWindows(
            forProcessIdentifier: appPID,
            windowIndices: [anchorIndex]
        ).first?.frame
    }

    private func reconcileAXWindows() {
        guard !groupedWindows.isEmpty else { return }
        let remainingWindows = groupedWindows.filter { window in
            guard let axWindow = window.window else { return false }
            return axWindow.position != nil && axWindow.size != nil
        }
        guard remainingWindows.count != groupedWindows.count else { return }
        applyGroupedWindowChange(remainingWindows)
    }

    private func reconcileScriptWindows(with currentStates: [ScriptWindowState]) {
        guard !groupedWindows.isEmpty, scriptAppName != nil else { return }
        let stateLookup = Dictionary(uniqueKeysWithValues: currentStates.map { ($0.index, $0) })
        let remainingWindows = groupedWindows.compactMap { window -> WindowChoice? in
            guard let scriptIndex = window.scriptIndex,
                  let state = stateLookup[scriptIndex] else { return nil }
            return WindowChoice(
                id: window.id,
                title: state.title.isEmpty ? window.title : state.title,
                window: nil,
                scriptIndex: scriptIndex
            )
        }
        guard remainingWindows.count != groupedWindows.count else { return }
        applyGroupedWindowChange(remainingWindows)
    }

    private func applyGroupedWindowChange(_ remainingWindows: [WindowChoice]) {
        groupedWindows = remainingWindows
        groupedTitles = remainingWindows.map(\.title)
        groupedScriptIndices = remainingWindows.compactMap(\.scriptIndex)
        if let selectedWindowID, !remainingWindows.contains(where: { $0.id == selectedWindowID }) {
            self.selectedWindowID = remainingWindows.first?.id
        }
        if let layoutAnchorWindowID, !remainingWindows.contains(where: { $0.id == layoutAnchorWindowID }) {
            self.layoutAnchorWindowID = remainingWindows.first?.id
            self.layoutAnchorScriptIndex = remainingWindows.first?.scriptIndex
        }
        onGroupedWindowsChanged?(remainingWindows)
    }

    func overlayItems(
        windowOrder: [UInt],
        titles: [String],
        accents: [UInt: StackPillAccent]
    ) -> [StackOverlayItem] {
        let highlightedID = selectedWindowID ?? windowOrder.first
        return zip(Array(windowOrder.enumerated()), titles).map { pair, title in
            let (index, id) = pair
            return StackOverlayItem(
                id: id,
                title: title,
                subtitle: nil,
                label: "\(index + 1)",
                accent: accents[id] ?? .blue,
                isSelected: id == highlightedID,
                windowState: overlayWindowState(for: id)
            )
        }
    }

    private func overlayWindowState(for id: UInt) -> StackOverlayItem.WindowState {
        guard let window = groupedWindows.first(where: { $0.id == id })?.window else {
            return .normal
        }

        if window.isMinimized {
            return .minimized
        }
        if window.isFullscreen {
            return .fullscreen
        }
        return .normal
    }

    func overlayAnchorFrame() -> CGRect? {
        let activeID = preferredAnchorWindowID()

        if let activeID,
           let activeWindow = groupedWindows.first(where: { $0.id == activeID })?.window,
           let position = activeWindow.position,
           let size = activeWindow.size {
            return CGRect(origin: position, size: size)
        }

        if let activeID,
           scriptAppName != nil,
           let scriptIndex = groupedWindows.first(where: { $0.id == activeID })?.scriptIndex,
           let state = WindowScriptBridge.fetchWindows(forProcessIdentifier: appPID, windowIndices: [scriptIndex]).first {
            return state.frame
        }

        return nil
    }

    func overlayAttachmentState() -> StackOverlayAttachmentState {
        guard AXIsProcessTrusted() else {
            return .permissionBlocked
        }

        if isTargetApplicationHidden() {
            return .hidden
        }

        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == appPID else {
            return .hidden
        }

        guard let activeID = focusedStackWindowIDForOverlay() else {
            return .hidden
        }

        if let activeWindow = groupedWindows.first(where: { $0.id == activeID })?.window {
            if activeWindow.isMinimized || activeWindow.isFullscreen {
                return .minimizedOrFullscreen
            }

            guard let position = activeWindow.position,
                  let size = activeWindow.size,
                  size.width > 0,
                  size.height > 0 else {
                return .missingAnchor
            }

            return .visible(anchorFrame: CGRect(origin: position, size: size))
        }

        if scriptAppName != nil,
           let scriptIndex = groupedWindows.first(where: { $0.id == activeID })?.scriptIndex,
           let state = WindowScriptBridge.fetchWindows(forProcessIdentifier: appPID, windowIndices: [scriptIndex]).first {
            guard state.frame.width > 0, state.frame.height > 0 else {
                return .missingAnchor
            }
            return .visible(anchorFrame: state.frame)
        }

        return .missingAnchor
    }

    private func focusedStackWindowIDForOverlay() -> UInt? {
        if !groupedWindows.isEmpty {
            let systemWideElement = AXUIElementCreateSystemWide()
            var value: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedWindowAttribute as CFString, &value)
            if result == .success,
               let focusedWindow = AXUIElement.from(value) {
                if let match = groupedWindowID(matching: focusedWindow) {
                    selectedWindowID = match
                    return match
                }
                return nil
            }

            if appPID != 0 {
                let appElement = AXUIElementCreateApplication(appPID)
                var mainWindowValue: CFTypeRef?
                let mainWindowResult = AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &mainWindowValue)
                if mainWindowResult == .success,
                   let mainWindow = AXUIElement.from(mainWindowValue) {
                    if let match = groupedWindowID(matching: mainWindow) {
                        selectedWindowID = match
                        return match
                    }
                    return nil
                }
            }
        }

        guard scriptAppName != nil,
              let mainIndex = WindowScriptBridge.mainWindowIndex(forProcessIdentifier: appPID),
              let match = groupedWindows.first(where: { $0.scriptIndex == mainIndex }) else {
            return nil
        }
        selectedWindowID = match.id
        return match.id
    }

    private func groupedWindowID(matching axWindow: AXUIElement) -> UInt? {
        groupedWindows.first { choice in
            guard let window = choice.window else { return false }
            return CFHash(window) == CFHash(axWindow)
        }?.id
    }

    private func preferredAnchorWindowID() -> UInt? {
        let focusedID = currentFocusedWindowID()
        if let focusedID,
           let window = groupedWindows.first(where: { $0.id == focusedID })?.window,
           !window.isMinimized,
           !window.isFullscreen {
            return focusedID
        }

        if let focusedID,
           groupedWindows.first(where: { $0.id == focusedID })?.window?.isFullscreen == true {
            return focusedID
        }

        if !groupedWindows.isEmpty,
           let visibleChoice = groupedWindows.first(where: { choice in
               guard let window = choice.window else { return false }
               return !window.isMinimized && !window.isFullscreen
           }) {
            return visibleChoice.id
        }

        if let focusedID {
            return focusedID
        }

        return groupedWindows.first?.id
    }

    private func isTargetApplicationHidden() -> Bool {
        guard appPID != 0,
              let runningApplication = NSRunningApplication(processIdentifier: appPID) else {
            return false
        }
        return runningApplication.isHidden
    }

    func groupedWindowChoices(in order: [UInt]? = nil) -> [WindowChoice] {
        guard let order else { return groupedWindows }
        return order.compactMap { id in
            groupedWindows.first(where: { $0.id == id })
        }
    }

    @discardableResult
    func regroupWindows(in order: [UInt]) -> Bool {
        guard let appName = groupedAppName else { return false }
        let windows = groupedWindowChoices(in: order)
        guard windows.count >= 2 else { return false }
        return startGrouping(windows, pid: appPID, appName: appName)
    }

    func separateWindow(withID id: UInt) {
        guard let window = groupedWindows.first(where: { $0.id == id }) else { return }

        if let axWindow = window.window,
           let position = axWindow.position,
           let size = axWindow.size {
            let newPosition = CGPoint(x: position.x + 56, y: position.y - 56)
            axWindow.set(position: newPosition)
            axWindow.set(size: size)
            return
        }

        if let scriptIndex = window.scriptIndex,
           scriptAppName != nil,
           let state = WindowScriptBridge.fetchWindows(forProcessIdentifier: appPID, windowIndices: [scriptIndex]).first {
            let newFrame = CGRect(
                x: state.frame.origin.x + 56,
                y: state.frame.origin.y - 56,
                width: state.frame.size.width,
                height: state.frame.size.height
            )
            _ = WindowScriptBridge.setFrame(newFrame, forWindowIndex: scriptIndex, processIdentifier: appPID)
        }
    }

    func focusWindow(withID id: UInt) {
        selectedWindowID = id

        if let axWindow = groupedWindows.first(where: { $0.id == id })?.window {
            if axWindow.isMinimized {
                _ = axWindow.setMinimized(false)
            }
            _ = AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
            if appPID != 0 {
                NSRunningApplication(processIdentifier: appPID)?.activate(options: [.activateAllWindows])
            }
            return
        }

        guard scriptAppName != nil,
              let scriptIndex = groupedWindows.first(where: { $0.id == id })?.scriptIndex else { return }
        _ = WindowScriptBridge.setMinimized(false, forWindowIndex: scriptIndex, processIdentifier: appPID)
        WindowScriptBridge.focusWindow(scriptIndex, processIdentifier: appPID)
    }

    func focusWindowChoice(_ window: WindowChoice) {
        selectedWindowID = window.id

        if let axWindow = window.window {
            if axWindow.isMinimized {
                _ = axWindow.setMinimized(false)
            }
            _ = AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
            if appPID != 0 {
                NSRunningApplication(processIdentifier: appPID)?.activate(options: [.activateAllWindows])
            }
            return
        }

        guard scriptAppName != nil,
              let scriptIndex = window.scriptIndex else { return }
        _ = WindowScriptBridge.setMinimized(false, forWindowIndex: scriptIndex, processIdentifier: appPID)
        WindowScriptBridge.focusWindow(scriptIndex, processIdentifier: appPID)
    }

    func minimizeWindow(id: UInt) {
        if let axWindow = groupedWindows.first(where: { $0.id == id })?.window {
            _ = axWindow.setMinimized(true)
            if selectedWindowID == id {
                selectedWindowID = preferredAnchorWindowID()
            }
            onGroupedWindowsChanged?(groupedWindows)
            return
        }

        guard scriptAppName != nil,
              let scriptIndex = groupedWindows.first(where: { $0.id == id })?.scriptIndex else { return }
        _ = WindowScriptBridge.setMinimized(true, forWindowIndex: scriptIndex, processIdentifier: appPID)
        if selectedWindowID == id {
            selectedWindowID = preferredAnchorWindowID()
        }
        onGroupedWindowsChanged?(groupedWindows)
    }

    func restoreWindow(id: UInt) {
        if let axWindow = groupedWindows.first(where: { $0.id == id })?.window {
            _ = axWindow.setMinimized(false)
            selectedWindowID = id
            _ = AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
            if appPID != 0 {
                NSRunningApplication(processIdentifier: appPID)?.activate(options: [.activateAllWindows])
            }
            onGroupedWindowsChanged?(groupedWindows)
            return
        }

        guard scriptAppName != nil,
              let scriptIndex = groupedWindows.first(where: { $0.id == id })?.scriptIndex else { return }
        _ = WindowScriptBridge.setMinimized(false, forWindowIndex: scriptIndex, processIdentifier: appPID)
        selectedWindowID = id
        WindowScriptBridge.focusWindow(scriptIndex, processIdentifier: appPID)
        onGroupedWindowsChanged?(groupedWindows)
    }

    func bringStackToFront(windowOrder: [UInt]) {
        if appPID != 0 {
            NSRunningApplication(processIdentifier: appPID)?.activate(options: [.activateAllWindows])
        }

        if !groupedWindows.isEmpty {
            let orderedWindows = windowOrder.compactMap { id in
                groupedWindows.first(where: { $0.id == id })?.window
            }

            for window in orderedWindows.reversed() {
                _ = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            }
            return
        }

        guard scriptAppName != nil else { return }
        for id in windowOrder.reversed() {
            guard let scriptIndex = groupedWindows.first(where: { $0.id == id })?.scriptIndex else { continue }
            WindowScriptBridge.focusWindow(scriptIndex, processIdentifier: appPID)
        }
    }

    func currentFocusedWindowID() -> UInt? {
        if !groupedWindows.isEmpty {
            let systemWideElement = AXUIElementCreateSystemWide()
            var value: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedWindowAttribute as CFString, &value)
            if result == .success,
               let axWindow = AXUIElement.from(value) {
                if let match = groupedWindows.first(where: { choice in
                    guard let window = choice.window else { return false }
                    return CFHash(window) == CFHash(axWindow)
                }) {
                    selectedWindowID = match.id
                    return match.id
                }
            }

            if appPID != 0 {
                let appElement = AXUIElementCreateApplication(appPID)
                var mainWindowValue: CFTypeRef?
                let mainWindowResult = AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &mainWindowValue)
                if mainWindowResult == .success,
                   let axWindow = AXUIElement.from(mainWindowValue) {
                    if let match = groupedWindows.first(where: { choice in
                        guard let window = choice.window else { return false }
                        return CFHash(window) == CFHash(axWindow)
                    }) {
                        selectedWindowID = match.id
                        return match.id
                    }
                }
            }
        }

        guard scriptAppName != nil,
              let mainIndex = WindowScriptBridge.mainWindowIndex(forProcessIdentifier: appPID),
              let match = groupedWindows.first(where: { $0.scriptIndex == mainIndex }) else {
            return nil
        }
        selectedWindowID = match.id
        return match.id
    }
}

private extension WindowStackController.GroupingMode {
    var debugName: String {
        switch self {
        case .stack:
            return "stack"
        case .layout:
            return "layout"
        }
    }
}
