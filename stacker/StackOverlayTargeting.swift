import ApplicationServices
import CoreGraphics

@MainActor
enum StackOverlayTargeting {
    static func focusedAddBackWindow(in session: ActiveStackSession) -> WindowChoice? {
        session.availableWindowChoices.first {
            focusedFrameForWindowChoice($0, appPID: session.app.processIdentifier, appName: session.app.name) != nil
        }
    }

    static func focusedFrameForWindowChoice(_ window: WindowChoice, appPID: pid_t, appName: String) -> CGRect? {
        if let axWindow = window.window,
           let focusedWindow = focusedAXWindow(for: appPID),
           CFHash(focusedWindow) == CFHash(axWindow),
           let position = axWindow.position,
           let size = axWindow.size {
            return CGRect(origin: position, size: size)
        }

        if let scriptIndex = window.scriptIndex,
           WindowScriptBridge.mainWindowIndex(forProcessIdentifier: appPID) == scriptIndex,
           let state = WindowScriptBridge.fetchWindows(forProcessIdentifier: appPID, windowIndices: [scriptIndex]).first {
            return state.frame
        }

        return nil
    }

    static func frontmostEligibleWindowFrame(for pid: pid_t, activeStackSessions: [ActiveStackSession]) -> CGRect? {
        guard !activeStackSessions.contains(where: { $0.app.processIdentifier == pid }) else {
            return nil
        }

        let appElement = AXUIElementCreateApplication(pid)
        for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            var value: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(appElement, attribute as CFString, &value)
            if result == .success,
               let window = AXUIElement.from(value) {
                if let position = window.position, let size = window.size {
                    return CGRect(origin: position, size: size)
                }
            }
        }

        return nil
    }

    private static func focusedAXWindow(for pid: pid_t) -> AXUIElement? {
        let systemWideElement = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        let focusedResult = AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedWindowAttribute as CFString, &value)
        if focusedResult == .success,
           let focusedWindow = AXUIElement.from(value) {
            return focusedWindow
        }

        let appElement = AXUIElementCreateApplication(pid)
        var mainWindowValue: CFTypeRef?
        let mainResult = AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &mainWindowValue)
        if mainResult == .success,
           let mainWindow = AXUIElement.from(mainWindowValue) {
            return mainWindow
        }

        return nil
    }
}
