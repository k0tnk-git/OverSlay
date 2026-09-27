# Validation

## Latest automated result

CI [36321982240](https://github.com/k0tnk-git/OverSlay/actions/runs/36321982240) passed for commit `1532df8458e7b8e2b736c4b09f8ddfa44ed46bb5`, the refreshed 0.1.0 release source including the user's README update. It ran the 89-test XCTest suite, built the universal arm64/x86_64 app, and passed ZIP and DMG launch, signature, and English/Russian catalog checks on macOS 15 and 26. The package is ad-hoc signed and not notarized.

The refreshed release assets were checked against `SHA256SUMS.txt`; the ZIP's embedded build commit matches the release tag, and it contains the license notices and both localization catalogs. GitHub's uploaded-asset SHA-256 digests match the verified files: ZIP `e2b55e401515190a4844254efbf19b0065207e1697abe411f798e61baafae080`, DMG `d6502471612113e5344292bb9f7e6bbb2b769111f901bdedca61592f69ece61a`.

New regression coverage includes constructing and resizing the macro editor, compact keyboard-layout titles, decoding older radial settings with `inputMode: "analog"`, and picker placement/cancellation through directly dispatched AppKit mouse events. These checks do not establish physical mouse capture across apps, Finder behavior, multiple-display interaction, or game compatibility; use the updated [manual checklist](TESTER.md).

## Previous release evidence

The original 0.1.0 publication was associated with commit `f083329766689f62b33d34df1c390064e20f3909` and CI [36309211349](https://github.com/k0tnk-git/OverSlay/actions/runs/36309211349). That run executed 77 deterministic tests and passed packaging and launch checks. Read-only verification of those original published assets passed: both downloaded files matched `SHA256SUMS.txt`; the ZIP contained version 0.1.0, the expected build commit, license notices, and both localization catalogs. This verification applies only to the original assets, not the replacement release.

## User manual report — 2026-09-27

The user confirmed that the fixes work after checking them, and separately updated the README with illustrations. This is a user-reported PASS for the reported fixes: macro creation, key placement, compact layout labels, and joystick simplification. The report does not specify macOS version, Mac architecture, tested build identifier, or individual test steps.

## Manual status

The reported fixes have user confirmation as recorded above. The broader target-Mac checklist remains **NOT REPORTED**: real keyboard delivery, Accessibility permission changes, profile switching, emergency exits, event cancellation races, fullscreen and Spaces, and click-through. CI build, tests, signatures, and launch smoke do not prove these behaviors or compatibility with any particular game.

A previous test release produced Finder’s “The application can’t be opened” message on one target Mac. The cause remains unresolved. CI launch checks did not reproduce it, so they do not establish that the issue is fixed. Record the exact macOS version, Mac architecture, release asset, and error text when investigating.

## Recording results

Keep automated build/test results separate from manual app and game checks. For every manual scenario, report PASS, FAIL, or NOT RUN and describe the observed behavior. Do not infer compatibility from a successful build, app launch, or similar code in another project.
