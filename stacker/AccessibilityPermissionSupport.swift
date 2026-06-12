import AppKit
import ApplicationServices

enum AccessibilityPermissionSupport {
    private static let lastLaunchedVersionKey = "stacker.lastLaunchedMarketingVersion"
    private static let installLocationWarningShownKey = "stacker.installLocationWarningShown"

    static var isProcessTrusted: Bool {
        AXIsProcessTrusted()
    }

    static var marketingVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    static func requestSystemPrompt() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
    }

    /// Makes TCC record Stacker in the Accessibility list (toggle off) without
    /// showing the system "Accessibility Access" dialog, by attempting a harmless
    /// AX query against another process. Lets onboarding deep-link the user to a
    /// System Settings pane where Stacker is already listed.
    static func registerInAccessibilityListSilently() {
        guard !isProcessTrusted else { return }
        let target = NSWorkspace.shared.frontmostApplication
            ?? NSWorkspace.shared.runningApplications.first { $0.activationPolicy == .regular }
        guard let target else { return }

        let element = AXUIElementCreateApplication(target.processIdentifier)
        var value: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value)
    }

    static func openSystemSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ]
        for urlString in urls {
            guard let url = URL(string: urlString), NSWorkspace.shared.open(url) else { continue }
            return
        }
    }

    /// Records this launch and returns true when the marketing version changed since last run.
    @discardableResult
    static func recordLaunchAndDetectVersionUpgrade() -> Bool {
        let current = marketingVersion
        let previous = UserDefaults.standard.string(forKey: lastLaunchedVersionKey)
        UserDefaults.standard.set(current, forKey: lastLaunchedVersionKey)

        guard let previous, !previous.isEmpty, previous != current else {
            return false
        }
        return true
    }

    static var postUpdatePermissionGuidance: String {
        """
        After updating, macOS may keep an old Accessibility entry for the previous build. Quit Stacker completely (Command+Q), then turn Stacker off and on in Accessibility. If it still does not work, remove Stacker with the minus button, click plus, and choose Stacker in Applications.
        """
    }

    static var installLocationGuidance: String? {
        let bundlePath = Bundle.main.bundleURL.standardizedFileURL.path
        let installedPath = URL(fileURLWithPath: "/Applications/Stacker.app").standardizedFileURL.path

        if bundlePath == installedPath {
            return nil
        }

        if bundlePath.contains("/Volumes/") || bundlePath.contains(".dmg") {
            return "Stacker is running from a disk image. Drag Stacker into Applications and launch it from there so Accessibility permission persists."
        }

        return "For reliable Accessibility permission across updates, install Stacker in Applications and launch it from there."
    }

    static func shouldPresentInstallLocationWarning() -> Bool {
        guard installLocationGuidance != nil else { return false }
        return !UserDefaults.standard.bool(forKey: installLocationWarningShownKey)
    }

    static func markInstallLocationWarningPresented() {
        UserDefaults.standard.set(true, forKey: installLocationWarningShownKey)
    }
}

@MainActor
enum AccessibilityPermissionCoordinator {
    private static var observer: NSObjectProtocol?
    private static var lastTrusted = AccessibilityPermissionSupport.isProcessTrusted
    private(set) static var didUpgradeThisLaunch = false

    static func start() {
        didUpgradeThisLaunch = AccessibilityPermissionSupport.recordLaunchAndDetectVersionUpgrade()
        lastTrusted = AccessibilityPermissionSupport.isProcessTrusted

        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                refreshTrustState(postOnChangeOnly: true)
            }
        }
    }

    @discardableResult
    static func refreshTrustState(postOnChangeOnly: Bool = false) -> Bool {
        let trusted = AccessibilityPermissionSupport.isProcessTrusted
        let changed = trusted != lastTrusted
        lastTrusted = trusted

        if changed || !postOnChangeOnly {
            NotificationCenter.default.post(
                name: .stackerAccessibilityTrustDidChange,
                object: trusted
            )
        }
        return trusted
    }
}
