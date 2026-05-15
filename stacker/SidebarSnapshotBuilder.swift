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
                let orderedWindows = session.controller.groupedWindowChoices(in: session.windowOrder)
                let titles = session.windowOrder.map { id in
                    return displayTitle(id, session.windowTitles, session.windowOrder)
                }
                return SidebarActiveStackSnapshot(
                    appName: session.app.name,
                    bundleIdentifier: session.app.bundleIdentifier,
                    processIdentifier: session.app.processIdentifier,
                    titles: titles,
                    activeWindows: orderedWindows.map { window in
                        SidebarWindowSnapshot(
                            id: window.id,
                            title: window.title,
                            accent: session.windowAccentStyles[window.id]
                        )
                    },
                    inactiveWindows: session.availableWindowChoices.map { window in
                        SidebarWindowSnapshot(
                            id: window.id,
                            title: window.title,
                            accent: nil
                        )
                    },
                    widgetHidden: OverlayAppVisibilityPreference.isHidden(bundleIdentifier: session.app.bundleIdentifier, appName: session.app.name),
                    overlayHealth: session.overlayHealth
                )
            },
            activeTitles: groupedTitles,
            activeWindows: activeWindows.map { window in
                SidebarWindowSnapshot(
                    id: window.id,
                    title: window.title,
                    accent: activeStackSessions
                        .first(where: { $0.windowIDs.contains(window.id) })?
                        .windowAccentStyles[window.id]
                )
            },
            inactiveWindows: inactiveWindows.map { window in
                SidebarWindowSnapshot(
                    id: window.id,
                    title: window.title,
                    accent: nil
                )
            },
            availableWindowTitles: availableWindows.map(\.title),
            isSelectingWindows: isSelectingWindows,
            selectedPID: targetPID,
            selectedName: appName ?? ""
        )
    }
}
