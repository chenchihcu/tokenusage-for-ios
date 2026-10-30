-- Cloudflare D1 Migration 0002: Rich Account Metrics & Verified SSOT Data
-- Adds metrics_json and fetched_at to provider_quotas, updates 5 designated platforms with real accounts data

ALTER TABLE provider_quotas ADD COLUMN metrics_json TEXT;
ALTER TABLE provider_quotas ADD COLUMN fetched_at TEXT;

-- 更新 5 大專屬平台為用戶本機 usage-api-cache.json 100% 真實數據
INSERT OR REPLACE INTO provider_quotas (
    provider_id, 
    name, 
    plan_name, 
    total_quota, 
    used_quota, 
    remaining_percent, 
    reset_time, 
    status, 
    metrics_json, 
    fetched_at,
    updated_at
) VALUES 
(
    'cursor',
    'Cursor',
    'Premium',
    100,
    100,
    0,
    '2026-11-03T12:12:52.768Z',
    'active',
    '[{"label":"Total usage","used":100.0,"limit":100.0,"kind":"percent","isAlert":true},{"label":"Auto usage","used":100.0,"limit":100.0,"kind":"percent"},{"label":"Grok Bot","used":100.0,"limit":100.0,"kind":"percent"},{"label":"API usage","used":0.0,"limit":100.0,"kind":"percent"}]',
    '2026-10-30T17:55:18.457747Z',
    CURRENT_TIMESTAMP
),
(
    'codex',
    'Codex',
    'Plus',
    100,
    0,
    100,
    '2026-11-04T06:48:16.000Z',
    'active',
    '[{"label":"Session","used":0.0,"limit":100.0,"kind":"percent"},{"label":"Weekly (Shared)","used":100.0,"limit":100.0,"kind":"percent","isAlert":true},{"label":"Resets","value":"0 available"},{"label":"Credits","value":"$0.00"}]',
    '2026-10-30T22:57:15.1249828Z',
    CURRENT_TIMESTAMP
),
(
    'antigravity',
    'Google Antigravity',
    'Google AI Pro',
    100,
    8,
    92,
    '2026-10-30T23:29:29Z',
    'active',
    '[{"label":"Session","used":8.0,"limit":100.0,"kind":"percent"},{"label":"Claude Sub-Session","used":0.0,"limit":100.0,"kind":"percent"},{"label":"Claude Weekly","used":54.0,"limit":100.0,"kind":"percent"}]',
    '2026-10-30T22:57:18.6093812Z',
    CURRENT_TIMESTAMP
),
(
    'claude',
    'Claude Code',
    'Pro',
    100,
    0,
    100,
    '2026-11-02T12:59:59.805Z',
    'active',
    '[{"label":"Session","used":0.0,"limit":100.0,"kind":"percent"},{"label":"Weekly (Shared)","used":98.0,"limit":100.0,"kind":"percent","isAlert":true},{"label":"Resets","value":"0 available"}]',
    '2026-10-30T19:12:17.6328982Z',
    CURRENT_TIMESTAMP
),
(
    'grok',
    'Grok (bonded with Cursor)',
    'SuperGrok',
    100,
    100,
    0,
    '2026-11-03T12:12:52.768Z',
    'active',
    '[{"label":"Weekly limit","used":100.0,"limit":100.0,"kind":"percent","isAlert":true},{"label":"Pay as you go","value":"Disabled"},{"label":"Bonded Sync","value":"Cursor Linked"}]',
    '2026-10-30T22:57:15.3476213Z',
    CURRENT_TIMESTAMP
);
