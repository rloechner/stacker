# Compatibility Matrix

Use this file to track which apps and window states are reliable enough for release.

## Ratings

- Good: core stack behavior works repeatedly.
- Partial: usable, but one or more important actions are unreliable.
- Blocked: app cannot be supported without a separate implementation path.
- Untested: not checked yet.

## Core Test Cases

For each app, test:

- discover app with two or more windows
- create a stack
- switch windows with `Command + \``
- move the active window and confirm the stack follows
- resize the active window and confirm the stack follows
- focus each window from the stack marker
- reorder windows
- remove one window
- add a removed window back
- hide/show stack markers globally
- hide/show the stack marker for that app
- test after minimizing one stacked window
- test after moving the stack to another display
- test after changing macOS Space
- test with fullscreen windows

## Apps

| App | Scenario | Rating | Notes |
| --- | --- | --- | --- |
| Chrome | Three profile windows, same size | Untested | Primary target use case. |
| Safari | Multiple windows/profiles | Untested | Check whether profile/window state exposes stable titles. |
| Finder | Multiple normal windows | Untested | Useful baseline for native AppKit windows. |
| Terminal | Multiple windows | Untested | Check behavior with tabs and window title changes. |
| VS Code | Multiple project windows | Untested | Electron target. |
| Slack | Multiple windows | Untested | Electron target with utility-style windows. |
| Notes | Multiple windows | Untested | Native app with smaller document windows. |

## Release Rule

The first public version should only claim support for apps and window states rated Good. Partial support can be documented as known limitations, but should not appear in marketing copy.
