import Foundation

enum MainWindowViewActions {
    static func refreshApplications() {
        NotificationCenter.default.post(name: .stackerRefreshApplications, object: nil)
    }

    static func readSelectedWindows() {
        NotificationCenter.default.post(name: .stackerReadSelectedWindows, object: nil)
    }

    static func selectApplication(_ pid: Int32, focusStack: Bool) {
        NotificationCenter.default.post(
            name: .stackerSelectTargetApplication,
            object: nil,
            userInfo: ["pid": pid]
        )

        if focusStack {
            focusApplicationStack(pid)
        }
    }

    static func autoStackApplication(_ pid: Int32) {
        NotificationCenter.default.post(
            name: .stackerAutoStackApplication,
            object: nil,
            userInfo: ["pid": pid]
        )
    }

    static func resetApplicationStack(_ pid: Int32) {
        NotificationCenter.default.post(
            name: .stackerResetApplicationStack,
            object: nil,
            userInfo: ["pid": pid]
        )
    }

    static func focusApplicationStack(_ pid: Int32) {
        NotificationCenter.default.post(
            name: .stackerFocusApplicationStack,
            object: nil,
            userInfo: ["pid": pid]
        )
    }

    static func addWindowToStack(pid: Int32, windowID: Int) {
        NotificationCenter.default.post(
            name: .stackerAddWindowToStack,
            object: nil,
            userInfo: ["pid": pid, "windowID": windowID]
        )
    }

    static func moveWindowInStack(pid: Int32, windowID: Int, direction: Int) {
        NotificationCenter.default.post(
            name: .stackerMoveWindowInStack,
            object: nil,
            userInfo: ["pid": pid, "windowID": windowID, "direction": direction]
        )
    }

    static func reorderWindowsInStack(pid: Int32, windowIDs: [Int]) {
        NotificationCenter.default.post(
            name: .stackerReorderWindowsInStack,
            object: nil,
            userInfo: ["pid": pid, "windowIDs": windowIDs]
        )
    }

    static func removeWindowFromStack(pid: Int32, windowID: Int) {
        NotificationCenter.default.post(
            name: .stackerRemoveWindowFromStack,
            object: nil,
            userInfo: ["pid": pid, "windowID": windowID]
        )
    }

    static func toggleApplicationOverlayVisibility(bundleIdentifier: String?, appName: String, pid: Int32) {
        NotificationCenter.default.post(
            name: .stackerToggleApplicationOverlayVisibility,
            object: nil,
            userInfo: [
                "bundleIdentifier": bundleIdentifier ?? "",
                "appName": appName,
                "pid": pid
            ]
        )
    }

    static func resetOverlayPosition(_ pid: Int32) {
        NotificationCenter.default.post(
            name: .stackerResetApplicationOverlayPosition,
            object: nil,
            userInfo: ["pid": pid]
        )
    }
}
