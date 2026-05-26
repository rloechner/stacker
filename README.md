# Stacker

Stacker is a native macOS utility that turns multiple open browser windows into one live window stack.

Open two or more windows in a supported browser, turn on a stack, and use the attached widget to switch between those windows without spreading them across your desktop.

Stacker does not launch browsers, restore sessions, or manage every app on your Mac. It works with browser windows that are already open.

<img width="924" height="707" alt="Screenshot 2026-05-26 at 9 20 39 AM" src="https://github.com/user-attachments/assets/fd93ed68-9156-4440-8818-78533c990368" />

<img width="1274" height="1081" alt="Screenshot 2026-05-26 at 9 24 49 AM" src="https://github.com/user-attachments/assets/cbcea173-96d6-4dd9-ad3f-2bb7b67f9690" />

https://github.com/user-attachments/assets/c3a56b44-222a-4b38-b52f-bbfb2113c531

https://github.com/user-attachments/assets/03cd95aa-f807-4152-8bce-bf3f4bc86fa8

## What It Does

- Detects supported browsers with two or more open windows.
- Links browser windows into one stack.
- Keeps stacked windows aligned when the active window moves or resizes.
- Shows a compact widget attached to the active browser window.
- Switches, reorders, adds, and removes windows from a stack.
- Hides the widget when the browser is hidden and brings it back when the browser returns.
- Remembers widget placement globally across supported browsers.
- Handles sleep/wake, monitor changes, and mixed-resolution multi-monitor setups.
- Provides menu bar controls and a hard refresh command for recovery.

## Supported Browsers

Stacker currently supports:

- Google Chrome
- Brave Browser
- Safari
- Microsoft Edge
- Firefox
- Orion
- Orion RC
- DuckDuckGo Browser

Each browser needs at least two normal open windows before Stacker can create a stack.

## Requirements

- macOS 15.0 or newer
- Accessibility permission for Stacker
- A supported browser with at least two open windows
- Xcode if building from source

Accessibility permission is required because Stacker needs to inspect, focus, move, resize, and observe browser windows. Without it, Stacker cannot read or control browser window state.

## First Run

1. Open two or more windows in a supported browser.
2. Launch Stacker.
3. Approve Accessibility permission when prompted.
4. Return to Stacker after granting permission.
5. Select a browser in the sidebar.
6. Turn on the switcher.
7. Use the attached widget to switch between stacked windows.

If the browser list does not update after opening windows, use `Stacker > Hard Refresh Browsers`.

## Using Stacker

### Main Window

The Stacker window is the admin and settings surface. It shows:

- detected browsers;
- active stacks;
- linked windows;
- windows that can be added to a stack;
- widget visibility and reset controls;
- appearance, placement, palette, and shortcut settings.

The admin refreshes automatically when Stacker is focused, when supported browsers launch or quit, and when browser state changes. The visible refresh button was intentionally removed; hard refresh is available from the menu when recovery is needed.

### Attached Widget

The widget attaches to the browser window and can sit on the top, bottom, left, or right edge. Drag it around the window boundary to choose a placement.

The widget uses dots or labels for stacked windows:

- active windows appear emphasized;
- inactive windows stay available;
- minimized windows become a yellow circle with a dash and can be restored from the widget;
- fullscreen windows show a fullscreen marker and remain part of the stack, but are not used as widget anchors.

Right-click a window dot to focus, minimize, restore, or remove that window from the stack. Remove uses an `xmark`; minimize uses the macOS-style yellow dash state so the two actions are visually distinct.

### Menu Bar

The menu bar extra provides quick access to:

- open or hide Stacker;
- hard refresh browsers;
- hide or show widgets;
- turn stacks on or off;
- retry paused stacks;
- open settings.

## Known Limitations

- Stacker is focused on browser windows, not arbitrary Mac apps.
- Fullscreen browser windows are treated as recoverable stack members, but are not used for active widget anchoring in v1.0.
- Browser Accessibility behavior can vary by browser version and macOS release.
- Stacker does not save browser sessions or reopen closed windows.
- Public binary distribution still requires proper signing, packaging, and notarization.

## Build From Source

Build from the command line:

```sh
xcodebuild -project stacker.xcodeproj -scheme stacker -configuration Debug build
```

Build and launch the local debug app:

```sh
script/build_and_run.sh
```

Useful helper modes:

```sh
script/build_and_run.sh --verify
script/build_and_run.sh --logs
script/build_and_run.sh --telemetry
script/build_and_run.sh --debug
```

The helper builds into `/private/tmp/stacker-derived` with code signing disabled, then opens the app.

## Release Plan

The first public release is planned as `v1.0.0`.

Before publishing a downloadable binary, validate:

- code signing;
- hardened runtime settings;
- notarization;
- packaged `.dmg` or `.zip` install flow;
- Accessibility permission onboarding on a clean Mac.

For source-only release, the main remaining work is QA across supported browsers and common display setups.

## QA Checklist

Recommended manual test pass before release:

- create a stack in each supported browser;
- hide and show each browser;
- minimize and restore a stacked window;
- enter and exit fullscreen;
- sleep and wake the Mac;
- unplug external monitors and return to laptop mode;
- move a stack between mixed-resolution displays;
- turn a stack off and back on;
- verify global widget placement is remembered;
- use hard refresh after opening and closing browser windows.

## Project Structure

- `stacker/BrowserSupport.swift`: supported browser detection.
- `stacker/ContentView.swift`: runtime coordination, discovery, sessions, and notifications.
- `stacker/MainWindowView.swift`: admin window UI.
- `stacker/OverlayRuntime.swift`: attached widget panels and interactions.
- `stacker/StackOverlaySupport.swift`: widget models, placement, palettes, and shared UI.
- `stacker/WindowStackController.swift`: stack alignment, observation, focusing, and window state.
- `stacker/WindowAttachmentEngine.swift`: widget attachment geometry.
- `stacker/WindowScriptBridge.swift`: System Events fallback for window reads and focus.
- `stacker/stacker/WindowDiscoveryService.swift`: Accessibility-based window discovery.

## Contributing

Stacker is a personal open-source macOS utility. Issues and focused pull requests are welcome, especially around browser compatibility, display setups, and Accessibility edge cases.

Please read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request.

## Support

If Stacker is useful to you:

- star the repository;
- share a bug report with browser, macOS version, and reproduction steps;
- consider [buying the developer a coffee](https://buymeacoffee.com/rloechner).

## License

MIT. See [LICENSE](LICENSE).
