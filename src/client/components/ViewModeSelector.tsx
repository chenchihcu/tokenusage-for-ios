import React from 'react';
import { LayoutGrid, Columns2 } from 'lucide-react';

export type DashboardViewMode = 'cockpit' | 'split';

interface ViewModeSelectorProps {
  currentMode: DashboardViewMode;
  onChangeMode: (mode: DashboardViewMode) => void;
  governingAlertCount?: number;
}

export const ViewModeSelector: React.FC<ViewModeSelectorProps> = ({
  currentMode,
  onChangeMode,
  governingAlertCount = 0,
}) => {
  const triggerHaptic = () => {
    if (typeof window !== 'undefined' && 'navigator' in window && navigator.vibrate) {
      try {
        navigator.vibrate(10);
      } catch {}
    }
  };

  const handleSelect = (mode: DashboardViewMode) => {
    triggerHaptic();
    onChangeMode(mode);
  };

  return (
    <nav
      aria-label="視圖模式切換器"
      className="inline-flex items-center p-1 rounded-xl bg-slate-900/90 border border-slate-800/90 shadow-inner backdrop-blur-md"
    >
      {/* 模式 A：全景駕駛艙 (Includes All) */}
      <button
        type="button"
        onClick={() => handleSelect('cockpit')}
        aria-pressed={currentMode === 'cockpit'}
        className={`relative flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-semibold transition-all min-h-[36px] active:scale-95 ${
          currentMode === 'cockpit'
            ? 'bg-gradient-to-r from-cyan-500/20 to-blue-500/20 text-cyan-300 border border-cyan-500/40 shadow-[0_0_12px_rgba(6,182,212,0.25)]'
            : 'text-slate-400 hover:text-slate-200 hover:bg-slate-800/50'
        }`}
      >
        <LayoutGrid className="w-3.5 h-3.5" />
        <span className="tracking-wide">ALL 全景</span>
        {governingAlertCount > 0 && (
          <span
            className="flex h-2 w-2 relative"
            title={`${governingAlertCount} 個平台處於耗盡或告警狀態`}
          >
            <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-rose-400 opacity-75"></span>
            <span className="relative inline-flex rounded-full h-2 w-2 bg-rose-500"></span>
          </span>
        )}
      </button>

      {/* 模式 B：雙欄深入工作台 (Duo Split) */}
      <button
        type="button"
        onClick={() => handleSelect('split')}
        aria-pressed={currentMode === 'split'}
        className={`flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-semibold transition-all min-h-[36px] active:scale-95 ${
          currentMode === 'split'
            ? 'bg-gradient-to-r from-purple-500/20 to-pink-500/20 text-purple-300 border border-purple-500/40 shadow-[0_0_12px_rgba(168,85,247,0.25)]'
            : 'text-slate-400 hover:text-slate-200 hover:bg-slate-800/50'
        }`}
      >
        <Columns2 className="w-3.5 h-3.5" />
        <span className="tracking-wide">DUO 雙欄</span>
      </button>
    </nav>
  );
};
