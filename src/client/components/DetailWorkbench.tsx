import React, { useState } from 'react';
import { QuotaCardProps } from './QuotaCard';
import { AudioVisualizer } from './AudioVisualizer';
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
} from 'lucide-react';

interface DetailWorkbenchProps {
  selectedItem: QuotaCardProps | undefined;
  isFocusMode: boolean;
  onToggleFocus: () => void;
  isVoiceActive: boolean;
  liveTranscript: string;
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
}) => {
  const [thinkingBudget, setThinkingBudget] = useState<number>(32768);

  if (!selectedItem) {
    return (
      <div className="flex flex-col items-center justify-center h-full p-8 text-center text-slate-500 bg-slate-950">
        <Activity className="w-12 h-12 text-slate-700 mb-3 animate-pulse" />
        <h3 className="font-semibold text-base text-slate-200">請選取左側 AI 平台</h3>
        <p className="text-sm mt-1 max-w-sm text-slate-400">
          點選左側清單以檢視各平台真實帳號指標、思維預算控制器與 Gemini 3.8 語音通話字幕。
        </p>
      </div>
    );
  }

  // 解析真實帳號多維度指標
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

  return (
    <div className="flex flex-col h-full bg-slate-950 overflow-y-auto text-slate-100">
      {/* 頂部工具列 */}
      <div className="flex items-center justify-between p-4 border-b border-slate-800/80 sticky top-0 bg-slate-950/90 backdrop-blur-xl z-10">
        <div className="flex items-center gap-3">
          <button
            onClick={onToggleFocus}
            title={isFocusMode ? '展開導航欄' : '進入專注全寬模式 (Focus Mode)'}
            className="p-2 rounded-xl text-slate-400 hover:text-white hover:bg-slate-800/60 active:scale-95 transition-all min-h-[44px] min-w-[44px] flex items-center justify-center"
          >
            {isFocusMode ? <PanelLeftOpen className="w-5 h-5 text-cyan-400" /> : <PanelLeftClose className="w-5 h-5" />}
          </button>
          <div>
            <h2 className="font-bold text-lg text-white tracking-tight flex items-center gap-2">
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
          <span className="flex items-center gap-1.5 text-xs font-semibold px-2.5 py-1 rounded-full bg-emerald-950/60 text-emerald-300 border border-emerald-500/40">
            <span className="w-2 h-2 rounded-full bg-emerald-400 animate-pulse" />
            100% 真實數據連線
          </span>
        </div>
      </div>

      <div className="p-6 space-y-6 max-w-4xl">
        {/* 即時語音互動與波形面板 */}
        <section className="space-y-3">
          <AudioVisualizer isActive={isVoiceActive} volume={isVoiceActive ? 0.75 : 0} />

          {/* 即時字幕面板 */}
          <div className="p-4 rounded-2xl glass-panel border border-slate-800/80">
            <div className="flex items-center gap-2 mb-2 text-xs font-semibold text-slate-400 uppercase tracking-wider">
              <Sparkles className="w-3.5 h-3.5 text-cyan-400" />
              Gemini 3.8 Live 即時對話字幕
            </div>
            <p className="text-sm leading-relaxed text-slate-200 min-h-[44px]">
              {liveTranscript || (isVoiceActive ? '正在聆聽語音指令...' : '語音休眠中。點擊右下角麥克風按鈕即可開始對話與查詢即時額度。')}
            </p>
          </div>
        </section>

        {/* 核心高保真數據卡片格線 */}
        <section className="grid grid-cols-1 sm:grid-cols-3 gap-4">
          <div className="p-4 rounded-2xl glass-panel border border-slate-800/80">
            <div className="flex items-center justify-between text-xs text-slate-400 mb-1">
              <span>剩餘額度百分比</span>
              <Activity className="w-4 h-4 text-cyan-400" />
            </div>
            <div className="text-3xl font-black font-mono tabular-nums text-white">
              {selectedItem.remainingPercent}%
            </div>
            <div className={`text-xs font-medium mt-1 ${selectedItem.remainingPercent < 20 ? 'text-rose-400' : 'text-emerald-400'}`}>
              {selectedItem.remainingPercent < 20 ? '注意：額度偏低或已達上限' : '充足無阻斷風險'}
            </div>
          </div>

          <div className="p-4 rounded-2xl glass-panel border border-slate-800/80">
            <div className="flex items-center justify-between text-xs text-slate-400 mb-1">
              <span>已用比例 / 基準</span>
              <Zap className="w-4 h-4 text-amber-400" />
            </div>
            <div className="text-3xl font-black font-mono tabular-nums text-white">
              {selectedItem.usedQuota}%
            </div>
            <div className="text-xs text-slate-400 mt-1">基準循環 100%</div>
          </div>

          <div className="p-4 rounded-2xl glass-panel border border-slate-800/80">
            <div className="flex items-center justify-between text-xs text-slate-400 mb-1">
              <span>週期重置時間</span>
              <Clock className="w-4 h-4 text-purple-400" />
            </div>
            <div className="text-sm font-bold font-mono text-slate-100 truncate mt-1.5">
              {displayReset}
            </div>
            <div className="text-xs text-slate-400 mt-1">定時自動刷新</div>
          </div>
        </section>

        {/* 平台專屬多維度真實指標卡片 (Extracted from SSOT Cache) */}
        {parsedMetrics.length > 0 && (
          <section className="p-5 rounded-2xl glass-panel border border-slate-800/80 space-y-3">
            <div className="flex items-center justify-between">
              <span className="font-semibold text-xs text-slate-300 uppercase tracking-wider flex items-center gap-1.5">
                <Sparkles className="w-3.5 h-3.5 text-cyan-400" />
                {selectedItem.name} 真實帳戶多維度限額細項
              </span>
              <span className="text-[11px] font-mono px-2 py-0.5 rounded-full bg-slate-800 text-slate-300 border border-slate-700">
                SSOT Verified
              </span>
            </div>

            <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 text-xs">
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
                      <div className={`font-mono font-bold text-lg mt-1 ${isAlert ? 'text-rose-400 animate-pulse' : 'text-slate-100'}`}>
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

        {/* 深度思考 (Extended Thinking) 預算控制器 (支援最高 100K Tokens) */}
        <section className="p-5 rounded-2xl glass-panel border border-slate-800/80 space-y-4">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <BrainCircuit className="w-5 h-5 text-cyan-400" />
              <h3 className="font-semibold text-base text-slate-100">
                思維鏈 (Thinking Budget) 預算調校
              </h3>
            </div>
            <span className="tabular-nums font-mono text-sm px-2.5 py-1 rounded-lg bg-cyan-950/80 text-cyan-300 border border-cyan-500/40 font-semibold">
              {thinkingBudget.toLocaleString()} Tokens
            </span>
          </div>

          <p className="text-xs text-slate-400 leading-relaxed">
            針對 o3-mini (100K)、Gemini 3.8 Flash (65K) 與 Claude 3.7 Sonnet (64K) 調節推理預算上限。更高的預算可強化複雜演算法設計與代碼除錯能力，預算用盡時自動啟動硬阻斷防爆帳單。
          </p>

          <input
            type="range"
            min={0}
            max={100000}
            step={1024}
            value={thinkingBudget}
            onChange={(e) => setThinkingBudget(Number(e.target.value))}
            className="w-full accent-cyan-400 h-2 bg-slate-800 rounded-lg cursor-pointer"
          />

          <div className="flex justify-between text-[11px] font-mono text-slate-500">
            <span>0 (即時回應)</span>
            <span>16K (標準編程)</span>
            <span>32K (深度架構)</span>
            <span>64K (極限推論)</span>
            <span className="text-cyan-400 font-bold">100K (o3-mini 頂峰)</span>
          </div>
        </section>
      </div>
    </div>
  );
};
