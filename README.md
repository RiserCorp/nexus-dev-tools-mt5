# nexus-dev-tools-mt5

**Nexus Trade — Developer SDK for MetaTrader 5 EAs**

A MQL5 SDK that lets EA developers integrate their expert advisors with the [Nexus Trade Marketplace](https://nexustradestudio.com). Handle authentication, licence validation, heartbeating, and dashboard rendering with a few `#include` statements.

---

## Requirements

- MetaTrader 5 (build 3000+)
- A [Nexus Trade](https://nexustradestudio.com) developer account
- A published EA on the marketplace (or an approved submission in progress)
- MT5 allowed URL: `https://ea.nexustradestudio.com`

  _Tools → Options → Expert Advisors → Allowed URLs_

---

## Quick start

### 1. Download and extract

Download `nexus-dev-tools-mt5-vX.Y.Z.zip` from the [latest release](../../releases/latest) and extract it into your EA's project folder or a shared `lib/` directory.

```
YourEA/
├── YourEA.mq5
└── nexus-dev-tools-mt5/
    ├── NexusDevTools.mq5   ← working template — copy and rename
    └── modules/
        ├── NxPayload.mqh
        ├── NxHttpClient.mqh
        ├── NxRetry.mqh
        ├── NxAuth.mqh
        ├── NxHealthcheck.mqh
        ├── NxVisual.mqh
        └── NxDashboard.mqh
```

### 2. Include the modules

```mql5
#include "nexus-dev-tools-mt5/modules/NxPayload.mqh"
#include "nexus-dev-tools-mt5/modules/NxHttpClient.mqh"
#include "nexus-dev-tools-mt5/modules/NxRetry.mqh"
#include "nexus-dev-tools-mt5/modules/NxAuth.mqh"
#include "nexus-dev-tools-mt5/modules/NxHealthcheck.mqh"
#include "nexus-dev-tools-mt5/modules/NxDashboard.mqh"
// NxVisual.mqh is pulled in transitively by NxDashboard.mqh
```

### 3. Use the template

Copy `NexusDevTools.mq5` and rename it to your EA. Fill in the marked sections — everything else is wired automatically.

### 4. Required input parameters

| Parameter | Type | Where to find it |
|---|---|---|
| `InpApiKey` | string | User's API key — copied from nexustradestudio.com → Profile |
| `InpToolKey` | string | Your tool key — copied from Dev Area → Keys & SDK |
| `InpMagic` | ulong | Magic number unique per EA instance (session tracking) |

The `InpMagic` value is passed to `Authenticate()` so the server can distinguish multiple instances of the same EA running on different charts. **Each instance must have a unique magic number.** Reuse across instances will collide in the backend session store.

---

## Configure the dashboard

Call `Configure()` once in `OnInit()` before any `Render()` call:

```mql5
g_dashboard.Configure(InpCorner,                                  // 0=TL 1=TR 2=BL 3=BR
                      InpShowCompte, InpShowLicence,
                      InpShowWarnings, InpShowErrors, InpShowInfos,
                      10, 10,                                     // x/y margins
                      MY_EA_NAME);                                // header brand name
```

The `brand_name` parameter is optional — if omitted, the dashboard header shows `NEXUS DEV TOOLS`. For a polished EA, pass your EA's name (automatically upper-cased visually by the Consolas monospace font).

---

## How authentication works

```
OnInit()
  ├─ TryResume() — POST /marketplace/v1/resume
  │    { session_token (from GlobalVar), magic_number }
  │    → 200 resumed=true   → session reused (no re-auth)
  │    → else               → fall through to full auth
  │
  └─ Authenticate() — POST /marketplace/v1/auth
       { api_key, tool_key, account_login, account_server, magic_number }
       → 200  session_token, expires_at    → g_sdk_ready = true
       → 401  AUTH_REJECTED                → exponential retry
       → 404  LICENCE_NOT_FOUND            → exponential retry
       → net  NETWORK_ERROR                → exponential retry

OnTimer() every 30s
  ├─ if !g_sdk_ready  → TryRetry()
  └─ if g_sdk_ready + heartbeat due (60min)
         POST /marketplace/v1/heartbeat { session_token }
         → SESSION_EXPIRED  → ForceReAuth()
```

Retry delays: 5s → 15s → 30s → 60s → EXHAUSTED (state machine in `NxRetry.mqh`).

### Session resumption

On `OnInit()`, the SDK first tries to resume an existing session using a token stored in MT5 `GlobalVariables` (keyed by `tool_key + magic_number`). This avoids burning a fresh auth request on every chart refresh, terminal restart, or brief network hiccup.

A new session is created only if resumption fails (expired or not found).

---

## Admin test mode

When a platform admin enters their API key (`ntk-` prefix), the server issues an `admin_test` session (8-hour validity). The EA runs without a licence or account assignment — useful for testing before approving a submission.

The dashboard shows `[ADM] admin_test` in the LICENCE section. Admin sessions are **not** persisted to `GlobalVariables` — each restart creates a fresh one for clean tracking in `admin_test_sessions`.

---

## Strategy Tester

The SDK detects Strategy Tester / Optimizer / Visual / Frame modes via `MQLInfoInteger(MQL_TESTER)` and bypasses authentication automatically. Your trading logic runs unchanged; `g_sdk_ready` is set to `true` and the EA reports a `TESTER_MODE` status.

No network call is made in tester mode, so backtests remain fast and offline-safe.

---

## Module reference

| Module | Responsibility |
|---|---|
| `NxPayload.mqh` | `NexusPayload` struct, `NxLog()`, `NxLogBuffer` (ring buffer, 64 entries) |
| `NxHttpClient.mqh` | POST (public) and POST Bearer (authenticated) with JSON response parsers |
| `NxRetry.mqh` | Exponential retry state machine — IDLE → PENDING → EXHAUSTED |
| `NxAuth.mqh` | `Authenticate()`, `TryRetry()`, `ForceReAuth()`, `TryResume()`, admin session detection |
| `NxHealthcheck.mqh` | 60-minute heartbeat, auto re-auth on SESSION_EXPIRED |
| `NxVisual.mqh` | Shared visual primitives — palette, fonts, labels/rects/separators, progress bars, semantic status colors |
| `NxDashboard.mqh` | 5-section dashboard overlay with 2-pass layout (measure + draw), works on all 4 corners |

---

## Logging

```mql5
NxLog(NX_INFO,  "EA started");
NxLog(NX_WARN,  "Spread too wide — skipping signal");
NxLog(NX_ERROR, "Order rejected by broker");

NexusPayload result = NxOk("SIGNAL_OK", "Long signal on EURUSD");
NexusPayload err    = NxErr("TRADE_FAIL", "Insufficient margin");
```

Logs appear in the MT5 Journal, are stored in the ring buffer (64 entries), and rendered in the dashboard ERREURS / AVERTISSEMENTS sections (truncated at ~54 chars with `..` overflow indicator).

---

## Dashboard

A compact 360px panel rendered in the chart corner selected by the user. Five sections, each toggleable via EA input parameters:

| Section | Content |
|---|---|
| Header | EA name (from `Configure(…, brand_name)`) + state pill (ONLINE / ADMIN / Retry n/4 / FAILED) |
| COMPTE MT5 | Login, server, balance, equity, floating P/L, drawdown % + progress bar (10% ref), open positions |
| LICENCE | Status badge, EA name, version, session expiry + countdown bar (30d window) |
| ERREURS | Last 3 `NX_ERROR` entries with timestamp |
| AVERTISSEMENTS | Last 3 `NX_WARN` entries with timestamp |
| INFOS | EA version, magic number, start time, uptime, last/next heartbeat |

### Rendering internals

The dashboard uses a **2-pass layout**:

1. **Measure pass** — walks the entire layout with drawing skipped, just to compute the total panel height.
2. **Draw pass** — places the background rectangle first (so it's at the bottom of the z-order and doesn't mask labels), then re-walks the layout to draw each element on top.

All objects are internally anchored to `CORNER_LEFT_UPPER` regardless of the user-selected corner. The panel origin is computed dynamically from `ChartGetInteger(CHART_WIDTH_IN_PIXELS / CHART_HEIGHT_IN_PIXELS)` and the measured height. This means:

- Bottom corners (2, 3) render **top-to-bottom** correctly (no more inverted layouts).
- The dashboard adapts automatically if the chart is resized.
- The background always sits beneath the content.

### Corner positioning

| `InpCorner` | Position |
|---|---|
| `0` (default) | Top-Left |
| `1` | Top-Right |
| `2` | Bottom-Left |
| `3` | Bottom-Right |

**Recommended default: `0` (Top-Left)** — doesn't mask the latest price candles on the right of the chart.

### CoverChart (optional)

If your EA runs on a dedicated display-only tab, call `g_dashboard.CoverChart()` in `OnInit()` to hide the chart widgets (grid, volumes, bid/ask lines) and set the chart background to black. The panel then sits on a clean surface.

---

## Versioning

This SDK follows [SemVer](https://semver.org/):

- **MAJOR** — breaking API changes (removed method, changed signature that breaks existing EAs)
- **MINOR** — backward-compatible feature additions (new optional parameters, new modules)
- **PATCH** — bug fixes with no API impact

Always pin your EA to a specific SDK version by committing the `nexus-dev-tools-mt5` folder into your EA's repository. See [CHANGELOG.md](./CHANGELOG.md) for version history.

---

## Roadmap

- [ ] Send custom logs to the platform (`POST /marketplace/v1/dev/logs`)
- [ ] Custom EA metrics (signals, drawdown, positions)
- [ ] In-dashboard marketplace rating widget
- [ ] `i18n` support for dashboard section titles (currently French)
- [ ] Type migration `int magic_number → long` in `NxAuth` for consistency with MT5 API

---

## License

This SDK is provided to Nexus Trade approved developer partners.  
See [nexustradestudio.com/terms](https://nexustradestudio.com/terms) for usage terms.
