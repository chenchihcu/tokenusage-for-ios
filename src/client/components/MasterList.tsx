import React from 'react';
import { QuotaCardProps } from './QuotaCard';
import { PlatformIcon } from './PlatformIcon';
import { percentText } from '../usage/usageFacts';

interface MasterListProps {
  quotas: QuotaCardProps[];
  selectedId: string;
  onSelect: (id: string) => void;
  isLoading: boolean;
}

export const MasterList: React.FC<MasterListProps> = ({ quotas, selectedId, onSelect, isLoading }) => {
  return (
    <div className="flex flex-col h-full min-h-0 overflow-hidden bg-slate-950 border-r border-slate-800/80">
      <div className="px-3 h-11 phoneland:hidden shrink-0 flex items-center justify-between border-b border-slate-800/80">
        <h2 className="text-base font-bold text-white">服務</h2>
        <span className="text-xs text-slate-400 tabular-nums">{quotas.length}</span>
      </div>

      {isLoading ? (
        <p role="status" className="flex-1 flex items-center justify-center text-sm text-slate-300">
          正在讀取額度
        </p>
      ) : quotas.length === 0 ? (
        <p className="flex-1 flex items-center justify-center text-sm text-slate-300">沒有符合的服務</p>
      ) : (
        <div
          className="flex-1 min-h-0 grid"
          style={{ gridTemplateRows: `repeat(${quotas.length}, minmax(0, 1fr))` }}
        >
          {quotas.map((item) => {
            const selected = item.id === selectedId;
            return (
              <button
                key={item.id}
                type="button"
                aria-pressed={selected}
                onClick={() => onSelect(item.id)}
                className={`min-h-0 h-full w-full overflow-hidden flex items-center gap-2 px-3 text-left border-b border-slate-800 focus:outline-none focus-visible:ring-2 focus-visible:ring-cyan-400 ${
                  selected ? 'bg-slate-900' : 'bg-slate-950'
                }`}
              >
                <PlatformIcon id={item.id} className="w-4 h-4 shrink-0" />
                <span className="min-w-0 flex-1 truncate text-sm font-bold text-slate-100">{item.name}</span>
                <span className="shrink-0 text-xs tabular-nums text-slate-300">{percentText(item.usedQuota)}</span>
              </button>
            );
          })}
        </div>
      )}
    </div>
  );
};
