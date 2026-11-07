import type { ErrorKind } from './types';

/** Project defaults. These are not iOS limits. */
export const JSON_TIMEOUT_MS = 15_000;
export const OPERATION_BUDGET_MS = 40_000;
export const HEALTH_TIMEOUT_MS = 5_000;
export const MAX_SAFE_RETRIES = 2;
export const PROBE_COOLDOWN_MS = 30_000;
export const ATTACHMENT_CONFIRM_BYTES = 5 * 1_048_576;

const RETRY_STATUS = new Set([408, 429, 502, 503, 504]);

export function classifyHttp(status: number): ErrorKind {
  if (status >= 200 && status < 300) return 'none';
  if (status === 304) return 'none';
  if (status === 401) return 'http_auth';
  if (status === 403) return 'http_forbidden';
  if (status === 429) return 'http_rate_limit';
  if (status >= 500) return 'http_server';
  if (status >= 400) return 'http_client';
  return 'transport';
}

export function classifyTransport(error: unknown): ErrorKind {
  const name = error instanceof DOMException ? error.name : error instanceof Error ? error.name : '';
  if (name === 'AbortError') return 'cancelled';
  const message = (error instanceof Error ? error.message : String(error ?? '')).toLowerCase();
  if (message.includes('cors')) return 'cors';
  if (message.includes('certificate') || message.includes('ssl') || /\btls\b/.test(message)) return 'tls';
  if (message.includes('dns') || message.includes('name not resolved') || message.includes('enotfound')) {
    return 'dns';
  }
  return 'transport';
}

/** Seconds or an HTTP-date. Returns a delay in milliseconds, or null when the header is unusable. */
export function parseRetryAfter(value: string | null | undefined, nowMs: number): number | null {
  if (!value) return null;
  const trimmed = value.trim();
  if (!trimmed) return null;
  if (/^\d+$/.test(trimmed)) {
    const seconds = Number(trimmed);
    if (!Number.isFinite(seconds)) return null;
    return seconds * 1000;
  }
  const date = Date.parse(trimmed);
  if (Number.isNaN(date)) return null;
  return Math.max(0, date - nowMs);
}

/** Full jitter: retry 1 waits 0–1s, retry 2 waits 0–2s. */
export function jitterMs(retryOrdinal: number, random: () => number): number {
  const cap = retryOrdinal <= 1 ? 1000 : 2000;
  const unit = random();
  const clamped = unit < 0 ? 0 : unit >= 1 ? 0.999999 : unit;
  return Math.floor(clamped * (cap + 1));
}

export type RetryPlan =
  | { waitMs: number }
  | { stop: 'method' | 'cancelled' | 'background' | 'limit' | 'budget' | 'confirmed' };

export function planRetry(input: {
  method: string;
  errorKind: ErrorKind;
  httpStatus: number | null;
  completedAttempts: number;
  maxRetries?: number;
  remainingBudgetMs: number;
  retryAfterMs: number | null;
  random: () => number;
  cancelled: boolean;
  foreground: boolean;
}): RetryPlan {
  if (input.cancelled || input.errorKind === 'cancelled') return { stop: 'cancelled' };
  if (!input.foreground) return { stop: 'background' };
  const method = input.method.toUpperCase();
  if (method !== 'GET' && method !== 'HEAD') return { stop: 'method' };

  const confirmed = new Set<ErrorKind>(['tls', 'cors', 'dns', 'schema', 'http_auth', 'http_forbidden', 'http_client']);
  if (confirmed.has(input.errorKind) && input.httpStatus !== 408) return { stop: 'confirmed' };

  const statusRetry = input.httpStatus !== null && RETRY_STATUS.has(input.httpStatus);
  const transportRetry = input.httpStatus === null && (input.errorKind === 'timeout' || input.errorKind === 'transport');
  if (!statusRetry && !transportRetry) return { stop: 'confirmed' };

  const maxRetries = input.maxRetries ?? MAX_SAFE_RETRIES;
  if (input.completedAttempts > maxRetries) return { stop: 'limit' };

  const waitMs = input.retryAfterMs === null ? jitterMs(input.completedAttempts, input.random) : input.retryAfterMs;
  if (waitMs > input.remainingBudgetMs) return { stop: 'budget' };
  return { waitMs };
}

/** Unknown size is confirmed before transfer. This is a product threshold, not a carrier measurement. */
export function needsSizeConfirm(bytes: number | null): boolean {
  if (bytes === null) return true;
  return bytes >= ATTACHMENT_CONFIRM_BYTES;
}

export class ProbeGate {
  private inFlight = false;
  private lastStartedAt = 0;

  constructor(private readonly cooldownMs = PROBE_COOLDOWN_MS) {}

  get busy(): boolean {
    return this.inFlight;
  }

  /** User and the cold start skip the cooldown. Only one probe runs at a time. */
  tryEnter(now: number, bypassCooldown: boolean): boolean {
    if (this.inFlight) return false;
    if (!bypassCooldown && this.lastStartedAt !== 0 && now - this.lastStartedAt < this.cooldownMs) {
      return false;
    }
    this.inFlight = true;
    this.lastStartedAt = now;
    return true;
  }

  leave(): void {
    this.inFlight = false;
  }
}
