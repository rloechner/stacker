import AppKit
import ApplicationServices

struct WindowDiscoveryOutcome {
    let availableWindows: [WindowChoice]
    let shouldEnterSelectionMode: Bool
    let errorMessage: String?
}

@MainActor
struct WindowDiscoveryService {
    var log: (String) -> Void = { _ in }

    func loadWindows(for targetApplication: TargetApplication) async -> WindowDiscoveryOutcome {
        let systemWideElement = AXUIElementCreateSystemWide()
        let directAppElement = AXUIElementCreateApplication(targetApplication.processIdentifier)
        let focusedApplicationProbe = focusedApplicationElement(from: systemWideElement)

        let fetchResult = await fetchWindows(
            for: targetApplication,
            systemWideElement: systemWideElement,
            focusedApplicationProbe: focusedApplicationProbe,
            directAppElement: directAppElement
        )

        guard fetchResult.error == .success else {
            let scriptWindows = WindowScriptBridge.fetchWindows(forProcessIdentifier: targetApplication.processIdentifier)
            if !scriptWindows.isEmpty {
                return WindowDiscoveryOutcome(
                    availableWindows: scriptWindows.map { state in
                        let title = targetApplication.isChrome
                            ? ChromeProfileSupport.profileWindowTitle(rawTitle: state.title, fallbackIndex: state.index)
                            : (state.title.isEmpty ? "Window \(state.index)" : state.title)
                        return WindowChoice(
                            id: UInt(state.index),
                            title: title,
                            window: nil,
                            scriptIndex: state.index
                        )
                    },
                    shouldEnterSelectionMode: true,
                    errorMessage: nil
                )
            }

            let errorMessage = targetApplication.isChrome
                ? "Unable to read Chrome profile windows. \(message(for: fetchResult.error))"
                : "Unable to read windows for \(targetApplication.name). \(message(for: fetchResult.error))"
            return WindowDiscoveryOutcome(
                availableWindows: [],
                shouldEnterSelectionMode: false,
                errorMessage: errorMessage
            )
        }

        let choices = fetchResult.windows.enumerated().compactMap { index, window -> WindowChoice? in
            let movableWindow = resolveMovableWindow(from: window)
            let role = movableWindow.role ?? window.role ?? "nil"
            let rawTitle = (movableWindow.title ?? window.title)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasPosition = movableWindow.position != nil
            let hasSize = movableWindow.size != nil

            guard role == kAXWindowRole as String else { return nil }
            let title = targetApplication.isChrome
                ? ChromeProfileSupport.profileWindowTitle(rawTitle: rawTitle, fallbackIndex: index + 1)
                : ((rawTitle?.isEmpty == false) ? rawTitle! : "Window \(index + 1)")
            guard hasPosition, hasSize else { return nil }

            return WindowChoice(
                id: CFHash(movableWindow),
                title: title,
                window: movableWindow,
                scriptIndex: nil
            )
        }

        return WindowDiscoveryOutcome(
            availableWindows: choices,
            shouldEnterSelectionMode: !choices.isEmpty,
            errorMessage: choices.isEmpty
                ? (targetApplication.isChrome
                    ? "No movable Chrome profile windows were found. Open at least two normal Chrome profile windows, then refresh."
                    : "No movable windows were found for \(targetApplication.name). Make sure that app has normal desktop windows open.")
                : nil
        )
    }

    private func runningApplication(for targetApplication: TargetApplication) -> NSRunningApplication? {
        NSRunningApplication(processIdentifier: targetApplication.processIdentifier)
    }

    private func resolveMovableWindow(from element: AXUIElement) -> AXUIElement {
        let candidates = [
            element,
            element.windowElement,
            element.topLevelUIElement,
            element.windowElement?.topLevelUIElement,
            element.topLevelUIElement?.windowElement
        ].compactMap { $0 }

        var seen = Set<UInt>()
        for candidate in candidates {
            let hash = CFHash(candidate)
            guard seen.insert(hash).inserted else { continue }

            if candidate.role == kAXWindowRole as String,
               candidate.position != nil,
               candidate.size != nil {
                return candidate
            }
        }

        return candidates.first ?? element
    }

    private func fetchWindows(
        for targetApplication: TargetApplication,
        systemWideElement: AXUIElement,
        focusedApplicationProbe: FocusedApplicationProbe?,
        directAppElement: AXUIElement
    ) async -> WindowFetchResult {
        var lastError: AXError = .failure
        var candidateAppElements: [(label: String, element: AXUIElement)] = []

        if let focusedApplicationProbe,
           focusedApplicationProbe.processIdentifier == targetApplication.processIdentifier {
            candidateAppElements.append(("focused app", focusedApplicationProbe.element))
        }

        candidateAppElements.append(("direct app", directAppElement))

        for attempt in 0..<4 {
            for candidate in candidateAppElements {
                let appElement = candidate.element
                let windowsResult = copyWindowList(from: appElement)
                if !windowsResult.windows.isEmpty {
                    return WindowFetchResult(windows: windowsResult.windows, error: .success)
                }

                if windowsResult.error == .success {
                    let focusedCandidates = fallbackWindows(from: appElement)
                    if !focusedCandidates.isEmpty {
                        return WindowFetchResult(windows: focusedCandidates, error: .success)
                    }
                    lastError = .noValue
                } else {
                    lastError = windowsResult.error
                }
            }

            let systemWideFocusedWindows = systemWideFocusedWindow(from: systemWideElement, expectedPID: targetApplication.processIdentifier)
            if !systemWideFocusedWindows.isEmpty {
                return WindowFetchResult(windows: systemWideFocusedWindows, error: .success)
            }

            if lastError == .cannotComplete, let runningApplication = runningApplication(for: targetApplication) {
                runningApplication.activate()
            }

            if attempt < 3 {
                try? await Task.sleep(for: .milliseconds(250))
            }
        }

        return WindowFetchResult(windows: [], error: lastError)
    }

    private func focusedApplicationElement(from systemWideElement: AXUIElement) -> FocusedApplicationProbe? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedApplicationAttribute as CFString, &value)
        guard result == .success,
              let element = axElement(from: value) else {
            return nil
        }

        var pid: pid_t = 0
        let pidResult = AXUIElementGetPid(element, &pid)
        guard pidResult == .success else {
            return nil
        }

        return FocusedApplicationProbe(element: element, processIdentifier: pid)
    }

    private func systemWideFocusedWindow(from systemWideElement: AXUIElement, expectedPID: pid_t) -> [AXUIElement] {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedWindowAttribute as CFString, &value)
        guard result == .success,
              let window = axElement(from: value) else {
            return []
        }

        var pid: pid_t = 0
        let pidResult = AXUIElementGetPid(window, &pid)
        guard pidResult == .success, pid == expectedPID else {
            return []
        }

        return [window]
    }

    private func copyWindowList(from appElement: AXUIElement) -> WindowListResult {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value)
        let windows = value as? [AXUIElement] ?? []
        return WindowListResult(windows: windows, error: result)
    }

    private func fallbackWindows(from appElement: AXUIElement) -> [AXUIElement] {
        let attributes = [kAXFocusedWindowAttribute, kAXMainWindowAttribute]
        var windows: [AXUIElement] = []
        var seenHashes = Set<UInt>()

        for attribute in attributes {
            var value: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(appElement, attribute as CFString, &value)
            guard result == .success,
                  let window = axElement(from: value) else {
                continue
            }

            let hash = CFHash(window)
            if seenHashes.insert(hash).inserted {
                windows.append(window)
            }
        }

        return windows
    }

    private func axElement(from value: CFTypeRef?) -> AXUIElement? {
        AXUIElement.from(value)
    }

    private func message(for error: AXError) -> String {
        switch error {
        case .success:
            return ""
        case .apiDisabled:
            return "Accessibility access is disabled."
        case .attributeUnsupported:
            return "Chrome does not expose window information through Accessibility."
        case .cannotComplete:
            return "macOS could not complete the Accessibility request."
        case .failure:
            return "The Accessibility request failed."
        case .illegalArgument:
            return "The Accessibility request used an invalid argument."
        case .invalidUIElement:
            return "Chrome is no longer available."
        case .notImplemented:
            return "Chrome does not implement the required Accessibility behavior."
        case .notificationUnsupported:
            return "Chrome does not support window change notifications."
        case .notificationAlreadyRegistered, .notificationNotRegistered:
            return "Window notifications could not be registered."
        case .noValue:
            return "Chrome did not return any window data."
        case .parameterizedAttributeUnsupported:
            return "Chrome rejected the window query."
        case .actionUnsupported:
            return "Chrome does not support the requested window action."
        case .notEnoughPrecision:
            return "macOS could not apply the window frame accurately."
        default:
            return "Unknown Accessibility error \(error.rawValue)."
        }
    }
}
