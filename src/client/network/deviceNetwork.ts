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

/**
 * Browser network and visibility signals. A browser cannot tell Wi-Fi from cellular,
 * so the path is only ever 'unknown' (online) or 'none' (offline).
 */
export async function bindDeviceNetwork(handlers: DeviceHandlers): Promise<() => Promise<void>> {
  let sequence = 0;
  const publish = (connected: boolean) => {
    handlers.onSnapshot({ connected, connectionType: connected ? 'unknown' : 'none', generation: ++sequence });
  };
  const online = () => publish(true);
  const offline = () => publish(false);
  const onVisibility = () => {
    if (document.visibilityState === 'hidden') {
      handlers.onLifecycle('background');
      return;
    }
    handlers.onLifecycle('active');
    handlers.onForeground();
  };

  window.addEventListener('online', online);
  window.addEventListener('offline', offline);
  document.addEventListener('visibilitychange', onVisibility);
  publish(navigator.onLine);
  handlers.onTextScale(1);

  return async () => {
    window.removeEventListener('online', online);
    window.removeEventListener('offline', offline);
    document.removeEventListener('visibilitychange', onVisibility);
  };
}
