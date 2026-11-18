---
name: verify
description: Build and drive the OpenTokenUsage web UI + local Worker in the Linux cloud container (no Xcode here).
---
# Verify recipe (Linux cloud container)

- `npm ci && npx vite build` → `dist/`.
- Local D1: `for f in migrations/*.sql; do npx wrangler d1 execute opentokenusage-db --local --file=$f; done`
- Run Worker + assets: `npx wrangler dev --port 8787 --ip 127.0.0.1` (serves `dist/` and `/api/*`).
  Production URL is blocked by the session proxy (403) — always use the local Worker.
- Drive with Playwright (`require('playwright')`, chromium only; WebKit not installed).
  iPhone Duo approximations (ASSUMPTION, not Apple figures): outer 375x812 / 812x375, inner 626x890 / 890x626.
- Refresh setting is `localStorage.opentokenusage_refresh_interval_sec` (15/30/60/300/900/0); count `/api/quotas` responses to check cadence.
- Simulate a PC push: `POST /api/quotas/sync {quotas:[...]}`.
- Gotchas: StatusBar plugin errors on web are expected; native iOS / iPhone Duo gates (G2+) need a Mac with Xcode 27.1 — not available here.
