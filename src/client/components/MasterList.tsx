import React, { useState } from 'react';
import { QuotaCard, QuotaCardProps } from './QuotaCard';
import { Search, ShieldCheck } from 'lucide-react';

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
    <div className="flex flex-col h-full bg-slate-950 border-r border-slate-800/80">
      {/* 頂部搜尋與安全指標 */}
      <div className="p-4 border-b border-slate-800/80 bg-slate-950/90 backdrop-blur-md sticky top-0 z-10">
        <div className="flex items-center justify-between mb-3">
          <div className="flex items-center gap-2">
            <h2 className="text-lg font-bold text-white tracking-tight">AI 額度監控</h2>
            <span className="flex items-center gap-1 text-[10px] font-semibold px-2 py-0.5 rounded-full bg-emerald-950/60 text-emerald-400 border border-emerald-500/40">
              <ShieldCheck className="w-3 h-3" />
              SSOT 有效
            </span>
          </div>
          <span className="text-xs font-semibold text-slate-400 tabular-nums font-mono">
            {filteredQuotas.length} 個平台
          </span>
        </div>

        {/* 搜尋欄 */}
        <div className="relative">
          <Search className="absolute left-3 top-2.5 w-4 h-4 text-slate-500" />
          <input
            type="text"
            placeholder="搜尋平台 (Cursor, Codex, Grok...)"
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
            className="w-full pl-9 pr-4 py-2 text-base bg-slate-900 border border-slate-800 rounded-xl text-slate-100 placeholder-slate-500 focus:outline-none focus:ring-2 focus:ring-cyan-500/50 focus:border-cyan-500/50 transition-all min-h-[44px]"
          />
        </div>
      </div>

      {/* 清單列表 */}
      <div className="flex-1 overflow-y-auto p-4 space-y-3">
        {isLoading ? (
          <div className="flex flex-col items-center justify-center h-48 text-slate-400 text-sm gap-2">
            <div className="w-6 h-6 border-2 border-cyan-400 border-t-transparent rounded-full animate-spin" />
            <span>正在自 Cloudflare 邊緣讀取真實額度...</span>
          </div>
        ) : filteredQuotas.length === 0 ? (
          <div className="text-center py-12 text-slate-500 text-sm">
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
