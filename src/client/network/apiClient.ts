import {
  JSON_TIMEOUT_MS,
  MAX_SAFE_RETRIES,
  OPERATION_BUDGET_MS,
  classifyTransport,
  parseRetryAfter,
  planRetry,
} from './policy';
import type { ErrorKind } from './types';

export interface ParsedBody<T> {
  data: T | null;
  errorKind: ErrorKind;
}

export interface ApiResult<T> {
  data: T | null;
  httpStatus: number | null;
  errorKind: ErrorKind;
  retryable: boolean;
  requestId: string | null;
  durationMs: number;
  attempts: number;
  etag: string | null;
  notModified: boolean;
  abortReason: 'user' | 'navigation' | 'timeout' | null;
  retryAfterMs: number | null;
  stopped: string | null;
}

export interface RequestSpec<T> {
  url: string;
  method?: string;
  headers?: Record<string, string>;
  body?: string | null;
  signal?: AbortSignal;
  abortReason?: 'user' | 'navigation';
  foreground?: () => boolean;
  timeoutMs?: number;
  budgetMs?: number;
  singleFlightKey?: string;
  parse: (ctx: { status: number; contentType: string | null; bodyText: string }) => ParsedBody<T>;
}

export interface ApiClientDeps {
  fetchImpl?: typeof fetch;
  now?: () => number;
  sleep?: (ms: number) => Promise<void>;
  random?: () => number;
  perRequestMs?: number;
  budgetMs?: number;
  maxRetries?: number;
}

function emptyResult<T>(partial: Partial<ApiResult<T>>): ApiResult<T> {
  return {
    data: null,
    httpStatus: null,
    errorKind: 'transport',
    retryable: false,
    requestId: null,
    durationMs: 0,
    attempts: 0,
    etag: null,
    notModified: false,
    abortReason: null,
    retryAfterMs: null,
    stopped: null,
    ...partial,
  };
}

export class ApiClient {
  private readonly fetchImpl: typeof fetch;
  private readonly now: () => number;
  private readonly sleep: (ms: number) => Promise<void>;
  private readonly random: () => number;
  private readonly perRequestMs: number;
  private readonly budgetMs: number;
  private readonly maxRetries: number;
  private readonly flights = new Map<string, Promise<ApiResult<unknown>>>();

  constructor(deps: ApiClientDeps = {}) {
    this.fetchImpl = deps.fetchImpl ?? fetch;
    this.now = deps.now ?? (() => Date.now());
    this.sleep = deps.sleep ?? ((ms) => new Promise((resolve) => setTimeout(resolve, ms)));
    this.random = deps.random ?? Math.random;
    this.perRequestMs = deps.perRequestMs ?? JSON_TIMEOUT_MS;
    this.budgetMs = deps.budgetMs ?? OPERATION_BUDGET_MS;
    this.maxRetries = deps.maxRetries ?? MAX_SAFE_RETRIES;
  }

  request<T>(spec: RequestSpec<T>): Promise<ApiResult<T>> {
    const key = spec.singleFlightKey;
    if (key) {
      const existing = this.flights.get(key);
      if (existing) return existing as Promise<ApiResult<T>>;
    }
    const promise = this.execute(spec);
    if (key) {
      this.flights.set(key, promise as Promise<ApiResult<unknown>>);
      promise.finally(() => {
        if (this.flights.get(key) === promise) this.flights.delete(key);
      });
    }
    return promise;
  }

  private async execute<T>(spec: RequestSpec<T>): Promise<ApiResult<T>> {
    const method = (spec.method ?? 'GET').toUpperCase();
    const started = this.now();
    const budgetMs = spec.budgetMs ?? this.budgetMs;
    let attempts = 0;
    let last = emptyResult<T>({});

    while (true) {
      const remaining = budgetMs - (this.now() - started);
      if (remaining <= 0 && attempts > 0) {
        return { ...last, stopped: 'budget', retryable: false };
      }
      const timeoutMs = Math.min(spec.timeoutMs ?? this.perRequestMs, Math.max(1, remaining));
      attempts += 1;
      last = await this.oneShot(spec, method, timeoutMs, attempts, started);
      const foreground = spec.foreground ? spec.foreground() : true;
      const plan = planRetry({
        method,
        errorKind: last.errorKind,
        httpStatus: last.httpStatus,
        completedAttempts: attempts,
        maxRetries: this.maxRetries,
        remainingBudgetMs: budgetMs - (this.now() - started),
        retryAfterMs: last.retryAfterMs,
        random: this.random,
        cancelled: last.abortReason === 'user' || last.abortReason === 'navigation' || spec.signal?.aborted === true,
        foreground,
      });
      if ('stop' in plan) {
        return { ...last, stopped: plan.stop, retryable: false };
      }
      await this.sleep(plan.waitMs);
    }
  }

  private async oneShot<T>(
    spec: RequestSpec<T>,
    method: string,
    timeoutMs: number,
    attempts: number,
    started: number,
  ): Promise<ApiResult<T>> {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    const onExternal = () => controller.abort();
    spec.signal?.addEventListener('abort', onExternal);
    try {
      if (spec.signal?.aborted) {
        return emptyResult({
          errorKind: 'cancelled',
          abortReason: spec.abortReason ?? 'user',
          attempts,
          durationMs: this.now() - started,
          stopped: 'cancelled',
        });
      }
      const response = await this.fetchImpl(spec.url, {
        method,
        headers: spec.headers,
        body: spec.body ?? undefined,
        signal: controller.signal,
        cache: 'no-store',
        credentials: 'omit',
      });
      let bodyText = '';
      if (response.status !== 204 && response.status !== 304) {
        bodyText = await response.text();
      }
      const parsed = spec.parse({
        status: response.status,
        contentType: response.headers.get('content-type'),
        bodyText,
      });
      const retryAfterMs = parseRetryAfter(response.headers.get('retry-after'), this.now());
      return {
        data: parsed.data,
        httpStatus: response.status,
        errorKind: parsed.errorKind,
        retryable: false,
        requestId: response.headers.get('x-request-id'),
        durationMs: this.now() - started,
        attempts,
        etag: response.headers.get('etag'),
        notModified: response.status === 304,
        abortReason: null,
        retryAfterMs,
        stopped: null,
      };
    } catch (error) {
      const external = spec.signal?.aborted === true;
      const timedOut = controller.signal.aborted && !external;
      const abortReason = external ? spec.abortReason ?? 'user' : timedOut ? 'timeout' : null;
      const errorKind = abortReason === 'timeout' ? 'timeout' : abortReason ? 'cancelled' : classifyTransport(error);
      return emptyResult({
        errorKind,
        abortReason,
        attempts,
        durationMs: this.now() - started,
      });
    } finally {
      clearTimeout(timer);
      spec.signal?.removeEventListener('abort', onExternal);
    }
  }
}
