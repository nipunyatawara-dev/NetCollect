# Changelog

All notable changes to NetCollect are documented here.

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
