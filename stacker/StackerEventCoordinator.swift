import AppKit
import Foundation

@MainActor
struct StackerSidebarEventHandlers {
    let onSelectTargetApplication: (pid_t) -> Void
    let onAutoStackApplication: (pid_t) -> Void
    let onRefreshApplications: () -> Void
    let onReadSelectedWindows: () -> Void
    let onResetSelectedStack: () -> Void
    let onResetApplicationStack: (pid_t) -> Void
    let onToggleApplicationOverlayVisibility: (_ bundleIdentifier: String?, _ appName: String) -> Void
    let onMoveWindowInStack: (_ pid: pid_t, _ windowID: UInt, _ direction: Int) -> Void
    let onReorderWindowsInStack: (_ pid: pid_t, _ windowIDs: [UInt]) -> Void
    let onAddWindowToStack: (_ pid: pid_t, _ windowID: UInt) -> Void
    let onRemoveWindowFromStack: (_ pid: pid_t, _ windowID: UInt) -> Void
    let onFocusApplicationStack: (pid_t) -> Void
    let onResetApplicationOverlayPosition: (pid_t) -> Void
}

@MainActor
final class StackerEventCoordinator {
    private var activationObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var sidebarObservers: [NSObjectProtocol] = []

    func startTrackingActiveApplications(onUpdate: @escaping (NSRunningApplication?) -> Void) {
        onUpdate(NSWorkspace.shared.frontmostApplication)

        guard activationObserver == nil else { return }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            onUpdate(app)
        }
    }

    func stopTrackingActiveApplications() {
        guard let activationObserver else { return }
        NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        self.activationObserver = nil
    }

    func startTrackingSystemWake(onWake: @escaping () -> Void) {
        guard wakeObserver == nil else { return }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            onWake()
        }
    }

    func stopTrackingSystemWake() {
        guard let wakeObserver else { return }
        NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        self.wakeObserver = nil
    }

    func startSidebarObservers(handlers: StackerSidebarEventHandlers) {
        guard sidebarObservers.isEmpty else { return }

        sidebarObservers = [
            observe(.stackerSelectTargetApplication) { notification in
                guard let pid = notification.userInfo?["pid"] as? Int32 else { return }
                handlers.onSelectTargetApplication(pid)
            },
            observe(.stackerAutoStackApplication) { notification in
                guard let pid = notification.userInfo?["pid"] as? Int32 else { return }
                handlers.onAutoStackApplication(pid)
            },
            observe(.stackerRefreshApplications) { _ in
                handlers.onRefreshApplications()
            },
            observe(.stackerReadSelectedWindows) { _ in
                handlers.onReadSelectedWindows()
            },
            observe(.stackerResetSelectedStack) { _ in
                handlers.onResetSelectedStack()
            },
            observe(.stackerResetApplicationStack) { notification in
                guard let pid = notification.userInfo?["pid"] as? Int32 else { return }
                handlers.onResetApplicationStack(pid)
            },
            observe(.stackerToggleApplicationOverlayVisibility) { notification in
                let bundleIdentifier = notification.userInfo?["bundleIdentifier"] as? String
                let appName = notification.userInfo?["appName"] as? String ?? ""
                handlers.onToggleApplicationOverlayVisibility(bundleIdentifier, appName)
            },
            observe(.stackerMoveWindowInStack) { notification in
                guard let pid = notification.userInfo?["pid"] as? Int32,
                      let windowID = notification.userInfo?["windowID"] as? Int,
                      let direction = notification.userInfo?["direction"] as? Int else { return }
                handlers.onMoveWindowInStack(pid, UInt(windowID), direction)
            },
            observe(.stackerReorderWindowsInStack) { notification in
                guard let pid = notification.userInfo?["pid"] as? Int32,
                      let windowIDs = notification.userInfo?["windowIDs"] as? [Int] else { return }
                handlers.onReorderWindowsInStack(pid, windowIDs.map(UInt.init))
            },
            observe(.stackerAddWindowToStack) { notification in
                guard let pid = notification.userInfo?["pid"] as? Int32,
                      let windowID = notification.userInfo?["windowID"] as? Int else { return }
                handlers.onAddWindowToStack(pid, UInt(windowID))
            },
            observe(.stackerRemoveWindowFromStack) { notification in
                guard let pid = notification.userInfo?["pid"] as? Int32,
                      let windowID = notification.userInfo?["windowID"] as? Int else { return }
                handlers.onRemoveWindowFromStack(pid, UInt(windowID))
            },
            observe(.stackerFocusApplicationStack) { notification in
                guard let pid = notification.userInfo?["pid"] as? Int32 else { return }
                handlers.onFocusApplicationStack(pid)
            },
            observe(.stackerResetApplicationOverlayPosition) { notification in
                guard let pid = notification.userInfo?["pid"] as? Int32 else { return }
                handlers.onResetApplicationOverlayPosition(pid)
            }
        ]
    }

    func stopSidebarObservers() {
        sidebarObservers.forEach(NotificationCenter.default.removeObserver)
        sidebarObservers.removeAll()
    }

    private func observe(_ name: Notification.Name, using handler: @escaping @MainActor (Notification) -> Void) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(
            forName: name,
            object: nil,
            queue: .main,
            using: { notification in
                MainActor.assumeIsolated {
                    handler(notification)
                }
            }
        )
    }
}
