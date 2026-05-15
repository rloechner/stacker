# Contributing to Stacker

Thanks for your interest in Stacker! This started as a personal tool for my own browser workflow and is now open source.

## Project Philosophy

Stacker is deliberately narrow in scope: it helps you stack multiple windows from the same browser into one live, synchronized group with an attached switcher widget. It does **not** aim to be a general window manager, workspace saver, or cross-app automation tool.

Because the scope is tight, feature requests that expand the mission significantly are likely to be declined.

## Reporting Issues

When you file a bug, please include:

- macOS version (e.g., 15.4.1)
- Browsers involved (Chrome, Brave, Safari, Edge, Firefox)
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
- Multi-monitor setups
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
