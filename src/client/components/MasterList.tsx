import React, { useState } from 'react';
import { QuotaCard, QuotaCardProps } from './QuotaCard';
import { Search, SlidersHorizontal, ShieldCheck } from 'lucide-react';

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
  const [searchTerm, setSearchTerm] = useState('');
  const [filter, setFilter] = useState<'all' | 'warning'>('all');

  const filteredQuotas = quotas.filter((q) => {
    const matchesSearch =
      q.name.toLowerCase().includes(searchTerm.toLowerCase()) ||
      q.planName.toLowerCase().includes(searchTerm.toLowerCase());
    if (filter === 'warning') {
      return matchesSearch && q.remainingPercent < 50;
    }
    return matchesSearch;
  });

  return (
    <div className="flex flex-col h-full bg-[#fbfbfd] border-r border-[#e5e5ea]">
      {/* 頂部搜尋與安全指標 */}
      <div className="p-4 border-b border-[#e5e5ea] bg-white sticky top-0 z-10">
        <div className="flex items-center justify-between mb-3">
          <div className="flex items-center gap-2">
            <h2 className="text-lg font-bold text-[#1d1d1f] tracking-tight">AI 額度監控</h2>
            <span className="flex items-center gap-1 text-[11px] font-medium px-2 py-0.5 rounded-full bg-emerald-50 text-emerald-700 border border-emerald-200">
              <ShieldCheck className="w-3 h-3" />
              本地安全憑證有效
            </span>
          </div>
          <span className="text-xs font-semibold text-[#86868b] tabular-nums">
            {filteredQuotas.length} 個平台
          </span>
        </div>

        {/* 搜尋欄 */}
        <div className="relative">
          <Search className="absolute left-3 top-2.5 w-4 h-4 text-[#86868b]" />
          <input
            type="text"
            placeholder="搜尋 AI 平台 (Cursor, Grok...)"
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
            className="w-full pl-9 pr-4 py-2 text-sm bg-[#f5f5f7] border border-[#e5e5ea] rounded-xl focus:outline-none focus:ring-2 focus:ring-[#0071e3] focus:bg-white transition-all"
          />
        </div>
      </div>

      {/* 清單列表 */}
      <div className="flex-1 overflow-y-auto p-4 space-y-3">
        {isLoading ? (
          <div className="flex flex-col items-center justify-center h-48 text-[#86868b] text-sm gap-2">
            <div className="w-6 h-6 border-2 border-[#0071e3] border-t-transparent rounded-full animate-spin" />
            <span>正在自 Cloudflare 邊緣讀取額度...</span>
          </div>
        ) : filteredQuotas.length === 0 ? (
          <div className="text-center py-12 text-[#86868b] text-sm">
            找不到符合條件的平台
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
