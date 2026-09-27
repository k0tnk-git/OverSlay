# Manual test checklist

Use a Mac running macOS 13 or later. Record macOS version, Intel or Apple silicon, release version, and each result as PASS, FAIL, or NOT RUN.

- [ ] Install from the release DMG; approve opening and grant Accessibility permission.
- [ ] Confirm the app launches and diagnostics show Accessibility access.
- [ ] With mouse only, edit, add, assign, move, resize, and save a button; restart and confirm persistence.
- [ ] Open Add Macro Button, add and save steps, then reopen for editing; check scrolling and resizing.
- [ ] Drag a key from Add Button onto the Desktop and another application's window: exactly one overlay button appears and no text clipping file is created. Check another display. Escape, dropping back inside the picker, hiding the overlay, and switching profiles must cancel placement without creating a button or leaving a preview.
- [ ] In a macro's key picker, clicking keys still selects them and dragging does not close the picker or place an overlay button.
- [ ] Check English, Russian, and custom layout labels: short titles fit the language button and the tooltip retains the full layout name.
- [ ] Check Hold, Toggle, timed input, combinations, and a macro in TextEdit.
- [ ] Use both emergency exits: five editor-button clicks and five distinct Escape presses, with no more than two seconds between activations. Confirm autorepeat does not count.
- [ ] While input is active, open the editor, switch focus, hide controls, cancel a drag, and revoke permission where practical. Confirm input releases and old actions do not resume.
- [ ] Drag the digital joystick in cardinal and diagonal directions, release inside and outside its panel, and reset during a drag.
- [ ] Import an older profile with radial inputMode set to analog: joystick movement uses WASD, other settings survive, and no input-mode selector or keyboard/gamepad icon is shown on the joystick.
- [ ] Check mouse clicks outside overlay controls, windowed mode, fullscreen/Spaces, and focus behavior in the intended game.
- [ ] Check profile switching and import/export without losing existing profile data.

A successful launch is not evidence of game compatibility. Do not include private chat contents, account data, or full key logs in a report.

- [ ] On a fresh install, confirm English UI. Select Russian under Settings, restart, and verify menus, editors, and errors. Switch back; confirm profile names and keyboard layouts are unchanged.
