import React from 'react';
import { Mic, MicOff, RefreshCw, Sparkles } from 'lucide-react';

interface FloatingActionToolbarProps {
  isVoiceActive: boolean;
  isSyncing: boolean;
  onToggleVoice: () => void;
  onSyncModels: () => void;
}

export const FloatingActionToolbar: React.FC<FloatingActionToolbarProps> = ({
  isVoiceActive,
  isSyncing,
  onToggleVoice,
  onSyncModels,
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
      className="fixed bottom-6 right-6 z-50 flex items-center gap-3 p-2 bg-white/90 backdrop-blur-md rounded-2xl border border-[#e5e5ea] shadow-lg transition-apple"
    >
      {/* 動態同步模型按鈕 (熱區 48x48 pt) */}
      <button
        onClick={handleSyncClick}
        disabled={isSyncing}
        title="即時同步最新模型型錄"
        className="w-12 h-12 flex items-center justify-center rounded-xl bg-[#f5f5f7] text-[#1d1d1f] hover:bg-[#e5e5ea] active:scale-95 transition-all focus:outline-none focus:ring-2 focus:ring-[#0071e3]"
      >
        <RefreshCw className={`w-5 h-5 ${isSyncing ? 'animate-spin text-[#0071e3]' : ''}`} />
      </button>

      {/* Gemini 3.8 Live 語音核心對話鈕 (主按鈕，熱區 52x52 pt) */}
      <button
        onClick={handleVoiceClick}
        title={isVoiceActive ? '結束實時語音通話' : '開啟 Gemini 3.8 Live 雙向語音'}
        className={`w-14 h-14 flex items-center justify-center rounded-2xl text-white shadow-md active:scale-95 transition-all focus:outline-none focus:ring-4 focus:ring-blue-200 ${
          isVoiceActive
            ? 'bg-rose-500 hover:bg-rose-600 animate-pulse'
            : 'bg-[#0071e3] hover:bg-[#0077ed]'
        }`}
      >
        {isVoiceActive ? <MicOff className="w-6 h-6" /> : <Mic className="w-6 h-6" />}
      </button>
    </aside>
  );
};
