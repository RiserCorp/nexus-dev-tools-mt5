//+------------------------------------------------------------------+
//| NexusDevTools.mq5                                                |
//| Nexus Trade — Developer SDK Template                             |
//|                                                                  |
//| HOW TO USE THIS TEMPLATE:                                        |
//|   1. Copy the nexus-dev-tools-mt5 folder into your EA project.  |
//|   2. Include the modules you need (all or a subset).            |
//|   3. Fill in your EA logic in the marked sections below.        |
//|   4. Set your tool_key (from Dev Area > Keys & SDK).            |
//|   5. Users enter their own API key in the EA settings.          |
//|                                                                  |
//| Authentication flow:                                             |
//|   OnInit   → POST /marketplace/v1/auth (api_key + tool_key)    |
//|   OnTimer  → heartbeat every 60 min                             |
//|   On fail  → exponential retry (5s / 15s / 30s / 60s)          |
//|                                                                  |
//| Admin bypass:                                                    |
//|   If an admin's API key is entered, the server returns an        |
//|   admin_test session — no licence or account required.           |
//|   This lets admins test any EA without a marketplace licence.   |
//|                                                                  |
//| IMPORTANT — add to MT5 allowed URLs:                             |
//|   https://api.nexustradestudio.com                               |
//|   Tools → Options → Expert Advisors → Allowed URLs              |
//+------------------------------------------------------------------+
#property copyright "Your Name / Studio"
#property link      "https://nexustradestudio.com"
#property version   "1.00"
#property strict
#property description "Nexus Dev Tools template — replace this with your EA description."

// ─── SDK Includes ─────────────────────────────────────────────────────────
#include "modules/NxPayload.mqh"
#include "modules/NxHttpClient.mqh"
#include "modules/NxRetry.mqh"
#include "modules/NxAuth.mqh"
#include "modules/NxHealthcheck.mqh"
#include "modules/NxDashboard.mqh"

//==========================================================================
// INPUT PARAMETERS
//==========================================================================

input group "=== Nexus Trade Marketplace ==="
input string InpApiKey  = "";  // API Key — user copies from nexustradestudio.com
input string InpToolKey = "";  // Tool Key — developer copies from Dev Area > Keys & SDK

input group "=== Dashboard ==="
input int  InpCorner        = 0;     // Corner: 0=TopLeft 1=TopRight 2=BotLeft 3=BotRight
input bool InpShowCompte    = true;  // Show account section
input bool InpShowLicence   = true;  // Show licence section
input bool InpShowWarnings  = true;  // Show warnings section
input bool InpShowErrors    = true;  // Show errors section
input bool InpShowInfos     = true;  // Show infos section

//==========================================================================
// SDK CONFIGURATION — Edit these constants for your EA
//==========================================================================

#define MY_EA_NAME     "My EA Name"    // Shown in dashboard
#define MY_EA_VERSION  "1.0.0"         // Shown in dashboard

#define SDK_MARKETPLACE_URL  "https://api.nexustradestudio.com"
#define SDK_TIMER_INTERVAL   30   // seconds (keep at 30 for responsive retries)

//==========================================================================
// GLOBAL STATE
//==========================================================================

bool   g_sdk_ready   = false;   // true when auth succeeded + EA is operational
datetime g_start_time = 0;

// ─── SDK Instances ────────────────────────────────────────────────────────
CNxHttpClient  *g_http        = NULL;
CNxAuth        *g_auth        = NULL;
CNxHealthcheck *g_healthcheck = NULL;
CNxDashboard   *g_dashboard   = NULL;

//==========================================================================
// Forward declarations
//==========================================================================
NxDashData BuildDashData();
void       RefreshDashboard();

//==========================================================================
// OnInit
// Always returns INIT_SUCCEEDED — the dashboard renders regardless of auth
// outcome. OnTimer is a no-op while g_sdk_ready == false.
//==========================================================================

int OnInit()
{
   g_sdk_ready  = false;
   g_start_time = TimeGMT();

   // ── Instantiate SDK modules ──────────────────────────────────────
   g_http        = new CNxHttpClient();
   g_auth        = new CNxAuth(g_http);
   g_healthcheck = new CNxHealthcheck(g_http);
   g_dashboard   = new CNxDashboard();

   // ── Configure dashboard ──────────────────────────────────────────
   g_dashboard.Configure(InpCorner,
                         InpShowCompte, InpShowLicence,
                         InpShowWarnings, InpShowErrors, InpShowInfos);

   // Uncomment if attaching to a dedicated chart (hides chart display):
   // g_dashboard.CoverChart();

   g_dashboard.RenderConnecting();

   // ── Configure HTTP ───────────────────────────────────────────────
   g_http.Init(SDK_MARKETPLACE_URL);

   // ── Authenticate ─────────────────────────────────────────────────
   NexusPayload auth_result = g_auth.Authenticate(InpApiKey, InpToolKey);

   if(auth_result.ok)
   {
      g_healthcheck.OnAuthSuccess();
      g_sdk_ready = true;
      NxLog(NX_INFO, MY_EA_NAME + " v" + MY_EA_VERSION + " initialised successfully.");

      //================================================================
      // YOUR EA INIT LOGIC HERE
      // Example: load config, set up indicators, etc.
      // g_sdk_ready == true means the licence is valid.
      //================================================================
   }
   else
   {
      // Auth failed — retry is scheduled automatically.
      // The EA continues running; OnTimer will drive retries.
      g_dashboard.RenderAuthError(auth_result.code, auth_result.message);
      NxLog(NX_WARN, "Auth failed at startup. Will retry automatically.");
   }

   RefreshDashboard();
   EventSetTimer(SDK_TIMER_INTERVAL);
   return INIT_SUCCEEDED;
}

//==========================================================================
// OnDeinit
//==========================================================================

void OnDeinit(const int reason)
{
   EventKillTimer();

   if(g_dashboard   != NULL) { g_dashboard.Clear(); delete g_dashboard;   g_dashboard   = NULL; }
   if(g_healthcheck != NULL) { delete g_healthcheck; g_healthcheck = NULL; }
   if(g_auth        != NULL) { delete g_auth;        g_auth        = NULL; }
   if(g_http        != NULL) { delete g_http;        g_http        = NULL; }

   NxLogBuffer::Release();
   Print("[NexusDev] Deinitialized. Reason: ", reason);
}

//==========================================================================
// OnTimer
//==========================================================================

void OnTimer()
{
   // ── Retry pending auth ───────────────────────────────────────────
   if(!g_sdk_ready)
   {
      NexusPayload retry = g_auth.TryRetry(InpApiKey, InpToolKey);
      if(retry.ok && retry.code != "RETRY_SKIP")
      {
         // Auth succeeded on retry
         g_healthcheck.OnAuthSuccess();
         g_sdk_ready = true;
         NxLog(NX_INFO, "Auth succeeded on retry. EA is now operational.");

         //============================================================
         // YOUR EA RE-INIT LOGIC HERE (same as OnInit success block)
         //============================================================
      }
      RefreshDashboard();
      return;
   }

   // ── Heartbeat ────────────────────────────────────────────────────
   if(g_healthcheck.IsDue())
   {
      NexusPayload hb = g_healthcheck.Send();
      if(!hb.ok && hb.code == "SESSION_EXPIRED")
      {
         NxLog(NX_WARN, "Session expired — re-authenticating...");
         NexusPayload reauth = g_auth.ForceReAuth(InpApiKey, InpToolKey);
         if(reauth.ok)
         {
            g_healthcheck.OnAuthSuccess();
            NxLog(NX_INFO, "Re-auth successful.");
         }
         else
         {
            g_sdk_ready = false;
            NxLog(NX_ERROR, "Re-auth failed. EA suspended until auth succeeds.");
         }
      }
   }

   //====================================================================
   // YOUR EA TIMER LOGIC HERE
   // At this point g_sdk_ready == true and the session is valid.
   // Example: scan for trade signals, update your own dashboard, etc.
   //====================================================================

   RefreshDashboard();
}

//==========================================================================
// OnTrade  (optional — remove if not needed)
//==========================================================================

void OnTrade()
{
   if(!g_sdk_ready) return;

   //======================================================================
   // YOUR TRADE EVENT LOGIC HERE
   //======================================================================

   RefreshDashboard();
}

//==========================================================================
// BuildDashData — collect current account + EA state for the dashboard
//==========================================================================

NxDashData BuildDashData()
{
   NxDashData d;

   d.acct_login    = AccountInfoInteger(ACCOUNT_LOGIN);
   d.acct_server   = AccountInfoString(ACCOUNT_SERVER);
   d.balance       = AccountInfoDouble(ACCOUNT_BALANCE);
   d.equity        = AccountInfoDouble(ACCOUNT_EQUITY);
   d.open_positions = PositionsTotal();

   // Simple drawdown: (balance - equity) / balance * 100
   d.drawdown_pct = (d.balance > 0 && d.equity < d.balance)
                    ? (d.balance - d.equity) / d.balance * 100.0
                    : 0.0;

   // Licence info
   if(g_auth.IsAdminSession())
      d.licence_status = "admin_test";
   else if(g_sdk_ready)
      d.licence_status = "active";
   else if(g_auth.IsRetryExhausted())
      d.licence_status = "unlinked";
   else
      d.licence_status = "pending";

   d.tool_name      = MY_EA_NAME;
   d.tool_version   = MY_EA_VERSION;
   d.session_expires = "";   // You can parse this from the auth response if needed

   d.ea_version = MY_EA_VERSION;
   d.start_time = g_start_time;

   return d;
}

//==========================================================================
// RefreshDashboard
//==========================================================================

void RefreshDashboard()
{
   if(g_dashboard == NULL) return;

   NxDashData d = BuildDashData();

   string auth_status;
   if(g_sdk_ready && g_auth.IsAdminSession()) auth_status = "ADMIN";
   else if(g_sdk_ready)                        auth_status = "OK";
   else if(g_auth.IsRetryExhausted())          auth_status = "EXHAUSTED";
   else                                         auth_status = g_auth.RetryStatus();

   string last_hb = g_healthcheck.LastHeartbeatString();
   string next_hb = g_healthcheck.NextHeartbeatString();

   g_dashboard.Render(d, auth_status, last_hb, next_hb);
}
