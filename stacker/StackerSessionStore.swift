import Darwin
import Observation

@MainActor
@Observable
final class StackerSessionStore {
    var groupedTitles: [String] = []
    var activeWindowIDs: Set<UInt> = []
    var activeWindowOrder: [UInt] = []
    var activeStackSessions: [ActiveStackSession] = []

    func currentStackSession(for targetPID: pid_t?) -> ActiveStackSession? {
        guard let targetPID else { return nil }
        return activeStackSessions.first(where: { $0.app.processIdentifier == targetPID })
    }

    func activeWindows(from availableWindows: [WindowChoice]) -> [WindowChoice] {
        availableWindows.filter { activeWindowIDs.contains($0.id) }
    }

    func inactiveWindows(from availableWindows: [WindowChoice]) -> [WindowChoice] {
        availableWindows.filter { !activeWindowIDs.contains($0.id) }
    }

    func syncSelectionState(availableWindows: inout [WindowChoice]) {
        for index in availableWindows.indices {
            availableWindows[index].isSelected = activeWindowIDs.contains(availableWindows[index].id)
        }
    }

    func store(
        _ session: ActiveStackSession,
        availableWindows: inout [WindowChoice],
        refreshOverlay: (ActiveStackSession) -> Void
    ) {
        if let index = activeStackSessions.firstIndex(where: { $0.app.processIdentifier == session.app.processIdentifier }) {
            activeStackSessions[index].controller.stopGrouping()
            activeStackSessions[index].overlayController.close()
            activeStackSessions[index] = session
        } else {
            activeStackSessions.append(session)
        }

        groupedTitles = session.windowTitles
        activeWindowIDs = session.windowIDs
        activeWindowOrder = session.windowOrder
        syncSelectionState(availableWindows: &availableWindows)
        refreshOverlay(session)
    }

    @discardableResult
    func removeSession(
        for pid: pid_t,
        targetPID: pid_t?,
        availableWindows: inout [WindowChoice]
    ) -> Bool {
        if let index = activeStackSessions.firstIndex(where: { $0.app.processIdentifier == pid }) {
            activeStackSessions[index].controller.stopGrouping(separateWindows: true)
            activeStackSessions[index].overlayController.close()
            activeStackSessions.remove(at: index)
        }

        guard targetPID == pid else { return false }

        groupedTitles = []
        activeWindowIDs = []
        activeWindowOrder = []
        syncSelectionState(availableWindows: &availableWindows)
        return true
    }

    func syncCurrentStackState(targetPID: pid_t?, availableWindows: inout [WindowChoice]) {
        if let currentStackSession = currentStackSession(for: targetPID) {
            groupedTitles = currentStackSession.windowTitles
            activeWindowIDs = currentStackSession.windowIDs
            activeWindowOrder = currentStackSession.windowOrder
        } else {
            groupedTitles = []
            activeWindowIDs = []
            activeWindowOrder = []
        }

        syncSelectionState(availableWindows: &availableWindows)
    }
}
