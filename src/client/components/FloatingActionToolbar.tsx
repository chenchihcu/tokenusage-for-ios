import React from 'react';
import { AlertTriangle, Gift, RefreshCw, Settings2 } from 'lucide-react';
import { HandednessMode } from './ViewModeSelector';
import { haptic } from '../services/haptics';

interface FastPathToolbarProps {
  handedness: HandednessMode;
  busy: boolean;
  onRefresh: () => void;
  resetBadge: number;
  onOpenResets: () => void;
  alertOnly: boolean;
  alertCount: number;
  onToggleAlerts: () => void;
  onOpenSettings: () => void;
}

/**
 * One-handed fast path: 4 actions in the thumb zone (bottom-trailing for right hand,
 * bottom-leading for left hand; a vertical column in short landscape).
 */
export const FloatingActionToolbar: React.FC<FastPathToolbarProps> = ({
  handedness,
  busy,
  onRefresh,
  resetBadge,
  onOpenResets,
  alertOnly,
  alertCount,
  onToggleAlerts,
  onOpenSettings,
}) => {
  const item =
    'relative flex flex-col items-center justify-center gap-0.5 w-14 max-w-[calc((100vw-3rem)/4)] min-w-[44px] min-h-[48px] overflow-hidden rounded-xl text-xs font-bold text-ink-primary hover:bg-surface-muted/70 active:scale-95 touch-manipulation transition-colors focus:outline-none focus-visible:ring-2 focus-visible:ring-accent-primary';

  return (
    <nav
      aria-label="快速操作"
      className={`fixed fab-safe-bottom z-40 flex phoneland:flex-col items-center gap-1 p-1.5 bg-surface-chrome backdrop-blur-xl rounded-2xl border border-border-hairline shadow-hig-dock ${
        handedness === 'left' ? 'fab-safe-left' : 'fab-safe-right'
      }`}
    >
      <button
        type="button"
        onClick={() => {
          haptic.impactLight();
          onRefresh();
        }}
        disabled={busy}
        aria-label={busy ? '更新中' : '立即更新'}
        className={`${item} disabled:opacity-60`}
      >
        <RefreshCw className={`w-5 h-5 ${busy ? 'animate-spin text-accent-primary' : ''}`} aria-hidden="true" />
        更新
      </button>
      <button
        type="button"
        onClick={() => {
          haptic.impactLight();
          onOpenResets();
        }}
        aria-label={resetBadge > 0 ? `免費重置，${resetBadge} 項可用` : '免費重置與重置時間'}
        className={item}
      >
        <Gift className="w-5 h-5" aria-hidden="true" />
        重置
        {resetBadge > 0 ? (
          <span className="absolute top-0.5 right-1 min-w-[18px] h-[18px] px-1 rounded-full bg-status-healthy text-white text-xs leading-[18px] text-center">
            {resetBadge}
          </span>
        ) : null}
      </button>
      <button
        type="button"
        onClick={() => {
          haptic.impactLight();
          onToggleAlerts();
        }}
        aria-pressed={alertOnly}
        aria-label={alertOnly ? '顯示全部服務' : `只看告警，共 ${alertCount} 項`}
        className={`${item} ${alertOnly ? 'bg-status-warning-bg text-status-warning' : ''}`}
      >
        <AlertTriangle className="w-5 h-5" aria-hidden="true" />
        告警
      </button>
      <button
        type="button"
        onClick={() => {
          haptic.impactLight();
          onOpenSettings();
        }}
        aria-label="設定：外觀、更新頻率與慣用手"
        className={item}
      >
        <Settings2 className="w-5 h-5" aria-hidden="true" />
        設定
      </button>
    </nav>
  );
};
