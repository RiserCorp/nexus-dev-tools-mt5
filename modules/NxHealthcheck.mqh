//+------------------------------------------------------------------+
//| NxHealthcheck.mqh                                                |
//| Nexus Dev Tools — Periodic heartbeat & licence validation        |
//|                                                                  |
//| Behaviour:                                                       |
//|   - Calls POST /marketplace/v1/heartbeat every 60 minutes       |
//|   - On SESSION_EXPIRED: triggers re-auth via CNxAuth            |
//|   - On NETWORK error: logs warning, does NOT stop the EA        |
//|   - Tracks consecutive failures to surface in dashboard         |
//|   - On licence revocation (403): logs error, EA continues       |
//+------------------------------------------------------------------+
#property strict

#ifndef NEXUS_NX_HEALTHCHECK_MQH
#define NEXUS_NX_HEALTHCHECK_MQH

#include "NxPayload.mqh"
#include "NxHttpClient.mqh"
#include "NxRetry.mqh"

//--- Endpoint
#define NX_ENDPOINT_HEARTBEAT "/marketplace/v1/heartbeat"

//--- How often to send a heartbeat (seconds)
#define NX_HEARTBEAT_INTERVAL_SEC 3600   // 60 minutes

//+------------------------------------------------------------------+
//| CNxHealthcheck                                                    |
//+------------------------------------------------------------------+
class CNxHealthcheck
{
private:
   CNxHttpClient *m_http;
   CNxRetry      *m_retry;

   datetime m_last_heartbeat;    // UTC time of last successful heartbeat
   datetime m_next_heartbeat;    // UTC time when next heartbeat is due
   int      m_consecutive_fails; // consecutive failed heartbeats
   bool     m_session_valid;     // false when server says session is gone

public:
   CNxHealthcheck(CNxHttpClient *http)
      : m_http(http),
        m_last_heartbeat(0),
        m_next_heartbeat(0),
        m_consecutive_fails(0),
        m_session_valid(true)
   {
      m_retry = new CNxRetry("HEARTBEAT");
   }

   ~CNxHealthcheck()
   {
      if(m_retry != NULL) { delete m_retry; m_retry = NULL; }
   }

   //+------------------------------------------------------------------+
   //| OnAuthSuccess — reset heartbeat schedule after successful auth   |
   //+------------------------------------------------------------------+
   void OnAuthSuccess()
   {
      m_last_heartbeat    = TimeGMT();
      m_next_heartbeat    = TimeGMT() + NX_HEARTBEAT_INTERVAL_SEC;
      m_consecutive_fails = 0;
      m_session_valid     = true;
      m_retry.Reset();
      NxLog(NX_INFO, "Heartbeat scheduled in " +
            IntegerToString(NX_HEARTBEAT_INTERVAL_SEC / 60) + " min.");
   }

   //+------------------------------------------------------------------+
   //| IsDue — returns true when a heartbeat should be sent            |
   //| Call from OnTimer.                                               |
   //+------------------------------------------------------------------+
   bool IsDue() const
   {
      if(MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION)) return false;
      if(m_next_heartbeat == 0) return false;
      return TimeGMT() >= m_next_heartbeat;
   }

   //+------------------------------------------------------------------+
   //| Send — perform one heartbeat call                                |
   //| Returns:                                                          |
   //|   NxOk("HEARTBEAT_OK")      — heartbeat accepted               |
   //|   NxWarn("HEARTBEAT_FAIL")  — network/server error, keep going |
   //|   NxErr("SESSION_EXPIRED")  — session gone, re-auth required    |
   //|   NxErr("LICENCE_REVOKED")  — licence cancelled by user/admin  |
   //+------------------------------------------------------------------+
   NexusPayload Send()
   {
      if(!m_http.HasSession())
         return NxErr("NO_SESSION", "Cannot send heartbeat — no active session.");

      string body = "{\"session_token\":\"" + m_http.GetSessionToken() + "\"}";
      NxLog(NX_INFO, "Sending heartbeat...");

      NxHttpResponse resp = m_http.PostBearer(NX_ENDPOINT_HEARTBEAT, body);
      NexusPayload   result = m_http.ParseHeartbeatResponse(resp);

      if(result.ok)
      {
         m_last_heartbeat    = TimeGMT();
         m_next_heartbeat    = TimeGMT() + NX_HEARTBEAT_INTERVAL_SEC;
         m_consecutive_fails = 0;
         m_session_valid     = true;
         m_retry.RecordSuccess();
         NxLog(NX_INFO, "Heartbeat OK. Next in " +
               IntegerToString(NX_HEARTBEAT_INTERVAL_SEC / 60) + " min.");
      }
      else if(result.code == "SESSION_EXPIRED")
      {
         m_session_valid = false;
         m_consecutive_fails++;
         // Caller (main EA) must call auth.ForceReAuth()
      }
      else
      {
         // Network or transient error
         m_consecutive_fails++;
         m_next_heartbeat = TimeGMT() + 300;  // Retry in 5 min on transient fail
         m_retry.RecordFailure();
         NxLog(NX_WARN, "Heartbeat failed (" + result.code + "). "
               + IntegerToString(m_consecutive_fails) + " consecutive failure(s).");
      }

      return result;
   }

   // ─── Getters ─────────────────────────────────────────────────────

   bool     SessionValid()       const { return m_session_valid; }
   int      ConsecutiveFails()   const { return m_consecutive_fails; }
   datetime LastHeartbeat()      const { return m_last_heartbeat; }
   datetime NextHeartbeat()      const { return m_next_heartbeat; }

   string LastHeartbeatString() const
   {
      if(m_last_heartbeat == 0) return "--:--:--";
      MqlDateTime dt;
      TimeToStruct(m_last_heartbeat, dt);
      return StringFormat("%02d:%02d:%02d UTC", dt.hour, dt.min, dt.sec);
   }

   string NextHeartbeatString() const
   {
      if(m_next_heartbeat == 0) return "--:--:--";
      int remaining = (int)(m_next_heartbeat - TimeGMT());
      if(remaining <= 0) return "now";
      int mins = remaining / 60;
      int secs = remaining % 60;
      return StringFormat("in %dm %ds", mins, secs);
   }
};

#endif // NEXUS_NX_HEALTHCHECK_MQH
