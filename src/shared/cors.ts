/** Public Internet API. The installed app calls this origin directly; it is not a Tailnet name. */
export const PUBLIC_API_ORIGIN = 'https://opentokenusage-web.chihfu-chen-tw.workers.dev';

/**
 * Origins that may call the API from a browser or the Capacitor WebView.
 * Credentials are not used, and the allowlist is still exact — never `*`.
 */
export const ALLOWED_ORIGINS: readonly string[] = [
  PUBLIC_API_ORIGIN,
  'https://localhost',
  'http://localhost',
  'capacitor://localhost',
  'ionic://localhost',
  'http://localhost:3000',
  'http://127.0.0.1:3000',
  'http://localhost:5173',
  'http://127.0.0.1:5173',
];

export function isAllowedOrigin(origin: string | null | undefined): origin is string {
  return typeof origin === 'string' && ALLOWED_ORIGINS.includes(origin);
}

/** Browser and WebView pages use a relative URL. The installed shell uses the public HTTPS origin. */
export function resolveApiOrigin(input: { native: boolean; override?: string | null }): string {
  const override = input.override?.trim();
  if (override) return override.replace(/\/$/, '');
  if (input.native) return PUBLIC_API_ORIGIN;
  return '';
}

export function joinApi(origin: string, path: string): string {
  const normalized = path.startsWith('/') ? path : `/${path}`;
  if (!origin) return normalized;
  return `${origin}${normalized}`;
}

export function websocketUrl(
  origin: string,
  page: { protocol: string; host: string },
  path: string,
): string {
  const normalized = path.startsWith('/') ? path : `/${path}`;
  if (origin) {
    const wsOrigin = origin.replace(/^http:/i, 'ws:').replace(/^https:/i, 'wss:');
    return `${wsOrigin}${normalized}`;
  }
  const protocol = page.protocol === 'https:' ? 'wss:' : 'ws:';
  return `${protocol}//${page.host}${normalized}`;
}

export function securityHeaders(origin: string | null): Record<string, string> {
  const headers: Record<string, string> = {
    'Access-Control-Allow-Methods': 'GET, HEAD, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization, If-None-Match, X-Request-Id',
    'Access-Control-Expose-Headers': 'ETag, Retry-After, X-Request-Id',
    Vary: 'Origin',
    'X-Content-Type-Options': 'nosniff',
    'X-Frame-Options': 'DENY',
    'Referrer-Policy': 'strict-origin-when-cross-origin',
  };
  if (isAllowedOrigin(origin)) {
    headers['Access-Control-Allow-Origin'] = origin;
  }
  return headers;
}
