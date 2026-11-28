import React, { useState, useRef, useEffect } from 'react';
import { Clock, Check, ChevronDown, Zap } from 'lucide-react';

export type RefreshIntervalSeconds = 600 | 3600 | 7200 | 0;

export const DEFAULT_REFRESH_INTERVAL: RefreshIntervalSeconds = 600;

export interface RefreshOption {
  value: RefreshIntervalSeconds;
  label: string;
  description: string;
  recommended?: boolean;
}

export const REFRESH_OPTIONS: RefreshOption[] = [
  { value: 600, label: '10 分鐘', description: '標準平衡（推薦）', recommended: true },
  { value: 3600, label: '60 分鐘', description: '每小時背景同步' },
  { value: 7200, label: '2 小時', description: '長效節能觀察' },
  { value: 0, label: '手動更新', description: '僅點擊時刷新' },
];

export function normalizeRefreshInterval(raw: string | number | null | undefined): RefreshIntervalSeconds {
  if (raw === null || raw === undefined || raw === '') return DEFAULT_REFRESH_INTERVAL;
  const parsed = Number(raw);
  return REFRESH_OPTIONS.some((o) => o.value === parsed)
    ? (parsed as RefreshIntervalSeconds)
    : DEFAULT_REFRESH_INTERVAL;
}

function formatCountdown(seconds: number): string {
  const s = Math.max(0, Math.floor(seconds));
  if (s >= 3600) {
    const h = Math.floor(s / 3600);
    const m = Math.floor((s % 3600) / 60);
    return m > 0 ? `${h}h${m}m` : `${h}h`;
  }
  if (s >= 60) {
    const m = Math.floor(s / 60);
    const rem = s % 60;
    return rem > 0 ? `${m}m${rem}s` : `${m}m`;
  }
  return `${s}s`;
}

export const STORAGE_KEY_REFRESH_INTERVAL = 'opentokenusage_refresh_interval_sec';

interface FrequencySelectorProps {
  interval: RefreshIntervalSeconds;
  onChangeInterval: (newInterval: RefreshIntervalSeconds) => void;
  countdownSeconds: number;
}

export const FrequencySelector: React.FC<FrequencySelectorProps> = ({
  interval,
  onChangeInterval,
  countdownSeconds,
}) => {
  const [isOpen, setIsOpen] = useState(false);
  const containerRef = useRef<HTMLDivElement>(null);

  const currentOption = REFRESH_OPTIONS.find(o => o.value === interval) || REFRESH_OPTIONS[0];

  useEffect(() => {
    const handleClickOutside = (e: MouseEvent) => {
      if (containerRef.current && !containerRef.current.contains(e.target as Node)) {
        setIsOpen(false);
      }
    };
    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, []);

  const handleSelect = (val: RefreshIntervalSeconds) => {
    onChangeInterval(val);
    setIsOpen(false);
    if (typeof window !== 'undefined' && 'navigator' in window && navigator.vibrate) {
      try { navigator.vibrate(12); } catch {}
    }
  };

  return (
    <div className="relative inline-block text-left" ref={containerRef}>
      <button
        type="button"
        onClick={() => setIsOpen(!isOpen)}
        className="flex items-center gap-2 px-3 py-1.5 rounded-xl bg-slate-800/80 hover:bg-slate-700/80 border border-slate-700/80 text-slate-200 text-xs font-medium whitespace-nowrap transition-all shadow-sm focus:outline-none focus:ring-2 focus:ring-cyan-500/50 min-h-[44px]"
        title="調整 Token 用量自動更新頻率"
      >
        <Clock className="w-3.5 h-3.5 text-cyan-400 animate-pulse" />
        <span className="tabular-nums font-semibold text-slate-100">
          {currentOption.label}
        </span>
        {interval > 0 && (
          <span className="hidden sm:inline-block px-1.5 py-0.5 rounded-md bg-cyan-950/80 border border-cyan-500/40 text-[10px] text-cyan-300 font-mono tabular-nums">
            {formatCountdown(countdownSeconds)}
          </span>
        )}
        <ChevronDown className={`w-3 h-3 text-slate-400 transition-transform ${isOpen ? 'rotate-180' : ''}`} />
      </button>

      {isOpen && (
        <div className="absolute right-0 mt-2 w-64 rounded-2xl glass-panel shadow-2xl border border-slate-700/80 z-50 overflow-hidden py-1.5 backdrop-blur-2xl animate-in fade-in zoom-in-95 duration-150">
          <div className="px-3 py-2 border-b border-slate-800/80 flex items-center justify-between">
            <span className="text-[11px] font-semibold text-slate-300 uppercase tracking-wider flex items-center gap-1.5">
              <Zap className="w-3 h-3 text-cyan-400" /> 更新頻率設定
            </span>
            <span className="text-[10px] text-slate-500 font-mono">localStorage</span>
          </div>

          <div className="py-1">
            {REFRESH_OPTIONS.map((opt) => {
              const isSelected = opt.value === interval;
              return (
                <button
                  key={opt.value}
                  type="button"
                  onClick={() => handleSelect(opt.value)}
                  className={`w-full text-left px-3.5 py-2 flex items-center justify-between transition-colors min-h-[44px] ${
                    isSelected ? 'bg-cyan-950/60 text-cyan-300' : 'text-slate-200 hover:bg-slate-800/60'
                  }`}
                >
                  <div className="flex flex-col">
                    <div className="flex items-center gap-2">
                      <span className="text-xs font-semibold">{opt.label}</span>
                      {opt.recommended && (
                        <span className="text-[9px] px-1.5 py-0.2 rounded-full bg-emerald-950/80 text-emerald-300 border border-emerald-500/40">
                          推薦
                        </span>
                      )}
                    </div>
                    <span className="text-[10px] text-slate-400">{opt.description}</span>
                  </div>
                  {isSelected && <Check className="w-4 h-4 text-cyan-400 shrink-0" />}
                </button>
              );
            })}
          </div>
        </div>
      )}
    </div>
  );
};
