# Feature Spec: OpenTokenUsage v3 — native iPhone Duo app with direct refresh

Status: **Draft — awaiting user approval** · 2026-11-17 · Companion plan: `docs/plan-v3-native-duo.md`
Governing rules: `Institution/ios/IOS_SPEC.md` (iOS 27.1 SDK, SwiftUI, Gates G0–G5), `00-core-rules.md`, `06-ui-ux-universal.md`.
Tags: untagged = stated by user or verified; `[ASSUMPTION]` = author default, confirm yes/no; `[OPEN_QUESTION]` = must be resolved before the affected phase.

## 1. Summary

**Problem.** The current app is a Capacitor web view that cannot load data (verified `Illegal invocation` bug). It only shows what a PC daemon last uploaded, does not show vendor-granted free resets, and does not follow iPhone Duo HIG.
**Actor.** The owner, a single iPhone Duo user on iOS 27.1+, holding the phone in one (usually right) hand. The user is not a developer.
**Success condition.** With the PC switched off, on Wi-Fi or cellular, the app and widget show current usage for Codex, Claude Code, Cursor and Antigravity. Refresh follows the chosen interval while the app is open. Codex and Claude Code show free-reset credits. Both Duo screens (outer and inner) and all fold postures follow Apple's iPhone Duo guidance.

## 2. Scope

**In scope**
- Native SwiftUI app + WidgetKit extension, built with the iOS 27.1 SDK.
- Four agents: Codex, Claude Code, Cursor, Antigravity.
- Direct vendor fetch from the phone; tokens in iOS Keychain.
- Refresh setting: 15 s / 30 s / 1 min / 5 min / 15 min / manual.
- Usage windows (5-hour session, weekly, per-pool where the vendor has pools) with reset countdowns.
- Free-reset credit monitoring for Codex and Claude Code.
- Right-hand fast path: 4 icons, mirrored for left hand.
- Outer-screen (compact) and inner-screen (regular) layouts with identical features.
- zh-Hant (primary) + en localisation; light theme default + dark.

**Out of scope**
- `[ASSUMPTION]` Grok (user tracks four agents).
- `[ASSUMPTION]` Gemini Live voice, model catalog, MCP tools, cost estimator.
- PC daemon, Cloudflare Worker data path, D1 (retired from the app's data path).
- App Store public release. `[ASSUMPTION]` Distribution is personal (TestFlight / own device only).
- Android, iPad-specific layouts, macOS, Apple Watch.
- Usage history charts / trends (only current state).
- Editing vendor accounts, buying plans, or redeeming a free reset from inside the app (view only).
- Multiple accounts per vendor. `[ASSUMPTION]` One account per vendor.

## 3. User Stories

- **US-1.** As the owner, I want to see all four agents' remaining usage at a glance on either Duo screen, so that I know which agent I can still use.
- **US-2.** As the owner, I want usage to refresh over my phone's own Wi-Fi or cellular at the interval I choose, so that I don't depend on my PC.
- **US-3.** As the owner, I want to see Codex and Claude Code free-reset credits and next reset times, so that I can use a free reset when the vendor grants one.
- **US-4.** As the owner, I want 4 fast-path icons in my right thumb's reach, so that I can act one-handed.
- **US-5.** As the owner, I want to sign in to each vendor inside the app (no PC involved), stay signed in, and sign out, so that refresh works without a PC.
- **US-6.** As the owner, I want a Home Screen widget with the same key numbers, so that I see them without opening the app.
- **US-7.** As the owner, I want the layout to keep my place when I fold, unfold or rotate the Duo, so that nothing jumps or breaks.

## 4. Functional Requirements

Dashboard (US-1)
- **FR-1.** Dashboard lists exactly the four agents with remaining % of the governing (most restrictive) window per agent.
- **FR-2.** Each agent shows its plan name, each window's remaining %, and time to reset (local time, Asia/Taipei).
- **FR-3.** Each agent shows "last updated" time; data older than 2× the refresh interval (min 10 min) is visibly marked stale.
- **FR-4.** An agent with no token shows "未設定" with a button to Settings — never placeholder numbers.
- **FR-5.** An agent whose last fetch failed shows the last good data, its timestamp, and the error in plain language with a retry action.

Refresh (US-2)
- **FR-6.** While the app is in the foreground, refresh runs every N seconds, where N is the chosen setting; the setting persists across launches.
- **FR-7.** "Manual" disables automatic refresh; only the user's refresh action fetches.
- **FR-8.** A refresh fetches the four agents in parallel; at most one request per agent is in flight.
- **FR-9.** Refresh uses whatever network iOS provides (Wi-Fi or cellular); no PC, Worker or VPN in the path.
- **FR-10.** With no network, no request is sent; the UI says "離線，顯示上次資料" and resumes on reconnect.
- **FR-11.** Background: app registers `BGAppRefreshTask` and widget timeline reloads; the Settings screen states that iOS controls background timing.
- **FR-12.** On HTTP 429 / 5xx, that agent backs off (honouring `Retry-After`) without affecting other agents.

Free resets (US-3)
- **FR-13.** Codex and Claude Code show "免費重置 N 次可用" when the vendor reports N ≥ 0.
- **FR-14.** When the vendor does not report reset credits, show "不提供" — never 0.
- **FR-15.** A badge appears on the agent and on fast-path icon 2 when credits > 0 or any window resets within 24 h.
- **FR-16.** "Reset reached" (window time passed) is labelled differently from "free reset credit available".

Fast path (US-4)
- **FR-17.** Four icons, each with SF Symbol + text title + VoiceOver label: (1) Refresh now `arrow.clockwise`, (2) Resets `gift`, (3) Alerts only `exclamationmark.triangle`, (4) Refresh interval `timer`.
- **FR-18.** Outer screen: icons in a bottom-trailing cluster inside the safe area (thumb zone). Inner screen: icons are `.toolbar` items (system may place them in the vertical bar).
- **FR-19.** Handedness setting (right default / left) mirrors the outer-screen cluster to bottom-leading.
- **FR-20.** "Alerts only" filters to agents with ≤ 5 % remaining; shows an empty state when none.

Sign-in (US-5) — decided 2026-11-17: **sign in inside the app, never via PC**
- **FR-21.** Each vendor row in Settings has 「登入」. It opens the vendor's own sign-in page in the system browser sheet (`ASWebAuthenticationSession`; never an embedded web view that can read the password). The app never sees or stores the password.
- **FR-21a.** `[OPEN_QUESTION]` Per-vendor sign-in method, chosen in plan P1 from what the vendor actually allows: (a) OAuth with redirect back to the app, (b) device-code flow (app shows a code; user approves on the vendor page on the same phone), (c) vendor web session in the browser sheet. A vendor with no workable phone sign-in shows 「此服務暫不支援手機登入」 — no PC fallback.
- **FR-21b.** Resulting access + refresh tokens are stored in Keychain (`kSecAttrAccessibleAfterFirstUnlock`), shared with the widget via a Keychain access group.
- **FR-21c.** Before access expiry the app renews the token on the phone using the refresh token; the user is not asked to sign in again while renewal succeeds.
- **FR-22.** Tokens are never displayed, logged, or included in diagnostics; Settings shows only "已登入 · <account email or name if the vendor returns it>".
- **FR-23.** After sign-in, the app runs a test fetch and shows 「連線成功」 or the specific failure (sign-in cancelled / denied / network).
- **FR-23a.** 「登出」 deletes that vendor's Keychain items and, where the vendor supports it, revokes the token.
- **FR-24.** HTTP 401/403 after a failed renewal marks that vendor 「需要重新登入」 with a one-tap 「重新登入」, and stops auto-refresh for that vendor until signed in again.

Widget (US-6)
- **FR-25.** Small widget: governing remaining % for 4 agents. Medium: plus next reset and Codex/Claude free-reset credits.
- **FR-26.** Widget shows the snapshot timestamp; it fetches directly using Keychain tokens when its timeline reloads.

Duo layout & continuity (US-7)
- **FR-27.** Layout branches only on horizontal size class: compact → single column; regular → `NavigationSplitView` (agent list | detail).
- **FR-28.** No interactive control overlaps a `.division` reserved region (crease) in partially folded postures.
- **FR-29.** Folding/unfolding/rotating keeps the selected agent, scroll position and open sheet.

## 5. Acceptance Criteria

### FR-1 / FR-2
- **Given** valid tokens for all four vendors **When** the dashboard loads **Then** four rows appear (Codex, Claude Code, Cursor, Antigravity), each with a remaining % and reset countdown, and no Grok row.
- **Given** a vendor returns windows 5h=80 % left, weekly=10 % left **When** displayed **Then** the agent's headline shows 10 %.

### FR-3
- **Given** interval 1 min and last success 12 min ago **When** the dashboard is visible **Then** that agent shows a "資料過舊" marker with the timestamp.

### FR-4
- **Given** no Cursor token **When** dashboard loads **Then** Cursor shows "未設定" and a "前往設定" button, and no percentage.

### FR-5
- **Given** a previous good Codex fetch **When** the next fetch times out **Then** previous numbers remain with their timestamp and an error line "連線逾時，點此重試".

### FR-6 / FR-7
- **Given** interval 15 s, app in foreground **When** 60 s elapse **Then** exactly 4 (±1) fetch rounds occur (measured via debug log / UI test).
- **Given** interval "手動" **When** 5 min elapse with no taps **Then** zero fetches occur.
- **Given** interval changed to 5 min **When** the app is relaunched **Then** the setting shows 5 分鐘.

### FR-8
- **Given** a fetch for Claude is still in flight **When** the timer fires again **Then** no second Claude request is sent.

### FR-9 / FR-10
- **Given** Wi-Fi off and cellular on, PC powered off **When** the user taps Refresh **Then** all agents with tokens update.
- **Given** Airplane Mode **When** the timer fires **Then** no request is sent and "離線，顯示上次資料" is shown; **When** network returns **Then** a refresh starts within 5 s.

### FR-11
- **Given** the app is backgrounded **When** the user opens Settings **Then** the interval section states "背景更新時間由 iOS 決定".

### FR-12
- **Given** Codex returns 429 with `Retry-After: 120` **When** the next interval fires at 15 s **Then** Codex is skipped until 120 s pass, while other agents still refresh.

### FR-13 / FR-14 / FR-16
- **Given** Claude Code reports 2 reset credits **When** displayed **Then** the row shows "免費重置 2 次可用".
- **Given** Codex's response has no reset-credit field **When** displayed **Then** the row shows "免費重置：不提供", not "0".
- **Given** a weekly window's reset time has passed but no new data has arrived **When** displayed **Then** it says "已到重置時間，等待更新", not "免費".

### FR-15
- **Given** Codex credits = 1 **When** the dashboard shows **Then** fast-path icon 2 shows a badge and its accessibility label includes "1 項可用".

### FR-17 / FR-18 / FR-19
- **Given** the outer screen in portrait, right-hand mode **When** the dashboard shows **Then** the 4 icons are bottom-trailing, each ≥ 44×44 pt, and fully inside the safe area.
- **Given** left-hand mode **When** the dashboard shows **Then** the cluster is bottom-leading.
- **Given** VoiceOver on **When** focus reaches each icon **Then** it reads its text title.

### FR-20
- **Given** no agent ≤ 5 % **When** "Alerts only" is on **Then** an empty state "目前沒有告警" is shown with a button to turn the filter off.

### FR-21 / FR-22 / FR-23 / FR-23a
- **Given** Claude Code not signed in, PC off **When** the user taps 登入 and completes the vendor page on the phone **Then** the app returns to Settings showing 「已登入」 and 「連線成功」, and the dashboard shows Claude Code numbers.
- **Given** the sign-in sheet is open **When** the user taps Cancel **Then** the app shows 「已取消登入」 and nothing is stored.
- **Given** signed in **When** 登出 is confirmed **Then** the vendor shows 「未設定」 and its Keychain items are gone.
- **Given** a vendor with no phone sign-in method (FR-21a) **When** Settings opens **Then** its 登入 button is disabled with 「此服務暫不支援手機登入」.

### FR-21c
- **Given** an access token that expires in 2 minutes and a valid refresh token **When** the next refresh round runs **Then** the token is renewed silently and data updates with no sign-in prompt.

### FR-24
- **Given** Cursor returns 401 **When** refreshed **Then** Cursor shows "需要重新登入" and no further Cursor requests are sent until the token is replaced.

### FR-25 / FR-26
- **Given** a medium widget on the Home Screen **When** its timeline reloads **Then** it shows 4 percentages, next reset and the Codex/Claude credits, with the snapshot time.

### FR-27 / FR-28 / FR-29
- **Given** the Duo is unfolded (regular width) **When** the app runs **Then** an agent list and a detail pane are visible side by side.
- **Given** book-style partial fold **When** the app is shown **Then** no button intersects the crease frame (screenshot P05).
- **Given** agent "Claude Code" selected and scrolled **When** the device is folded to the outer screen **Then** Claude Code is still selected at the same scroll position (P10).

## 6. Edge Cases and Failure Modes

- **Case:** Vendor changes response schema. **Behavior:** parser rejects it; agent shows "資料格式已變更，請更新 App"; last good data kept; no crash.
- **Case:** Percent outside 0–100 or negative. **Behavior:** clamp for display, mark agent "資料異常".
- **Case:** Reset time missing. **Behavior:** show "重置時間不明"; no countdown.
- **Case:** Reset time in the past. **Behavior:** "已到重置時間，等待更新" (FR-16) and trigger one immediate refresh for that agent.
- **Case:** Device clock wrong by > 5 min vs server `Date` header. **Behavior:** countdowns use server time offset.
- **Case:** Token expires during background. **Behavior:** widget shows "需要重新登入" for that vendor.
- **Case:** User taps Refresh repeatedly. **Behavior:** taps while a round is in flight are ignored (haptic once); no queued duplicates.
- **Case:** Interval 15 s on cellular. **Behavior:** allowed; Settings shows estimated data use per hour.
- **Case:** All four tokens missing (first launch). **Behavior:** onboarding empty state with one action "新增第一個權杖".
- **Case:** Keychain unavailable before first unlock. **Behavior:** widget shows last snapshot with timestamp, no fetch.
- **Case:** Fold during an in-flight request. **Behavior:** request continues; result applies to the new layout (FR-29).
- **Case:** Large accessibility text size. **Behavior:** numbers and labels wrap, never truncate (P11).
- **Case:** Vendor endpoint unreachable from iOS (CORS is not an issue natively, but geo/blocked). **Behavior:** agent error state; other agents unaffected.

## 7. Non-Functional Requirements

- **Compatibility.** iOS 27.1+ deployment target, Xcode 27.1+, Swift 6.4 with strict concurrency; iPhone Duo primary, other iPhones must still work (IOS_SPEC §1).
- **Performance.** Cold launch to first cached render ≤ 1 s on device; a refresh round finishes ≤ 10 s p95 on LTE; per-request timeout 15 s.
- **Network/data.** Each round is ≤ 4 requests; payload per round `[ASSUMPTION]` ≤ 50 KB.
- **Security & privacy.** Tokens only in Keychain; never in UserDefaults, logs, screenshots, crash reports or git. HTTPS only (ATS default). No third-party SDKs. `PrivacyInfo.xcprivacy` present. No analytics.
- **Accessibility.** All targets ≥ 44×44 pt; Dynamic Type up to AX5 without truncation; contrast ≥ 4.5:1; status never by colour alone; Reduce Motion / Reduce Transparency supported; full VoiceOver labels.
- **HIG / Duo.** Forbidden-API audit (IOS_SPEC §4.3) = 0 hits; system containers (`NavigationSplitView`, `.toolbar`, `.sheet`); Liquid Glass only on controls; posture matrix P01–P13 × C1–C6 passes.
- **Localisation.** All strings in `Localizable.xcstrings` (zh-Hant, en); dates/percent via formatters.
- **Theme.** Light default + dark (06-ui-ux §3); semantic colours only.
- **Observability.** On-device debug log (no tokens) showing per-agent fetch time, status code, duration — viewable in Settings › 診斷.

## 8. Dependencies

- **Vendor usage endpoints** (unofficial) for Codex, Claude Code, Cursor, Antigravity — `[OPEN_QUESTION]` exact URLs, auth, fields; resolved in plan P1. **Not ready.**
- **Mac build path:** Xcode 27.1 on a cloud Mac or GitHub `xcode-27` runner — **not ready** (needs user approval/billing).
- **iOS 27.1 SDK APIs:** `reservedRegions`, `NavigationSplitView` on Duo, vertical toolbar — verify per IOS_SPEC §4.4 (plan P1).
- **Apple Developer account** for signing / TestFlight — user-owned.
- **XcodeGen** (build tool only, not shipped).
- **Codex** as second reviewer for every PR (dual review).

## 9. Risks and Mitigations

- **Risk:** Vendors' usage endpoints are undocumented and may change or block third-party clients. **Mitigation:** per-provider parser with schema check, clear error state, fixtures for fast fixes; never fake numbers.
- **Risk (highest):** Vendors may not allow a third-party iPhone app to sign in. Codex and Claude Code sign-in is built for their desktop CLIs (localhost redirect), and Google commonly blocks sign-in from non-official clients for Antigravity. **Mitigation:** P1 spike tries each method in FR-21a per vendor before any UI is built; a vendor that fails is shown as unsupported (FR-21a), and the user decides whether to keep it in v3.
- **Risk:** Access tokens expire (hours). **Mitigation:** on-phone renewal (FR-21c); otherwise FR-24 one-tap re-sign-in.
- **Risk:** Vendor ToS may forbid automated polling. **Mitigation:** minimum interval 15 s, per-vendor backoff; user accepts ToS risk (personal use).
- **Risk:** Background refresh cadence controlled by iOS. **Mitigation:** stated in UI (FR-11); foreground guarantee only.
- **Risk:** Duo simulator can't run most extensions. **Mitigation:** widget verified on device (G5).
- **Risk:** No Mac in this cloud session. **Mitigation:** Core logic testable on Linux (G1); G2+ via CI runner.

## 10. Open Questions

- **Q1.** **Resolved 2026-11-17:** sign in inside the app, not via PC (FR-21…FR-24). Remaining: which method works per vendor (FR-21a) — owner: P1 spike.
- **Q2.** `[OPEN_QUESTION]` Should the app send a local notification when a free-reset credit appears or a weekly window resets? Default: **no** in v3 (badge only). Owner: user.
- **Q3.** `[OPEN_QUESTION]` Do Cursor and Antigravity also grant free resets? Default: not shown. Owner: P1 spike.
- **Q4.** `[ASSUMPTION]` Drop Grok, voice, model catalog. Owner: user (yes/no).
- **Q5.** `[OPEN_QUESTION]` Approve `xcode-27` runner billing or provide a cloud Mac. Owner: user.
- **Q6.** `[ASSUMPTION]` Personal distribution only (TestFlight), not public App Store. Owner: user.
- **Q7.** `[ASSUMPTION]` App name stays "OpenTokenUsage"; bundle ID unchanged from current project (IOS_SPEC forbids changing it without confirmation).

## 11. Success Metrics

- **Leading:** all four agents show data with PC off on cellular (G5 checklist); 15 s / 1 min / manual cadence verified by UI test; posture matrix 13/13 pass; forbidden-API audit 0.
- **Lagging:** over the first 2 weeks of use, the owner no longer runs the PC daemon; no session where the app showed a stale number without a stale marker; owner reports catching ≥ 1 free reset via the badge.
