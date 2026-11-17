export interface Env {
  ASSETS: Fetcher;
  DB: D1Database;
  KV_CATALOG: KVNamespace;
  ENCRYPTION_MASTER_KEY?: string;
}

export interface MetricItem {
  label: string;
  used?: number;
  limit?: number;
  kind?: 'percent' | 'count';
  value?: string;
  isAlert?: boolean;
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
  token_pools_json?: string;
  metrics_json?: string;
  fetched_at?: string;
  updated_at?: string;
}

export interface ModelCatalogItem {
  id: string;
  name: string;
  provider: 'Cursor' | 'OpenAI' | 'Google' | 'Anthropic' | 'xAI';
  context_window: number;
  supports_live: boolean;
  supports_thinking: boolean;
  thinking_budget_max?: number;
  cost_per_m_input: number;
  cost_per_m_output: number;
  status: 'active';
  verified_date: string;
}
