# Stacker

Stacker is a native macOS utility that turns multiple open web browser windows into one live window stack.

It is inspired by Arc's spaces workflow: separate browser contexts can feel like separate workspaces without keeping every browser window visible at once. Stacker applies that idea at the macOS window level. Open two or more browser windows, turn on a stack, and switch between those live windows from a compact drawer attached to the active browser window.

Stacker is intentionally narrow. It does not launch missing browsers or profiles, recreate browser sessions, restore arbitrary workspaces, or manage every app on the system. It coordinates browser windows that already exist.

## Current Capabilities

- Detects supported browsers when multiple windows are open.
- Links two or more browser windows into one live stack.
- Keeps linked windows aligned when the active window is moved or resized.
- Focuses, reorders, adds, and removes windows from an active stack.
- Switches the current browser window from a small attached drawer widget.
- Lets the drawer attach to the top, bottom, left, or right edge of the browser window.
- Keeps the drawer clear of rounded macOS window corners while dragging around the window boundary.
- Supports widget visibility, appearance, color palette, placement, preview, shortcut, and Accessibility settings.
- Exposes lightweight stack controls from the menu bar.

Closed browser windows are not shown. Stacker only switches between windows that are currently open.

## Requirements

- macOS 15.0 or newer.
- Xcode with the macOS SDK.
- Chrome, Brave, Safari, Edge, or Firefox with at least two open windows.
- macOS Accessibility permission for Stacker.

Accessibility permission is required because Stacker inspects, focuses, moves, resizes, and observes windows that belong to supported browsers. The app may also use System Events fallback behavior when Accessibility does not expose enough window data.

## Build And Run

Build from the command line:

```sh
xcodebuild -project stacker.xcodeproj -scheme stacker -configuration Debug build
```

Build and launch the local debug app:

```sh
script/build_and_run.sh
```

The helper builds into `/private/tmp/stacker-derived` with code signing disabled, then opens the app.

Useful helper modes:

```sh
script/build_and_run.sh --verify
script/build_and_run.sh --logs
script/build_and_run.sh --telemetry
script/build_and_run.sh --debug
```

The first launch will need Accessibility approval in System Settings before stack discovery and window control can work.

## Product Scope

In scope:

- Live stacks, not saved spaces.
- Chrome, Brave, Safari, Edge, and Firefox browser windows.
- Normal, like-sized browser windows.
- A main Stacker window for setup and stack controls.
- A compact drawer widget attached to each active stack's browser window.
- Clear permission onboarding for Accessibility and Automation behavior.

Out of scope for now:

- Saved workspaces.
- Browser/profile launching.
- Browser session restoration.
- Arbitrary app window management.
- Mac App Store assumptions.

## Main Surfaces

### Stacker Window

The main window is both the admin surface and the settings surface. Its sidebar includes:

- `Settings`: widget appearance, color palette, edge, shortcut, preview, and Accessibility status.
- `Browsers`: detected supported browser windows and active browser stacks.

For a selected browser stack, the detail pane shows stack status, linked windows, available windows, widget visibility, reset controls, and turn-on/turn-off actions.

The admin view refreshes browser discovery when it appears and when the selected browser changes. Before a stack is turned on, the `Ready To Link` rows are scoped to the selected browser process so Chrome, Brave, Edge, Safari, and Firefox windows do not bleed into each other. For active stacks, linked windows can be removed from the stack or reordered by dragging rows; the row badges use the same color assignments as the attached widget dots.

### Attached Widget

Each active stack can show a drawer-style widget attached to the browser window. The widget:

- starts visible by default;
- can attach to any window edge;
- can be dragged around the window boundary;
- uses dim inactive window dots and a larger active dot;
- supports widget-only `System`, `Light`, and `Dark` appearance modes;
- uses the selected dot palette from settings.

The drawer is meant to feel attached to the browser window, not like a separate floating utility window.

### Menu Bar

The menu bar exposes browser window status, stack toggles, widget visibility, settings access, refresh, and quit.

## Architecture

Stacker is a SwiftUI/AppKit macOS app.

- `stacker/stackerApp.swift`: app entry point, main window, menu bar extra, commands, and settings scene.
- `stacker/ContentView.swift`: runtime coordinator view for discovery, sessions, notifications, overlay startup, and permission flow.
- `stacker/MainWindowView.swift`: main window UI for settings, eligible browser apps, stack controls, linked windows, and available windows.
- `stacker/OverlayShortcutSettingsView.swift`: widget settings and live preview.
- `stacker/OverlayRuntime.swift`: AppKit panel controllers and SwiftUI drawer/widget views.
- `stacker/StackOverlaySupport.swift`: overlay display modes, placement, palettes, models, and shared widget support.
- `stacker/WindowStackController.swift`: core stack engine for alignment, observation, focusing, movement, resizing, and regrouping.
- `stacker/WindowAttachmentEngine.swift`: geometry helper for attached overlay positioning.
- `stacker/stacker/WindowDiscoveryService.swift`: window discovery through Accessibility with fallback behavior through System Events.
- `stacker/WindowScriptBridge.swift`: AppleScript bridge for System Events window reads, frame changes, and focus actions.
- `stacker/BrowserSupport.swift`: supported-browser detection and browser window-title normalization.
- `stacker/StackRuntimeCoordinator.swift`: active stack session creation and overlay state refresh.
- `stacker/StackerSessionCoordinator.swift`: stack order, overlay mode, add/remove behavior, and reset behavior.
- `stacker/SidebarSnapshotBuilder.swift`: main-window sidebar and detail snapshot generation.
- `stacker/StackerWorkspaceController.swift`: eligible app tracking, selection state, permissions, and discovery errors.

## Distribution Status

Stacker currently builds as a local macOS app, but it is not ready for Mac App Store submission.

The main blocker is entitlement compatibility. The core behavior depends on Accessibility control of other apps and Apple Events/System Events fallback behavior, while Mac App Store apps are required to use App Sandbox. Direct distribution with Developer ID signing, Hardened Runtime, notarization, and clear permission onboarding is the more realistic path.

See [docs/distribution-readiness.md](docs/distribution-readiness.md) for the current distribution assessment and [docs/compatibility-matrix.md](docs/compatibility-matrix.md) for release validation tracking.

## Current Cleanup Priorities

- Test browser window-title detection across real Chrome, Brave, Safari, Edge, and Firefox title variants.
- Tighten widget edge and corner behavior across multi-monitor setups and different window sizes.
- Add focused regression tests for stack/session logic that can run without controlling real apps.
- Add signing and entitlement files for the chosen distribution channel.
- Maintain the compatibility matrix for each supported browser, multi-monitor, Spaces, fullscreen, minimized windows, and wake-from-sleep behavior.
