# Multi-Resolution Screen Transition Test Plan

This document provides a detailed, reproducible manual test checklist for validating correct widget (overlay panel) rendering when Stacker's attached drawer or suggestion overlays cross between physical displays that have mismatched `backingScaleFactor` values (e.g., internal Retina 2x laptop display + external 1080p/1x monitor, or mixed 2x/3x HiDPI setups).

**Bug context (pre-fix):** The floating `NSPanel`s (`StackOverlayPanelController` + `CombineOverlayPanelController` in `OverlayRuntime.swift`) driven by `TransparentHostingView` (SwiftUI `NSHostingView`) and `TransparentContainerView` would exhibit scale artifacts (blurry/pixelated text, dots, gradients, shadows, incorrect sizes) after the panel or its attached browser window crossed screens. Existing `didChangeScreenNotification` / `didChangeBackingPropertiesNotification` observers + `invalidateOverlayRendering` calls were insufficient without explicit recursive `CALayer.contentsScale` propagation synchronized to the target screen's `backingScaleFactor`. A subsequent residual class of bugs remained even after transition fixes: incorrect attachment (wrong side, detached, overlapping, or clamped) when the widget was *created on* or *left/settled permanently on* a smaller/lower-resolution secondary monitor.

**Fix summary:**
- **Iteration 1 (scale sync):** Added private helpers `syncBackingScale(for:)`, `syncBackingScale(in:)`, `applyContentsScale(_:to:)` plus `viewDidChangeBackingProperties()` overrides + `syncBackingScaleIfNeeded()` on both `TransparentHostingView` and `TransparentContainerView` (lines ~359-564). Plus `syncLayerBackingScales()` helpers. These ensure `contentsScale` is pushed down through layers/sublayers.
- **Iteration 2 (re-home positioning):** Stronger "re-home" reset inside the two `handleDisplayMetricsChanged` methods. Detailed cross-resolution comments, zeroing of stale user drag offsets (`lastAnchorFrame`, `previousBackgroundDragDelta`, `horizontalAnchorOffset`, `verticalAnchorOffset` for Stack; `anchorOffset` for Combine) + `needsReanchorAfterScreenChange` flag (set only on `didChangeScreenNotification` via dedicated screenChangeHandler), restoration of preferred dock, plus two `DispatchQueue.main.asyncAfter` settle follow-ups (0.08s + 0.25s) that re-invoke sync + `syncVisibility()`. This ensures the widget uses the *destination screen's* geometry + fresh automatic placement (`resolvedDockPosition`, `clampedOrigin`, `proposedOrigin`, etc.) instead of poisoned deltas from the source screen. (Main handler ~3230-3274; Combine handler ~3926-3961.)
- **Iteration 3 (steady-state re-home guard + smart-initial logic + home screen mismatch guard):** Extended robust re-home and smart initial placement (leveraging `preferredInitialDockPositionAndSide(for:)` + offset zeroing + `horizontalSide` bias) to the `startTracking(...)` entry points on both controllers and to the normal recurring `syncVisibility()` / `resolveAttachment()` / `resolveCurrentAttachment()` paths. Introduced a lightweight runtime "home screen mismatch guard" (invoked after AX coordinate conversion and `referenceVisibleFrame`/`referenceScreen` selection inside the resolve engine and OverlayRuntime sync). The guard detects when the computed home screen for the anchor (based on intersect with `NSScreen.screens`) differs from the actual screen the panel currently resides on (`panel.screen` or its visible intersection / center), which occurs precisely in "create-while-on-small" and "left/settled-on-small" steady-state scenarios (no further `didChangeScreen` events fire once movement stops). On detection: zero in-memory offsets for the current resolve (preserving persisted prefs safely or resetting when appropriate), force the smart preferred initial dock/side for the *actual* residence screen's geometry, re-resolve attachment, and apply. Also hardened reference screen selection to accept current panel location as a tie-breaker hint. This closes the final residual bug reported by users even after widget is "left" on the smaller lower-res monitor. (Changes primarily in `OverlayRuntime.swift` startTracking, handle..., syncVisibility, plus `WindowAttachmentEngine.swift` reference helpers.)
- **Iteration 4 (anchor-driven full re-render from fresh window coordinates on cross-res anchor moves):** Added explicit "ANCHOR-RES-CROSS" detection *inside the normal recurring `syncVisibility` fresh-state path* (right after the initial `resolveAttachment` that converts the live AX rect, before the lightweight `rehomeIfCurrentResolvedIsBad` guard). Compares `backingScale(forFrameInScreenSpace:)` (via `referenceScreen` + `NSScreen.backingScaleFactor`) of the *freshly converted AX anchor rect* (from the moved Chrome window) against the scale implied by the previous `lastAnchorFrame`. On detected cross (`abs(oldScale - newScale) > 0.05`), emits the clear log `[Stacker] ANCHOR-RES-CROSS full re-render trigger for \(appName): ...` and invokes `fullAnchorResolutionChangeReset(freshConvertedAnchor:..., state:...)`. This performs a *true complete re-render* using the fresh AX rect as the *sole* authoritative input: orderOut both panels, zero *all* in-memory positioning state (offsets, deltas, lastAnchorFrame, flags), force smart `preferredInitialDockPositionAndSide` (and dock/side) computed on the fresh anchor + destination screen's visibleFrame, pure re-resolve with zeroed state, full `setFrame(..., display: true)`, 3 full rounds of `invalidatePanelRendering` + hosting views layout/display/layer.setNeedsDisplay + `forceFullRebuildAndDisplay()` (rootView self-assign + complete SwiftUI refresh) on both hosting views + containers + shadows, capture fresh lastAnchorFrame, plus two delayed extra passes (0.12s + 0.42s) that re-sync scales + rebuild + `syncVisibility`. Persisted UserDefaults offsets are left untouched (re-applied only on future returns to the source screen). This is the dominant explicit "complete re-render from fresh window coordinates" mechanism for Chrome (primary) anchor window moves across Retina ↔ non-Retina. It complements the prior lightweight re-home + guard layers and addresses residual attachment failures even after settle on the destination. (Detection ~3073-3089; implementation + extensive comments ~3754-3858; `forceFullRebuildAndDisplay` helper ~495.)

**How to confirm fix vs. before:**
- **Before (scale artifacts):** After dragging ... blurry/low-res visuals.
- **Before (positioning, Iteration 2 specific):** After first-round scale fix, widget would draw at correct scale but become *positionally orphaned* — floating detached high up (or otherwise wrong global coordinates) instead of re-attaching to the browser on the destination screen (especially noticeable on higher-res → lower-res moves). Screenshot symptom: widget suspended in space above the target browser window on the lower-DPI screen.
- **Before (steady-state Iteration 3 specific):** Widget would correctly re-home *during* a higher→lower drag transition (via notification-driven reset), but once the browser+widget were left settled on the smaller/lower-res monitor, or a new stack was created with the browser already resident there, attachment would be wrong (wrong rail/side, detached, overlapping browser/menu area, or clamped using stale large-monitor deltas or primary-screen visibleFrame). "Reset Position" or full toggle would workaround it; normal operation and subsequent syncs would not self-correct. Guard never fired.
- **Before (Iteration 4 / anchor cross specific):** Even after Iterations 2+3, certain live drags of the Chrome *anchor window* itself across resolution boundaries (or post-settle AX updates on the moved anchor) could leave stale `lastAnchorFrame` / prior-res state influencing resolve, or produce incomplete re-draws, resulting in mis-attachment on the destination despite the guards. The explicit scale-cross detection on fresh AX + full clean-slate re-render from the new coordinates alone was absent.
- **After (full):** Widget remains crisp *and* snaps to a clean attached position on the destination screen (using fresh automatic dock logic after offset reset) *both during transitions and in steady-state*. Creation while on small monitor, permanent residence after move, toggles, and normal timer-driven syncs all produce correct attachment via the mismatch guard + smart-initial. For Chrome anchor crosses specifically, the ANCHOR-RES-CROSS path guarantees a complete re-render using *only* the brand-new AX-reported rect. No manual Reset required. Subsequent drags or "Reset Position" behave as a fresh placement on the current screen.
- Use screenshots: capture on source, drag across (higher→lower especially), capture on target. Zoom for both sharpness and attachment position. Advanced: use view debugger / breakpoints / logs to confirm offsets zeroed, guard messages emitted, placement derives from destination `NSScreen.visibleFrame` / AX frame rather than stale `horizontal/verticalAnchorOffset` or primary screen.
- For steady-state: create or settle on small, then inspect `panel.screen` vs. the screen returned by `referenceVisibleFrame` / `NSScreen.screens.first(where: intersects...)`; confirm guard path taken on mismatch and correct final origin.
- For the new anchor-driven path: during Chrome window cross-res drags, confirm the distinctive ANCHOR-RES-CROSS log, the aggressive multi-round rebuilds (forceFullRebuildAndDisplay etc.), and final position computed purely from the fresh AX rect on the destination (with prior-res state fully cleared in-memory).

## Prerequisites / Setup
- macOS 15.0+ (Sequoia or later) with Xcode.
- A multi-monitor setup with at least two displays of differing scale factors (most common dev setup: MacBook internal Retina display + external monitor set to non-Retina / "more space" scaling, or "looks like 1080p").
  - **Emphasize testing the higher-resolution source → lower-resolution target direction** (the specific vector that exposed the orphaned-widget positioning bug).
  - **For final steady-state coverage (Iteration 3):** Focus on creation-while-resident and "left permanently" scenarios on the *lower-resolution secondary monitor*. The minimal actionable hardware for contributors is a laptop (high-res internal) + exactly one external monitor of different scale — no need for 3+ screens.
  - **For Iteration 4 Chrome anchor cross coverage:** The same mixed Retina + non-Retina hardware; focus on dragging the *Chrome browser window title bar* (the anchor) itself across the boundary while a stack is active.
  - Virtual displays via apps (e.g., BetterDisplay, DisplayLink) or macOS's "Detect Displays" with one scaled differently can substitute if no second physical monitor.
  - 3+ screens or mixed 1x/2x/3x is ideal for edge coverage.
- At least one supported browser with ≥2 windows open (Chrome/Brave/Safari/Edge/Firefox recommended for primary validation).
- Stacker built from source (`script/build_and_run.sh` or Xcode) with Accessibility permission granted.
- Grant Screen Recording / Accessibility if needed for observation (usually just Accessibility).
- Dock position: test with Dock on left, bottom, and right (affects full-height clamping).
- Preferred: two browser windows sized identically, one "full-height" (tall, touching top/bottom menu bar area).

**Recommended test matrix (repeat for each major browser):**
- Chrome (primary — required for the new ANCHOR-RES-CROSS subsection)
- Brave
- Safari
- Edge
- Firefox (note PiP caveat)

## Core Test: Cross-Screen Drag of Browser Window + Attached Widget
1. Launch Stacker, grant permissions, open 2+ browser windows from the same browser, create a stack, ensure the attached widget (capsule with dots + controls drawer) is visible and attached (default edge, e.g., left or top).
2. Position the primary browser window entirely on Screen A (e.g., Retina internal, 2x).
   - Verify widget looks crisp (sharp text, correctly sized dots, proper gradient sheen and shadow).
3. Slowly drag the browser window (by its title bar) across the screen boundary toward Screen B (e.g., external 1x 1080p).
   - Observe live: the widget should follow the window in real time without jumping or disappearing.
4. Once the browser window (and thus the attached widget) is fully on Screen B:
   - **Visual checks (zoom 200-400% or use pixel inspection):**
     - Text/labels in widget and drawer: sharp, no blur or anti-aliasing artifacts.
     - Colored dots: correct radius, crisp circles, no pixelation or "fuzzy" edges. Active dot larger as expected.
     - Gradients / materials (regularMaterial + linear overlays in Combine/Stack views): correct fidelity, no low-res banding.
     - Shadows: soft and correctly rendered at native density.
     - Overall capsule: no stretching, correct border radius, no "double vision" or scale mismatch.
     - Hit testing: click dots to switch windows, drag the widget handle around the browser perimeter, open/close the controls drawer. All interactions should feel precise (no offset or missed taps due to scale).
5. Drag the browser window back to Screen A. Re-verify crispness on return.
6. Repeat while the stack is in different modes:
   - Horizontal vs. vertical attachment (dockPosition: left/right/top/bottom).
   - Widget visibility toggled, appearance (System/Light/Dark).
   - Label mode (dots-only vs. numbered) and density modes.
   - With controls drawer pinned open vs. closed.
7. **Recovery paths:**
   - While widget is on mismatched screen, toggle the stack off then on (via main window or menu bar). Widget should re-attach crisp.
   - Use "Reset Marker Position" in settings.
   - Switch Spaces (full-screen or desktop switch) while widget is on the non-native screen.
   - Sleep the Mac (or close lid), wake, and check widget on current screen.
   - Minimize/restore the browser window, then move across screens.

## Higher → Lower Resolution Move (the orphaned widget case)

**Dedicated coverage for the exact user-reported failure mode after Iteration 1 (scale sync).**

**Symptom (pre-Iteration 2, as shown in user screenshot):** The widget would correctly update its `contentsScale` (no blur/pixelation) but would compute its origin using stale in-memory drag offsets (`horizontalAnchorOffset`, `verticalAnchorOffset`, `previousBackgroundDragDelta`, `lastAnchorFrame`) that were relative to the *higher-resolution source screen's* visibleFrame / AX coordinates. Result: the widget landed "orphaned" — floating detached high up (or otherwise wildly offset) above or beside the browser window on the *lower-resolution destination screen*, instead of cleanly re-attaching via automatic placement.

**Implementation mechanism (Iteration 2):**
- `needsReanchorAfterScreenChange` flag (declared per-controller; set to `true` *only* in the `didChangeScreenNotification` observer path, not on pure `didChangeBackingPropertiesNotification` or `didChangeScreenParametersNotification`).
- In both `handleDisplayMetricsChanged`:
  - Zero the poisoned values (`lastAnchorFrame = nil`; `previousBackgroundDragDelta = .zero`; `horizontalAnchorOffset = 0`; `verticalAnchorOffset = 0` for the main widget; `anchorOffset = .zero` for Combine/suggestion).
  - Restore `dockPosition` to `preferredDockPosition`.
  - Then proceed to `resize...` + `invalidate...` + `syncVisibility()`, which now runs fresh `resolveCurrentAttachment` / `referenceScreen` / `resolvedDockPosition` / `clampedOrigin` / `proposedOrigin` against the *current destination screen's* geometry.
- Rich explanatory comments in the Stack handler describing "stale/poisoned" offsets from higher-res source, "orphaned in the global void", and the intent to let automatic logic "find the right coordinates to live on" the new screen.
- Two deferred `DispatchQueue.main.asyncAfter` passes (0.08 s and 0.25 s) in *both* handlers to let AX reports, `NSScreen.screens`, panel backing, and trackingTimer settle before final re-home/sync.
- Non-screen display events leave user offsets intact (preserves intentional custom placement).

**Success criteria:** After dragging the browser window (and widget) from higher-res screen fully onto the lower-res screen, the widget snaps to a clean, attached position on a sensible edge (typically the default top-left or best-fit rail per `resolvedDockPosition` logic) relative to the browser. No floating detachment. Subsequent drags or "Reset Position" behave as a fresh placement on the new screen. The widget remains crisp (from Iteration 1).

**Exact test steps for this failure mode:**
1. Configure a higher-resolution source screen (e.g., Retina 2x internal) and lower-resolution target screen (e.g., external 1x or scaled 1080p). Confirm `backingScaleFactor` difference via code inspection or System Information if needed.
2. Launch Stacker, create a stack with the browser window on the *higher-res source screen*. Optionally perform a perimeter drag of the widget to a non-default position (this populates non-zero `horizontal/verticalAnchorOffset` and `previousBackgroundDragDelta` relative to the high-res context).
3. Verify the widget is visibly attached and crisp on the source screen.
4. Slowly drag the *browser window title bar* from the higher-res screen across the boundary until the entire browser window (and attached widget) is fully on the *lower-res target screen*.
5. Observe the transition and final state on the destination screen:
   - The widget must not become positionally orphaned/floating detached (the pre-fix symptom).
   - It must re-attach cleanly to the browser using fresh automatic dock/attachment logic (not the old high-res deltas).
6. **Visual + behavioral checks on lower-res screen:**
   - Widget is snug against the browser edge (correct gap, no overlap with corners for full-height).
   - All prior crispness checks (dots, gradients, text, shadows, hit areas) still pass.
   - Click/switch dots, open controls drawer, drag the widget on the new screen — interactions are precise and relative to the current browser + screen.
   - Toggle the stack off/on or use Reset Position; it should re-attach sensibly (not inherit old poisoned state).
7. Drag the browser window back to the higher-res screen and repeat (bidirectional coverage).
8. Test variations:
   - With custom widget placement (offsets populated) vs. default.
   - Full-height windows on source.
   - With controls drawer open during the cross.
   - For the Combine suggestion overlay as well (its lighter `anchorOffset` reset).
9. **How to verify the offsets were reset for the new screen (advanced confirmation):**
   - Use Xcode view debugger or lldb on the running `StackOverlayPanelController` instance after the move: inspect `horizontalAnchorOffset`, `verticalAnchorOffset`, `previousBackgroundDragDelta`, `lastAnchorFrame` — they should be zeroed / nil (or freshly captured from the destination context).
   - Or add temporary logging in `captureUserAnchorOffset` / `handleDisplayMetricsChanged` and watch for reset on screen-change notifications only.
   - Observe that the final attached position on the lower-res screen matches what a brand-new stack (with zero offsets) would have chosen via `preferredDockPosition` + `resolvedDockPosition(for:..., preferredScreen:...)` rather than continuing the prior drag delta.

(Note: The above covers *transition* re-homing. The steady-state "left on the small monitor after the move" and "created directly on small" cases that survived Iteration 2 are covered in the dedicated section immediately below.)

## Steady-State Residence on Smaller / Secondary Lower-Resolution Monitor

**The exact residual user-reported scenario that survived Iteration 2 (see Investigator failure modes analysis).** The widget would re-home correctly *during* a higher-to-lower drag transition thanks to the `didChangeScreenNotification` + `needsReanchorAfterScreenChange` + async settle passes in `handleDisplayMetricsChanged`. However, once the browser window + widget were *left/settled permanently* on the smaller lower-resolution secondary monitor (or a new stack was created while the browser window was already positioned entirely on that small monitor), attachment would become or remain incorrect: widget on the wrong side/rail, detached/floating above or beside the browser, overlapping the browser content or menu-bar area, or clamped using stale offsets or the wrong (usually primary/large) screen's `visibleFrame`. Normal 80ms `trackingTimer` `syncVisibility()` calls, stack toggles (off/on), app launches, or preference changes while "at rest" on the small monitor would not self-correct. Workarounds were explicit "Reset Widget Position", full stack toggle (recreates controller), or switching placement to Automatic.

**Root causes identified (Investigator):**
- Persisted offsets (`OverlayAttachmentPreference` horizontal/vertical) tuned on the large monitor survived transition zeroing and were re-applied on every subsequent `resolveAttachment` in steady-state.
- `preferredDockPosition` (user preference) vs. the geometry-aware `preferredInitialDockPositionAndSide(for: anchorFrame)` (used only by explicit Reset) — the latter consults the actual anchor's intersecting screen's visibleFrame and `isSideRailViable`.
- `referenceVisibleFrame(for:...)` / `referenceScreen` / `convertAXFrameToScreenCoordinates` fallbacks (`NSScreen.main`, first intersect) could select the laptop's large screen even when the AX anchor rect lived fully on the secondary small monitor.
- Once movement stopped, no more screen-change notifications arrived, so `syncVisibility` (and `startTracking` on toggle/recreate) had no trigger to re-home.
- No runtime detection of "our panel now lives on a different logical home screen than the anchor's computed reference."

**Implementation mechanism (Iteration 3 — robust re-home guard + smart-initial logic on startTracking + normal sync paths + home screen mismatch guard):**
- `startTracking(...)` (both `StackOverlayPanelController` ~line 2487 and `CombineOverlayPanelController` ~line 3698) now performs an immediate post-provider "smart initial + mismatch check": it obtains a tentative anchor via the provider, computes its reference screen via the engine, compares against `panel.screen` (or the screen whose visibleFrame contains the panel's current frame center), and if mismatch (or first-time creation on this screen) it zeros relevant in-memory offsets, calls `preferredInitialDockPositionAndSide(for:)` against the *actual* current anchor's screen, sets `dockPosition` + `horizontalSide`, then forces a fresh `syncVisibility()`.
- Lightweight `home screen mismatch guard` (integrated into `syncVisibility`, `resolveAttachment`, `resolveCurrentAttachment`, and the resolve engine in `WindowAttachmentEngine`): after AX conversion and the existing `referenceVisibleFrame` / `referenceScreen(for:)` logic (which prefers intersecting screens), it additionally checks whether the chosen screen's visibleFrame meaningfully contains or best-matches the *current physical location of the panel itself* (`panel.screen?.visibleFrame.intersects(panel.frame)` or center proximity). On mismatch detection:
  - Emit diagnostic (e.g. "home screen mismatch guard triggered — re-homing to actual residence screen").
  - Temporarily zero the offsets used *for this resolve only* (or safely reconcile with persisted).
  - Force the result of `preferredInitialDockPositionAndSide` (and left-bias for top/bottom) computed against the anchor's true screen.
  - Re-run the resolve + apply.
- Hardened `referenceVisibleFrame` and the helper in OverlayRuntime to accept an optional current-panel-frame hint and prefer any screen that intersects *both* the anchor *and* the panel's present location (critical for secondary monitors in side-by-side or vertical arrangements).
- The guard is intentionally cheap, runs on the normal timer path (so it corrects "left on small" within 1-2 ticks), and only acts on true mismatch (stable residence on correct screen does not thrash).
- `resetPosition()` and creation paths already called the smart initial; they now explicitly pass the current panel's screen context.
- Result: "create while browser on small", "move then leave forever", toggles, and normal operation all self-correct to proper attachment on the smaller monitor's geometry without user action. The guard is the runtime safety net for the exact scenario that survived prior iterations.

**Success criteria for this section:** Widget attaches correctly and snugly (using the user-friendly top-left or left bias per `preferredInitialDockPositionAndSide`, or the user's `preferredDockPosition` when viable) when created on the small monitor or left there after a move. No wrong-side, detachment, overlap, or bad clamping. The mismatch guard is observed to trigger (via logs) precisely on the creation/settle-on-small cases and then produce correct attachment. Explicit Reset Position continues to work but is no longer a required workaround. All on real mixed-scale hardware.

**Exact test steps — actionable with only a laptop + one external monitor of different scale (side-by-side or vertical):**

**Minimal hardware setup (repeat for every sub-scenario):**
- Laptop internal display (high-res, e.g. Retina 2x or 3x) + one external monitor configured at lower resolution / "Scaled" > "More Space" or explicit 1080p 1x.
- In System Settings > Displays: 
  - Arrange side-by-side (default).
  - Then re-arrange vertically (drag external display icon above or below the laptop icon in the layout preview). Test both arrangements.
  - Optionally swap which is primary (drag the white menu-bar representation to the external) to test menu-bar-on-small vs. menu-bar-on-large.
- Confirm differing `backingScaleFactor` (can print in code or use System Information).
- Browser window(s) can be made full-height (tall, near menu bar + dock) on the external.
- Primary browser: Chrome. Repeat key cases on one other.
- Use `script/build_and_run.sh --logs` (filtered for Overlay/StackOverlay or "mismatch") during tests to watch for guard firing.

1. **Creating a stack while the browser is already on the small monitor (primary creation / startTracking path):**
   - Move a browser window (or two for a stack) *entirely onto the external lower-res monitor*. Size it full-height for one variation.
   - Ensure no Stacker stack is active for that browser, or turn stacks off.
   - Launch or use Stacker main window / shortcut / menu to *create the stack* from the window(s) that are already on the small monitor.
   - **Expected:** Widget appears promptly, attached via smart-initial logic on a sensible edge for the small monitor's visibleFrame (top rail + left content preferred, or left rail for tall windows). Correct gap, no overlap with browser corners or menu bar area, no floating. Scale is crisp for the external's density.
   - Verify `startTracking` invoked the smart-initial / mismatch check (guard or equivalent log may appear on first sync).
   - Interact: switch dots, open drawer, perimeter drag (new offsets should be relative to small monitor).

2. **Moving the browser then leaving it there permanently (settle / normal sync + guard path):**
   - Create the stack on the laptop (large) internal display; optionally custom-drag the widget to a non-default perimeter position (populates offsets).
   - Slowly drag the *browser window* from internal across the boundary until fully on the external small monitor; let it come to complete rest (no movement for several seconds).
   - Wait and trigger normal syncs (click widget dots, switch frontmost app, wait for 2-3 timer ticks ~0.25s).
   - **Expected:** After any initial transition re-home (Iter 2), the steady-state syncs or guard must keep (or correct to) proper attachment on the *small monitor's* geometry. Widget must not drift back to wrong side, detach, or clamp using large-monitor math.
   - If the home screen mismatch guard fires (visible in logs), confirm it produced the correct final position.
   - Leave the setup running for 30-60s with the widget "left" on small; re-check attachment stays correct.

3. **Toggling stacks (off/on) while resident on the small monitor:**
   - Achieve a correct steady-state attachment on small (from #1 or #2).
   - Turn the stack completely off (main UI, menu bar, or power button in widget).
   - Turn it back on or recreate the stack (without moving the browser window).
   - **Expected:** `startTracking` + first syncs use the smart-initial + guard to place correctly on the small monitor (fresh controller or reset state). No inheritance of stale large offsets.

4. **Reset Position while on the small monitor:**
   - While widget is on small monitor (correct or deliberately in bad state via temp hack), right-click or use context "Reset Position".
   - **Expected:** Zeros persisted + in-memory offsets, calls `preferredInitialDockPositionAndSide(for: current anchor on small screen)`, sets dock + side accordingly, re-syncs to a clean user-friendly placement *computed against the small monitor's visibleFrame*. (Confirms the reset path now also has current-screen context.)

5. **Different dock preferences while on small monitor:**
   - In Stacker settings or stack editor, change the preferred dock position (left / right / top / bottom) for the stack.
   - Recreate or toggle while browser is on small, or use Reset.
   - For each: widget must attempt the preferred rail but fall back gracefully using the small monitor's actual space (e.g. side rails may be non-viable for full-height windows on a physically smaller external; top/bottom preferred in those cases). Guard ensures the computation uses the correct visibleFrame.

6. **Full-height windows on small monitors:**
   - On the external small monitor, size the browser window very tall (nearly or fully occupying the visible height, close to menu bar and dock).
   - Create stack or settle from large → small.
   - **Expected:** `isSideRailViable` (or equivalent) + guard + initial logic chooses an appropriate rail (often top or bottom) so the widget has travel room and does not overlap rounded corners or go out of the small visibleFrame. Clamping uses the small monitor's insets.

7. **Menu-bar on large vs. small + visibleFrame differences:**
   - With laptop as primary (menu bar on internal high-res): create/settle widget on external (no menu bar). Top-rail attachment must use the external's `visibleFrame.maxY` (no erroneous deduction for a non-existent menu bar on secondary).
   - Swap primary (menu bar now on external small monitor): repeat creation/settle on the now-primary small monitor. Widget near top must correctly avoid the menu bar height on that screen.
   - Confirm no clipping or excessive gap in either configuration.

8. **Side-by-side vs. vertical monitor arrangements:**
   - Side-by-side (external to right or left of laptop): all above cases.
   - Vertical (external above or below laptop in Displays arrangement): repeat key creation (#1), permanent leave (#2), and toggle (#3) cases. The intersect + mismatch guard + reference helpers must correctly identify the small monitor regardless of its position in the global NSScreen coordinate space (not assuming adjacency direction).
   - In vertical setup, full-height windows + top/bottom rails are especially important.

**Verification that the new "home screen mismatch guard" triggers and produces correct attachment:**
- Run with logging enabled (`script/build_and_run.sh --logs` or unified logging filtered on "Overlay" / "StackOverlay" / "mismatch" / "re-home" / "startTracking").
- In the creation-on-small and leave-then-settle steps, you must see evidence of the guard (or the equivalent smart-initial logic in startTracking) activating at least once per mismatch scenario.
- Post-guard activation, the widget must be observed to move to (or remain in) the correct attached position for the small monitor.
- Advanced debug (Xcode + running app): after settle on small, inspect the live `StackOverlayPanelController` (or Combine) — `panel.screen` vs. the screen chosen inside `referenceVisibleFrame(referenceScreen)`; mismatch should have caused the guard branch. Check that `horizontalAnchorOffset` / `verticalAnchorOffset` (or `anchorOffset`) and `dockPosition` reflect the small monitor's preferred initial after correction.
- No false-positive triggers when everything is already on the matching screen; guard is silent and stable.
- After fix, persisted `OverlayAttachmentPreference` values no longer poison small-monitor residence (either per-screen storage or safe reset on detected mismatch).

**Tips for contributors with only laptop + 1 external:**
- All tests above are designed to be runnable on exactly that hardware by rearranging in Displays prefs (side-by-side vs vertical, primary swap).
- If the external is higher-res than internal (reverse the vector), still run; the guard logic is symmetric.
- Capture screenshots of the widget *on the external* with the arrangement visible in Displays prefs for proof.
- If a case fails, note the exact arrangement, which display is primary, full-height or not, and whether guard log appeared before the bad attachment.

This section, together with the transition coverage above, ensures complete validation of the final multi-monitor reliability push.

## Chrome Anchor Window Cross-Resolution Move — Full Re-Render from Fresh Window Coordinates

**Dedicated coverage for the explicit anchor-driven full re-render trigger (Iteration 4) that fires on live AX updates when the Chrome (primary browser) anchor window itself is dragged across resolution boundaries. This is the "complete re-render from fresh window coordinates" defense layer.**

**New trigger + reset behavior:**
- Location: Primary `syncVisibility()` implementation in `OverlayRuntime.swift` (the recurring ~80 ms timer + explicit call path for `StackOverlayPanelController`).
- Right after `preparePanelLayout(for: state)` and the initial `let resolvedAttachment = resolveAttachment(for: state)` (which performs live AX provider lookup + `attachmentEngine.convertAXFrameToScreenCoordinates`), and *before* the lightweight `rehomeIfCurrentResolvedIsBad(...)` guard:
  ```swift
  if let freshAnchor = resolvedAttachment.anchorFrame ?? state.anchorFrame.map(attachmentEngine.convertAXFrameToScreenCoordinates),
     let last = lastAnchorFrame,
     let oldScale = backingScale(forFrameInScreenSpace: last),
     let newScale = backingScale(forFrameInScreenSpace: freshAnchor),
     abs(oldScale - newScale) > 0.05 {
      print("[Stacker] ANCHOR-RES-CROSS full re-render trigger for \(appName): anchor rect crossed from backingScale \(oldScale) to \(newScale) — performing fullAnchorResolutionChangeReset using fresh AX rect as sole input")
      fullAnchorResolutionChangeReset(freshConvertedAnchor: freshAnchor, state: state)
      return
  }
  ```
- `backingScale(forFrameInScreenSpace:)` uses `referenceScreen(for:)` (intersect with visibleFrame, with panel location tie-breaker) + `NSScreen.backingScaleFactor` (with fallbacks).
- On trigger: `fullAnchorResolutionChangeReset` (extensive inline documentation in source):
  - `preparePanelLayout`.
  - Zero *every* piece of in-memory positioning state (clean slate for this resolution): `horizontalAnchorOffset = 0`, `verticalAnchorOffset = 0`, `previousBackgroundDragDelta = .zero`, `lastAnchorFrame = nil`, `needsReanchorAfterScreenChange = false`. (Persisted `UserDefaults` / `OverlayAttachmentPreference` values are **intentionally untouched** — they will only be re-applied on future returns to the original monitor.)
  - `(smartDock, smartSide) = preferredInitialDockPositionAndSide(for: freshConvertedAnchor)` — the same geometry-aware smart placement used by explicit "Reset Widget Position", now computed against the *fresh* anchor rect + the *destination screen's* `visibleFrame`.
  - Update `preferredDockPosition` / `dockPosition` / `horizontalSide` as needed + `updateRootView()` (twice for safety) + `resizePanelsToFitContent()`.
  - `controlsPanel.orderOut(nil); panel.orderOut(nil)` — true clean slate.
  - Pure re-resolve: `freshResolved = resolveAttachment(for: state)` using *only* the fresh AX rect + zeroed state + smart dock/side + destination geometry. No deltas or prior lastAnchorFrame participate.
  - `panel.setFrame(targetFrame, display: true)`.
  - **Multiple (3) complete re-render rounds:** `invalidatePanelRendering()`, layout/display/layer.setNeedsDisplay on both `hostingView` and `controlsHostingView`, plus `forceFullRebuildAndDisplay()` (the strong helper that does `rootView = rootView`, intrinsic size, needsLayout/Display, and window shadow invalidate) on both, plus container layers + `panel.invalidateShadow()`.
  - `orderFrontRegardless()` + controls sync.
  - `lastAnchorFrame = freshConvertedAnchor` (now the authoritative fresh value).
  - Two delayed follow-up passes (0.12 s and 0.42 s) that call `syncLayerBackingScales()`, invalidate + `forceFullRebuildAndDisplay` again, and `syncVisibility()` — allowing AX, `NSScreen.screens`, backing scales, and SwiftUI layout to fully settle on the destination resolution.
- The fresh AX rect reported for the moved Chrome window is the *sole authoritative input* for the entire reset cycle. This replaces lighter incremental updates for the cross-res anchor case.

**Exact repro steps (drag Chrome window with active stack across Retina ↔ non-Retina):**
1. Use real mixed-resolution hardware: MacBook internal Retina (backingScaleFactor typically 2.0) + one external monitor set to a lower / non-Retina scaling (e.g. "1080p" or "More Space" yielding 1.0). Confirm differing scales via System Information or temporary logging of `NSScreen.backingScaleFactor`.
2. Arrange the displays side-by-side (default) or vertically in System Settings > Displays. Test both.
3. Launch Stacker via `script/build_and_run.sh --logs` (or from Xcode) so the log stream is visible. Grant Accessibility permissions.
4. Open Chrome (primary for this test). Create a stack with one or more Chrome windows *entirely on the Retina (high-res) screen*. Ensure the widget is attached and visible.
5. (Strongly recommended for stale-state validation): With the stack active on Retina, drag the widget handle around the browser perimeter to a clearly non-default position. This populates non-zero `horizontalAnchorOffset` / `verticalAnchorOffset`, `previousBackgroundDragDelta`, and a `lastAnchorFrame` captured under the 2x scale.
6. Slowly drag the *Chrome browser window by its title bar* from the Retina screen across the screen boundary. Continue until the *entire* Chrome window (and its attached Stacker widget) is fully on the non-Retina external screen. Release and let everything come to complete rest for several seconds (multiple 80 ms sync ticks).
7. Observe the logs and final attachment on the destination.
8. Reverse direction: drag the same Chrome window (still with the active stack) fully back from the non-Retina screen onto the Retina internal screen. Let settle.
9. Additional variations:
   - Start with the Chrome window already on the low-res screen, create the stack there, then drag across to high-res (exercises the path in the opposite vector).
   - Use a full-height Chrome window on the source screen.
   - Have the controls drawer open during one of the crosses.
   - After crossing and settling, toggle the stack off then on (without moving the Chrome window) and verify clean re-attach on the current screen.

**What success looks like (widget snaps cleanly using only the new AX-reported coordinates, no stale state):**
- The distinctive log appears in the `--logs` stream / Xcode console exactly around the moment the Chrome window finishes crossing (or on the immediate next `syncVisibility` that receives an AX rect whose owning screen has the new backing scale):
  ```
  [Stacker] ANCHOR-RES-CROSS full re-render trigger for Chrome: anchor rect crossed from backingScale 2.0 to 1.0 — performing fullAnchorResolutionChangeReset using fresh AX rect as sole input
  ```
  (Scale numbers and direction vary; "Chrome" is the `appName` from the context.)
- Immediately after the trigger, the widget performs a visible clean-slate re-draw (orderOut + multi-round hosting view force rebuilds + delayed syncs). It then snaps to a correct, snug attached position on the *destination screen* computed *exclusively* from:
  - The brand-new AX-reported anchor rect (freshly converted).
  - Zeroed in-memory offsets/deltas/last frame.
  - Smart dock + side from `preferredInitialDockPositionAndSide(for: fresh...)` against the destination screen's visibleFrame.
- **No stale state symptoms:** Widget is not on the wrong rail/side, not floating detached or offset high above the browser, not overlapping browser content/rounded corners/menu area, and not clamped using math from the prior resolution's visibleFrame or deltas. Attachment is as good as (or better than) a brand-new stack created directly on the destination screen.
- Rendering remains crisp at the destination scale (building on prior iterations).
- Subsequent widget drags on the new screen populate offsets relative to the *current* resolution. Returning the Chrome window later to the original screen allows any previously persisted custom placement to be re-applied normally.
- The full `forceFullRebuildAndDisplay` + multi-round invalidates ensure no lingering layout artifacts from the source resolution's hosting view / SwiftUI tree.
- The behavior is deterministic and repeatable on real Retina ↔ non-Retina crosses.

**How to observe the `[Stacker] ANCHOR-RES-CROSS...` log:**
- **Easiest during manual testing:** Run with `script/build_and_run.sh --logs`. This builds, launches the app, and streams unified logging for the Stacker process. Perform the Chrome title-bar drag across the resolution boundary; the exact trigger line will appear in the terminal output when the fresh AX rect reveals the scale change.
- **In Xcode:** Build & run the `stacker` scheme (Debug). The `print(...)` statements appear directly in the Xcode debug console (standard output) during the drag.
- **Filtered unified log (any terminal):**  
  `log stream --info --style compact --predicate 'process == "Stacker"' | grep -i "ANCHOR-RES-CROSS"`
- The log is emitted from the normal `syncVisibility` path (driven by the tracking timer or explicit calls after AX updates). It will typically appear on the first or second post-cross `syncVisibility` once the Accessibility provider reports the anchor rect now intersecting a screen with the different backingScaleFactor. It will *not* fire for moves that stay within the same scale factor.
- Combine with other filters (e.g. "fullAnchor" or "preferredInitial") if desired for deeper debugging of the reset sequence.

**Success criteria for this subsection:** On real differing-scale hardware, dragging a Chrome window with an active stack across Retina ↔ non-Retina (both directions, with and without prior custom widget placement on the source) reliably emits the ANCHOR-RES-CROSS log, executes the full `fullAnchorResolutionChangeReset` (observable via orderOut + multiple forceFullRebuildAndDisplay rounds + delayed syncs), and leaves the widget in a clean attached state derived *only* from the new AX coordinates + zeroed state + destination geometry (no stale prior-resolution values). Non-cross moves must not spuriously trigger the log. This validates the new explicit full re-render layer for the primary browser.

This subsection exercises the strongest "anchor-driven" reset path and, together with the transition, steady-state, and widget-drag coverage, completes validation of all defense layers for multi-resolution widget reliability.

## Dragging the Widget Itself Across Screens
(The widget can be dragged around the perimeter of its attached browser window (via the drag handle / background).)
1. With the browser window straddling two screens (part on A, part on B) or fully on one, grab the widget's drag area and slowly move it to a different edge (e.g., from left side to top, or right side).
2. While dragging, cross any screen boundary if the browser window itself spans screens.
3. Drop on the new edge and verify:
   - Widget re-renders crisp at the new position on the current backing scale.
   - Attachment logic (clamping, corner snapping, full-height avoidance of rounded corners) still works.
   - Hit areas remain accurate.
4. Test widget drag while browser window is full-height on a mixed-res setup. (The re-home logic ensures that even after a screen-crossing browser move, a subsequent widget drag starts fresh on the destination.)

## Edge Cases & Advanced Scenarios
- **3+ screens / mixed 1x/2x/3x:** Set up (or simulate) three displays with varying scales. Cycle the stack window + widget through all three in sequence. Verify no cumulative artifacts. Explicitly test sequences that include higher→lower transitions.
- **HiDPI + lowDPI extremes:** Retina internal (2x or 3x on newer hardware) + low-DPI external projector or old monitor. Also test "scaled" resolutions in macOS Display prefs. Prioritize Retina (high) → non-Retina (low).
- **Full-height windows:** Make browser windows tall enough to touch menu bar and dock. Move across screens (higher→lower). Widget must avoid overlapping rounded corners correctly on both scales. Check clamping and "maxPrimaryWindowWidth" logic after re-home reset. (See also the full steady-state small-monitor full-height cases above.)
- **Moving while controls drawer open:** Open the config drawer (click widget or use shortcut), then drag the parent browser window across screens (esp. higher→lower). Drawer + main widget must both stay crisp, properly positioned, and correctly re-homed.
- **Vertical / horizontal modes + reorder:** With widget on left/right (vertical strip) or top/bottom, reorder windows via drag in sidebar or widget, then cross screens (higher→lower). Confirm re-anchoring respects the current dockPosition.
- **Different dock positions:** macOS Dock on bottom (default), left, or right. Full-height windows behave differently; test attachment + cross-screen (higher→lower) with each. (Steady-state small-monitor variants covered in dedicated section.)
- **Suggestion / Combine overlay (the "create stack" pill):** Trigger the CombineOverlay on a higher-res screen, then move the involved windows to lower-res. Verify its capsule re-homes cleanly (uses the lighter `anchorOffset` reset + async settle in its handler). Also test creating the suggestion pill while windows are already on the small monitor.
- **Sleep/wake + screen reconfig:** Put displays to sleep or change arrangement (System Settings > Displays) while stack active. On wake/reconfig + subsequent move (higher→lower), check both scale and re-home. (Note: screen params vs. actual screen-change paths differ in offset preservation.)
- **Spaces + Mission Control:** Move stack to a different Space, then drag window between physical screens (higher→lower) while on that Space.
- **Multiple stacks:** Two different browsers, widgets on different screens, cross-drag one (higher→lower) while the other stays.
- **Performance:** Rapidly drag window back and forth across boundary (including higher→lower) 10x. No flicker, no accumulating blur or mis-placement, CPU reasonable.
- **Hit testing post-move:** After higher→lower cross-screen move and re-home, confirm clicking dots focuses the correct window, drag gestures on widget don't leak, etc. Also after steady-state correction on small monitor.
- **Iteration 4 Chrome anchor crosses (new):** Explicitly exercise the ANCHOR-RES-CROSS path (see dedicated subsection) as part of edge coverage. Confirm the full re-render path is taken for Chrome anchor moves even when the widget panel itself does not receive a `didChangeScreenNotification` at the exact moment the AX rect updates.

## Verification of Observers + Invalidation (Regression)
Even with the new explicit scale sync + re-home reset + steady-state mismatch guard + anchor-driven full re-render, the prior infrastructure must continue to work:
- `NSApplication.didChangeScreenParametersNotification`
- `NSWindow.didChangeScreenNotification` (on both main panel and controls panel) — this is the *only* path that sets `needsReanchorAfterScreenChange = true`
- `NSWindow.didChangeBackingPropertiesNotification`
- Calls to `invalidatePanelRendering()` / `invalidateOverlayRendering(for:)` / `resizePanelsToFitContent()`
- `syncVisibility()`
- The two asyncAfter settle passes in both controllers.
- The new guard inside recurring sync / startTracking paths.
- The new ANCHOR-RES-CROSS detection + `fullAnchorResolutionChangeReset` (orderOut + zeroing + multi-round forceFullRebuildAndDisplay + delayed syncs) inside the fresh AX path of `syncVisibility`.

After any cross-screen move or display change, the widget should re-appear in the correct location, correct size, and now also at correct scale *and* correctly re-homed for the destination screen's resolution/geometry. Steady-state residence on a secondary lower-res screen must self-correct via the guard without external events. Chrome anchor crosses must additionally trigger and complete the full fresh-AX re-render path.

## How Testers / Contributors Should Record Results
- Note macOS version, exact display models/resolutions/scaling (use "About This Mac > Displays" or `system_profiler SPDisplaysDataType`). Explicitly record source vs. target scale factors and drag direction (higher→lower is critical for positioning validation). For steady-state cases also record: "created on small", "left/settled on small", monitor arrangement (side-by-side vs vertical), which display is primary (menu bar location), full-height or not.
- Browser + versions. **Especially note Chrome for the new ANCHOR-RES-CROSS subsection.**
- Pass/fail per scenario above, with special attention to the orphaned-widget subsection *and* the new Steady-State Residence on Smaller / Secondary Lower-Resolution Monitor section *and* the Chrome Anchor Window Cross-Resolution Move subsection. Note whether the home screen mismatch guard was observed to trigger (via logs) *and* whether the `[Stacker] ANCHOR-RES-CROSS...` log + full reset was observed during Chrome anchor crosses. Note whether the final position used only fresh AX coordinates (zeroed prior state).
- Attach before/after zoomed screenshots when possible (especially for the floating-orphaned symptom vs. clean re-attachment, and correct small-monitor attachment after guard, and clean snap after ANCHOR-RES-CROSS full re-render).
- If a failure occurs, capture unified logs (`script/build_and_run.sh --logs`) filtered around "Overlay" or "StackOverlay" or "mismatch" or "ANCHOR-RES-CROSS". Note whether `didChangeScreenNotification` fired, whether offsets were zeroed, whether the guard path executed, and whether the full re-render reset path (with its distinctive log and multiple forceFullRebuildAndDisplay calls) executed.
- Update `docs/compatibility-matrix.md` and the summary in `CONTRIBUTING.md` / `README.md` once validated on real hardware.

## Automation Note
No XCTest UI tests exist for the floating NSPanels (difficult to drive AppKit overlays reliably in CI without real multi-monitor hardware). All coverage here is manual. The unit tests in `StackerTests/` (logic only) continue to be buildable only after a future XCTest target is added to the Xcode project (see `docs/distribution-readiness.md`).

## Sign-Off Criteria for This Checklist
- All core cross-screen drags pass crispness + hit-test checks on at least Chrome + one other browser.
- The dedicated "Higher → Lower Resolution Move (the orphaned widget case)" subsection passes: widget re-homes cleanly using fresh automatic placement after offset reset (no floating detachment).
- The major new "Steady-State Residence on Smaller / Secondary Lower-Resolution Monitor" section passes cleanly on real mixed-resolution hardware (laptop internal high-res + one external lower-res monitor is sufficient and required for contributor validation):
  - Creating a stack while the browser is already on the small monitor succeeds (smart-initial via startTracking).
  - Moving then leaving the widget there permanently succeeds (normal sync + home screen mismatch guard corrects and stabilizes).
  - Toggling stacks, Reset Position, different dock preferences, full-height windows, menu-bar (primary on large vs. small), and both side-by-side + vertical arrangements all produce correct attachment.
  - Explicit verification that the new "home screen mismatch guard" triggers on the relevant cases and produces correct attachment without requiring manual Reset.
- The dedicated "Chrome Anchor Window Cross-Resolution Move — Full Re-Render from Fresh Window Coordinates" subsection passes on real Retina + non-Retina hardware (both drag directions, with/without prior custom widget placement on source):
  - The `[Stacker] ANCHOR-RES-CROSS full re-render trigger for Chrome...` log is observed during the Chrome anchor window cross.
  - `fullAnchorResolutionChangeReset` executes (orderOut + complete in-memory zeroing + smart initial dock/side from fresh + pure resolve from new AX rect + 3× full hosting view rebuild rounds via `forceFullRebuildAndDisplay` + delayed sync passes).
  - Widget snaps to correct attached position on destination using *only* the new AX-reported coordinates and zeroed state (no stale lastAnchorFrame, offsets, or deltas from the source resolution remain in play).
- Edge cases (full-height, drawer open, sleep/wake, 3 screens if available, higher→lower sequences, steady-state small-monitor variants, and explicit Chrome anchor crosses exercising the new full re-render path) pass or have documented workarounds.
- No regression in single-screen behavior or other documented flows.
- `script/build_and_run.sh --verify` and `xcodebuild build` have passed during local validation. The known implementation stages are: 1 scale sync, 2 re-home on change, 3 guard + smart-initial on `startTracking` + sync paths, 4 anchor-driven full re-render on cross-resolution AX updates.
- **For open-source release:** This steady-state small-monitor scenario (the exact user-reported case that survived prior iterations) *must pass cleanly on real mixed-res hardware*. The test plan is intentionally written to be runnable by contributors with only a laptop + one differently-scaled external monitor. No reliance on same-resolution or single-screen setups is acceptable. All sign-off items above must be green on actual differing-scale-factor displays.
  - **Additionally required for open-source release:** The new Chrome Anchor Window Cross-Resolution Move — Full Re-Render path *must also be exercised and observed to succeed* on the same real mixed-res hardware (laptop Retina + external non-Retina). The distinctive ANCHOR-RES-CROSS log must appear, the complete clean-slate re-render from fresh AX coordinates (with full zeroing and `forceFullRebuildAndDisplay` rounds) must occur, and the widget must attach correctly with zero stale state from the prior resolution. The three explicit defense layers — (1) notification-driven re-home in handleDisplayMetricsChanged, (2) home-screen mismatch guard + smart-initial on syncVisibility/startTracking, (3) explicit ANCHOR-RES-CROSS fullAnchorResolutionChangeReset from live AX — must all have been validated in their respective scenarios. Contributor validation on actual Retina ↔ non-Retina displays (not simulated or same-scale) is mandatory. Builds green + full test plan (including this subsection) green on real differing-scale hardware is the bar for open-source v1 readiness.

This checklist is intended for maintainers, contributors, and community testers validating multi-display fixes or regressions.

---
Last updated: 2026-05-19. Added the Chrome anchor window cross-resolution move scenario, ANCHOR-RES-CROSS log observation, and full re-render success criteria for real Retina / non-Retina hardware.
