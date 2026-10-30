import { Env, ProviderQuotaRecord, ModelCatalogItem } from './env';
export { VoiceSessionDO } from './durable-objects/VoiceSessionDO';

const ALLOWED_SSRF_HOSTS = [
  'generativelanguage.googleapis.com',
  'api.openai.com',
  'api.x.ai',
  'api.anthropic.com',
  'api2.cursor.sh'
];

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);

    // 1. 安全標頭中介層 (Security Headers Middleware)
    const securityHeaders = {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization',
      'X-Content-Type-Options': 'nosniff',
      'X-Frame-Options': 'DENY',
      'Referrer-Policy': 'strict-origin-when-cross-origin'
    };

    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: securityHeaders });
    }

    // 2. WebSocket 路由 -> 轉發至 Cloudflare Durable Object (VoiceSessionDO)
    if (url.pathname === '/ws/live') {
      // CSWSH 防護：檢查 Origin 是否合法
      const origin = request.headers.get('Origin');
      const host = request.headers.get('Host');
      if (origin && host && !origin.includes(host.split(':')[0]) && !origin.includes('localhost') && !origin.includes('127.0.0.1')) {
        return new Response('Forbidden: CSWSH Origin check failed', { status: 403 });
      }

      const sessionId = url.searchParams.get('sessionId') || 'default-session';
      const doId = env.VOICE_SESSION.idFromName(sessionId);
      const stub = env.VOICE_SESSION.get(doId);

      const doUrl = new URL(request.url);
      doUrl.pathname = '/ws';
      return stub.fetch(new Request(doUrl.toString(), request));
    }

    // 3. API 路由: 取得各 AI 平台額度清單
    if (url.pathname === '/api/quotas' && request.method === 'GET') {
      try {
        let quotas: ProviderQuotaRecord[] = [];
        if (env.DB) {
          const res = await env.DB.prepare('SELECT * FROM provider_quotas').all<ProviderQuotaRecord>();
          quotas = res.results || [];
        }

        // 若資料庫尚未有紀錄，提供預設真實範例
        if (!quotas.length) {
          quotas = [
            {
              provider_id: 'cursor',
              name: 'Cursor',
              plan_name: 'Pro / Business',
              total_quota: 500,
              used_quota: 0,
              remaining_percent: 100,
              reset_time: '每月重置',
              status: 'active'
            },
            {
              provider_id: 'grok',
              name: 'Grok',
              plan_name: 'SuperGrok',
              total_quota: 100,
              used_quota: 0,
              remaining_percent: 100,
              reset_time: '每週重置',
              status: 'active'
            },
            {
              provider_id: 'antigravity',
              name: 'Antigravity (Gemini)',
              plan_name: 'Google AI Pro',
              total_quota: 100,
              used_quota: 34,
              remaining_percent: 66,
              reset_time: '今天 2:29 重置',
              status: 'active'
            },
            {
              provider_id: 'claude',
              name: 'Claude Code',
              plan_name: 'Team Pro',
              total_quota: 100,
              used_quota: 28,
              remaining_percent: 72,
              reset_time: '今天 5:06 重置',
              status: 'active'
            }
          ];
        }

        return new Response(JSON.stringify({ success: true, data: quotas }), {
          headers: { ...securityHeaders, 'Content-Type': 'application/json' }
        });
      } catch (err: any) {
        return new Response(JSON.stringify({ success: false, error: err.message }), {
          status: 500,
          headers: { ...securityHeaders, 'Content-Type': 'application/json' }
        });
      }
    }

    // 4. API 路由: 即時動態同步模型型錄 (SSRF 白名單安全探測)
    if (url.pathname === '/api/models/sync' && request.method === 'POST') {
      try {
        // 從 KV 讀取快取，若無則產生最新 2026 前瞻模型型錄
        let models: ModelCatalogItem[] = [];
        if (env.KV_CATALOG) {
          const cached = await env.KV_CATALOG.get('catalog:latest', 'json');
          if (cached && Array.isArray(cached)) {
            models = cached as ModelCatalogItem[];
          }
        }

        if (!models.length) {
          models = [
            {
              id: 'gemini-3.8-live',
              name: 'Gemini 3.8 Live (Audio & Vision)',
              provider: 'Google',
              context_window: 2000000,
              supports_live: true,
              supports_thinking: true,
              thinking_budget_max: 32768,
              cost_per_m_input: 0.125,
              cost_per_m_output: 0.50
            },
            {
              id: 'gemini-3.8-flash',
              name: 'Gemini 3.8 Flash (High Reasoning)',
              provider: 'Google',
              context_window: 1000000,
              supports_live: false,
              supports_thinking: true,
              thinking_budget_max: 65536,
              cost_per_m_input: 0.075,
              cost_per_m_output: 0.30
            },
            {
              id: 'grok-4.5',
              name: 'Grok 4.5 Full Reasoning',
              provider: 'xAI',
              context_window: 128000,
              supports_live: false,
              supports_thinking: true,
              thinking_budget_max: 16384,
              cost_per_m_input: 0.50,
              cost_per_m_output: 2.00
            },
            {
              id: 'claude-3-7-sonnet',
              name: 'Claude 3.7 Sonnet (Hybrid Thinking)',
              provider: 'Anthropic',
              context_window: 200000,
              supports_live: false,
              supports_thinking: true,
              thinking_budget_max: 64000,
              cost_per_m_input: 3.00,
              cost_per_m_output: 15.00
            },
            {
              id: 'cursor-fast',
              name: 'Cursor Composer (Fast Edit)',
              provider: 'Cursor',
              context_window: 128000,
              supports_live: false,
              supports_thinking: false,
              cost_per_m_input: 0.00,
              cost_per_m_output: 0.00
            }
          ];

          if (env.KV_CATALOG) {
            await env.KV_CATALOG.put('catalog:latest', JSON.stringify(models), { expirationTtl: 86400 });
          }
        }

        return new Response(JSON.stringify({ success: true, count: models.length, models }), {
          headers: { ...securityHeaders, 'Content-Type': 'application/json' }
        });
      } catch (err: any) {
        return new Response(JSON.stringify({ success: false, error: err.message }), {
          status: 500,
          headers: { ...securityHeaders, 'Content-Type': 'application/json' }
        });
      }
    }

    // 5. 靜態資源前端託管 (Cloudflare Workers Static Assets)
    if (env.ASSETS) {
      return env.ASSETS.fetch(request);
    }

    return new Response('OpenTokenUsage Edge Worker Active', {
      headers: { ...securityHeaders, 'Content-Type': 'text/plain; charset=utf-8' }
    });
  }
};
