import React from 'react';
import { AlertTriangle, CheckCircle2, Sparkles } from 'lucide-react';
import { PlatformIcon } from './PlatformIcon';
import { MiniRingChart } from './MiniRingChart';
import { extractResetWindowSummary } from '../utils/resetMonitor';
import { AgentUsage, levelWord, modelText, percentText } from '../usage/usageFacts';

export interface QuotaCardProps {
  id: string;
  name: string;
  planName: string;
  remainingPercent: number;
  usedQuota: number;
  totalQuota: number;
  resetTime: string;
  status: string;
  token_pools_json?: string;
  metrics_json?: string;
  fetched_at?: string;
  isSelected?: boolean;
  highlightKey?: 'agent' | 'model' | 'session' | 'week' | 'fee';
  onClick?: () => void;
}

const PLATFORM_RING_COLORS: Record<string, [string, string]> = {
  cursor: ['#0284C7', '#007AFF'],
  codex: ['#059669', '#10B981'],
  antigravity: ['#4F46E5', '#7C3AED'],
  claude: ['#D97706', '#EA580C'],
};

export const QuotaCard: React.FC<QuotaCardProps & { usage?: AgentUsage }> = ({
  id,
  name,
  planName,
  remainingPercent,
  usedQuota,
  totalQuota,
  resetTime,
  status,
  token_pools_json,
  metrics_json,
  isSelected = false,
  highlightKey = 'agent',
  usage,
  onClick,
}) => {
  const isCritical = remainingPercent <= 5;
  const isWarning = remainingPercent <= 20 && remainingPercent > 5;
  const level = levelWord(remainingPercent);
  const ringColors = PLATFORM_RING_COLORS[id] ?? ['#007AFF', '#38BDF8'];

  const win = extractResetWindowSummary({
    id,
    name,
    planName,
    remainingPercent,
    usedQuota,
    totalQuota,
    resetTime,
    status,
    token_pools_json,
    metrics_json,
  });

  const sessionVal = usage?.sessionUsed ?? null;
  const weekVal = usage?.weekUsed ?? null;
  const modelLabel = usage ? modelText(usage) : '未提供';
  const feeLabel = usage?.feeText ?? '未提供';

  return (
    <button
      type="button"
      onClick={onClick}
      aria-pressed={isSelected}
      className={`bento-card group relative w-full sm:h-full phoneland:h-full min-h-0 min-w-0 flex flex-col justify-between gap-0.5 sm:gap-2 phoneland:gap-0.5 px-3 py-1.5 sm:p-3.5 phoneland:px-2.5 phoneland:py-1.5 rounded-2xl border text-left transition-colors focus:outline-none focus-visible:ring-2 focus-visible:ring-accent-primary ${
        isSelected
          ? 'bg-surface-card border-accent-primary shadow-hig-card ring-1 ring-accent-primary/20'
          : 'bg-surface-card border-border-hairline shadow-hig-card hover:border-border-strong'
      }`}
    >
      {/* Top Row: Identity + Ring */}
      <div className="flex items-start justify-between gap-2 min-w-0 w-full">
        <div className="flex items-center gap-2 min-w-0 flex-1">
          <PlatformIcon id={id} className="w-6 h-6 phoneland:w-5 phoneland:h-5 shrink-0" />
          <div className="min-w-0 flex-1">
            <div className="flex items-center gap-1.5 min-w-0">
              <h3 className="text-body font-bold text-ink-primary truncate">{name}</h3>
              <span className="sm:hidden text-xs text-ink-muted truncate">{planName}</span>
              {level ? (
                <span
                  className={`inline-flex items-center gap-0.5 px-1.5 py-0.5 rounded-full text-xs font-bold shrink-0 ${
                    isCritical
                      ? 'bg-status-critical-bg text-status-critical'
                      : 'bg-status-warning-bg text-status-warning'
                  }`}
                >
                  <AlertTriangle className="w-3 h-3" aria-hidden="true" />
                  {level}
                </span>
              ) : (
                <span className="hidden sm:inline-flex items-center gap-0.5 px-1.5 py-0.5 rounded-full text-xs font-normal bg-status-healthy-bg text-status-healthy shrink-0">
                  <CheckCircle2 className="w-3 h-3" aria-hidden="true" />
                  正常
                </span>
              )}
            </div>
            <p className="hidden sm:block phoneland:hidden text-xs text-ink-muted truncate">{planName}</p>
          </div>
        </div>

        <MiniRingChart
          value={remainingPercent}
          gradientId={`ring-${id}`}
          gradientColors={ringColors}
          isCritical={isCritical}
          compact={true}
          label={name}
        />
      </div>

      {/* Middle: Model & Dual Window Meters */}
      <div className="flex flex-col gap-0.5 sm:gap-1.5 phoneland:gap-0.5 min-w-0 w-full">
        <div
          className={`text-xs truncate ${
            highlightKey === 'model' ? 'text-accent-primary font-bold' : 'text-ink-secondary font-normal'
          }`}
          title={`模型 ${modelLabel}`}
        >
          模型 {modelLabel}
        </div>

        <div className="flex flex-wrap items-center gap-x-3 gap-y-0.5 text-xs tabular-nums text-ink-secondary">
          <span className={highlightKey === 'session' ? 'text-accent-primary font-bold' : ''}>
            5小時 {percentText(sessionVal)}
          </span>
          <span className={highlightKey === 'week' ? 'text-accent-primary font-bold' : ''}>
            每週 {percentText(weekVal)}
          </span>
          <span className={highlightKey === 'fee' ? 'text-accent-primary font-bold' : ''}>
            費用 {feeLabel}
          </span>
        </div>
      </div>

      {/* Bottom: Reset & Free Credits (hidden in compact phoneland where ResetMonitorBar is visible above) */}
      <div className="flex phoneland:hidden items-center justify-between gap-2 min-w-0 w-full pt-0.5 sm:pt-1 border-t border-border-hairline text-xs text-ink-muted">
        <span className="truncate tabular-nums">
          {win.sessionText !== '--' ? `5h ${win.sessionText}` : `週 ${win.weeklyText}`}
        </span>
        {(win.resetCredits ?? 0) > 0 ? (
          <span className="inline-flex items-center gap-1 px-1.5 py-0.5 rounded-md bg-status-healthy-bg text-status-healthy text-xs font-bold shrink-0">
            <Sparkles className="w-3 h-3" aria-hidden="true" />
            免費重置 {win.resetCredits} 次
          </span>
        ) : (
          <span className="shrink-0 tabular-nums">已用 {percentText(usedQuota)}</span>
        )}
      </div>
    </button>
  );
};
