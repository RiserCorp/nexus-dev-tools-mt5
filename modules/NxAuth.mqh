//+------------------------------------------------------------------+
//| NxAuth.mqh                                                       |
//| Nexus Dev Tools — Marketplace authentication module              |
//|                                                                  |
//| Flow:                                                            |
//|   1. POST /marketplace/v1/auth with user api_key + tool_key     |
//|      + account_login + account_server from the MT5 terminal     |
//|   2. On success: store session_token, mark as operational       |
//|   3. On failure: log the error, schedule retry via CNxRetry     |
//|                                                                  |
//| Admin bypass:                                                    |
//|   If the api_key belongs to a platform admin, the server        |
//|   returns a session of type "admin_test". The EA detects this   |
//|   and sets m_is_admin_session = true, allowing operation        |
//|   without a configured account on the platform.                 |
//+------------------------------------------------------------------+
#property strict

#ifndef NEXUS_NX_AUTH_MQH
#define NEXUS_NX_AUTH_MQH

#include "NxPayload.mqh"
#include "NxHttpClient.mqh"
#include "NxRetry.mqh"

//--- Endpoint
#define NX_ENDPOINT_AUTH "/marketplace/v1/auth"

//+------------------------------------------------------------------+
//| CNxAuth                                                           |
//+------------------------------------------------------------------+
class CNxAuth
{
private:
   CNxHttpClient *m_http;
   CNxRetry      *m_retry;

   bool   m_authenticated;     // true after a successful auth
   bool   m_is_admin_session;  // true when server returns admin_test session
   string m_last_error_code;
   string m_last_error_msg;

   // Read account identity from the MT5 terminal
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

   // Detect admin session from response body
   bool IsAdminSession(const string &body)
   {
      return StringFind(body, "admin_test") >= 0;
   }

   // Build JSON body for /auth
   string BuildAuthBody(const string &api_key, const string &tool_key,
                        long login, const string &server)
   {
      return "{\"api_key\":\"" + api_key + "\","
           + "\"tool_key\":\"" + tool_key + "\","
           + "\"account_login\":\"" + IntegerToString(login) + "\","
           + "\"account_server\":\"" + server + "\"}";
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
   //| Call from OnInit or from OnTimer when m_retry.ShouldAttempt().   |
   //| Returns NxOk on success, NxErr on failure.                       |
   //+------------------------------------------------------------------+
   NexusPayload Authenticate(const string &api_key, const string &tool_key)
   {
      m_authenticated = false;

      if(!m_http.IsConfigured())
         return NxErr("NOT_CONFIGURED", "HTTP client not initialised.");

      if(StringLen(api_key) == 0)
         return NxErr("NO_API_KEY", "API key is empty. Enter your key in the EA settings.");

      if(StringLen(tool_key) == 0)
         return NxErr("NO_TOOL_KEY", "Tool key is empty. Enter your EA tool key.");

      long   login;
      string server;

      // Admin mode: skip account verification if no MT5 account is connected.
      // The server will validate the admin key and return an admin_test session.
      bool has_account = ReadTerminalAccount(login, server);
      if(!has_account)
      {
         // Attempt with zero login — server will handle admin bypass
         login  = 0;
         server = "admin_test";
         NxLog(NX_WARN, "No MT5 account connected. Attempting admin-mode auth.");
      }

      string body = BuildAuthBody(api_key, tool_key, login, server);
      NxLog(NX_INFO, "Authenticating with marketplace... login=" +
            IntegerToString(login) + " server=" + server);

      NxHttpResponse resp = m_http.PostPublic(NX_ENDPOINT_AUTH, body);
      NexusPayload   result = m_http.ParseAuthResponse(resp);

      if(result.ok)
      {
         m_authenticated    = true;
         m_is_admin_session = IsAdminSession(resp.body);
         m_last_error_code  = "";
         m_last_error_msg   = "";
         m_retry.RecordSuccess();

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
   //| Returns NxOk if a retry was performed and succeeded.             |
   //| Returns NxErr if retry fired but failed again.                   |
   //| Returns NxOk("RETRY_SKIP") if it is not yet time to retry.      |
   //+------------------------------------------------------------------+
   NexusPayload TryRetry(const string &api_key, const string &tool_key)
   {
      if(!m_retry.ShouldAttempt())
         return NxOk("RETRY_SKIP", "");

      NxLog(NX_INFO, "Retrying authentication... attempt " +
            IntegerToString(m_retry.Attempt() + 1));

      return Authenticate(api_key, tool_key);
   }

   //+------------------------------------------------------------------+
   //| ForceReAuth — call when heartbeat detects session_expired        |
   //| Resets retry counter and immediately attempts a new auth.        |
   //+------------------------------------------------------------------+
   NexusPayload ForceReAuth(const string &api_key, const string &tool_key)
   {
      NxLog(NX_WARN, "Session expired — forcing re-authentication.");
      m_retry.Reset();
      m_authenticated = false;
      return Authenticate(api_key, tool_key);
   }

   // ─── Getters ─────────────────────────────────────────────────────

   bool   IsAuthenticated()   const { return m_authenticated; }
   bool   IsAdminSession()    const { return m_is_admin_session; }
   string LastErrorCode()     const { return m_last_error_code; }
   string LastErrorMessage()  const { return m_last_error_msg; }
   bool   IsRetryExhausted()  const { return m_retry.IsExhausted(); }
   bool   IsRetryPending()    const { return m_retry.IsPending(); }
   string RetryStatus()       const { return m_retry.StatusString(); }
};

#endif // NEXUS_NX_AUTH_MQH
