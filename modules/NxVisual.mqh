//+------------------------------------------------------------------+
//| NxVisual.mqh                                                     |
//| Nexus shared visual primitives — palette, fonts, rect/label      |
//| helpers, and progress bars with semantic threshold colors.       |
//|                                                                  |
//| Design conventions:                                              |
//|   - Palette: near-black bg, high-contrast text, vivid semantics  |
//|   - Font:    Consolas (monospace) for perfect alignment          |
//|   - Layout:  panel width NXV_PANEL_W, line height = fs * 1.8     |
//|   - Status:  Safe 0..50%, Warning 50..80%, Danger >= 80%         |
//|                                                                  |
//| Intended to be shared by NxDashboard (Dev Tools) and the         |
//| Monitor EA dashboard when refactored.                            |
//+------------------------------------------------------------------+
#property strict

#ifndef NEXUS_NX_VISUAL_MQH
#define NEXUS_NX_VISUAL_MQH

//--- Palette (near-black, pro trading terminal look) ---------------
#define NXV_BG          C'14,17,24'    // panel background
#define NXV_BG_SUNK     C'10,12,18'    // deeper background for sections
#define NXV_BORDER      C'30,35,50'    // panel outer border
#define NXV_SEP         C'40,55,75'    // 1px separator line
#define NXV_BAR_BG      C'25,28,38'    // progress bar track

#define NXV_HEADER      C'90,180,250'  // H1, section headers, accent
#define NXV_PRIMARY     C'220,225,235' // values, high-emphasis text
#define NXV_TEXT        C'165,170,185' // normal body text
#define NXV_SECONDARY   C'100,120,145' // meta info, labels
#define NXV_SECTION     C'100,120,145' // section titles
#define NXV_DIM         C'80,85,100'   // sub-info (pct hint under bars)
#define NXV_BRAND       C'50,55,70'    // very subtle brand/footer text

#define NXV_SAFE        C'0,200,83'    // healthy / green
#define NXV_WARNING     C'255,215,0'   // yellow / approaching limit
#define NXV_DANGER      C'255,23,68'   // red / breach
#define NXV_TARGET      C'0,230,118'   // vivid green / target reached
#define NXV_BLUE        C'100,165,255' // info / connecting
#define NXV_VIOLET      C'180,120,255' // admin / special session
#define NXV_ORANGE      C'255,155,40'  // transient warning

//--- Font --------------------------------------------------------
#define NXV_FONT        "Consolas"
#define NXV_FONT_BOLD   "Consolas Bold"

//--- Layout defaults --------------------------------------------
#define NXV_PANEL_W     360            // compact floating panel
#define NXV_MARGIN      14             // internal left/right padding
#define NXV_BAR_H       7              // progress bar height

//--- Thresholds (% of limit used) -------------------------------
#define NXV_THRESH_WARNING  50
#define NXV_THRESH_DANGER   80

//+------------------------------------------------------------------+
//| NxLineH — line height based on font size (responsive)            |
//+------------------------------------------------------------------+
int NxLineH(const int fs)
{
   return (int)(fs * 1.8);
}

//+------------------------------------------------------------------+
//| NxStatusColor — semantic color from usage percentage             |
//| 0..50% = safe, 50..80% = warning, 80+% = danger                  |
//+------------------------------------------------------------------+
color NxStatusColor(const double usedPct)
{
   if(usedPct >= NXV_THRESH_DANGER)  return NXV_DANGER;
   if(usedPct >= NXV_THRESH_WARNING) return NXV_WARNING;
   return NXV_SAFE;
}

//+------------------------------------------------------------------+
//| NxFormatSigned — "+1234.56" / "-1234.56" / "0.00"                |
//+------------------------------------------------------------------+
string NxFormatSigned(const double v, const int decimals = 2)
{
   if(v >  0.005) return "+" + DoubleToString(v, decimals);
   if(v < -0.005) return DoubleToString(v, decimals);
   return DoubleToString(0.0, decimals);
}

//+------------------------------------------------------------------+
//| NxFormatDuration — "45s" / "2m 15s" / "2h 15m" / "3d 4h"         |
//+------------------------------------------------------------------+
string NxFormatDuration(const int totalSec)
{
   if(totalSec < 60) return IntegerToString(totalSec) + "s";
   int mins  = totalSec / 60;
   int secs  = totalSec % 60;
   if(mins < 60) return IntegerToString(mins) + "m " + IntegerToString(secs) + "s";
   int hours = mins / 60;
   mins      = mins % 60;
   if(hours < 24) return IntegerToString(hours) + "h " + IntegerToString(mins) + "m";
   int days  = hours / 24;
   hours     = hours % 24;
   return IntegerToString(days) + "d " + IntegerToString(hours) + "h";
}

//+------------------------------------------------------------------+
//| NxParseIsoDate — "2026-05-18T00:00:00Z" -> datetime               |
//| Returns 0 if the string cannot be parsed.                        |
//+------------------------------------------------------------------+
datetime NxParseIsoDate(const string iso)
{
   if(StringLen(iso) < 10) return 0;
   string date_part = StringSubstr(iso, 0, 10);  // 2026-05-18
   StringReplace(date_part, "-", ".");
   string combined = date_part;
   if(StringLen(iso) >= 19)
   {
      string time_part = StringSubstr(iso, 11, 8); // 00:00:00
      combined = date_part + " " + time_part;
   }
   return StringToTime(combined);
}

//+------------------------------------------------------------------+
//| NxMakeLabel — create or replace an OBJ_LABEL                     |
//+------------------------------------------------------------------+
void NxMakeLabel(const string name,
                 const int    corner,
                 const int    x,
                 const int    y,
                 const string text,
                 const color  clr,
                 const int    fontSize = 9,
                 const bool   bold     = false)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER,     corner);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR,     ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,  x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,  y);
   ObjectSetInteger(0, name, OBJPROP_COLOR,      clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,   fontSize);
   ObjectSetString (0, name, OBJPROP_FONT,       bold ? NXV_FONT_BOLD : NXV_FONT);
   ObjectSetString (0, name, OBJPROP_TEXT,       text);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
}

//+------------------------------------------------------------------+
//| NxMakeRect — create or replace an OBJ_RECTANGLE_LABEL            |
//+------------------------------------------------------------------+
void NxMakeRect(const string name,
                const int    corner,
                const int    x,
                const int    y,
                const int    w,
                const int    h,
                const color  bgClr,
                const color  borderClr)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER,       corner);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,    x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,    y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE,        w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE,        h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,      bgClr);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE,  BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, borderClr);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE,   false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,       true);
   ObjectSetInteger(0, name, OBJPROP_BACK,         false);
}

//+------------------------------------------------------------------+
//| NxMakeSep — thin 1px horizontal separator                        |
//+------------------------------------------------------------------+
void NxMakeSep(const string name,
               const int    corner,
               const int    x,
               const int    y,
               const int    w)
{
   NxMakeRect(name, corner, x, y, w, 1, NXV_SEP, NXV_SEP);
}

//+------------------------------------------------------------------+
//| NxSetLabelText — update existing label text + color              |
//+------------------------------------------------------------------+
void NxSetLabelText(const string name, const string text, const color clr)
{
   ObjectSetString (0, name, OBJPROP_TEXT,  text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
}

//+------------------------------------------------------------------+
//| NxSetRectSize — update rect width / height                       |
//+------------------------------------------------------------------+
void NxSetRectSize(const string name, const int w, const int h)
{
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
}

//+------------------------------------------------------------------+
//| NxSetRectColor — update rect bg + border color                   |
//+------------------------------------------------------------------+
void NxSetRectColor(const string name, const color bgClr, const color borderClr)
{
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,      bgClr);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, borderClr);
}

//+------------------------------------------------------------------+
//| NxProgressBar — create (or replace) a progress bar track + fill  |
//|                                                                  |
//| Two objects are created:                                         |
//|   namePrefix + "_Bg"    — full-width dark background track       |
//|   namePrefix + "_Fill"  — colored fill clipped to usedPct        |
//|                                                                  |
//| @param namePrefix  unique id for this bar (e.g. "Dd_Bar")        |
//| @param corner      chart corner (0=TL..3=BR)                     |
//| @param x, y        top-left pixel position                       |
//| @param totalW      full width of the bar in pixels               |
//| @param usedPct     0..100 fill percentage (clamped internally)   |
//| @param fillClr     fill color (use NxStatusColor for semantic)   |
//| @param height      bar height in pixels (default NXV_BAR_H)      |
//+------------------------------------------------------------------+
void NxProgressBar(const string namePrefix,
                   const int    corner,
                   const int    x,
                   const int    y,
                   const int    totalW,
                   const double usedPct,
                   const color  fillClr,
                   const int    height = NXV_BAR_H)
{
   NxMakeRect(namePrefix + "_Bg", corner, x, y, totalW, height,
              NXV_BAR_BG, NXV_BAR_BG);

   double pct = usedPct;
   if(pct < 0)   pct = 0;
   if(pct > 100) pct = 100;
   int fillW = (int)MathMax(1, totalW * pct / 100.0);

   NxMakeRect(namePrefix + "_Fill", corner, x, y, fillW, height,
              fillClr, fillClr);
}

//+------------------------------------------------------------------+
//| NxUpdateProgressBar — update existing bar width + color          |
//| Faster than NxProgressBar when the objects already exist.        |
//+------------------------------------------------------------------+
void NxUpdateProgressBar(const string namePrefix,
                         const int    totalW,
                         const double usedPct,
                         const color  fillClr,
                         const int    height = NXV_BAR_H)
{
   double pct = usedPct;
   if(pct < 0)   pct = 0;
   if(pct > 100) pct = 100;
   int fillW = (int)MathMax(1, totalW * pct / 100.0);
   NxSetRectSize(namePrefix + "_Fill", fillW, height);
   NxSetRectColor(namePrefix + "_Fill", fillClr, fillClr);
}

//+------------------------------------------------------------------+
//| NxDeleteByPrefix — remove all objects whose name starts with `p` |
//+------------------------------------------------------------------+
void NxDeleteByPrefix(const string p)
{
   for(int i = ObjectsTotal(0) - 1; i >= 0; i--)
   {
      string n = ObjectName(0, i);
      if(StringFind(n, p) == 0)
         ObjectDelete(0, n);
   }
}

#endif // NEXUS_NX_VISUAL_MQH
