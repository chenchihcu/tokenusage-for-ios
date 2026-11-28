import React, { useEffect, useState } from 'react';
import { CloudOff, RefreshCw, Smartphone, Wifi } from 'lucide-react';
import type { StatusPresentation } from '../network/presentStatus';

interface ConnectionStatusProps {
  status: StatusPresentation;
  busy: boolean;
  onRetry: () => void;
}

export const ConnectionStatus: React.FC<ConnectionStatusProps> = ({
  status,
  busy,
  onRetry,
}) => {
  const [spoken, setSpoken] = useState(status.live ?? '正在確認連線…');

  useEffect(() => {
    if (status.live && status.live !== spoken) setSpoken(status.live);
  }, [status.live, spoken]);

  const Icon = status.checkHint ? CloudOff : status.pathLabel ? Smartphone : Wifi;

  return (
    <div className="w-full border-b border-border-hairline bg-surface-card px-4 py-1 sm:px-6 pl-safe-island pr-safe-island phoneland:py-0">
      <div className="max-w-7xl mx-auto flex flex-nowrap items-center gap-2">
        <p role="status" aria-live="polite" className="flex flex-1 items-center gap-2 text-body text-ink-primary min-h-[44px] phoneland:min-h-[36px] min-w-0">
          <Icon className="w-4 h-4 shrink-0 text-accent-primary" aria-hidden="true" />
          <span className="min-w-0 truncate">{spoken}</span>
          {status.showProgress && busy ? <span className="text-xs text-ink-muted shrink-0">請稍候</span> : null}
        </p>
        {status.pathLabel ? (
          <span className="text-xs font-bold text-ink-secondary px-2.5 py-1 rounded-full bg-surface-muted border border-border-hairline shrink-0">
            {status.pathLabel}
          </span>
        ) : null}
        <button
          type="button"
          onClick={onRetry}
          className="inline-flex items-center gap-1 min-h-[44px] phoneland:min-h-[36px] min-w-[44px] px-3 rounded-xl border border-border-hairline bg-surface-canvas text-body text-ink-primary hover:border-border-strong focus:outline-none focus-visible:ring-2 focus-visible:ring-accent-primary shrink-0"
        >
          <RefreshCw className={`w-4 h-4 ${busy ? 'animate-spin text-accent-primary' : ''}`} aria-hidden="true" />
          重試
        </button>
      </div>
      {status.checkHint ? <p className="text-xs text-ink-secondary pb-1 max-w-3xl">{status.checkHint}</p> : null}
    </div>
  );
};
