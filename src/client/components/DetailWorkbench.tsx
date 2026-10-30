import React, { useState } from 'react';
import { QuotaCardProps } from './QuotaCard';
import { AudioVisualizer } from './AudioVisualizer';
import {
  PanelLeftClose,
  PanelLeftOpen,
  Cpu,
  BrainCircuit,
  Activity,
  Zap,
  Clock,
  Sparkles,
} from 'lucide-react';

interface DetailWorkbenchProps {
  selectedItem: QuotaCardProps | undefined;
  isFocusMode: boolean;
  onToggleFocus: () => void;
  isVoiceActive: boolean;
  liveTranscript: string;
}

export const DetailWorkbench: React.FC<DetailWorkbenchProps> = ({
  selectedItem,
  isFocusMode,
  onToggleFocus,
  isVoiceActive,
  liveTranscript,
}) => {
  const [thinkingBudget, setThinkingBudget] = useState<number>(16384);

  if (!selectedItem) {
    return (
      <div className="flex flex-col items-center justify-center h-full p-8 text-center text-[#86868b] bg-white">
        <Activity className="w-12 h-12 text-[#d2d2d7] mb-3" />
        <h3 className="font-semibold text-base text-[#1d1d1f]">請選取左側 AI 平台</h3>
        <p className="text-sm mt-1 max-w-sm">
          點選左側清單以檢視即時 Token 用量、思維預算控制器與 Gemini 3.8 語音通話字幕。
        </p>
      </div>
    );
  }

  return (
    <div className="flex flex-col h-full bg-white overflow-y-auto">
      {/* 頂部工具列 */}
      <div className="flex items-center justify-between p-4 border-b border-[#e5e5ea] sticky top-0 bg-white/95 backdrop-blur-md z-10">
        <div className="flex items-center gap-3">
          <button
            onClick={onToggleFocus}
            title={isFocusMode ? '展開導覽列' : '進入專注全寬模式 (Focus Mode)'}
            className="p-2 rounded-xl text-[#86868b] hover:text-[#1d1d1f] hover:bg-[#f5f5f7] active:scale-95 transition-all"
          >
            {isFocusMode ? <PanelLeftOpen className="w-5 h-5 text-[#0071e3]" /> : <PanelLeftClose className="w-5 h-5" />}
          </button>
          <div>
            <h2 className="font-bold text-lg text-[#1d1d1f] tracking-tight flex items-center gap-2">
              {selectedItem.name}
              <span className="text-xs font-medium px-2 py-0.5 rounded-full bg-blue-50 text-[#0071e3] border border-blue-100">
                {selectedItem.planName}
              </span>
            </h2>
          </div>
        </div>

        <div className="flex items-center gap-2">
          <span className="flex items-center gap-1.5 text-xs font-semibold px-2.5 py-1 rounded-full bg-emerald-50 text-emerald-700 border border-emerald-200">
            <span className="w-2 h-2 rounded-full bg-emerald-500 animate-pulse" />
            邊緣同步中
          </span>
        </div>
      </div>

      <div className="p-6 space-y-6 max-w-4xl">
        {/* 即時語音互動與波形面板 */}
        <section className="space-y-3">
          <AudioVisualizer isActive={isVoiceActive} volume={isVoiceActive ? 0.75 : 0} />
          
          {/* 即時字幕面板 */}
          <div className="p-4 rounded-xl bg-[#f5f5f7] border border-[#e5e5ea]">
            <div className="flex items-center gap-2 mb-2 text-xs font-semibold text-[#86868b] uppercase tracking-wider">
              <Sparkles className="w-3.5 h-3.5 text-[#0071e3]" />
              Gemini 3.8 Live 即時對話字幕
            </div>
            <p className="text-sm leading-relaxed text-[#1d1d1f] min-h-[44px]">
              {liveTranscript || (isVoiceActive ? '正在聆聽語音指令...' : '語音休眠中。點擊右下角麥克風按鈕即可開始對話與查詢額度。')}
            </p>
          </div>
        </section>

        {/* 核心指標卡片格線 */}
        <section className="grid grid-cols-1 sm:grid-cols-3 gap-4">
          <div className="p-4 rounded-xl bg-[#fbfbfd] border border-[#e5e5ea]">
            <div className="flex items-center justify-between text-xs text-[#86868b] mb-1">
              <span>剩餘額度百分比</span>
              <Activity className="w-4 h-4 text-[#0071e3]" />
            </div>
            <div className="text-2xl font-bold tabular-nums text-[#1d1d1f]">
              {selectedItem.remainingPercent}%
            </div>
            <div className={`text-xs font-medium mt-1 ${selectedItem.remainingPercent < 30 ? 'text-amber-600' : 'text-emerald-600'}`}>
              {selectedItem.remainingPercent < 30 ? '注意：額度偏低接近限額' : '充足無阻斷風險'}
            </div>
          </div>

          <div className="p-4 rounded-xl bg-[#fbfbfd] border border-[#e5e5ea]">
            <div className="flex items-center justify-between text-xs text-[#86868b] mb-1">
              <span>已耗用 / 總配額</span>
              <Zap className="w-4 h-4 text-amber-500" />
            </div>
            <div className="text-2xl font-bold tabular-nums text-[#1d1d1f]">
              {selectedItem.usedQuota} / {selectedItem.totalQuota}
            </div>
            <div className="text-xs text-[#86868b] mt-1">月度基準循環</div>
          </div>

          <div className="p-4 rounded-xl bg-[#fbfbfd] border border-[#e5e5ea]">
            <div className="flex items-center justify-between text-xs text-[#86868b] mb-1">
              <span>額度重置時間</span>
              <Clock className="w-4 h-4 text-blue-500" />
            </div>
            <div className="text-base font-bold text-[#1d1d1f] truncate mt-1">
              {selectedItem.resetTime}
            </div>
            <div className="text-xs text-[#86868b] mt-1">定時自動刷新</div>
          </div>
        </section>

        {/* Codex (ChatGPT Plus) 專屬雙重限額展示 */}
        {selectedItem.id === 'codex' && (
          <section className="p-4 rounded-xl bg-amber-50/70 border border-amber-200 space-y-3">
            <div className="flex items-center justify-between">
              <span className="font-semibold text-xs text-amber-900 uppercase tracking-wider">
                ChatGPT Plus 雙重限額明細
              </span>
              <span className="text-xs font-semibold px-2 py-0.5 rounded-full bg-amber-100 text-amber-800">
                週限額已達 100%
              </span>
            </div>
            <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 text-xs">
              <div className="p-2.5 bg-white rounded-lg border border-amber-100">
                <div className="text-[#86868b]">Session 短視窗</div>
                <div className="font-bold text-base text-[#1d1d1f] tabular-nums mt-0.5">72% 已用</div>
                <div className="text-[11px] text-[#86868b]">今天 5:06 重置</div>
              </div>
              <div className="p-2.5 bg-white rounded-lg border border-amber-100">
                <div className="text-[#86868b]">Weekly 共享池</div>
                <div className="font-bold text-base text-rose-600 tabular-nums mt-0.5">100% 已達</div>
                <div className="text-[11px] text-[#86868b]">11月4日 14:48 重置</div>
              </div>
              <div className="p-2.5 bg-white rounded-lg border border-amber-100">
                <div className="text-[#86868b]">Rate Limit Resets</div>
                <div className="font-bold text-base text-[#1d1d1f] tabular-nums mt-0.5">0 次可用</div>
                <div className="text-[11px] text-[#86868b]">每月固定重置</div>
              </div>
              <div className="p-2.5 bg-white rounded-lg border border-amber-100">
                <div className="text-[#86868b]">Credits 帳戶額度</div>
                <div className="font-bold text-base text-[#1d1d1f] tabular-nums mt-0.5">$0.00</div>
                <div className="text-[11px] text-[#86868b]">0 credits</div>
              </div>
            </div>
          </section>
        )}

        {/* 深度思考 (Extended Thinking) 預算控制器 */}
        <section className="p-5 rounded-2xl bg-[#fbfbfd] border border-[#e5e5ea] space-y-4">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <BrainCircuit className="w-5 h-5 text-[#0071e3]" />
              <h3 className="font-semibold text-base text-[#1d1d1f]">
                思維鏈 (Thinking Budget) 預算調校
              </h3>
            </div>
            <span className="tabular-nums font-mono text-sm px-2.5 py-1 rounded-lg bg-blue-50 text-[#0071e3] border border-blue-200 font-semibold">
              {thinkingBudget.toLocaleString()} Tokens
            </span>
          </div>

          <p className="text-xs text-[#86868b] leading-relaxed">
            針對 Claude 3.7 Sonnet、Gemini 3.8 Flash 與 o3-mini 調節推理預算上限。更高的預算可強化複雜演算法設計與代碼除錯能力，預算用盡時自動啟動硬阻斷防爆帳單。
          </p>

          <input
            type="range"
            min={0}
            max={65536}
            step={1024}
            value={thinkingBudget}
            onChange={(e) => setThinkingBudget(Number(e.target.value))}
            className="w-full accent-[#0071e3] h-2 bg-[#e5e5ea] rounded-lg cursor-pointer"
          />

          <div className="flex justify-between text-[11px] font-mono text-[#86868b]">
            <span>0 (即時回應)</span>
            <span>16K (標準編程)</span>
            <span>32K (深度架構)</span>
            <span>64K (極限推論)</span>
          </div>
        </section>
      </div>
    </div>
  );
};
