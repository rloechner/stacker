import AppKit

enum ChromeProfileSupport {
    static let bundleIdentifier = "com.google.Chrome"
    static let appName = "Google Chrome"

    static func isSupportedChrome(_ app: NSRunningApplication) -> Bool {
        app.activationPolicy == .regular && isSupportedChrome(bundleIdentifier: app.bundleIdentifier, name: app.localizedName)
    }

    static func isSupportedChrome(bundleIdentifier: String?, name: String?) -> Bool {
        if bundleIdentifier == Self.bundleIdentifier {
            return true
        }

        return bundleIdentifier == nil && name == Self.appName
    }

    static func profileWindowTitle(rawTitle: String?, fallbackIndex: Int) -> String {
        let title = rawTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty else {
            return "Chrome Profile \(fallbackIndex)"
        }

        return profileName(fromWindowTitle: title) ?? title
    }

    private static func profileName(fromWindowTitle title: String) -> String? {
        let separators = [" — ", " – ", " - "]

        for separator in separators {
            let parts = title
                .components(separatedBy: separator)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            guard parts.count >= 2 else { continue }

            if isChromeName(parts.last) {
                return parts.dropLast().last
            }

            if isChromeName(parts.first) {
                return parts.dropFirst().first
            }

            if parts.count >= 3 {
                return parts[parts.count - 2]
            }
        }

        return nil
    }

    private static func isChromeName(_ value: String?) -> Bool {
        guard let value else { return false }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "google chrome" || normalized == "chrome"
    }
}

extension TargetApplication {
    var isChrome: Bool {
        ChromeProfileSupport.isSupportedChrome(bundleIdentifier: bundleIdentifier, name: name)
    }
}
