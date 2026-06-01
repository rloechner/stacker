# Contributing to Stacker

Thanks for your interest in Stacker! This started as a personal tool for my own browser workflow and is now open source.

## Project Philosophy

Stacker is deliberately narrow in scope: it helps you stack multiple windows from the same browser into one live, synchronized group with an attached switcher widget. It does **not** aim to be a general window manager, workspace saver, or cross-app automation tool.

Because the scope is tight, feature requests that expand the mission significantly are likely to be declined.

## Reporting Issues

When you file a bug, please include:

- macOS version (e.g., 15.4.1)
- Browsers involved (Chrome, Brave, Safari, Edge, Firefox, Orion, DuckDuckGo Browser, Dia, BrowserOS, Vivaldi)
- Whether the problem occurs via the Accessibility path or falls back to System Events / AppleScript
- Reproduction steps, especially anything involving:
  - Full-height browser windows
  - Multiple displays
  - macOS Spaces
  - Wake from sleep
  - Minimized or fullscreen windows

The more specific you can be, the faster I can help.

## Development Setup

The easiest way to build and run during development:

```sh
script/build_and_run.sh
```

Useful variants:

```sh
script/build_and_run.sh --debug     # attach lldb
script/build_and_run.sh --logs      # stream unified logging
script/build_and_run.sh --verify    # just build and verify
```

You'll need macOS 15.0+ and Accessibility permission granted to the debug build the first time you run it.

## Testing Expectations

Before submitting a pull request, please manually test the affected flows, especially:

- Creating and using stacks with full-height (top-to-bottom) browser windows
- Dragging the widget around the perimeter on both normal and full-height windows
- **Multi-monitor setups (critical for v1 open-source release)**, including mixed laptop Retina + external non-Retina (or any differing resolution/size) displays:
  - Move the browser window + attached widget between screens of differing backing scales. Verify (a) crisp rendering (no scale artifacts) and (b) correct re-attachment on the destination. **For Chrome stacks, specifically exercise the new explicit anchor-driven full re-render**: during the cross-res move, watch for the `[Stacker] ANCHOR-RES-CROSS full re-render trigger` log; the widget must perform a complete clean-slate re-render (`fullAnchorResolutionChangeReset`) from the fresh AX rect / new window coordinates (orderOut, zero state, smart initial from fresh rect, strong rebuilds + settlement passes) rather than carrying stale deltas.
  - **The key steady-state test**: With the browser window already resident (or moved and left) on the *smaller / lower-resolution secondary monitor*, turn the stack **on** (or toggle it off then back on). The widget **must** attach correctly — correct side, snug to the window (no detachment, no bad overlap with corners on full-height windows, no over-clamping) — using automatic placement. **No manual "Reset Widget Position" may be required.** This exercises the full final mechanism: the anchor-driven full re-render path (for moves) + home-screen mismatch guard + smart initial `preferredInitialDockPositionAndSide` logic now invoked from `startTracking` and recurring `syncVisibility` (in addition to the robust re-home path in `handleDisplayMetricsChanged` on live screen-change notifications).
  - Full coverage is in `docs/testing-multi-display.md`, including the higher-to-lower resolution move, steady-state residence, and ANCHOR-RES-CROSS / full re-render checks for Chrome moves. See also `docs/compatibility-matrix.md` for supported-browser notes.
  - Bidirectional moves, custom user-dragged widget positions, full-height windows, and controls drawer open during transitions must all continue to work cleanly on the smaller monitor. The anchor-driven complete re-render ensures fresh-from-coordinates behavior precisely on Chrome cross-res moves.

This multi-monitor reliability (especially permanent residence on secondary displays) is now a validated strength of the floating widget and closes a long-standing class of real-user bugs. Contributors with mixed-display rigs are the most valuable testers here.
- Switching Spaces while a stack is active
- Wake-from-sleep recovery

## Pull Requests

- Small, focused changes are strongly preferred.
- Please run the app and verify the change works in real browser windows (not just unit tests — there aren't many yet).
- If you're making a larger change, open an issue first so we can discuss direction.

## License

Stacker is released under the MIT License. By contributing, you agree that your contributions will be licensed under the same terms.

---

Maintenance is best-effort. I may not always have time to review PRs quickly. Thank you for understanding, and for helping make Stacker better for everyone who lives in multiple browser windows.
