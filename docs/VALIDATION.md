# Validation

## Latest automated result

CI [36309211349](https://github.com/k0tnk-git/OverSlay/actions/runs/36309211349) passed for commit `f083329766689f62b33d34df1c390064e20f3909`. The run executed 77 deterministic tests, built the universal arm64/x86_64 app, and passed ZIP and DMG launch, signature, and English/Russian catalog checks on macOS 15 and 26. The package is ad-hoc signed and not notarized.

Read-only verification of the published assets passed: both downloaded files match `SHA256SUMS.txt`; the ZIP contains version 0.1.0, the expected build commit, license notices, and both localization catalogs.

## Manual status

Target-Mac interactive validation is **NOT RUN**. This includes real keyboard delivery, Accessibility permission behavior, editor interaction, profile switching, event cancellation races, fullscreen and Spaces, click-through. CI build, tests, signatures, and launch smoke do not prove these behaviors or compatibility with any particular game.

A previous test release produced Finder’s “The application can’t be opened” message on one target Mac. The cause remains unresolved. CI launch checks did not reproduce it, so they do not establish that the issue is fixed. Record the exact macOS version, Mac architecture, release asset, and error text when investigating.

## Recording results

Keep automated build/test results separate from manual app and game checks. For every manual scenario, report PASS, FAIL, or NOT RUN and describe the observed behavior. Do not infer compatibility from a successful build, app launch, or similar code in another project.
