# Release Notes Template / Notes for the Maintainer

This file is a lightweight aid for drafting GitHub Releases. It is not used by automation.

## Suggested Release Title
`Stacker vX.Y.Z`

## Standard Sections

### Highlights
- One or two sentence summary of the release.

### What's Changed
- Bullet list of user-visible changes (or link to the compare view)
- Mention any browser-specific fixes or new validation in the compatibility matrix

### Requirements
- macOS 15.0 or newer
- Accessibility permission (first launch)
- Supported browsers: Chrome, Brave, Safari, Edge, Firefox

### Installation
1. Download the `.dmg` from the Assets section below
2. Open it and drag Stacker to your Applications folder
3. Launch and grant Accessibility permission when prompted (System Settings → Privacy & Security → Accessibility)
4. You may also see a one-time Automation prompt for System Events fallback

### Known Limitations / Testing Notes
- Reference the current state of `docs/compatibility-matrix.md`
- Call out any remaining edge cases around full-height windows, multi-monitor, Spaces, or sleep recovery
- Note that maintenance and support remain best-effort

### Acknowledgments
- Thanks to contributors, testers, or people who reported issues

---

## Pre-release Checklist (for the author)
- [ ] Update `docs/compatibility-matrix.md` with any new validation
- [ ] Bump version in Xcode project / Info.plist if needed
- [ ] Build, sign, notarize, and staple a Release DMG
- [ ] Test the DMG on a clean machine (or at least verify the notarized artifact)
- [ ] Draft release notes using this template
- [ ] Attach the DMG + (optionally) the source zip
- [ ] Announce in README / changelog if you maintain one

## Tips
- Keep releases small and frequent when possible.
- Be explicit about what was *actually tested* vs. "should work."
- Never over-promise support or timelines — this remains a personal tool.
