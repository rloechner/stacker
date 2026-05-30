# Stacker

**⬇️ [Download Stacker v1.1.3 for macOS (DMG)](https://github.com/rloechner/stacker/releases/download/v1.1.3/Stacker-1.1.3.dmg)**

A tiny native macOS utility that turns multiple open browser windows into one live, aligned stack (with a handy widget for switching).

**Installation (30 seconds):**
1. Download the DMG above
2. Open it and drag **Stacker** into your Applications folder
3. Open Stacker from Applications → macOS will ask for Accessibility permission (System Settings → Privacy & Security → Accessibility → enable Stacker)

After updating, quit Stacker and toggle Accessibility off/on if macOS still shows permission enabled but Stacker does not detect it.

Works with Chrome, Brave, Safari, Edge, Firefox, Orion, DuckDuckGo Browser, Dia, and Vivaldi (needs 2+ normal windows open).

Signed and notarized for macOS Developer ID distribution.

Stacker is freeware and open source. You can also browse [all GitHub Releases](https://github.com/rloechner/stacker/releases) or build from source with Xcode.

Stacker does not launch browsers, restore sessions, or manage every app on your Mac. It works with browser windows that are already open.

<img width="924" height="707" alt="Screenshot 2026-05-26 at 9 20 39 AM" src="https://github.com/user-attachments/assets/fd93ed68-9156-4440-8818-78533c990368" />

<img width="1274" height="1081" alt="Screenshot 2026-05-26 at 9 24 49 AM" src="https://github.com/user-attachments/assets/cbcea173-96d6-4dd9-ad3f-2bb7b67f9690" />

https://github.com/user-attachments/assets/d4325b63-443a-4205-93d5-8e5f99e6d7d7


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
- Dia
- Vivaldi

Each browser needs at least two normal open windows before Stacker can create a stack.

## Requirements

- macOS 15.0 or newer
- Accessibility permission for Stacker
- Automation permission if macOS prompts for System Events access
- A supported browser with at least two open windows
- Xcode if building from source

Accessibility permission is required because Stacker needs to inspect, focus, move, resize, and observe browser windows. Without it, Stacker cannot read or control browser window state.

## First Run

1. Open two or more windows in a supported browser.
2. Launch Stacker.
3. Approve Accessibility permission when prompted.
4. Approve Automation permission if macOS prompts for System Events access.
5. Return to Stacker after granting permission.
6. Select a browser in the sidebar.
7. Turn on the switcher.
8. Use the attached widget, macOS `Command-\`` window cycling, or `Control-1` through `Control-9` to jump directly to a stacked window slot.

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

You can switch through the stacked browser windows with the widget or with the native macOS `Command-\`` shortcut. Stacker keeps the windows aligned so that standard same-app window cycling feels more like tabbing through one desktop slot.

Press `Control-1` through `Control-9` to jump directly to a specific stacked window (first dot = 1, second = 2, and so on). These shortcuts only apply when a stacked browser is frontmost, so they do not replace the browser's `Command-1` through `Command-9` tab shortcuts. Change the modifier or turn stack jump off in Settings.

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
- Unsigned or locally built copies may trigger extra macOS security prompts.

## For Developers

### Build From Source

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

### Releasing

Maintainers can create a signed, notarized DMG with:

```sh
script/release_dmg.sh
```

See [docs/releasing.md](docs/releasing.md) for the full Developer ID release checklist.

### QA Checklist

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
