# Architecture

OverSlay is a native Swift and AppKit macOS application. The executable target owns windows, menus, permissions, event taps, and system input. `OverSlayCore` contains deterministic input, profile, geometry, and macro logic; `OverSlayCoreTests` tests that logic independently of AppKit.

## Runtime boundaries

- Each game control is an independent non-activating `NSPanel`. The editor and other service controls have their own lifecycle.
- Mouse events update core state; the view layer does not inject keyboard events directly.
- Keyboard events pass through one serial injector. It tracks owners of held keys so a shared key is released only after its last owner ends.
- UI work stays on the main thread. Event tap callbacks remain short and never wait for UI or file I/O.
- Profiles are versioned Codable JSON with validation and atomic writes. Failed imports must preserve existing user data.

## Input and cancellation

Every hold, macro, delayed action, or pointer capture has an explicit cancellation path. Emergency reset cancels future work before releasing current synthetic input, clears ownership and capture, and leaves the app available. Five left clicks on the editor control and five separate Escape presses use independent counters, each with at most two seconds between activations; Escape autorepeat is ignored. The fifth editor click performs the reset before toggling editor state.

Digital joystick input maps directions to keys. Game and fullscreen compatibility must be established by manual testing, not inferred from the window level or successful launch.

## External reference

The input ownership and event-injection design was informed by the pinned ClickPlay revision. See [REFERENCES.md](REFERENCES.md) and [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md) for provenance and required notices.
