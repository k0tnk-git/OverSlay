# References

## ClickPlay

Input mechanisms were reviewed against [TheOPBunny/ClickPlay](https://github.com/TheOPBunny/ClickPlay), pinned at revision [`ba12e003f0c98d2234e185107e9d5c185aceda44`](https://github.com/TheOPBunny/ClickPlay/tree/ba12e003f0c98d2234e185107e9d5c185aceda44). The repository retains reference copies of `KeyInjector.swift`, `GamepadButtonView.swift`, `VirtualCursorModeController.swift`, `Profile.swift`, the upstream documentation, and its Apache License 2.0 in `docs/reference/clickplay`. These files are reference material and are not compiled into OverSlay.

OverSlay adapts the serial event queue, key ownership, modifier handling, and release discipline in `Sources/OverSlay/CGKeyInjector.swift`. Its radial core independently implements shared directional ownership and cancellable delayed release. The Escape event tap and emergency controller implement separate editor-click and Escape sequences, autorepeat/self-event filtering, and synchronized lifecycle handling. See [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md); the application package includes the upstream license and notices.

The ClickPlay license applies to covered upstream material and adaptations. It does not license all original OverSlay code. Preserve required notices and update the third-party inventory when adapting additional source.

## Platform documentation

Use current Apple documentation and the selected macOS SDK for AppKit panels, Quartz event services, Accessibility, and workspace/application lifecycle APIs. Availability and actual behavior must be checked on supported macOS versions. A source-code precedent is not proof of game compatibility.
