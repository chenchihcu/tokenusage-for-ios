import React, { useMemo, useState } from 'react';
import { QuotaCardProps } from './QuotaCard';
import { HandednessMode } from './ViewModeSelector';
import { PlatformIcon } from './PlatformIcon';
import {
  USAGE_GROUPS,
  UsageGroupId,
  buildAgentUsage,
  isUsageGroup,
  levelWord,
  modelText,
  orderAgents,
  percentText,
} from '../usage/usageFacts';

interface CockpitOverviewProps {
  quotas: QuotaCardProps[];
  selectedId: string;
  onSelectPlatform: (id: string) => void;
  onOpenDetail: (id: string) => void;
  isOnline: boolean;
  linkLabel?: string;
  countdownSeconds: number;
  filterAlertOnly?: boolean;
  onToggleFilterAlert?: () => void;
  handedness?: HandednessMode;
  compact?: boolean;
}

const STORAGE_KEY_USAGE_GROUP = 'opentokenusage_usage_group';

const SELECTED_BORDER: Record<string, string> = {
  cursor: 'border-cyan-400',
  codex: 'border-emerald-400',
  antigravity: 'border-purple-400',
  claude: 'border-amber-400',
};

function readGroup(): UsageGroupId {
  try {
    const fromUrl = new URLSearchParams(window.location.search).get('group');
    if (isUsageGroup(fromUrl)) return fromUrl;
    const saved = window.localStorage.getItem(STORAGE_KEY_USAGE_GROUP);
    if (isUsageGroup(saved)) return saved;
  } catch {
    /* private mode */
  }
  return 'agent';
}

function storeGroup(group: UsageGroupId): void {
  try {
    window.localStorage.setItem(STORAGE_KEY_USAGE_GROUP, group);
    const url = new URL(window.location.href);
    url.searchParams.set('group', group);
    window.history.replaceState({}, '', url.toString());
  } catch {
    /* private mode */
  }
}

export const CockpitOverview: React.FC<CockpitOverviewProps> = ({
  quotas,
  selectedId,
  onSelectPlatform,
  onOpenDetail,
  filterAlertOnly = false,
}) => {
  const [group, setGroup] = useState<UsageGroupId>(readGroup);

  const rows = useMemo(() => {
    const visible = filterAlertOnly ? quotas.filter((item) => item.remainingPercent <= 20) : quotas;
    return orderAgents(visible.map(buildAgentUsage), group);
  }, [quotas, filterAlertOnly, group]);

  const chooseGroup = (next: UsageGroupId) => {
    setGroup(next);
    storeGroup(next);
  };

  const hot = (id: UsageGroupId) => (group === id ? 'text-cyan-300 font-bold' : 'text-slate-300 font-normal');

  return (
    <div
      data-usage-board
      className="usage-board fab-clearance flex flex-col h-full min-h-0 min-w-0 w-full max-w-full overflow-hidden bg-slate-950 select-none"
    >
      <div role="tablist" aria-label="用量分組" className="shrink-0 flex flex-nowrap gap-1 px-2 pt-1">
        {USAGE_GROUPS.map((item) => {
          const selected = group === item.id;
          return (
            <button
              key={item.id}
              type="button"
              role="tab"
              aria-selected={selected}
              onClick={() => chooseGroup(item.id)}
              className={`flex-1 min-w-0 min-h-[44px] px-1 rounded-lg text-xs whitespace-nowrap focus:outline-none focus-visible:ring-2 focus-visible:ring-cyan-400 ${
                selected ? 'bg-slate-800 text-cyan-300 font-bold' : 'text-slate-400 font-normal'
              }`}
            >
              {item.label}
            </button>
          );
        })}
      </div>

      {rows.length === 0 ? (
        <p role="status" className="flex-1 flex items-center justify-center text-sm text-slate-300">
          沒有剩餘 20% 以下的服務
        </p>
      ) : (
        <div
          role="list"
          aria-label="四個服務的額度"
          className="flex-1 min-h-0 min-w-0 grid gap-1 px-2 py-1"
          style={{ gridTemplateRows: `repeat(${rows.length}, minmax(0, 1fr))` }}
        >
          {rows.map((row) => {
            const level = levelWord(row.remainingPercent);
            const selected = row.id === selectedId;
            return (
              <div key={row.id} role="listitem" className="min-h-0 min-w-0 h-full">
              <button
                type="button"
                aria-pressed={selected}
                onClick={() => onSelectPlatform(row.id)}
                onDoubleClick={() => onOpenDetail(row.id)}
                className={`min-h-0 min-w-0 h-full w-full overflow-hidden flex items-center gap-2 px-2 rounded-xl border text-left focus:outline-none focus-visible:ring-2 focus-visible:ring-cyan-400 ${
                  selected
                    ? `bg-slate-900 ${SELECTED_BORDER[row.id] ?? 'border-cyan-400'}`
                    : 'bg-slate-900/60 border-slate-800'
                }`}
              >
                <PlatformIcon id={row.id} className="w-4 h-4 shrink-0" />
                <span className="min-w-0 flex-1 overflow-hidden">
                  <span className="flex items-center gap-1 min-w-0">
                    <h3 className="min-w-0 text-sm font-bold text-slate-100 truncate">{row.name}</h3>
                    {level ? <span className="shrink-0 text-xs font-bold text-rose-300">{level}</span> : null}
                  </span>
                  <span className={`block text-xs truncate ${hot('model')}`}>模型 {modelText(row)}</span>
                </span>
                <span className="min-w-0 max-w-[62%] truncate text-xs tabular-nums text-slate-300 font-normal">
                  5小時 {percentText(row.sessionUsed)} · 每週 {percentText(row.weekUsed)} · 費用 {row.feeText ?? '未提供'}
                </span>
              </button>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
};
