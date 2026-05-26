import AppKit

struct StackOverlayCoordinatorHandlers {
    let onSelect: (UInt) -> Void
    let onDisplayModeChanged: (StackOverlayDisplayMode) -> Void
    let onLabelModeChanged: (StackOverlayLabelMode) -> Void
    let onDensityModeChanged: (StackOverlayDensityMode) -> Void
    let onPlacementPreferenceChanged: (StackOverlayPlacementPreference) -> Void
    let onDockPositionChanged: (StackOverlayDockPosition) -> Void
    let onAddWindow: (UInt) -> Void
    let onOpenEditor: () -> Void
    let onHideWidget: () -> Void
    let onFocusStack: () -> Void
    let onTurnOff: () -> Void
    let onMove: (UInt, Int) -> Void
    let onReorder: (UInt, UInt) -> Void
    let onMinimize: (UInt) -> Void
    let onRestore: (UInt) -> Void
    let onRemove: (UInt) -> Void
}

@MainActor
final class StackRuntimeCoordinator {
    func makeStackController(
        onError: @escaping (String) -> Void,
        onDebug: @escaping (String) -> Void
    ) -> WindowStackController {
        let controller = WindowStackController()
        controller.onError = { message in
            DispatchQueue.main.async {
                onError(message)
            }
        }
        controller.onDebug = { message in
            DispatchQueue.main.async {
                onDebug(message)
            }
        }
        return controller
    }

    func buildSession(
        targetPID: pid_t,
        targetApplication: TargetApplication,
        appName: String,
        windows: [WindowChoice],
        existingSession: ActiveStackSession?,
        availableWindows: [WindowChoice],
        onError: @escaping (String) -> Void,
        onDebug: @escaping (String) -> Void,
        overlayHandlers: StackOverlayCoordinatorHandlers
    ) -> ActiveStackSession? {
        OverlayAppVisibilityPreference.setHidden(false, bundleIdentifier: targetApplication.bundleIdentifier, appName: targetApplication.name)

        let controller = makeStackController(onError: onError, onDebug: onDebug)
        guard controller.startGrouping(windows, pid: targetPID, appName: appName) else {
            return nil
        }

        let savedDockPosition = StackOverlayDockPositionPreference.current(
            bundleIdentifier: targetApplication.bundleIdentifier,
            appName: targetApplication.name
        )
        let initialDockPosition = existingSession?.overlayDockPosition ?? savedDockPosition ?? .left
        let initialPlacementPreference = existingSession?.overlayPlacementPreference
            ?? StackOverlayPlacementPreference(dockPosition: initialDockPosition)

        let activeWindowIDs = Set(windows.map(\.id))
        let activeWindowOrder = windows.map(\.id)
        let groupedTitles = controller.groupedTitles
        let overlayController = makeOverlayController(
            controller: controller,
            targetApplication: targetApplication,
            currentSession: existingSession,
            handlers: overlayHandlers,
            initialDockPosition: initialDockPosition
        )

        let defaultAccents = defaultAccentAssignments(for: windows, existingAccents: existingSession?.windowAccentStyles ?? [:])

        let session = ActiveStackSession(
            app: targetApplication,
            controller: controller,
            overlayController: overlayController,
            windowIDs: activeWindowIDs,
            windowOrder: activeWindowOrder,
            windowTitles: groupedTitles,
            availableWindowChoices: availableWindows.filter { !activeWindowIDs.contains($0.id) },
            windowAccentStyles: defaultAccents,
            overlayDisplayMode: existingSession?.overlayDisplayMode ?? .vertical,
            overlayLabelMode: existingSession?.overlayLabelMode ?? .names,
            overlayDensityMode: existingSession?.overlayDensityMode ?? .comfortable,
            overlayPlacementPreference: initialPlacementPreference,
            overlayDockPosition: existingSession?.overlayDockPosition ?? initialDockPosition
        )
        overlayController.onHealthChanged = { [weak session] health in
            session?.overlayHealth = health
        }
        return session
    }

    private func defaultAccentAssignments(
        for windows: [WindowChoice],
        existingAccents: [UInt: StackPillAccent]
    ) -> [UInt: StackPillAccent] {
        var assignments = existingAccents
        var nextIndex = 0
        let accentCycle = StackOverlayDotPalettePreference.current().accents

        for window in windows {
            if assignments[window.id] != nil {
                continue
            }
            assignments[window.id] = accentCycle[nextIndex % accentCycle.count]
            nextIndex += 1
        }

        return assignments
    }

    func applyCurrentDotPalette(to session: ActiveStackSession) {
        let accentCycle = StackOverlayDotPalettePreference.current().accents
        session.windowAccentStyles = Dictionary(
            uniqueKeysWithValues: session.windowOrder.enumerated().map { index, id in
                (id, accentCycle[index % accentCycle.count])
            }
        )
    }

    func applyCurrentAppearance(to session: ActiveStackSession) {
        session.overlayController.setCurrentAppearance(StackOverlayAppearancePreference.current())
    }

    func refreshOverlay(for session: ActiveStackSession) {
        applyCurrentDotPalette(to: session)
        let items = session.controller.overlayItems(
            windowOrder: session.windowOrder,
            titles: session.windowTitles,
            accents: session.windowAccentStyles
        )
        let addableWindows = session.availableWindowChoices.enumerated().map { offset, window in
            StackOverlayAddableWindow(
                id: window.id,
                title: window.title,
                label: "\(session.windowOrder.count + offset + 1)"
            )
        }
        session.overlayController.update(
            items: items,
            addableWindows: addableWindows,
            appearance: StackOverlayAppearancePreference.current(),
            displayMode: session.overlayDisplayMode,
            labelMode: session.overlayLabelMode,
            densityMode: session.overlayDensityMode,
            placementPreference: session.overlayPlacementPreference,
            dockPosition: session.overlayDockPosition
        )
        session.overlayController.startTracking { [weak controller = session.controller] in
            controller?.overlayAttachmentState() ?? .missingAnchor
        } selectedItemProvider: { [weak controller = session.controller] in
            controller?.currentFocusedWindowID()
        }
        session.overlayHealth = session.overlayController.currentHealth
    }

    func focusApplicationStack(
        session: ActiveStackSession,
        selectTargetPID: (pid_t) -> Void,
        setTargetApplication: (TargetApplication) -> Void,
        setAppName: (String) -> Void,
        setTargetPID: (pid_t) -> Void,
        syncCurrentStackState: () -> Void
    ) {
        selectTargetPID(session.app.processIdentifier)
        setTargetApplication(session.app)
        setAppName(session.app.name)
        setTargetPID(session.app.processIdentifier)
        syncCurrentStackState()

        session.controller.bringStackToFront(windowOrder: session.windowOrder)

        let targetWindowID = session.controller.currentFocusedWindowID() ?? session.windowOrder.first
        if let targetWindowID {
            session.controller.focusWindow(withID: targetWindowID)
            session.overlayController.selectWindow(targetWindowID)
        }
    }

    private func makeOverlayController(
        controller: WindowStackController,
        targetApplication: TargetApplication,
        currentSession: ActiveStackSession?,
        handlers: StackOverlayCoordinatorHandlers,
        initialDockPosition: StackOverlayDockPosition
    ) -> StackOverlayPanelController {
        var overlayController: StackOverlayPanelController?
        let sessionPID = targetApplication.processIdentifier
        let sessionAppName = targetApplication.name
        let displayMode = currentSession?.overlayDisplayMode ?? .vertical
        let labelMode = currentSession?.overlayLabelMode ?? .names
        let densityMode = currentSession?.overlayDensityMode ?? .comfortable
        let placementPreference = currentSession?.overlayPlacementPreference ?? StackOverlayPlacementPreference(dockPosition: initialDockPosition)
        let dockPosition = currentSession?.overlayDockPosition ?? initialDockPosition

        overlayController = StackOverlayPanelController(
            appPID: sessionPID,
            appBundleIdentifier: currentSession?.app.bundleIdentifier ?? targetApplication.bundleIdentifier,
            appName: sessionAppName,
            displayMode: displayMode,
            labelMode: labelMode,
            densityMode: densityMode,
            placementPreference: placementPreference,
            dockPosition: dockPosition,
            onSelect: { id in
                handlers.onSelect(id)
                overlayController?.selectWindow(id)
            },
            onDisplayModeChanged: handlers.onDisplayModeChanged,
            onLabelModeChanged: handlers.onLabelModeChanged,
            onDensityModeChanged: handlers.onDensityModeChanged,
            onPlacementPreferenceChanged: handlers.onPlacementPreferenceChanged,
            onDockPositionChanged: handlers.onDockPositionChanged,
            onAddWindow: handlers.onAddWindow,
            onOpenEditor: handlers.onOpenEditor,
            onHideWidget: handlers.onHideWidget,
            onResetPositionRequested: {},
            onFocusStack: handlers.onFocusStack,
            onTurnOff: handlers.onTurnOff,
            onMove: handlers.onMove,
            onReorder: handlers.onReorder,
            onMinimize: handlers.onMinimize,
            onRestore: handlers.onRestore,
            onRemove: handlers.onRemove
        )

        if currentSession == nil {
            // Force new stacks to start with left bias on top/bottom rails
            overlayController?.forceLeftBiasForTopDock()
        }

        return overlayController!
    }
}
