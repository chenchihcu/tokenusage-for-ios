import React, { useEffect, useState } from 'react';
import { QuotaCardProps } from './QuotaCard';
import { PlatformIcon } from './PlatformIcon';
import { extractResetWindowSummary } from '../utils/resetMonitor';
import { Clock, Sparkles } from 'lucide-react';

interface ResetMonitorBarProps {
  quotas: QuotaCardProps[];
  activePlatformId: string;
  onSelectPlatform: (id: string) => void;
}

const MONITORED_IDS = ['antigravity', 'codex', 'claude'] as const;

const ACCENT_MAP: Record<string, string> = {
  antigravity: 'text-purple-300 border-purple-500/40 bg-purple-950/40',
  codex: 'text-emerald-300 border-emerald-500/40 bg-emerald-950/40',
  claude: 'text-amber-300 border-amber-500/40 bg-amber-950/40',
};

/**
 * Antigravity · Codex · Claude Code 週期重置與免費釋放窗口即時監控列
 */
export const ResetMonitorBar: React.FC<ResetMonitorBarProps> = ({
  quotas,
  activePlatformId,
  onSelectPlatform,
}) => {
  const [nowMs, setNowMs] = useState<number>(() => Date.now());

  useEffect(() => {
    const timer = window.setInterval(() => setNowMs(Date.now()), 30_000);
    return () => window.clearInterval(timer);
  }, []);

  const monitored = MONITORED_IDS.map((id) => quotas.find((q) => q.id === id)).filter(
    (q): q is QuotaCardProps => Boolean(q)
  );

  if (monitored.length === 0) return null;

  return (
    <section
      aria-label="Antigravity 與 Codex、Claude Code 重置時間監控"
      className="w-full border-b border-slate-800/80 bg-slate-950/90 px-4 py-1.5 sm:px-6 pl-safe-island pr-safe-island phoneland:py-1 shrink-0"
    >
      <div className="max-w-7xl mx-auto flex items-center gap-2 overflow-x-auto no-scrollbar">
        <span className="inline-flex items-center gap-1 text-[10px] font-mono font-bold uppercase tracking-wider text-slate-400 shrink-0">
          <Clock className="w-3.5 h-3.5 text-cyan-400" aria-hidden="true" />
          <span className="hidden sm:inline">RESET MONITOR</span>
        </span>

        <div className="flex items-center gap-2">
          {monitored.map((item) => {
            const summary = extractResetWindowSummary(item, nowMs);
            const isActive = activePlatformId === item.id;
            const accent = ACCENT_MAP[item.id] || 'text-slate-200 border-slate-700 bg-slate-900';

            return (
              <button
                key={item.id}
                type="button"
                onClick={() => onSelectPlatform(item.id)}
                className={`inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full border text-[11px] font-mono transition-all min-h-[36px] phoneland:min-h-[32px] shrink-0 active:scale-95 touch-manipulation ${
                  isActive
                    ? `${accent} ring-1 ring-white/25`
                    : 'bg-slate-900/70 border-slate-800 text-slate-300 hover:border-slate-700'
                }`}
              >
                <PlatformIcon id={item.id} className="w-3.5 h-3.5 shrink-0" />
                <span className="font-bold text-slate-100">
                  {item.id === 'antigravity' ? 'Antigravity' : item.id === 'codex' ? 'Codex' : 'Claude Code'}
                </span>
                <span className="text-slate-500">·</span>
                <span className="text-slate-300">
                  5h <strong className="text-slate-100">{summary.sessionText}</strong>
                </span>
                <span className="text-slate-500">/</span>
                <span className="text-slate-300">
                  Wk <strong className="text-cyan-300">{summary.weeklyText}</strong>
                </span>
                {summary.isFreeResetReady ? (
                  <span className="inline-flex items-center gap-0.5 px-1.5 py-0.5 rounded-full bg-emerald-950/90 text-emerald-300 border border-emerald-500/50 text-[9px] font-bold">
                    <Sparkles className="w-2.5 h-2.5" aria-hidden="true" />
                    FREE
                  </span>
                ) : summary.isResettingSoon ? (
                  <span className="px-1.5 py-0.5 rounded-full bg-amber-950/80 text-amber-300 border border-amber-500/40 text-[9px] font-bold">
                    SOON
                  </span>
                ) : null}
              </button>
            );
          })}
        </div>
      </div>
    </section>
  );
};
