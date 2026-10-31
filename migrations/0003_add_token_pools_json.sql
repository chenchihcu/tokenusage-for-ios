-- Cloudflare D1 Migration 0003: Multi-Token Pools Schema Evolution
-- Adds token_pools_json column to provider_quotas and sets high-fidelity multi-pool baseline for Google Antigravity

ALTER TABLE provider_quotas ADD COLUMN token_pools_json TEXT;

-- 更新 Google Antigravity 3 大真實配額池數據 (對齊用戶實機截圖)
UPDATE provider_quotas 
SET 
    token_pools_json = json_array(
        json_object(
            'id', 'gemini_models',
            'name', 'Gemini Models',
            'effectiveRemaining', 31.0,
            'effectiveUsed', 69.0,
            'primaryResetTime', '2026-11-02T16:54:00Z',
            'isCritical', false,
            'tiers', json_array(
                json_object('id', 'weekly', 'label', 'Weekly limit', 'used', 69.0, 'limit', 100.0, 'remaining', 31.0, 'resetsAt', '2026-11-02T16:54:00Z', 'resetDurationText', '2d 9h', 'isGoverning', true),
                json_object('id', '5h', 'label', '5h limit', 'used', 5.0, 'limit', 100.0, 'remaining', 95.0, 'resetsAt', '2026-10-31T12:31:00Z', 'resetDurationText', '4h 37m', 'isGoverning', false)
            )
        ),
        json_object(
            'id', 'claude_gpt',
            'name', 'Claude and GPT models',
            'effectiveRemaining', 46.0,
            'effectiveUsed', 54.0,
            'primaryResetTime', '2026-11-02T16:54:00Z',
            'isCritical', false,
            'tiers', json_array(
                json_object('id', 'weekly', 'label', 'Weekly limit', 'used', 54.0, 'limit', 100.0, 'remaining', 46.0, 'resetsAt', '2026-11-02T16:54:00Z', 'resetDurationText', '2d 9h', 'isGoverning', true),
                json_object('id', '5h', 'label', '5h limit', 'used', 0.0, 'limit', 100.0, 'remaining', 100.0, 'resetsAt', null, 'resetDurationText', '100% left', 'isGoverning', false)
            )
        ),
        json_object(
            'id', 'gemini_4_argon',
            'name', 'Gemini 4 Argon',
            'effectiveRemaining', 0.0,
            'effectiveUsed', 100.0,
            'primaryResetTime', '2026-11-02T15:54:00Z',
            'isCritical', true,
            'tiers', json_array(
                json_object('id', 'weekly', 'label', 'Weekly limit', 'used', 100.0, 'limit', 100.0, 'remaining', 0.0, 'resetsAt', '2026-11-02T15:54:00Z', 'resetDurationText', '2d 8h', 'isGoverning', true)
            )
        )
    ),
    used_quota = 100.0,
    remaining_percent = 0.0,
    reset_time = '2026-11-02T15:54:00Z',
    status = 'active',
    updated_at = CURRENT_TIMESTAMP
WHERE provider_id = 'antigravity';
