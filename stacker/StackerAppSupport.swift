import SwiftUI
import AppKit
import Combine

extension NSUserInterfaceItemIdentifier {
    static let stackerAdminWindow = NSUserInterfaceItemIdentifier("stacker.adminWindow")
}

struct StackerAdminWindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        StackerAdminWindowMarkerView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            window.identifier = .stackerAdminWindow
            window.title = "Stacker"
        }
    }
}

private final class StackerAdminWindowMarkerView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        window.identifier = .stackerAdminWindow
        window.title = "Stacker"
    }
}

enum OverlayShortcutPreference {
    static let hiddenKey = "stacker.overlayHidden"
    static let keyCodeKey = "stacker.overlayShortcutKeyCode"
    static let modifiersKey = "stacker.overlayShortcutModifiers"
    static let defaultKeyCode = 15 // R
    static let defaultModifiers = Int(NSEvent.ModifierFlags.command.union(.option).rawValue)
}

enum StackerAppWindowActions {
    private static var adminWindows: [NSWindow] {
        NSApp.windows.filter { $0.identifier == .stackerAdminWindow }
    }

    static func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = adminWindows.first ??
            NSApp.windows.first(where: { $0.canBecomeKey && $0.title.localizedCaseInsensitiveContains("stacker") }) ??
            NSApp.windows.first(where: \.canBecomeKey) {
            window.makeKeyAndOrderFront(nil)
        } else {
            NSApp.sendAction(#selector(NSWindow.makeKeyAndOrderFront(_:)), to: nil, from: nil)
        }
    }

    static func hideMainWindow() {
        adminWindows.forEach { window in
            window.orderOut(nil)
        }
    }

    static func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}

enum OverlayShortcutState {
    static func ensureDefaults() {
        UserDefaults.standard.set(false, forKey: OverlayShortcutPreference.hiddenKey)

        if UserDefaults.standard.object(forKey: OverlayShortcutPreference.keyCodeKey) == nil {
            UserDefaults.standard.set(Int(OverlayShortcutPreference.defaultKeyCode), forKey: OverlayShortcutPreference.keyCodeKey)
        }

        if UserDefaults.standard.object(forKey: OverlayShortcutPreference.modifiersKey) == nil {
            UserDefaults.standard.set(OverlayShortcutPreference.defaultModifiers, forKey: OverlayShortcutPreference.modifiersKey)
        }

        if UserDefaults.standard.object(forKey: StackOverlayPlacementPreferenceStore.key) == nil {
            StackOverlayPlacementPreferenceStore.set(.left)
        }

        StackJumpShortcutState.ensureDefaults()
    }

    static func isHidden() -> Bool {
        UserDefaults.standard.bool(forKey: OverlayShortcutPreference.hiddenKey)
    }

    @discardableResult
    static func toggleVisibility() -> Bool {
        let nextValue = !isHidden()
        UserDefaults.standard.set(nextValue, forKey: OverlayShortcutPreference.hiddenKey)
        NotificationCenter.default.post(name: .stackerOverlayVisibilityDidChange, object: nil)
        return nextValue
    }

    static func shortcutDescription() -> String {
        let keyCode = UInt16(UserDefaults.standard.integer(forKey: OverlayShortcutPreference.keyCodeKey))
        let modifierFlags = NSEvent.ModifierFlags(rawValue: UInt(UserDefaults.standard.integer(forKey: OverlayShortcutPreference.modifiersKey)))
        let modifierDescription = [
            modifierFlags.contains(.command) ? "Command" : nil,
            modifierFlags.contains(.option) ? "Option" : nil,
            modifierFlags.contains(.control) ? "Control" : nil,
            modifierFlags.contains(.shift) ? "Shift" : nil
        ]
        .compactMap { $0 }
        .joined(separator: " + ")
        let keyTitle = ShortcutKeyOption.commonOptions.first(where: { $0.id == keyCode })?.title ?? "R"
        return "\(modifierDescription) + \(keyTitle)"
    }
}

enum OverlayAppVisibilityPreference {
    static let hiddenAppIdentifiersKey = "stacker.hiddenOverlayApps"

    static func appIdentifier(bundleIdentifier: String?, appName: String) -> String {
        if let bundleIdentifier, !bundleIdentifier.isEmpty {
            return "bundle:\(bundleIdentifier)"
        }
        return "name:\(appName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }

    static func hiddenAppIdentifiers() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: hiddenAppIdentifiersKey) ?? [])
    }

    static func isHidden(bundleIdentifier: String?, appName: String) -> Bool {
        hiddenAppIdentifiers().contains(appIdentifier(bundleIdentifier: bundleIdentifier, appName: appName))
    }

    static func setHidden(_ hidden: Bool, bundleIdentifier: String?, appName: String) {
        let identifier = appIdentifier(bundleIdentifier: bundleIdentifier, appName: appName)
        var identifiers = hiddenAppIdentifiers()
        if hidden {
            identifiers.insert(identifier)
        } else {
            identifiers.remove(identifier)
        }
        UserDefaults.standard.set(Array(identifiers).sorted(), forKey: hiddenAppIdentifiersKey)
    }

    static func toggle(bundleIdentifier: String?, appName: String) -> Bool {
        let next = !isHidden(bundleIdentifier: bundleIdentifier, appName: appName)
        setHidden(next, bundleIdentifier: bundleIdentifier, appName: appName)
        return next
    }
}

struct ShortcutKeyOption: Identifiable, Hashable {
    let id: UInt16
    let title: String

    static let commonOptions: [ShortcutKeyOption] = [
        .init(id: 15, title: "R"),
        .init(id: 17, title: "T"),
        .init(id: 1, title: "S"),
        .init(id: 14, title: "E"),
        .init(id: 13, title: "W"),
        .init(id: 2, title: "D"),
        .init(id: 3, title: "F"),
        .init(id: 37, title: "L"),
        .init(id: 46, title: "M"),
        .init(id: 45, title: "N"),
        .init(id: 11, title: "B"),
        .init(id: 31, title: "O")
    ]
}

final class OverlayVisibilityController: ObservableObject {
    @Published private(set) var isHidden = UserDefaults.standard.bool(forKey: OverlayShortcutPreference.hiddenKey)
    @Published private(set) var shortcutDescription = ""

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var defaultsObserver: NSObjectProtocol?

    init() {
        OverlayShortcutState.ensureDefaults()
        updateShortcutDescription()
        installMonitors()
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.isHidden = UserDefaults.standard.bool(forKey: OverlayShortcutPreference.hiddenKey)
                self?.updateShortcutDescription()
            }
        }
    }

    deinit {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
    }

    func toggleOverlayVisibility() {
        isHidden = OverlayShortcutState.toggleVisibility()
    }

    private func installMonitors() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event: event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if self.matchesShortcut(event) {
                self.toggleOverlayVisibility()
                return nil
            }
            return event
        }
    }

    private func handle(event: NSEvent) {
        guard matchesShortcut(event) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.toggleOverlayVisibility()
        }
    }

    private func matchesShortcut(_ event: NSEvent) -> Bool {
        let storedKeyCode = UInt16(UserDefaults.standard.integer(forKey: OverlayShortcutPreference.keyCodeKey))
        let storedModifiersValue = UInt(UserDefaults.standard.integer(forKey: OverlayShortcutPreference.modifiersKey))
        let storedModifiers = NSEvent.ModifierFlags(rawValue: storedModifiersValue)
        let normalizedEventModifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        return event.keyCode == storedKeyCode && normalizedEventModifiers == storedModifiers
    }

    private func updateShortcutDescription() {
        shortcutDescription = OverlayShortcutState.shortcutDescription()
    }
}
