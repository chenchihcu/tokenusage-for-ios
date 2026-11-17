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
    <div className="w-full border-b border-slate-800/80 bg-slate-950/95 px-4 py-1.5 sm:px-6 pl-safe-island pr-safe-island phoneland:py-0">
      <div className="max-w-7xl mx-auto flex flex-nowrap items-center gap-2">
        <p role="status" aria-live="polite" className="flex flex-1 items-center gap-2 text-sm text-slate-100 min-h-[44px] min-w-0">
          <Icon className="w-4 h-4 shrink-0 text-cyan-300" aria-hidden="true" />
          <span className="min-w-0">{spoken}</span>
          {status.showProgress && busy ? <span className="text-xs text-slate-400">請稍候</span> : null}
        </p>
        {status.pathLabel ? (
          <span className="text-xs font-medium text-slate-300 px-2 py-1 rounded-full border border-slate-700">
            {status.pathLabel}
          </span>
        ) : null}
        <button
          type="button"
          onClick={onRetry}
          className="inline-flex items-center gap-1 min-h-[44px] min-w-[44px] px-3 rounded-xl border border-slate-700 text-sm text-slate-100"
        >
          <RefreshCw className={`w-4 h-4 ${busy ? 'animate-spin' : ''}`} aria-hidden="true" />
          重試
        </button>
      </div>
      {status.checkHint ? <p className="text-xs text-slate-400 pb-1 max-w-3xl">{status.checkHint}</p> : null}
    </div>
  );
};
