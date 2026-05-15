import SwiftUI

@main
struct stackerApp: App {
    @NSApplicationDelegateAdaptor(StackerAppDelegate.self) private var appDelegate
    @StateObject private var menuBarState = MenuBarStateStore()
    @StateObject private var overlayVisibilityController = OverlayVisibilityController()

    var body: some Scene {
        WindowGroup("Stacker") {
            MainWindowView()
                .frame(minWidth: 900, minHeight: 620)
        }

        MenuBarExtra {
            StackerMenuBarContent(state: menuBarState)
        } label: {
            StackerMenuBarLabel(count: menuBarState.activeStackCount)
        }

        Settings {
            OverlayShortcutSettingsView()
        }
        .commands {
            CommandMenu("Stacker") {
                Button("Open Stacker") {
                    StackerAppWindowActions.openMainWindow()
                }
                .keyboardShortcut("0", modifiers: [.command])

                Button("Refresh Chrome") {
                    NotificationCenter.default.post(name: .stackerRefreshApplications, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button(overlayVisibilityController.isHidden ? "Show Profile Widgets" : "Hide Profile Widgets") {
                    overlayVisibilityController.toggleOverlayVisibility()
                }
            }
        }
    }
}
