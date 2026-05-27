# Releasing Stacker

This document describes the direct distribution release flow for Stacker.

Stacker is distributed outside the Mac App Store because its core behavior depends on Accessibility APIs and Apple Events/System Events to inspect, focus, move, and resize browser windows. The release artifact should be a Developer ID signed, notarized, stapled DMG.

## Prerequisites

- Active Apple Developer Program membership.
- Xcode installed and signed in with the Apple ID for team `44N969GC55`.
- A valid `Developer ID Application: Ryan Loechner (44N969GC55)` certificate installed in Keychain.
- A notarytool keychain profile named `stacker-notary`.

Validate signing identity:

```sh
security find-identity -p codesigning -v
```

Expected:

```text
Developer ID Application: Ryan Loechner (44N969GC55)
```

Create notary credentials if needed:

```sh
xcrun notarytool store-credentials stacker-notary
```

Validate the notary profile:

```sh
xcrun notarytool history --keychain-profile stacker-notary
```

## Release Build

Run the release script:

```sh
script/release_dmg.sh
```

The script will:

- archive the `stacker` scheme in Release configuration;
- export a Developer ID signed `Stacker.app`;
- verify the app signature and entitlements;
- create a drag-to-Applications DMG;
- submit the DMG for notarization;
- staple the notarization ticket;
- validate the stapled DMG;
- run a final Gatekeeper assessment.

The script uses `/private/tmp/stacker-release-build` for temporary archive/export work and writes the output DMG to `dist/`.

For a local packaging smoke test only, without public distribution readiness:

```sh
script/release_dmg.sh --skip-notarize
```

Do not upload a `--skip-notarize` DMG as a public release.

## Manual Verification

After the script succeeds, verify the output again:

```sh
spctl -a -vv -t open dist/Stacker-*.dmg
```

Then test the DMG on a clean Mac or clean macOS user account:

- mount the DMG;
- drag `Stacker.app` to `/Applications`;
- launch from `/Applications`;
- approve Accessibility permission;
- approve Automation permission if prompted;
- create and use a stack with at least one supported browser.

## GitHub Release

Create a GitHub Release with:

- tag matching the app version, for example `v1.0`;
- the notarized `Stacker-<version>.dmg` attached;
- release notes that mention macOS 15.0+, Accessibility permission, and supported browsers.

Keep source builds available for developers, but point normal users to the signed DMG.
