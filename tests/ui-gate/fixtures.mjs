// Deterministic /api/quotas bodies for the Web UI Acceptance Gate pages and flows.
// All times are relative to the gate clock (".ui-gate.json" → clock), so screenshots are stable.

const BASE = '2026-11-27T09:00:00+08:00';

function at(clockISO, hoursFromNow) {
  return new Date(new Date(clockISO || BASE).getTime() + hoursFromNow * 3_600_000).toISOString();
}

export function quotaRows(clockISO = BASE) {
  const tier = (id, label, used, h, governing) => ({
    id, label, used, limit: 100, remaining: 100 - used, resetsAt: at(clockISO, h), resetDurationText: '', isGoverning: governing,
  });
  const row = (id, name, plan, remaining, metrics, pools) => ({
    provider_id: id, name, plan_name: plan, total_quota: 100, used_quota: 100 - remaining, remaining_percent: remaining,
    reset_time: at(clockISO, 48), status: 'active', metrics_json: JSON.stringify(metrics),
    token_pools_json: pools ? JSON.stringify(pools) : null, fetched_at: at(clockISO, -0.1),
  });
  return [
    row('codex', 'Codex', 'Plus', 3, [{ label: 'Resets', value: '1 available' }], [
      { id: 'codex_shared', name: 'Codex CLI & Cloud', effectiveRemaining: 3, effectiveUsed: 97, primaryResetTime: at(clockISO, 20), isCritical: true,
        tiers: [tier('weekly', 'Weekly limit', 97, 20, true), tier('5h', '5h Session', 40, 3, false)] },
    ]),
    row('claude', 'Claude Code', 'Pro', 58, [{ label: 'Resets', value: '0 available' }]),
    row('cursor', 'Cursor', 'Pro', 41, [{ label: 'Total usage', used: 59, limit: 100, kind: 'percent' }]),
    row('antigravity', 'Google Antigravity', 'Google AI Pro', 77, []),
  ];
}

export function quotas(clockISO) {
  return { success: true, data: quotaRows(clockISO) };
}

export function empty() {
  return { success: true, data: [] };
}

/** Flow helper: serve the fixture on /api/quotas. */
export async function serveQuotas(page, body = quotas(new Date().toISOString())) {
  await page.route('**/api/quotas', (route) =>
    route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(body) }),
  );
}
