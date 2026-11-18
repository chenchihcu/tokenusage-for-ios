import React from 'react';
import { QuotaCard, QuotaCardProps } from './QuotaCard';

interface MasterListProps {
  quotas: QuotaCardProps[];
  selectedId: string;
  onSelect: (id: string) => void;
  isLoading: boolean;
}

export const MasterList: React.FC<MasterListProps> = ({
  quotas,
  selectedId,
  onSelect,
  isLoading,
}) => {
  const filteredQuotas = quotas;

  return (
    <div className="flex flex-col h-full bg-slate-950 border-r border-slate-800/80">
      <div className="px-4 pt-3 pb-2 phoneland:hidden flex items-center justify-between border-b border-slate-800/80">
        <h2 className="text-lg font-bold text-white">AI 額度</h2>
        <span className="text-xs text-slate-400 tabular-nums">{filteredQuotas.length} 個服務</span>
      </div>

      {/* 清單列表 */}
      <div className="flex-1 overflow-y-auto p-4 space-y-3 phoneland:p-2 phoneland:space-y-2 fab-clearance">
        {isLoading ? (
          <div className="flex flex-col items-center justify-center h-48 text-slate-400 text-sm gap-2">
            <div className="w-6 h-6 border-2 border-cyan-400 border-t-transparent rounded-full animate-spin" />
            <span>正在自 Cloudflare 邊緣讀取真實額度...</span>
          </div>
        ) : filteredQuotas.length === 0 ? (
          <div className="text-center py-12 text-slate-500 text-sm">
            目前沒有符合條件的服務
          </div>
        ) : (
          filteredQuotas.map((item) => (
            <QuotaCard
              key={item.id}
              {...item}
              isSelected={item.id === selectedId}
              onClick={() => onSelect(item.id)}
            />
          ))
        )}
      </div>
    </div>
  );
};
