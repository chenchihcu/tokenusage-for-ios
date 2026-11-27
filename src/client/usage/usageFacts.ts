import type { QuotaCardProps } from '../components/QuotaCard';
import type { TokenPool } from '../../types/quota';

/** Same four services the dashboard already tracks, in the default agent order. */
export const TRACKED_AGENT_IDS = ['codex', 'claude', 'cursor', 'antigravity'] as const;

export const USAGE_GROUPS = [
  { id: 'agent', label: 'Agent' },
  { id: 'model', label: '模型' },
  { id: 'session', label: '5 小時' },
  { id: 'week', label: '每週' },
  { id: 'fee', label: '費用' },
] as const;

export type UsageGroupId = (typeof USAGE_GROUPS)[number]['id'];

export interface AgentUsage {
  id: string;
  name: string;
  planName: string;
  usedPercent: number;
  remainingPercent: number;
  /** Pool the service actually reported. Never synthesized from a speed tier. */
  modelName: string | null;
  extraModels: number;
  sessionUsed: number | null;
  weekUsed: number | null;
  feeText: string | null;
}

const SESSION_LABEL = /5\s*h|session|今日|當天/i;
const WEEK_LABEL = /week|每週|每周/i;
const MONEY = /\$\s?\d[\d,]*(?:\.\d+)?/;

interface Metric {
  label?: unknown;
  used?: unknown;
  value?: unknown;
}

export function isUsageGroup(value: string | null): value is UsageGroupId {
  return USAGE_GROUPS.some((group) => group.id === value);
}

function asMetrics(raw?: string): Metric[] {
  if (!raw) return [];
  try {
    const parsed: unknown = JSON.parse(raw);
    if (!Array.isArray(parsed)) return [];
    return parsed.filter((item): item is Metric => Boolean(item) && typeof item === 'object');
  } catch {
    return [];
  }
}

function asPools(raw?: string): TokenPool[] {
  if (!raw) return [];
  try {
    const parsed: unknown = JSON.parse(raw);
    if (!Array.isArray(parsed)) return [];
    return parsed.filter(
      (item): item is TokenPool =>
        Boolean(item) && typeof item === 'object' && typeof (item as TokenPool).name === 'string',
    );
  } catch {
    return [];
  }
}

function metricUsed(metrics: Metric[], pattern: RegExp): number | null {
  for (const metric of metrics) {
    if (typeof metric.label === 'string' && pattern.test(metric.label) && typeof metric.used === 'number') {
      return metric.used;
    }
  }
  return null;
}

function feeText(metrics: Metric[]): string | null {
  for (const metric of metrics) {
    if (typeof metric.value !== 'string') continue;
    const found = metric.value.match(MONEY);
    if (found) return found[0].replace(/\s/g, '');
  }
  return null;
}

const SESSION_TIER_IDS = ['5h', 'session'];
const WEEK_TIER_IDS = ['weekly'];

function tierUsed(pool: TokenPool, tierIds: readonly string[]): number | null {
  const tier = pool.tiers?.find((item) => tierIds.includes(item.id));
  return tier && typeof tier.used === 'number' ? tier.used : null;
}

function windowUsed(
  pool: TokenPool | null,
  tierIds: readonly string[],
  metrics: Metric[],
  pattern: RegExp,
): number | null {
  if (pool) {
    const fromTier = tierUsed(pool, tierIds);
    if (fromTier !== null) return fromTier;
  }
  return metricUsed(metrics, pattern);
}

function governingPool(pools: TokenPool[]): TokenPool | null {
  if (pools.length === 0) return null;
  return pools.reduce((tightest, pool) =>
    pool.effectiveRemaining < tightest.effectiveRemaining ? pool : tightest,
  );
}

export function buildAgentUsage(item: QuotaCardProps): AgentUsage {
  const metrics = asMetrics(item.metrics_json);
  const pools = asPools(item.token_pools_json);
  const pool = governingPool(pools);
  return {
    id: item.id,
    name: item.name,
    planName: item.planName,
    usedPercent: item.usedQuota,
    remainingPercent: item.remainingPercent,
    modelName: pool ? pool.name : null,
    extraModels: Math.max(0, pools.length - 1),
    sessionUsed: windowUsed(pool, SESSION_TIER_IDS, metrics, SESSION_LABEL),
    weekUsed: windowUsed(pool, WEEK_TIER_IDS, metrics, WEEK_LABEL),
    feeText: feeText(metrics),
  };
}

function feeNumber(text: string | null): number | null {
  if (!text) return null;
  const parsed = Number(text.replace(/[$,]/g, ''));
  return Number.isFinite(parsed) ? parsed : null;
}

export function orderAgents(items: AgentUsage[], group: UsageGroupId): AgentUsage[] {
  const rank = new Map<string, number>(TRACKED_AGENT_IDS.map((id, index) => [id, index]));
  const byTracked = (a: AgentUsage, b: AgentUsage) => (rank.get(a.id) ?? 99) - (rank.get(b.id) ?? 99);
  const rows = [...items];
  if (group === 'model') {
    return rows.sort((a, b) => {
      if ((a.modelName === null) !== (b.modelName === null)) return a.modelName === null ? 1 : -1;
      return (a.modelName ?? '').localeCompare(b.modelName ?? '', 'zh-Hant') || byTracked(a, b);
    });
  }
  if (group === 'session') {
    return rows.sort((a, b) => (b.sessionUsed ?? -1) - (a.sessionUsed ?? -1) || byTracked(a, b));
  }
  if (group === 'week') {
    return rows.sort((a, b) => (b.weekUsed ?? -1) - (a.weekUsed ?? -1) || byTracked(a, b));
  }
  if (group === 'fee') {
    return rows.sort((a, b) => {
      const left = feeNumber(a.feeText);
      const right = feeNumber(b.feeText);
      if ((left === null) !== (right === null)) return left === null ? 1 : -1;
      return (right ?? 0) - (left ?? 0) || byTracked(a, b);
    });
  }
  return rows.sort(byTracked);
}

export function percentText(value: number | null): string {
  if (value === null) return '未提供';
  return Number.isInteger(value) ? `${value}%` : `${value.toFixed(1)}%`;
}

export function modelText(row: AgentUsage): string {
  if (!row.modelName) return '未提供';
  if (row.extraModels > 0) return `${row.modelName}，另 ${row.extraModels} 個`;
  return row.modelName;
}

export function levelWord(remainingPercent: number): string | null {
  if (remainingPercent <= 5) return '耗盡';
  if (remainingPercent <= 20) return '偏低';
  return null;
}
