//+------------------------------------------------------------------+
//| NxRetry.mqh                                                      |
//| Nexus Dev Tools — Exponential backoff retry state machine        |
//|                                                                  |
//| Retry schedule (seconds):  5 → 15 → 30 → 60                    |
//| After 4 failed attempts the state stays EXHAUSTED until the     |
//| developer resolves the issue and the EA is restarted, OR until  |
//| Reset() is called explicitly on a live correction.              |
//|                                                                  |
//| Design: the EA never blocks MT5. OnTimer drives the retries.    |
//| Each call to ShouldAttempt() returns true once per interval.    |
//+------------------------------------------------------------------+
#property strict

#ifndef NEXUS_NX_RETRY_MQH
#define NEXUS_NX_RETRY_MQH

#include "NxPayload.mqh"

//--- Retry schedule in seconds
#define NX_RETRY_DELAYS_COUNT 4
static int NX_RETRY_DELAYS[NX_RETRY_DELAYS_COUNT] = { 5, 15, 30, 60 };

//--- States
enum ENUM_RETRY_STATE
{
   RETRY_IDLE,       // No retry pending — everything OK
   RETRY_PENDING,    // Waiting for next attempt interval
   RETRY_EXHAUSTED   // All attempts used — manual restart required
};

//+------------------------------------------------------------------+
//| CNxRetry                                                          |
//+------------------------------------------------------------------+
class CNxRetry
{
private:
   ENUM_RETRY_STATE m_state;
   int              m_attempt;      // 0-based, incremented before each try
   datetime         m_next_try;     // UTC time of next allowed attempt
   string           m_context;      // label for log messages (e.g. "AUTH", "HEARTBEAT")

public:
   CNxRetry(const string context = "AUTH")
      : m_state(RETRY_IDLE), m_attempt(0), m_next_try(0), m_context(context) {}

   //+------------------------------------------------------------------+
   //| RecordSuccess — call when the underlying operation succeeds      |
   //+------------------------------------------------------------------+
   void RecordSuccess()
   {
      if(m_state != RETRY_IDLE)
         NxLog(NX_INFO, m_context + " recovered after " +
               IntegerToString(m_attempt) + " attempt(s).");
      m_state   = RETRY_IDLE;
      m_attempt = 0;
      m_next_try = 0;
   }

   //+------------------------------------------------------------------+
   //| RecordFailure — call when the underlying operation fails         |
   //| Schedules the next attempt and logs the delay.                   |
   //+------------------------------------------------------------------+
   void RecordFailure()
   {
      if(m_state == RETRY_EXHAUSTED) return;

      if(m_attempt >= NX_RETRY_DELAYS_COUNT)
      {
         m_state = RETRY_EXHAUSTED;
         NxLog(NX_ERROR, m_context + " — all " + IntegerToString(NX_RETRY_DELAYS_COUNT) +
               " retry attempts exhausted. Restart the EA after fixing the issue.");
         return;
      }

      int delay  = NX_RETRY_DELAYS[m_attempt];
      m_next_try = TimeGMT() + delay;
      m_state    = RETRY_PENDING;
      m_attempt++;

      NxLog(NX_WARN, m_context + " failed. Retry " + IntegerToString(m_attempt) +
            "/" + IntegerToString(NX_RETRY_DELAYS_COUNT) +
            " in " + IntegerToString(delay) + "s.");
   }

   //+------------------------------------------------------------------+
   //| ShouldAttempt — returns true when it's time to retry            |
   //| Call this in OnTimer. It returns true only once per interval.    |
   //+------------------------------------------------------------------+
   bool ShouldAttempt()
   {
      if(m_state == RETRY_IDLE)      return false;
      if(m_state == RETRY_EXHAUSTED) return false;
      if(TimeGMT() < m_next_try)     return false;

      // Move next_try far ahead to prevent double-trigger within same tick
      m_next_try = TimeGMT() + 3600;
      return true;
   }

   //+------------------------------------------------------------------+
   //| Reset — fully clear the state (call if user corrects the issue   |
   //| at runtime, e.g. a new licence is assigned to the account)       |
   //+------------------------------------------------------------------+
   void Reset()
   {
      m_state    = RETRY_IDLE;
      m_attempt  = 0;
      m_next_try = 0;
      NxLog(NX_INFO, m_context + " retry state reset.");
   }

   // ─── Getters ─────────────────────────────────────────────────────

   ENUM_RETRY_STATE State()       const { return m_state; }
   int              Attempt()     const { return m_attempt; }
   bool             IsExhausted() const { return m_state == RETRY_EXHAUSTED; }
   bool             IsPending()   const { return m_state == RETRY_PENDING; }
   bool             IsIdle()      const { return m_state == RETRY_IDLE; }

   // Seconds until next attempt (0 if ready or idle)
   int SecondsUntilNext() const
   {
      if(m_state != RETRY_PENDING) return 0;
      int remaining = (int)(m_next_try - TimeGMT());
      return remaining > 0 ? remaining : 0;
   }

   string StatusString() const
   {
      switch(m_state)
      {
         case RETRY_IDLE:      return "OK";
         case RETRY_EXHAUSTED: return "EXHAUSTED — restart EA";
         case RETRY_PENDING:
            return "Retry " + IntegerToString(m_attempt) + "/" +
                   IntegerToString(NX_RETRY_DELAYS_COUNT) +
                   " in " + IntegerToString(SecondsUntilNext()) + "s";
      }
      return "Unknown";
   }
};

#endif // NEXUS_NX_RETRY_MQH
