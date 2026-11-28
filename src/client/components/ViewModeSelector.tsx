import React from 'react';
import { LayoutGrid, Columns2 } from 'lucide-react';
import { haptic } from '../services/haptics';

export type DashboardViewMode = 'cockpit' | 'split';
export type HandednessMode = 'right' | 'left';

export interface ViewModeSelectorProps {
  currentMode: DashboardViewMode;
  onChangeMode: (mode: DashboardViewMode) => void;
  governingAlertCount?: number;
}

export const ViewModeSelector: React.FC<ViewModeSelectorProps> = ({
  currentMode,
  onChangeMode,
  governingAlertCount = 0,
}) => {
  const handleSelectMode = (mode: DashboardViewMode) => {
    haptic.impactMedium();
    onChangeMode(mode);
  };

  return (
    <nav
      aria-label="視圖模式切換器"
      className="inline-flex items-center p-1 rounded-xl bg-surface-muted/80 border border-border-hairline select-none"
    >
      <button
        type="button"
        onClick={() => handleSelectMode('cockpit')}
        aria-pressed={currentMode === 'cockpit'}
        className={`relative flex items-center justify-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-bold transition-colors min-h-[44px] sm:min-h-[36px] touch-manipulation focus:outline-none focus-visible:ring-2 focus-visible:ring-accent-primary ${
          currentMode === 'cockpit'
            ? 'bg-surface-card text-ink-primary shadow-hig-card'
            : 'text-ink-secondary hover:text-ink-primary'
        }`}
      >
        <LayoutGrid className="w-4 h-4" aria-hidden="true" />
        <span>全景</span>
        {governingAlertCount > 0 && (
          <span
            className="flex h-2 w-2 relative ml-0.5"
            title={`${governingAlertCount} 個平台處於耗盡或告警狀態`}
          >
            <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-status-critical opacity-75" />
            <span className="relative inline-flex rounded-full h-2 w-2 bg-status-critical" />
          </span>
        )}
      </button>

      <button
        type="button"
        onClick={() => handleSelectMode('split')}
        aria-pressed={currentMode === 'split'}
        className={`flex items-center justify-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-bold transition-colors min-h-[44px] sm:min-h-[36px] touch-manipulation focus:outline-none focus-visible:ring-2 focus-visible:ring-accent-primary ${
          currentMode === 'split'
            ? 'bg-surface-card text-ink-primary shadow-hig-card'
            : 'text-ink-secondary hover:text-ink-primary'
        }`}
      >
        <Columns2 className="w-4 h-4" aria-hidden="true" />
        <span>雙欄</span>
      </button>
    </nav>
  );
};
