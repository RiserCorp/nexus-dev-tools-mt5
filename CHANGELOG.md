# Changelog

All notable changes to `nexus-dev-tools-mt5` are documented here.  
Format: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) — Versioning: [SemVer](https://semver.org/).

---

## [1.1.0] — 2026-04-21

### Added
- `NxVisual.mqh` — shared visual primitives: palette (near-black pro-terminal look), Consolas font, label/rect/separator helpers, progress bars with semantic status colors (Safe 0–50% / Warning 50–80% / Danger ≥80%), `NxLineH`, `NxFormatSigned`, `NxFormatDuration`, `NxParseIsoDate`
- `CNxDashboard::Configure()` — new optional `brand_name` parameter. The header now shows the EA name instead of the hardcoded "NEXUS DEV TOOLS". Backward-compatible: omitting the parameter falls back to the legacy brand string.
- `NxDashData::magic_number` — new `long` field, surfaced in the INFOS section as `Magic: <value>` (or `--` if not set).
- `NexusDevTools.mq5` — new `input ulong InpMagic` parameter, passed to all `Authenticate` / `TryRetry` / `ForceReAuth` calls.
- Drawdown progress bar in the COMPTE MT5 section (10% tolerance reference).
- Session expiry countdown bar in the LICENCE section (30-day window, red <3d, yellow <7d, green otherwise).
- Floating P/L row in the COMPTE MT5 section with signed formatting (`+1234.56` / `-1234.56`).

### Changed
- Dashboard panel width: 310 → 360px (more room for log messages).
- Log truncation: 42 → 56 chars. Overflowed lines end with `..` for a clear cue.
- Dashboard rendering is now **two-pass**: a measure pass computes the total height, then a draw pass places the background first (correct z-order) and fills the content. Fixes the flashing / overlap issues on all 4 corners.
- All dashboard objects are anchored to `CORNER_LEFT_UPPER` internally — the user-selected corner (0–3) now maps to a computed top-left origin via `ChartGetInteger(CHART_WIDTH / HEIGHT)`. Dashboards on bottom corners (`InpCorner = 2` or `3`) now render top-to-bottom correctly.
- Empty log sections show grammatically correct French messages — `Aucune erreur recente` / `Aucun avertissement recent` instead of `Aucun ERREURS`.
- `NexusGoldEA.mq5`: default `InpCorner` changed from `1` (Top-Right) to `0` (Top-Left) so the dashboard no longer masks the latest price candles.

### Fixed
- **Magic number was ignored during authentication.** `NexusDevTools.mq5` and `NexusGoldEA.mq5` called `Authenticate()` without passing the magic number, defaulting to `0`. This caused session-token collisions between multiple instances of the same EA on different charts and broke server-side per-instance tracking. Both templates now pass their magic explicitly.
- `NxAuth::TryResume` — removed dead code path that read from a non-existent `GlobalVariable` as a double before overwriting with `GetSessionVar()`.
- Dashboard background no longer masks the panel content (z-order issue caused by creating the background last).
- Pill position in the header now clamps against the dynamic title width instead of a hardcoded 130px minimum — prevents overlap with long EA names.

---

## [1.0.0] — 2026-03-22

### Added
- `NxPayload.mqh` — `NexusPayload` struct, `NxLog()`, `NxOk()`, `NxErr()`, `NxWarn()`, `NxLogBuffer` ring buffer (64 entries)
- `NxHttpClient.mqh` — HTTP POST (public) and POST Bearer (authenticated) with JSON response parsing
- `NxRetry.mqh` — exponential retry state machine: IDLE → PENDING → EXHAUSTED (5s / 15s / 30s / 60s delays)
- `NxAuth.mqh` — `Authenticate()`, `TryRetry()`, `ForceReAuth()`, `TryResume()`, admin session detection (`IsAdminSession()`)
- `NxHealthcheck.mqh` — 60-minute heartbeat with automatic re-auth on `SESSION_EXPIRED`
- `NxDashboard.mqh` — 5-section MT5 dashboard overlay (Account, Licence, Errors, Warnings, Infos), configurable corner
- `NexusDevTools.mq5` — full integration template with all modules wired and marked extension points
- Admin test mode: admin API keys bypass licence/account validation and receive an 8-hour `admin_test` session
- Session resumption: token persisted in MT5 `GlobalVariables` survives EA reattachment and terminal restart
