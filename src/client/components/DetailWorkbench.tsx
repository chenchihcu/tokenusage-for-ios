import React, { useMemo } from 'react';
import { QuotaCardProps } from './QuotaCard';
import { HandednessMode } from './ViewModeSelector';
import { PlatformIcon } from './PlatformIcon';
import { PanelLeftClose, PanelLeftOpen } from 'lucide-react';
import { haptic } from '../services/haptics';
import { buildAgentUsage, modelText, percentText } from '../usage/usageFacts';

interface DetailWorkbenchProps {
  selectedItem: QuotaCardProps | undefined;
  isFocusMode: boolean;
  onToggleFocus: () => void;
  handedness?: HandednessMode;
  connectionLabel?: string;
}

export const DetailWorkbench: React.FC<DetailWorkbenchProps> = ({
  selectedItem,
  isFocusMode,
  onToggleFocus,
  connectionLabel = '待確認',
}) => {
  const usage = useMemo(() => (selectedItem ? buildAgentUsage(selectedItem) : null), [selectedItem]);

  if (!selectedItem || !usage) {
    return (
      <div className="flex h-full items-center justify-center p-4 text-body text-ink-secondary">
        選擇一個服務
      </div>
    );
  }

  const cells = [
    { label: '模型', value: modelText(usage) },
    { label: '5 小時', value: percentText(usage.sessionUsed) },
    { label: '每週', value: percentText(usage.weekUsed) },
    { label: '費用', value: usage.feeText ?? '未提供' },
  ];

  return (
    <div className="usage-board fab-clearance flex flex-col h-full min-h-0 overflow-hidden bg-surface-canvas text-ink-primary">
      <div className="shrink-0 h-11 px-3 flex items-center gap-2 border-b border-border-hairline bg-surface-card">
        <button
          type="button"
          onClick={() => {
            haptic.impactLight();
            onToggleFocus();
          }}
          aria-label={isFocusMode ? '展開清單' : '隱藏清單'}
          className="min-h-[44px] min-w-[44px] flex items-center justify-center rounded-xl text-ink-secondary hover:bg-surface-muted focus:outline-none focus-visible:ring-2 focus-visible:ring-accent-primary"
        >
          {isFocusMode ? <PanelLeftOpen className="w-5 h-5" /> : <PanelLeftClose className="w-5 h-5" />}
        </button>
        <PlatformIcon id={selectedItem.id} className="w-5 h-5 shrink-0" />
        <h2 id="detail-title" tabIndex={-1} className="min-w-0 truncate text-heading-section font-bold outline-none">
          {selectedItem.name}
        </h2>
        <span className="shrink-0 text-xs text-ink-muted">{selectedItem.planName}</span>
        <span className="ml-auto shrink-0 text-xs text-ink-secondary truncate">{connectionLabel}</span>
      </div>

      <div className="flex-1 min-h-0 grid grid-cols-2 grid-rows-2 gap-2.5 p-3">
        {cells.map((cell) => (
          <div
            key={cell.label}
            className="min-h-0 min-w-0 overflow-hidden rounded-2xl border border-border-hairline bg-surface-card shadow-hig-card px-3.5 py-2.5 flex flex-col justify-center"
          >
            <div className="text-xs text-ink-muted">{cell.label}</div>
            <div className="text-body font-bold text-ink-primary tabular-nums truncate mt-0.5">{cell.value}</div>
          </div>
        ))}
      </div>

      <p className="shrink-0 px-3.5 h-8 flex items-center text-xs text-ink-secondary tabular-nums">
        已用 {percentText(usage.usedPercent)} · 剩餘 {percentText(usage.remainingPercent)}
      </p>
    </div>
  );
};
