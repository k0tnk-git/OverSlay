# OverSlay

OverSlay is a free, mouse-controlled macOS overlay built for accessibility and convenience. It is designed for gaming and control customization, and can also be useful in other apps. Arrange independent on-screen controls to send keyboard input without relying on a physical keyboard.

**[Download the latest release](https://github.com/k0tnk-git/OverSlay/releases/latest)** · **[Installation guide](docs/INSTALL.md)**

<img width="698" height="388" alt="SlayInGame" src="https://github.com/user-attachments/assets/84e7e8b3-f539-4eb7-ab95-b9824715d72d" />

## Features

- Independent buttons with Hold, Toggle, timed Toggle, and multi-step Tap/Hold/Wait/Text macros.

<img width="584" height="332" alt="SlayKeyResize" src="https://github.com/user-attachments/assets/5190d33d-e4d4-48f0-8ed4-cb3435ab9980" />

- Mouse-based editing, grouping, resizing, and on-screen assignment of keys and combinations.

<img width="584" height="332" alt="SlayKeyReposition" src="https://github.com/user-attachments/assets/ec0129f4-9ac3-4ce3-8c4d-ea4795388ffe" />

- Per-button colors, fill patterns, and opacity.
- App-linked profiles with JSON import and export.
- Digital radial joystick and on-screen keyboard.
- Switchable key-label layouts and a control to hide or show the overlay.
- Emergency input reset by five editor-button clicks or five separate Escape presses.

## Install

Download the universal DMG from the latest release, open it on your Mac, and drag `OverSlay.app` to Applications. Requires macOS 13 or later; supports Intel and Apple silicon. Releases are ad-hoc signed without Developer ID signing or Apple notarization, so macOS may ask you to approve opening the app. Follow the [installation guide](docs/INSTALL.md) to grant Accessibility permission.

The app interface starts in English; choose Russian in **Settings → App Language** to apply it on the next launch. Compatibility with specific games, fullscreen setups, and keyboard workflows requires hands-on testing; a successful build or launch does not guarantee it.

## Known compatibility limitations

- **Exclusive fullscreen:** overlays may disappear or lose focus. Use borderless windowed mode when available.
- **Synthetic input:** some games ignore software-generated keystrokes. OverSlay cannot guarantee input support in every game.
- **Focus:** clicking an overlay may cause some games to lose focus and stop receiving input, even with non-activating controls.

These are known game/platform compatibility limitations; please avoid duplicate bug reports for these cases.

## Build from source

Requires macOS and Swift 5.9 or later. Run `bash scripts/ci.sh` from the repository root.

See [CONTRIBUTING.md](CONTRIBUTING.md) for development notes and [Apache-2.0 license](LICENSE).
