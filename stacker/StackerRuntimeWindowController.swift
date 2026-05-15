import AppKit
import SwiftUI

@MainActor
final class StackerRuntimeWindowController {
    private var window: NSWindow?

    func startIfNeeded() {
        guard window == nil else { return }

        let hostingView = NSHostingView(rootView: ContentView(presentation: .window))
        hostingView.sizingOptions = []
        hostingView.translatesAutoresizingMaskIntoConstraints = true
        hostingView.frame = NSRect(x: 0, y: 0, width: 1, height: 1)

        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        containerView.translatesAutoresizingMaskIntoConstraints = true
        containerView.autoresizesSubviews = false
        containerView.addSubview(hostingView)

        let runtimeWindow = NSWindow(
            contentRect: NSRect(x: -10_000, y: -10_000, width: 1, height: 1),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        runtimeWindow.contentView = containerView
        runtimeWindow.contentMinSize = .zero
        runtimeWindow.contentMaxSize = NSSize(width: 1, height: 1)
        runtimeWindow.isReleasedWhenClosed = false
        runtimeWindow.level = .statusBar
        runtimeWindow.backgroundColor = .clear
        runtimeWindow.isOpaque = false
        runtimeWindow.hasShadow = false
        runtimeWindow.ignoresMouseEvents = true
        runtimeWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        runtimeWindow.orderFrontRegardless()
        runtimeWindow.orderBack(nil)

        window = runtimeWindow
    }
}

final class StackerAppDelegate: NSObject, NSApplicationDelegate {
    private let runtimeWindowController = StackerRuntimeWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            runtimeWindowController.startIfNeeded()
        }
    }
}
