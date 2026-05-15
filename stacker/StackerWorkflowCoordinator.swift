import Foundation

@MainActor
final class StackerWorkflowCoordinator {
    func handleSelectedTargetChange(
        newValue: pid_t,
        eligibleApplications: [TargetApplication],
        pendingAutoStackPID: pid_t?,
        setTargetApplication: (TargetApplication) -> Void,
        setAppName: (String) -> Void,
        setTargetPID: (pid_t) -> Void,
        syncCurrentStackState: () -> Void,
        loadFrontmostAppWindows: @escaping () async -> Void,
        clearPendingAutoStackPID: @escaping () -> Void,
        autoStackLoadedWindows: @escaping () -> Void
    ) {
        guard let selectedApp = eligibleApplications.first(where: { $0.processIdentifier == newValue }) else { return }

        setTargetApplication(selectedApp)
        setAppName(selectedApp.name)
        setTargetPID(selectedApp.processIdentifier)
        syncCurrentStackState()

        Task { @MainActor in
            await loadFrontmostAppWindows()
            if pendingAutoStackPID == newValue {
                clearPendingAutoStackPID()
                autoStackLoadedWindows()
            }
        }
    }

    func autoStackLoadedWindows(
        availableWindows: inout [WindowChoice],
        setErrorMessage: (String) -> Void,
        startStack: ([WindowChoice]) -> Void
    ) {
        let windows = availableWindows
        guard windows.count >= 2 else {
            setErrorMessage("Open at least two readable Chrome profile windows before turning on profile switching.")
            return
        }

        for index in availableWindows.indices {
            availableWindows[index].isSelected = true
        }

        startStack(windows)
    }

    func triggerCombine(
        pid: pid_t,
        targetPID: pid_t?,
        setPendingAutoStackPID: (pid_t) -> Void,
        setSelectedTargetPID: (pid_t) -> Void,
        loadFrontmostAppWindows: @escaping () async -> Void,
        clearPendingAutoStackPID: @escaping () -> Void,
        autoStackLoadedWindows: @escaping () -> Void
    ) {
        setPendingAutoStackPID(pid)
        setSelectedTargetPID(pid)

        guard targetPID == pid else { return }

        Task { @MainActor in
            await loadFrontmostAppWindows()
            clearPendingAutoStackPID()
            autoStackLoadedWindows()
        }
    }
}
