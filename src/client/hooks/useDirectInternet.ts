import { useCallback, useEffect, useRef, useState } from 'react';
import { Capacitor } from '@capacitor/core';
import { resolveApiOrigin } from '../../shared/cors';
import { ApiClient } from '../network/apiClient';
import { bindDeviceNetwork } from '../network/deviceNetwork';
import { ProbeGate } from '../network/policy';
import { presentStatus, shortLinkLabel, type StatusPresentation } from '../network/presentStatus';
import { reduceNet } from '../network/reducer';
import { QuotaRepository } from '../network/repository';
import { initialNetState, type CheckReason, type NetState } from '../network/types';
import type { QuotaCardProps } from '../components/QuotaCard';
import { SecureStorageService } from '../services/storage';

type RefreshMode = 'initial' | 'restore' | 'interval' | 'user';

function readOriginOverride(): string | undefined {
  const env = (import.meta as ImportMeta & { env?: Record<string, string | undefined> }).env;
  return env?.VITE_API_ORIGIN;
}

function formatTaipei(iso: string | null): string | null {
  if (!iso) return null;
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return null;
  return new Intl.DateTimeFormat('zh-TW', {
    timeZone: 'Asia/Taipei',
    month: 'numeric',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
  }).format(date);
}

function newestFetchedAt(items: QuotaCardProps[]): string | null {
  let best: string | null = null;
  let bestMs = -1;
  for (const item of items) {
    if (!item.fetched_at) continue;
    const ms = new Date(item.fetched_at).getTime();
    if (!Number.isNaN(ms) && ms > bestMs) {
      bestMs = ms;
      best = item.fetched_at;
    }
  }
  return best;
}

export interface DirectInternet {
  countdown: number;
  pathAvailable: boolean;
  linkLabel: string;
  status: StatusPresentation;
  busy: boolean;
  textScale: number;
  refresh: () => void;
}

export function useDirectInternet(options: {
  refreshInterval: number;
  onQuotas: (items: QuotaCardProps[]) => void;
}): DirectInternet {
  const [net, setNet] = useState<NetState>(initialNetState);
  const [countdown, setCountdown] = useState(options.refreshInterval > 0 ? options.refreshInterval : 0);
  const [busy, setBusy] = useState(false);
  const [textScale, setTextScale] = useState(1);
  const [updatedLabel, setUpdatedLabel] = useState<string | null>(null);
  const netRef = useRef(net);
  const onQuotasRef = useRef(options.onQuotas);
  const intervalRef = useRef(options.refreshInterval);
  onQuotasRef.current = options.onQuotas;
  intervalRef.current = options.refreshInterval;

  const gateRef = useRef(new ProbeGate());
  const originRef = useRef(
    resolveApiOrigin({
      native: Capacitor.isNativePlatform(),
      override: readOriginOverride(),
    }),
  );
  const repoRef = useRef<QuotaRepository | null>(null);
  if (!repoRef.current) {
    const origin = originRef.current;
    repoRef.current = new QuotaRepository({
      client: new ApiClient(),
      origin,
      accountKey: 'anonymous',
      now: () => Date.now(),
      kv: {
        getItem: (key) => SecureStorageService.getItem(key),
        setItem: (key, value) => SecureStorageService.setItem(key, value),
        removeItem: (key) => SecureStorageService.removeItem(key),
      },
    });
  }

  const apply = useCallback((action: Parameters<typeof reduceNet>[1]) => {
    const next = reduceNet(netRef.current, action);
    netRef.current = next;
    setNet(next);
    return next;
  }, []);

  const refresh = useCallback(async (mode: RefreshMode) => {
    const repo = repoRef.current;
    if (!repo) return;
    const current = netRef.current;
    if (mode !== 'user' && current.connectedHint === false) return;
    if (mode !== 'user' && (current.errorKind === 'tls' || current.errorKind === 'cors')) return;
    const bypass = mode === 'user' || mode === 'initial';
    if (mode !== 'interval' && !gateRef.current.tryEnter(Date.now(), bypass)) return;
    if (mode === 'interval' && gateRef.current.busy) return;
    setBusy(true);
    const reason: Exclude<CheckReason, null> = mode === 'interval' ? 'interval' : mode === 'user' ? 'user' : mode === 'restore' ? 'restore' : 'initial';
    apply({ type: 'checking', generation: netRef.current.requestGeneration, reason, at: Date.now() });
    const generation = repo.currentGeneration();
    try {
      const read = await repo.readQuotas({
        generation,
        foreground: () => netRef.current.lifecycle !== 'background',
      });
      if (read.stale || generation !== repo.currentGeneration()) {
        queueMicrotask(() => {
          void refresh('initial');
        });
        return;
      }
      apply({
        type: 'result',
        generation: netRef.current.requestGeneration,
        at: Date.now(),
        httpStatus: read.result.httpStatus,
        errorKind: read.result.errorKind,
        notModified: read.result.notModified,
        appliedData: Boolean(read.items && read.items.length > 0),
      });
      if (read.items && read.items.length > 0) {
        onQuotasRef.current(read.items);
        setUpdatedLabel(formatTaipei(newestFetchedAt(read.items)));
      }
      if (mode === 'restore' || mode === 'user' || mode === 'initial') {
        setCountdown(intervalRef.current > 0 ? intervalRef.current : 0);
      }
    } finally {
      if (mode !== 'interval') gateRef.current.leave();
      setBusy(false);
    }
  }, [apply]);

  useEffect(() => {
    let stopped = false;
    let unbind: () => Promise<void> = async () => {};
    const repo = repoRef.current;
    if (!repo) return;

    void repo.loadCached().then((cached) => {
      if (stopped || !cached) return;
      onQuotasRef.current(cached.items);
      setUpdatedLabel(formatTaipei(new Date(cached.savedAt).toISOString()));
    });

    void bindDeviceNetwork({
      onSnapshot: (snapshot) => {
        const before = netRef.current.requestGeneration;
        const next = apply({
          type: 'snapshot',
          generation: snapshot.generation,
          connected: snapshot.connected,
          connectionType: snapshot.connectionType,
          at: Date.now(),
        });
        if (next.requestGeneration !== before) repo.bumpGeneration();
        if (snapshot.connected) void refresh('restore');
      },
      onLifecycle: (lifecycle) => {
        apply({ type: 'lifecycle', lifecycle });
      },
      onForeground: () => {
        void refresh('restore');
      },
      onTextScale: (scale) => {
        if (!stopped) setTextScale(scale);
      },
    }).then((done) => {
      if (stopped) void done();
      else unbind = done;
    });

    void refresh('initial');

    return () => {
      stopped = true;
      void unbind();
    };
  }, [apply, refresh]);

  useEffect(() => {
    if (options.refreshInterval <= 0) return;
    const timer = window.setInterval(() => {
      if (document.visibilityState === 'hidden') return;
      if (netRef.current.lifecycle === 'background') return;
      if (netRef.current.connectedHint === false || netRef.current.path === 'none') return;
      if (netRef.current.autoRetrySuspended) return;
      if (netRef.current.errorKind === 'tls' || netRef.current.errorKind === 'cors') return;
      setCountdown((prev) => {
        if (prev <= 1) {
          void refresh('interval');
          return options.refreshInterval;
        }
        return prev - 1;
      });
    }, 1000);
    return () => window.clearInterval(timer);
  }, [options.refreshInterval, refresh]);

  useEffect(() => {
    setCountdown(options.refreshInterval > 0 ? options.refreshInterval : 0);
  }, [options.refreshInterval]);

  const status = presentStatus(net, updatedLabel);
  const pathAvailable = net.connectedHint !== false && net.path !== 'none';

  return {
    countdown,
    pathAvailable,
    linkLabel: shortLinkLabel(net),
    status,
    busy,
    textScale,
    refresh: () => {
      void refresh('user');
    },
  };
}
