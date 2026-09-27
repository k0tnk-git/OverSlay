# Third-party material

## ClickPlay

Source: https://github.com/TheOPBunny/ClickPlay
Author/project: TheOPBunny / ClickPlay contributors.
Revision: ba12e003f0c98d2234e185107e9d5c185aceda44.
License: Apache License 2.0; full text in docs/reference/clickplay/LICENSE.

Unmodified reference copies retained in docs/reference/clickplay:

- ClickPlay/KeyInjector.swift
- ClickPlay/GamepadButtonView.swift
- ClickPlay/VirtualCursorModeController.swift
- ClickPlayShared/Profile.swift
- docs/index.md

These reference copies are not compiled into the bootstrap application.
No upstream NOTICE file was present in the inspected revision's repository tree.
When implementation adapts any source, retain its notices, mark modified files,
and extend this inventory with the destination paths and nature of changes.

OverSlay is distributed under the project license in the repository root. The upstream Apache-2.0 license applies to the referenced ClickPlay material and its covered adaptations; it does not replace the project license.

## Adapted mechanisms (2026-09-21)

`Sources/OverSlay/CGKeyInjector.swift` adapts KeyInjector's serial queue,
logical/physical ownership, modifier flags and ordered release. OverSlay adds
an event marker and its InputSink interface, and omits raw key logging.
`Sources/OverSlayCore/RadialCore.swift` reimplements directional shared-key
ownership and delayed release with explicit cancellation identities.
`Sources/OverSlay/EscapeEventTap.swift` and the core emergency controller
implement the five-Escape mechanism with separate edit-click counting,
autorepeat/self-event filtering and synchronized lifecycle.
Reference revision and Apache-2.0 license above apply to these adaptations;
the full license is also packaged with the application.
