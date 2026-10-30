export interface Env {
  ASSETS: Fetcher;
  DB: D1Database;
  KV_CATALOG: KVNamespace;
  VOICE_SESSION: DurableObjectNamespace;
  GEMINI_API_KEY?: string;
  ENCRYPTION_MASTER_KEY?: string;
}

export interface ProviderQuotaRecord {
  provider_id: string;
  name: string;
  plan_name: string;
  total_quota: number;
  used_quota: number;
  remaining_percent: number;
  reset_time: string;
  status: string;
  updated_at?: string;
}

export interface ModelCatalogItem {
  id: string;
  name: string;
  provider: string;
  context_window: number;
  supports_live: boolean;
  supports_thinking: boolean;
  thinking_budget_max?: number;
  cost_per_m_input: number;
  cost_per_m_output: number;
}
