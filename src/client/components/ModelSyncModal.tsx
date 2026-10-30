import React, { useState } from 'react';
import { X, CheckCircle2, Sparkles, RefreshCw, ShieldCheck } from 'lucide-react';

interface ModelItem {
  id: string;
  name: string;
  provider: string;
  context_window?: number;
  contextWindow?: number;
  supports_thinking?: boolean;
  supportsThinking?: boolean;
  thinking_budget_max?: number;
  thinkingBudgetMax?: number;
  cost_per_m_input?: number;
  costPerMInput?: number;
  status?: string;
  verified_date?: string;
  verifiedDate?: string;
}

interface ModelSyncModalProps {
  isOpen: boolean;
  onClose: () => void;
  models: ModelItem[];
  isSyncing: boolean;
  onTriggerSync: () => void;
}

export const ModelSyncModal: React.FC<ModelSyncModalProps> = ({
  isOpen,
  onClose,
  models,
  isSyncing,
  onTriggerSync,
}) => {
  const [selectedProvider, setSelectedProvider] = useState<string>('all');

  if (!isOpen) return null;

  const filteredModels = models.filter((m) => {
    if (selectedProvider === 'all') return true;
    if (selectedProvider === 'OpenAI') return m.provider === 'OpenAI';
    if (selectedProvider === 'Google') return m.provider === 'Google';
    if (selectedProvider === 'Anthropic') return m.provider === 'Anthropic';
    if (selectedProvider === 'xAI') return m.provider === 'xAI';
    if (selectedProvider === 'Cursor') return m.provider === 'Cursor';
    return true;
  });

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80 backdrop-blur-md animate-in fade-in duration-200">
      <div className="w-full max-w-2xl bg-slate-900 rounded-2xl shadow-2xl border border-slate-700/80 overflow-hidden flex flex-col max-h-[85vh]">
        {/* Modal 頂部 */}
        <div className="flex items-center justify-between p-5 border-b border-slate-800 bg-slate-900/90">
          <div className="flex items-center gap-2.5">
            <Sparkles className="w-5 h-5 text-cyan-400" />
            <div>
              <h3 className="font-bold text-lg text-white">5 大平台最新活躍前瞻 AI 模型型錄</h3>
              <p className="text-xs text-slate-400 flex items-center gap-1.5 mt-0.5">
                <ShieldCheck className="w-3.5 h-3.5 text-emerald-400" />
                Deprecation Guard 啟用 • 已過期舊模型全面硬阻斷排除
              </p>
            </div>
          </div>
          <button
            onClick={onClose}
            className="p-2 rounded-xl text-slate-400 hover:text-white hover:bg-slate-800 transition-all min-h-[44px] min-w-[44px] flex items-center justify-center"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* 供應商分類 Tab 標籤 */}
        <div className="flex items-center gap-1.5 px-5 py-2.5 border-b border-slate-800 bg-slate-950/60 overflow-x-auto">
          {[
            { id: 'all', label: '全部' },
            { id: 'OpenAI', label: 'Codex (OpenAI)' },
            { id: 'Google', label: 'Antigravity (Google)' },
            { id: 'Anthropic', label: 'Claude Code' },
            { id: 'xAI', label: 'Grok' },
            { id: 'Cursor', label: 'Cursor' },
          ].map((tab) => (
            <button
              key={tab.id}
              type="button"
              onClick={() => setSelectedProvider(tab.id)}
              className={`px-3 py-1.5 text-xs font-semibold rounded-lg transition-all shrink-0 min-h-[36px] ${
                selectedProvider === tab.id
                  ? 'bg-cyan-500/20 text-cyan-300 border border-cyan-500/50'
                  : 'text-slate-400 hover:text-white hover:bg-slate-800'
              }`}
            >
              {tab.label}
            </button>
          ))}
        </div>

        {/* 模型列表 */}
        <div className="flex-1 overflow-y-auto p-5 space-y-3">
          {filteredModels.map((m) => {
            const ctxWindow = m.context_window || m.contextWindow || 128000;
            const maxBudget = m.thinking_budget_max || m.thinkingBudgetMax || 0;
            const inputCost = m.cost_per_m_input ?? m.costPerMInput ?? 0;

            return (
              <div
                key={m.id}
                className="p-4 rounded-xl border border-slate-800 bg-slate-950/60 flex items-center justify-between hover:border-slate-700 transition-all"
              >
                <div>
                  <div className="flex items-center gap-2">
                    <span className="font-bold text-sm text-white">{m.name}</span>
                    <span className="text-[10px] font-mono font-semibold px-2 py-0.5 rounded-full bg-cyan-950/60 text-cyan-300 border border-cyan-500/40">
                      {m.provider}
                    </span>
                    <span className="text-[10px] font-mono px-2 py-0.5 rounded-full bg-emerald-950/60 text-emerald-400 border border-emerald-500/40">
                      Active
                    </span>
                  </div>
                  <div className="flex items-center gap-4 mt-2 text-xs text-slate-400 font-mono">
                    <span>Context: {(ctxWindow / 1000).toFixed(0)}k</span>
                    {maxBudget > 0 && (
                      <span className="text-cyan-400">
                        Thinking: 最高 {(maxBudget / 1000).toFixed(0)}k
                      </span>
                    )}
                    <span>Input: ${inputCost.toFixed(3)}/M</span>
                  </div>
                </div>

                <div className="flex items-center gap-1.5 text-xs font-semibold text-emerald-400 shrink-0">
                  <CheckCircle2 className="w-4 h-4" />
                  即時在線
                </div>
              </div>
            );
          })}
        </div>

        {/* 底部動作列 */}
        <div className="flex items-center justify-between p-4 bg-slate-950 border-t border-slate-800">
          <span className="text-xs text-slate-400 tabular-nums">
            已載入 {filteredModels.length} 個在線前瞻模型（無舊模型）
          </span>
          <div className="flex items-center gap-2">
            <button
              onClick={onClose}
              className="px-4 py-2 text-sm font-medium rounded-xl text-slate-300 hover:text-white hover:bg-slate-800 transition-all min-h-[44px]"
            >
              關閉
            </button>
            <button
              onClick={onTriggerSync}
              disabled={isSyncing}
              className="flex items-center gap-2 px-4 py-2 text-sm font-semibold rounded-xl bg-cyan-500 hover:bg-cyan-400 text-slate-950 shadow-lg shadow-cyan-500/25 transition-all disabled:opacity-50 min-h-[44px]"
            >
              <RefreshCw className={`w-4 h-4 ${isSyncing ? 'animate-spin' : ''}`} />
              強制刷新型錄
            </button>
          </div>
        </div>
      </div>
    </div>
  );
};
