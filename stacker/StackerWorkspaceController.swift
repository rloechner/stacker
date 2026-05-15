import AppKit
import ApplicationServices
import Observation

@MainActor
@Observable
final class StackerWorkspaceController {
    var eligibleApplications: [TargetApplication] = []
    var selectedTargetPID: pid_t?
    var targetApplication: TargetApplication?
    var appName: String?
    var targetPID: pid_t?
    var availableWindows: [WindowChoice] = []
    var isSelectingWindows = false
    var isLoadingWindows = false
    var showAccessibilityAlert = false
    var errorMessage: String?
    var debugMessages: [String] = []
    var hasRequestedAccessibilityPrompt = false
    var accessibilityTrusted = AXIsProcessTrusted()
    var pendingAutoStackPID: pid_t?
    var frontmostEligiblePID: pid_t?

    func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    func requestAccessibilityPrompt() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func configureAccessibilityTimeout() {
        let systemWideElement = AXUIElementCreateSystemWide()
        let result = AXUIElementSetMessagingTimeout(systemWideElement, 15)
        appendDebug("AX messaging timeout set result: \(message(for: result)) [\(result.rawValue)]")
    }

    func appendDebug(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        debugMessages.append(trimmed)
        if debugMessages.count > 120 {
            debugMessages.removeFirst(debugMessages.count - 120)
        }
    }

    func updateTrackedApplication(from app: NSRunningApplication?, activeStackSessions: [ActiveStackSession]) {
        guard let app, isEligibleTargetApp(app) else {
            frontmostEligiblePID = nil
            return
        }

        if activeStackSessions.contains(where: { $0.app.processIdentifier == app.processIdentifier }) {
            frontmostEligiblePID = nil
            return
        }

        frontmostEligiblePID = eligibleApplications.contains(where: { $0.processIdentifier == app.processIdentifier })
            ? app.processIdentifier
            : nil
    }

    func isEligibleTargetApp(_ app: NSRunningApplication) -> Bool {
        ChromeProfileSupport.isSupportedChrome(app)
    }

    func loadEligibleApplications(activeStackSessions: [ActiveStackSession]) async {
        guard isAccessibilityTrusted() else {
            showAccessibilityAlert = true
            return
        }

        isLoadingWindows = true
        defer { isLoadingWindows = false }

        let runningApplications = NSWorkspace.shared.runningApplications
            .filter(isEligibleTargetApp)
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }

        var discoveredApplications: [TargetApplication] = []
        for app in runningApplications {
            let name = app.localizedName ?? ChromeProfileSupport.appName
            let scriptWindowCount = WindowScriptBridge.windowCount(forProcessIdentifier: app.processIdentifier) ?? 0
            let activeSessionWindowCount = activeStackSessions.first(where: { $0.app.processIdentifier == app.processIdentifier })?.windowTitles.count ?? 0
            let windowCount = max(scriptWindowCount, activeSessionWindowCount)

            guard windowCount >= 2 else { continue }

            discoveredApplications.append(
                TargetApplication(
                    name: name,
                    bundleIdentifier: app.bundleIdentifier,
                    processIdentifier: app.processIdentifier,
                    windowCount: windowCount
                )
            )
        }

        eligibleApplications = discoveredApplications

        if let selectedTargetPID,
           let selectedApp = eligibleApplications.first(where: { $0.processIdentifier == selectedTargetPID }) {
            targetApplication = selectedApp
            appName = selectedApp.name
            targetPID = selectedApp.processIdentifier
        } else if let firstApp = eligibleApplications.first {
            selectedTargetPID = firstApp.processIdentifier
            targetApplication = firstApp
            appName = firstApp.name
            targetPID = firstApp.processIdentifier
        } else {
            selectedTargetPID = nil
            targetApplication = nil
            appName = nil
            targetPID = nil
            errorMessage = nil
        }
    }

    private func message(for error: AXError) -> String {
        switch error {
        case .success:
            return ""
        case .apiDisabled:
            return "Accessibility access is disabled."
        case .attributeUnsupported:
            return "Chrome does not expose profile window information through Accessibility."
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
        case .notificationAlreadyRegistered:
            return "That window was already being observed."
        case .notificationNotRegistered:
            return "That window was not being observed."
        case .notificationUnsupported:
            return "Chrome does not support window move notifications."
        case .noValue:
            return "Chrome did not return a focused or main window."
        case .actionUnsupported:
            return "Chrome does not support the requested Accessibility action."
        case .notEnoughPrecision:
            return "macOS could not set the requested window frame precisely enough."
        case .parameterizedAttributeUnsupported:
            return "Chrome does not support the requested Accessibility query."
        case .invalidUIElementObserver:
            return "The Accessibility observer is no longer valid."
        @unknown default:
            return "An unknown Accessibility error occurred."
        }
    }
}
