# Competitive Gap Analysis + Feature Spec: v3.1 「一眼可見、通知完整」

Status: P1 + P2 implemented 2026-11-19 in v3.1.0 (owner approved; defaults taken for Q2 = 12 h / 50 %, Q3 = control starts the Live Activity) · builds on `spec-quota-threshold-alerts.md` (QuotaAlerts, FR-A*), `spec-usage-pace-charts.md` (PaceEstimate) and `spec-widget-alignment.md`.
Tags: untagged = read on the App Store pages on 2026-11-19 or verified in this repo's code; `[ASSUMPTION]` = author default, confirm yes/no; `[OPEN_QUESTION]` = must be answered before implementation; `[VERIFY]` = needs a check on device.

---

## Part A — What the two competitors do, and where we stand

### A.1 The two apps

| | **A. AI Token Limits: Usage Tracker** (Pocket Grove Ltd, id6803703387) | **B. AI Token Usage Tracker** (Siegfried-Thor Bolz, id6760191068) |
|---|---|---|
| What it tracks | Subscription **quota windows** (same idea as ours) | Anthropic **API spend in dollars** (Admin API key). Says subscription use (claude.ai, Claude Code plans) is *not* tracked |
| Providers | Claude, Codex, Cursor, Grok, Muse, GitHub Copilot | Anthropic API only |
| Price | Free + Pro: US$1.99/mo, US$7.99/yr, US$12.99 lifetime. Pro unlocks widgets and alerts | Free + Pro US$3.99 once (7-day trial) |
| Minimum OS | iOS 18 | iOS 27.2, plus macOS menu bar and visionOS |
| Ratings | Too few to show | Too few to show |
| Release pace | 1.0 on Sep 15 → 1.7 in Nov (about one release every 1–2 weeks) | 2.1 → 2.2.0 (iPhone Duo support) |
| Privacy | On-device, Keychain, no backend; the label still lists Device ID, purchases and usage data | "Data Not Collected" |

So **A is our direct competitor**; B shows a different product (API cost) that our earlier spec already listed as a separate candidate.

### A.2 Feature matrix

✅ we have it · 🟡 partly · ❌ missing · ➖ not relevant to us

| Area | Feature | A | B | **Ours (v3.0.0)** | Gap |
|---|---|---|---|---|---|
| Providers | Claude Code / Codex / Cursor | ✅ | ➖ | ✅ (Antigravity: not on phone) | — |
| | GitHub Copilot | ✅ | ❌ | ❌ | **Gap** (P4) |
| | Grok, Muse | ✅ | ❌ | ❌ (Grok removed on purpose in v1.4) | Keep out |
| | Anthropic Admin API spend ($, tokens, cache, per model/key/workspace) | ❌ | ✅ | ❌ | **Gap** (P4, separate spec) |
| Status | Last successful update **per provider** | ✅ | — | 🟡 `fetchedAt` is stored per item, but `QuotaStore.state` keeps only `result.firstError` | **Gap** (P1) |
| | Refresh one provider on its own | ✅ | — | ❌ (one global refresh) | **Gap** (P1) |
| | Clear message when a plan is unsupported | ✅ | — | 🟡 `[VERIFY]` | P1 |
| Glanceable | Home Screen widget | ✅ | ✅ | ✅ small, medium | — |
| | **Lock Screen** widgets | ✅ | ❌ | ❌ (`supportedFamilies` is small + medium only) | **Gap** (P1) |
| | Widget remembers the chosen limit (configurable) | ✅ | — | ❌ | **Gap** (P1) |
| | **Live Activity** for next reset | ✅ | ❌ | ❌ | **Gap** (P1) |
| | **Control Center** control | ✅ | ❌ | ❌ | **Gap** (P1) |
| | **Siri / Shortcuts** | ✅ | ❌ | ❌ | **Gap** (P1) |
| Alerts | Level alerts | ✅ 25 % and 10 % left | ✅ $ spend limit | ✅ 80 % and 95 % used | — |
| | Alert when the limit is **reached** | ✅ | — | ❌ | **Gap** (P2) |
| | Optional earlier alerts | ✅ | — | ❌ (fixed levels) | **Gap** (P2) |
| | Run-out (pace) alert | ✅ | ❌ | ✅ | — |
| | Notification when a window **resets** | ✅ | ❌ | ❌ (only free-reset *credits*) | **Gap** (P2) |
| | "Quota still unused before reset" reminder | ✅ | ❌ | ❌ | **Gap** (P2) |
| | Quiet hours | ✅ | ❌ | ❌ | **Gap** (P2) |
| | Weekly summary | ✅ | ❌ | ❌ | **Gap** (P2) |
| | Free-reset credit alerts | ❌ | ❌ | ✅ | **Ours only** |
| Analysis | Pace forecast per window | ✅ | ❌ | ✅ | — |
| | Trends | ✅ 24 h / 7 / 14 / 30 d | ✅ hourly (Pro) | 🟡 daily / weekly / monthly, 400-day history, no intraday | **Gap** (P3) |
| | Show used % *or* remaining %; relative *or* exact reset | ✅ | — | ❌ | **Gap** (P3) |
| | CSV export | ❌ | ✅ | ❌ | **Gap** (P3) |
| | Model and price catalog | ❌ | 🟡 | ✅ | **Ours only** |
| Accounts | One account per provider | ✅ | multi-key (Pro) | ✅ | Multi-account P4 |
| | Sign out removes credentials | ✅ | ✅ | ✅ 「登出」 | — |
| | Demo data without an account | ✅ | — | ✅ 「示範資料」 | — |
| Platform | iPhone Duo two-pane layout | — | ✅ (compat only) | ✅ native list + detail at the fold, one-hand fast path | **Ours stronger** |
| | Mac / visionOS | 🟡 | ✅ | ❌ (iPhone only) | Keep out |
| | Languages | 5 (no zh-Hant) | EN | zh-Hant | ➖ single owner |
| Quality | Accessibility labels | not declared | not declared | ✅ VoiceOver labels on rows, charts, widget | **Ours stronger** |

### A.3 What this tells us

1. **Our data and analysis are on par or ahead** (pace forecast, run-out alerts, free-reset credits, model catalog, Duo layout, accessibility).
2. **Our biggest gap is reach outside the app.** A shows usage on the Lock Screen, in a Live Activity, in Control Center and through Siri. We show it only inside the app and on two Home Screen widget sizes. For a tool you check many times a day, this matters most.
3. **Second gap: notification coverage.** A tells you when a limit is hit, when a window resets, and when quota is about to go unused, and it respects quiet hours. We cover the "running out" half only.
4. **Third gap: per-provider honesty.** Our sources are undocumented endpoints that can break one at a time, yet the app shows one global error. A shows each provider's last good update and refreshes each one on its own.
5. B's dollar-cost tracking is a different product. It stays a separate spec (P4).

### A.4 Priority

| Tranche | Contents | Why this order |
|---|---|---|
| **P1 — this spec** | Per-provider status and refresh · Lock Screen + configurable widgets · Live Activity · Control Center · Siri/Shortcuts | Largest daily-use gap; no new data source; reuses `Quota`, `PaceEstimate`, widget extension |
| **P2 — this spec** | Limit-reached alert · reset notification · unused-quota reminder · quiet hours · weekly summary · early-alert option | Extends `QuotaAlerts` with the same pure, tested pattern |
| P3 — next spec | Intraday 24 h trend, 14-day range, used/remaining and relative/exact display options, CSV export | Needs a history format change (hourly samples) |
| P4 — separate specs | GitHub Copilot source · Anthropic/OpenAI Admin API cost · multiple accounts per provider | New endpoints, new credentials, new risk |

---

## Part B — Feature Spec: v3.1 (P1 + P2)

## 1. Summary

**Problem.** The owner checks Claude Code, Codex and Cursor quota many times a day, but the numbers live only inside the app and two Home Screen widget sizes. Alerts cover only "running out"; nothing says when a blocked window is usable again, when weekly quota is about to be wasted, and alerts can arrive at night. When one provider's endpoint breaks, the app shows one global error.
**Actor.** The owner, sole user, on iPhone / iPhone Duo (iOS 27.1), app sideloaded with a free Apple ID. All work is done by the app, its widget extension and iOS; there is no push server.
**Success condition.** Without opening the app, the owner can see each provider's remaining % and next reset on the Lock Screen, in a Live Activity, in Control Center and by asking Siri. The owner gets notified when a limit is hit, when it resets, and when weekly quota is about to go unused, never during quiet hours. Each provider row shows its own last good update and error.

## 2. Scope

**In scope**
- P1-a: per-provider refresh state, last successful update, per-provider retry.
- P1-b: Lock Screen widgets (inline, circular, rectangular) and a configurable provider/window choice for all widget sizes.
- P1-c: a Live Activity (Lock Screen + Dynamic Island) that follows one quota window's reset.
- P1-d: App Intents: a Control Center control and Siri/Shortcuts phrases.
- P2: limit-reached alert, reset notification, unused-quota reminder, quiet hours, weekly summary, early-alert option.

**Out of scope**
- Everything in tranches P3 and P4 (intraday trends, display options, CSV, Copilot, Admin API cost, multi-account).
- Push-based Live Activity updates (needs an APNs server; the repo has none for the phone).
- Grok, Muse, Google Antigravity on the phone.
- Mac, visionOS, Apple Watch, other languages.
- Paywall or in-app purchase (personal app).
- Changing refresh floors (Claude Code 5 min; Codex, Cursor 1 min) or the 429 back-off.
- `[ASSUMPTION]` Large and extra-large widget sizes.

## 3. User Stories

- **US-1.** As the owner, I want each provider to show when it last updated successfully and why it failed, so that I know which number I can trust.
- **US-2.** As the owner, I want to retry one provider without waiting for the others, so that a slow or broken one doesn't hold up the rest.
- **US-3.** As the owner, I want my most important window on the Lock Screen, so that I see it without unlocking.
- **US-4.** As the owner, I want to pick which provider and window a widget shows, so that each widget is useful.
- **US-5.** As the owner, I want a Live Activity counting down to a window's reset, so that I know when I can work again.
- **US-6.** As the owner, I want to start that Live Activity from Control Center or Siri, so that I don't have to open the app.
- **US-7.** As the owner, I want to ask Siri how much quota is left, so that I can check hands-free.
- **US-8.** As the owner, I want to be told when a limit is fully used and when it resets, so that I stop and restart at the right time.
- **US-9.** As the owner, I want a reminder when weekly quota will go unused, so that I don't waste what I pay for.
- **US-10.** As the owner, I want no quota notifications during my sleep hours, so that alerts don't wake me.
- **US-11.** As the owner, I want a weekly summary, so that I see my pattern without opening analytics.

## 4. Functional Requirements

### P1-a Per-provider status
- **FR-1.** `QuotaStore` keeps, per `ProviderSource` (`claude`, `codex`, `cursor`), a state: `idle`, `refreshing`, `failed(QuotaClientError)`, and `lastSuccess: Date?`.
- **FR-2.** `lastSuccess` and the last error per provider persist across launches (App Group defaults, so the widget can read them).
- **FR-3.** Each provider row on 額度 shows 「\(relative time) 更新」 from `lastSuccess`.
- **FR-4.** A provider whose last refresh failed shows an error line under its name with a cause-specific message: 401/403 → 「需要重新登入」 with a button to its sign-in; 429 → 「請求過多，\(n) 分鐘後再試」; parse failure → 「服務回應格式改變，暫時無法讀取」; offline → 「沒有網路」.
- **FR-5.** A failed provider keeps showing its last good numbers, marked 「上次資料」.
- **FR-6.** Pull-to-refresh refreshes every provider. A context-menu action 「只更新這個服務」 refreshes one provider and respects that provider's floor.
- **FR-7.** A plan the parser recognises but cannot show (e.g. a window type it doesn't know) shows 「這個方案目前無法顯示額度」 instead of empty bars. `[VERIFY]` which Codex/Cursor plans hit this today.

### P1-b Widgets
- **FR-8.** The widget extension adds `accessoryInline`, `accessoryCircular`, `accessoryRectangular` families.
- **FR-9.** `accessoryCircular` shows a gauge of remaining % with the provider badge letter.
- **FR-10.** `accessoryRectangular` shows provider name, remaining %, and reset time as relative text.
- **FR-11.** `accessoryInline` shows 「\(provider) 剩 \(n)% · \(reset)」.
- **FR-12.** All widget sizes use an `AppIntentConfiguration` with two parameters: 服務 (provider) and 窗口 (window: e.g. 5 小時 / 每週 / 方案). Default: 「最緊的窗口」 = the window with the lowest remaining % across providers.
- **FR-13.** A widget whose chosen provider is signed out shows 「未登入」 and opens Settings › 帳號 on tap.
- **FR-14.** Widgets show the data time; data older than 1 hour is shown dimmed with 「\(time) 的資料」.

### P1-c Live Activity
- **FR-15.** The app declares Live Activity support. One activity type 「重置倒數」 holds: provider, pool, window label, remaining %, reset date, data time.
- **FR-16.** The Lock Screen view shows provider, window, remaining %, and a countdown to reset drawn by the system (`Text(timerInterval:)`), so the countdown stays exact without app updates.
- **FR-17.** The Dynamic Island compact view shows the provider badge and the countdown; the expanded view adds remaining % and data time.
- **FR-18.** The detail page of each window has 「在鎖定畫面追蹤」, which starts the activity for that window. At most one activity runs at a time; starting a new one ends the old one.
- **FR-19.** Every successful refresh (foreground or background) updates the running activity's remaining % and data time.
- **FR-20.** When the reset time passes, the activity shows 「已重置」 and ends with a dismissal 15 minutes later. `[ASSUMPTION]` 15 minutes.
- **FR-21.** If the window's reset date moves (new window), the activity follows the new date.
- **FR-22.** No activity can be started while 示範資料 is on.

### P1-d Control Center and Siri
- **FR-23.** An App Intent 「追蹤下次重置」 starts the FR-15 activity for a chosen window (default: tightest window, FR-12). It runs without opening the app.
- **FR-24.** A Control Center control (`ControlWidgetButton`) runs FR-23. Its label shows the tightest window's provider and remaining % from the last refresh.
- **FR-25.** An App Intent 「查詢剩餘額度」 answers with a spoken/visual line per signed-in provider: 「Claude Code 5 小時剩 42%，2 小時 10 分後重置」. It uses cached data and states the data time when older than 15 minutes.
- **FR-26.** `AppShortcutsProvider` registers zh-Hant phrases for FR-23 and FR-25, each containing the app name (e.g. 「用 OpenTokenUsage 查額度」).
- **FR-27.** Intents read the same cache the widget reads; they never trigger a network refresh. `[ASSUMPTION]` keeps them fast and inside the floors.

### P2 Alerts (extends `QuotaAlerts`, `spec-quota-threshold-alerts.md`)
- **FR-28.** A **limit-reached alert** fires once per window when `used ≥ 100` or the tier's status is exhausted: 「\(provider) · \(pool) 已用完」, body 「\(reset in) 後重置。」 It replaces a 95 % alert from the same refresh (same rule as FR-A6).
- **FR-29.** A new Settings picker 「提醒時機」 under 額度警示通知: 標準 (80 / 95 / 用完) — default — or 提早 (50 / 80 / 95 / 用完).
- **FR-30.** A **reset notification** is scheduled as a local time-based notification at the window's `resetsAt` when the last reading of that window was ≥ 80 % used. Text: 「\(provider) · \(pool) 已重置，可以繼續用了」.
- **FR-31.** On every refresh the reset notification of each window is rescheduled (or cancelled when used drops below 80 % or `resetsAt` changes), keyed by the FR-A10 window key.
- **FR-32.** An **unused-quota reminder** is scheduled 12 hours before `resetsAt` for weekly windows only, when the last reading shows < 50 % used: 「\(provider) 每週額度還剩 \(n)%，12 小時後重置」. Rescheduled on each refresh; cancelled when used ≥ 50 %. `[ASSUMPTION]` 12 h and 50 %.
- **FR-33.** Each P2 kind has its own switch under one Settings group 「通知」: 用完與重置, 未用完提醒, 每週摘要. The existing 免費重置通知 and 額度警示通知 stay as they are.
- **FR-34.** **Quiet hours**: a switch 「勿擾時段」 with start and end times (default 23:00–08:00, off). An immediate alert that would arrive inside the period is scheduled at the period's end instead. A time-based alert whose trigger falls inside the period is moved to the period's end.
- **FR-35.** A held alert is dropped at delivery time if it no longer applies: a held level/limit alert whose window has reset, or a held reset notification that is older than 2 hours. `[ASSUMPTION]` Implemented by scheduling with the window key and cancelling on the next refresh when obsolete.
- **FR-36.** **Weekly summary**: one notification each Monday 09:00 (moved by quiet hours if needed), built from `UsageHistory` for the previous 7 days: per provider, how many times a window hit 100 % and the busiest day. Rebuilt on each refresh so it uses the latest data.
- **FR-37.** Tapping a reset or unused reminder opens 額度; tapping the weekly summary opens 用量分析.
- **FR-38.** No P2 notification is scheduled or sent while 示範資料 is on (same rule as FR-A12).

## 5. Acceptance Criteria

### FR-1–FR-5 Per-provider status
- **Given** Claude Code returns 200 and Codex returns 401, **When** the app refreshes, **Then** the Claude row shows 「剛剛更新」 and the Codex row shows 「需要重新登入」 with a sign-in button.
- **Given** Codex failed with 401, **When** the 額度 page shows, **Then** Codex still shows its last good remaining % labelled 「上次資料」.
- **Given** every provider succeeds, **When** the page shows, **Then** no error line appears on any row.
- **Given** a Cursor response that does not parse, **When** the app refreshes, **Then** only the Cursor row shows 「服務回應格式改變，暫時無法讀取」.

### FR-6
- **Given** Codex was refreshed 30 s ago, **When** the owner taps 「只更新這個服務」 on Codex, **Then** no request is sent and the row says when the next update is allowed.
- **Given** Cursor was refreshed 2 min ago, **When** the owner taps 「只更新這個服務」 on Cursor, **Then** only Cursor's request is sent and only its timestamp changes.

### FR-8–FR-14 Widgets
- **Given** a rectangular Lock Screen widget set to Claude Code · 5 小時, **When** the app last read 58 % used, **Then** the widget shows 「Claude Code 剩 42%」 and the reset time.
- **Given** a widget set to 「最緊的窗口」, **When** Codex weekly has the lowest remaining %, **Then** the widget shows Codex weekly.
- **Given** a widget set to Cursor and Cursor is signed out, **When** the widget renders, **Then** it shows 「未登入」.
- **Given** the last refresh was 3 hours ago, **When** any widget renders, **Then** it shows the numbers dimmed with the data time.

### FR-15–FR-22 Live Activity
- **Given** Claude Code 5 小時 resets in 2 h 10 min, **When** the owner taps 「在鎖定畫面追蹤」, **Then** a Lock Screen activity shows the window and a countdown from 2:10:00.
- **Given** an activity is running, **When** a background refresh reads a new remaining %, **Then** the activity shows the new % and data time.
- **Given** an activity is running, **When** the reset time passes, **Then** it shows 「已重置」 and is gone from the Lock Screen within 15 minutes.
- **Given** an activity is running for Claude, **When** the owner starts one for Codex, **Then** only the Codex activity remains.
- **Given** 示範資料 is on, **When** the owner opens a window detail, **Then** 「在鎖定畫面追蹤」 is disabled.
- **Given** Live Activities are disabled for the app in iOS Settings, **When** the owner taps 「在鎖定畫面追蹤」, **Then** the app shows 「即時動態已關閉，需要到 iOS「設定」開啟。」.

### FR-23–FR-27 Control Center and Siri
- **Given** the Control Center control is added, **When** the owner taps it with the phone locked, **Then** the activity for the tightest window starts without opening the app.
- **Given** cached data from 5 minutes ago, **When** the owner says 「用 OpenTokenUsage 查額度」, **Then** Siri reads one line per signed-in provider and no network request is made.
- **Given** cached data from 2 hours ago, **When** the owner runs 查詢剩餘額度, **Then** the answer begins with 「兩小時前的資料：」.
- **Given** no provider is signed in, **When** the owner runs 查詢剩餘額度, **Then** the answer is 「還沒有登入任何服務」.

### FR-28–FR-29
- **Given** Codex 5 h was at 90 % and alerts are on, **When** a refresh reads 100 %, **Then** one notification 「Codex · … 已用完」 arrives and no separate 95 % alert.
- **Given** 提醒時機 = 標準, **When** a window reaches 55 %, **Then** no notification arrives.
- **Given** 提醒時機 = 提早, **When** a window reaches 55 % for the first time, **Then** one 50 % alert arrives.

### FR-30–FR-31 Reset notification
- **Given** Claude 5 h read 100 % with reset at 14:00, **When** 14:00 comes and the app has not run since, **Then** 「Claude Code · … 已重置，可以繼續用了」 arrives at 14:00.
- **Given** Claude 5 h read 30 % used, **When** its reset time comes, **Then** no reset notification arrives.
- **Given** a reset notification was scheduled for 14:00, **When** a refresh shows the window's `resetsAt` moved to 15:00, **Then** the notification arrives at 15:00 and not at 14:00.

### FR-32 Unused reminder
- **Given** Codex weekly reads 30 % used and resets Sunday 20:00, **When** Sunday 08:00 comes, **Then** 「Codex 每週額度還剩 70%，12 小時後重置」 arrives.
- **Given** the same window reaches 60 % used on Saturday, **When** Sunday 08:00 comes, **Then** no reminder arrives.
- **Given** a 5-hour window at 10 % used, **When** its reset approaches, **Then** no unused reminder arrives.

### FR-34–FR-35 Quiet hours
- **Given** quiet hours 23:00–08:00 are on, **When** a 95 % alert is triggered at 01:00, **Then** it is delivered at 08:00.
- **Given** that held 95 % alert, **When** the window resets at 05:00 and the app refreshes at 06:00, **Then** nothing about the old window is delivered at 08:00.
- **Given** quiet hours are off, **When** an alert triggers at 01:00, **Then** it arrives at 01:00.

### FR-36 Weekly summary
- **Given** 每週摘要 is on and Claude hit 100 % twice last week, **When** Monday 09:00 comes, **Then** a summary arrives that mentions Claude Code 2 次用完.
- **Given** 每週摘要 is off, **When** Monday 09:00 comes, **Then** no summary arrives.

### FR-38
- **Given** 示範資料 is on and all notification switches are on, **When** sample data shows 100 % used, **Then** no notification is scheduled (pending-request list is empty for quota kinds).

## 6. Edge Cases and Failure Modes

- **Case:** Reset time is unknown for a window. **Behavior:** no reset notification, no unused reminder, Live Activity button disabled with 「沒有重置時間」.
- **Case:** Codex sends only `reset_after_seconds`, so `resetsAt` drifts a few seconds each refresh. **Behavior:** reuse FR-A10a (within 10 minutes = same window); do not reschedule notifications for drift under 10 minutes.
- **Case:** Background refresh doesn't run for hours. **Behavior:** time-based notifications (reset, unused, summary) still fire from the last reading; level alerts wait for the next refresh. The text of time-based alerts uses data from the last reading only.
- **Case:** Notification permission denied. **Behavior:** all notification switches stay off; footer shows the existing 「通知已關閉…」 + 「開啟設定」.
- **Case:** iOS pending-notification limit (64). **Behavior:** at most 3 providers × few windows × 2 kinds + 1 summary ≈ under 20 pending; if more are needed, the soonest are kept. `[ASSUMPTION]` 64 is the iOS limit per app.
- **Case:** Live Activity exceeds the system's maximum run time. **Behavior:** iOS ends it; the next start replaces it. The detail page shows the button again.
- **Case:** A 5-hour window reset is more than the Live Activity's maximum life away. **Behavior:** cannot happen for 5 h; for weekly windows, the button text says 「最多追蹤 8 小時」 and the activity ends early. `[VERIFY]` current ActivityKit limit on iOS 27.
- **Case:** Provider signed out while its activity runs. **Behavior:** the activity ends.
- **Case:** Quiet hours where start = end. **Behavior:** treated as off; the time pickers block saving equal times.
- **Case:** Quiet hours crossing midnight (23:00–08:00). **Behavior:** supported; a trigger at 23:30 or 07:59 is held.
- **Case:** Time zone change while notifications are scheduled. **Behavior:** reset and unused notifications are absolute dates and follow the real reset; weekly summary and quiet hours use local time and are rescheduled on the next refresh.
- **Case:** Widget configured for a window that no longer exists (plan changed). **Behavior:** shows 「窗口已不存在，請重新設定」.

## 7. Non-Functional Requirements

- **Performance.** Widget timeline and intents read cache only; render ≤ 1 s on device. `[ASSUMPTION]` No new network calls from the extension.
- **Reliability.** No change to refresh floors or 429 back-off. All alert decision logic is pure and unit-tested like `QuotaAlerts.increases` (target: every FR in §4 that decides "send / don't send" has a test).
- **Security & privacy.** Tokens stay in the Keychain; the widget extension and intents read only the cached quota numbers in the App Group, never credentials. No analytics, no server.
- **Compatibility.** iOS 27.1, iPhone Duo outer (compact) and inner (regular) screens; Dynamic Island present or not. Must work with a free Apple ID build: no new extension targets — Lock Screen widgets, the Live Activity UI and the Control Center control all go in the existing `OpenTokenUsageWidget` extension.
- **Accessibility.** Every new widget, activity and control has a VoiceOver label with provider, window, remaining % and reset time (same pattern as `QuotaWidgetContent.rowLabel`). Text uses Dynamic Type in app screens; Lock Screen families follow system sizing. Colour is never the only signal of level.
- **Internationalization.** zh-Hant only, consistent with `developmentLanguage: zh-Hant`.

## 8. Dependencies

- ActivityKit, WidgetKit (accessory families, `ControlWidget`), App Intents (`LiveActivityIntent`, `AppShortcutsProvider`), UserNotifications — all in the iOS 27 SDK; no third-party code.
- `Info.plist` key `NSSupportsLiveActivities = YES` via `project.yml`.
- Existing: `QuotaStore`, `QuotaCache` (App Group), `PaceEstimate`, `QuotaAlerts`, `ResetAlerts`, `NotificationRouter`, `UsageHistory`.
- GitHub Actions `build-ios.yml` (xcode-27) and `ios-simulator-screenshots.yml` must still build and capture both Duo screens.

## 9. Risks and Mitigations

- **Risk:** Free Apple ID provisioning limits (App ID count per week, capabilities). **Mitigation:** no new targets or new capabilities beyond what already builds; verify a free-account install before merging. `[VERIFY]`
- **Risk:** Live Activity shows a stale % because there is no push server. **Mitigation:** the countdown is drawn by the system and always correct; the % shows its data time.
- **Risk:** Vendors change undocumented endpoints. **Mitigation:** per-provider error states (FR-4) make the break visible and limited to one row.
- **Risk:** Too many notifications. **Mitigation:** each kind has its own switch, once-per-window rules, quiet hours, and reset notifications only after heavy use (≥ 80 %).
- **Risk:** Scope is large for one release. **Mitigation:** ship in two PRs — P1 (FR-1–27) then P2 (FR-28–38); each can be tested on its own.

## 10. Open Questions

- `[OPEN_QUESTION]` Q1. Ship P1 and P2 together as v3.1, or P1 first? Default: P1 first (glanceable), then P2.
- `[OPEN_QUESTION]` Q2. Unused-reminder thresholds: 12 h before reset and < 50 % used — OK?
- `[OPEN_QUESTION]` Q3. Should the Control Center control start the Live Activity (default) or open the app on 額度?
- `[OPEN_QUESTION]` Q4. Which P4 item is next after this: GitHub Copilot quota, or Anthropic Admin API cost (competitor B's product)?
- `[VERIFY]` Q5. Which Codex/Cursor plans today produce an empty or wrong row (input to FR-7).

## 11. Success Metrics

Single-owner app, so metrics are the owner's observations over the first two weeks after install:
- **Leading:** a Lock Screen widget and the Control Center control are in use; at least one Live Activity is started per working day; Siri phrase works on first try.
- **Lagging:** the owner opens the app less often just to check numbers; no "surprise" block by Claude Code / Codex / Cursor without a prior alert; no quota notification arrives during quiet hours; at least one weekly reminder leads to using quota that would have been wasted.
- **Quality gates:** all new decision logic covered by unit tests; CI builds the unsigned `.ipa`; both Duo screens captured by the screenshot workflow with no layout regression.
