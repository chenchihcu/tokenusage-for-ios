import React, { useMemo, useState } from 'react';
import { QuotaCard, QuotaCardProps } from './QuotaCard';
import { HandednessMode } from './ViewModeSelector';
import {
  USAGE_GROUPS,
  UsageGroupId,
  buildAgentUsage,
  isUsageGroup,
  orderAgents,
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

  const visibleQuotas = useMemo(
    () => (filterAlertOnly ? quotas.filter((item) => item.remainingPercent <= 20) : quotas),
    [quotas, filterAlertOnly],
  );

  const rows = useMemo(
    () => orderAgents(visibleQuotas.map(buildAgentUsage), group),
    [visibleQuotas, group],
  );

  const chooseGroup = (next: UsageGroupId) => {
    setGroup(next);
    storeGroup(next);
  };

  return (
    <div
      data-usage-board
      className="bento-board usage-board fab-clearance flex flex-col h-full min-h-0 min-w-0 w-full max-w-7xl mx-auto overflow-y-auto phoneland:overflow-hidden bg-surface-canvas select-none"
    >
      {/* Apple HIG Segmented Control */}
      <div className="shrink-0 px-3 sm:px-6 pt-2.5 phoneland:pt-1 pb-1.5 phoneland:pb-0.5">
        <div
          role="tablist"
          aria-label="用量分組"
          className="flex flex-nowrap gap-1 p-1 phoneland:p-0.5 rounded-xl bg-surface-muted/80 border border-border-hairline"
        >
          {USAGE_GROUPS.map((item) => {
            const selected = group === item.id;
            return (
              <button
                key={item.id}
                type="button"
                role="tab"
                aria-selected={selected}
                onClick={() => chooseGroup(item.id)}
                className={`flex-1 min-w-0 min-h-[44px] phoneland:min-h-[32px] px-2 rounded-lg text-xs whitespace-nowrap transition-colors focus:outline-none focus-visible:ring-2 focus-visible:ring-accent-primary ${
                  selected
                    ? 'bg-surface-card text-ink-primary font-bold shadow-hig-card'
                    : 'text-ink-secondary font-normal hover:text-ink-primary'
                }`}
              >
                {item.label}
              </button>
            );
          })}
        </div>
      </div>

      {rows.length === 0 ? (
        <p role="status" className="flex-1 flex items-center justify-center text-body text-ink-secondary px-4">
          沒有剩餘 20% 以下的服務
        </p>
      ) : (
        <div
          role="list"
          aria-label="四個服務的額度"
          className="bento-grid flex-1 min-h-0 min-w-0 grid grid-cols-1 gap-1.5 sm:gap-3 phoneland:grid-cols-2 phoneland:grid-rows-2 phoneland:gap-1.5 px-3 sm:px-6 py-1 sm:py-2 phoneland:py-0.5 content-start phoneland:content-stretch"
        >
          {rows.map((row) => {
            const fullQuota = visibleQuotas.find((q) => q.id === row.id);
            if (!fullQuota) return null;
            return (
              <div key={row.id} role="listitem" className="min-w-0 phoneland:min-h-0 phoneland:h-full">
                <QuotaCard
                  {...fullQuota}
                  usage={row}
                  isSelected={row.id === selectedId}
                  highlightKey={group}
                  onClick={() => {
                    onSelectPlatform(row.id);
                    onOpenDetail(row.id);
                  }}
                />
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
};
