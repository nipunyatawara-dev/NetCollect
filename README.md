# NetCollect 🌐

A native, ultra-lightweight macOS application that monitors and aggregates per-application network data usage across **Daily (Today)**, **Weekly (This Week)**, and **Monthly (This Month)** timeframes.

Built with **SwiftUI**, **Swift Charts**, Darwin kernel process accounting (`libproc`), and embedded **SQLite**, designed following Apple's fluid interface guidelines (`/apple-design`).

---

## ✨ Features

- **📊 Comprehensive Timeframe Analytics**: Toggle smoothly between **Today**, **This Week**, **This Month**, and **All Time**.
- **⚡️ Real-Time Throughput**: Live upload and download speed meters (KB/s, MB/s) with a status indicator in the navigation bar and Menu Bar extra.
- **📱 Per-Application Attribution**: Automatically consolidates background helpers (e.g. Chrome Renderers, Spotify Helpers) into their parent application bundle and displays native high-resolution app icons.
- **📈 Interactive Network Activity Chart**: Visualizes network activity trends using Apple Swift Charts with smooth gradient area fills and hover inspection.
- **🚀 Dual Foreground & Background Modes**:
  - **Menu Bar Only (Background Mode)**: Completely hides from the Dock and Cmd-Tab switcher, running quietly in the macOS menu bar with negligible resource usage (< 0.1% CPU, < 25 MB RAM).
  - **Full Dashboard (Foreground Mode)**: Rich macOS window with search, category filtering (User Apps vs System), and sorting (Total Usage, Download, Upload, Alphabetical).
- **🗄 Embedded SQLite Persistence**: Batched in-memory writes to embedded SQLite database (`~/Library/Application Support/NetCollect/netcollect.sqlite`) ensure zero disk thrashing and instant queries.
- **🎨 Apple Design Compliance**: Fluid spring animations (`dampingFraction: 0.85`), translucent materials (`.ultraThinMaterial`), optical typography tracking, and `.monospacedDigit()` for jitter-free numbers.

---

## 🛠 Project Structure

```
NetCollect/
├── Package.swift                             # Swift Package configuration (macOS 14+)
├── NetCollect.app/                           # Compiled standalone macOS Application Bundle
├── Sources/
│   ├── NetCollect/                           # Executable entrypoint (main.swift)
│   └── NetCollectCore/                       # Core Framework
│       ├── App/
│       │   ├── NetCollectApp.swift           # SwiftUI App definition (MenuBarExtra & WindowGroup)
│       │   └── AppDelegate.swift             # AppKit lifecycle & dynamic activation policy
│       ├── Models/
│       │   ├── AppUsageRecord.swift          # App usage data model & ByteCountFormatter
│       │   ├── TimeframeFilter.swift         # Daily, Weekly, Monthly, All-Time intervals
│       │   ├── LiveBandwidth.swift           # Real-time network speed metrics
│       │   ├── ChartDataPoint.swift          # Time-series data points for Swift Charts
│       │   └── FilterAndSortOptions.swift    # Category & sorting enums
│       ├── Services/
│       │   ├── NetworkCollector.swift        # Background nettop process streaming engine
│       │   ├── AppResolver.swift             # PID -> App bundle & high-res icon resolver
│       │   ├── DatabaseService.swift         # SQLite persistence for hourly & daily rollups
│       │   └── LaunchAtLoginService.swift    # SMAppService helper for macOS login items
│       ├── ViewModels/
│       │   └── AppUsageViewModel.swift       # Observable state management
│       └── Views/
│           ├── Dashboard/
│           │   ├── DashboardView.swift       # Main window view with glassmorphism design
│           │   ├── HeroMetricsCard.swift     # Translucent summary metric cards
│           │   ├── UsageChartView.swift      # Interactive Swift Charts breakdown
│           │   ├── AppUsageRowView.swift     # Application row with icons, meters & stats
│           │   └── TimeframeSegmentPicker.swift # Fluid animated spring segmented control
│           ├── MenuBar/
│           │   └── MenuBarPopoverView.swift  # Status bar quick-glance popover
│           └── Settings/
│               └── SettingsView.swift        # Preferences & background mode configuration
├── Tests/
│   └── NetCollectTests/                      # Automated test suite
└── Scripts/
    └── build_app.sh                          # Compiles release and builds NetCollect.app bundle
```

---

## 🚀 Building & Running

### Option 1: Run the Standalone `.app`
```bash
open NetCollect.app
```
*(Or drag `NetCollect.app` into `/Applications`)*

### Option 2: Run from Swift Package Manager
```bash
swift run NetCollect
```

### Option 3: Run the Test Suite
```bash
swift run NetCollectTests
```

### Option 4: Recompile Release App Bundle
```bash
./Scripts/build_app.sh
```
