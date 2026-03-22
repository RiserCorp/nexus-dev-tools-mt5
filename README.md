# nexus-dev-tools-mt5

**Nexus Trade — Developer SDK for MetaTrader 5 EAs**

A MQL5 SDK that lets EA developers integrate their expert advisors with the [Nexus Trade Marketplace](https://nexustradestudio.com). Handle authentication, licence validation, heartbeating, and dashboard rendering with a few `#include` statements.

---

## Requirements

- MetaTrader 5 (build 3000+)
- A [Nexus Trade](https://nexustradestudio.com) developer account
- A published EA on the marketplace (or an approved submission in progress)
- MT5 allowed URL: `https://api.nexustradestudio.com`

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
```

### 3. Use the template

Copy `NexusDevTools.mq5` and rename it to your EA. Fill in the marked sections — everything else is wired automatically.

### 4. Required input parameters

| Parameter | Where to find it |
|---|---|
| `InpApiKey` | User's API key — copied from nexustradestudio.com → Profile |
| `InpToolKey` | Your tool key — copied from Dev Area → Keys & SDK |

---

## How authentication works

```
OnInit()
  └─ POST /marketplace/v1/auth
       { api_key, tool_key, account_login, account_server }
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

---

## Admin test mode

When a platform admin enters their API key, the server issues an `admin_test` session (8-hour validity). The EA runs without a licence or account assignment — useful for testing before approving a submission.

The dashboard shows `[ADM] admin_test` in the LICENCE section.

---

## Module reference

| Module | Responsibility |
|---|---|
| `NxPayload.mqh` | `NexusPayload` struct, `NxLog()`, `NxLogBuffer` (ring buffer, 64 entries) |
| `NxHttpClient.mqh` | POST (public) and POST Bearer (authenticated) with JSON response parsers |
| `NxRetry.mqh` | Exponential retry state machine — IDLE → PENDING → EXHAUSTED |
| `NxAuth.mqh` | `Authenticate()`, `TryRetry()`, `ForceReAuth()`, admin session detection |
| `NxHealthcheck.mqh` | 60-minute heartbeat, auto re-auth on SESSION_EXPIRED |
| `NxDashboard.mqh` | 5-section dashboard overlay (Account, Licence, Errors, Warnings, Infos) |

---

## Logging

```mql5
NxLog(NX_INFO,  "EA started");
NxLog(NX_WARN,  "Spread too wide — skipping signal");
NxLog(NX_ERROR, "Order rejected by broker");

NexusPayload result = NxOk("SIGNAL_OK", "Long signal on EURUSD");
NexusPayload err    = NxErr("TRADE_FAIL", "Insufficient margin");
```

Logs appear in the MT5 Journal, are stored in the ring buffer (64 entries), and rendered in the dashboard ERROR / WARNING sections.

---

## Dashboard

Five configurable sections — toggle each via EA input parameters:

| Section | Content |
|---|---|
| Account | Login, server, balance, equity, drawdown %, open positions |
| Licence | Status, EA name, version, session expiry |
| Errors | Last 4 `NX_ERROR` entries |
| Warnings | Last 4 `NX_WARN` entries |
| Infos | EA version, start time, uptime, last/next heartbeat |

Corner: `0 = Top-Left · 1 = Top-Right · 2 = Bottom-Left · 3 = Bottom-Right`

---

## Roadmap

- [ ] Send custom logs to the platform (`POST /marketplace/v1/dev/logs`)
- [ ] Custom EA metrics (signals, drawdown, positions)
- [ ] In-dashboard marketplace rating widget

---

## License

This SDK is provided to Nexus Trade approved developer partners.  
See [nexustradestudio.com/terms](https://nexustradestudio.com/terms) for usage terms.
