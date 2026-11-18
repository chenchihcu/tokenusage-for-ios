import { test, expect } from '@playwright/test';
import { ALLOWED_ORIGINS, joinApi, resolveApiOrigin, securityHeaders, websocketUrl } from '../src/shared/cors';
import { ApiClient } from '../src/client/network/apiClient';
import { decideColumns, LIST_MIN_PX } from '../src/client/network/layout';
import { ATTACHMENT_CONFIRM_BYTES, ProbeGate, jitterMs, needsSizeConfirm, parseRetryAfter, planRetry } from '../src/client/network/policy';
import { presentStatus, toDiagnostic } from '../src/client/network/presentStatus';
import { QuotaRepository } from '../src/client/network/repository';
import { reduceNet } from '../src/client/network/reducer';
import { initialNetState, type NetState } from '../src/client/network/types';

function memoryKv() {
  const store = new Map<string, string>();
  return {
    store,
    getItem: async (key: string) => store.get(key) ?? null,
    setItem: async (key: string, value: string) => {
      store.set(key, value);
    },
    removeItem: async (key: string) => {
      store.delete(key);
    },
  };
}

test('public origin is HTTPS and the installed app does not use a relative or tailnet URL', () => {
  expect(resolveApiOrigin({ native: false })).toBe('');
  expect(resolveApiOrigin({ native: true })).toBe('https://opentokenusage-web.chihfu-chen-tw.workers.dev');
  expect(resolveApiOrigin({ native: true })).not.toMatch(/tailscale|ts\.net/i);
  expect(joinApi(resolveApiOrigin({ native: true }), '/api/quotas')).toBe(
    'https://opentokenusage-web.chihfu-chen-tw.workers.dev/api/quotas',
  );
  expect(websocketUrl('https://opentokenusage-web.chihfu-chen-tw.workers.dev', { protocol: 'https:', host: 'localhost' }, '/ws/live')).toBe(
    'wss://opentokenusage-web.chihfu-chen-tw.workers.dev/ws/live',
  );
});

test('CORS reflects only known origins and never a wildcard', () => {
  const allowed = securityHeaders('https://localhost');
  expect(allowed['Access-Control-Allow-Origin']).toBe('https://localhost');
  expect(allowed['Access-Control-Expose-Headers']).toContain('ETag');
  expect(allowed['Access-Control-Expose-Headers']).toContain('Retry-After');
  expect(securityHeaders('https://evil.example')['Access-Control-Allow-Origin']).toBeUndefined();
  expect(JSON.stringify(securityHeaders('https://localhost'))).not.toContain('*');
  // The Capacitor shell was removed; its WebView origin is no longer allowed.
  expect(ALLOWED_ORIGINS).not.toContain('capacitor://localhost');
});

test('stale network snapshots are dropped and a lost path clears a verified API', () => {
  let state = reduceNet(initialNetState(), {
    type: 'snapshot',
    generation: 2,
    connected: true,
    connectionType: 'cellular',
    at: 10,
  });
  state = reduceNet(state, {
    type: 'result',
    generation: 2,
    at: 20,
    httpStatus: 200,
    errorKind: 'none',
    appliedData: true,
  });
  expect(state.api).toBe('reachable');
  expect(state.path).toBe('cellular');
  expect(state.costHint).toBe('unknown');
  expect(state.constrainedHint).toBe('unknown');

  const stale = reduceNet(state, {
    type: 'snapshot',
    generation: 1,
    connected: false,
    connectionType: 'none',
    at: 30,
  });
  expect(stale).toBe(state);

  const offline = reduceNet(state, {
    type: 'snapshot',
    generation: 3,
    connected: false,
    connectionType: 'wifi',
    at: 40,
  });
  expect(offline.path).toBe('none');
  expect(offline.api).toBe('unknown');
  expect(offline.autoRetrySuspended).toBe(true);
  expect(offline.costHint).toBe('unknown');
});

test('HTTP failures stay reachable and are not treated as the phone being offline', () => {
  const base = reduceNet(initialNetState(), {
    type: 'snapshot',
    generation: 1,
    connected: true,
    connectionType: 'wifi',
    at: 1,
  });
  const server = reduceNet(base, {
    type: 'result',
    generation: 1,
    at: 2,
    httpStatus: 503,
    errorKind: 'http_server',
  });
  expect(server.api).toBe('reachable');
  expect(server.path).not.toBe('none');
  expect(presentStatus(server, null).live).toBe('服務忙碌，請稍後再試');

  const denied = reduceNet(base, {
    type: 'result',
    generation: 1,
    at: 3,
    httpStatus: 401,
    errorKind: 'http_auth',
  });
  expect(denied.auth).toBe('expired');
  expect(denied.api).toBe('reachable');
  expect(presentStatus(denied, null).live).toBe('登入已失效');

  const transport = reduceNet(base, {
    type: 'result',
    generation: 1,
    at: 4,
    httpStatus: null,
    errorKind: 'transport',
  });
  expect(transport.api).toBe('unreachable');
  expect(presentStatus(transport, null).live).toBe('無法連接服務，請稍後重試');
  expect(presentStatus(transport, null).live).not.toMatch(/SIM|5G|憑證/);
});

test('status copy does not drive the reducer and unknown cost is not false', () => {
  const checking = reduceNet(initialNetState(), {
    type: 'checking',
    generation: 0,
    reason: 'initial',
    at: 1,
  });
  expect(presentStatus(checking, null).live).toBe('正在確認連線…');
  const pending = reduceNet(checking, { type: 'write', outcome: 'unknown' });
  expect(pending.writeState).toBe('pending');
  expect(presentStatus(pending, null).live).toBe('已送出，正在確認結果');
  const offline = reduceNet(initialNetState(), {
    type: 'snapshot',
    generation: 1,
    connected: false,
    connectionType: 'none',
    at: 2,
  });
  expect(presentStatus(offline, '11/5 23:00').live).toContain('目前無法連線');
  expect(presentStatus(offline, null).checkHint).toContain('設定');
  const diagnostic = toDiagnostic({
    requestId: 'req-1',
    errorKind: 'transport',
    durationMs: 12,
    attempts: 1,
    path: 'cellular',
    httpStatus: null,
    authorization: 'Bearer secret',
    body: 'token=abc',
    url: 'https://example.test/?key=secret',
  });
  expect(diagnostic).not.toHaveProperty('authorization');
  expect(JSON.stringify(diagnostic)).not.toMatch(/Bearer|token|secret/);
});

test('jitter, Retry-After, and safe-read limits', () => {
  expect(jitterMs(1, () => 0)).toBe(0);
  expect(jitterMs(1, () => 0.999)).toBeLessThanOrEqual(1000);
  expect(jitterMs(2, () => 0.999)).toBeGreaterThan(1000);
  expect(jitterMs(2, () => 0.999)).toBeLessThanOrEqual(2000);
  expect(parseRetryAfter('2', 0)).toBe(2000);
  const later = Date.parse('Wed, 21 Oct 2026 07:28:00 GMT');
  expect(parseRetryAfter('Wed, 21 Oct 2026 07:28:00 GMT', later - 1500)).toBe(1500);
  expect(parseRetryAfter('not-a-date', 0)).toBeNull();

  expect(
    planRetry({
      method: 'GET',
      errorKind: 'http_server',
      httpStatus: 503,
      completedAttempts: 1,
      remainingBudgetMs: 1000,
      retryAfterMs: 5000,
      random: () => 0,
      cancelled: false,
      foreground: true,
    }),
  ).toEqual({ stop: 'budget' });

  expect(
    planRetry({
      method: 'POST',
      errorKind: 'transport',
      httpStatus: null,
      completedAttempts: 1,
      remainingBudgetMs: 10_000,
      retryAfterMs: null,
      random: () => 0,
      cancelled: false,
      foreground: true,
    }),
  ).toEqual({ stop: 'method' });

  expect(
    planRetry({
      method: 'GET',
      errorKind: 'http_auth',
      httpStatus: 401,
      completedAttempts: 1,
      remainingBudgetMs: 10_000,
      retryAfterMs: null,
      random: () => 0,
      cancelled: false,
      foreground: true,
    }),
  ).toEqual({ stop: 'confirmed' });

  expect(
    planRetry({
      method: 'GET',
      errorKind: 'cancelled',
      httpStatus: null,
      completedAttempts: 1,
      remainingBudgetMs: 10_000,
      retryAfterMs: null,
      random: () => 0,
      cancelled: true,
      foreground: true,
    }),
  ).toEqual({ stop: 'cancelled' });

  expect(needsSizeConfirm(null)).toBe(true);
  expect(needsSizeConfirm(ATTACHMENT_CONFIRM_BYTES - 1)).toBe(false);
  expect(needsSizeConfirm(ATTACHMENT_CONFIRM_BYTES)).toBe(true);
  expect(LIST_MIN_PX).toBeGreaterThan(0);
});

test('columns follow the container and large text falls back to one column', () => {
  expect(decideColumns(390, 1)).toBe('single');
  expect(decideColumns(852, 1)).toBe('dual');
  expect(decideColumns(852, 1.6)).toBe('single');
  expect(decideColumns(0, 1)).toBe('single');
});

test('probe gate allows one restore and lets an explicit retry skip the cooldown', () => {
  const gate = new ProbeGate(30_000);
  expect(gate.tryEnter(1_000, false)).toBe(true);
  expect(gate.tryEnter(1_100, true)).toBe(false);
  gate.leave();
  expect(gate.tryEnter(2_000, false)).toBe(false);
  expect(gate.tryEnter(2_000, true)).toBe(true);
});

test('client retries a safe read twice, waits for Retry-After, and does not resend POST', async () => {
  const calls: string[] = [];
  let now = 0;
  const sleeps: number[] = [];
  const client = new ApiClient({
    now: () => now,
    sleep: async (ms) => {
      sleeps.push(ms);
      now += ms;
    },
    random: () => 0,
    perRequestMs: 1000,
    budgetMs: 40_000,
    fetchImpl: async (input, init) => {
      const url = String(input);
      calls.push(`${init?.method ?? 'GET'} ${url}`);
      if (url.endsWith('/retry')) {
        if (calls.filter((item) => item.includes('/retry')).length < 3) {
          return new Response('{"success":false}', {
            status: 503,
            headers: { 'content-type': 'application/json', 'retry-after': '1', 'x-request-id': 'r1' },
          });
        }
        return new Response('{"ok":true}', {
          status: 200,
          headers: { 'content-type': 'application/json', 'x-request-id': 'r2' },
        });
      }
      return new Response('no', { status: 503, headers: { 'content-type': 'application/json' } });
    },
  });

  const retried = await client.request({
    url: 'https://example.test/retry',
    method: 'GET',
    foreground: () => true,
    parse: () => ({ data: null, errorKind: 'http_server' }),
  });
  expect(calls.filter((item) => item.startsWith('GET'))).toHaveLength(3);
  expect(sleeps).toEqual([1000, 1000]);
  expect(retried.attempts).toBe(3);
  expect(retried.stopped).toBe('confirmed');

  const posted = await client.request({
    url: 'https://example.test/write',
    method: 'POST',
    body: '{}',
    foreground: () => true,
    parse: () => ({ data: null, errorKind: 'http_server' }),
  });
  expect(calls.filter((item) => item.startsWith('POST'))).toHaveLength(1);
  expect(posted.stopped).toBe('method');
});

test('timeout, schema, and cancellation stop without another attempt', async () => {
  let release: (reason?: unknown) => void = () => {};
  const hanging = new ApiClient({
    perRequestMs: 20,
    budgetMs: 100,
    random: () => 0,
    sleep: async () => {},
    fetchImpl: (_input, init) =>
      new Promise((_resolve, reject) => {
        release = reject;
        init?.signal?.addEventListener('abort', () => {
          reject(new DOMException('Aborted', 'AbortError'));
        });
      }),
  });
  const timed = await hanging.request({
    url: 'https://example.test/slow',
    method: 'GET',
    foreground: () => true,
    parse: () => ({ data: { ok: true }, errorKind: 'none' }),
  });
  expect(timed.errorKind).toBe('timeout');
  expect(timed.abortReason).toBe('timeout');
  expect(timed.attempts).toBeLessThanOrEqual(3);
  void release;

  const schemaClient = new ApiClient({
    fetchImpl: async () => new Response('<html></html>', { status: 200, headers: { 'content-type': 'text/html' } }),
  });
  const schema = await schemaClient.request({
    url: 'https://example.test/quotas',
    method: 'GET',
    foreground: () => true,
    parse: ({ contentType }) => ({ data: null, errorKind: contentType?.includes('json') ? 'none' : 'schema' }),
  });
  expect(schema.errorKind).toBe('schema');
  expect(schema.attempts).toBe(1);
  expect(schema.stopped).toBe('confirmed');

  const controller = new AbortController();
  controller.abort();
  const cancelClient = new ApiClient({
    fetchImpl: async () => {
      throw new Error('should not send');
    },
  });
  const cancelled = await cancelClient.request({
    url: 'https://example.test/quotas',
    method: 'GET',
    signal: controller.signal,
    abortReason: 'user',
    foreground: () => true,
    parse: () => ({ data: null, errorKind: 'none' }),
  });
  expect(cancelled.errorKind).toBe('cancelled');
  expect(cancelled.abortReason).toBe('user');
  expect(cancelled.attempts).toBe(1);
});

test('single-flight reads and unknown writes are not sent twice', async () => {
  let quotaCalls = 0;
  let modelCalls = 0;
  const kv = memoryKv();
  let now = 1_000;
  const client = new ApiClient({
    now: () => now,
    fetchImpl: async (input, init) => {
      const url = String(input);
      if (url.endsWith('/api/quotas')) {
        quotaCalls += 1;
        await new Promise((resolve) => setTimeout(resolve, 30));
        return new Response(
          JSON.stringify({
            success: true,
            data: [{ provider_id: 'cursor', name: 'Cursor', remaining_percent: 10, fetched_at: '2026-11-05T00:00:00Z' }],
          }),
          { status: 200, headers: { 'content-type': 'application/json', etag: '"q1"' } },
        );
      }
      modelCalls += 1;
      expect(init?.method).toBe('POST');
      throw new TypeError('network down');
    },
  });
  const repo = new QuotaRepository({
    client,
    origin: 'https://opentokenusage-web.chihfu-chen-tw.workers.dev',
    accountKey: 'anonymous',
    kv,
    now: () => now,
  });
  const firstGen = repo.currentGeneration();
  const [a, b] = await Promise.all([
    repo.readQuotas({ generation: firstGen, foreground: () => true }),
    repo.readQuotas({ generation: firstGen, foreground: () => true }),
  ]);
  expect(quotaCalls).toBe(1);
  expect(a.items?.[0].id).toBe('cursor');
  expect(b.items?.[0].remainingPercent).toBe(10);
  const cached = await repo.loadCached();
  expect(cached?.items).toHaveLength(1);

  repo.bumpGeneration();
  const stale = await repo.readQuotas({ generation: firstGen, foreground: () => true });
  expect(stale.stale).toBe(true);
  expect(stale.items).toBeNull();

  const other = new QuotaRepository({
    client,
    origin: 'https://opentokenusage-web.chihfu-chen-tw.workers.dev',
    accountKey: 'other-account',
    kv,
    now: () => now,
  });
  expect(await other.loadCached()).toBeNull();

  const unknown = await repo.writeModels({ userInitiated: true, foreground: () => true });
  expect(unknown.outcome).toBe('unknown');
  const again = await repo.writeModels({ userInitiated: true, foreground: () => true });
  expect(again.outcome).toBe('unknown');
  expect(again.resubmitted).toBe(false);
  expect(modelCalls).toBe(1);
  now += 1;
});

test('lifecycle inactive is not background, and a newer result is not applied on the old generation', () => {
  const active = reduceNet(initialNetState(), { type: 'lifecycle', lifecycle: 'inactive' });
  expect(active.lifecycle).toBe('inactive');
  const background = reduceNet(active, { type: 'lifecycle', lifecycle: 'background' });
  expect(background.lifecycle).toBe('background');
  const ignored = reduceNet(background, {
    type: 'result',
    generation: 5,
    at: 9,
    httpStatus: 200,
    errorKind: 'none',
    appliedData: true,
  });
  expect(ignored.api).toBe('unknown');
  expect(ignored.data).not.toBe('fresh');
  const state: NetState = ignored;
  expect(state.costHint).not.toBe(false);
});
