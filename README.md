# Stacker

Stacker is a native macOS utility that turns multiple open web browser windows into one live window stack.

It is inspired by Arc's spaces workflow: separate browser contexts can feel like separate workspaces without keeping every browser window visible at once. Stacker applies that idea at the macOS window level. Open two or more browser windows, turn on a stack, and switch between those live windows from a compact drawer attached to the active browser window.

Stacker is intentionally narrow. It does not launch missing browsers or profiles, recreate browser sessions, restore arbitrary workspaces, or manage every app on the system. It coordinates browser windows that already exist.

If Stacker saves you time every day, consider [buying the developer a coffee](https://buymeacoffee.com/rloechner).

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

**Multi-monitor guarantee**: The widget now correctly and automatically attaches (and re-homes on the fly) for any mix of monitor sizes/resolutions. Users with laptop + external setups can confidently leave a stack running with its widget resident on the smaller secondary display; the explicit **anchor-driven full re-render** (fresh converted AX rect backing scale vs. `lastAnchorFrame` detection in the normal sync path, triggering complete clean-slate `fullAnchorResolutionChangeReset` using the new window coordinates as sole input) plus the home-screen mismatch guard + preferredInitial logic on startTracking / recurring sync plus the re-home path ensure production-quality attachment without manual intervention. This anchor-driven complete re-render from fresh AX is the production solution for Chrome stack moves across mixed-res monitors. See Recent Fixes, docs/compatibility-matrix.md, and the test plan in docs/testing-multi-display.md for the full four-layer mechanism (INVESTIGATOR / CODER / TESTER collaboration).

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

## Getting Stacker

Stacker is open source and free. You have two ways to run it:

### 1. Download a notarized DMG (easiest for most people)
Pre-built, signed, and notarized releases will be attached to the GitHub Releases page. These are the recommended way to try Stacker without installing Xcode.

### 2. Build from source
Developers and people who want the absolute latest can build directly:

```sh
script/build_and_run.sh
```

The script builds a debug version into `/private/tmp/stacker-derived` (unsigned, for local use) and opens it. See the [Build And Run](#build-and-run) section for more options, including logging and verification modes.

The first time you run any version you will be prompted for Accessibility permission (required for window inspection and control) and may see a one-time Automation prompt.

See [docs/distribution-readiness.md](docs/distribution-readiness.md) for the technical reasoning behind the distribution choices and [docs/compatibility-matrix.md](docs/compatibility-matrix.md) for current browser validation status.

## Current Focus Areas

These are the areas where improvements and additional validation are most valuable:

- Expand real-world testing coverage (especially Firefox and post-sleep recovery) and keep the compatibility matrix honest.
- Multi-monitor widget reliability on mixed-resolution setups (including the explicit anchor-driven full re-render for live Chrome stack moves across resolution boundaries, plus steady-state attachment when leaving stacks on smaller secondary monitors) is now fully resolved and production-ready via the four defense layers (see Recent Fixes and the detailed story in docs/compatibility-matrix.md). Focus has shifted to other polish areas.
- Add a small number of focused unit tests for the pure session and ordering logic (no real browsers required).
- Maintain clear documentation so new users can build from source or run a DMG with minimal friction.
- Continue refining the attached widget and main-window admin experience for clarity and polish.

## Recent Fixes

- **Multi-monitor / multi-resolution floating widget reliability (the hardest real-world edge for v1 open-source readiness):** The attached drawer widget now reliably attaches, re-homes, and maintains correct positioning on *any* combination of monitor sizes and resolutions — including the critical case of permanent / steady-state residence on smaller secondary lower-resolution displays (e.g., MacBook Retina + external 1080p) with no manual "Reset Widget Position" required. This closes a long-standing class of bugs where the widget would end up wrong-side, detached, overlapping rounded corners, or over-clamped after cross-screen moves or when stacks were started/left on secondary monitors.

  The complete mechanism (identified by INVESTIGATOR, implemented by CODER with TESTER's exhaustive validation plan in `docs/testing-multi-display.md`; now four coordinated defense layers) features the **new explicit anchor-driven full re-render as the production solution for Chrome stack moves across mixed-res monitors**:
  - **Anchor-driven full re-render (dominant explicit path for live moves)**: In the normal fresh-AX state path inside `syncVisibility` (OverlayRuntime.swift), the code explicitly detects when the Chrome anchor window has crossed resolution screens by comparing `backingScaleFactor` of the newly converted fresh AX rect (via `referenceScreen`) against the scale implied by the previous `lastAnchorFrame`. Delta > 0.05 triggers `fullAnchorResolutionChangeReset` using the *fresh AX rect as sole authoritative input*: zeros all in-memory positioning state (offsets, deltas, `lastAnchorFrame`, `needsReanchor...`), forces smart dock/side via `preferredInitialDockPositionAndSide(for: freshConvertedAnchor)`, `orderOut` panels for clean slate, pure-from-fresh `resolveAttachment` + full `setFrame`, three rounds of strong rebuilds (`invalidatePanelRendering`, `hostingView.forceFullRebuildAndDisplay()`, layer/display passes on both main + controls panels), then two delayed settlement passes (0.12s + 0.42s) that re-sync scales, rebuild, and `syncVisibility`. This delivers a *true complete re-render from the new window coordinates*.
  - **Robust re-home + home-screen mismatch guard** on display metrics / `didChangeScreenNotification` (in `handleDisplayMetricsChanged` for both controllers) and the lightweight runtime `rehomeIfCurrentResolvedIsBad` guard (called from `syncVisibility` and `startTracking`): surgically zeros poisoned offsets when screen mismatch or bad/clamped origin detected, restores preferred dock, schedules settle passes.
  - **Smart initial logic on `startTracking` + birth-time guard**: inspects current anchor home screen vs. loaded persisted offsets; on mismatch zeros and invokes `preferredInitialDockPositionAndSide` for the *actual* residence screen.
  - Supporting pieces (referenceVisibleFrame / referenceScreen with panel hint, clamping, resolvedDockPosition, scale sync) always derive from the live anchor + destination screen.

  Full details, code comments (the "NEW ANCHOR-DRIVEN FULL RE-RENDER DETECTION" block and `fullAnchorResolutionChangeReset` docstring), and the contributor test matrix live in `docs/compatibility-matrix.md` (multi-monitor section) and `docs/testing-multi-display.md`. The widget (with the anchor-driven complete re-render for moves) is now production-ready for everyday mixed-monitor users. (See also the strengthened notes in the Attached Widget section above and in CONTRIBUTING.md.)

## Contributing & Support

Stacker is open source under the MIT license. Contributions are welcome, but please read [CONTRIBUTING.md](CONTRIBUTING.md) first — this is a personal tool with best-effort maintenance.

If you find Stacker genuinely useful, you can support its development here:

- [Buy Me a Coffee](https://buymeacoffee.com/rloechner)
- Star the repository (it genuinely helps visibility)

Bug reports, especially around edge cases with full-height windows, multiple monitors, and browser title handling, are very appreciated.
