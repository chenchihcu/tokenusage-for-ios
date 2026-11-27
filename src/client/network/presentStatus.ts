import type { NetState } from './types';

export interface StatusPresentation {
  /** Spoken only when this text changes. Null keeps the previous announcement. */
  live: string | null;
  pathLabel: string | null;
  checkHint: string | null;
  showProgress: boolean;
}

const CHECK_HINT = '請至「設定」檢查行動服務及此 App 的行動數據。選單名稱依系統語言與版本而異。';

/** Copy is chosen from state fields. The reducer never reads these strings. */
export function presentStatus(state: NetState, updatedLabel: string | null): StatusPresentation {
  const pathLabel = state.path === 'cellular' ? '使用行動網路' : null;
  if (state.writeState === 'pending') {
    return { live: '已送出，正在確認結果', pathLabel, checkHint: null, showProgress: true };
  }
  if (state.path === 'none' || state.connectedHint === false) {
    const when = updatedLabel ? `上次更新 ${updatedLabel}` : '顯示上次更新資料';
    return {
      live: `目前無法連線，${when}`,
      pathLabel: null,
      checkHint: CHECK_HINT,
      showProgress: false,
    };
  }
  if (state.auth === 'expired' || state.errorKind === 'http_auth') {
    return { live: '登入已失效', pathLabel, checkHint: null, showProgress: false };
  }
  if (state.errorKind === 'http_forbidden') {
    return { live: '沒有此項權限', pathLabel, checkHint: null, showProgress: false };
  }
  if (state.errorKind === 'http_rate_limit' || (state.errorKind === 'http_server' && state.api === 'reachable')) {
    return { live: '服務忙碌，請稍後再試', pathLabel, checkHint: null, showProgress: false };
  }
  if (state.api === 'unreachable') {
    return { live: '無法連接服務，請稍後重試', pathLabel, checkHint: null, showProgress: false };
  }
  if (state.errorKind === 'schema' || state.errorKind === 'http_client') {
    return { live: '無法連接服務，請稍後重試', pathLabel, checkHint: null, showProgress: false };
  }
  if (state.announce === 'synced') {
    return { live: updatedLabel ? `已同步 · 資料時間 ${updatedLabel}` : '已同步', pathLabel, checkHint: null, showProgress: false };
  }
  if (state.announce === 'recovered') {
    return { live: '連線已恢復', pathLabel, checkHint: null, showProgress: false };
  }
  if (state.api === 'checking' && state.checkReason !== 'interval') {
    return { live: '正在確認連線…', pathLabel, checkHint: null, showProgress: true };
  }
  if (state.api === 'unknown') {
    return { live: '正在確認連線…', pathLabel, checkHint: null, showProgress: true };
  }
  if (state.api === 'reachable' && state.errorKind === 'none') {
    return { live: updatedLabel ? `已同步 · 資料時間 ${updatedLabel}` : '已同步', pathLabel, checkHint: null, showProgress: false };
  }
  return { live: null, pathLabel, checkHint: null, showProgress: state.api === 'checking' };
}

/** True when the main screen should show the status sentence. Success and "checking" stay quiet. */
export function isFailureStatus(status: StatusPresentation): boolean {
  const live = status.live ?? '';
  return (
    status.checkHint !== null ||
    live.startsWith('目前無法連線') ||
    live === '登入已失效' ||
    live === '沒有此項權限' ||
    live === '服務忙碌，請稍後再試' ||
    live === '無法連接服務，請稍後重試'
  );
}

export function shortLinkLabel(state: NetState): string {
  if (state.path === 'none' || state.connectedHint === false) return '離線資料';
  if (state.writeState === 'pending') return '待確認';
  if (state.api === 'reachable' && state.data === 'fresh') return '已同步';
  if (state.api === 'unreachable' || state.errorKind === 'schema' || state.errorKind === 'http_client') return '服務中斷';
  if (state.api === 'checking' || state.api === 'unknown') return '確認中';
  return '待確認';
}

const DIAGNOSTIC_KEYS = ['requestId', 'errorKind', 'durationMs', 'attempts', 'path', 'httpStatus'] as const;

export function toDiagnostic(input: {
  requestId: string | null;
  errorKind: string;
  durationMs: number;
  attempts: number;
  path: string;
  httpStatus: number | null;
  authorization?: string;
  body?: string;
  url?: string;
}): Record<string, string | number | null> {
  const source = input as unknown as Record<string, string | number | null | undefined>;
  const safe: Record<string, string | number | null> = {};
  for (const key of DIAGNOSTIC_KEYS) {
    const value = source[key];
    if (typeof value === 'string' || typeof value === 'number' || value === null) safe[key] = value;
  }
  return safe;
}
