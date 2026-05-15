import AppKit

enum BrowserSupport {
    enum Browser: CaseIterable {
        case chrome
        case brave
        case safari
        case edge
        case firefox

        var bundleIdentifier: String {
            switch self {
            case .chrome:
                return "com.google.Chrome"
            case .brave:
                return "com.brave.Browser"
            case .safari:
                return "com.apple.Safari"
            case .edge:
                return "com.microsoft.edgemac"
            case .firefox:
                return "org.mozilla.firefox"
            }
        }

        var appName: String {
            switch self {
            case .chrome:
                return "Google Chrome"
            case .brave:
                return "Brave Browser"
            case .safari:
                return "Safari"
            case .edge:
                return "Microsoft Edge"
            case .firefox:
                return "Firefox"
            }
        }

        var shortName: String {
            switch self {
            case .chrome:
                return "Chrome"
            case .brave:
                return "Brave"
            case .safari:
                return "Safari"
            case .edge:
                return "Edge"
            case .firefox:
                return "Firefox"
            }
        }

        var knownNames: Set<String> {
            switch self {
            case .chrome:
                return ["google chrome", "chrome"]
            case .brave:
                return ["brave browser", "brave"]
            case .safari:
                return ["safari"]
            case .edge:
                return ["microsoft edge", "edge"]
            case .firefox:
                return ["firefox"]
            }
        }
    }

    static let fallbackAppName = Browser.chrome.appName

    static func browser(for app: NSRunningApplication) -> Browser? {
        guard app.activationPolicy == .regular else { return nil }
        return browser(bundleIdentifier: app.bundleIdentifier, name: app.localizedName)
    }

    static func browser(bundleIdentifier: String?, name: String?) -> Browser? {
        if let bundleIdentifier,
           let match = Browser.allCases.first(where: { $0.bundleIdentifier == bundleIdentifier }) {
            return match
        }

        guard let normalizedName = normalized(name) else { return nil }
        return Browser.allCases.first { browser in
            browser.knownNames.contains(normalizedName)
        }
    }

    static func isSupportedBrowser(_ app: NSRunningApplication) -> Bool {
        browser(for: app) != nil
    }

    static func isSupportedBrowser(bundleIdentifier: String?, name: String?) -> Bool {
        browser(bundleIdentifier: bundleIdentifier, name: name) != nil
    }

    static func windowTitle(for targetApplication: TargetApplication, rawTitle: String?, fallbackIndex: Int) -> String {
        let browser = targetApplication.browser
        let title = rawTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty else {
            return "\(browser?.shortName ?? "Browser") Window \(fallbackIndex)"
        }

        return browserWindowName(fromWindowTitle: title, browser: browser) ?? title
    }

    private static func browserWindowName(fromWindowTitle title: String, browser: Browser?) -> String? {
        let separators = [" — ", " – ", " - "]

        for separator in separators {
            let parts = title
                .components(separatedBy: separator)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            guard parts.count >= 2 else { continue }

            if isBrowserName(parts.last, browser: browser) {
                return parts.dropLast().last
            }

            if isBrowserName(parts.first, browser: browser) {
                return parts.dropFirst().first
            }

            if parts.count >= 3 {
                return parts[parts.count - 2]
            }
        }

        return nil
    }

    private static func isBrowserName(_ value: String?, browser: Browser?) -> Bool {
        guard let normalizedValue = normalized(value) else { return false }
        if let browser {
            return browser.knownNames.contains(normalizedValue)
        }
        return Browser.allCases.contains { $0.knownNames.contains(normalizedValue) }
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }
}

extension TargetApplication {
    var browser: BrowserSupport.Browser? {
        BrowserSupport.browser(bundleIdentifier: bundleIdentifier, name: name)
    }

    var isSupportedBrowser: Bool {
        BrowserSupport.isSupportedBrowser(bundleIdentifier: bundleIdentifier, name: name)
    }
}
