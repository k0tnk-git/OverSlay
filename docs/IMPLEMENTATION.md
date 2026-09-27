# Implementation status

OverSlay currently includes independent overlay buttons, Hold/Toggle/timed behavior, key combinations and macros, mouse-based editing and resizing, profiles with JSON import/export, a digital radial joystick, and a diagnostic on-screen keyboard. The app targets macOS 13 or later and packages universal Intel and Apple silicon builds.

The next acceptance work is manual testing on a target Mac. Until that is done, no implementation phase is considered fully accepted.

## Next: target-Mac validation

1. Install the current release and grant Accessibility permission.
2. Test button assignment, Hold/Toggle, timed input, combinations/macros, profile persistence, and editor drag/resize using only the mouse.
3. Verify both emergency reset paths: five editor clicks and five separate Escape presses, with at most two seconds between activations. Confirm the editor click counter still works while entering/leaving edit mode.
4. Check that changing focus, opening the editor, hiding controls, ending a gesture, and revoking permission release synthetic input and cancel pending work.
5. Test digital joystick movement, release, and reset during drag.
6. Test TextEdit delivery, at least one target game, windowed/fullscreen operation, focus, and click-through behavior. Record each result separately; a CI launch check is not game compatibility evidence.

See [VALIDATION.md](VALIDATION.md) for the latest automated evidence and [TESTER.md](TESTER.md) for the checklist.
