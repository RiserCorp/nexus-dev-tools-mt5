//+------------------------------------------------------------------+
//| NxPayload.mqh                                                    |
//| Nexus Dev Tools — Structured result & logging system            |
//|                                                                  |
//| Pattern inspired by Go-style returns:                            |
//|   { ok: bool, code: string, message: string, data: string }     |
//|                                                                  |
//| Usage:                                                           |
//|   NexusPayload res = NxOk("AUTH_OK", "Session active");         |
//|   NexusPayload err = NxErr("LICENCE_INVALID", "No licence");    |
//|   NxLog(NX_INFO, "Heartbeat sent");                             |
//+------------------------------------------------------------------+
#property strict

#ifndef NEXUS_PAYLOAD_MQH
#define NEXUS_PAYLOAD_MQH

//--- Log levels
#define NX_INFO   "INFO"
#define NX_WARN   "WARN"
#define NX_ERROR  "ERROR"
#define NX_DEBUG  "DEBUG"

//--- Maximum entries kept in the in-memory log ring buffer
#define NX_LOG_MAX 64

//+------------------------------------------------------------------+
//| NexusPayload — single result container                           |
//| Mimics Go's (value, error) pattern with a structured payload.   |
//+------------------------------------------------------------------+
struct NexusPayload
{
   bool   ok;       // true = success
   string code;     // machine-readable code  (e.g. "AUTH_OK", "NETWORK_ERROR")
   string message;  // human-readable message (shown in dashboard)
   string data;     // optional extra data    (JSON string or plain value)
};

//+------------------------------------------------------------------+
//| NexusLogEntry — one log line in the ring buffer                  |
//+------------------------------------------------------------------+
struct NexusLogEntry
{
   string timestamp;
   string level;
   string message;
};

//+------------------------------------------------------------------+
//| NxLogBuffer — global ring buffer shared across all modules       |
//| The dashboard reads from here to display the log sections.       |
//+------------------------------------------------------------------+
class NxLogBuffer
{
private:
   NexusLogEntry m_entries[NX_LOG_MAX];
   int           m_head;     // next write position (ring)
   int           m_count;    // total entries stored (capped at NX_LOG_MAX)

   static NxLogBuffer *s_instance;

   NxLogBuffer() : m_head(0), m_count(0) {}

public:
   static NxLogBuffer *Get()
   {
      if(s_instance == NULL) s_instance = new NxLogBuffer();
      return s_instance;
   }

   static void Release()
   {
      if(s_instance != NULL) { delete s_instance; s_instance = NULL; }
   }

   void Push(const string level, const string message)
   {
      MqlDateTime dt;
      TimeToStruct(TimeGMT(), dt);
      m_entries[m_head].timestamp = StringFormat("%02d:%02d:%02d", dt.hour, dt.min, dt.sec);
      m_entries[m_head].level     = level;
      m_entries[m_head].message   = message;
      m_head  = (m_head + 1) % NX_LOG_MAX;
      if(m_count < NX_LOG_MAX) m_count++;
   }

   // Read the last N entries newest-first
   void GetRecent(int n, NexusLogEntry &out[], int &count)
   {
      count = MathMin(n, m_count);
      ArrayResize(out, count);
      int pos = (m_head - 1 + NX_LOG_MAX) % NX_LOG_MAX;
      for(int i = 0; i < count; i++)
      {
         out[i] = m_entries[pos];
         pos = (pos - 1 + NX_LOG_MAX) % NX_LOG_MAX;
      }
   }

   // Filter by level and return last N matches
   void GetByLevel(const string level, int n, NexusLogEntry &out[], int &count)
   {
      count = 0;
      ArrayResize(out, n);
      int pos   = (m_head - 1 + NX_LOG_MAX) % NX_LOG_MAX;
      int total = m_count;
      for(int i = 0; i < total && count < n; i++)
      {
         if(m_entries[pos].level == level)
         {
            out[count] = m_entries[pos];
            count++;
         }
         pos = (pos - 1 + NX_LOG_MAX) % NX_LOG_MAX;
      }
   }

   int Count() const { return m_count; }
};

// Static instance definition
NxLogBuffer *NxLogBuffer::s_instance = NULL;

//+------------------------------------------------------------------+
//| Free helper functions                                             |
//+------------------------------------------------------------------+

// Log a message to the ring buffer AND to the MT5 Journal
void NxLog(const string level, const string message)
{
   NxLogBuffer::Get().Push(level, message);
   Print("[NexusDev][", level, "] ", message);
}

// Build a success payload
NexusPayload NxOk(const string code = "OK",
                  const string message = "",
                  const string data = "")
{
   NexusPayload p;
   p.ok      = true;
   p.code    = code;
   p.message = message;
   p.data    = data;
   return p;
}

// Build an error payload and log it automatically
NexusPayload NxErr(const string code,
                   const string message,
                   const string data = "")
{
   NxLog(NX_ERROR, code + " — " + message);
   NexusPayload p;
   p.ok      = false;
   p.code    = code;
   p.message = message;
   p.data    = data;
   return p;
}

// Build a warning payload and log it
NexusPayload NxWarn(const string code,
                    const string message,
                    const string data = "")
{
   NxLog(NX_WARN, code + " — " + message);
   NexusPayload p;
   p.ok      = false;
   p.code    = code;
   p.message = message;
   p.data    = data;
   return p;
}

#endif // NEXUS_PAYLOAD_MQH
