import React, { useEffect, useState } from 'react';
import { QuotaCardProps } from './QuotaCard';
import { PlatformIcon } from './PlatformIcon';
import { extractResetWindowSummary } from '../utils/resetMonitor';

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
      className="w-full min-w-0 max-w-full h-12 phoneland:h-11 overflow-hidden border-b border-border-hairline bg-surface-canvas px-4 sm:px-6 pl-safe-island pr-safe-island shrink-0 fab-clearance-side"
    >
      <div className="max-w-7xl mx-auto flex flex-nowrap items-center gap-2 h-full min-w-0">
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
              className={`inline-flex min-w-0 flex-1 items-center gap-1.5 h-11 px-2.5 rounded-xl border text-xs overflow-hidden transition-colors focus:outline-none focus-visible:ring-2 focus-visible:ring-accent-primary ${
                isActive
                  ? 'border-accent-primary bg-surface-card shadow-hig-card'
                  : 'border-border-hairline bg-surface-card/70 hover:bg-surface-card'
              }`}
            >
              <PlatformIcon id={item.id} className="w-4 h-4 shrink-0" />
              <span className={`min-w-0 flex-1 truncate text-xs font-bold tabular-nums ${hasCredits ? 'text-status-healthy' : 'text-ink-primary'}`}>
                {`${NAMES[item.id]} ${creditsLabel(s.resetCredits)} 5h ${s.sessionText} · 週 ${s.weeklyText}`}
              </span>
            </button>
          );
        })}
      </div>
    </section>
  );
};
