# Install OverSlay

OverSlay is an early release for macOS 13 or later, on Intel and Apple silicon. The interface starts in English. In **Settings → App Language**, choose English or Русский; the change applies the next time OverSlay launches. Xcode and Terminal are not required to install it.

## Download and open

1. Download `OverSlay-macOS-universal.dmg` from the [latest release](https://github.com/k0tnk-git/OverSlay/releases/latest). Open the DMG on your Mac.
2. Drag `OverSlay.app` to Applications. Eject the OverSlay disk image, then launch the app from Applications. If an older copy is running, quit it first from the OverSlay menu.
3. This release is ad-hoc signed, without a Developer ID signature or Apple notarization. If macOS blocks it because the developer cannot be verified, try opening it once, then go to System Settings → Privacy & Security and choose **Open Anyway** for OverSlay. Confirm the prompt. Exact wording varies by macOS version.
4. Grant OverSlay **Accessibility** permission in System Settings → Privacy & Security → Accessibility. If it is not listed, use **+** to add it from Applications. macOS may request authentication.
5. From the OverSlay menu, choose **Refresh Permissions**, then **Diagnostics & Permissions**. Accessibility should show as granted. Restart OverSlay if the status does not update. Replacing the app may require adding it to the permission list again.

If macOS says the app is damaged, offers no way to approve opening it, or it fails to launch, report the exact message and your macOS version. Do not disable macOS security or use Terminal commands to install the app.

Apple guides: [Open an app from an unidentified developer](https://support.apple.com/102445) · [Control access to your Mac](https://support.apple.com/guide/mac-help/control-access-to-your-mac-mchld5a35146/mac)

## Basic controls

- **Hold button:** hold the left mouse button on a control; release to stop sending its key.
- **Toggle button:** click once to turn it on and click again to turn it off. The initial controls use Hold.
- **Digital joystick:** hold and drag in a direction; diagonals activate two directions. Release the mouse button to stop.
- **Editor (⚙):** enter or leave edit mode. Drag controls to move them; use the side and corner handles to resize. Controls do not send game input while editing.
- **Button options:** right-click a button in edit mode to change its assignment and behavior.
- **On-screen keyboard (⌨):** open or close the diagnostic keyboard. Modifier keys toggle with separate clicks.
- **Emergency reset:** click the editor button five times, with no more than two seconds between clicks. Or press Escape five separate times, with no more than two seconds between presses. Holding Escape and clicking the on-screen Escape key do not count. The OverSlay menu also includes Emergency Reset and Quit.

## Current limitations

Game compatibility, fullscreen behavior, keyboard layouts, focus, and interactive operation require testing on target Macs. A successful build or launch does not establish compatibility with a particular game. The on-screen keyboard is not a complete text-input or IME system.

## Uninstall

Quit OverSlay from its menu, then move `OverSlay.app` from Applications to Trash. You can also remove its Accessibility permission in System Settings.
