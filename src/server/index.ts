import http from 'node:http';
import { WebSocketServer, WebSocket } from 'ws';
import { defaultLedger } from './ledger/usage-ledger';
import { discoverLatestModels, validateUpstreamUrl } from './catalog/discovery';
import { OPENTOKENUSAGE_MCP_TOOLS, handleMcpToolCall } from './mcp/quota-mcp-server';

const PORT = process.env.PORT || 8787;

const server = http.createServer(async (req, res) => {
  // 設置 CORS 與安全標頭
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'DENY');

  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    res.end();
    return;
  }

  const url = new URL(req.url || '/', `http://${req.headers.host}`);

  if (url.pathname === '/api/quotas' && req.method === 'GET') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(
      JSON.stringify({
        success: true,
        data: [
          {
            provider_id: 'cursor',
            name: 'Cursor',
            plan_name: 'Pro / Business',
            total_quota: 500,
            used_quota: 0,
            remaining_percent: 100,
            reset_time: '每月重置',
            status: 'active',
          },
          {
            provider_id: 'grok',
            name: 'Grok',
            plan_name: 'SuperGrok',
            total_quota: 100,
            used_quota: 0,
            remaining_percent: 100,
            reset_time: '每週重置',
            status: 'active',
          },
          {
            provider_id: 'antigravity',
            name: 'Antigravity (Gemini)',
            plan_name: 'Google AI Pro',
            total_quota: 100,
            used_quota: 34,
            remaining_percent: 66,
            reset_time: '今天 2:29 重置',
            status: 'active',
          },
          {
            provider_id: 'claude',
            name: 'Claude Code',
            plan_name: 'Team Pro',
            total_quota: 100,
            used_quota: 28,
            remaining_percent: 72,
            reset_time: '今天 5:06 重置',
            status: 'active',
          },
        ],
      })
    );
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
  res.end('OpenTokenUsage Node Fallback Server Running');
});

const wss = new WebSocketServer({ server, path: '/ws/live' });

wss.on('connection', (ws, req) => {
  // CSWSH 防護
  const origin = req.headers.origin;
  const host = req.headers.host;
  if (origin && host && !origin.includes(host.split(':')[0]) && !origin.includes('localhost')) {
    ws.close(1008, 'CSWSH Origin Check Failed');
    return;
  }

  ws.send(
    JSON.stringify({
      type: 'ready',
      message: 'Gemini 3.8 Live API 代理連線已建立 (Node.js 備用伺服器模式)',
    })
  );

  ws.on('message', async (data) => {
    try {
      const msg = JSON.parse(data.toString());
      if (msg.type === 'call_tool') {
        const result = await handleMcpToolCall(msg.tool, msg.args || {}, {});
        ws.send(JSON.stringify({ type: 'tool_result', result }));
      }
    } catch {}
  });
});

server.listen(PORT, () => {
  console.log(`[OpenTokenUsage Web] Server running at http://localhost:${PORT}`);
});
