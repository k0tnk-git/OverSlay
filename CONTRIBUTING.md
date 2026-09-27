# Contributing

Thanks for helping improve OverSlay. Bug reports and focused, reviewable changes are useful.

## Reports

Use the GitHub issue forms for bug reports and feature ideas. Include the macOS version, Mac architecture (Intel or Apple silicon), steps to reproduce, and what happened versus what you expected. For input problems, say whether the control was Hold, Toggle, or joystick and whether the issue persists after using Emergency Reset.

Do not include private messages, account details, or other sensitive data. Do not claim a game is compatible based only on a successful build or launch; describe the exact setup and observed behavior.

## Development

OverSlay is a native Swift/AppKit macOS app. Development and the CI workflow require macOS with Swift 5.9 or later. Run the existing checks with:

```sh
bash scripts/ci.sh
```

Keep input ownership and cancellation explicit. Any change that can hold input or capture the pointer must provide cleanup on cancellation and emergency reset. Do not log chat contents or full key streams.

Before changing implementation, read [AGENTS.md](AGENTS.md), [architecture](docs/ARCHITECTURE.md), [implementation plan](docs/IMPLEMENTATION.md), and [validation notes](docs/VALIDATION.md). Platform-specific behavior still needs manual verification on a Mac; report CI results and manual checks separately.
