import { QuotaCardProps } from '../components/QuotaCard';
import { TokenPool } from '../../types/quota';

export interface ResetWindowSummary {
  platformId: string;
  platformName: string;
  remainingPercent: number;
  sessionText: string;
  weeklyText: string;
  weeklyResetAt: string | null;
  sessionResetAt: string | null;
  isFreeResetReady: boolean;
  isResettingSoon: boolean;
}

export function formatResetCountdown(isoOrText: string | null | undefined, nowMs: number = Date.now()): string {
  if (!isoOrText) return '週期中';
  if (!isoOrText.includes('T')) return isoOrText;

  const targetMs = new Date(isoOrText).getTime();
  if (Number.isNaN(targetMs)) return isoOrText;

  const diffMs = targetMs - nowMs;
  if (diffMs <= 0) {
    return '已重置 (FREE)';
  }

  const totalMinutes = Math.floor(diffMs / 60_000);
  const days = Math.floor(totalMinutes / (60 * 24));
  const hours = Math.floor((totalMinutes % (60 * 24)) / 60);
  const minutes = totalMinutes % 60;

  if (days > 0) return `${days}d ${hours}h`;
  if (hours > 0) return `${hours}h ${minutes}m`;
  return `${Math.max(1, minutes)}m`;
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
          if (tier.id === '5h' && !sessionResetAt) {
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
  const isFreeResetReady =
    (!Number.isNaN(weeklyTargetMs) && nowMs >= weeklyTargetMs) ||
    item.remainingPercent === 100 ||
    weeklyText.includes('已重置');
  const isResettingSoon =
    !isFreeResetReady &&
    !Number.isNaN(weeklyTargetMs) &&
    weeklyTargetMs - nowMs > 0 &&
    weeklyTargetMs - nowMs <= 24 * 60 * 60 * 1000;

  return {
    platformId: item.id,
    platformName: item.name,
    remainingPercent: item.remainingPercent,
    sessionText,
    weeklyText,
    weeklyResetAt,
    sessionResetAt,
    isFreeResetReady,
    isResettingSoon,
  };
}
