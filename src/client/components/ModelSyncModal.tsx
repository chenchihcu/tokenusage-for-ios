import React from 'react';
import { X, CheckCircle2, Sparkles, RefreshCw } from 'lucide-react';

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
  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/40 backdrop-blur-sm animate-fade-in">
      <div className="w-full max-w-2xl bg-white rounded-2xl shadow-2xl border border-[#e5e5ea] overflow-hidden flex flex-col max-h-[85vh]">
        {/* Modal 頂部 */}
        <div className="flex items-center justify-between p-5 border-b border-[#e5e5ea]">
          <div className="flex items-center gap-2.5">
            <Sparkles className="w-5 h-5 text-[#0071e3]" />
            <div>
              <h3 className="font-bold text-lg text-[#1d1d1f]">即時遠端動態模型型錄</h3>
              <p className="text-xs text-[#86868b]">
                SSRF 白名單安全探測 • 自動快取於 Cloudflare KV
              </p>
            </div>
          </div>
          <button
            onClick={onClose}
            className="p-1.5 rounded-lg text-[#86868b] hover:text-[#1d1d1f] hover:bg-[#f5f5f7] transition-all"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* 模型列表 */}
        <div className="flex-1 overflow-y-auto p-5 space-y-3">
          {models.map((m) => {
            const ctxWindow = m.context_window || m.contextWindow || 128000;
            const maxBudget = m.thinking_budget_max || m.thinkingBudgetMax || 0;
            const inputCost = m.cost_per_m_input ?? m.costPerMInput ?? 0;

            return (
              <div
                key={m.id}
                className="p-4 rounded-xl border border-[#e5e5ea] bg-[#fbfbfd] flex items-center justify-between hover:border-[#b0b0b8] transition-all"
              >
                <div>
                  <div className="flex items-center gap-2">
                    <span className="font-bold text-sm text-[#1d1d1f]">{m.name}</span>
                    <span className="text-[11px] font-mono px-2 py-0.5 rounded-full bg-blue-50 text-[#0071e3] border border-blue-100">
                      {m.provider}
                    </span>
                  </div>
                  <div className="flex items-center gap-4 mt-2 text-xs text-[#86868b] font-mono">
                    <span>Context: {(ctxWindow / 1000).toFixed(0)}k</span>
                    {maxBudget > 0 && <span>Thinking: Up to {(maxBudget / 1000).toFixed(0)}k</span>}
                    <span>Input: ${inputCost.toFixed(3)}/M</span>
                  </div>
                </div>

                <div className="flex items-center gap-1.5 text-xs font-semibold text-emerald-600">
                  <CheckCircle2 className="w-4 h-4" />
                  已同步
                </div>
              </div>
            );
          })}
        </div>

        {/* 底部動作列 */}
        <div className="flex items-center justify-between p-4 bg-[#f5f5f7] border-t border-[#e5e5ea]">
          <span className="text-xs text-[#86868b] tabular-nums">
            已載入 {models.length} 個最新模型
          </span>
          <div className="flex items-center gap-2">
            <button
              onClick={onClose}
              className="px-4 py-2 text-sm font-medium rounded-xl text-[#1d1d1f] hover:bg-[#e5e5ea] transition-all"
            >
              關閉
            </button>
            <button
              onClick={onTriggerSync}
              disabled={isSyncing}
              className="flex items-center gap-2 px-4 py-2 text-sm font-medium rounded-xl bg-[#0071e3] text-white hover:bg-[#0077ed] active:scale-95 transition-all shadow-sm"
            >
              <RefreshCw className={`w-4 h-4 ${isSyncing ? 'animate-spin' : ''}`} />
              {isSyncing ? '探測中...' : '立即重新探測'}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
};
