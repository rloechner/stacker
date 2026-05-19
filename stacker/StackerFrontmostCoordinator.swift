import AppKit

@MainActor
final class StackerFrontmostCoordinator {
    func updateTrackedApplication(
        app: NSRunningApplication?,
        workspaceController: StackerWorkspaceController,
        activeStackSessions: [ActiveStackSession],
        selectedTargetPID: pid_t?,
        groupedTitles: [String],
        isSelectingWindows: Bool,
        postFrontmostNotification: (NSRunningApplication?) -> Void,
        syncCombineOverlay: @escaping () -> Void,
        loadEligibleApplications: @escaping () async -> Void,
        refreshOverlay: @escaping (ActiveStackSession) -> Void,
        selectOverlayWindow: @escaping (ActiveStackSession, UInt) -> Void,
        setSelectedTargetPID: @escaping (pid_t?) -> Void,
        setTargetApplication: @escaping (TargetApplication?) -> Void,
        setAppName: @escaping (String?) -> Void,
        setTargetPID: @escaping (pid_t?) -> Void,
        syncCurrentStackState: @escaping () -> Void,
        eligibleApplicationsProvider: @escaping () -> [TargetApplication]
    ) {
        postFrontmostNotification(app)
        workspaceController.updateTrackedApplication(from: app, activeStackSessions: activeStackSessions)
        syncCombineOverlay()

        guard let app, workspaceController.isEligibleTargetApp(app) else { return }
        let appPID = app.processIdentifier

        // Always refresh the window list for the current frontmost eligible browser.
        // This gives the user a live view in the admin without ever clicking Refresh.
        Task { @MainActor in
            await loadEligibleApplications()

            if let session = activeStackSessions.first(where: { $0.app.processIdentifier == appPID }) {
                refreshOverlay(session)
                if let selectedWindowID = session.controller.currentFocusedWindowID() ?? session.windowOrder.first {
                    selectOverlayWindow(session, selectedWindowID)
                }
            }

            // When an eligible browser becomes frontmost, auto-select it in the admin
            // so the window list refreshes automatically (user request).
            if let matchingApp = eligibleApplicationsProvider().first(where: { $0.processIdentifier == appPID }) {
                setSelectedTargetPID(matchingApp.processIdentifier)
                setTargetApplication(matchingApp)
                setAppName(matchingApp.name)
                setTargetPID(matchingApp.processIdentifier)
                syncCurrentStackState()

                // Explicitly refresh the window list for the newly frontmost browser
                // so the admin always shows current windows without the user clicking Refresh.
                Task { @MainActor in
                    await loadEligibleApplications()
                    // loadFrontmostAppWindows will be triggered via onChange(selectedTargetPID)
                }
            } else if groupedTitles.isEmpty && !isSelectingWindows {
                setTargetApplication(nil)
                setAppName(nil)
                setTargetPID(nil)
            }

            syncCombineOverlay()
        }
    }

    func syncCombineOverlay(
        frontmostApp: NSRunningApplication?,
        frontmostEligiblePID: pid_t?,
        eligibleApplications: [TargetApplication],
        activeStackSessions: [ActiveStackSession],
        combineOverlayController: CombineOverlayPanelController,
        showAddBackOverlay: (ActiveStackSession) -> Void,
        frontmostEligibleWindowFrame: @escaping () -> CGRect?,
        triggerCombine: @escaping (pid_t) -> Void
    ) {
        if let frontmostApp,
           let activeSession = activeStackSessions.first(where: { $0.app.processIdentifier == frontmostApp.processIdentifier }),
           !activeSession.availableWindowChoices.isEmpty {
            showAddBackOverlay(activeSession)
            return
        }

        if let frontmostApp,
           activeStackSessions.contains(where: { $0.app.processIdentifier == frontmostApp.processIdentifier }) {
            combineOverlayController.clear()
            return
        }

        guard let pid = frontmostEligiblePID,
              let app = eligibleApplications.first(where: { $0.processIdentifier == pid }),
              !activeStackSessions.contains(where: { $0.app.processIdentifier == pid }) else {
            combineOverlayController.clear()
            return
        }

        combineOverlayController.update(
            appPID: pid,
            appBundleIdentifier: app.bundleIdentifier,
            appName: app.name,
            style: .createStack(windowCount: app.windowCount),
            frameProvider: {
                frontmostEligibleWindowFrame()
            }
        ) {
            triggerCombine(pid)
        }
    }
}
