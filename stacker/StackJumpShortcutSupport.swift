import AppKit
import ApplicationServices
import Carbon
import Combine
import Foundation

enum StackJumpShortcutPreference {
    static let enabledKey = "stacker.stackJumpShortcutsEnabled"
    static let modifiersKey = "stacker.stackJumpShortcutModifiers"
    static let defaultEnabled = true
    static let defaultModifiers = Int(NSEvent.ModifierFlags.control.rawValue)
}

enum StackJumpShortcutState {
    static func ensureDefaults() {
        if UserDefaults.standard.object(forKey: StackJumpShortcutPreference.enabledKey) == nil {
            UserDefaults.standard.set(StackJumpShortcutPreference.defaultEnabled, forKey: StackJumpShortcutPreference.enabledKey)
        }

        if UserDefaults.standard.object(forKey: StackJumpShortcutPreference.modifiersKey) == nil {
            UserDefaults.standard.set(StackJumpShortcutPreference.defaultModifiers, forKey: StackJumpShortcutPreference.modifiersKey)
        }
    }

    static func isEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: StackJumpShortcutPreference.enabledKey)
    }

    static func requiredModifiersRawValue() -> Int {
        let stored = UserDefaults.standard.integer(forKey: StackJumpShortcutPreference.modifiersKey)
        if stored == 0, UserDefaults.standard.object(forKey: StackJumpShortcutPreference.modifiersKey) == nil {
            return StackJumpShortcutPreference.defaultModifiers
        }
        return stored
    }

    static func shortcutDescription() -> String {
        let modifierFlags = NSEvent.ModifierFlags(rawValue: UInt(requiredModifiersRawValue()))
        let modifierDescription = [
            modifierFlags.contains(.command) ? "Command" : nil,
            modifierFlags.contains(.option) ? "Option" : nil,
            modifierFlags.contains(.control) ? "Control" : nil,
            modifierFlags.contains(.shift) ? "Shift" : nil
        ]
        .compactMap { $0 }
        .joined(separator: " + ")
        let prefix = modifierDescription.isEmpty ? "" : "\(modifierDescription) + "
        return "\(prefix)1 ... 9"
    }
}

enum StackJumpShortcutLogic {
    static let digitKeyCodeToSlot: [UInt16: Int] = [
        UInt16(kVK_ANSI_1): 1,
        UInt16(kVK_ANSI_2): 2,
        UInt16(kVK_ANSI_3): 3,
        UInt16(kVK_ANSI_4): 4,
        UInt16(kVK_ANSI_5): 5,
        UInt16(kVK_ANSI_6): 6,
        UInt16(kVK_ANSI_7): 7,
        UInt16(kVK_ANSI_8): 8,
        UInt16(kVK_ANSI_9): 9
    ]

    static func slotNumber(forKeyCode keyCode: UInt16) -> Int? {
        digitKeyCodeToSlot[keyCode]
    }

    static func normalizedModifierFlags(from eventFlags: CGEventFlags) -> NSEvent.ModifierFlags {
        var flags = NSEvent.ModifierFlags()
        if eventFlags.contains(.maskCommand) { flags.insert(.command) }
        if eventFlags.contains(.maskAlternate) { flags.insert(.option) }
        if eventFlags.contains(.maskControl) { flags.insert(.control) }
        if eventFlags.contains(.maskShift) { flags.insert(.shift) }
        return flags.intersection([.command, .option, .control, .shift])
    }

    static func matchesModifiers(eventFlags: CGEventFlags, requiredRawValue: Int) -> Bool {
        let required = NSEvent.ModifierFlags(rawValue: UInt(requiredRawValue))
            .intersection([.command, .option, .control, .shift])
        return normalizedModifierFlags(from: eventFlags) == required
    }

    static func resolvedWindowID(slotNumber: Int, windowOrder: [UInt]) -> UInt? {
        let index = slotNumber - 1
        guard windowOrder.indices.contains(index) else { return nil }
        return windowOrder[index]
    }

    static func shouldHandle(
        isEnabled: Bool,
        stackerIsFrontmost: Bool,
        keyCode: UInt16,
        eventFlags: CGEventFlags,
        requiredModifiersRawValue: Int,
        frontmostPID: pid_t?,
        windowOrder: [UInt]?
    ) -> Bool {
        guard isEnabled else { return false }
        guard !stackerIsFrontmost else { return false }
        guard let slotNumber = slotNumber(forKeyCode: keyCode) else { return false }
        guard matchesModifiers(eventFlags: eventFlags, requiredRawValue: requiredModifiersRawValue) else { return false }
        guard let frontmostPID, frontmostPID > 0 else { return false }
        guard let windowOrder, !windowOrder.isEmpty else { return false }
        return resolvedWindowID(slotNumber: slotNumber, windowOrder: windowOrder) != nil
    }
}

enum StackJumpShortcutSessionRegistry {
    private static let lock = NSLock()
    private static var windowOrdersByPID: [pid_t: [UInt]] = [:]

    static func sync(activeStackSessions: [ActiveStackSession]) {
        let snapshot = Dictionary(uniqueKeysWithValues: activeStackSessions.map {
            ($0.app.processIdentifier, $0.windowOrder)
        })
        lock.lock()
        windowOrdersByPID = snapshot
        lock.unlock()
    }

    static func windowOrder(for pid: pid_t) -> [UInt]? {
        lock.lock()
        defer { lock.unlock() }
        return windowOrdersByPID[pid]
    }
}

final class StackJumpShortcutController: ObservableObject {
    @Published private(set) var shortcutDescription = StackJumpShortcutState.shortcutDescription()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var trustObserver: NSObjectProtocol?
    private var defaultsObserver: NSObjectProtocol?

    init() {
        StackJumpShortcutState.ensureDefaults()
        updateShortcutDescription()
        installTapIfNeeded()
        observeChanges()
    }

    deinit {
        removeTap()
        if let trustObserver {
            NotificationCenter.default.removeObserver(trustObserver)
        }
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
    }

    private func observeChanges() {
        trustObserver = NotificationCenter.default.addObserver(
            forName: .stackerAccessibilityTrustDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.installTapIfNeeded()
        }

        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateShortcutDescription()
            self?.installTapIfNeeded()
        }
    }

    private func updateShortcutDescription() {
        shortcutDescription = StackJumpShortcutState.shortcutDescription()
    }

    private func installTapIfNeeded() {
        removeTap()

        guard StackJumpShortcutState.isEnabled() else { return }
        guard AccessibilityPermissionSupport.isProcessTrusted else { return }

        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else {
                return Unmanaged.passUnretained(event)
            }
            let controller = Unmanaged<StackJumpShortcutController>.fromOpaque(userInfo).takeUnretainedValue()
            return controller.handleEvent(type: type, event: event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func removeTap() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let stackerIsFrontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Bundle.main.bundleIdentifier
        let windowOrder = frontmostPID.flatMap { StackJumpShortcutSessionRegistry.windowOrder(for: $0) }

        guard StackJumpShortcutLogic.shouldHandle(
            isEnabled: StackJumpShortcutState.isEnabled(),
            stackerIsFrontmost: stackerIsFrontmost,
            keyCode: keyCode,
            eventFlags: event.flags,
            requiredModifiersRawValue: StackJumpShortcutState.requiredModifiersRawValue(),
            frontmostPID: frontmostPID,
            windowOrder: windowOrder
        ), let slotNumber = StackJumpShortcutLogic.slotNumber(forKeyCode: keyCode),
           let pid = frontmostPID,
           let order = windowOrder,
           let windowID = StackJumpShortcutLogic.resolvedWindowID(slotNumber: slotNumber, windowOrder: order) else {
            return Unmanaged.passUnretained(event)
        }

        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .stackerFocusWindowInStack,
                object: nil,
                userInfo: [
                    "pid": pid,
                    "windowID": Int(windowID)
                ]
            )
        }

        return nil
    }
}
