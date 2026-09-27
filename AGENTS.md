# Development instructions

OverSlay is a native Swift/AppKit macOS application designed to be usable with a mouse. Priorities are predictable controls, independent placement, and reliable release of synthetic input. Keyboard shortcuts are optional conveniences; they must not be the only path where a mouse toggle is practical.

## Read first

1. [README](README.md) for the product and current scope.
2. [Architecture](docs/ARCHITECTURE.md) for component boundaries and invariants.
3. [Implementation status](docs/IMPLEMENTATION.md) for current behavior and next acceptance work.
4. [Validation](docs/VALIDATION.md) and [references](docs/REFERENCES.md) for evidence and provenance.

## Engineering invariants

- Use Swift and AppKit for the app, windows, and events. Keep the independent non-activating panel per game widget; do not combine controls into a shared pad.
- Hold, Toggle, Compatibility behavior, and both emergency exits are core requirements. Emergency counters are independent: five editor-button clicks or five distinct Escape presses, with no more than two seconds between activations. Ignore Escape autorepeat. Opening the editor must not move or hide its always-available button or reset its counter; the fifth click triggers reset first.
- UI work stays on the main thread. Event-tap callbacks stay short and do not wait on UI, disk, or the injection queue.
- Send injected keys through one serial queue with explicit owners for held keys. On emergency cleanup, cancel future work before releasing currently held input. Every hold, timed action, macro, or pointer capture needs an immediate cancellation and cleanup path.
- Separate deterministic input, timing, ownership, and cancellation logic from AppKit/CGEvent. Add behavior tests for meaningful state transitions and release/repress races; do not write tests that only mirror the implementation.
- Store versioned Codable JSON with validation and atomic writes. A failed import must not discard existing user data.
- Do not log game chat contents or complete key streams. Diagnostics should contain states, action identifiers, timing, and errors.
- Treat CI build/tests, launch smoke, and manual Mac/game validation as separate evidence. Do not call a macOS scenario passed without target-Mac observation.
- Consult the pinned ClickPlay source before adapting its mechanisms. Preserve license notices and update [third-party provenance](docs/REFERENCES.md).
- Use the existing SwiftPM project and `bash scripts/ci.sh`; do not add a new build pipeline or dependencies without a concrete need.
- Do not create parallel agents unless explicitly requested.

## Current platform limitation

The project currently relies on configured macOS CI for builds and tests. Interactive validation requires access to a target Mac. Leave platform assumptions open until that evidence exists.
