-- Cloudflare D1 Initial Migration
-- ai_usage_ledger & provider_quotas

CREATE TABLE IF NOT EXISTS ai_usage_ledger (
    id TEXT PRIMARY KEY,
    provider TEXT NOT NULL,
    model_id TEXT NOT NULL,
    prompt_tokens INTEGER NOT NULL,
    completion_tokens INTEGER NOT NULL,
    thinking_tokens INTEGER DEFAULT 0,
    total_tokens INTEGER NOT NULL,
    cost_usd REAL NOT NULL,
    session_id TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS provider_quotas (
    provider_id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    plan_name TEXT,
    total_quota REAL,
    used_quota REAL,
    remaining_percent REAL,
    reset_time TEXT,
    status TEXT,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_ledger_provider ON ai_usage_ledger(provider);
CREATE INDEX IF NOT EXISTS idx_ledger_created ON ai_usage_ledger(created_at);

-- 預設插入目前支援之模型與平台種子資料
INSERT OR REPLACE INTO provider_quotas (provider_id, name, plan_name, total_quota, used_quota, remaining_percent, reset_time, status)
VALUES 
    ('cursor', 'Cursor', 'Pro / Business', 500, 0, 100, '每月重置', 'active'),
    ('grok', 'Grok', 'SuperGrok', 100, 0, 100, '每週重置', 'active'),
    ('antigravity', 'Antigravity (Gemini)', 'Google AI Pro', 100, 34, 66, '今天 2:29 重置', 'active'),
    ('claude', 'Claude Code', 'Team Pro', 100, 28, 72, '今天 5:06 重置', 'active');
