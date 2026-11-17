import { classifyHttp } from './policy';
import { initialNetState, type ConnectionType, type NetAction, type NetState, type PathHint } from './types';

export function mapPath(connected: boolean, connectionType: ConnectionType): PathHint {
  if (!connected || connectionType === 'none') return 'none';
  if (connectionType === 'wifi') return 'wifi';
  if (connectionType === 'cellular') return 'cellular';
  return 'unknown';
}

export function reduceNet(state: NetState = initialNetState(), action: NetAction): NetState {
  if (action.type === 'lifecycle') {
    if (state.lifecycle === action.lifecycle) return state;
    return { ...state, lifecycle: action.lifecycle };
  }

  if (action.type === 'write') {
    if (action.outcome === 'unknown') {
      return { ...state, writeState: 'pending', announce: null };
    }
    if (action.outcome === 'confirmed') {
      return { ...state, writeState: 'confirmed' };
    }
    return { ...state, writeState: 'rejected' };
  }

  if (action.type === 'snapshot') {
    if (action.generation <= state.requestGeneration) return state;
    const path = mapPath(action.connected, action.connectionType);
    // The first snapshot only resolves 'unknown' → known; it is not a network change.
    // Treating it as one reset a just-confirmed API state and left the UI on 「正在確認連線…」.
    const firstHint = state.connectedHint === 'unknown';
    const pathChanged = firstHint
      ? state.path !== 'unknown' && path !== state.path
      : path !== state.path || action.connected !== (state.connectedHint === true);
    const next: NetState = {
      ...state,
      path,
      connectedHint: action.connected,
      requestGeneration: action.generation,
      lastCheckedAt: action.at,
      costHint: 'unknown',
      constrainedHint: 'unknown',
      announce: null,
    };
    if (!action.connected) {
      next.path = 'none';
      next.autoRetrySuspended = true;
      if (state.api === 'reachable') next.api = 'unknown';
      return next;
    }
    next.autoRetrySuspended = false;
    if (pathChanged) next.api = 'unknown';
    return next;
  }

  if (action.generation !== state.requestGeneration) return state;

  if (action.type === 'checking') {
    return {
      ...state,
      api: 'checking',
      checkReason: action.reason,
      lastCheckedAt: action.at,
      announce: null,
    };
  }

  const wasUnreachable = state.api === 'unreachable';
  const errorKind = action.errorKind !== 'none' ? action.errorKind : action.httpStatus !== null ? classifyHttp(action.httpStatus) : 'transport';
  const next: NetState = {
    ...state,
    lastCheckedAt: action.at,
    errorKind,
    checkReason: null,
    costHint: 'unknown',
    constrainedHint: 'unknown',
  };

  if (action.httpStatus === null) {
    next.api = 'unreachable';
    next.announce = null;
    if (state.data === 'fresh') next.data = 'stale';
    return next;
  }

  next.api = 'reachable';
  if (action.httpStatus === 401) next.auth = 'expired';
  if (errorKind === 'none' && action.appliedData) {
    next.data = 'fresh';
    next.lastSuccessAt = action.at;
    next.errorKind = 'none';
    next.announce = 'synced';
    return next;
  }
  if (errorKind === 'none' && action.notModified) {
    next.errorKind = 'none';
    next.announce = wasUnreachable ? 'recovered' : null;
    return next;
  }
  next.announce = wasUnreachable && errorKind !== 'none' ? null : wasUnreachable ? 'recovered' : null;
  if (wasUnreachable && (action.httpStatus === 401 || action.httpStatus === 403 || action.httpStatus >= 429)) {
    next.announce = null;
  }
  return next;
}
