# NetCollect

NetCollect is a macOS app that monitors network data usage per application. It tracks downloads and uploads across today, the current week, the current month, and all time.

Written in Swift using SwiftUI, Swift Charts, `nettop`, and SQLite.

---

## Preview

<p align="center">
  <img src="docs/screenshots/dashboard.png" width="760" alt="NetCollect Dashboard" />
</p>

<p align="center">
  <img src="docs/screenshots/menubar.png" width="360" alt="NetCollect Menu Bar Popover" />
</p>

---

## Features

- **Timeframe tracking**: View usage by day, week, month, or total history.
- **Live bandwidth speeds**: Shows current upload and download rates in the menu bar and dashboard window.
- **App grouping**: Groups helper processes (like Chrome renderers or Spotify helpers) under their main application.
- **Activity graph**: Interactive chart showing bandwidth over time with hover inspection.
- **Menu bar and window modes**: Keep it in the menu bar for quick checks, or open the main window to search, filter by system/user apps, and sort by usage.
- **Local storage**: Stores history in a local SQLite file at `~/Library/Application Support/NetCollect/netcollect.sqlite`. No data leaves your Mac.
- **Low resource usage**: Uses short-lived network snapshots instead of a continuously running sampler.

---

## Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon Mac
- Xcode 15+ or Swift 6.0+ (to build from source)

---

## Installation

### Homebrew (Recommended)

```bash
brew install --cask nipunyatawara-dev/tap/netcollect
```

Or add the tap first:
```bash
brew tap nipunyatawara-dev/tap
brew install --cask netcollect
```

### Direct Download (DMG)

Download `NetCollect-v1.0.0.dmg` from the [Releases](https://github.com/nipunyatawara-dev/NetCollect/releases/latest) page, open the disk image, and drag `NetCollect.app` into your Applications folder.

---

## Development and building

### Run with Swift Package Manager
```bash
swift run NetCollect
```

### Run tests
```bash
swift run NetCollectTests
```

### Build release app bundle
```bash
./Scripts/build_app.sh
```

### Build release DMG
```bash
./Scripts/create_dmg.sh
```

---

## Project structure

```
NetCollect/
├── Package.swift                    # Swift package manifest
├── NetCollect.app/                  # Application bundle
├── Sources/
│   ├── NetCollect/                  # App entry point (main.swift)
│   └── NetCollectCore/              # Application logic and UI
│       ├── App/                     # App lifecycle and menu bar setup
│       ├── Models/                  # Data types (records, bandwidth, chart points)
│       ├── Services/                # Network collector (nettop), resolver, SQLite
│       ├── ViewModels/              # App state
│       └── Views/                   # Dashboard, menu bar popup, settings
├── Tests/
│   └── NetCollectTests/             # Unit test suite
└── Scripts/
    ├── build_app.sh                 # App bundle packager
    ├── create_dmg.sh                # DMG packager
    ├── create_icns.sh               # Icon converter
    └── generate_icon.swift          # Icon generation script
```

---

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| <kbd>⌘</kbd> <kbd>,</kbd> | Open settings |
| <kbd>⌘</kbd> <kbd>W</kbd> | Close dashboard window |
| <kbd>⌘</kbd> <kbd>Q</kbd> | Quit NetCollect |

---

## License

MIT License. See [LICENSE](LICENSE) for details.
