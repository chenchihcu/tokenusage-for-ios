import { Env, ProviderQuotaRecord, ModelCatalogItem } from './env';
import { securityHeaders as allowlistedHeaders } from '../shared/cors';

const ALLOWED_SSRF_HOSTS = [
  'generativelanguage.googleapis.com',
  'api.openai.com',
  'api.x.ai',
  'api.anthropic.com',
  'api2.cursor.sh'
];

// 過期/舊版廢棄模型黑名單 (Deprecation Guard)
const DEPRECATED_MODEL_PATTERNS = [
  /gpt-3\.5/i,
  /davinci/i,
  /claude-[12]/i,
  /gemini-1\.0/i,
  /gpt-4-0[36]1[34]/i,
  /babbage/i,
  /curie/i,
  /ada/i,
];

export function purgeDeprecatedModels(models: ModelCatalogItem[]): ModelCatalogItem[] {
  return models.filter(m => {
    const isDeprecated = DEPRECATED_MODEL_PATTERNS.some(p => p.test(m.id) || p.test(m.name));
    return !isDeprecated && m.status === 'active';
  });
}

// 5 大平台現役前瞻模型型錄 SSOT
export const ACTIVE_FRONTIER_MODELS: ModelCatalogItem[] = [
  // OpenAI (Codex / ChatGPT)
  {
    id: 'gpt-6.1-sol',
    name: 'GPT-6.1 Sol (Workhorse Coding)',
    provider: 'OpenAI',
    context_window: 128000,
    supports_live: false,
    supports_thinking: true,
    thinking_budget_max: 32768,
    cost_per_m_input: 1.25,
    cost_per_m_output: 5.00,
    status: 'active',
    verified_date: '2026-10-30'
  },
  {
    id: 'gpt-6-astra',
    name: 'GPT-6 Astra (Frontier Intelligence)',
    provider: 'OpenAI',
    context_window: 200000,
    supports_live: false,
    supports_thinking: true,
    thinking_budget_max: 65536,
    cost_per_m_input: 2.50,
    cost_per_m_output: 10.00,
    status: 'active',
    verified_date: '2026-10-30'
  },
  {
    id: 'o3-mini',
    name: 'OpenAI o3-mini (High Reasoning 100K)',
    provider: 'OpenAI',
    context_window: 128000,
    supports_live: false,
    supports_thinking: true,
    thinking_budget_max: 100000,
    cost_per_m_input: 1.10,
    cost_per_m_output: 4.40,
    status: 'active',
    verified_date: '2026-10-30'
  },
  {
    id: 'gpt-4o-latest',
    name: 'GPT-4o (Omni Multimodal Flagship)',
    provider: 'OpenAI',
    context_window: 128000,
    supports_live: false,
    supports_thinking: false,
    cost_per_m_input: 2.50,
    cost_per_m_output: 10.00,
    status: 'active',
    verified_date: '2026-10-30'
  },
  // Google (Antigravity / Gemini)
  {
    id: 'gemini-3.8-flash',
    name: 'Gemini 3.8 Flash (High Reasoning)',
    provider: 'Google',
    context_window: 1000000,
    supports_live: false,
    supports_thinking: true,
    thinking_budget_max: 65536,
    cost_per_m_input: 0.075,
    cost_per_m_output: 0.30,
    status: 'active',
    verified_date: '2026-10-30'
  },
  {
    id: 'gemini-3.8-live',
    name: 'Gemini 3.8 Live (Audio & Vision Stream)',
    provider: 'Google',
    context_window: 2000000,
    supports_live: true,
    supports_thinking: true,
    thinking_budget_max: 32768,
    cost_per_m_input: 0.125,
    cost_per_m_output: 0.50,
    status: 'active',
    verified_date: '2026-10-30'
  },
  {
    id: 'gemini-2.5-pro',
    name: 'Gemini 2.5 Pro (Deep Code & Context)',
    provider: 'Google',
    context_window: 1000000,
    supports_live: false,
    supports_thinking: true,
    thinking_budget_max: 32768,
    cost_per_m_input: 1.25,
    cost_per_m_output: 5.00,
    status: 'active',
    verified_date: '2026-10-30'
  },
  {
    id: 'gemini-2.5-flash',
    name: 'Gemini 2.5 Flash (Agile Workhorse)',
    provider: 'Google',
    context_window: 1000000,
    supports_live: false,
    supports_thinking: false,
    cost_per_m_input: 0.075,
    cost_per_m_output: 0.30,
    status: 'active',
    verified_date: '2026-10-30'
  },
  // Anthropic (Claude Code)
  {
    id: 'claude-3-7-sonnet',
    name: 'Claude 3.7 Sonnet (Hybrid Thinking)',
    provider: 'Anthropic',
    context_window: 200000,
    supports_live: false,
    supports_thinking: true,
    thinking_budget_max: 64000,
    cost_per_m_input: 3.00,
    cost_per_m_output: 15.00,
    status: 'active',
    verified_date: '2026-10-30'
  },
  {
    id: 'claude-3-5-sonnet',
    name: 'Claude 3.5 Sonnet (Frontier Coding)',
    provider: 'Anthropic',
    context_window: 200000,
    supports_live: false,
    supports_thinking: false,
    cost_per_m_input: 3.00,
    cost_per_m_output: 15.00,
    status: 'active',
    verified_date: '2026-10-30'
  },
  {
    id: 'claude-3-5-haiku',
    name: 'Claude 3.5 Haiku (Fast Agent)',
    provider: 'Anthropic',
    context_window: 200000,
    supports_live: false,
    supports_thinking: false,
    cost_per_m_input: 0.80,
    cost_per_m_output: 4.00,
    status: 'active',
    verified_date: '2026-10-30'
  },
  {
    id: 'claude-fable-5-1',
    name: 'Claude Fable 5.1 (Long-Running Agent)',
    provider: 'Anthropic',
    context_window: 1000000,
    supports_live: false,
    supports_thinking: true,
    thinking_budget_max: 64000,
    cost_per_m_input: 4.00,
    cost_per_m_output: 20.00,
    status: 'active',
    verified_date: '2026-10-30'
  },
  // xAI (Grok - bonded with Cursor)
  {
    id: 'grok-4.5',
    name: 'Grok 4.5 Full Reasoning',
    provider: 'xAI',
    context_window: 128000,
    supports_live: false,
    supports_thinking: true,
    thinking_budget_max: 32768,
    cost_per_m_input: 0.50,
    cost_per_m_output: 2.00,
    status: 'active',
    verified_date: '2026-10-30'
  },
  {
    id: 'grok-3',
    name: 'Grok 3 Frontier',
    provider: 'xAI',
    context_window: 128000,
    supports_live: false,
    supports_thinking: false,
    cost_per_m_input: 0.50,
    cost_per_m_output: 2.00,
    status: 'active',
    verified_date: '2026-10-30'
  },
  // Cursor
  {
    id: 'cursor-fast',
    name: 'Cursor Composer (Fast Edit)',
    provider: 'Cursor',
    context_window: 128000,
    supports_live: false,
    supports_thinking: false,
    cost_per_m_input: 0.00,
    cost_per_m_output: 0.00,
    status: 'active',
    verified_date: '2026-10-30'
  },
  {
    id: 'cursor-agent',
    name: 'Cursor Autonomous Agent',
    provider: 'Cursor',
    context_window: 128000,
    supports_live: false,
    supports_thinking: true,
    thinking_budget_max: 32768,
    cost_per_m_input: 0.00,
    cost_per_m_output: 0.00,
    status: 'active',
    verified_date: '2026-10-30'
  }
];


/** Constant-time check of `Authorization: Bearer <secret>` (hashing first equalises lengths). */
async function bearerMatches(request: Request, secret: string): Promise<boolean> {
  const header = request.headers.get('Authorization') ?? '';
  const given = header.startsWith('Bearer ') ? header.slice(7).trim() : '';
  const encoder = new TextEncoder();
  const [a, b] = await Promise.all([
    crypto.subtle.digest('SHA-256', encoder.encode(given)),
    crypto.subtle.digest('SHA-256', encoder.encode(secret)),
  ]);
  return given.length > 0 && crypto.subtle.timingSafeEqual(a, b);
}

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);

    // 1. 安全標頭。只反射允許的 App / 開發 origin，不使用 *。
    const securityHeaders = {
      ...allowlistedHeaders(request.headers.get('Origin')),
      'X-Request-Id': crypto.randomUUID(),
    };

    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: securityHeaders });
    }

    if (url.pathname === '/api/antigravity/refresh' && ['GET', 'POST'].includes(request.method)) {
      const js = (body: object, status = 200) => new Response(JSON.stringify(body), {
        status,
        headers: { ...securityHeaders, 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
      });
      if (!env.ANTIGRAVITY_REFRESH_TOKEN || !env.SYNC_TOKEN || !env.DB) {
        return js({ error: 'Refresh unavailable' }, 503);
      }
      const phone = request.method === 'POST';
      const secret = phone ? env.ANTIGRAVITY_REFRESH_TOKEN : env.SYNC_TOKEN;
      if (!(await bearerMatches(request, secret))) return js({ error: 'Unauthorized' }, 401);

      try {
        if (phone) {
          const now = new Date();
          const cutoff = new Date(now.getTime() - 60_000).toISOString();
          await env.DB.prepare(`
            INSERT INTO antigravity_refresh (singleton, requested_at) VALUES (1, ?)
            ON CONFLICT(singleton) DO UPDATE SET requested_at = excluded.requested_at
            WHERE antigravity_refresh.requested_at <= ?
          `).bind(now.toISOString(), cutoff).run();
        }
        const row = await env.DB.prepare(
          'SELECT requested_at FROM antigravity_refresh WHERE singleton = 1'
        ).first<{ requested_at: string }>();
        return js({ requested_at: row?.requested_at ?? null }, phone ? 202 : 200);
      } catch {
        return js({ error: 'Refresh unavailable' }, 503);
      }
    }

    // 3. API 路由: 取得各 AI 平台額度清單 (GET /api/quotas)
    if (url.pathname === '/api/quotas' && request.method === 'GET') {
      try {
        let quotas: ProviderQuotaRecord[] = [];
        if (env.DB) {
          try {
            const res = await env.DB.prepare('SELECT * FROM provider_quotas').all<ProviderQuotaRecord>();
            if (res.results && res.results.length > 0) {
              quotas = res.results;
            }
          } catch {
            // D1 連線或欄位異常時優雅降級
          }
        }

        // No built-in sample rows: an empty table returns an empty list, and the app says 「尚無額度資料」.

        const bodyStr = JSON.stringify({ success: true, data: quotas });
        
        // ETag 支援與 304 快取加速
        const etag = `"${Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(bodyStr)))).slice(0, 8).map(b => b.toString(16).padStart(2, '0')).join('')}"`;
        if (request.headers.get('If-None-Match') === etag) {
          return new Response(null, { status: 304, headers: { ...securityHeaders, ETag: etag } });
        }

        return new Response(bodyStr, {
          headers: {
            ...securityHeaders,
            'Content-Type': 'application/json',
            'ETag': etag,
            'Cache-Control': 'public, max-age=5'
          }
        });
      } catch (err: any) {
        return new Response(JSON.stringify({ success: false, error: err.message }), {
          status: 500,
          headers: { ...securityHeaders, 'Content-Type': 'application/json' }
        });
      }
    }

    // 4. API 路由: 本機同步推播端點 (POST /api/quotas/sync)
    if (url.pathname === '/api/quotas/sync' && request.method === 'POST') {
      // The phone shows whatever is stored here, so writes need the secret once it is set.
      if (env.SYNC_TOKEN && !(await bearerMatches(request, env.SYNC_TOKEN))) {
        return new Response(JSON.stringify({ success: false, error: 'Unauthorized' }), {
          status: 401,
          headers: { ...securityHeaders, 'Content-Type': 'application/json' }
        });
      }
      try {
        const payload = await request.json() as { quotas?: ProviderQuotaRecord[] };
        const items = payload.quotas || [];
        if (!Array.isArray(items) || items.length === 0) {
          return new Response(JSON.stringify({ success: false, error: 'Empty quotas payload' }), {
            status: 400,
            headers: { ...securityHeaders, 'Content-Type': 'application/json' }
          });
        }

        if (env.DB) {
          for (const item of items) {
            await env.DB.prepare(`
              INSERT OR REPLACE INTO provider_quotas (
                provider_id, name, plan_name, total_quota, used_quota, remaining_percent, reset_time, status, metrics_json, token_pools_json, fetched_at, updated_at
              ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
            `).bind(
              item.provider_id,
              item.name,
              item.plan_name,
              item.total_quota,
              item.used_quota,
              item.remaining_percent,
              item.reset_time,
              item.status || 'active',
              item.metrics_json || null,
              item.token_pools_json || null,
              item.fetched_at || new Date().toISOString()
            ).run();
          }
        }

        return new Response(JSON.stringify({ success: true, count: items.length }), {
          headers: { ...securityHeaders, 'Content-Type': 'application/json' }
        });
      } catch (err: any) {
        return new Response(JSON.stringify({ success: false, error: err.message }), {
          status: 500,
          headers: { ...securityHeaders, 'Content-Type': 'application/json' }
        });
      }
    }

    // 5. API 路由: 即時動態同步模型型錄 (POST /api/models/sync)
    if (url.pathname === '/api/models/sync' && request.method === 'POST') {
      try {
        const force = url.searchParams.get('force') === 'true';
        let models: ModelCatalogItem[] = [];

        if (env.KV_CATALOG && !force) {
          const cached = await env.KV_CATALOG.get('catalog:latest', 'json');
          if (cached && Array.isArray(cached) && cached.length >= 10) {
            models = purgeDeprecatedModels(cached as ModelCatalogItem[]);
          }
        }

        if (!models.length) {
          models = purgeDeprecatedModels(ACTIVE_FRONTIER_MODELS);
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

    // 6. 靜態資源前端託管 (Cloudflare Workers Static Assets)
    if (env.ASSETS) {
      return env.ASSETS.fetch(request);
    }

    return new Response('OpenTokenUsage Edge Worker Active', {
      headers: { ...securityHeaders, 'Content-Type': 'text/plain; charset=utf-8' }
    });
  }
};
