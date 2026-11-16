import React, { useState } from 'react';
import { QuotaCardProps } from './QuotaCard';
import { AudioVisualizer } from './AudioVisualizer';
import { MiniRingChart } from './MiniRingChart';
import { TokenPool } from '../../types/quota';
import { HandednessMode } from './ViewModeSelector';
import { haptic } from '../services/haptics';
import { PlatformIcon } from './PlatformIcon';
import { extractResetWindowSummary } from '../utils/resetMonitor';
import {
  PanelLeftClose,
  PanelLeftOpen,
  BrainCircuit,
  Activity,
  Zap,
  Clock,
  Sparkles,
  AlertTriangle,
  Link2,
  Layers,
} from 'lucide-react';

interface DetailWorkbenchProps {
  selectedItem: QuotaCardProps | undefined;
  isFocusMode: boolean;
  onToggleFocus: () => void;
  isVoiceActive: boolean;
  liveTranscript: string;
  handedness?: HandednessMode;
  connectionLabel?: string;
}

interface ParsedMetric {
  label: string;
  used?: number;
  limit?: number;
  kind?: string;
  value?: string;
  isAlert?: boolean;
}

export const DetailWorkbench: React.FC<DetailWorkbenchProps> = ({
  selectedItem,
  isFocusMode,
  onToggleFocus,
  isVoiceActive,
  liveTranscript,
  handedness = 'right',
  connectionLabel = '待確認',
}) => {
  const [thinkingBudget, setThinkingBudget] = useState<number>(32768);

  if (!selectedItem) {
    return (
      <div className="flex flex-col items-center justify-center h-full p-8 text-center text-slate-500 bg-slate-950 select-none">
        <Activity className="w-10 h-10 text-slate-700 mb-2 animate-pulse" />
        <h3 className="font-bold text-sm text-slate-300 uppercase tracking-wider">SELECT PLATFORM</h3>
      </div>
    );
  }

  // 解析真實帳號多配額池 (Token Pools)
  let parsedPools: TokenPool[] = [];
  if (selectedItem.token_pools_json) {
    try {
      const parsed = JSON.parse(selectedItem.token_pools_json);
      if (Array.isArray(parsed)) {
        parsedPools = parsed;
      }
    } catch {
      parsedPools = [];
    }
  }

  // 解析真實帳號多維度指標 (作為後備)
  let parsedMetrics: ParsedMetric[] = [];
  if (selectedItem.metrics_json) {
    try {
      parsedMetrics = JSON.parse(selectedItem.metrics_json);
    } catch {
      parsedMetrics = [];
    }
  }

  // 格式化重置時間戳
  let displayReset = selectedItem.resetTime;
  if (selectedItem.resetTime && selectedItem.resetTime.includes('T')) {
    try {
      const d = new Date(selectedItem.resetTime);
      displayReset = `${d.getFullYear()}/${d.getMonth() + 1}/${d.getDate()} ${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')} 重置`;
    } catch {
      displayReset = selectedItem.resetTime;
    }
  }

  const handleSelectPreset = (tokens: number) => {
    haptic.impactMedium();
    setThinkingBudget(tokens);
  };

  return (
    <div className="flex flex-col h-full bg-slate-950 overflow-y-auto text-slate-100 select-none pb-24">
      {/* 頂部工具列 (Apple HIG ≥ 44pt 觸控熱區) */}
      <div
        className={`flex items-center justify-between p-3 sm:p-4 phoneland:p-2 border-b border-slate-800/80 sticky top-0 bg-slate-950/90 backdrop-blur-xl z-10 ${
          handedness === 'left' ? 'flex-row-reverse' : ''
        }`}
      >
        <div className="flex items-center gap-3">
          <button
            onClick={() => {
              haptic.impactLight();
              onToggleFocus();
            }}
            title={isFocusMode ? '展開導航欄' : '進入專注全寬模式 (Focus Mode)'}
            className="p-2 rounded-xl text-slate-400 hover:text-white hover:bg-slate-800/60 active:scale-95 transition-all min-h-[44px] min-w-[44px] flex items-center justify-center touch-manipulation"
          >
            {isFocusMode ? <PanelLeftOpen className="w-5 h-5 text-cyan-400" /> : <PanelLeftClose className="w-5 h-5" />}
          </button>
          <div>
            <h2 id="detail-title" tabIndex={-1} className="font-bold text-lg text-white tracking-tight flex items-center gap-2 outline-none">
              <span className="p-1.5 rounded-lg bg-slate-900 border border-slate-700/80 text-cyan-300 shrink-0">
                <PlatformIcon id={selectedItem.id} className="w-4 h-4" />
              </span>
              {selectedItem.name}
              <span className="text-xs font-semibold px-2 py-0.5 rounded-full bg-cyan-950/60 text-cyan-300 border border-cyan-500/40">
                {selectedItem.planName}
              </span>
              {selectedItem.id === 'grok' && (
                <span className="flex items-center gap-1 text-[11px] px-2 py-0.5 rounded-full bg-pink-950/60 text-pink-300 border border-pink-500/40">
                  <Link2 className="w-3 h-3 text-cyan-400" />
                  Bonded with Cursor
                </span>
              )}
            </h2>
          </div>
        </div>

        <div className="flex items-center gap-2">
          <span className="flex items-center gap-1.5 text-xs font-semibold px-2.5 py-1.5 rounded-full bg-emerald-950/60 text-emerald-300 border border-emerald-500/40 min-h-[36px]">
            <span className="w-2 h-2 rounded-full bg-emerald-400 animate-pulse" />
            {connectionLabel}
          </span>
        </div>
      </div>

      <div className="p-4 sm:p-6 phoneland:p-3 space-y-5 phoneland:space-y-3 max-w-4xl mx-auto w-full">
        {/* 即時語音互動與波形面板 */}
        <section className="space-y-3">
          <AudioVisualizer isActive={isVoiceActive} volume={isVoiceActive ? 0.75 : 0} />

          {/* 即時字幕面板 */}
          <div className="p-3 sm:p-4 rounded-2xl glass-panel border border-slate-800/80">
            <div className="flex items-center gap-2 mb-1.5 text-xs font-semibold text-slate-400 uppercase tracking-wider font-mono">
              <Sparkles className="w-3.5 h-3.5 text-cyan-400" />
              LIVE TRANSCRIPT 字幕
            </div>
            <p className="text-sm leading-relaxed text-slate-200 min-h-[36px] font-mono text-xs">
              {liveTranscript || (isVoiceActive ? 'LISTENING 正在聆聽語音...' : 'STANDBY 語音休眠中')}
            </p>
          </div>
        </section>

        {/* 核心高保真數據卡片格線 (Governing Bottleneck) */}
        <section className="grid grid-cols-1 sm:grid-cols-3 gap-3 sm:gap-4">
          <div className="p-4 rounded-2xl glass-panel border border-slate-800/80 flex items-center justify-between">
            <div>
              <div className="flex items-center gap-1.5 text-xs text-slate-400 mb-1">
                <span className="font-mono text-[10px] uppercase font-bold">REMAINING 有效剩餘</span>
                <Activity className="w-3.5 h-3.5 text-cyan-400" />
              </div>
              <div className={`text-3xl font-black font-mono tabular-nums ${selectedItem.remainingPercent <= 5 ? 'text-rose-400 animate-pulse' : 'text-white'}`}>
                {selectedItem.remainingPercent}%
              </div>
              <div className={`text-[11px] font-medium mt-1 ${selectedItem.remainingPercent <= 5 ? 'text-rose-400' : selectedItem.remainingPercent < 20 ? 'text-amber-400' : 'text-emerald-400'}`}>
                {selectedItem.remainingPercent <= 5 ? 'CRITICAL EXHAUSTED' : selectedItem.remainingPercent < 20 ? 'LOW WATERMARK' : 'HEALTHY'}
              </div>
            </div>
            <MiniRingChart
              value={selectedItem.remainingPercent}
              size={56}
              strokeWidth={5}
              gradientId={`detail-ring-${selectedItem.id}`}
              gradientColors={
                selectedItem.id === 'codex'
                  ? ['#00FF87', '#60EFFF']
                  : selectedItem.id === 'antigravity'
                  ? ['#4285F4', '#A855F7']
                  : selectedItem.id === 'claude'
                  ? ['#F59E0B', '#FB923C']
                  : selectedItem.id === 'grok'
                  ? ['#FF007A', '#7928CA']
                  : ['#00F2FE', '#4FACFE']
              }
              isCritical={selectedItem.remainingPercent <= 5}
              showCenterText={false}
              compact={true}
            />
          </div>

          <div className="p-4 rounded-2xl glass-panel border border-slate-800/80">
            <div className="flex items-center justify-between text-xs text-slate-400 mb-1">
              <span className="font-mono text-[10px] uppercase font-bold">USED / BASE 已用比例</span>
              <Zap className="w-4 h-4 text-amber-400" />
            </div>
            <div className="text-3xl font-black font-mono tabular-nums text-white">
              {selectedItem.usedQuota}%
            </div>
            <div className="text-xs text-slate-400 mt-1 font-mono">基準循環 100%</div>
          </div>

          <div className="p-4 rounded-2xl glass-panel border border-slate-800/80">
            <div className="flex items-center justify-between text-xs text-slate-400 mb-1">
              <span className="font-mono text-[10px] uppercase font-bold">RESET TIME 週期重置</span>
              <Clock className="w-4 h-4 text-purple-400" />
            </div>
            {(() => {
              const win = extractResetWindowSummary(selectedItem);
              return (
                <>
                  <div className="text-sm font-bold font-mono text-slate-100 truncate mt-1.5">
                    {displayReset}
                  </div>
                  <div className="flex flex-wrap items-center gap-1.5 mt-1.5 text-[11px] font-mono">
                    {win.sessionText !== '--' && (
                      <span className="px-1.5 py-0.5 rounded bg-slate-900 border border-slate-700 text-slate-300">
                        5h: <strong className="text-cyan-300">{win.sessionText}</strong>
                      </span>
                    )}
                    <span className="px-1.5 py-0.5 rounded bg-slate-900 border border-slate-700 text-slate-300">
                      Wk: <strong className="text-purple-300">{win.weeklyText}</strong>
                    </span>
                    {win.isFreeResetReady && (
                      <span className="px-1.5 py-0.5 rounded bg-emerald-950/80 border border-emerald-500/50 text-emerald-300 font-bold">
                        FREE RESET
                      </span>
                    )}
                  </div>
                </>
              );
            })()}
          </div>
        </section>

        {/* 專屬：多配額池矩陣儀表板 (Multi-Pool Matrix Deck) */}
        {parsedPools.length > 0 && (
          <section className="p-4 sm:p-5 rounded-2xl glass-panel border border-slate-800/80 space-y-3">
            <div className="flex items-center justify-between">
              <span className="font-semibold text-xs text-slate-300 uppercase tracking-wider flex items-center gap-1.5 font-mono">
                <Layers className="w-3.5 h-3.5 text-cyan-400" />
                {selectedItem.name} 多配額池 (Token Pools) 獨立儀表板
              </span>
              <span className="text-[11px] font-mono px-2 py-0.5 rounded-full bg-cyan-950/60 text-cyan-300 border border-cyan-500/40">
                {parsedPools.length} 個配額池在線
              </span>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
              {parsedPools.map((pool) => {
                const isCritical = pool.isCritical || pool.effectiveRemaining <= 5;
                const isWarning = pool.effectiveRemaining < 20 && !isCritical;
                return (
                  <div
                    key={pool.id}
                    className={`p-3.5 rounded-xl border flex flex-col justify-between transition-all ${
                      isCritical
                        ? 'bg-rose-950/40 border-rose-500/50 shadow-[0_0_20px_rgba(244,63,94,0.2)] ring-1 ring-rose-500/30'
                        : isWarning
                        ? 'bg-amber-950/30 border-amber-500/40'
                        : 'bg-slate-900/80 border-slate-800/80 hover:border-slate-700'
                    }`}
                  >
                    <div>
                      <div className="flex items-center justify-between gap-1 mb-2">
                        <h4 className="font-bold text-sm text-slate-200 tracking-tight truncate">
                          {pool.name}
                        </h4>
                        <span
                          className={`text-[10px] font-semibold px-2 py-0.5 rounded-full border ${
                            isCritical
                              ? 'bg-rose-950/80 text-rose-300 border-rose-500/50 animate-pulse'
                              : isWarning
                              ? 'bg-amber-950/80 text-amber-300 border-amber-500/40'
                              : 'bg-emerald-950/60 text-emerald-300 border-emerald-500/40'
                          }`}
                        >
                          {isCritical ? '⚠️ 耗盡告警' : isWarning ? '注意水位' : '正常可用'}
                        </span>
                      </div>

                      <div className="flex items-baseline gap-1.5 mb-2.5">
                        <span
                          className={`text-2xl font-black font-mono tabular-nums ${
                            isCritical
                              ? 'text-rose-400 animate-pulse'
                              : isWarning
                              ? 'text-amber-400'
                              : 'text-cyan-300'
                          }`}
                        >
                          {pool.effectiveRemaining}%
                        </span>
                        <span className="text-[10px] text-slate-500 uppercase font-medium">有效剩餘</span>
                      </div>
                    </div>

                    {/* 雙週期細項進度條 (5h vs Weekly) */}
                    <div className="space-y-2 pt-2 border-t border-slate-800/80">
                      {pool.tiers &&
                        pool.tiers.map((tier) => {
                          const tierRemaining =
                            tier.remaining !== undefined
                              ? tier.remaining
                              : Math.max(0, 100 - tier.used);
                          const isTierAlert = tierRemaining <= 5;
                          return (
                            <div key={tier.id} className="space-y-1">
                              <div className="flex items-center justify-between text-[11px] font-mono">
                                <span className="text-slate-400">{tier.label}</span>
                                <span className="text-slate-200">
                                  {tierRemaining}% 剩餘
                                  {tier.resetDurationText && (
                                    <span className="text-slate-500 text-[10px] ml-1">
                                      ({tier.resetDurationText})
                                    </span>
                                  )}
                                </span>
                              </div>
                              <div className="w-full h-1.5 rounded-full bg-slate-950 overflow-hidden border border-slate-800/60">
                                <div
                                  className={`h-full rounded-full transition-all duration-500 ${
                                    isTierAlert
                                      ? 'bg-rose-500 animate-pulse'
                                      : tierRemaining < 20
                                      ? 'bg-amber-400'
                                      : 'bg-gradient-to-r from-cyan-400 via-indigo-400 to-purple-400'
                                  }`}
                                  style={{
                                    width: `${Math.min(100, Math.max(2, tierRemaining))}%`,
                                  }}
                                />
                              </div>
                            </div>
                          );
                        })}
                    </div>
                  </div>
                );
              })}
            </div>
          </section>
        )}

        {/* 平台專屬多維度真實指標卡片 (後備模式) */}
        {parsedPools.length === 0 && parsedMetrics.length > 0 && (
          <section className="p-4 sm:p-5 rounded-2xl glass-panel border border-slate-800/80 space-y-3">
            <div className="flex items-center justify-between">
              <span className="font-semibold text-xs text-slate-300 uppercase tracking-wider flex items-center gap-1.5 font-mono">
                <Sparkles className="w-3.5 h-3.5 text-cyan-400" />
                {selectedItem.name} 真實帳戶多維度限額細項
              </span>
              <span className="text-[11px] font-mono px-2 py-0.5 rounded-full bg-slate-800 text-slate-300 border border-slate-700">
                SSOT Verified
              </span>
            </div>

            <div className="grid grid-cols-2 sm:grid-cols-4 gap-2.5 text-xs">
              {parsedMetrics.map((m, idx) => {
                const isAlert = m.isAlert || (m.used !== undefined && m.used >= 95);
                return (
                  <div
                    key={idx}
                    className={`p-3 rounded-xl border transition-all ${
                      isAlert
                        ? 'bg-rose-950/40 border-rose-500/50 shadow-[0_0_15px_rgba(244,63,94,0.15)]'
                        : 'bg-slate-900/70 border-slate-800/80'
                    }`}
                  >
                    <div className="text-slate-400 text-[11px] font-medium">{m.label}</div>
                    {m.used !== undefined ? (
                      <div
                        className={`font-mono font-bold text-lg mt-1 ${
                          isAlert ? 'text-rose-400 animate-pulse' : 'text-slate-100'
                        }`}
                      >
                        {m.used}%
                        <span className="text-[10px] text-slate-500 ml-1">已用</span>
                      </div>
                    ) : (
                      <div className="font-mono font-bold text-sm text-slate-100 mt-1 truncate">
                        {m.value || '--'}
                      </div>
                    )}
                    {isAlert && (
                      <div className="text-[10px] text-rose-400 font-semibold flex items-center gap-1 mt-1">
                        <AlertTriangle className="w-3 h-3" /> 超標 / 告警
                      </div>
                    )}
                  </div>
                );
              })}
            </div>
          </section>
        )}

        {/* 深度思考 (Extended Thinking) 預算控制器 - Apple HIG 單手熱區拇指預設按鈕 (≥ 44pt Touch Targets) */}
        <section className="p-4 rounded-2xl glass-panel border border-slate-800/80 space-y-3">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <BrainCircuit className="w-4 h-4 text-cyan-400" />
              <h3 className="font-bold text-xs uppercase tracking-wider text-slate-300 font-mono">
                THINKING BUDGET 思維鏈預算
              </h3>
            </div>
            <span className="tabular-nums font-mono text-xs px-2.5 py-1 rounded-md bg-cyan-950/80 text-cyan-300 border border-cyan-500/40 font-bold">
              {thinkingBudget.toLocaleString()} TOKENS
            </span>
          </div>

          <div className="py-2">
            <input
              type="range"
              min={0}
              max={100000}
              step={1024}
              value={thinkingBudget}
              onChange={(e) => setThinkingBudget(Number(e.target.value))}
              className="w-full accent-cyan-400 h-3 bg-slate-800 rounded-lg cursor-pointer touch-manipulation"
              aria-label="思維鏈預算調整滑桿"
            />
          </div>

          {/* 單手一鍵快選拇指熱區膠囊 (One-Handed Thumb Presets - Apple HIG ≥ 44×44pt) */}
          <div className="grid grid-cols-5 gap-1.5 pt-1">
            {[
              { label: '0K', value: 0, sub: '即時回應' },
              { label: '16K', value: 16384, sub: '標準編程' },
              { label: '32K', value: 32768, sub: '深度架構' },
              { label: '64K', value: 65536, sub: '極限推論' },
              { label: '100K', value: 100000, sub: 'o3-mini 頂峰' },
            ].map((p) => {
              const isCurrent = Math.abs(thinkingBudget - p.value) < 1024;
              return (
                <button
                  key={p.label}
                  type="button"
                  onClick={() => handleSelectPreset(p.value)}
                  className={`flex flex-col items-center justify-center p-1.5 rounded-xl border font-mono transition-all min-h-[44px] active:scale-95 touch-manipulation ${
                    isCurrent
                      ? 'bg-cyan-950/80 border-cyan-400 text-cyan-300 shadow-[0_0_12px_rgba(6,182,212,0.3)] ring-1 ring-cyan-400/40'
                      : 'bg-slate-900/60 border-slate-800 text-slate-400 hover:text-slate-200 hover:bg-slate-850'
                  }`}
                >
                  <span className="text-xs font-bold leading-none">{p.label}</span>
                  <span className="text-[8px] text-slate-500 mt-1 leading-none text-center truncate w-full">
                    {p.label === '100K' ? '100K (o3-mini 頂峰)' : p.sub}
                  </span>
                </button>
              );
            })}
          </div>
        </section>
      </div>
    </div>
  );
};
