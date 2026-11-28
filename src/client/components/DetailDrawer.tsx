import React, { useEffect, useMemo, useRef } from 'react';
import { X, AlertTriangle, CheckCircle2, Sparkles } from 'lucide-react';
import { QuotaCardProps } from './QuotaCard';
import { PlatformIcon } from './PlatformIcon';
import { MiniRingChart } from './MiniRingChart';
import { buildAgentUsage, levelWord, modelText, percentText } from '../usage/usageFacts';
import { extractResetWindowSummary } from '../utils/resetMonitor';
import { creditsLabel, MONITORED_RESET_IDS } from './ResetMonitorBar';
import type { TokenPool } from '../../types/quota';

interface DetailDrawerProps {
  item: QuotaCardProps | undefined;
  open: boolean;
  onClose: () => void;
  connectionLabel?: string;
}

const PLATFORM_RING_COLORS: Record<string, [string, string]> = {
  cursor: ['#0284C7', '#007AFF'],
  codex: ['#059669', '#10B981'],
  antigravity: ['#4F46E5', '#7C3AED'],
  claude: ['#D97706', '#EA580C'],
};

export const DetailDrawer: React.FC<DetailDrawerProps> = ({
  item,
  open,
  onClose,
  connectionLabel = '待確認',
}) => {
  const dialogRef = useRef<HTMLDialogElement>(null);

  useEffect(() => {
    const dialog = dialogRef.current;
    if (!dialog) return;
    if (open && !dialog.open) {
      dialog.showModal();
    } else if (!open && dialog.open) {
      dialog.close();
    }
  }, [open]);

  // Safari fallback for closedby="any"
  useEffect(() => {
    const dialog = dialogRef.current;
    if (!dialog) return;
    const onCloseEvent = () => {
      dialog.returnValue = '';
      onClose();
    };
    dialog.addEventListener('close', onCloseEvent);

    if ('closedBy' in HTMLDialogElement.prototype) {
      return () => dialog.removeEventListener('close', onCloseEvent);
    }

    const outside = (e: PointerEvent) => {
      const r = dialog.getBoundingClientRect();
      return e.clientX < r.left || e.clientX > r.right || e.clientY < r.top || e.clientY > r.bottom;
    };
    let pressedOutside = false;
    const onDown = (e: PointerEvent) => {
      pressedOutside = outside(e);
    };
    const onUp = (e: PointerEvent) => {
      if (pressedOutside && outside(e)) dialog.close();
      pressedOutside = false;
    };
    dialog.addEventListener('pointerdown', onDown);
    dialog.addEventListener('pointerup', onUp);
    return () => {
      dialog.removeEventListener('close', onCloseEvent);
      dialog.removeEventListener('pointerdown', onDown);
      dialog.removeEventListener('pointerup', onUp);
    };
  }, [onClose]);

  const usage = useMemo(() => (item ? buildAgentUsage(item) : null), [item]);
  const pools = useMemo<TokenPool[]>(() => {
    if (!item?.token_pools_json) return [];
    try {
      const parsed = JSON.parse(item.token_pools_json);
      return Array.isArray(parsed) ? parsed : [];
    } catch {
      return [];
    }
  }, [item?.token_pools_json]);

  const resetSummary = useMemo(() => (item ? extractResetWindowSummary(item) : null), [item]);
  const isMonitored = item ? (MONITORED_RESET_IDS as readonly string[]).includes(item.id) : false;
  const level = item ? levelWord(item.remainingPercent) : null;
  const ringColors: [string, string] = item
    ? PLATFORM_RING_COLORS[item.id] ?? ['#007AFF', '#38BDF8']
    : ['#007AFF', '#38BDF8'];

  return (
    <dialog
      ref={dialogRef}
      closedby="any"
      aria-labelledby="drawer-title"
      className="m-0 mt-auto sm:mt-0 sm:ml-auto w-full sm:w-[26rem] max-w-full h-auto max-h-[88dvh] sm:h-full sm:max-h-full rounded-t-2xl sm:rounded-l-2xl sm:rounded-r-none bg-surface-card text-ink-primary border border-border-hairline shadow-hig-drawer p-0 open:flex flex-col overflow-hidden"
    >
      {open && item && usage ? (
        <>
          {/* Drawer Header */}
          <div className="shrink-0 flex items-center justify-between gap-3 px-4 py-3 border-b border-border-hairline bg-surface-chrome backdrop-blur-md">
            <div className="flex items-center gap-2.5 min-w-0">
              <PlatformIcon id={item.id} className="w-7 h-7 shrink-0" />
              <div className="min-w-0">
                <h1 id="drawer-title" className="text-heading-section font-bold text-ink-primary truncate">
                  {item.name}
                </h1>
                <p className="text-xs text-ink-muted truncate">
                  {item.planName} · {connectionLabel}
                </p>
              </div>
            </div>
            <button
              type="button"
              onClick={onClose}
              aria-label="關閉詳情"
              className="min-h-[44px] min-w-[44px] inline-flex items-center justify-center rounded-xl text-ink-secondary hover:bg-surface-muted focus:outline-none focus-visible:ring-2 focus-visible:ring-accent-primary"
            >
              <X className="w-5 h-5" aria-hidden="true" />
            </button>
          </div>

          {/* Drawer Body */}
          <div className="flex-1 min-h-0 overflow-y-auto p-4 pb-safe flex flex-col gap-4">
            {/* Hero Summary */}
            <div className="flex items-center justify-between gap-4 p-4 rounded-2xl bg-surface-canvas border border-border-hairline">
              <div className="flex flex-col gap-1 min-w-0">
                <span className="text-xs text-ink-muted">整體剩餘額度</span>
                <div className="flex items-baseline gap-2">
                  <span className="text-kpi font-bold tabular-nums text-ink-primary">
                    {percentText(usage.remainingPercent)}
                  </span>
                  <span className="text-xs text-ink-secondary tabular-nums">
                    已用 {percentText(usage.usedPercent)}
                  </span>
                </div>
                {level ? (
                  <span
                    className={`inline-flex items-center gap-1 self-start px-2 py-0.5 rounded-full text-xs font-bold ${
                      item.remainingPercent <= 5
                        ? 'bg-status-critical-bg text-status-critical'
                        : 'bg-status-warning-bg text-status-warning'
                    }`}
                  >
                    <AlertTriangle className="w-3.5 h-3.5" aria-hidden="true" />
                    {level}
                  </span>
                ) : (
                  <span className="inline-flex items-center gap-1 self-start px-2 py-0.5 rounded-full text-xs font-normal bg-status-healthy-bg text-status-healthy">
                    <CheckCircle2 className="w-3.5 h-3.5" aria-hidden="true" />
                    額度充足
                  </span>
                )}
              </div>
              <MiniRingChart
                value={item.remainingPercent}
                size={76}
                strokeWidth={7}
                gradientId={`drawer-ring-${item.id}`}
                gradientColors={ringColors}
                isCritical={item.remainingPercent <= 5}
                label={item.name}
              />
            </div>

            {/* Key Metrics Grid */}
            <div className="grid grid-cols-2 gap-2.5">
              <div className="p-3 rounded-xl bg-surface-canvas border border-border-hairline">
                <div className="text-xs text-ink-muted">模型</div>
                <div className="text-body font-bold text-ink-primary mt-0.5 break-words">{modelText(usage)}</div>
              </div>
              <div className="p-3 rounded-xl bg-surface-canvas border border-border-hairline">
                <div className="text-xs text-ink-muted">費用</div>
                <div className="text-body font-bold text-ink-primary tabular-nums mt-0.5">
                  {usage.feeText ?? '未提供'}
                </div>
              </div>
              <div className="p-3 rounded-xl bg-surface-canvas border border-border-hairline">
                <div className="text-xs text-ink-muted">5 小時用量</div>
                <div className="text-body font-bold text-ink-primary tabular-nums mt-0.5">
                  {percentText(usage.sessionUsed)}
                </div>
              </div>
              <div className="p-3 rounded-xl bg-surface-canvas border border-border-hairline">
                <div className="text-xs text-ink-muted">每週用量</div>
                <div className="text-body font-bold text-ink-primary tabular-nums mt-0.5">
                  {percentText(usage.weekUsed)}
                </div>
              </div>
            </div>

            {/* Reset Window Info */}
            {resetSummary && (
              <div className="p-3.5 rounded-xl bg-surface-canvas border border-border-hairline flex flex-col gap-1.5">
                <div className="text-xs font-bold text-ink-secondary">重置時間與免費重置</div>
                <div className="flex flex-wrap items-center justify-between gap-2 text-xs text-ink-primary tabular-nums">
                  <span>
                    {resetSummary.sessionText !== '--' ? `5 小時 ${resetSummary.sessionText} · ` : ''}
                    每週 {resetSummary.weeklyText}
                  </span>
                  {isMonitored && (
                    <span className="inline-flex items-center gap-1 font-bold text-status-healthy">
                      <Sparkles className="w-3.5 h-3.5" aria-hidden="true" />
                      {creditsLabel(resetSummary.resetCredits)}
                    </span>
                  )}
                </div>
              </div>
            )}

            {/* Token Pools Breakdown */}
            {pools.length > 0 && (
              <div className="flex flex-col gap-2">
                <div className="text-xs font-bold text-ink-secondary">配額池明細</div>
                <ul className="flex flex-col gap-2">
                  {pools.map((pool) => {
                    const rem = Math.min(100, Math.max(0, Math.round(pool.effectiveRemaining)));
                    const crit = pool.isCritical || rem <= 5;
                    return (
                      <li
                        key={pool.id}
                        className="p-3 rounded-xl bg-surface-canvas border border-border-hairline flex flex-col gap-1.5"
                      >
                        <div className="flex items-center justify-between gap-2 text-xs">
                          <span className="font-bold text-ink-primary truncate">{pool.name}</span>
                          <span
                            className={`font-mono font-bold tabular-nums shrink-0 ${
                              crit ? 'text-status-critical' : 'text-ink-primary'
                            }`}
                          >
                            剩餘 {rem}%
                          </span>
                        </div>
                        <div className="w-full h-1.5 rounded-full bg-surface-muted overflow-hidden">
                          <div
                            className={`h-full rounded-full ${
                              crit ? 'bg-status-critical' : 'bg-accent-primary'
                            }`}
                            style={{ width: `${Math.max(2, rem)}%` }}
                          />
                        </div>
                      </li>
                    );
                  })}
                </ul>
              </div>
            )}
          </div>

          {/* Footer Action */}
          <div className="shrink-0 px-4 py-3 border-t border-border-hairline bg-surface-chrome backdrop-blur-md flex justify-end">
            <button
              type="button"
              onClick={onClose}
              className="min-h-[44px] px-5 rounded-xl bg-accent-primary text-white text-body font-bold hover:opacity-90 focus:outline-none focus-visible:ring-2 focus-visible:ring-accent-primary"
            >
              完成
            </button>
          </div>
        </>
      ) : null}
    </dialog>
  );
};
