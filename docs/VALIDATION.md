# Validation

## Latest automated result

The English/Russian 0.1.0 release awaits macOS CI in this repository. Local checks passed for 222 matching localization keys, format specifiers, lookup coverage, and Git whitespace checks. Build, tests, and packaged launch results will be recorded here after CI completes.

## Manual status

Target-Mac interactive validation is **NOT RUN**. This includes real keyboard delivery, Accessibility permission behavior, editor interaction, profile switching, event cancellation races, fullscreen and Spaces, click-through. CI build, tests, and launch smoke do not prove these behaviors or compatibility with any particular game.

A previous test release produced Finder’s “The application can’t be opened” message on one target Mac. The cause remains unresolved. CI launch checks did not reproduce it, so they do not establish that the issue is fixed. Record the exact macOS version, Mac architecture, release asset, and error text when investigating.

## Recording results

Keep automated build/test results separate from manual app and game checks. For every manual scenario, report PASS, FAIL, or NOT RUN and describe the observed behavior. Do not infer compatibility from a successful build, app launch, or similar code in another project.
