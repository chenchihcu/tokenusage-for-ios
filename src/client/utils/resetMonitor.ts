import { QuotaCardProps } from '../components/QuotaCard';
import { TokenPool } from '../../types/quota';

export const WINDOW_PASSED_TEXT = '已到重置時間';

export interface ResetWindowSummary {
  platformId: string;
  platformName: string;
  remainingPercent: number;
  sessionText: string;
  weeklyText: string;
  weeklyResetAt: string | null;
  sessionResetAt: string | null;
  /** The weekly reset time has passed but no newer data has arrived yet. Not a free reset. */
  isWindowPassed: boolean;
  isResettingSoon: boolean;
  /** Vendor-granted free resets ("Resets: N available"). null = the vendor did not report it. */
  resetCredits: number | null;
}

export function formatResetCountdown(isoOrText: string | null | undefined, nowMs: number = Date.now()): string {
  if (!isoOrText) return '週期中';
  if (!isoOrText.includes('T')) return isoOrText;

  const targetMs = new Date(isoOrText).getTime();
  if (Number.isNaN(targetMs)) return isoOrText;

  const diffMs = targetMs - nowMs;
  if (diffMs <= 0) return WINDOW_PASSED_TEXT;

  const totalMinutes = Math.floor(diffMs / 60_000);
  const days = Math.floor(totalMinutes / (60 * 24));
  const hours = Math.floor((totalMinutes % (60 * 24)) / 60);
  const minutes = totalMinutes % 60;

  if (days > 0) return `${days}d ${hours}h`;
  if (hours > 0) return `${hours}h ${minutes}m`;
  return `${Math.max(1, minutes)}m`;
}

/** Reads the vendor's free-reset count from metrics such as `{ label: 'Resets', value: '2 available' }`. */
export function parseResetCredits(item: Pick<QuotaCardProps, 'metrics_json'>): number | null {
  if (!item.metrics_json) return null;
  try {
    const metrics = JSON.parse(item.metrics_json);
    if (!Array.isArray(metrics)) return null;
    const entry = metrics.find(
      (m: { label?: unknown }) => typeof m?.label === 'string' && /^resets?\b/i.test(m.label.trim()),
    );
    if (!entry) return null;
    const raw = typeof entry.value === 'string' || typeof entry.value === 'number' ? String(entry.value) : '';
    const match = raw.match(/\d+/);
    return match ? Number(match[0]) : null;
  } catch {
    return null;
  }
}

export function extractResetWindowSummary(item: QuotaCardProps, nowMs: number = Date.now()): ResetWindowSummary {
  let sessionResetAt: string | null = null;
  let weeklyResetAt: string | null = item.resetTime || null;
  let sessionText = '--';
  let weeklyText = formatResetCountdown(item.resetTime, nowMs);

  if (item.token_pools_json) {
    try {
      const pools: TokenPool[] = JSON.parse(item.token_pools_json);
      for (const pool of pools) {
        for (const tier of pool.tiers || []) {
          if ((tier.id === '5h' || tier.id === 'session') && !sessionResetAt) {
            sessionResetAt = tier.resetsAt;
            sessionText = tier.resetsAt
              ? formatResetCountdown(tier.resetsAt, nowMs)
              : tier.resetDurationText || '100% left';
          }
          if (tier.id === 'weekly') {
            if (!weeklyResetAt || (tier.resetsAt && tier.isGoverning)) {
              weeklyResetAt = tier.resetsAt;
            }
            if (tier.resetsAt) {
              weeklyText = formatResetCountdown(tier.resetsAt, nowMs);
            } else if (tier.resetDurationText) {
              weeklyText = tier.resetDurationText;
            }
          }
        }
      }
    } catch {}
  }

  const weeklyTargetMs = weeklyResetAt && weeklyResetAt.includes('T') ? new Date(weeklyResetAt).getTime() : NaN;
  const isWindowPassed = !Number.isNaN(weeklyTargetMs) && nowMs >= weeklyTargetMs;
  const isResettingSoon =
    !isWindowPassed &&
    !Number.isNaN(weeklyTargetMs) &&
    weeklyTargetMs - nowMs <= 24 * 60 * 60 * 1000;

  return {
    platformId: item.id,
    platformName: item.name,
    remainingPercent: item.remainingPercent,
    sessionText,
    weeklyText,
    weeklyResetAt,
    sessionResetAt,
    isWindowPassed,
    isResettingSoon,
    resetCredits: parseResetCredits(item),
  };
}
