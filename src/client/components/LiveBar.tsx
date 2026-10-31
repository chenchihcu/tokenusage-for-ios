import React from 'react';
import { RefreshCw, Activity, Volume2 } from 'lucide-react';

export interface LiveBarSegment {
  id: string;
  name: string;
  remainingPercent: number;
  gradient: string;
  glowColor: string;
  isAlert?: boolean;
  label?: string;
}

export interface LiveBarProps {
  segments: LiveBarSegment[];
  activePlatformId: string;
  onSelectPlatform: (id: string) => void;
  countdownSeconds: number;
  isSyncing: boolean;
  onTriggerSync: () => void;
  isVoiceActive: boolean;
  audioLevels?: number[];
  isOnline?: boolean;
}

export const LiveBar: React.FC<LiveBarProps> = ({
  segments,
  activePlatformId,
  onSelectPlatform,
  countdownSeconds,
  isSyncing,
  onTriggerSync,
  isVoiceActive,
  audioLevels = [],
  isOnline = true,
}) => {
  return (
    <div className="w-full bg-slate-950/90 border-b border-slate-800/80 backdrop-blur-xl relative z-20 overflow-hidden">
      {/* 頂部極細發光光子掃描射線 */}
      <div className="absolute top-0 left-0 right-0 h-[2px] bg-slate-900 overflow-hidden">
        <div className={`h-full w-1/3 photon-beam ${isSyncing ? 'animate-photon-sweep' : 'opacity-40 animate-pulse'}`} />
      </div>

      <div className="max-w-7xl mx-auto px-4 py-2 sm:py-2.5 flex flex-col sm:flex-row sm:items-center justify-between gap-2">
        {/* 左側：LIVE 心跳徽章與倒數 */}
        <div className="flex items-center gap-3">
          <button
            type="button"
            onClick={onTriggerSync}
            disabled={isSyncing || !isOnline}
            className={`flex items-center gap-1.5 px-2.5 py-1 rounded-full border text-xs transition-all group ${
              isOnline
                ? 'bg-slate-900 border-slate-800 text-slate-300 hover:text-white hover:border-slate-700'
                : 'bg-amber-950/40 border-amber-600/40 text-amber-300'
            }`}
            title={isOnline ? '點擊立即加速更新' : '離線模式：當前使用本機離線快取'}
          >
            {isOnline ? (
              <>
                <span className="relative flex h-2 w-2">
                  <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75"></span>
                  <span className="relative inline-flex rounded-full h-2 w-2 bg-emerald-500"></span>
                </span>
                <span className="font-mono text-[11px] font-bold tracking-wider text-emerald-400 uppercase">
                  LIVE
                </span>
                <span className="tabular-nums font-mono text-[11px] text-slate-400 group-hover:text-cyan-300">
                  {countdownSeconds > 0 ? `${countdownSeconds}s` : '手動'}
                </span>
                <RefreshCw className={`w-3 h-3 text-slate-400 group-hover:text-cyan-400 transition-transform ${isSyncing ? 'animate-spin' : ''}`} />
              </>
            ) : (
              <>
                <span className="relative inline-flex rounded-full h-2 w-2 bg-amber-400"></span>
                <span className="font-mono text-[11px] font-bold tracking-wider text-amber-400">
                  離線快取
                </span>
                <span className="text-[10px] text-amber-400/80">
                  (暫停輪詢)
                </span>
              </>
            )}
          </button>

          <span className="text-[11px] font-medium text-slate-400 hidden md:inline-flex items-center gap-1">
            <Activity className="w-3 h-3 text-cyan-400" />
            全景 5 大平台算力即時光譜
          </span>
        </div>

        {/* 中間/右側：動態狀態光譜條 (或語音音波模式) */}
        <div className="flex-1 max-w-xl mx-auto sm:mx-0 w-full flex items-center gap-2">
          {isVoiceActive ? (
            /* 語音等化器音波形變模式 (Gemini 3.8 Live Equalizer) */
            <div className="w-full flex items-center justify-center gap-1 py-1 px-3 rounded-xl bg-purple-950/40 border border-purple-500/40">
              <Volume2 className="w-3.5 h-3.5 text-purple-400 animate-pulse shrink-0" />
              <div className="flex items-center justify-center gap-0.5 h-5 flex-1">
                {[...Array(24)].map((_, i) => {
                  const level = audioLevels[i] || ((i % 5) + 1) * 0.18;
                  const barHeight = Math.max(15, Math.min(100, Math.round(level * 100)));
                  return (
                    <div
                      key={i}
                      className="w-1.5 rounded-full bg-gradient-to-t from-purple-500 via-pink-400 to-cyan-300 transition-all duration-75"
                      style={{
                        height: `${barHeight}%`,
                        opacity: 0.7 + (level * 0.3)
                      }}
                    />
                  );
                })}
              </div>
              <span className="text-[10px] font-mono text-purple-300 font-semibold uppercase tracking-wider shrink-0">
                Gemini 3.8 Live Streaming
              </span>
            </div>
          ) : (
            /* 5 色等比配額動態光譜條 (Multi-Segment Live Bar) */
            <div className="w-full flex items-center gap-1.5 p-1 rounded-xl bg-slate-900/90 border border-slate-800/80 shadow-inner">
              {segments.map((seg) => {
                const isActive = seg.id === activePlatformId;
                const isAlert = seg.isAlert || seg.remainingPercent <= 10;
                return (
                  <button
                    key={seg.id}
                    type="button"
                    onClick={() => onSelectPlatform(seg.id)}
                    className={`group relative flex-1 flex flex-col gap-0.5 px-2 py-1 rounded-lg transition-all text-left ${
                      isActive
                        ? 'bg-slate-800/90 ring-1 ring-cyan-500/40 shadow-lg'
                        : 'hover:bg-slate-800/50'
                    }`}
                    title={`${seg.name}: 剩餘 ${seg.remainingPercent}%${seg.label ? ` (${seg.label})` : ''}`}
                  >
                    <div className="flex items-center justify-between text-[10px]">
                      <span className="font-semibold truncate text-slate-300 group-hover:text-white">
                        {seg.name.split(' ')[0]}
                      </span>
                      <span
                        className={`tabular-nums font-mono font-bold ${
                          isAlert ? 'text-rose-400 animate-pulse' : 'text-slate-400'
                        }`}
                      >
                        {seg.remainingPercent}%
                      </span>
                    </div>

                    {/* 彩色進度條軌道 */}
                    <div className="w-full h-1.5 rounded-full bg-slate-950 overflow-hidden relative">
                      <div
                        className={`h-full rounded-full transition-all duration-500 ${seg.gradient} ${
                          isAlert ? 'animate-pulse' : ''
                        }`}
                        style={{
                          width: `${Math.max(4, seg.remainingPercent)}%`,
                          boxShadow: seg.glowColor,
                        }}
                      />
                    </div>
                  </button>
                );
              })}
            </div>
          )}
        </div>
      </div>
    </div>
  );
};
