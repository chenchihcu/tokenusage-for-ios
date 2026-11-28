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
    <div className="flex flex-col h-full min-h-0 overflow-hidden bg-surface-card border-r border-border-hairline">
      <div className="px-3.5 h-11 phoneland:hidden shrink-0 flex items-center justify-between border-b border-border-hairline">
        <h2 className="text-heading-section font-bold text-ink-primary">服務</h2>
        <span className="text-xs text-ink-muted tabular-nums">{quotas.length}</span>
      </div>

      {isLoading ? (
        <p role="status" className="flex-1 flex items-center justify-center text-body text-ink-secondary">
          正在讀取額度
        </p>
      ) : quotas.length === 0 ? (
        <p className="flex-1 flex items-center justify-center text-body text-ink-secondary">沒有符合的服務</p>
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
                className={`min-h-0 h-full w-full overflow-hidden flex items-center gap-2.5 px-3.5 text-left border-b border-border-hairline transition-colors focus:outline-none focus-visible:ring-2 focus-visible:ring-accent-primary ${
                  selected ? 'bg-accent-tint' : 'bg-surface-card hover:bg-surface-canvas'
                }`}
              >
                <PlatformIcon id={item.id} className="w-5 h-5 shrink-0" />
                <span className="min-w-0 flex-1 truncate text-body font-bold text-ink-primary">{item.name}</span>
                <span className="shrink-0 text-xs tabular-nums font-bold text-ink-secondary">
                  {percentText(item.usedQuota)}
                </span>
              </button>
            );
          })}
        </div>
      )}
    </div>
  );
};
