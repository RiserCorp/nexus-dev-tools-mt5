//+------------------------------------------------------------------+
//| NxDashboard.mqh                                                  |
//| Nexus Dev Tools — Configurable multi-section overlay dashboard   |
//|                                                                  |
//| Sections (each independently toggleable via EA inputs):          |
//|   [COMPTE]        — MT5 login, server, balance, equity, DD      |
//|   [LICENCE]       — Status, tool name, expiration, session type |
//|   [AVERTISSEMENTS]— Last N warnings from the log buffer         |
//|   [ERREURS]       — Last N errors from the log buffer           |
//|   [INFOS]         — Last sync, uptime, EA version, heartbeat    |
//|                                                                  |
//| Corner positioning:                                              |
//|   0 = Top-Left   1 = Top-Right                                  |
//|   2 = Bottom-Left  3 = Bottom-Right                             |
//+------------------------------------------------------------------+
#property strict

#ifndef NEXUS_NX_DASHBOARD_MQH
#define NEXUS_NX_DASHBOARD_MQH

#include "NxPayload.mqh"

//--- Object prefix
#define NXD_PFX "NxDev_"

//--- Visual constants
#define NXD_BG_COLOR     C'14,20,32'
#define NXD_PRIMARY      C'220,225,235'
#define NXD_SECONDARY    C'100,120,145'
#define NXD_GREEN        C'80,210,120'
#define NXD_RED          C'225,70,70'
#define NXD_ORANGE       C'255,155,40'
#define NXD_YELLOW       C'255,220,60'
#define NXD_BLUE         C'100,165,255'
#define NXD_VIOLET       C'180,120,255'
#define NXD_SEPARATOR    C'40,55,75'
#define NXD_SECTION_CLR  C'90,115,150'

//--- Layout
#define NXD_W    320   // panel width
#define NXD_MX    12   // horizontal margin
#define NXD_LH    19   // line height
#define NXD_SH    10   // gap above section title

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
   string licence_status;   // "active" | "expired" | "unlinked" | "admin_test"
   string tool_name;        // your EA name
   string tool_version;     // your EA version
   string session_expires;  // ISO string from server

   // INFOS section
   string ea_version;       // version string shown by the developer
   datetime start_time;     // OnInit timestamp for uptime calculation
};

//+------------------------------------------------------------------+
//| CNxDashboard                                                      |
//+------------------------------------------------------------------+
class CNxDashboard
{
private:
   // Section visibility flags
   bool m_show_compte;
   bool m_show_licence;
   bool m_show_warnings;
   bool m_show_errors;
   bool m_show_infos;

   int  m_corner;       // 0=TL 1=TR 2=BL 3=BR
   int  m_x_offset;
   int  m_y_offset;
   int  m_cur_y;        // running Y position during rendering

   // ─── Low-level drawing ────────────────────────────────────────────

   void CleanObjects()
   {
      for(int i = ObjectsTotal(0) - 1; i >= 0; i--)
      {
         string n = ObjectName(0, i);
         if(StringFind(n, NXD_PFX) == 0)
            ObjectDelete(0, n);
      }
   }

   void DrawBg(int h)
   {
      string n = NXD_PFX + "Bg";
      if(ObjectFind(0, n) < 0)
         ObjectCreate(0, n, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, n, OBJPROP_CORNER,      m_corner);
      ObjectSetInteger(0, n, OBJPROP_XDISTANCE,   m_x_offset);
      ObjectSetInteger(0, n, OBJPROP_YDISTANCE,   m_y_offset);
      ObjectSetInteger(0, n, OBJPROP_XSIZE,       NXD_W);
      ObjectSetInteger(0, n, OBJPROP_YSIZE,       h);
      ObjectSetInteger(0, n, OBJPROP_BGCOLOR,     NXD_BG_COLOR);
      ObjectSetInteger(0, n, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE,  false);
      ObjectSetInteger(0, n, OBJPROP_HIDDEN,      true);
      ObjectSetInteger(0, n, OBJPROP_ZORDER,      0);
   }

   void Lbl(string id, string txt, int y, color clr,
            int fs = 8, bool bold = false)
   {
      string n = NXD_PFX + id;
      if(ObjectFind(0, n) < 0)
         ObjectCreate(0, n, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, n, OBJPROP_CORNER,     m_corner);
      ObjectSetInteger(0, n, OBJPROP_XDISTANCE,  m_x_offset + NXD_MX);
      ObjectSetInteger(0, n, OBJPROP_YDISTANCE,  m_y_offset + y);
      ObjectSetInteger(0, n, OBJPROP_COLOR,      clr);
      ObjectSetInteger(0, n, OBJPROP_FONTSIZE,   fs);
      ObjectSetString (0, n, OBJPROP_FONT,       bold ? "Arial Bold" : "Arial");
      ObjectSetString (0, n, OBJPROP_TEXT,       txt);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, n, OBJPROP_HIDDEN,     true);
   }

   void Sep(string id, int y)
   {
      string n = NXD_PFX + id;
      if(ObjectFind(0, n) < 0)
         ObjectCreate(0, n, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, n, OBJPROP_CORNER,      m_corner);
      ObjectSetInteger(0, n, OBJPROP_XDISTANCE,   m_x_offset + NXD_MX);
      ObjectSetInteger(0, n, OBJPROP_YDISTANCE,   m_y_offset + y);
      ObjectSetInteger(0, n, OBJPROP_XSIZE,       NXD_W - NXD_MX * 2);
      ObjectSetInteger(0, n, OBJPROP_YSIZE,       1);
      ObjectSetInteger(0, n, OBJPROP_BGCOLOR,     NXD_SEPARATOR);
      ObjectSetInteger(0, n, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE,  false);
      ObjectSetInteger(0, n, OBJPROP_HIDDEN,      true);
   }

   // ─── Layout helpers ───────────────────────────────────────────────

   void Header(string icon, string label, color icn_clr)
   {
      Lbl("Hdr", icon + "  NEXUS DEV TOOLS", m_cur_y, icn_clr, 10, true);
      m_cur_y += NXD_LH + 4;
      Sep("HdrSep", m_cur_y);
      m_cur_y += 6;
   }

   void SectionTitle(string id, string title)
   {
      m_cur_y += NXD_SH;
      Lbl(id + "_T", title, m_cur_y, NXD_SECTION_CLR, 7, false);
      m_cur_y += NXD_LH;
   }

   void Row(string id, string label, string value, color val_clr)
   {
      Lbl(id, "  " + label + " :  " + value, m_cur_y, val_clr, 8);
      m_cur_y += NXD_LH;
   }

   void RowFull(string id, string txt, color clr)
   {
      Lbl(id, "  " + txt, m_cur_y, clr, 8);
      m_cur_y += NXD_LH;
   }

   void EndSection()
   {
      Sep("Sep_" + IntegerToString(m_cur_y), m_cur_y);
      m_cur_y += 4;
   }

   // ─── Section renderers ────────────────────────────────────────────

   void RenderCompte(const NxDashData &d)
   {
      SectionTitle("Compte", "COMPTE MT5");
      Row("Cpt_Login", "Login",   IntegerToString(d.acct_login), NXD_PRIMARY);
      Row("Cpt_Srv",   "Serveur", d.acct_server,                 NXD_PRIMARY);
      Row("Cpt_Bal",   "Balance", DoubleToString(d.balance, 2),  NXD_PRIMARY);
      Row("Cpt_Equ",   "Equity",  DoubleToString(d.equity,  2),  NXD_PRIMARY);
      color dd_clr = d.drawdown_pct < 30 ? NXD_GREEN :
                     d.drawdown_pct < 60 ? NXD_YELLOW : NXD_RED;
      Row("Cpt_DD", "Drawdown", DoubleToString(d.drawdown_pct, 2) + "%", dd_clr);
      Row("Cpt_Pos", "Positions", IntegerToString(d.open_positions), NXD_SECONDARY);
      EndSection();
   }

   void RenderLicence(const NxDashData &d)
   {
      SectionTitle("Lic", "LICENCE");

      color status_clr;
      string status_icon;
      if(d.licence_status == "active")         { status_clr = NXD_GREEN;  status_icon = "[OK] "; }
      else if(d.licence_status == "admin_test") { status_clr = NXD_VIOLET; status_icon = "[ADM]"; }
      else if(d.licence_status == "expired")    { status_clr = NXD_RED;    status_icon = "[EXP]"; }
      else                                      { status_clr = NXD_ORANGE; status_icon = "[!]  "; }

      Row("Lic_Sta",  "Statut",   status_icon + d.licence_status, status_clr);
      Row("Lic_Tool", "EA",       d.tool_name,                    NXD_PRIMARY);
      Row("Lic_Ver",  "Version",  d.tool_version,                 NXD_SECONDARY);
      if(d.licence_status != "admin_test")
         Row("Lic_Exp", "Expire", d.session_expires,              NXD_SECONDARY);
      else
         RowFull("Lic_Adm", "Admin mode — licence checks bypassed", NXD_VIOLET);
      EndSection();
   }

   void RenderLogSection(const string section_id, const string title,
                         const string level, int max_lines)
   {
      SectionTitle(section_id, title);
      NexusLogEntry entries[];
      int count;
      NxLogBuffer::Get().GetByLevel(level, max_lines, entries, count);

      if(count == 0)
      {
         RowFull(section_id + "_Empty", "Aucun " + title, NXD_SECONDARY);
      }
      else
      {
         for(int i = 0; i < count; i++)
         {
            string txt = entries[i].timestamp + "  " + entries[i].message;
            color  clr = (level == NX_ERROR) ? NXD_RED :
                         (level == NX_WARN)  ? NXD_ORANGE : NXD_SECONDARY;
            RowFull(section_id + "_L" + IntegerToString(i), txt, clr);
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
      int uptime_min = uptime_sec / 60;
      int uptime_hr  = uptime_min / 60;
      string uptime_str = uptime_hr > 0
         ? IntegerToString(uptime_hr) + "h " + IntegerToString(uptime_min % 60) + "m"
         : IntegerToString(uptime_min) + "m " + IntegerToString(uptime_sec % 60) + "s";

      Row("Inf_EAV",   "EA Version",  d.ea_version,   NXD_SECONDARY);
      Row("Inf_Start", "Demarrage",   start_str,       NXD_SECONDARY);
      Row("Inf_Up",    "Uptime",      uptime_str,      NXD_SECONDARY);
      Row("Inf_HBL",   "Dernier HB",  last_hb,         NXD_SECONDARY);
      Row("Inf_HBN",   "Prochain HB", next_hb,         NXD_SECONDARY);
      // No EndSection — last section, bottom of panel
   }

public:
   CNxDashboard()
      : m_show_compte(true), m_show_licence(true),
        m_show_warnings(true), m_show_errors(true), m_show_infos(true),
        m_corner(0), m_x_offset(10), m_y_offset(10), m_cur_y(0) {}

   //+------------------------------------------------------------------+
   //| Configure — call once in OnInit before any Render call           |
   //+------------------------------------------------------------------+
   void Configure(int corner,
                  bool show_compte,   bool show_licence,
                  bool show_warnings, bool show_errors,
                  bool show_infos,
                  int x_offset = 10, int y_offset = 10)
   {
      m_corner       = corner;
      m_x_offset     = x_offset;
      m_y_offset     = y_offset;
      m_show_compte   = show_compte;
      m_show_licence  = show_licence;
      m_show_warnings = show_warnings;
      m_show_errors   = show_errors;
      m_show_infos    = show_infos;
   }

   //+------------------------------------------------------------------+
   //| CoverChart — optional: hides chart to use panel as sole display  |
   //| Only call this if your EA is attached to a dedicated chart.      |
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
   //| Render — full panel redraw each timer cycle                      |
   //| auth_status  — short string shown in the header                  |
   //| last_hb/next_hb — strings from CNxHealthcheck                   |
   //+------------------------------------------------------------------+
   void Render(const NxDashData &d,
               const string auth_status,
               const string last_hb,
               const string next_hb)
   {
      CleanObjects();
      m_cur_y = 8;

      // ── Header ──────────────────────────────────────────────────────
      string icon;
      color  icon_clr;
      if(auth_status == "OK" || auth_status == "ADMIN")
         { icon = "[OK]"; icon_clr = NXD_GREEN; }
      else if(StringFind(auth_status, "Retry") >= 0)
         { icon = "[~] "; icon_clr = NXD_ORANGE; }
      else
         { icon = "[X] "; icon_clr = NXD_RED; }

      Header(icon, auth_status, icon_clr);

      // ── Sections ─────────────────────────────────────────────────────
      if(m_show_compte)   RenderCompte(d);
      if(m_show_licence)  RenderLicence(d);
      if(m_show_errors)   RenderLogSection("Err", "ERREURS",        NX_ERROR, 4);
      if(m_show_warnings) RenderLogSection("Wrn", "AVERTISSEMENTS", NX_WARN,  4);
      if(m_show_infos)    RenderInfos(d, last_hb, next_hb);

      // ── Background sized to content ───────────────────────────────
      DrawBg(m_cur_y + 12);
      ChartRedraw(0);
   }

   //+------------------------------------------------------------------+
   //| RenderAuthError — minimal panel before full data is available    |
   //+------------------------------------------------------------------+
   void RenderAuthError(const string error_code, const string error_msg)
   {
      CleanObjects();
      m_cur_y = 8;
      Header("[X] ", "Auth Error", NXD_RED);
      SectionTitle("AErr", "STATUT");
      RowFull("AErr_Code", error_code,  NXD_RED);
      RowFull("AErr_Msg",  error_msg,   NXD_ORANGE);
      RowFull("AErr_Hint", "Check your API key and tool key settings.", NXD_SECONDARY);
      DrawBg(m_cur_y + 12);
      ChartRedraw(0);
   }

   //+------------------------------------------------------------------+
   //| RenderConnecting — shown during OnInit before auth completes     |
   //+------------------------------------------------------------------+
   void RenderConnecting()
   {
      CleanObjects();
      m_cur_y = 8;
      Header("... ", "Connecting...", NXD_BLUE);
      SectionTitle("Conn", "STATUT");
      RowFull("Conn_L1", "Contacting marketplace server...", NXD_BLUE);
      DrawBg(m_cur_y + 12);
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
