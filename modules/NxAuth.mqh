//+------------------------------------------------------------------+
//| NxAuth.mqh                                                       |
//| Nexus Dev Tools — Marketplace authentication module              |
//|                                                                  |
//| Flow:                                                            |
//|   1. On OnInit — attempt session resumption first (POST /resume) |
//|      with the session token stored in a GlobalVar keyed on       |
//|      toolKey + "_" + MagicNumber. No new session created if      |
//|      resumption succeeds.                                        |
//|   2. If resumption fails (expired / not found) — full auth      |
//|      via POST /auth with api_key + tool_key + account +          |
//|      magic_number. Store new token in GlobalVar.                 |
//|   3. On failure: log the error, schedule retry via CNxRetry.    |
//|                                                                  |
//| Admin bypass:                                                    |
//|   If the api_key belongs to a platform admin (ntk- prefix), the |
//|   server returns a session of type "admin_test". The EA detects  |
//|   this and sets m_is_admin_session = true, allowing operation   |
//|   without a configured account on the platform.                 |
//|                                                                  |
//| Magic number:                                                    |
//|   Each EA instance is identified by its MagicNumber input.      |
//|   The GlobalVar key is "NX_SESSION_{toolKey}_{MagicNumber}".    |
//|   This guarantees no collision when multiple instances of the   |
//|   same EA run simultaneously on different charts.               |
//+------------------------------------------------------------------+
#property strict

#ifndef NEXUS_NX_AUTH_MQH
#define NEXUS_NX_AUTH_MQH

#include "NxPayload.mqh"
#include "NxHttpClient.mqh"
#include "NxRetry.mqh"

//--- Endpoints
#define NX_ENDPOINT_AUTH   "/marketplace/v1/auth"
#define NX_ENDPOINT_RESUME "/marketplace/v1/resume"

//+------------------------------------------------------------------+
//| CNxAuth                                                           |
//+------------------------------------------------------------------+
class CNxAuth
{
private:
   CNxHttpClient *m_http;
   CNxRetry      *m_retry;

   bool   m_authenticated;
   bool   m_is_admin_session;
   string m_last_error_code;
   string m_last_error_msg;

   //+------------------------------------------------------------------+
   //| GlobalVar key — unique per EA instance (tool + magic number)     |
   //+------------------------------------------------------------------+
   string SessionVarKey(const string &tool_key, int magic_number) const
   {
      return "NX_SESSION_" + tool_key + "_" + IntegerToString(magic_number);
   }

   //+------------------------------------------------------------------+
   //| Read account identity from the MT5 terminal                      |
   //+------------------------------------------------------------------+
   bool ReadTerminalAccount(long &login, string &server)
   {
      login  = AccountInfoInteger(ACCOUNT_LOGIN);
      server = AccountInfoString(ACCOUNT_SERVER);
      if(login <= 0 || StringLen(server) == 0)
      {
         NxLog(NX_ERROR, "MT5 is not connected to a trading account.");
         return false;
      }
      return true;
   }

   bool IsAdminSession(const string &body)
   {
      return StringFind(body, "admin_test") >= 0;
   }

   //+------------------------------------------------------------------+
   //| Build JSON body for /auth                                        |
   //+------------------------------------------------------------------+
   string BuildAuthBody(const string &api_key, const string &tool_key,
                        long login, const string &server, int magic_number)
   {
      return "{\"api_key\":\"" + api_key + "\","
           + "\"tool_key\":\"" + tool_key + "\","
           + "\"account_login\":\"" + IntegerToString(login) + "\","
           + "\"account_server\":\"" + server + "\","
           + "\"magic_number\":" + IntegerToString(magic_number) + "}";
   }

   //+------------------------------------------------------------------+
   //| Build JSON body for /resume                                      |
   //+------------------------------------------------------------------+
   string BuildResumeBody(const string &session_token, int magic_number)
   {
      return "{\"session_token\":\"" + session_token + "\","
           + "\"magic_number\":" + IntegerToString(magic_number) + "}";
   }

   //+------------------------------------------------------------------+
   //| TryResume — attempt to resume an existing session               |
   //| Returns true if the server accepted the resume.                  |
   //+------------------------------------------------------------------+
   bool TryResume(const string &tool_key, int magic_number)
   {
      string saved_token = GetSessionVar(tool_key, magic_number);
      if(StringLen(saved_token) == 0)
      {
         NxLog(NX_INFO, "No saved session for this instance — will authenticate.");
         return false;
      }

      NxLog(NX_INFO, "Attempting session resumption for magic=" +
            IntegerToString(magic_number) + "...");

      string body = BuildResumeBody(saved_token, magic_number);
      NxHttpResponse resp = m_http.PostPublic(NX_ENDPOINT_RESUME, body);

      if(resp.status == 200 && StringFind(resp.body, "\"resumed\":true") >= 0)
      {
         // Keep the same token (server extended the TTL)
         m_http.SetSessionToken(saved_token);
         m_authenticated    = true;
         m_is_admin_session = IsAdminSession(resp.body);
         m_last_error_code  = "";
         m_last_error_msg   = "";
         m_retry.RecordSuccess();
         NxLog(NX_INFO, "Session resumed successfully (no new auth required).");
         return true;
      }

      NxLog(NX_INFO, "Session resumption failed (code=" +
            IntegerToString(resp.status) + ") — will re-authenticate.");
      // Clear the stale token
      ClearSessionVar(tool_key, magic_number);
      return false;
   }

   //+------------------------------------------------------------------+
   //| String GlobalVar helpers                                          |
   //| MT5 GlobalVariables only store double. We encode a string token  |
   //| by storing each character's ASCII value in individual GVs with   |
   //| a char-index suffix. Simple and portable.                        |
   //+------------------------------------------------------------------+
   string StrGVPrefix(const string &tool_key, int magic_number) const
   {
      return "NX_TOK_" + tool_key + "_" + IntegerToString(magic_number) + "_";
   }

   void SetSessionVar(const string &tool_key, int magic_number, const string &token)
   {
      string prefix = StrGVPrefix(tool_key, magic_number);
      int len = StringLen(token);
      // Store length
      GlobalVariableSet(prefix + "LEN", (double)len);
      // Store each char
      for(int i = 0; i < len; i++)
         GlobalVariableSet(prefix + IntegerToString(i),
                           (double)StringGetCharacter(token, i));
   }

   string GetSessionVar(const string &tool_key, int magic_number) const
   {
      string prefix = StrGVPrefix(tool_key, magic_number);
      string len_key = prefix + "LEN";
      if(!GlobalVariableCheck(len_key)) return "";
      int len = (int)GlobalVariableGet(len_key);
      if(len <= 0 || len > 256) return "";
      string result = "";
      for(int i = 0; i < len; i++)
      {
         ushort ch = (ushort)GlobalVariableGet(prefix + IntegerToString(i));
         result += ShortToString(ch);
      }
      return result;
   }

   void ClearSessionVar(const string &tool_key, int magic_number)
   {
      string prefix = StrGVPrefix(tool_key, magic_number);
      string len_key = prefix + "LEN";
      if(!GlobalVariableCheck(len_key)) return;
      int len = (int)GlobalVariableGet(len_key);
      GlobalVariableDel(len_key);
      for(int i = 0; i < len && i < 256; i++)
         GlobalVariableDel(prefix + IntegerToString(i));
   }

public:
   CNxAuth(CNxHttpClient *http) : m_http(http)
   {
      m_retry            = new CNxRetry("AUTH");
      m_authenticated    = false;
      m_is_admin_session = false;
      m_last_error_code  = "";
      m_last_error_msg   = "";
   }

   ~CNxAuth()
   {
      if(m_retry != NULL) { delete m_retry; m_retry = NULL; }
   }

   //+------------------------------------------------------------------+
   //| Authenticate                                                      |
   //| Tries session resumption first. Falls back to full auth.         |
   //| Call from OnInit or from OnTimer when m_retry.ShouldAttempt().   |
   //+------------------------------------------------------------------+
   NexusPayload Authenticate(const string &api_key, const string &tool_key,
                             int magic_number = 0)
   {
      m_authenticated = false;

      // Strategy Tester / Optimizer bypass
      if(MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION) ||
         MQLInfoInteger(MQL_VISUAL_MODE) || MQLInfoInteger(MQL_FRAME_MODE))
      {
         m_authenticated    = true;
         m_is_admin_session = false;
         m_last_error_code  = "";
         m_last_error_msg   = "";
         NxLog(NX_INFO, "Strategy Tester mode — licence auth bypassed.");
         return NxOk("TESTER_MODE", "Running in Strategy Tester — auth disabled.");
      }

      if(!m_http.IsConfigured())
         return NxErr("NOT_CONFIGURED", "HTTP client not initialised.");

      if(StringLen(api_key) == 0)
         return NxErr("NO_API_KEY", "API key is empty. Enter your key in the EA settings.");

      if(StringLen(tool_key) == 0)
         return NxErr("NO_TOOL_KEY", "Tool key is empty. Enter your EA tool key.");

      // ── Attempt session resumption ──────────────────────────────────
      // Skip resumption for admin test keys — they always create a new session
      // for proper tracking in admin_test_sessions.
      bool is_admin_key = (StringLen(api_key) >= 4 && StringSubstr(api_key, 0, 4) == "ntk-");
      if(!is_admin_key && TryResume(tool_key, magic_number))
         return NxOk("SESSION_RESUMED", "Session resumed. No re-auth needed.");

      // ── Full authentication ─────────────────────────────────────────
      long   login;
      string server;
      bool has_account = ReadTerminalAccount(login, server);
      if(!has_account)
      {
         login  = 0;
         server = "admin_test";
         NxLog(NX_WARN, "No MT5 account connected. Attempting admin-mode auth.");
      }

      string body = BuildAuthBody(api_key, tool_key, login, server, magic_number);
      NxLog(NX_INFO, "Authenticating with marketplace... login=" +
            IntegerToString(login) + " server=" + server +
            " magic=" + IntegerToString(magic_number));

      NxHttpResponse resp = m_http.PostPublic(NX_ENDPOINT_AUTH, body);
      NexusPayload   result = m_http.ParseAuthResponse(resp);

      if(result.ok)
      {
         m_authenticated    = true;
         m_is_admin_session = IsAdminSession(resp.body);
         m_last_error_code  = "";
         m_last_error_msg   = "";
         m_retry.RecordSuccess();

         // Persist token for future resumption (skip for admin test sessions)
         if(!m_is_admin_session)
         {
            string tok = m_http.GetSessionToken();
            SetSessionVar(tool_key, magic_number, tok);
         }

         if(m_is_admin_session)
            NxLog(NX_WARN, "Admin session active — licence checks bypassed.");
         else
            NxLog(NX_INFO, "Authentication successful. Session active.");
      }
      else
      {
         m_last_error_code = result.code;
         m_last_error_msg  = result.message;
         m_retry.RecordFailure();
      }

      return result;
   }

   //+------------------------------------------------------------------+
   //| TryRetry — call from OnTimer to drive the retry machine          |
   //+------------------------------------------------------------------+
   NexusPayload TryRetry(const string &api_key, const string &tool_key,
                         int magic_number = 0)
   {
      if(MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION))
         return NxOk("RETRY_SKIP", "");
      if(!m_retry.ShouldAttempt())
         return NxOk("RETRY_SKIP", "");

      NxLog(NX_INFO, "Retrying authentication... attempt " +
            IntegerToString(m_retry.Attempt() + 1));

      return Authenticate(api_key, tool_key, magic_number);
   }

   //+------------------------------------------------------------------+
   //| ForceReAuth — call when heartbeat detects SESSION_EXPIRED        |
   //+------------------------------------------------------------------+
   NexusPayload ForceReAuth(const string &api_key, const string &tool_key,
                            int magic_number = 0)
   {
      NxLog(NX_WARN, "Session expired — forcing re-authentication.");
      // Clear saved token so TryResume doesn't attempt with the expired one
      ClearSessionVar(tool_key, magic_number);
      m_retry.Reset();
      m_authenticated = false;
      return Authenticate(api_key, tool_key, magic_number);
   }

   //+------------------------------------------------------------------+
   //| OnDeinit — called when EA is removed from chart                  |
   //| Does NOT clear the session var — session may be resumed on       |
   //| next OnInit (e.g., chart refresh, terminal reconnect).           |
   //+------------------------------------------------------------------+
   // Note: we intentionally do NOT clear the session GlobalVar on EA deinit.
   // This allows session resumption on the next OnInit (chart refresh, reconnect).
   // Truly dead sessions are cleaned up server-side every 6h.
   // Call ClearSessionVar() explicitly only when changing magic number.

   // ─── Getters ─────────────────────────────────────────────────────

   bool   IsAuthenticated()   const { return m_authenticated; }
   bool   IsAdminSession()    const { return m_is_admin_session; }
   bool   IsTesterMode()      const { return (bool)(MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION)); }
   string LastErrorCode()     const { return m_last_error_code; }
   string LastErrorMessage()  const { return m_last_error_msg; }
   bool   IsRetryExhausted()  const { return m_retry.IsExhausted(); }
   bool   IsRetryPending()    const { return m_retry.IsPending(); }
   string RetryStatus()       const { return m_retry.StatusString(); }
};

#endif // NEXUS_NX_AUTH_MQH
