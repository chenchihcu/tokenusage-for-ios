export type PathHint = 'unknown' | 'none' | 'wifi' | 'cellular';
export type ApiState = 'unknown' | 'checking' | 'reachable' | 'unreachable';
export type AuthState = 'unknown' | 'signedOut' | 'valid' | 'expired';
export type DataState = 'empty' | 'fresh' | 'stale' | 'draft' | 'pending';
export type CostHint = boolean | 'unknown';
export type Lifecycle = 'active' | 'inactive' | 'background';
export type CheckReason = 'initial' | 'restore' | 'interval' | 'user' | null;
export type WriteState = 'idle' | 'pending' | 'confirmed' | 'rejected';

export type ErrorKind =
  | 'none'
  | 'offline'
  | 'timeout'
  | 'cancelled'
  | 'dns'
  | 'tls'
  | 'cors'
  | 'transport'
  | 'http_auth'
  | 'http_forbidden'
  | 'http_rate_limit'
  | 'http_server'
  | 'http_client'
  | 'schema';

export type ConnectionType = 'wifi' | 'cellular' | 'none' | 'unknown';

export interface NetState {
  path: PathHint;
  connectedHint: boolean | 'unknown';
  api: ApiState;
  auth: AuthState;
  data: DataState;
  /** NWPath flags are not bridged. Must stay `unknown`, never a guessed false. */
  costHint: CostHint;
  constrainedHint: CostHint;
  lastCheckedAt: number | null;
  lastSuccessAt: number | null;
  errorKind: ErrorKind;
  lifecycle: Lifecycle;
  requestGeneration: number;
  autoRetrySuspended: boolean;
  checkReason: CheckReason;
  announce: 'recovered' | 'synced' | null;
  writeState: WriteState;
}

export function initialNetState(): NetState {
  return {
    path: 'unknown',
    connectedHint: 'unknown',
    api: 'unknown',
    auth: 'unknown',
    data: 'stale',
    costHint: 'unknown',
    constrainedHint: 'unknown',
    lastCheckedAt: null,
    lastSuccessAt: null,
    errorKind: 'none',
    lifecycle: 'active',
    requestGeneration: 0,
    autoRetrySuspended: false,
    checkReason: null,
    announce: null,
    writeState: 'idle',
  };
}

export type NetAction =
  | {
      type: 'snapshot';
      generation: number;
      connected: boolean;
      connectionType: ConnectionType;
      at: number;
    }
  | { type: 'lifecycle'; lifecycle: Lifecycle }
  | { type: 'checking'; generation: number; reason: Exclude<CheckReason, null>; at: number }
  | {
      type: 'result';
      generation: number;
      at: number;
      httpStatus: number | null;
      errorKind: ErrorKind;
      notModified?: boolean;
      appliedData?: boolean;
    }
  | { type: 'write'; outcome: 'unknown' | 'confirmed' | 'rejected' };
