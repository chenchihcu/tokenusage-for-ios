import React, { useEffect, useMemo, useState } from 'react';
import { Sparkles } from 'lucide-react';
import { SplitViewContainer } from './components/SplitViewContainer';
import { FloatingActionToolbar } from './components/FloatingActionToolbar';
import { QuotaCardProps } from './components/QuotaCard';
import {
  REFRESH_OPTIONS,
  RefreshIntervalSeconds,
  STORAGE_KEY_REFRESH_INTERVAL,
  normalizeRefreshInterval,
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
import { TRACKED_AGENT_IDS } from './usage/usageFacts';

export const STORAGE_KEY_VIEW_MODE = 'opentokenusage_view_mode';
export const STORAGE_KEY_HANDEDNESS = 'opentokenusage_handedness';
export const STORAGE_KEY_FILTER_ALERT = 'opentokenusage_filter_alert';
export const STORAGE_KEY_COLOR_SCHEME = 'color-scheme';

export type ColorSchemePreference = 'system' | 'light' | 'dark';

export { TRACKED_AGENT_IDS };

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

function removeStored(key: string): void {
  try {
    window.localStorage.removeItem(key);
  } catch {}
}

function applyColorSchemeMeta(pref: ColorSchemePreference): void {
  const meta = document.querySelector('meta[name="color-scheme"]');
  if (meta) {
    meta.setAttribute('content', pref === 'system' ? 'light dark' : pref);
  }
}

function readColorScheme(): ColorSchemePreference {
  const saved = readStored(STORAGE_KEY_COLOR_SCHEME);
  if (saved === 'light' || saved === 'dark') return saved;
  return 'system';
}

function replaceUrlParam(name: string, value: string | null): void {
  const url = new URL(window.location.href);
  if (value === null) url.searchParams.delete(name);
  else url.searchParams.set(name, value);
  window.history.replaceState({}, '', url.toString());
}

export const App: React.FC = () => {
  const [quotas, setQuotas] = useState<QuotaCardProps[]>([]);
  const [selectedId, setSelectedId] = useState<string>('codex');
  const [sheet, setSheet] = useState<'resets' | 'settings' | null>(null);
  const [colorScheme, setColorScheme] = useState<ColorSchemePreference>(readColorScheme);

  const [refreshInterval, setRefreshInterval] = useState<RefreshIntervalSeconds>(() => {
    const raw = readStored(STORAGE_KEY_REFRESH_INTERVAL);
    const normalized = normalizeRefreshInterval(raw);
    if (raw !== null && String(normalized) !== raw) {
      writeStored(STORAGE_KEY_REFRESH_INTERVAL, String(normalized));
    }
    return normalized;
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

  const [wide, setWide] = useState<boolean>(() => decideColumns(window.innerWidth, net.textScale) === 'dual');
  useEffect(() => {
    const apply = () => setWide(decideColumns(window.innerWidth, net.textScale) === 'dual');
    apply();
    window.addEventListener('resize', apply);
    return () => window.removeEventListener('resize', apply);
  }, [net.textScale]);

  useEffect(() => {
    applyColorSchemeMeta(colorScheme);
  }, [colorScheme]);

  useEffect(() => {
    const onStorage = (e: StorageEvent) => {
      if (e.key === STORAGE_KEY_COLOR_SCHEME) {
        const next = e.newValue === 'light' || e.newValue === 'dark' ? e.newValue : 'system';
        setColorScheme(next);
      }
    };
    window.addEventListener('storage', onStorage);
    return () => window.removeEventListener('storage', onStorage);
  }, []);

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

  const handleChangeColorScheme = (pref: ColorSchemePreference) => {
    setColorScheme(pref);
    if (pref === 'system') removeStored(STORAGE_KEY_COLOR_SCHEME);
    else writeStored(STORAGE_KEY_COLOR_SCHEME, pref);
    applyColorSchemeMeta(pref);
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
      className="app-viewport relative w-full overflow-hidden bg-surface-canvas text-ink-primary flex flex-col font-sans"
    >
      <header className="w-full h-12 phoneland:h-10 bg-surface-chrome backdrop-blur-md border-b border-border-hairline px-4 sm:px-6 pl-safe-island pr-safe-island flex items-center justify-between gap-2 shrink-0 z-30">
        <div className="flex items-center gap-2.5 min-w-0">
          <div className="w-7 h-7 rounded-lg bg-accent-primary flex items-center justify-center shrink-0">
            <Sparkles className="w-4 h-4 text-white" aria-hidden="true" />
          </div>
          <h1 className="font-bold text-heading-section text-ink-primary truncate">OpenTokenUsage</h1>
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

      <div id="app-content" className="flex-1 min-h-0 min-w-0 relative">
        {quotas.length === 0 ? (
          <div role="status" className="h-full flex flex-col items-center justify-center gap-3 p-8 text-center">
            {net.busy ? (
              <>
                <div className="w-6 h-6 border-2 border-accent-primary border-t-transparent rounded-full animate-spin" />
                <p className="text-body text-ink-secondary">正在讀取額度…</p>
              </>
            ) : (
              <>
                <p className="text-heading-section font-bold text-ink-primary">尚無額度資料</p>
                <p className="text-body text-ink-secondary max-w-xs">
                  目前沒有 Codex、Claude Code、Cursor、Antigravity 的額度紀錄。
                </p>
                <button
                  type="button"
                  onClick={net.refresh}
                  className="min-h-[44px] px-5 rounded-xl bg-surface-card border border-border-hairline shadow-hig-card text-body font-bold text-accent-primary hover:border-border-strong"
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
          <p className="text-body text-ink-secondary">尚無資料。</p>
        ) : (
          <ul>
            {resetSummaries.map(({ item, summary }) => {
              const monitored = (MONITORED_RESET_IDS as readonly string[]).includes(item.id);
              return (
                <li
                  key={item.id}
                  className="flex items-center gap-2.5 min-h-[44px] min-w-0 py-1.5 border-b border-border-hairline last:border-b-0"
                >
                  <PlatformIcon id={item.id} className="w-5 h-5 shrink-0" />
                  <span className="text-body font-bold text-ink-primary truncate">{item.name}</span>
                  <span className="ml-auto min-w-0 text-xs text-ink-secondary tabular-nums truncate">
                    {monitored ? `${creditsLabel(summary.resetCredits)} · ` : ''}
                    {summary.sessionText !== '--' ? `5 小時 ${summary.sessionText} · ` : ''}
                    每週 {summary.weeklyText}
                  </span>
                </li>
              );
            })}
          </ul>
        )}
      </Sheet>

      <Sheet title="設定" open={sheet === 'settings'} onClose={() => setSheet(null)}>
        <fieldset>
          <legend className="text-body font-bold text-ink-secondary mb-1.5">外觀主題</legend>
          <div className="grid grid-cols-3 gap-1.5">
            {(
              [
                { value: 'system', label: '跟隨系統' },
                { value: 'light', label: '淺色' },
                { value: 'dark', label: '深色' },
              ] as const
            ).map((opt) => (
              <label
                key={opt.value}
                className="flex items-center gap-2 min-h-[44px] px-2.5 rounded-xl border border-border-hairline bg-surface-canvas text-body text-ink-primary cursor-pointer"
              >
                <input
                  type="radio"
                  name="color-scheme"
                  checked={colorScheme === opt.value}
                  onChange={() => handleChangeColorScheme(opt.value)}
                  className="w-4 h-4 accent-accent-primary"
                />
                {opt.label}
              </label>
            ))}
          </div>
        </fieldset>

        <fieldset className="mt-4">
          <legend className="text-body font-bold text-ink-secondary mb-1.5">更新頻率</legend>
          <div className="grid grid-cols-2 gap-1.5">
            {REFRESH_OPTIONS.map((o) => (
              <label
                key={o.value}
                className="flex items-center gap-2 min-h-[44px] px-2.5 rounded-xl border border-border-hairline bg-surface-canvas text-body text-ink-primary cursor-pointer"
              >
                <input
                  type="radio"
                  name="refresh-interval"
                  checked={refreshInterval === o.value}
                  onChange={() => handleChangeInterval(o.value)}
                  className="w-4 h-4 accent-accent-primary"
                />
                {o.label}
              </label>
            ))}
          </div>
          <p className="text-xs text-ink-muted mt-1.5 px-1">前景依此更新。背景時間由瀏覽器或系統決定。</p>
        </fieldset>

        <fieldset className="mt-4">
          <legend className="text-body font-bold text-ink-secondary mb-1.5">慣用手</legend>
          <div className="grid grid-cols-2 gap-1.5">
            {(['right', 'left'] as const).map((h) => (
              <label
                key={h}
                className="flex items-center gap-2.5 min-h-[44px] px-2.5 rounded-xl border border-border-hairline bg-surface-canvas text-body text-ink-primary cursor-pointer"
              >
                <input
                  type="radio"
                  name="handedness"
                  checked={handedness === h}
                  onChange={() => handleChangeHandedness(h)}
                  className="w-4 h-4 accent-accent-primary"
                />
                {h === 'right' ? '右手' : '左手'}
              </label>
            ))}
          </div>
        </fieldset>
      </Sheet>
    </div>
  );
};

export default App;
