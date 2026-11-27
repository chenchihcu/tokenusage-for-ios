import React, { useEffect, useState } from 'react';
import { QuotaCardProps } from './QuotaCard';
import { PlatformIcon } from './PlatformIcon';
import { extractResetWindowSummary } from '../utils/resetMonitor';
import { Gift } from 'lucide-react';

interface ResetMonitorBarProps {
  quotas: QuotaCardProps[];
  activePlatformId: string;
  onSelectPlatform: (id: string) => void;
}

/** Codex and Claude Code: vendor free-reset credits and reset windows. */
export const MONITORED_RESET_IDS = ['codex', 'claude'] as const;

const NAMES: Record<string, string> = { codex: 'Codex', claude: 'Claude Code' };

export function creditsLabel(credits: number | null): string {
  return credits === null ? '免費重置：不提供' : `免費重置 ${credits} 次`;
}

export const ResetMonitorBar: React.FC<ResetMonitorBarProps> = ({ quotas, activePlatformId, onSelectPlatform }) => {
  const [nowMs, setNowMs] = useState<number>(() => Date.now());

  useEffect(() => {
    const timer = window.setInterval(() => setNowMs(Date.now()), 30_000);
    return () => window.clearInterval(timer);
  }, []);

  const monitored = MONITORED_RESET_IDS.map((id) => quotas.find((q) => q.id === id)).filter(
    (q): q is QuotaCardProps => Boolean(q),
  );
  if (monitored.length === 0) return null;

  return (
    <section
      aria-label="Codex 與 Claude Code 免費重置與重置時間"
      className="w-full border-b border-slate-800/80 bg-slate-950/90 px-4 py-1.5 sm:px-6 pl-safe-island pr-safe-island shrink-0 fab-clearance-side"
    >
      <div className="max-w-7xl mx-auto flex flex-wrap items-center gap-2">
        {monitored.map((item) => {
          const s = extractResetWindowSummary(item, nowMs);
          const hasCredits = (s.resetCredits ?? 0) > 0;
          const isActive = activePlatformId === item.id;
          return (
            <button
              key={item.id}
              type="button"
              onClick={() => onSelectPlatform(item.id)}
              aria-pressed={isActive}
              aria-label={`${NAMES[item.id]}，${creditsLabel(s.resetCredits)}，5 小時 ${s.sessionText}，每週 ${s.weeklyText}`}
              className={`inline-flex flex-wrap items-center gap-x-2 gap-y-0.5 px-3 py-1 rounded-xl border text-xs min-h-[44px] touch-manipulation ${
                isActive ? 'border-cyan-500/60 bg-slate-900' : 'border-slate-800 bg-slate-900/60'
              }`}
            >
              <span className="inline-flex items-center gap-1.5 font-bold text-slate-100">
                <PlatformIcon id={item.id} className="w-4 h-4 shrink-0" />
                {NAMES[item.id]}
              </span>
              <span
                className={`inline-flex items-center gap-1 font-bold ${hasCredits ? 'text-emerald-300' : 'text-slate-400'}`}
              >
                <Gift className="w-3.5 h-3.5" aria-hidden="true" />
                {creditsLabel(s.resetCredits)}
              </span>
              <span className="text-slate-300 tabular-nums">
                5h {s.sessionText} · 週 {s.weeklyText}
              </span>
            </button>
          );
        })}
      </div>
    </section>
  );
};
