# Compatibility Matrix

This document records real-world testing of Stacker against different browsers and macOS behaviors. Stacker is a narrow, personal tool focused on turning multiple open windows from the *same* browser into one live, synchronized stack (inspired by Arc Spaces but without requiring Arc).

Because the value depends on reliable window observation, movement, and focus, we are explicit about what has been validated and what is still "works for the author on their machine."

## Ratings

- **Good** — Core flows (create stack, switch, move/resize sync, reorder, add/remove, widget interaction) work reliably on the author's primary machine.
- **Partial** — Usable for daily driving, but one or more important scenarios are unreliable or require workarounds.
- **Limited** — Basic stacking works, but significant caveats (title handling, certain window states, recovery behavior).
- **Untested** — No meaningful validation yet. Not recommended for production use with this browser.

## Author's Testing Summary (as of May 2026)

**Tested by author on macOS 15.x (Sequoia/Tahoe-era):**

- **Chrome** — Primary daily driver. Full core flows validated. **Good**
- **Brave** — Chromium-based. Full core flows validated. **Good**
- **Microsoft Edge** — Chromium-based. Full core flows validated. **Good**
- **Safari** — Native WebKit. Full core flows validated. **Good**
- **Firefox** — Full core flows validated (create, live sync, reorder, widget, etc.). Behaves well for Stacker's narrow purpose. **Good**

All five supported browsers now carry a **Good** rating for the documented core test cases.

**Wake-from-sleep behavior (all browsers):**  
Recent testing shows stacks generally survive sleep/wake with the widget still visible and functional. Transient inconsistencies can still occur; toggling the stack off and back on is a reliable recovery. This remains the most visible known limitation but is not a blocker for daily use.

**Multi-monitor, Spaces, full-height windows, and widget edge-dragging** have been exercised during normal use across the tested browsers.

## Supported Browsers

| Browser       | Rating     | Notes |
|---------------|------------|-------|
| Chrome        | Good       | Primary development and daily-use browser. Window titles, AX discovery, and move/resize observation are reliable. Named windows (Window > Name Window) are respected. |
| Brave         | Good       | Behaves like Chrome. Title normalization and AX attributes are consistent with other Chromium browsers. |
| Microsoft Edge| Good       | Behaves like Chrome. No unique issues observed in core stack operations. |
| Safari        | Good       | Native macOS browser. Stable window roles and titles. Widget attachment and synchronization work cleanly. |
| Firefox       | Good       | Full core flows validated (create stack, live sync on move/resize, reorder, add/remove, widget switching). Behaves comparably to the Chromium browsers for Stacker's use case.<br><br>Known caveats (same as other browsers + Firefox-specific):<br>• Picture-in-Picture windows and certain small UI elements can appear in Accessibility window lists — user may need to manually remove them once.<br>• Wake-from-sleep recovery may still be required (documented limitation). |

## Non-Browser Apps (Out of Scope)

Stacker is intentionally limited to browser windows from a single process. The following are listed only to set expectations:

- Finder, Terminal, VS Code, Slack, Notes, etc. — **Untested and unsupported**.
- Stacker will not offer them as stackable targets and makes no claims about behavior with non-browser windows.

## Known Limitations (Documented)

- **Wake from sleep**: Stacks can enter an inconsistent state. Recovery is usually "turn the stack off then on again" for the affected browser. This is the most visible post-sleep issue.
- **Picture-in-Picture windows (especially Firefox)**: May be discovered as normal windows. User must manually remove them from the stack.
- **Very dynamic title changes**: Heavy YouTube/Slack/CRM use can cause noisy title updates. Stacker normalizes titles but very rapid changes can still produce brief UI flicker in the widget or sidebar.
- **Full-screen / full-height windows**: Widget attachment and corner handling have extra logic; occasional clamping or manual "Reset Marker Position" may be needed.
- **macOS 15.0+ only**: The overlay widget uses APIs that do not exist on earlier releases.

## Release Rule for v1 and Beyond

The public repository and any pre-built DMGs will only claim "Good" support for browsers that have been actually tested by the author or have strong community confirmation.

Partial or Limited browsers will be clearly marked with caveats in the README and this matrix.

We will not market Stacker as a general window manager or universal workspace tool. It solves one specific workflow: multiple same-browser windows acting as live Arc-style Spaces.
