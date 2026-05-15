import AppKit
import OSLog

enum WindowScriptBridge {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "RHL-Studios.stacker",
        category: "AppleScript"
    )

    static func windowCount(forAppName appName: String) -> Int? {
        windowCount(processReference: "process \"\(escaped(appName))\"")
    }

    static func windowCount(forProcessIdentifier processIdentifier: pid_t) -> Int? {
        windowCount(processReference: "(first process whose unix id is \(processIdentifier))")
    }

    private static func windowCount(processReference: String) -> Int? {
        let source = """
        tell application "System Events"
            tell \(processReference)
                return count of windows
            end tell
        end tell
        """

        guard let output = run(source)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }

        return Int(output)
    }

    static func fetchWindows(forAppName appName: String) -> [ScriptWindowState] {
        fetchWindows(forAppName: appName, windowIndices: nil)
    }

    static func fetchWindows(forAppName appName: String, windowIndices: [Int]?) -> [ScriptWindowState] {
        fetchWindows(processReference: "process \"\(escaped(appName))\"", windowIndices: windowIndices)
    }

    static func fetchWindows(forProcessIdentifier processIdentifier: pid_t) -> [ScriptWindowState] {
        fetchWindows(forProcessIdentifier: processIdentifier, windowIndices: nil)
    }

    static func fetchWindows(forProcessIdentifier processIdentifier: pid_t, windowIndices: [Int]?) -> [ScriptWindowState] {
        fetchWindows(processReference: "(first process whose unix id is \(processIdentifier))", windowIndices: windowIndices)
    }

    private static func fetchWindows(processReference: String, windowIndices: [Int]?) -> [ScriptWindowState] {
        let windowSelectionScript: String
        if let windowIndices, !windowIndices.isEmpty {
            let indicesList = windowIndices.map(String.init).joined(separator: ", ")
            windowSelectionScript = """
                set requestedIndices to {\(indicesList)}
                repeat with i in requestedIndices
                    set w to window (i as integer)
            """
        } else {
            windowSelectionScript = """
                repeat with i from 1 to count of windows
                    set w to window i
            """
        }

        let source = """
        tell application "System Events"
            tell \(processReference)
                set outputLines to {}
                \(windowSelectionScript)
                    try
                        set windowName to name of w
                    on error
                        set windowName to ""
                    end try
                    set p to position of w
                    set s to size of w
                    set end of outputLines to ((i as text) & "||" & windowName & "||" & (item 1 of p as text) & "||" & (item 2 of p as text) & "||" & (item 1 of s as text) & "||" & (item 2 of s as text))
                end repeat
                return outputLines as string
            end tell
        end tell
        """

        guard let output = run(source) else {
            return []
        }

        return output
            .split(separator: ",")
            .compactMap { line in
                let parts = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
                guard parts.count >= 11 else { return nil }
                guard let index = Int(parts[0]),
                      let x = Double(parts[4]),
                      let y = Double(parts[6]),
                      let width = Double(parts[8]),
                      let height = Double(parts[10]) else {
                    return nil
                }

                let title = parts[2]
                return ScriptWindowState(
                    index: index,
                    title: title,
                    frame: CGRect(x: x, y: y, width: width, height: height)
                )
            }
    }

    static func setFrame(_ frame: CGRect, forWindowIndex index: Int, appName: String) -> Bool {
        setFrame(frame, forWindowIndex: index, processReference: "process \"\(escaped(appName))\"")
    }

    static func setFrame(_ frame: CGRect, forWindowIndex index: Int, processIdentifier: pid_t) -> Bool {
        setFrame(frame, forWindowIndex: index, processReference: "(first process whose unix id is \(processIdentifier))")
    }

    private static func setFrame(_ frame: CGRect, forWindowIndex index: Int, processReference: String) -> Bool {
        let source = """
        tell application "System Events"
            tell \(processReference)
                tell window \(index)
                    set position to {\(Int(frame.origin.x)), \(Int(frame.origin.y))}
                    set size to {\(Int(frame.size.width)), \(Int(frame.size.height))}
                end tell
            end tell
        end tell
        """

        return run(source) != nil
    }

    static func focusWindow(_ index: Int, appName: String) {
        focusWindow(index, processReference: "process \"\(escaped(appName))\"")
    }

    static func focusWindow(_ index: Int, processIdentifier: pid_t) {
        focusWindow(index, processReference: "(first process whose unix id is \(processIdentifier))")
    }

    private static func focusWindow(_ index: Int, processReference: String) {
        let source = """
        tell application "System Events"
            tell \(processReference)
                set frontmost to true
                try
                    perform action "AXRaise" of window \(index)
                end try
            end tell
        end tell
        """

        _ = run(source)
    }

    static func openNewWindow(forAppName appName: String) {
        let source = """
        tell application "\(escaped(appName))" to activate
        delay 0.15
        tell application "System Events"
            tell process "\(escaped(appName))"
                set frontmost to true
                keystroke "n" using command down
            end tell
        end tell
        """

        _ = run(source)
    }

    static func mainWindowIndex(forAppName appName: String) -> Int? {
        mainWindowIndex(processReference: "process \"\(escaped(appName))\"")
    }

    static func mainWindowIndex(forProcessIdentifier processIdentifier: pid_t) -> Int? {
        mainWindowIndex(processReference: "(first process whose unix id is \(processIdentifier))")
    }

    private static func mainWindowIndex(processReference: String) -> Int? {
        let source = """
        tell application "System Events"
            tell \(processReference)
                repeat with i from 1 to count of windows
                    try
                        if value of attribute "AXMain" of window i is true then
                            return i as text
                        end if
                    end try
                end repeat
            end tell
        end tell
        """

        guard let output = run(source)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !output.isEmpty else { return nil }
        return Int(output)
    }

    private static var loggedErrorKeys: Set<String> = []

    private static func run(_ source: String) -> String? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let descriptor = script.executeAndReturnError(&error)
        if let error {
            logAppleScriptErrorIfNeeded(error)
            return nil
        }
        return descriptor.stringValue
    }

    private static func escaped(_ string: String) -> String {
        string.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func logAppleScriptErrorIfNeeded(_ error: NSDictionary) {
        let errorNumber = error[NSAppleScript.errorNumber] as? Int
        if errorNumber == -1719 || errorNumber == -1728 {
            return
        }

        let message = (error[NSAppleScript.errorMessage] as? String)
            ?? (error[NSAppleScript.errorBriefMessage] as? String)
            ?? error.description
        let key = "\(errorNumber ?? 0):\(message)"
        guard loggedErrorKeys.insert(key).inserted else { return }
        logger.error("AppleScript error \(errorNumber ?? 0): \(message, privacy: .public)")
    }
}
