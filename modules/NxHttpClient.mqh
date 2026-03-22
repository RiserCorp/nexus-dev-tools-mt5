//+------------------------------------------------------------------+
//| NxHttpClient.mqh                                                 |
//| Nexus Dev Tools — HTTP client for Marketplace endpoints          |
//|                                                                  |
//| Auth scheme (different from NexusMonitor):                       |
//|   Initial auth call — no auth header (public endpoint)          |
//|   All subsequent calls — Authorization: Bearer <session_token>  |
//|                                                                  |
//| Endpoints used:                                                  |
//|   POST /marketplace/v1/auth       — get session token           |
//|   POST /marketplace/v1/heartbeat  — renew session               |
//+------------------------------------------------------------------+
#property strict

#ifndef NEXUS_NX_HTTP_CLIENT_MQH
#define NEXUS_NX_HTTP_CLIENT_MQH

#include "NxPayload.mqh"

//--- HTTP status codes
#define NX_HTTP_OK           200
#define NX_HTTP_CREATED      201
#define NX_HTTP_BAD_REQ      400
#define NX_HTTP_UNAUTHORIZED 401
#define NX_HTTP_FORBIDDEN    403
#define NX_HTTP_NOT_FOUND    404
#define NX_HTTP_SERVER_ERR   500
#define NX_HTTP_URL_BLOCKED  -2   // MT5 error 4014

//--- Timeout
#define NX_HTTP_TIMEOUT_MS   12000

//+------------------------------------------------------------------+
//| NxHttpResponse — raw HTTP result                                 |
//+------------------------------------------------------------------+
struct NxHttpResponse
{
   int    status;   // HTTP status code; 0 = network error; NX_HTTP_URL_BLOCKED = MT5 block
   string body;
   bool   success;  // true if 2xx
};

//+------------------------------------------------------------------+
//| CNxHttpClient                                                     |
//+------------------------------------------------------------------+
class CNxHttpClient
{
private:
   string m_base_url;
   string m_session_token;   // Bearer token after auth

   // ─── Build headers ────────────────────────────────────────────────

   void BuildPublicHeaders(string &h)
   {
      h = "Content-Type: application/json\r\nAccept: application/json\r\n";
   }

   void BuildAuthHeaders(string &h)
   {
      h = "Content-Type: application/json\r\n"
          "Authorization: Bearer " + m_session_token + "\r\n"
          "Accept: application/json\r\n";
   }

   // ─── Low-level POST ───────────────────────────────────────────────

   NxHttpResponse DoPost(const string &url, const string &json, string &headers)
   {
      char   req_data[];
      char   resp_data[];
      string resp_headers;

      int len = StringLen(json);
      ArrayResize(req_data, len);
      StringToCharArray(json, req_data, 0, len);

      ResetLastError();
      int status = WebRequest("POST", url, headers, NX_HTTP_TIMEOUT_MS,
                              req_data, resp_data, resp_headers);

      NxHttpResponse r;
      if(status == -1)
      {
         int e = GetLastError();
         if(e == 4014)
         {
            NxLog(NX_ERROR, "URL blocked by MT5 (err 4014). Add to allowed URLs: " + url);
            r.status  = NX_HTTP_URL_BLOCKED;
            r.success = false;
         }
         else
         {
            NxLog(NX_WARN, "WebRequest failed. MT5 error=" + IntegerToString(e) + " url=" + url);
            r.status  = 0;
            r.success = false;
         }
         r.body = "";
         return r;
      }

      r.status  = status;
      r.success = (status >= 200 && status < 300);
      r.body    = ArraySize(resp_data) > 0
                  ? CharArrayToString(resp_data, 0, ArraySize(resp_data))
                  : "";
      return r;
   }

   // ─── Simple JSON value extractor ─────────────────────────────────

   string ExtractString(const string &json, const string &key)
   {
      string search = "\"" + key + "\":\"";
      int start = StringFind(json, search);
      if(start < 0) return "";
      start += StringLen(search);
      int end = StringFind(json, "\"", start);
      if(end < 0) return "";
      return StringSubstr(json, start, end - start);
   }

   bool ExtractBool(const string &json, const string &key)
   {
      string search = "\"" + key + "\":";
      int start = StringFind(json, search);
      if(start < 0) return false;
      start += StringLen(search);
      return StringFind(StringSubstr(json, start, 8), "true") >= 0;
   }

public:
   CNxHttpClient() : m_base_url(""), m_session_token("") {}

   void Init(const string base_url)
   {
      m_base_url = base_url;
      // Strip trailing slash
      while(StringLen(m_base_url) > 0 &&
            StringGetCharacter(m_base_url, StringLen(m_base_url) - 1) == '/')
         m_base_url = StringSubstr(m_base_url, 0, StringLen(m_base_url) - 1);
   }

   void   SetSessionToken(const string t) { m_session_token = t; }
   string GetSessionToken()         const { return m_session_token; }
   bool   HasSession()              const { return StringLen(m_session_token) > 0; }
   bool   IsConfigured()            const { return StringLen(m_base_url) > 0; }
   string GetBaseUrl()              const { return m_base_url; }

   //+------------------------------------------------------------------+
   //| PostPublic — no auth header (used for initial /auth call)        |
   //+------------------------------------------------------------------+
   NxHttpResponse PostPublic(const string endpoint, const string json_body)
   {
      string url = m_base_url + endpoint;
      string headers;
      BuildPublicHeaders(headers);
      return DoPost(url, json_body, headers);
   }

   //+------------------------------------------------------------------+
   //| PostBearer — Authorization: Bearer <session_token>               |
   //+------------------------------------------------------------------+
   NxHttpResponse PostBearer(const string endpoint, const string json_body)
   {
      if(!HasSession())
      {
         NxHttpResponse r;
         r.status  = 0;
         r.success = false;
         r.body    = "";
         NxLog(NX_ERROR, "PostBearer called without session token");
         return r;
      }
      string url = m_base_url + endpoint;
      string headers;
      BuildAuthHeaders(headers);
      return DoPost(url, json_body, headers);
   }

   //+------------------------------------------------------------------+
   //| ParseAuthResponse — extract session_token from /auth response   |
   //| Returns NxOk with session_token in .data, or NxErr on failure.  |
   //+------------------------------------------------------------------+
   NexusPayload ParseAuthResponse(const NxHttpResponse &resp)
   {
      if(resp.status == NX_HTTP_URL_BLOCKED)
         return NxErr("URL_BLOCKED",
                      "MT5 has blocked the marketplace URL. Add it to Tools > Options > Expert Advisors.");

      if(resp.status == 0)
         return NxErr("NETWORK_ERROR", "Cannot reach the marketplace server.");

      if(resp.status == NX_HTTP_UNAUTHORIZED || resp.status == NX_HTTP_FORBIDDEN)
         return NxErr("AUTH_REJECTED",
                      "Invalid API key or tool key. Check your settings.");

      if(resp.status == NX_HTTP_NOT_FOUND)
         return NxErr("LICENCE_NOT_FOUND",
                      "No active licence found for this account. Subscribe on the marketplace.");

      if(!resp.success)
         return NxErr("AUTH_FAILED",
                      "Server returned HTTP " + IntegerToString(resp.status));

      if(!ExtractBool(resp.body, "success"))
         return NxErr("AUTH_FAILED", "Server response: success=false. Body=" + resp.body);

      // Navigate into data object to find session_token
      string token = ExtractString(resp.body, "session_token");
      if(StringLen(token) == 0)
         return NxErr("PARSE_ERROR", "session_token not found in response.");

      string expires = ExtractString(resp.body, "expires_at");

      m_session_token = token;
      NxLog(NX_INFO, "Session token received. Expires: " + expires);

      return NxOk("AUTH_OK", "Licence validated. Session active.", token);
   }

   //+------------------------------------------------------------------+
   //| ParseHeartbeatResponse — validate /heartbeat response            |
   //+------------------------------------------------------------------+
   NexusPayload ParseHeartbeatResponse(const NxHttpResponse &resp)
   {
      if(resp.status == NX_HTTP_URL_BLOCKED)
         return NxErr("URL_BLOCKED", "MT5 blocked the marketplace URL.");

      if(resp.status == 0)
         return NxWarn("HEARTBEAT_NETWORK", "Heartbeat failed — network error.");

      if(resp.status == NX_HTTP_UNAUTHORIZED)
      {
         m_session_token = "";  // Session expired — will trigger re-auth
         return NxErr("SESSION_EXPIRED", "Session token expired or revoked.");
      }

      if(!resp.success)
         return NxWarn("HEARTBEAT_FAILED",
                       "Heartbeat returned HTTP " + IntegerToString(resp.status));

      return NxOk("HEARTBEAT_OK", "Heartbeat acknowledged.");
   }
};

#endif // NEXUS_NX_HTTP_CLIENT_MQH
