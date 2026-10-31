import React from 'react';
import { Mic, MicOff, RefreshCw } from 'lucide-react';
import { HandednessMode } from './ViewModeSelector';

interface FloatingActionToolbarProps {
  isVoiceActive: boolean;
  isSyncing: boolean;
  onToggleVoice: () => void;
  onSyncModels: () => void;
  handedness?: HandednessMode;
}

export const FloatingActionToolbar: React.FC<FloatingActionToolbarProps> = ({
  isVoiceActive,
  isSyncing,
  onToggleVoice,
  onSyncModels,
  handedness = 'right',
}) => {
  const triggerHaptic = () => {
    if (typeof window !== 'undefined' && 'navigator' in window && navigator.vibrate) {
      try {
        navigator.vibrate([12, 24]);
      } catch {}
    }
  };

  const handleVoiceClick = () => {
    triggerHaptic();
    onToggleVoice();
  };

  const handleSyncClick = () => {
    triggerHaptic();
    onSyncModels();
  };

  return (
    <aside
      aria-label="即時浮動控制列"
      className={`fixed bottom-6 z-50 flex items-center gap-3 p-2 bg-slate-900/90 backdrop-blur-2xl rounded-2xl border border-slate-700/80 shadow-2xl transition-all duration-300 ${
        handedness === 'left' ? 'left-6 flex-row-reverse' : 'right-6'
      }`}
    >
      {/* 動態同步模型按鈕 (熱區 48x48 pt) */}
      <button
        onClick={handleSyncClick}
        disabled={isSyncing}
        title="即時同步最新模型型錄"
        className="w-12 h-12 flex items-center justify-center rounded-xl bg-slate-800 text-slate-200 hover:text-white hover:bg-slate-700 active:scale-95 transition-all focus:outline-none focus:ring-2 focus:ring-cyan-500/50 border border-slate-700/60 touch-manipulation"
      >
        <RefreshCw className={`w-5 h-5 ${isSyncing ? 'animate-spin text-cyan-400' : 'text-slate-300'}`} />
      </button>

      {/* Gemini 3.8 Live 語音核心對話鈕 (主按鈕，熱區 54x54 pt) */}
      <button
        onClick={handleVoiceClick}
        title={isVoiceActive ? '結束實時語音通話' : '開啟 Gemini 3.8 Live 雙向語音'}
        className={`w-14 h-14 flex items-center justify-center rounded-2xl text-white shadow-lg active:scale-95 transition-all focus:outline-none focus:ring-4 focus:ring-cyan-500/30 touch-manipulation ${
          isVoiceActive
            ? 'bg-rose-500 hover:bg-rose-600 animate-pulse shadow-rose-500/40'
            : 'bg-gradient-to-tr from-cyan-500 via-blue-600 to-purple-600 hover:opacity-90 shadow-cyan-500/25'
        }`}
      >
        {isVoiceActive ? <MicOff className="w-6 h-6" /> : <Mic className="w-6 h-6" />}
      </button>
    </aside>
  );
};
