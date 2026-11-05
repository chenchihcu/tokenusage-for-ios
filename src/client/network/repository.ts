import { joinApi } from '../../shared/cors';
import type { QuotaCardProps } from '../components/QuotaCard';
import { ApiClient, type ApiResult } from './apiClient';
import { isUnknownWrite, parseModelResponse, parseQuotaResponse, type ModelRecord } from './quotaSchema';

export interface KeyValueStore {
  getItem(key: string): Promise<string | null>;
  setItem(key: string, value: string): Promise<void>;
  removeItem(key: string): Promise<void>;
}

export interface DisplayCacheEnvelope {
  accountKey: string;
  origin: string;
  savedAt: number;
  items: QuotaCardProps[];
}

export interface QuotaRead {
  generation: number;
  stale: boolean;
  items: QuotaCardProps[] | null;
  result: ApiResult<QuotaCardProps[]>;
}

export interface WriteResult {
  outcome: 'unknown' | 'confirmed' | 'rejected';
  resubmitted: boolean;
  models: ModelRecord[] | null;
  result: ApiResult<ModelRecord[]> | null;
}

const DEFAULT_TTL_MS = 6 * 60 * 60 * 1000;

export class QuotaRepository {
  private generation = 0;
  private etag: string | null = null;
  private readonly pending = new Map<string, { at: number }>();
  private readonly writes = new Map<string, Promise<WriteResult>>();

  constructor(
    private readonly deps: {
      client: ApiClient;
      origin: string;
      accountKey: string;
      kv: KeyValueStore;
      now: () => number;
      ttlMs?: number;
    },
  ) {}

  get accountKey(): string {
    return this.deps.accountKey;
  }

  cacheStorageKey(): string {
    const origin = this.deps.origin || 'relative';
    return `otu:v1:${this.deps.accountKey}:${origin}:quotas`;
  }

  bumpGeneration(): number {
    this.generation += 1;
    return this.generation;
  }

  currentGeneration(): number {
    return this.generation;
  }

  /** Display-only quota snapshot. Tokens and account secrets are not stored here. */
  async loadCached(): Promise<{ items: QuotaCardProps[]; savedAt: number; expired: boolean } | null> {
    const raw = await this.deps.kv.getItem(this.cacheStorageKey());
    if (!raw) return null;
    try {
      const parsed = JSON.parse(raw) as DisplayCacheEnvelope;
      if (parsed.accountKey !== this.deps.accountKey || parsed.origin !== (this.deps.origin || 'relative')) return null;
      if (!Array.isArray(parsed.items)) return null;
      const ttl = this.deps.ttlMs ?? DEFAULT_TTL_MS;
      return {
        items: parsed.items,
        savedAt: parsed.savedAt,
        expired: this.deps.now() - parsed.savedAt > ttl,
      };
    } catch {
      return null;
    }
  }

  async clearAccount(): Promise<void> {
    await this.deps.kv.removeItem(this.cacheStorageKey());
    this.etag = null;
    this.pending.clear();
  }

  async readQuotas(input: {
    generation: number;
    foreground: () => boolean;
    signal?: AbortSignal;
    abortReason?: 'user' | 'navigation';
  }): Promise<QuotaRead> {
    const headers: Record<string, string> = { Accept: 'application/json' };
    if (this.etag) headers['If-None-Match'] = this.etag;
    const result = await this.deps.client.request({
      url: joinApi(this.deps.origin, '/api/quotas'),
      method: 'GET',
      headers,
      singleFlightKey: `GET ${this.deps.origin}/api/quotas`,
      foreground: input.foreground,
      signal: input.signal,
      abortReason: input.abortReason,
      parse: parseQuotaResponse,
    });
    const stale = input.generation !== this.generation;
    if (!stale && result.etag) this.etag = result.etag;
    if (!stale && result.data && result.errorKind === 'none') {
      const envelope: DisplayCacheEnvelope = {
        accountKey: this.deps.accountKey,
        origin: this.deps.origin || 'relative',
        savedAt: this.deps.now(),
        items: result.data,
      };
      await this.deps.kv.setItem(this.cacheStorageKey(), JSON.stringify(envelope));
    }
    return { generation: input.generation, stale, items: stale ? null : result.data, result };
  }

  /**
   * POST is not retried. A missing response stays pending and a second call does not send again.
   * There is no idempotency-key contract for this route yet.
   */
  writeModels(input: { userInitiated: boolean; foreground: () => boolean; signal?: AbortSignal }): Promise<WriteResult> {
    const id = 'model-catalog';
    if (input.userInitiated && this.pending.has(id)) {
      return Promise.resolve({ outcome: 'unknown', resubmitted: false, models: null, result: null });
    }
    const existing = this.writes.get(id);
    if (existing) return existing;
    const promise = this.sendModels(id, input).finally(() => {
      if (this.writes.get(id) === promise) this.writes.delete(id);
    });
    this.writes.set(id, promise);
    return promise;
  }

  private async sendModels(
    id: string,
    input: { userInitiated: boolean; foreground: () => boolean; signal?: AbortSignal },
  ): Promise<WriteResult> {
    const result = await this.deps.client.request({
      url: joinApi(this.deps.origin, '/api/models/sync'),
      method: 'POST',
      headers: { Accept: 'application/json', 'Content-Type': 'application/json' },
      body: '{}',
      foreground: input.foreground,
      signal: input.signal,
      abortReason: 'user',
      parse: parseModelResponse,
    });
    if (isUnknownWrite(result.errorKind, result.httpStatus)) {
      if (input.userInitiated) this.pending.set(id, { at: this.deps.now() });
      return { outcome: 'unknown', resubmitted: false, models: null, result };
    }
    if (result.errorKind === 'none' && result.data) {
      this.pending.delete(id);
      return { outcome: 'confirmed', resubmitted: false, models: result.data, result };
    }
    return { outcome: 'rejected', resubmitted: false, models: null, result };
  }
}
