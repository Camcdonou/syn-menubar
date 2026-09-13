# ✦ Syn Usage

A native macOS menu bar app for your [Synthetic](https://synthetic.new) API quotas — built in the Liquid Glass style of macOS 26, in a single Swift file with zero dependencies.

![platform](https://img.shields.io/badge/platform-macOS%2026-black) ![swift](https://img.shields.io/badge/swift-6-orange) ![license](https://img.shields.io/badge/license-MIT-blue)

The menu bar shows your weekly quota at a glance:

```
✦ 72%
```

Click it for a floating glass panel with your full quota status:

| Section | Shows |
|---|---|
| **Weekly** | % of weekly token quota remaining, plus a live `Regenerates 2% in 1h 8m` countdown |
| **Requests · 5h** | Rolling 5-hour request window usage and next tick |
| **Search · hourly** | Hourly search requests used vs. limit, and when it renews |

The footer has a last-updated stamp plus **Refresh** and **Quit** glass buttons. The panel adapts to light and dark mode, floats above fullscreen apps, and dismisses on outside-click or <kbd>Esc</kbd>.

## Features

- ✦ Menu bar title with weekly % remaining (or `✦ …` while loading, `✦ !` on error)
- 🪟 True Liquid Glass: `NSGlassEffectView` panel, glass-styled buttons, system-adaptive materials
- 🔄 Auto-refreshes every 5 minutes, whenever you open the panel, or on demand
- 🔑 No config: picks up `SYNTHETIC_API_KEY` from your environment automatically
- 📦 Single-file AppKit app (`Sources/main.swift`) — no Xcode project, no SwiftPM, no pods

## Requirements

- macOS 26 (Tahoe) or later — the app uses `NSGlassEffectView` and glass button styles
- Swift toolchain (`xcode-select --install` is enough)
- A Synthetic API key

## Build & run

```sh
./build.sh          # → build/Syn Usage.app
open "build/Syn Usage.app"
```

To have it always available, drag `Syn Usage.app` into `/Applications` and add it
under **System Settings → General → Login Items**.

## API key

The app reads `SYNTHETIC_API_KEY` from, in order:

1. The environment it inherits (launching from a shell that has it exported)
2. An `export SYNTHETIC_API_KEY=…` line in `~/.zshenv`, `~/.zshrc`, `~/.zprofile`, `~/.profile`, or `~/.bash_profile`
3. Interactive `zsh` (`printf %s "$SYNTHETIC_API_KEY"`) as a fallback

So the usual setup works even when macOS launches the app from Finder or Login Items:

```sh
echo 'export SYNTHETIC_API_KEY="your-key-here"' >> ~/.zshrc
```

## Configuration

Two constants at the top of `Sources/main.swift`:

```swift
let refreshInterval: TimeInterval = 300   // auto-refresh cadence (seconds)
let panelWidth: CGFloat = 320             // glass panel width
```

## How it works

One `GET https://api.synthetic.new/v2/quotas` request (same endpoint as CLI tools)
with a `Bearer` token, parsed with `JSONSerialization`, rendered with `NSStatusItem`
+ a borderless, non-activating `NSPanel`. That's it.

## Disclaimer

Unofficial, community project — not affiliated with or endorsed by Synthetic.
No API key is ever stored, logged, or transmitted anywhere except to
`api.synthetic.new`.

## License

[MIT](LICENSE) © Connor McDonough
