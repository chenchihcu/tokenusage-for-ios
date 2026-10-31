import React, { useState, useEffect, useRef, useCallback } from 'react';
import { SplitViewContainer } from './components/SplitViewContainer';
import { FloatingActionToolbar } from './components/FloatingActionToolbar';
import { ModelSyncModal } from './components/ModelSyncModal';
import { QuotaCardProps } from './components/QuotaCard';
import { LiveBar, LiveBarSegment } from './components/LiveBar';
import { FrequencySelector, RefreshIntervalSeconds, STORAGE_KEY_REFRESH_INTERVAL } from './components/FrequencySelector';
import { ViewModeSelector, DashboardViewMode, HandednessMode } from './components/ViewModeSelector';

export const STORAGE_KEY_VIEW_MODE = 'opentokenusage_view_mode';
export const STORAGE_KEY_HANDEDNESS = 'opentokenusage_handedness';
export const STORAGE_KEY_FILTER_ALERT = 'opentokenusage_filter_alert';
import { Shield, Sparkles } from 'lucide-react';

// 5 大平台專屬真實基準快照 (100% SSOT Default)
const INITIAL_REAL_QUOTAS: QuotaCardProps[] = [
  {
    id: 'cursor',
    name: 'Cursor',
    planName: 'Premium',
    totalQuota: 100,
    usedQuota: 100,
    remainingPercent: 0,
    resetTime: '2026-11-03T12:12:52.768Z',
    status: 'active',
    metrics_json: JSON.stringify([
      { label: 'Total usage', used: 100.0, limit: 100.0, kind: 'percent', isAlert: true },
      { label: 'Auto usage', used: 100.0, limit: 100.0, kind: 'percent' },
      { label: 'Grok Bot', used: 100.0, limit: 100.0, kind: 'percent' },
      { label: 'API usage', used: 0.0, limit: 100.0, kind: 'percent' }
    ]),
    fetched_at: '2026-10-30T17:55:18.457747Z'
  },
  {
    id: 'codex',
    name: 'Codex',
    planName: 'Plus',
    totalQuota: 100,
    usedQuota: 100,
    remainingPercent: 0,
    resetTime: '2026-11-04T06:48:16.000Z',
    status: 'active',
    metrics_json: JSON.stringify([
      { label: 'Session', used: 0.0, limit: 100.0, kind: 'percent' },
      { label: 'Weekly (Shared)', used: 100.0, limit: 100.0, kind: 'percent', isAlert: true },
      { label: 'Resets', value: '0 available' },
      { label: 'Credits', value: '$0.00' }
    ]),
    fetched_at: '2026-10-30T22:57:15.1249828Z'
  },
  {
    id: 'antigravity',
    name: 'Google Antigravity',
    planName: 'Google AI Pro',
    totalQuota: 100,
    usedQuota: 69,
    remainingPercent: 31,
    resetTime: '2026-11-02T16:54:00Z',
    status: 'active',
    metrics_json: JSON.stringify([
      { label: 'Gemini (5h)', used: 5.0, limit: 100.0, kind: 'percent' },
      { label: 'Gemini (週)', used: 69.0, limit: 100.0, kind: 'percent' },
      { label: 'Claude (週)', used: 54.0, limit: 100.0, kind: 'percent' },
      { label: 'Argon', used: 100.0, limit: 100.0, kind: 'percent', isAlert: true }
    ]),
    token_pools_json: JSON.stringify([
      {
        id: 'gemini_models',
        name: 'Gemini Models',
        effectiveRemaining: 31.0,
        effectiveUsed: 69.0,
        primaryResetTime: '2026-11-02T16:54:00Z',
        isCritical: false,
        tiers: [
          { id: 'weekly', label: 'Weekly limit', used: 69.0, limit: 100.0, remaining: 31.0, resetsAt: '2026-11-02T16:54:00Z', resetDurationText: '2d 9h', isGoverning: true },
          { id: '5h', label: '5h limit', used: 5.0, limit: 100.0, remaining: 95.0, resetsAt: '2026-10-31T12:31:00Z', resetDurationText: '4h 37m', isGoverning: false }
        ]
      },
      {
        id: 'claude_gpt',
        name: 'Claude and GPT models',
        effectiveRemaining: 46.0,
        effectiveUsed: 54.0,
        primaryResetTime: '2026-11-02T16:54:00Z',
        isCritical: false,
        tiers: [
          { id: 'weekly', label: 'Weekly limit', used: 54.0, limit: 100.0, remaining: 46.0, resetsAt: '2026-11-02T16:54:00Z', resetDurationText: '2d 9h', isGoverning: true },
          { id: '5h', label: '5h limit', used: 0.0, limit: 100.0, remaining: 100.0, resetsAt: null, resetDurationText: '100% left', isGoverning: false }
        ]
      },
      {
        id: 'gemini_4_argon',
        name: 'Gemini 4 Argon',
        effectiveRemaining: 0.0,
        effectiveUsed: 100.0,
        primaryResetTime: '2026-11-02T15:54:00Z',
        isCritical: true,
        tiers: [
          { id: 'weekly', label: 'Weekly limit', used: 100.0, limit: 100.0, remaining: 0.0, resetsAt: '2026-11-02T15:54:00Z', resetDurationText: '2d 8h', isGoverning: true }
        ]
      }
    ]),
    fetched_at: '2026-10-30T22:57:18.6093812Z'
  },
  {
    id: 'claude',
    name: 'Claude Code',
    planName: 'Pro',
    totalQuota: 100,
    usedQuota: 98,
    remainingPercent: 2,
    resetTime: '2026-11-02T12:59:59.805Z',
    status: 'active',
    metrics_json: JSON.stringify([
      { label: 'Session', used: 0.0, limit: 100.0, kind: 'percent' },
      { label: 'Weekly (Shared)', used: 98.0, limit: 100.0, kind: 'percent', isAlert: true },
      { label: 'Resets', value: '0 available' }
    ]),
    fetched_at: '2026-10-30T19:12:17.6328982Z'
  },
  {
    id: 'grok',
    name: 'Grok (bonded with Cursor)',
    planName: 'SuperGrok',
    totalQuota: 100,
    usedQuota: 100,
    remainingPercent: 0,
    resetTime: '2026-11-03T12:12:52.768Z',
    status: 'active',
    metrics_json: JSON.stringify([
      { label: 'Weekly limit', used: 100.0, limit: 100.0, kind: 'percent', isAlert: true },
      { label: 'Pay as you go', value: 'Disabled' },
      { label: 'Bonded Sync', value: 'Cursor Linked' }
    ]),
    fetched_at: '2026-10-30T22:57:15.3476213Z'
  }
];

// 智慧到期自動滿血推算 (Smart Quota Auto-Reset Guard)
// 當當前時間超過重置時間點，前端自動計算為 100% 滿血，離線或未即時同步時不卡舊 0% 狀態
function applySmartAutoReset(items: QuotaCardProps[]): QuotaCardProps[] {
  const now = Date.now();
  return items.map((item) => {
    let updatedItem = { ...item };

    if (updatedItem.token_pools_json) {
      try {
        const pools = JSON.parse(updatedItem.token_pools_json);
        if (Array.isArray(pools)) {
          let hasPoolChanged = false;
          const updatedPools = pools.map((pool: any) => {
            const poolTiers = pool.tiers || [];
            let tierChanged = false;
            const updatedTiers = poolTiers.map((t: any) => {
              if (t.resetsAt) {
                const rTime = new Date(t.resetsAt).getTime();
                if (!isNaN(rTime) && now >= rTime && (t.remaining === 0 || t.used >= 100)) {
                  tierChanged = true;
                  return {
                    ...t,
                    used: 0,
                    remaining: 100,
                    resetDurationText: '已重置 (滿血)',
                    isGoverning: false,
                  };
                }
              }
              return t;
            });

            if (tierChanged) {
              hasPoolChanged = true;
              const effRemaining = Math.min(...updatedTiers.map((t: any) => t.remaining ?? 100));
              const effUsed = Math.max(...updatedTiers.map((t: any) => t.used ?? 0));
              return {
                ...pool,
                effectiveRemaining: effRemaining,
                effectiveUsed: effUsed,
                isCritical: effRemaining <= 5,
                tiers: updatedTiers,
              };
            }
            return pool;
          });

          if (hasPoolChanged) {
            updatedItem.token_pools_json = JSON.stringify(updatedPools);
            if (updatedItem.id === 'antigravity') {
              const workhorses = updatedPools.filter((p: any) => p.id === 'gemini_models' || p.id === 'claude_gpt');
              if (workhorses.length > 0) {
                const minRemaining = Math.min(...workhorses.map((p: any) => p.effectiveRemaining));
                updatedItem.remainingPercent = minRemaining;
                updatedItem.usedQuota = 100 - minRemaining;
              }
            } else {
              const minRemaining = Math.min(...updatedPools.map((p: any) => p.effectiveRemaining));
              updatedItem.remainingPercent = minRemaining;
              updatedItem.usedQuota = 100 - minRemaining;
            }
          }
        }
      } catch {}
    }

    if (updatedItem.resetTime && updatedItem.resetTime.includes('T')) {
      const rTime = new Date(updatedItem.resetTime).getTime();
      if (!isNaN(rTime) && now >= rTime && updatedItem.remainingPercent === 0) {
        updatedItem.remainingPercent = 100;
        updatedItem.usedQuota = 0;
      }
    }

    return updatedItem;
  });
}

export const App: React.FC = () => {
  const [quotas, setQuotas] = useState<QuotaCardProps[]>(INITIAL_REAL_QUOTAS);
  const [selectedId, setSelectedId] = useState<string>('cursor');
  const [isLoading, setIsLoading] = useState<boolean>(false);
  const [isVoiceActive, setIsVoiceActive] = useState<boolean>(false);
  const [liveTranscript, setLiveTranscript] = useState<string>('');
  const [isModelModalOpen, setIsModelModalOpen] = useState<boolean>(false);
  const [isSyncing, setIsSyncing] = useState<boolean>(false);
  const [models, setModels] = useState<any[]>([]);

  const [isOnline, setIsOnline] = useState<boolean>(() => {
    if (typeof navigator !== 'undefined') {
      return navigator.onLine;
    }
    return true;
  });

  // 使用者自訂更新頻率 (預設 60 秒，支援 localStorage 持久化)
  const [refreshInterval, setRefreshInterval] = useState<RefreshIntervalSeconds>(() => {
    if (typeof window !== 'undefined') {
      const saved = localStorage.getItem(STORAGE_KEY_REFRESH_INTERVAL);
      if (saved !== null) {
        const parsed = Number(saved);
        if ([15, 30, 60, 300, 900, 0].includes(parsed)) {
          return parsed as RefreshIntervalSeconds;
        }
      }
    }
    return 60;
  });

  const [countdown, setCountdown] = useState<number>(refreshInterval > 0 ? refreshInterval : 0);

  // 視圖模式狀態 (預設一頁式全景駕駛艙 cockpit，支援 localStorage 與 URL 同步)
  const [viewMode, setViewMode] = useState<DashboardViewMode>(() => {
    if (typeof window !== 'undefined') {
      const urlParams = new URLSearchParams(window.location.search);
      const urlView = urlParams.get('view');
      if (urlView === 'cockpit' || urlView === 'split') {
        return urlView;
      }
      const saved = localStorage.getItem(STORAGE_KEY_VIEW_MODE);
      if (saved === 'cockpit' || saved === 'split') {
        return saved;
      }
    }
    return 'cockpit';
  });

  const handleChangeViewMode = (mode: DashboardViewMode) => {
    setViewMode(mode);
    if (typeof window !== 'undefined') {
      localStorage.setItem(STORAGE_KEY_VIEW_MODE, mode);
      const url = new URL(window.location.href);
      url.searchParams.set('view', mode);
      window.history.replaceState({}, '', url.toString());
    }
  };

  // 單手握持偏好 (Apple HIG Reachability: right / left / dual)
  const [handedness, setHandedness] = useState<HandednessMode>(() => {
    if (typeof window !== 'undefined') {
      const urlParams = new URLSearchParams(window.location.search);
      const urlHanded = urlParams.get('handed');
      if (urlHanded === 'right' || urlHanded === 'left' || urlHanded === 'dual') {
        return urlHanded;
      }
      const saved = localStorage.getItem(STORAGE_KEY_HANDEDNESS);
      if (saved === 'right' || saved === 'left' || saved === 'dual') {
        return saved;
      }
    }
    return 'right';
  });

  const handleChangeHandedness = (h: HandednessMode) => {
    setHandedness(h);
    if (typeof window !== 'undefined') {
      localStorage.setItem(STORAGE_KEY_HANDEDNESS, h);
      const url = new URL(window.location.href);
      url.searchParams.set('handed', h);
      window.history.replaceState({}, '', url.toString());
    }
  };

  // 單手快速過濾「僅告警平台」狀態
  const [filterAlertOnly, setFilterAlertOnly] = useState<boolean>(() => {
    if (typeof window !== 'undefined') {
      const urlParams = new URLSearchParams(window.location.search);
      if (urlParams.get('filter') === 'alert') return true;
      const saved = localStorage.getItem(STORAGE_KEY_FILTER_ALERT);
      if (saved === '1') return true;
    }
    return false;
  });

  const handleToggleFilterAlert = () => {
    setFilterAlertOnly((prev) => {
      const next = !prev;
      if (typeof window !== 'undefined') {
        localStorage.setItem(STORAGE_KEY_FILTER_ALERT, next ? '1' : '0');
        const url = new URL(window.location.href);
        if (next) {
          url.searchParams.set('filter', 'alert');
        } else {
          url.searchParams.delete('filter');
        }
        window.history.replaceState({}, '', url.toString());
      }
      return next;
    });
  };

  const wsRef = useRef<WebSocket | null>(null);

  const fetchQuotas = useCallback(async () => {
    // 網路連線感知：若離線則僅套用智慧到期推算，不發送無效請求
    if (typeof navigator !== 'undefined' && !navigator.onLine) {
      setQuotas((prev) => applySmartAutoReset(prev));
      return;
    }

    try {
      setIsSyncing(true);
      const res = await fetch('/api/quotas');
      if (res.status === 304) {
        setQuotas((prev) => applySmartAutoReset(prev));
        return; // 快取命中
      }
      const data = await res.json();
      if (data.success && Array.isArray(data.data) && data.data.length > 0) {
        const mapped: QuotaCardProps[] = data.data.map((item: any) => ({
          id: item.provider_id || item.id,
          name: item.name,
          planName: item.plan_name || 'Standard',
          totalQuota: item.total_quota || 100,
          usedQuota: item.used_quota || 0,
          remainingPercent: item.remaining_percent ?? 0,
          resetTime: item.reset_time || '每月重置',
          status: item.status || 'active',
          token_pools_json: item.token_pools_json,
          metrics_json: item.metrics_json,
          fetched_at: item.fetched_at,
        }));
        setQuotas(applySmartAutoReset(mapped));
      }
    } catch {
      // 離線降級：保留既有真實快照並套用到期滿血
      setQuotas((prev) => applySmartAutoReset(prev));
    } finally {
      setIsSyncing(false);
    }
  }, []);

  const fetchModels = useCallback(async () => {
    try {
      const res = await fetch('/api/models/sync', { method: 'POST' });
      const data = await res.json();
      if (data.success && Array.isArray(data.models)) {
        setModels(data.models);
        return;
      }
    } catch {}

    // 本地預設前瞻活躍模型（嚴格排除過期模型）
    setModels([
      { id: 'gpt-6.1-sol', name: 'GPT-6.1 Sol (Workhorse Coding)', provider: 'OpenAI', context_window: 128000, supports_thinking: true, thinking_budget_max: 32768, cost_per_m_input: 1.25, cost_per_m_output: 5.0, status: 'active', verified_date: '2026-10-30' },
      { id: 'gpt-6-astra', name: 'GPT-6 Astra (Frontier Intelligence)', provider: 'OpenAI', context_window: 200000, supports_thinking: true, thinking_budget_max: 65536, cost_per_m_input: 2.50, cost_per_m_output: 10.0, status: 'active', verified_date: '2026-10-30' },
      { id: 'o3-mini', name: 'OpenAI o3-mini (High Reasoning 100K)', provider: 'OpenAI', context_window: 128000, supports_thinking: true, thinking_budget_max: 100000, cost_per_m_input: 1.10, cost_per_m_output: 4.40, status: 'active', verified_date: '2026-10-30' },
      { id: 'gpt-4o-latest', name: 'GPT-4o (Omni Multimodal Flagship)', provider: 'OpenAI', context_window: 128000, supports_thinking: false, cost_per_m_input: 2.50, cost_per_m_output: 10.0, status: 'active', verified_date: '2026-10-30' },
      { id: 'gemini-3.8-flash', name: 'Gemini 3.8 Flash (High Reasoning)', provider: 'Google', context_window: 1000000, supports_thinking: true, thinking_budget_max: 65536, cost_per_m_input: 0.075, cost_per_m_output: 0.30, status: 'active', verified_date: '2026-10-30' },
      { id: 'gemini-3.8-live', name: 'Gemini 3.8 Live (Audio & Vision)', provider: 'Google', context_window: 2000000, supports_live: true, supports_thinking: true, thinking_budget_max: 32768, cost_per_m_input: 0.125, cost_per_m_output: 0.50, status: 'active', verified_date: '2026-10-30' },
      { id: 'gemini-2.5-pro', name: 'Gemini 2.5 Pro (Deep Code)', provider: 'Google', context_window: 1000000, supports_thinking: true, thinking_budget_max: 32768, cost_per_m_input: 1.25, cost_per_m_output: 5.0, status: 'active', verified_date: '2026-10-30' },
      { id: 'claude-3-7-sonnet', name: 'Claude 3.7 Sonnet (Hybrid Thinking)', provider: 'Anthropic', context_window: 200000, supports_thinking: true, thinking_budget_max: 64000, cost_per_m_input: 3.0, cost_per_m_output: 15.0, status: 'active', verified_date: '2026-10-30' },
      { id: 'claude-3-5-sonnet', name: 'Claude 3.5 Sonnet (Frontier Coding)', provider: 'Anthropic', context_window: 200000, supports_thinking: false, cost_per_m_input: 3.0, cost_per_m_output: 15.0, status: 'active', verified_date: '2026-10-30' },
      { id: 'claude-fable-5-1', name: 'Claude Fable 5.1 (Long-Running Agent)', provider: 'Anthropic', context_window: 1000000, supports_thinking: true, thinking_budget_max: 64000, cost_per_m_input: 4.0, cost_per_m_output: 20.0, status: 'active', verified_date: '2026-10-30' },
      { id: 'grok-4.5', name: 'Grok 4.5 Full Reasoning', provider: 'xAI', context_window: 128000, supports_thinking: true, thinking_budget_max: 32768, cost_per_m_input: 0.50, cost_per_m_output: 2.0, status: 'active', verified_date: '2026-10-30' },
      { id: 'cursor-fast', name: 'Cursor Composer (Fast Edit)', provider: 'Cursor', context_window: 128000, supports_thinking: false, cost_per_m_input: 0.0, cost_per_m_output: 0.0, status: 'active', verified_date: '2026-10-30' },
      { id: 'cursor-agent', name: 'Cursor Autonomous Agent', provider: 'Cursor', context_window: 128000, supports_thinking: true, thinking_budget_max: 32768, cost_per_m_input: 0.0, cost_per_m_output: 0.0, status: 'active', verified_date: '2026-10-30' }
    ]);
  }, []);

  // 連線感知監聽器 (Online/Offline Network Detection)
  useEffect(() => {
    const handleOnline = () => {
      setIsOnline(true);
      fetchQuotas();
    };
    const handleOffline = () => {
      setIsOnline(false);
    };

    window.addEventListener('online', handleOnline);
    window.addEventListener('offline', handleOffline);

    return () => {
      window.removeEventListener('online', handleOnline);
      window.removeEventListener('offline', handleOffline);
    };
  }, [fetchQuotas]);

  // 初次載入
  useEffect(() => {
    fetchQuotas();
    fetchModels();
  }, [fetchQuotas, fetchModels]);

  // 更新頻率切換與持久化
  const handleChangeInterval = (newInterval: RefreshIntervalSeconds) => {
    setRefreshInterval(newInterval);
    setCountdown(newInterval);
    if (typeof window !== 'undefined') {
      localStorage.setItem(STORAGE_KEY_REFRESH_INTERVAL, String(newInterval));
    }
    if (newInterval > 0) {
      fetchQuotas();
    }
  };

  // 背景輪詢計時器 + Page Visibility API 節能守衛 + 離線掛起守衛
  useEffect(() => {
    if (refreshInterval === 0 || !isOnline) {
      return; // 手動模式或離線時不啟動定時器
    }

    const timer = setInterval(() => {
      // 若頁面在背景最小化，凍結計時以省電
      if (typeof document !== 'undefined' && document.visibilityState === 'hidden') {
        return;
      }

      setCountdown((prev) => {
        if (prev <= 1) {
          fetchQuotas();
          return refreshInterval;
        }
        return prev - 1;
      });
    }, 1000);

    // 頁面重新回到前景時立即補償刷新
    const handleVisibilityChange = () => {
      if (document.visibilityState === 'visible' && refreshInterval > 0 && isOnline) {
        fetchQuotas();
        setCountdown(refreshInterval);
      }
    };

    document.addEventListener('visibilitychange', handleVisibilityChange);

    return () => {
      clearInterval(timer);
      document.removeEventListener('visibilitychange', handleVisibilityChange);
    };
  }, [refreshInterval, fetchQuotas, isOnline]);

  // 組裝 Live Bar 5 色分段
  const liveSegments: LiveBarSegment[] = quotas.map((q) => {
    if (q.id === 'cursor') {
      return {
        id: 'cursor',
        name: 'Cursor',
        remainingPercent: q.remainingPercent,
        gradient: 'bg-gradient-to-r from-[#00F2FE] to-[#4FACFE]',
        glowColor: '0 0 12px rgba(0,242,254,0.4)',
        isAlert: q.remainingPercent <= 5,
      };
    }
    if (q.id === 'codex') {
      return {
        id: 'codex',
        name: 'Codex',
        remainingPercent: q.remainingPercent,
        gradient: 'bg-gradient-to-r from-[#00FF87] to-[#60EFFF]',
        glowColor: '0 0 12px rgba(0,255,135,0.4)',
        isAlert: q.remainingPercent <= 5,
      };
    }
    if (q.id === 'antigravity') {
      return {
        id: 'antigravity',
        name: 'Antigravity',
        remainingPercent: q.remainingPercent,
        gradient: 'bg-gradient-to-r from-[#4285F4] via-[#A855F7] to-[#EC4899]',
        glowColor: '0 0 12px rgba(168,85,247,0.4)',
        isAlert: q.remainingPercent <= 5,
        label: 'Gemini 31% · Claude 46% · Argon 0% ⚠️',
      };
    }
    if (q.id === 'claude') {
      return {
        id: 'claude',
        name: 'Claude Code',
        remainingPercent: q.remainingPercent,
        gradient: 'bg-gradient-to-r from-amber-400 to-orange-400',
        glowColor: '0 0 12px rgba(245,158,11,0.4)',
        isAlert: q.remainingPercent <= 5,
      };
    }
    // grok
    return {
      id: 'grok',
      name: 'Grok',
      remainingPercent: q.remainingPercent,
      gradient: 'bg-gradient-to-r from-[#FF007A] to-[#7928CA]',
      glowColor: '0 0 12px rgba(255,0,122,0.45)',
      isAlert: q.remainingPercent <= 5,
    };
  });

  const handleSyncModels = async () => {
    setIsSyncing(true);
    try {
      await fetchModels();
      setIsModelModalOpen(true);
    } finally {
      setIsSyncing(false);
    }
  };

  const toggleVoice = () => {
    if (isVoiceActive) {
      if (wsRef.current) {
        wsRef.current.close();
        wsRef.current = null;
      }
      setIsVoiceActive(false);
      setLiveTranscript('語音對話已結束。連線已休眠。');
    } else {
      setIsVoiceActive(true);
      setLiveTranscript('正在連線至 Cloudflare Durable Object (Gemini 3.8 Live)...');

      try {
        const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
        const wsUrl = `${protocol}//${window.location.host}/ws/live?sessionId=user_session_${Date.now()}`;
        const ws = new WebSocket(wsUrl);
        wsRef.current = ws;

        ws.onopen = () => {
          setLiveTranscript('Gemini 3.8 Live API 語音連線已建立。請說話（例如：「查詢 Cursor 剩餘配額」）...');
        };

        ws.onmessage = (event) => {
          try {
            const data = JSON.parse(event.data);
            if (data.serverContent?.modelTurn?.parts) {
              const textParts = data.serverContent.modelTurn.parts
                .map((p: any) => p.text || '')
                .join('');
              if (textParts) {
                setLiveTranscript((prev) => `${prev}\nGemini: ${textParts}`);
              }
            }
          } catch {
            setLiveTranscript(`Gemini Live: ${event.data}`);
          }
        };

        ws.onerror = () => {
          setLiveTranscript('連線至 Gemini Live 服務中斷，已啟動自動防護。');
        };

        ws.onclose = () => {
          setIsVoiceActive(false);
        };
      } catch (err: any) {
        setLiveTranscript(`連線失敗: ${err.message}`);
        setIsVoiceActive(false);
      }
    }
  };

  return (
    <div className="relative w-screen h-screen overflow-hidden bg-slate-950 text-slate-100 flex flex-col font-sans neon-ambient-glow">
      {/* 頂部導航列 (Cyber Dark Header) */}
      <header className="w-full bg-slate-950/95 border-b border-slate-800/80 px-4 py-2 sm:px-6 flex items-center justify-between shrink-0 z-30">
        <div className="flex items-center gap-3">
          <div className="flex items-center gap-2">
            <div className="w-7 h-7 rounded-lg bg-gradient-to-br from-cyan-400 via-purple-500 to-pink-500 flex items-center justify-center shadow-lg shadow-cyan-500/20">
              <Sparkles className="w-4 h-4 text-slate-950 font-black" />
            </div>
            <h1 className="font-black text-base sm:text-lg tracking-tight bg-gradient-to-r from-cyan-300 via-purple-300 to-pink-300 bg-clip-text text-transparent">
              OpenTokenUsage
            </h1>
          </div>
          <span className="hidden md:inline-flex items-center gap-1 text-[11px] font-mono px-2 py-0.5 rounded-full bg-slate-900 border border-slate-700 text-slate-400">
            <Shield className="w-3 h-3 text-cyan-400" />
            5 Platforms Bonded
          </span>
        </div>

        {/* 右側：更新頻率選擇器與手動刷新按鈕 */}
        <div className="flex items-center gap-2">
          <ViewModeSelector
            currentMode={viewMode}
            onChangeMode={handleChangeViewMode}
            governingAlertCount={quotas.filter((q) => q.remainingPercent <= 5).length}
            handedness={handedness}
            onChangeHandedness={handleChangeHandedness}
          />
          <FrequencySelector
            interval={refreshInterval}
            onChangeInterval={handleChangeInterval}
            countdownSeconds={countdown}
          />
        </div>
      </header>

      {/* 用戶原創概念：Live Bar 動態狀態光譜條 */}
      <LiveBar
        segments={liveSegments}
        activePlatformId={selectedId}
        onSelectPlatform={setSelectedId}
        countdownSeconds={countdown}
        isSyncing={isSyncing}
        onTriggerSync={fetchQuotas}
        isVoiceActive={isVoiceActive}
        isOnline={isOnline}
      />

      {/* 主工作區：iPhone Duo 雙欄或單欄自適應 */}
      <div className="flex-1 min-h-0 relative">
        <SplitViewContainer
          quotas={quotas}
          selectedId={selectedId}
          onSelect={setSelectedId}
          isLoading={isLoading}
          isVoiceActive={isVoiceActive}
          liveTranscript={liveTranscript}
          viewMode={viewMode}
          onChangeViewMode={handleChangeViewMode}
          isOnline={isOnline}
          countdownSeconds={countdown}
          handedness={handedness}
          filterAlertOnly={filterAlertOnly}
          onToggleFilterAlert={handleToggleFilterAlert}
        />
      </div>

      {/* 懸浮工具列 (Gemini 3.8 Live 麥克風與模型型錄入口) */}
      <FloatingActionToolbar
        isVoiceActive={isVoiceActive}
        isSyncing={isSyncing}
        onToggleVoice={toggleVoice}
        onSyncModels={handleSyncModels}
        handedness={handedness}
      />

      {/* 最新活躍前瞻模型型錄 Modal */}
      <ModelSyncModal
        isOpen={isModelModalOpen}
        onClose={() => setIsModelModalOpen(false)}
        models={models}
        isSyncing={isSyncing}
        onTriggerSync={fetchModels}
      />
    </div>
  );
};

export default App;
