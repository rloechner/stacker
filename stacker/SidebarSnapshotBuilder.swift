import Foundation

struct SidebarSnapshotBuilder {
    func makeSnapshot(
        eligibleApplications: [TargetApplication],
        activeStackSessions: [ActiveStackSession],
        groupedTitles: [String],
        activeWindows: [WindowChoice],
        inactiveWindows: [WindowChoice],
        availableWindows: [WindowChoice],
        isSelectingWindows: Bool,
        targetPID: pid_t?,
        appName: String?,
        displayTitle: (UInt, [String], [UInt]) -> String
    ) -> SidebarSnapshot {
        SidebarSnapshot(
            apps: eligibleApplications.map {
                SidebarAppSnapshot(
                    name: $0.name,
                    bundleIdentifier: $0.bundleIdentifier,
                    processIdentifier: $0.processIdentifier,
                    windowCount: $0.windowCount,
                    widgetHidden: OverlayAppVisibilityPreference.isHidden(bundleIdentifier: $0.bundleIdentifier, appName: $0.name)
                )
            },
            activeStacks: activeStackSessions.map { session in
                let titles = session.windowOrder.map { id in
                    return displayTitle(id, session.windowTitles, session.windowOrder)
                }
                return SidebarActiveStackSnapshot(
                    appName: session.app.name,
                    bundleIdentifier: session.app.bundleIdentifier,
                    processIdentifier: session.app.processIdentifier,
                    titles: titles,
                    widgetHidden: OverlayAppVisibilityPreference.isHidden(bundleIdentifier: session.app.bundleIdentifier, appName: session.app.name),
                    overlayHealth: session.overlayHealth
                )
            },
            activeTitles: groupedTitles,
            activeWindows: activeWindows.map { window in
                SidebarWindowSnapshot(
                    id: window.id,
                    title: window.title
                )
            },
            inactiveWindows: inactiveWindows.map { window in
                SidebarWindowSnapshot(
                    id: window.id,
                    title: window.title
                )
            },
            availableWindowTitles: availableWindows.map(\.title),
            isSelectingWindows: isSelectingWindows,
            selectedPID: targetPID,
            selectedName: appName ?? ""
        )
    }
}
