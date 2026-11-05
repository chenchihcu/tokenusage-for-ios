import type { QuotaCardProps } from '../components/QuotaCard';
import { classifyHttp } from './policy';
import type { ErrorKind } from './types';
import type { ParsedBody } from './apiClient';

export interface ModelRecord {
  id: string;
  name: string;
  [key: string]: unknown;
}

function asRecord(value: unknown): Record<string, unknown> | null {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
  return value as Record<string, unknown>;
}

export function coerceQuotas(json: unknown): QuotaCardProps[] | null {
  const body = asRecord(json);
  if (!body || body.success !== true || !Array.isArray(body.data)) return null;
  const items: QuotaCardProps[] = [];
  for (const raw of body.data) {
    const item = asRecord(raw);
    if (!item) return null;
    const id = typeof item.provider_id === 'string' ? item.provider_id : typeof item.id === 'string' ? item.id : null;
    if (!id || typeof item.name !== 'string') return null;
    items.push({
      id,
      name: item.name,
      planName: typeof item.plan_name === 'string' ? item.plan_name : typeof item.planName === 'string' ? item.planName : 'Standard',
      totalQuota: typeof item.total_quota === 'number' ? item.total_quota : typeof item.totalQuota === 'number' ? item.totalQuota : 100,
      usedQuota: typeof item.used_quota === 'number' ? item.used_quota : typeof item.usedQuota === 'number' ? item.usedQuota : 0,
      remainingPercent:
        typeof item.remaining_percent === 'number'
          ? item.remaining_percent
          : typeof item.remainingPercent === 'number'
            ? item.remainingPercent
            : 0,
      resetTime: typeof item.reset_time === 'string' ? item.reset_time : typeof item.resetTime === 'string' ? item.resetTime : '',
      status: typeof item.status === 'string' ? item.status : 'active',
      token_pools_json: typeof item.token_pools_json === 'string' ? item.token_pools_json : undefined,
      metrics_json: typeof item.metrics_json === 'string' ? item.metrics_json : undefined,
      fetched_at: typeof item.fetched_at === 'string' ? item.fetched_at : undefined,
    });
  }
  return items;
}

export function parseQuotaResponse(ctx: {
  status: number;
  contentType: string | null;
  bodyText: string;
}): ParsedBody<QuotaCardProps[]> {
  if (ctx.status === 304 || ctx.status === 204) return { data: null, errorKind: 'none' };
  const httpKind = classifyHttp(ctx.status);
  if (httpKind !== 'none') return { data: null, errorKind: httpKind };
  const type = ctx.contentType ?? '';
  if (!type.includes('json')) return { data: null, errorKind: 'schema' };
  try {
    const items = coerceQuotas(JSON.parse(ctx.bodyText));
    if (!items) return { data: null, errorKind: 'schema' };
    return { data: items, errorKind: 'none' };
  } catch {
    return { data: null, errorKind: 'schema' };
  }
}

export function parseModelResponse(ctx: {
  status: number;
  contentType: string | null;
  bodyText: string;
}): ParsedBody<ModelRecord[]> {
  if (ctx.status === 204) return { data: null, errorKind: 'none' };
  const httpKind = classifyHttp(ctx.status);
  if (httpKind !== 'none') return { data: null, errorKind: httpKind };
  if (!(ctx.contentType ?? '').includes('json')) return { data: null, errorKind: 'schema' };
  try {
    const body = asRecord(JSON.parse(ctx.bodyText));
    if (!body || body.success !== true || !Array.isArray(body.models)) return { data: null, errorKind: 'schema' };
    const models: ModelRecord[] = [];
    for (const raw of body.models) {
      const item = asRecord(raw);
      if (!item || typeof item.id !== 'string' || typeof item.name !== 'string') return { data: null, errorKind: 'schema' };
      models.push(item as ModelRecord);
    }
    return { data: models, errorKind: 'none' };
  } catch {
    return { data: null, errorKind: 'schema' };
  }
}

export function isUnknownWrite(errorKind: ErrorKind, httpStatus: number | null): boolean {
  return httpStatus === null && (errorKind === 'timeout' || errorKind === 'transport' || errorKind === 'dns');
}
