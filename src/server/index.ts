import http from 'node:http';
import { securityHeaders } from '../shared/cors';
import { defaultLedger } from './ledger/usage-ledger';
import { discoverLatestModels, validateUpstreamUrl } from './catalog/discovery';
import { OPENTOKENUSAGE_MCP_TOOLS, handleMcpToolCall } from './mcp/quota-mcp-server';

const PORT = process.env.PORT || 8787;

let memoryQuotas = [
  {
    provider_id: 'cursor',
    name: 'Cursor',
    plan_name: 'Premium',
    total_quota: 100,
    used_quota: 100,
    remaining_percent: 0,
    reset_time: '2026-11-03T12:12:52.768Z',
    status: 'active',
    metrics_json: JSON.stringify([
      { label: 'Total usage', used: 100.0, limit: 100.0, kind: 'percent', isAlert: true },
      { label: 'Auto usage', used: 100.0, limit: 100.0, kind: 'percent' },
      { label: 'Grok Bot', used: 100.0, limit: 100.0, kind: 'percent' },
      { label: 'API usage', used: 0.0, limit: 100.0, kind: 'percent' }
    ]),
    fetched_at: '2026-10-30T17:55:18.457747Z'
  },
  {
    provider_id: 'codex',
    name: 'Codex',
    plan_name: 'Plus',
    total_quota: 100,
    used_quota: 0,
    remaining_percent: 100,
    reset_time: '2026-11-04T06:48:16.000Z',
    status: 'active',
    metrics_json: JSON.stringify([
      { label: 'Session', used: 0.0, limit: 100.0, kind: 'percent' },
      { label: 'Weekly (Shared)', used: 100.0, limit: 100.0, kind: 'percent', isAlert: true },
      { label: 'Resets', value: '0 available' },
      { label: 'Credits', value: '$0.00' }
    ]),
    fetched_at: '2026-10-30T22:57:15.1249828Z'
  },
  {
    provider_id: 'antigravity',
    name: 'Google Antigravity',
    plan_name: 'Google AI Pro',
    total_quota: 100,
    used_quota: 8,
    remaining_percent: 92,
    reset_time: '2026-10-30T23:29:29Z',
    status: 'active',
    metrics_json: JSON.stringify([
      { label: 'Session', used: 8.0, limit: 100.0, kind: 'percent' },
      { label: 'Claude Sub-Session', used: 0.0, limit: 100.0, kind: 'percent' },
      { label: 'Claude Weekly', used: 54.0, limit: 100.0, kind: 'percent' }
    ]),
    fetched_at: '2026-10-30T22:57:18.6093812Z'
  },
  {
    provider_id: 'claude',
    name: 'Claude Code',
    plan_name: 'Pro',
    total_quota: 100,
    used_quota: 0,
    remaining_percent: 100,
    reset_time: '2026-11-02T12:59:59.805Z',
    status: 'active',
    metrics_json: JSON.stringify([
      { label: 'Session', used: 0.0, limit: 100.0, kind: 'percent' },
      { label: 'Weekly (Shared)', used: 98.0, limit: 100.0, kind: 'percent', isAlert: true },
      { label: 'Resets', value: '0 available' }
    ]),
    fetched_at: '2026-10-30T19:12:17.6328982Z'
  },
  {
    provider_id: 'grok',
    name: 'Grok (bonded with Cursor)',
    plan_name: 'SuperGrok',
    total_quota: 100,
    used_quota: 100,
    remaining_percent: 0,
    reset_time: '2026-11-03T12:12:52.768Z',
    status: 'active',
    metrics_json: JSON.stringify([
      { label: 'Weekly limit', used: 100.0, limit: 100.0, kind: 'percent', isAlert: true },
      { label: 'Pay as you go', value: 'Disabled' },
      { label: 'Bonded Sync', value: 'Cursor Linked' }
    ]),
    fetched_at: '2026-10-30T22:57:15.3476213Z'
  }
];

const server = http.createServer(async (req, res) => {
  const headers = securityHeaders(typeof req.headers.origin === 'string' ? req.headers.origin : null);
  headers['X-Request-Id'] = crypto.randomUUID();
  for (const [key, value] of Object.entries(headers)) {
    res.setHeader(key, value);
  }

  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    res.end();
    return;
  }

  const url = new URL(req.url || '/', `http://${req.headers.host}`);

  if (url.pathname === '/api/quotas' && req.method === 'GET') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ success: true, data: memoryQuotas }));
    return;
  }

  if (url.pathname === '/api/quotas/sync' && req.method === 'POST') {
    let body = '';
    req.on('data', chunk => { body += chunk; });
    req.on('end', () => {
      try {
        const payload = JSON.parse(body);
        if (Array.isArray(payload.quotas)) {
          memoryQuotas = payload.quotas;
        }
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ success: true, count: memoryQuotas.length }));
      } catch (err: any) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ success: false, error: err.message }));
      }
    });
    return;
  }

  if (url.pathname === '/api/models/sync' && req.method === 'POST') {
    const models = await discoverLatestModels();
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ success: true, count: models.length, models }));
    return;
  }

  if (url.pathname === '/api/mcp/tools' && req.method === 'GET') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ tools: OPENTOKENUSAGE_MCP_TOOLS }));
    return;
  }

  res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' });
  res.end('OpenTokenUsage Local Server Active');
});

if (process.env.NODE_ENV !== 'test') {
  server.listen(PORT, () => {
    console.log(`Server running on http://localhost:${PORT}`);
  });
}

export { server };
