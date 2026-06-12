import SwiftUI

@main
struct stackerApp: App {
    @NSApplicationDelegateAdaptor(StackerAppDelegate.self) private var appDelegate
    @StateObject private var menuBarState = MenuBarStateStore()
    @StateObject private var overlayVisibilityController = OverlayVisibilityController()
    @StateObject private var stackJumpShortcutController = StackJumpShortcutController()

    var body: some Scene {
        WindowGroup("Stacker") {
            MainWindowView()
                .background(StackerAdminWindowAccessor())
        }
        .defaultSize(width: 900, height: 620)

        MenuBarExtra {
            StackerMenuBarContent(state: menuBarState)
        } label: {
            StackerMenuBarLabel(
                count: menuBarState.activeStackCount,
                degradedCount: menuBarState.degradedStackCount,
                floatingCount: menuBarState.floatingStackCount
            )
        }

        Settings {
            OverlayShortcutSettingsView()
                .frame(minWidth: 520, idealWidth: 560, minHeight: 540, idealHeight: 680)
        }
        .commands {
            CommandGroup(replacing: .appVisibility) {
                Button("Hide Stacker Window") {
                    StackerAppWindowActions.hideMainWindow()
                }
                .keyboardShortcut("h", modifiers: [.command])

                Button("Hide Others") {
                    NSApp.hideOtherApplications(nil)
                }
                .keyboardShortcut("h", modifiers: [.command, .option])

                Button("Show All") {
                    NSApp.unhideAllApplications(nil)
                }
            }

            CommandMenu("Stacker") {
                Button("Open Stacker") {
                    StackerAppWindowActions.openMainWindow()
                }
                .keyboardShortcut("0", modifiers: [.command])

                Button("Hide Stacker Window") {
                    StackerAppWindowActions.hideMainWindow()
                }

                Button("Hard Refresh Browsers") {
                    NotificationCenter.default.post(name: .stackerRefreshApplications, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button(overlayVisibilityController.isHidden ? "Show Window Widgets" : "Hide Window Widgets") {
                    overlayVisibilityController.toggleOverlayVisibility()
                }
            }
        }
    }
}
