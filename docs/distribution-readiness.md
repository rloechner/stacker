# Distribution Readiness

This document records the current distribution position for Stacker.

## Current Conclusion

Mac App Store distribution is unlikely to be possible for Stacker in its current form.

The blocker is architectural, not cosmetic. Stacker's core value depends on controlling windows that belong to other apps:

- reading other apps' windows
- moving and resizing those windows
- focusing and raising those windows
- observing window movement/resizing
- using System Events as a fallback for apps that do not expose enough Accessibility data

Those behaviors depend on macOS Accessibility APIs and Apple Events/System Events. Apple requires App Sandbox for Mac App Store apps, and Apple's sandbox documentation lists both of these categories as incompatible or restricted for sandboxed apps:

- use of Accessibility APIs in assistive apps
- sending Apple Events to arbitrary apps

Relevant Apple docs:

- https://developer.apple.com/documentation/security/app_sandbox
- https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox
- https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution
- https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.automation.apple-events

## Current Project State

Observed locally:

- Project target: `stacker`
- Scheme: `stacker`
- App Sandbox: disabled in the Xcode project
- Hardened Runtime: enabled in the Xcode project
- Entitlements file: `stacker/stacker.entitlements`
- Release signing: no longer forced to ad hoc signing; direct distribution uses a Developer ID archive/export
- Local signing identities: `security find-identity -p codesigning -v` should report a valid Developer ID Application identity before release, for example `Developer ID Application: Ryan Loechner (44N969GC55)`.
- Local signed Release artifact: builds and passes `codesign --verify --strict`, but it is signed with Apple Development, includes `com.apple.security.get-task-allow`, and is rejected by `spctl`. It is suitable for local testing only.
- Automation usage string: present through generated Info.plist build setting
- App icon: app icon PNGs are present in `Assets.xcassets/AppIcon.appiconset`, and Debug/Release builds generate `AppIcon.icns`.
- Tests: no XCTest target is currently present
- Minimum OS: `MACOSX_DEPLOYMENT_TARGET` is currently `15.0`. A macOS 14.0 probe fails because the overlay uses `WindowDragGesture` and `allowsWindowActivationEvents`, which require macOS 15.0 or newer.

The local debug build succeeds when Xcode is allowed to run outside the sandbox:

```sh
xcodebuild -project stacker.xcodeproj -scheme stacker -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/stacker-derived build CODE_SIGNING_ALLOWED=NO
```

Sandbox experiment build also succeeds when sandboxing is forced from the command line:

```sh
xcodebuild -project stacker.xcodeproj -scheme stacker -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/stacker-sandbox-derived build ENABLE_APP_SANDBOX=YES CODE_SIGNING_ALLOWED=YES
```

That build signs the app with:

- `com.apple.security.app-sandbox`
- `com.apple.security.automation.apple-events`
- `com.apple.security.files.user-selected.read-only`
- `com.apple.security.get-task-allow` for debug

This compile/signing success does not prove runtime or App Review viability. The next meaningful test is whether a sandboxed build can still discover, move, resize, focus, and observe other apps' windows.

## Mac App Store Risk

The App Store path would require at least:

- enabling App Sandbox
- removing arbitrary-app Apple Events behavior
- proving the app can still inspect, move, resize, and focus other apps' windows from a sandboxed process
- passing App Review with a utility whose main behavior is control of other apps' UI

Based on Apple's current documentation, that is not a safe assumption. A Mac App Store submission may be rejected even if the app compiles and runs locally.

## Direct Distribution Path

Direct distribution is the more realistic commercial path:

- sign with Developer ID
- keep Hardened Runtime enabled
- keep a real entitlements file for required runtime permissions, especially Apple Events
- notarize the app
- staple the notarization ticket
- provide clear Accessibility and Automation permission onboarding

Relevant Apple docs:

- https://developer.apple.com/developer-id/
- https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution

## Product Positioning For Review

Regardless of distribution channel, the product should be positioned as:

> Stack same-app windows into one desktop slot and use native macOS window switching to move between them.

Avoid claims about:

- restoring arbitrary workspaces
- recreating browser profiles
- saving app sessions
- managing all windows across the system

Those claims imply reliability that macOS does not give a third-party utility.

## Next Validation Steps

1. Runtime-test the sandbox experiment build and record which core operations fail.
2. Add final app icon assets for all macOS icon sizes.
3. Confirm a valid Developer ID Application signing identity is installed.
4. Build a notarization-ready Developer ID archive/export with `script/release_dmg.sh`, then run `codesign`, `spctl`, notarization, and stapling validation on the exported artifact.
5. Add a small XCTest target for stack/session logic that does not need to control real apps.
6. Keep reducing the app UI/docs to live stacks only.
7. Add a compatibility matrix and record known-good app/window combinations.
8. Decide whether to attempt Mac App Store review as an experiment or commit to direct distribution first.

**v1 Open-Source Note**: Multi-resolution / multi-monitor widget behavior has received focused local testing, including re-home handling, home-screen mismatch guards, and smart initial placement on `startTracking`. This is a good source-first open-source release point, but direct binary distribution still requires signing, packaging, notarization, and more clean-machine QA.
