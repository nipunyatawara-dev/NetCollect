# Changelog

All notable changes to NetCollect are documented here.

## 1.2.0 — 2026-11-18

### Added

- Updated the dashboard, menu bar panel, and Settings with native macOS controls and Liquid Glass on supported systems.
- Added a usage period menu beside live bandwidth. It starts on Today and switches the totals, chart, and application list together.
- Moved application search, filtering, and sorting directly above the list.

### Fixed

- Kept the current usage figures visible while loading a new period. Totals roll when the unit stays the same and fade in as a complete value when the unit changes. Reduce Motion turns off the transition.
- Fixed duplicate dashboard windows when reopening the app and improved launch-at-login status feedback.
- Made SQLite writes retry safely and flush quiet samples on a timer. Collection drains before quitting, and live bandwidth uses 64-bit interface counters.
- Restricted access to local history and lock files and enabled Hardened Runtime for the app bundle.

## 1.1.0 — 2026-08-28

### Added

- Added date-period history deletion in Settings for Today, the last 3, 7, 14, 30, or 90 days, and All History.
- Added a destructive-action confirmation that identifies the selected deletion period.

### Fixed

- Ranged deletion now removes matching in-memory samples as well as saved SQLite rows, preventing deleted usage from returning on the next flush.
- Deletion periods use local calendar-day boundaries, including daylight-saving-time transitions.

## 1.0.0 — 2026-08-18

### Added

- Initial release with per-application network usage, live bandwidth speeds, charts, menu bar support, and local SQLite history.
