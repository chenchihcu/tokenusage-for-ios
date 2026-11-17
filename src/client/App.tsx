import React, { useEffect, useMemo, useState } from 'react';
import { StatusBar, Style } from '@capacitor/status-bar';
import { Sparkles } from 'lucide-react';
import { SplitViewContainer } from './components/SplitViewContainer';
import { FloatingActionToolbar } from './components/FloatingActionToolbar';
import { QuotaCardProps } from './components/QuotaCard';
import {
  REFRESH_OPTIONS,
  RefreshIntervalSeconds,
  STORAGE_KEY_REFRESH_INTERVAL,
} from './components/FrequencySelector';
import { ViewModeSelector, DashboardViewMode, HandednessMode } from './components/ViewModeSelector';
import { ConnectionStatus } from './components/ConnectionStatus';
import { ResetMonitorBar, MONITORED_RESET_IDS, creditsLabel } from './components/ResetMonitorBar';
import { PlatformIcon } from './components/PlatformIcon';
import { Sheet } from './components/Sheet';
import { SecureStorageService } from './services/storage';
import { useDirectInternet } from './hooks/useDirectInternet';
import { decideColumns } from './network/layout';
import { extractResetWindowSummary } from './utils/resetMonitor';

export const STORAGE_KEY_VIEW_MODE = 'opentokenusage_view_mode';
export const STORAGE_KEY_HANDEDNESS = 'opentokenusage_handedness';
export const STORAGE_KEY_FILTER_ALERT = 'opentokenusage_filter_alert';

/** The four tracked agents, in display order. Anything else from the server is ignored. */
export const TRACKED_AGENT_IDS = ['codex', 'claude', 'cursor', 'antigravity'] as const;

function keepTrackedAgents(items: QuotaCardProps[]): QuotaCardProps[] {
  return TRACKED_AGENT_IDS.map((id) => items.find((q) => q.id === id)).filter(
    (q): q is QuotaCardProps => Boolean(q),
  );
}

function readStored(key: string): string | null {
  try {
    return window.localStorage.getItem(key);
  } catch {
    return null;
  }
}

function writeStored(key: string, value: string): void {
  try {
    window.localStorage.setItem(key, value);
  } catch {}
}

function replaceUrlParam(name: string, value: string | null): void {
  const url = new URL(window.location.href);
  if (value === null) url.searchParams.delete(name);
  else url.searchParams.set(name, value);
  window.history.replaceState({}, '', url.toString());
}

export const App: React.FC = () => {
  // No built-in numbers: until the server (or the display cache) answers, the screen says so.
  const [quotas, setQuotas] = useState<QuotaCardProps[]>([]);
  const [selectedId, setSelectedId] = useState<string>('codex');
  const [sheet, setSheet] = useState<'resets' | 'settings' | null>(null);

  const [refreshInterval, setRefreshInterval] = useState<RefreshIntervalSeconds>(() => {
    const parsed = Number(readStored(STORAGE_KEY_REFRESH_INTERVAL));
    return REFRESH_OPTIONS.some((o) => o.value === parsed) && readStored(STORAGE_KEY_REFRESH_INTERVAL) !== null
      ? (parsed as RefreshIntervalSeconds)
      : 60;
  });

  const net = useDirectInternet({
    refreshInterval,
    onQuotas: (items) => setQuotas(keepTrackedAgents(items)),
  });

  const [viewMode, setViewMode] = useState<DashboardViewMode>(() => {
    const fromUrl = new URLSearchParams(window.location.search).get('view');
    if (fromUrl === 'cockpit' || fromUrl === 'split') return fromUrl;
    const saved = readStored(STORAGE_KEY_VIEW_MODE);
    return saved === 'split' ? 'split' : 'cockpit';
  });

  const [handedness, setHandedness] = useState<HandednessMode>(() => {
    const fromUrl = new URLSearchParams(window.location.search).get('handed');
    const value = fromUrl ?? readStored(STORAGE_KEY_HANDEDNESS);
    return value === 'left' ? 'left' : 'right';
  });

  const [filterAlertOnly, setFilterAlertOnly] = useState<boolean>(() => {
    if (new URLSearchParams(window.location.search).get('filter') === 'alert') return true;
    return readStored(STORAGE_KEY_FILTER_ALERT) === '1';
  });

  // The 全景/雙欄 switch only appears when two columns actually fit (V8).
  const [wide, setWide] = useState<boolean>(() => decideColumns(window.innerWidth, net.textScale) === 'dual');
  useEffect(() => {
    const apply = () => setWide(decideColumns(window.innerWidth, net.textScale) === 'dual');
    apply();
    window.addEventListener('resize', apply);
    return () => window.removeEventListener('resize', apply);
  }, [net.textScale]);

  useEffect(() => {
    try {
      StatusBar.setStyle({ style: Style.Dark });
      StatusBar.setBackgroundColor({ color: '#020617' });
    } catch {}
  }, []);

  // Display snapshot shared with the widget / offline view.
  useEffect(() => {
    if (quotas.length === 0) return;
    void SecureStorageService.setItem('opentokenusage_cached_quotas', JSON.stringify(quotas)).catch(() => {});
  }, [quotas]);

  useEffect(() => {
    if (quotas.length > 0 && !quotas.some((q) => q.id === selectedId)) setSelectedId(quotas[0].id);
  }, [quotas, selectedId]);

  const handleChangeViewMode = (mode: DashboardViewMode) => {
    setViewMode(mode);
    writeStored(STORAGE_KEY_VIEW_MODE, mode);
    replaceUrlParam('view', mode);
  };

  const handleChangeHandedness = (h: HandednessMode) => {
    setHandedness(h);
    writeStored(STORAGE_KEY_HANDEDNESS, h);
    replaceUrlParam('handed', h);
  };

  const handleToggleFilterAlert = () => {
    const next = !filterAlertOnly;
    setFilterAlertOnly(next);
    writeStored(STORAGE_KEY_FILTER_ALERT, next ? '1' : '0');
    replaceUrlParam('filter', next ? 'alert' : null);
  };

  const handleChangeInterval = (value: RefreshIntervalSeconds) => {
    setRefreshInterval(value);
    writeStored(STORAGE_KEY_REFRESH_INTERVAL, String(value));
    if (value > 0) net.refresh();
  };

  const resetSummaries = useMemo(
    () => quotas.map((q) => ({ item: q, summary: extractResetWindowSummary(q) })),
    [quotas],
  );
  const resetBadge = resetSummaries
    .filter(({ item }) => (MONITORED_RESET_IDS as readonly string[]).includes(item.id))
    .reduce((sum, { summary }) => sum + (summary.resetCredits ?? 0), 0);
  const alertCount = quotas.filter((q) => q.remainingPercent <= 20).length;
  const effectiveViewMode: DashboardViewMode = wide ? viewMode : 'cockpit';

  return (
    <div
      data-hand={handedness}
      className="app-viewport relative w-full overflow-hidden bg-slate-950 text-slate-100 flex flex-col font-sans"
    >
      <header className="w-full bg-slate-950 border-b border-slate-800/80 px-4 py-1.5 sm:px-6 pl-safe-island pr-safe-island flex items-center justify-between gap-2 shrink-0 z-30">
        <div className="flex items-center gap-2 min-w-0">
          <div className="w-7 h-7 rounded-lg bg-gradient-to-br from-cyan-400 via-purple-500 to-pink-500 flex items-center justify-center shrink-0">
            <Sparkles className="w-4 h-4 text-slate-950" aria-hidden="true" />
          </div>
          <h1 className="font-bold text-base text-slate-100 truncate">OpenTokenUsage</h1>
        </div>
        {wide ? (
          <ViewModeSelector
            currentMode={viewMode}
            onChangeMode={handleChangeViewMode}
            governingAlertCount={quotas.filter((q) => q.remainingPercent <= 5).length}
          />
        ) : null}
      </header>

      <ConnectionStatus status={net.status} busy={net.busy} onRetry={net.refresh} />

      <ResetMonitorBar quotas={quotas} activePlatformId={selectedId} onSelectPlatform={setSelectedId} />

      <div id="app-content" className="flex-1 min-h-0 relative">
        {quotas.length === 0 ? (
          <div role="status" className="h-full flex flex-col items-center justify-center gap-3 p-8 text-center">
            {net.busy ? (
              <>
                <div className="w-6 h-6 border-2 border-cyan-400 border-t-transparent rounded-full animate-spin" />
                <p className="text-base text-slate-200">正在讀取額度…</p>
              </>
            ) : (
              <>
                <p className="text-base font-bold text-slate-100">尚無額度資料</p>
                <p className="text-sm text-slate-400 max-w-xs">目前沒有 Codex、Claude Code、Cursor、Antigravity 的額度紀錄。</p>
                <button
                  type="button"
                  onClick={net.refresh}
                  className="min-h-[44px] px-4 rounded-xl border border-slate-700 text-base text-slate-100"
                >
                  重新讀取
                </button>
              </>
            )}
          </div>
        ) : (
          <SplitViewContainer
            quotas={quotas}
            selectedId={selectedId}
            onSelect={setSelectedId}
            isLoading={false}
            viewMode={effectiveViewMode}
            onChangeViewMode={handleChangeViewMode}
            isOnline={net.linkLabel === '已同步'}
            linkLabel={net.linkLabel}
            textScale={net.textScale}
            countdownSeconds={net.countdown}
            handedness={handedness}
            filterAlertOnly={filterAlertOnly}
            onToggleFilterAlert={handleToggleFilterAlert}
          />
        )}
      </div>

      <FloatingActionToolbar
        handedness={handedness}
        busy={net.busy}
        onRefresh={net.refresh}
        resetBadge={resetBadge}
        onOpenResets={() => setSheet('resets')}
        alertOnly={filterAlertOnly}
        alertCount={alertCount}
        onToggleAlerts={handleToggleFilterAlert}
        onOpenSettings={() => setSheet('settings')}
      />

      <Sheet title="免費重置與重置時間" open={sheet === 'resets'} onClose={() => setSheet(null)}>
        {resetSummaries.length === 0 ? (
          <p className="text-sm text-slate-300">尚無資料。</p>
        ) : (
          <ul className="space-y-2">
            {resetSummaries.map(({ item, summary }) => {
              const monitored = (MONITORED_RESET_IDS as readonly string[]).includes(item.id);
              return (
                <li key={item.id} className="rounded-xl border border-slate-800 bg-slate-950 p-3">
                  <div className="flex items-center gap-2 text-base font-bold text-slate-100">
                    <PlatformIcon id={item.id} className="w-4 h-4" />
                    {item.name}
                  </div>
                  {monitored ? (
                    <p
                      className={`mt-1 text-sm font-bold ${
                        (summary.resetCredits ?? 0) > 0 ? 'text-emerald-300' : 'text-slate-300'
                      }`}
                    >
                      {creditsLabel(summary.resetCredits)}
                    </p>
                  ) : null}
                  <p className="mt-1 text-sm text-slate-300 tabular-nums">
                    {summary.sessionText !== '--' ? `5 小時：${summary.sessionText} · ` : ''}每週：{summary.weeklyText}
                  </p>
                </li>
              );
            })}
          </ul>
        )}
      </Sheet>

      <Sheet title="設定" open={sheet === 'settings'} onClose={() => setSheet(null)}>
        <fieldset className="space-y-1">
          <legend className="text-sm font-bold text-slate-300 mb-1">更新頻率</legend>
          {REFRESH_OPTIONS.map((o) => (
            <label key={o.value} className="flex items-center gap-3 min-h-[44px] px-2 rounded-xl text-base text-slate-100">
              <input
                type="radio"
                name="refresh-interval"
                checked={refreshInterval === o.value}
                onChange={() => handleChangeInterval(o.value)}
                className="w-5 h-5 accent-cyan-400"
              />
              {o.label}
            </label>
          ))}
          <p className="text-xs text-slate-400 px-2">App 在前景時依此頻率更新；背景更新時間由 iOS 決定。</p>
        </fieldset>
        <fieldset className="space-y-1 mt-4">
          <legend className="text-sm font-bold text-slate-300 mb-1">慣用手（快速操作位置）</legend>
          {(['right', 'left'] as const).map((h) => (
            <label key={h} className="flex items-center gap-3 min-h-[44px] px-2 rounded-xl text-base text-slate-100">
              <input
                type="radio"
                name="handedness"
                checked={handedness === h}
                onChange={() => handleChangeHandedness(h)}
                className="w-5 h-5 accent-cyan-400"
              />
              {h === 'right' ? '右手' : '左手'}
            </label>
          ))}
        </fieldset>
      </Sheet>
    </div>
  );
};

export default App;
