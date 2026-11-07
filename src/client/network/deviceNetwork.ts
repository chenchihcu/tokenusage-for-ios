import { Capacitor } from '@capacitor/core';
import type { ConnectionType, Lifecycle } from './types';

export interface DeviceSnapshot {
  connected: boolean;
  connectionType: ConnectionType;
  generation: number;
}

export interface DeviceHandlers {
  onSnapshot: (snapshot: DeviceSnapshot) => void;
  onLifecycle: (lifecycle: Lifecycle) => void;
  onForeground: () => void;
  onTextScale: (scale: number) => void;
}

function asConnectionType(value: string, connected: boolean): ConnectionType {
  if (!connected || value === 'none') return 'none';
  if (value === 'wifi') return 'wifi';
  if (value === 'cellular') return 'cellular';
  return 'unknown';
}

async function applyPreferredTextZoom(onTextScale: (scale: number) => void): Promise<void> {
  try {
    const { TextZoom } = await import('@capacitor/text-zoom');
    const preferred = await TextZoom.getPreferred();
    if (!preferred || typeof preferred.value !== 'number' || preferred.value <= 0) return;
    await TextZoom.set({ value: preferred.value });
    onTextScale(preferred.value);
  } catch {
    onTextScale(1);
  }
}

/**
 * Subscribes to path hints and app lifecycle. Listener handles are removed
 * individually so other consumers keep their own subscriptions.
 * `appStateChange` inactive is not treated as background; `pause` is.
 */
export async function bindDeviceNetwork(handlers: DeviceHandlers): Promise<() => Promise<void>> {
  const removers: Array<() => Promise<void> | void> = [];
  let sequence = 0;
  let applied = 0;

  const native = Capacitor.isNativePlatform();
  const publish = (connected: boolean, connectionType: string, generation: number) => {
    if (generation < applied) return;
    applied = generation;
    // The web plugin maps Network Information effectiveType "4g" to wifi.
    // That is not a path. Only the native plugin may report wifi or cellular.
    const hinted = native ? asConnectionType(connectionType, connected) : connected ? 'unknown' : 'none';
    handlers.onSnapshot({
      connected,
      connectionType: hinted,
      generation,
    });
  };

  try {
    const { Network } = await import('@capacitor/network');
    const snapGen = ++sequence;
    const initial = Network.getStatus();
    const handle = await Network.addListener('networkStatusChange', (status) => {
      publish(status.connected, status.connectionType, ++sequence);
    });
    removers.push(() => handle.remove());
    const status = await initial;
    publish(status.connected, status.connectionType, snapGen);
  } catch {
    const online = () => publish(true, 'unknown', ++sequence);
    const offline = () => publish(false, 'none', ++sequence);
    window.addEventListener('online', online);
    window.addEventListener('offline', offline);
    publish(navigator.onLine, navigator.onLine ? 'unknown' : 'none', ++sequence);
    removers.push(() => {
      window.removeEventListener('online', online);
      window.removeEventListener('offline', offline);
    });
  }

  try {
    const { App } = await import('@capacitor/app');
    const stateHandle = await App.addListener('appStateChange', ({ isActive }) => {
      handlers.onLifecycle(isActive ? 'active' : 'inactive');
    });
    const pauseHandle = await App.addListener('pause', () => {
      handlers.onLifecycle('background');
    });
    const resumeHandle = await App.addListener('resume', () => {
      handlers.onLifecycle('active');
      void applyPreferredTextZoom(handlers.onTextScale);
      handlers.onForeground();
    });
    removers.push(() => stateHandle.remove());
    removers.push(() => pauseHandle.remove());
    removers.push(() => resumeHandle.remove());
  } catch {
    // Browser preview still gets the visibility listener below.
  }

  const onVisibility = () => {
    if (document.visibilityState === 'hidden') {
      handlers.onLifecycle('background');
      return;
    }
    handlers.onLifecycle('active');
    void applyPreferredTextZoom(handlers.onTextScale);
    handlers.onForeground();
  };
  document.addEventListener('visibilitychange', onVisibility);
  removers.push(() => document.removeEventListener('visibilitychange', onVisibility));

  await applyPreferredTextZoom(handlers.onTextScale);

  return async () => {
    for (const remove of removers) await remove();
  };
}
