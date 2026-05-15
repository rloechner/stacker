import AppKit
import Foundation

@MainActor
final class StackerSessionCoordinator {
    func moveWindowInSession(
        store: StackerSessionStore,
        targetPID: pid_t?,
        pid: pid_t,
        id: UInt,
        offset: Int,
        refreshOverlay: (ActiveStackSession) -> Void,
        syncSelectionState: () -> Void,
        postSidebarSnapshot: () -> Void,
        syncCombineOverlay: () -> Void
    ) {
        guard let session = store.activeStackSessions.first(where: { $0.app.processIdentifier == pid }),
              let currentIndex = session.windowOrder.firstIndex(of: id) else { return }

        let newIndex = currentIndex + offset
        guard session.windowOrder.indices.contains(newIndex) else { return }

        var reordered = session.windowOrder
        let movedID = reordered.remove(at: currentIndex)
        reordered.insert(movedID, at: newIndex)

        guard session.controller.regroupWindows(in: reordered) else { return }
        session.windowOrder = reordered
        session.windowIDs = Set(reordered)
        session.windowTitles = session.controller.groupedTitles
        refreshOverlay(session)

        if targetPID == pid {
            store.groupedTitles = session.windowTitles
            store.activeWindowIDs = session.windowIDs
            store.activeWindowOrder = session.windowOrder
            syncSelectionState()
        }

        postSidebarSnapshot()
        syncCombineOverlay()
    }

    func reorderWindowInSession(
        store: StackerSessionStore,
        targetPID: pid_t?,
        pid: pid_t,
        sourceID: UInt,
        targetWindowID: UInt,
        refreshOverlay: (ActiveStackSession) -> Void,
        syncSelectionState: () -> Void,
        postSidebarSnapshot: () -> Void,
        syncCombineOverlay: () -> Void
    ) {
        guard let session = store.activeStackSessions.first(where: { $0.app.processIdentifier == pid }),
              let sourceIndex = session.windowOrder.firstIndex(of: sourceID),
              let targetIndex = session.windowOrder.firstIndex(of: targetWindowID),
              sourceIndex != targetIndex else { return }

        var reordered = session.windowOrder
        let movedID = reordered.remove(at: sourceIndex)
        reordered.insert(movedID, at: targetIndex)

        guard session.controller.regroupWindows(in: reordered) else { return }
        session.windowOrder = reordered
        session.windowIDs = Set(reordered)
        session.windowTitles = session.controller.groupedTitles
        refreshOverlay(session)

        if targetPID == pid {
            store.groupedTitles = session.windowTitles
            store.activeWindowIDs = session.windowIDs
            store.activeWindowOrder = session.windowOrder
            syncSelectionState()
        }

        postSidebarSnapshot()
        syncCombineOverlay()
    }

    func reorderWindowsInSession(
        store: StackerSessionStore,
        targetPID: pid_t?,
        pid: pid_t,
        orderedIDs: [UInt],
        refreshOverlay: (ActiveStackSession) -> Void,
        syncSelectionState: () -> Void,
        postSidebarSnapshot: () -> Void,
        syncCombineOverlay: () -> Void
    ) {
        guard let session = store.activeStackSessions.first(where: { $0.app.processIdentifier == pid }) else { return }

        let currentIDs = Set(session.windowOrder)
        let requestedIDs = Set(orderedIDs)
        guard currentIDs == requestedIDs, orderedIDs != session.windowOrder else { return }

        guard session.controller.regroupWindows(in: orderedIDs) else { return }
        session.windowOrder = orderedIDs
        session.windowIDs = Set(orderedIDs)
        session.windowTitles = session.controller.groupedTitles
        refreshOverlay(session)

        if targetPID == pid {
            store.groupedTitles = session.windowTitles
            store.activeWindowIDs = session.windowIDs
            store.activeWindowOrder = session.windowOrder
            syncSelectionState()
        }

        postSidebarSnapshot()
        syncCombineOverlay()
    }

    func addWindowToSession(
        store: StackerSessionStore,
        targetPID: pid_t?,
        pid: pid_t,
        id: UInt,
        combineOverlayController: CombineOverlayPanelController,
        refreshOverlay: (ActiveStackSession) -> Void,
        syncSelectionState: () -> Void,
        postSidebarSnapshot: () -> Void,
        syncCombineOverlay: () -> Void
    ) {
        guard let session = store.activeStackSessions.first(where: { $0.app.processIdentifier == pid }),
              let addedWindow = session.availableWindowChoices.first(where: { $0.id == id }) else { return }

        combineOverlayController.clear()

        var windows = session.controller.groupedWindowChoices(in: session.windowOrder)
        windows.append(addedWindow)

        guard session.controller.startGrouping(windows, pid: session.app.processIdentifier, appName: session.app.name) else {
            return
        }

        session.windowOrder.append(id)
        session.windowIDs.insert(id)
        session.windowTitles = session.controller.groupedTitles
        session.availableWindowChoices.removeAll { $0.id == id }

        refreshOverlay(session)

        if targetPID == pid {
            store.groupedTitles = session.windowTitles
            store.activeWindowIDs = session.windowIDs
            store.activeWindowOrder = session.windowOrder
            syncSelectionState()
        }

        postSidebarSnapshot()
        syncCombineOverlay()
    }

    func removeWindowFromSession(
        store: StackerSessionStore,
        targetPID: pid_t?,
        pid: pid_t,
        id: UInt,
        removeStackSession: (pid_t) -> Void,
        refreshOverlay: (ActiveStackSession) -> Void,
        syncSelectionState: () -> Void,
        postSidebarSnapshot: () -> Void,
        syncCombineOverlay: () -> Void,
        showAddBackOverlay: (ActiveStackSession) -> Void
    ) {
        guard let session = store.activeStackSessions.first(where: { $0.app.processIdentifier == pid }) else { return }
        let removedChoice = session.controller.groupedWindowChoices(in: session.windowOrder).first(where: { $0.id == id })
        session.controller.separateWindow(withID: id)

        let remainingOrder = session.windowOrder.filter { $0 != id }
        if remainingOrder.count < 2 {
            removeStackSession(pid)
            return
        }

        guard session.controller.regroupWindows(in: remainingOrder) else { return }
        session.windowOrder = remainingOrder
        session.windowIDs = Set(remainingOrder)
        session.windowTitles = session.controller.groupedTitles
        if let removedChoice, !session.availableWindowChoices.contains(where: { $0.id == removedChoice.id }) {
            session.availableWindowChoices.append(removedChoice)
        }
        refreshOverlay(session)

        if targetPID == pid {
            store.groupedTitles = session.windowTitles
            store.activeWindowIDs = session.windowIDs
            store.activeWindowOrder = session.windowOrder
            syncSelectionState()
        }

        postSidebarSnapshot()
        if let removedChoice {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                session.controller.focusWindowChoice(removedChoice)
            }
        }
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
           removedChoice != nil,
           !session.availableWindowChoices.isEmpty {
            showAddBackOverlay(session)
        } else {
            syncCombineOverlay()
        }
    }

    func updateOverlayDisplayMode(
        store: StackerSessionStore,
        pid: pid_t,
        mode: StackOverlayDisplayMode,
        refreshOverlay: (ActiveStackSession) -> Void,
        postSidebarSnapshot: () -> Void
    ) {
        guard let session = store.activeStackSessions.first(where: { $0.app.processIdentifier == pid }) else { return }
        session.overlayDisplayMode = mode
        refreshOverlay(session)
        postSidebarSnapshot()
    }

    func updateOverlayLabelMode(
        store: StackerSessionStore,
        pid: pid_t,
        mode: StackOverlayLabelMode,
        refreshOverlay: (ActiveStackSession) -> Void,
        postSidebarSnapshot: () -> Void
    ) {
        guard let session = store.activeStackSessions.first(where: { $0.app.processIdentifier == pid }) else { return }
        session.overlayLabelMode = mode
        refreshOverlay(session)
        postSidebarSnapshot()
    }

    func updateOverlayDensityMode(
        store: StackerSessionStore,
        pid: pid_t,
        mode: StackOverlayDensityMode,
        refreshOverlay: (ActiveStackSession) -> Void,
        postSidebarSnapshot: () -> Void
    ) {
        guard let session = store.activeStackSessions.first(where: { $0.app.processIdentifier == pid }) else { return }
        session.overlayDensityMode = mode
        refreshOverlay(session)
        postSidebarSnapshot()
    }

    func updateOverlayPlacementPreference(
        store: StackerSessionStore,
        pid: pid_t,
        preference: StackOverlayPlacementPreference,
        refreshOverlay: (ActiveStackSession) -> Void,
        postSidebarSnapshot: () -> Void
    ) {
        guard let session = store.activeStackSessions.first(where: { $0.app.processIdentifier == pid }) else { return }
        session.overlayPlacementPreference = preference
        StackOverlayPlacementPreferenceStore.set(preference)
        if let dockPosition = preference.dockPosition {
            session.overlayDockPosition = dockPosition
        }
        refreshOverlay(session)
        postSidebarSnapshot()
    }

    func updateOverlayDockPosition(
        store: StackerSessionStore,
        pid: pid_t,
        position: StackOverlayDockPosition,
        refreshOverlay: (ActiveStackSession) -> Void,
        postSidebarSnapshot: () -> Void
    ) {
        guard let session = store.activeStackSessions.first(where: { $0.app.processIdentifier == pid }) else { return }
        session.overlayPlacementPreference = StackOverlayPlacementPreference(dockPosition: position)
        StackOverlayPlacementPreferenceStore.set(session.overlayPlacementPreference)
        session.overlayDockPosition = position
        refreshOverlay(session)
        postSidebarSnapshot()
    }
}
