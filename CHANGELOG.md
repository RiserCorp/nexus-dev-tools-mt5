# Changelog

All notable changes to `nexus-dev-tools-mt5` are documented here.  
Format: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) — Versioning: [SemVer](https://semver.org/).

---

## [1.0.0] — 2026-03-22

### Added
- `NxPayload.mqh` — `NexusPayload` struct, `NxLog()`, `NxOk()`, `NxErr()`, `NxWarn()`, `NxLogBuffer` ring buffer (64 entries)
- `NxHttpClient.mqh` — HTTP POST (public) and POST Bearer (authenticated) with JSON response parsing
- `NxRetry.mqh` — exponential retry state machine: IDLE → PENDING → EXHAUSTED (5s / 15s / 30s / 60s delays)
- `NxAuth.mqh` — `Authenticate()`, `TryRetry()`, `ForceReAuth()`, admin session detection (`IsAdminSession()`)
- `NxHealthcheck.mqh` — 60-minute heartbeat with automatic re-auth on `SESSION_EXPIRED`
- `NxDashboard.mqh` — 5-section MT5 dashboard overlay (Account, Licence, Errors, Warnings, Infos), configurable corner
- `NexusDevTools.mq5` — full integration template with all modules wired and marked extension points
- Admin test mode: admin API keys bypass licence/account validation and receive an 8-hour `admin_test` session
