import React from 'react';
import { LayoutGrid, Columns2, Hand } from 'lucide-react';

export type DashboardViewMode = 'cockpit' | 'split';
export type HandednessMode = 'right' | 'left' | 'dual';

export interface ViewModeSelectorProps {
  currentMode: DashboardViewMode;
  onChangeMode: (mode: DashboardViewMode) => void;
  governingAlertCount?: number;
  handedness?: HandednessMode;
  onChangeHandedness?: (mode: HandednessMode) => void;
}

export const ViewModeSelector: React.FC<ViewModeSelectorProps> = ({
  currentMode,
  onChangeMode,
  governingAlertCount = 0,
  handedness = 'right',
  onChangeHandedness,
}) => {
  const triggerHaptic = (ms = 10) => {
    if (typeof window !== 'undefined' && 'navigator' in window && navigator.vibrate) {
      try {
        navigator.vibrate(ms);
      } catch {}
    }
  };

  const handleSelectMode = (mode: DashboardViewMode) => {
    triggerHaptic(10);
    onChangeMode(mode);
  };

  const handleToggleHandedness = () => {
    triggerHaptic(15);
    if (!onChangeHandedness) return;
    const nextHandedness: HandednessMode =
      handedness === 'right' ? 'left' : handedness === 'left' ? 'dual' : 'right';
    onChangeHandedness(nextHandedness);
  };

  return (
    <nav
      aria-label="視圖模式切換器"
      className={`inline-flex items-center p-1 rounded-xl bg-slate-900/90 border border-slate-800/90 shadow-inner backdrop-blur-md select-none transition-all ${
        handedness === 'left' ? 'flex-row-reverse' : ''
      }`}
    >
      {/* 模式 A：全景駕駛艙 (Includes All) - Apple HIG ≥ 44pt 觸控熱區 */}
      <button
        type="button"
        onClick={() => handleSelectMode('cockpit')}
        aria-pressed={currentMode === 'cockpit'}
        className={`relative flex items-center justify-center gap-1.5 px-3.5 py-2 rounded-lg text-xs font-semibold transition-all min-h-[44px] active:scale-95 touch-manipulation ${
          currentMode === 'cockpit'
            ? 'bg-gradient-to-r from-cyan-500/20 to-blue-500/20 text-cyan-300 border border-cyan-500/40 shadow-[0_0_12px_rgba(6,182,212,0.25)]'
            : 'text-slate-400 hover:text-slate-200 hover:bg-slate-800/50'
        }`}
      >
        <LayoutGrid className="w-4 h-4" />
        <span className="tracking-wide">ALL 全景</span>
        {governingAlertCount > 0 && (
          <span
            className="flex h-2 w-2 relative ml-0.5"
            title={`${governingAlertCount} 個平台處於耗盡或告警狀態`}
          >
            <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-rose-400 opacity-75"></span>
            <span className="relative inline-flex rounded-full h-2 w-2 bg-rose-500"></span>
          </span>
        )}
      </button>

      {/* 模式 B：雙欄深入工作台 (Duo Split) - Apple HIG ≥ 44pt 觸控熱區 */}
      <button
        type="button"
        onClick={() => handleSelectMode('split')}
        aria-pressed={currentMode === 'split'}
        className={`flex items-center justify-center gap-1.5 px-3.5 py-2 rounded-lg text-xs font-semibold transition-all min-h-[44px] active:scale-95 touch-manipulation ${
          currentMode === 'split'
            ? 'bg-gradient-to-r from-purple-500/20 to-pink-500/20 text-purple-300 border border-purple-500/40 shadow-[0_0_12px_rgba(168,85,247,0.25)]'
            : 'text-slate-400 hover:text-slate-200 hover:bg-slate-800/50'
        }`}
      >
        <Columns2 className="w-4 h-4" />
        <span className="tracking-wide">DUO 雙欄</span>
      </button>

      {/* 單手握持慣用手切換按鈕 (Apple HIG Reachability Handedness Toggle) */}
      {onChangeHandedness && (
        <button
          type="button"
          onClick={handleToggleHandedness}
          title={`單手握持模式: 當前為【${
            handedness === 'right' ? '右手握持' : handedness === 'left' ? '左手握持' : '雙手握持'
          }】，點擊切換`}
          className="flex items-center justify-center px-2 py-2 ml-1 text-slate-400 hover:text-cyan-300 hover:bg-slate-800/60 rounded-lg transition-all min-h-[44px] min-w-[44px] active:scale-95 touch-manipulation"
          aria-label={`單手握持模式: ${handedness}`}
        >
          <Hand className="w-3.5 h-3.5" />
          <span className="text-[10px] font-mono font-bold uppercase ml-1">
            {handedness === 'right' ? 'RH' : handedness === 'left' ? 'LH' : 'DUO'}
          </span>
        </button>
      )}
    </nav>
  );
};
