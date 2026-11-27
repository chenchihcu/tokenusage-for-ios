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
}

export const DetailWorkbench: React.FC<DetailWorkbenchProps> = ({
  selectedItem,
  isFocusMode,
  onToggleFocus,
}) => {
  const usage = useMemo(() => (selectedItem ? buildAgentUsage(selectedItem) : null), [selectedItem]);

  if (!selectedItem || !usage) {
    return (
      <div className="flex h-full items-center justify-center p-4 text-sm text-slate-300">
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
    <div className="usage-board fab-clearance flex flex-col h-full min-h-0 overflow-hidden text-slate-100">
      <div className="shrink-0 h-11 px-2 flex items-center gap-2 border-b border-slate-800">
        <button
          type="button"
          onClick={() => {
            haptic.impactLight();
            onToggleFocus();
          }}
          aria-label={isFocusMode ? '展開清單' : '隱藏清單'}
          className="min-h-[44px] min-w-[44px] flex items-center justify-center rounded-lg text-slate-300 focus:outline-none focus-visible:ring-2 focus-visible:ring-cyan-400"
        >
          {isFocusMode ? <PanelLeftOpen className="w-5 h-5" /> : <PanelLeftClose className="w-5 h-5" />}
        </button>
        <PlatformIcon id={selectedItem.id} className="w-4 h-4 shrink-0" />
        <h2 id="detail-title" tabIndex={-1} className="min-w-0 truncate text-base font-bold outline-none">
          {selectedItem.name}
        </h2>
      </div>

      <div className="flex-1 min-h-0 grid grid-cols-2 grid-rows-2 gap-2 p-2">
        {cells.map((cell) => (
          <div key={cell.label} className="min-h-0 min-w-0 overflow-hidden rounded-xl border border-slate-800 bg-slate-900/70 px-3 py-2">
            <div className="text-xs text-slate-400">{cell.label}</div>
            <div className="text-sm font-bold tabular-nums truncate">{cell.value}</div>
          </div>
        ))}
      </div>
    </div>
  );
};
