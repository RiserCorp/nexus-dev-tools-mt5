//+------------------------------------------------------------------+
//| NxDashboard.mqh                                                  |
//| Nexus Dev Tools — Developer SDK dashboard.                       |
//|                                                                  |
//| A compact floating panel (310px) rendered in the chart corner   |
//| chosen by the user via EA inputs. Each section can be toggled   |
//| independently. Styling is shared with the Monitor dashboard via |
//| NxVisual.mqh (palette, progress bars, primitives).              |
//|                                                                  |
//| Layout strategy:                                                 |
//|   - All objects are anchored to CORNER_LEFT_UPPER internally    |
//|     (so the Y axis always points down). The user-selected       |
//|     corner (0..3) is translated into a top-left origin via      |
//|     ComputePanelOrigin using the current chart size.            |
//|   - Rendering is two-pass:                                      |
//|       1. Measure: walk the layout with m_measure_mode = true,   |
//|          skip drawing, collect the total panel height.          |
//|       2. Draw: place the background first (so it's underneath   |
//|          the labels in z-order), then re-walk the layout        |
//|          normally. This guarantees a visible dark panel and     |
//|          correct top-to-bottom rendering on any corner.         |
//|                                                                  |
//| Sections:                                                        |
//|   Header       - state pill (OK / ADMIN / Retry / FAILED)        |
//|   COMPTE MT5   - login, server, balance, equity, floating,      |
//|                  drawdown + progress bar                         |
//|   LICENCE      - status, EA, version, expiration + countdown     |
//|   ERREURS      - last N ERROR log entries                        |
//|   AVERTISSEMENTS - last N WARN log entries                       |
//|   INFOS        - EA version, start time, uptime, heartbeats     |
//|                                                                  |
//| Corner positioning:                                              |
//|   0 = Top-Left    1 = Top-Right                                 |
//|   2 = Bottom-Left 3 = Bottom-Right                              |
//+------------------------------------------------------------------+
#property strict

#ifndef NEXUS_NX_DASHBOARD_MQH
#define NEXUS_NX_DASHBOARD_MQH

#include "NxPayload.mqh"
#include "NxVisual.mqh"

//--- Object prefix
#define NXD_PFX "NxDev_"

//--- Font sizes
#define NXD_FS_TITLE 11
#define NXD_FS_SEC   9
#define NXD_FS_ROW   9
#define NXD_FS_META  8

//--- Panel width (inherited from NxVisual)
#define NXD_W        NXV_PANEL_W

//+------------------------------------------------------------------+
//| Dashboard data snapshot — filled by the main EA each timer tick  |
//+------------------------------------------------------------------+
struct NxDashData
{
   // COMPTE section
   long   acct_login;
   string acct_server;
   double balance;
   double equity;
   double drawdown_pct;     // current drawdown % (EA's own calculation)
   int    open_positions;

   // LICENCE section
   string licence_status;   // "active" | "expired" | "unlinked" | "admin_test" | "tester" | "pending"
   string tool_name;
   string tool_version;
   string session_expires;  // ISO string from server (e.g. "2026-05-18T00:00:00Z"), "" if unknown

   // INFOS section
   string   ea_version;       // version string shown by the developer
   datetime start_time;       // OnInit timestamp (TimeGMT) for uptime calculation
   long     magic_number;     // EA magic number (0 = not configured, shown as "--")
};

//+------------------------------------------------------------------+
//| CNxDashboard                                                      |
//+------------------------------------------------------------------+
class CNxDashboard
{
private:
   // User config (set via Configure)
   bool   m_show_compte;
   bool   m_show_licence;
   bool   m_show_warnings;
   bool   m_show_errors;
   bool   m_show_infos;
   int    m_user_corner;       // 0=TL 1=TR 2=BL 3=BR (user's choice)
   int    m_x_margin;          // horizontal margin from chart edge
   int    m_y_margin;          // vertical margin from chart edge
   string m_brand_name;        // header title (EA name in UPPER CASE)

   // Computed per Render (based on measured height + user_corner).
   // All drawn objects use CORNER_LEFT_UPPER anchoring; these offsets
   // place the panel top-left corner in the correct absolute position.
   int  m_x_offset;
   int  m_y_offset;
   int  m_cur_y;             // running Y cursor (local to panel)
   bool m_measure_mode;      // pass 1 = measure only, skip drawing

   //+------------------------------------------------------------------+
   //| Cleanup                                                           |
   //+------------------------------------------------------------------+
   void CleanObjects()
   {
      NxDeleteByPrefix(NXD_PFX);
   }

   //+------------------------------------------------------------------+
   //| Drawing wrappers — always use CORNER_LEFT_UPPER, skip when       |
   //| measuring. m_cur_y advancement happens in the higher-level       |
   //| layout helpers (Row, RowFull, etc) so measurement still works.   |
   //+------------------------------------------------------------------+
   void Lbl(const string id, const int y, const string text,
            const color clr, const int fs = NXD_FS_ROW, const bool bold = false)
   {
      if(m_measure_mode) return;
      NxMakeLabel(NXD_PFX + id, CORNER_LEFT_UPPER,
                  m_x_offset + NXV_MARGIN, m_y_offset + y,
                  text, clr, fs, bold);
   }

   void LblAt(const string id, const int x, const int y, const string text,
              const color clr, const int fs = NXD_FS_ROW, const bool bold = false)
   {
      if(m_measure_mode) return;
      NxMakeLabel(NXD_PFX + id, CORNER_LEFT_UPPER,
                  m_x_offset + x, m_y_offset + y,
                  text, clr, fs, bold);
   }

   void Sep(const string id, const int y)
   {
      if(m_measure_mode) return;
      NxMakeSep(NXD_PFX + id, CORNER_LEFT_UPPER,
                m_x_offset + NXV_MARGIN, m_y_offset + y,
                NXD_W - NXV_MARGIN * 2);
   }

   void BarAt(const string id, const int y, const double pct, const color clr)
   {
      if(m_measure_mode) return;
      NxProgressBar(NXD_PFX + id, CORNER_LEFT_UPPER,
                    m_x_offset + NXV_MARGIN, m_y_offset + y,
                    NXD_W - NXV_MARGIN * 2, pct, clr);
   }

   //+------------------------------------------------------------------+
   //| Layout helpers                                                    |
   //+------------------------------------------------------------------+
   void HeaderLine(const string icon, const string state, const color state_clr)
   {
      // Title (left) — uses the EA name stored via Configure
      LblAt("Title", NXV_MARGIN, m_cur_y,
            m_brand_name,
            NXV_HEADER, NXD_FS_TITLE, true);

      // State pill (right) — approximate width for Consolas at fs=9
      string state_txt = icon + " " + state;
      int    state_w   = (int)(StringLen(state_txt) * 7);
      int    state_x   = NXD_W - NXV_MARGIN - state_w;
      // Clamp so the pill never overlaps the title (estimated ~9px per bold char at fs=11)
      int    min_x     = NXV_MARGIN + (int)(StringLen(m_brand_name) * 9) + 20;
      if(state_x < min_x) state_x = min_x;
      LblAt("State", state_x, m_cur_y + 3,
            state_txt, state_clr, NXD_FS_ROW, false);

      m_cur_y += NxLineH(NXD_FS_TITLE) + 4;
      Sep("HdrSep", m_cur_y);
      m_cur_y += 6;
   }

   void SectionTitle(const string id, const string title)
   {
      m_cur_y += 6;
      Lbl(id + "_Title", m_cur_y, title, NXV_SECTION, NXD_FS_SEC, true);
      m_cur_y += NxLineH(NXD_FS_SEC);
   }

   // Aligned "  Label   :  Value" row (Consolas monospace gives perfect cols).
   // Label is padded to 10 chars so values line up across all rows.
   void Row(const string id, const string label, const string value, const color val_clr)
   {
      string padded = label;
      while(StringLen(padded) < 10) padded += " ";
      Lbl(id, m_cur_y, "  " + padded + ":  " + value, val_clr, NXD_FS_ROW);
      m_cur_y += NxLineH(NXD_FS_ROW);
   }

   // Row with no "Label : Value" structure (full-width message).
   void RowFull(const string id, const string text, const color clr)
   {
      Lbl(id, m_cur_y, "  " + text, clr, NXD_FS_ROW);
      m_cur_y += NxLineH(NXD_FS_ROW);
   }

   // Smaller dim sub-info row (e.g. "32% of 10% tolerance used").
   void RowMeta(const string id, const string text)
   {
      Lbl(id, m_cur_y, "  " + text, NXV_DIM, NXD_FS_META);
      m_cur_y += NxLineH(NXD_FS_META);
   }

   // Inline progress bar with small vertical gap after.
   void BarRow(const string id, const double pct, const color clr)
   {
      BarAt(id, m_cur_y, pct, clr);
      m_cur_y += NXV_BAR_H + 4;
   }

   void EndSection()
   {
      m_cur_y += 4;
      Sep("Sep_" + IntegerToString(m_cur_y), m_cur_y);
      m_cur_y += 4;
   }

   //+------------------------------------------------------------------+
   //| Background rectangle — drawn BEFORE content in pass 2 so it is   |
   //| at the bottom of the z-order and doesn't mask the labels.       |
   //+------------------------------------------------------------------+
   void DrawBackground(const int totalHeight)
   {
      NxMakeRect(NXD_PFX + "Bg", CORNER_LEFT_UPPER,
                 m_x_offset, m_y_offset,
                 NXD_W, totalHeight,
                 NXV_BG, NXV_BORDER);
   }

   //+------------------------------------------------------------------+
   //| Compute panel top-left origin based on the user-selected corner  |
   //| and the measured panel height.                                   |
   //+------------------------------------------------------------------+
   void ComputePanelOrigin(const int totalHeight)
   {
      int chartW = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
      int chartH = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);

      switch(m_user_corner)
      {
         case 1: // TR
            m_x_offset = chartW - NXD_W - m_x_margin;
            m_y_offset = m_y_margin;
            break;
         case 2: // BL
            m_x_offset = m_x_margin;
            m_y_offset = chartH - totalHeight - m_y_margin;
            break;
         case 3: // BR
            m_x_offset = chartW - NXD_W - m_x_margin;
            m_y_offset = chartH - totalHeight - m_y_margin;
            break;
         case 0: // TL (default)
         default:
            m_x_offset = m_x_margin;
            m_y_offset = m_y_margin;
            break;
      }

      // Clamp to stay on-chart if the panel is taller than the chart.
      if(m_y_offset < 0) m_y_offset = 0;
      if(m_x_offset < 0) m_x_offset = 0;
   }

   //+------------------------------------------------------------------+
   //| Auth status → icon + short label + color                          |
   //+------------------------------------------------------------------+
   void AuthVisuals(const string auth_status,
                    string &icon, string &label, color &clr)
   {
      if(auth_status == "OK")
      {
         icon = "[OK]";  label = "ONLINE";   clr = NXV_SAFE;
      }
      else if(auth_status == "ADMIN")
      {
         icon = "[ADM]"; label = "ADMIN";    clr = NXV_VIOLET;
      }
      else if(auth_status == "EXHAUSTED")
      {
         icon = "[X]";   label = "FAILED";   clr = NXV_DANGER;
      }
      else if(StringFind(auth_status, "Retry") >= 0)
      {
         icon = "[~]";   label = auth_status; clr = NXV_ORANGE;
      }
      else
      {
         icon = "[...]"; label = auth_status; clr = NXV_BLUE;
      }
   }

   //+------------------------------------------------------------------+
   //| Section renderers                                                  |
   //+------------------------------------------------------------------+
   void RenderCompte(const NxDashData &d)
   {
      SectionTitle("Cpt", "COMPTE MT5");

      Row("Cpt_Login", "Login",    IntegerToString(d.acct_login),  NXV_PRIMARY);
      Row("Cpt_Srv",   "Serveur",  d.acct_server,                   NXV_PRIMARY);
      Row("Cpt_Bal",   "Balance",  DoubleToString(d.balance, 2),    NXV_PRIMARY);
      Row("Cpt_Equ",   "Equity",   DoubleToString(d.equity, 2),     NXV_PRIMARY);

      double floating  = d.equity - d.balance;
      color  float_clr = (floating >  0.005) ? NXV_SAFE
                       : (floating < -0.005) ? NXV_DANGER
                       : NXV_SECONDARY;
      Row("Cpt_Flt", "Floating", NxFormatSigned(floating), float_clr);

      // Drawdown with progress bar — 10% tolerance reference
      // (typical prop-firm max DD; generic enough for most SDK users).
      double dd         = d.drawdown_pct;
      double dd_usedPct = MathMin(100.0, dd / 10.0 * 100.0);
      color  dd_clr     = NxStatusColor(dd_usedPct);

      Row("Cpt_DD", "Drawdown", DoubleToString(dd, 2) + "%", dd_clr);
      BarRow("Cpt_DD_Bar", dd_usedPct, dd_clr);
      RowMeta("Cpt_DD_Meta",
              StringFormat("%.0f%% of 10%% tolerance used", dd_usedPct));

      Row("Cpt_Pos", "Positions", IntegerToString(d.open_positions), NXV_SECONDARY);

      EndSection();
   }

   void RenderLicence(const NxDashData &d)
   {
      SectionTitle("Lic", "LICENCE");

      color  st_clr;
      string st_icon;
      if(d.licence_status == "active")          { st_clr = NXV_SAFE;    st_icon = "[OK] "; }
      else if(d.licence_status == "admin_test") { st_clr = NXV_VIOLET;  st_icon = "[ADM]"; }
      else if(d.licence_status == "tester")     { st_clr = NXV_BLUE;    st_icon = "[TST]"; }
      else if(d.licence_status == "expired")    { st_clr = NXV_DANGER;  st_icon = "[EXP]"; }
      else                                       { st_clr = NXV_ORANGE; st_icon = "[!]  "; }

      Row("Lic_Sta",  "Statut",  st_icon + d.licence_status, st_clr);
      Row("Lic_Tool", "EA",      d.tool_name,                 NXV_PRIMARY);
      Row("Lic_Ver",  "Version", d.tool_version,              NXV_SECONDARY);

      if(d.licence_status == "admin_test")
      {
         RowFull("Lic_Adm", "Admin mode - licence checks bypassed", NXV_VIOLET);
      }
      else if(d.licence_status == "tester")
      {
         RowFull("Lic_Tst", "Strategy Tester - auth desactivee", NXV_BLUE);
      }
      else
      {
         // Try to parse session_expires for a countdown bar.
         datetime exp_ts = NxParseIsoDate(d.session_expires);
         if(exp_ts > 0)
         {
            int days_left = (int)((exp_ts - TimeGMT()) / 86400);
            if(days_left < 0) days_left = 0;

            string exp_label;
            color  exp_clr;
            if(days_left == 0)
            {
               exp_label = "expire today";
               exp_clr   = NXV_DANGER;
            }
            else if(days_left == 1)
            {
               exp_label = "expire in 1 day";
               exp_clr   = NXV_DANGER;
            }
            else if(days_left < 7)
            {
               exp_label = "expire in " + IntegerToString(days_left) + " days";
               exp_clr   = NXV_WARNING;
            }
            else
            {
               exp_label = "expire in " + IntegerToString(days_left) + " days";
               exp_clr   = NXV_SECONDARY;
            }
            Row("Lic_Exp", "Expire", exp_label, exp_clr);

            // Countdown bar: fill = remaining / 30d * 100 (clamped).
            // Color mirrors the label (< 3d danger, < 7d warning, else safe).
            double fill_pct = MathMin(100.0, days_left / 30.0 * 100.0);
            color  bar_clr  = (days_left < 3) ? NXV_DANGER
                            : (days_left < 7) ? NXV_WARNING
                            : NXV_SAFE;
            BarRow("Lic_Exp_Bar", fill_pct, bar_clr);
            RowMeta("Lic_Exp_Meta",
                    StringFormat("%d days remaining (30d window)", days_left));
         }
         else
         {
            // Fallback: show raw string if unparseable / empty.
            string fallback = StringLen(d.session_expires) > 0
                              ? d.session_expires
                              : "unknown";
            Row("Lic_Exp", "Expire", fallback, NXV_SECONDARY);
         }
      }

      EndSection();
   }

   void RenderLogSection(const string section_id, const string title,
                         const string level, const int max_lines,
                         const string empty_text)
   {
      SectionTitle(section_id, title);

      NexusLogEntry entries[];
      int count;
      NxLogBuffer::Get().GetByLevel(level, max_lines, entries, count);

      if(count == 0)
      {
         RowFull(section_id + "_Empty", empty_text, NXV_SECONDARY);
      }
      else
      {
         color log_clr = (level == NX_ERROR) ? NXV_DANGER
                       : (level == NX_WARN)  ? NXV_ORANGE
                       : NXV_SECONDARY;
         for(int i = 0; i < count; i++)
         {
            string txt = entries[i].timestamp + "  " + entries[i].message;
            // Truncate to fit the 360px panel width at Consolas fs=9.
            // ~56 chars max; cut to 54 and append ".." to make overflow visible.
            if(StringLen(txt) > 56) txt = StringSubstr(txt, 0, 54) + "..";
            RowFull(section_id + "_L" + IntegerToString(i), txt, log_clr);
         }
      }

      EndSection();
   }

   void RenderInfos(const NxDashData &d, const string last_hb, const string next_hb)
   {
      SectionTitle("Inf", "INFOS");

      MqlDateTime dt;
      TimeToStruct(d.start_time, dt);
      string start_str = StringFormat("%02d:%02d UTC", dt.hour, dt.min);

      int uptime_sec = (int)(TimeGMT() - d.start_time);
      if(uptime_sec < 0) uptime_sec = 0;
      string uptime_str = NxFormatDuration(uptime_sec);

      string magic_str = (d.magic_number != 0)
                         ? IntegerToString(d.magic_number)
                         : "--";

      Row("Inf_EAV",   "EA Version",  d.ea_version,  NXV_SECONDARY);
      Row("Inf_Mag",   "Magic",       magic_str,     NXV_SECONDARY);
      Row("Inf_Start", "Demarrage",   start_str,      NXV_SECONDARY);
      Row("Inf_Up",    "Uptime",      uptime_str,     NXV_SECONDARY);
      Row("Inf_HBL",   "Dernier HB",  last_hb,        NXV_SECONDARY);
      Row("Inf_HBN",   "Prochain HB", next_hb,        NXV_SECONDARY);

      // Footer branding — no EndSection, last block before panel bottom.
      m_cur_y += 6;
      LblAt("Brand", NXV_MARGIN, m_cur_y, "Nexus Trade Studio",
            NXV_BRAND, NXD_FS_META);
      m_cur_y += NxLineH(NXD_FS_META);
   }

   //+------------------------------------------------------------------+
   //| Section walkers — run in both measure and draw mode              |
   //+------------------------------------------------------------------+
   void WalkMain(const NxDashData &d, const string auth_status,
                 const string last_hb, const string next_hb)
   {
      m_cur_y = 10;

      string icon, label;
      color  clr;
      AuthVisuals(auth_status, icon, label, clr);
      HeaderLine(icon, label, clr);

      if(m_show_compte)   RenderCompte(d);
      if(m_show_licence)  RenderLicence(d);
      if(m_show_errors)   RenderLogSection("Err", "ERREURS",        NX_ERROR, 3, "Aucune erreur recente");
      if(m_show_warnings) RenderLogSection("Wrn", "AVERTISSEMENTS", NX_WARN,  3, "Aucun avertissement recent");
      if(m_show_infos)    RenderInfos(d, last_hb, next_hb);
   }

   void WalkAuthError(const string error_code, const string error_msg)
   {
      m_cur_y = 10;

      HeaderLine("[X]", "AUTH ERROR", NXV_DANGER);

      SectionTitle("AErr", "ERREUR D'AUTHENTIFICATION");
      RowFull("AErr_Code", error_code, NXV_DANGER);

      if(error_code == "URL_BLOCKED")
      {
         RowFull("AErr_M1", "URL bloquee par MT5.",                  NXV_ORANGE);
         RowFull("AErr_M2", "1. Outils > Options > Expert Advisors", NXV_PRIMARY);
         RowFull("AErr_M3", "2. Ajouter et coller :",                 NXV_PRIMARY);
         RowFull("AErr_M4", error_msg,                                 NXV_WARNING);
         RowFull("AErr_M5", "3. Redemarrer l'EA apres OK.",           NXV_SECONDARY);
      }
      else if(error_code == "AUTH_REJECTED")
      {
         RowFull("AErr_M1", error_msg,                                 NXV_ORANGE);
         RowFull("AErr_M2", "Verifier API_KEY (Settings > Profile)",  NXV_SECONDARY);
         RowFull("AErr_M3", "Verifier TOOL_KEY (Dev Area > Keys)",    NXV_SECONDARY);
      }
      else if(error_code == "NETWORK_ERROR")
      {
         RowFull("AErr_M1", error_msg,                                 NXV_ORANGE);
         RowFull("AErr_M2", "Verifier la connexion internet.",        NXV_SECONDARY);
         RowFull("AErr_M3", "Retry automatique en cours.",            NXV_SECONDARY);
      }
      else if(error_code == "LICENCE_NOT_FOUND")
      {
         RowFull("AErr_M1", error_msg,                                 NXV_ORANGE);
         RowFull("AErr_M2", "nexustradestudio.com > Marketplace",     NXV_BLUE);
      }
      else
      {
         RowFull("AErr_M1", error_msg,                                 NXV_ORANGE);
         RowFull("AErr_M2", "Verifier API_KEY et TOOL_KEY.",          NXV_SECONDARY);
      }

      EndSection();
   }

   void WalkConnecting()
   {
      m_cur_y = 10;

      HeaderLine("[...]", "CONNECTING", NXV_BLUE);

      SectionTitle("Conn", "STATUT");
      RowFull("Conn_L1", "Contacting marketplace server...", NXV_BLUE);
      RowMeta("Conn_L2", "This may take a few seconds");
   }

public:
   CNxDashboard() :
      m_show_compte(true),  m_show_licence(true),
      m_show_warnings(true), m_show_errors(true), m_show_infos(true),
      m_user_corner(0), m_x_margin(10), m_y_margin(10),
      m_brand_name("NEXUS DEV TOOLS"),
      m_x_offset(10), m_y_offset(10), m_cur_y(0), m_measure_mode(false) {}

   //+------------------------------------------------------------------+
   //| Configure — call once in OnInit before any Render call           |
   //| brand_name : header title (UPPER CASE recommended, e.g. EA name) |
   //+------------------------------------------------------------------+
   void Configure(const int    corner,
                  const bool   show_compte,
                  const bool   show_licence,
                  const bool   show_warnings,
                  const bool   show_errors,
                  const bool   show_infos,
                  const int    x_offset   = 10,
                  const int    y_offset   = 10,
                  const string brand_name = "NEXUS DEV TOOLS")
   {
      m_user_corner   = corner;
      m_x_margin      = x_offset;
      m_y_margin      = y_offset;
      m_show_compte   = show_compte;
      m_show_licence  = show_licence;
      m_show_warnings = show_warnings;
      m_show_errors   = show_errors;
      m_show_infos    = show_infos;
      m_brand_name    = StringLen(brand_name) > 0 ? brand_name : "NEXUS DEV TOOLS";
   }

   //+------------------------------------------------------------------+
   //| CoverChart — optional: hide chart widgets when the EA sits on    |
   //| a dedicated tab used as a display only.                          |
   //+------------------------------------------------------------------+
   void CoverChart()
   {
      ChartSetInteger(0, CHART_SHOW_GRID,        false);
      ChartSetInteger(0, CHART_SHOW_VOLUMES,     false);
      ChartSetInteger(0, CHART_SHOW_PERIOD_SEP,  false);
      ChartSetInteger(0, CHART_SHOW_ASK_LINE,    false);
      ChartSetInteger(0, CHART_SHOW_BID_LINE,    false);
      ChartSetInteger(0, CHART_COLOR_BACKGROUND, clrBlack);
      ChartSetInteger(0, CHART_COLOR_FOREGROUND, clrBlack);
   }

   //+------------------------------------------------------------------+
   //| Render — two-pass layout:                                        |
   //|   pass 1: walk to measure total height                           |
   //|   pass 2: draw background first (correct z-order), then content  |
   //+------------------------------------------------------------------+
   void Render(const NxDashData &d,
               const string auth_status,
               const string last_hb,
               const string next_hb)
   {
      CleanObjects();

      // Pass 1 — measure
      m_measure_mode = true;
      WalkMain(d, auth_status, last_hb, next_hb);
      int totalH = m_cur_y + 10;

      // Position the panel based on the user-selected corner
      ComputePanelOrigin(totalH);

      // Pass 2 — draw (background first so labels sit on top of it)
      m_measure_mode = false;
      DrawBackground(totalH);
      WalkMain(d, auth_status, last_hb, next_hb);

      ChartRedraw(0);
   }

   //+------------------------------------------------------------------+
   //| RenderAuthError — compact error panel with actionable hints      |
   //+------------------------------------------------------------------+
   void RenderAuthError(const string error_code, const string error_msg)
   {
      CleanObjects();

      m_measure_mode = true;
      WalkAuthError(error_code, error_msg);
      int totalH = m_cur_y + 10;

      ComputePanelOrigin(totalH);

      m_measure_mode = false;
      DrawBackground(totalH);
      WalkAuthError(error_code, error_msg);

      ChartRedraw(0);
   }

   //+------------------------------------------------------------------+
   //| RenderConnecting — transient state during startup auth            |
   //+------------------------------------------------------------------+
   void RenderConnecting()
   {
      CleanObjects();

      m_measure_mode = true;
      WalkConnecting();
      int totalH = m_cur_y + 10;

      ComputePanelOrigin(totalH);

      m_measure_mode = false;
      DrawBackground(totalH);
      WalkConnecting();

      ChartRedraw(0);
   }

   //+------------------------------------------------------------------+
   //| Clear — restore chart on OnDeinit                                |
   //+------------------------------------------------------------------+
   void Clear()
   {
      CleanObjects();
      ChartSetInteger(0, CHART_SHOW_GRID,        true);
      ChartSetInteger(0, CHART_SHOW_ASK_LINE,    true);
      ChartSetInteger(0, CHART_SHOW_BID_LINE,    true);
      ChartSetInteger(0, CHART_COLOR_BACKGROUND, clrWhite);
      ChartSetInteger(0, CHART_COLOR_FOREGROUND, clrBlack);
      ChartRedraw(0);
   }
};

#endif // NEXUS_NX_DASHBOARD_MQH
