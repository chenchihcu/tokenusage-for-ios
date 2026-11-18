# Feature Spec: 額度警示通知 — usage-threshold and run-out alerts

Status: implemented 2026-11-19 (owner approved, defaults taken for Q1–Q3; Q4 still to confirm on device) · builds on `spec-usage-pace-charts.md` (PaceEstimate, FR-P2…FR-P5) and the free-reset notification (`Data/ResetAlerts.swift`).
Idea source: the reference app's 「Notify when spending reaches threshold」 switch. That app warns on dollars; this one warns on each subscription quota window.
Tags: untagged = stated by the owner or verified in the code; `[ASSUMPTION]` = author default, confirm yes/no; `[OPEN_QUESTION]` = must be answered before implementation.

## 1. Summary

**Problem.** Today the app only notifies when free-reset credits appear. The owner finds out that a Claude Code, Codex or Cursor window is nearly used up only by opening the app, or when the tool refuses a request.
**Actor.** The owner, the single user of the app on iPhone / iPhone Duo (iOS 27.1). Alerts are produced by the app's own refresh, in the foreground or in iOS background refresh. There is no push server.
**Success condition.** With 「額度警示通知」 on, the owner gets one local notification when a quota window passes a usage level, and one when the current pace will use the window up before it resets. Each alert fires at most once per window, and none fires from demo data.

## 2. Scope

**In scope**
- A new Settings switch 「額度警示通知」, in the same section as 「免費重置通知」 and using the same permission flow.
- **Level alerts:** a window's used % crosses 80 % or 95 %. `[ASSUMPTION]` These are fixed levels with no picker; see Q1.
- **Pace alert:** `PaceEstimate.status` turns `.willRunOut` for a window, so it will run out before it resets.
- Checking every tier (window) of every pool of every configured provider after each refresh, in the same place `ResetAlerts.check` runs (`QuotaStore.refresh`).
- One alert per (provider, pool, tier, window, kind). The state of what was already sent is remembered across launches.
- Tapping an alert opens the app on the 額度 tab.
- Pure, unit-tested decision logic, with the same pattern as `ResetAlerts.increases`.

**Out of scope**
- Dollar budgets, Admin API keys, spend limits (candidate feature #2, a separate spec).
- Push notifications or any server-side check. iOS background refresh timing stays as it is.
- Quiet hours, snooze, and per-provider or per-window on/off. `[ASSUMPTION]` These can come in a later iteration.
- Alerts on the widget, Live Activities, or Lock Screen widgets.
- Changing the refresh floors (Claude Code 5 min; Codex and Cursor 1 min) or the 429 back-off.
- Google Antigravity (not supported on the phone).
- Changing how the existing free-reset notification behaves, apart from sharing the permission request.

## 3. User Stories

- **US-1.** As the owner, I want to be told when a quota window reaches 80 % and again at 95 %, so that I can slow down or switch tools before I am blocked.
- **US-2.** As the owner, I want to be told when my current pace will use up a window before it resets, so that I can act while I still have quota left.
- **US-3.** As the owner, I want each warning only once per window, so that alerts stay rare enough to read.
- **US-4.** As the owner, I want to turn these alerts on and off on their own, separately from free-reset alerts.

## 4. Functional Requirements

- **FR-A1.** Settings shows, directly below 「免費重置通知」 in the same section, a switch 「額度警示通知」, off by default, stored under the key `opentokenusage_quota_alerts`.
- **FR-A2.** Turning the switch on asks for notification permission (alert, sound, badge) if it has not been granted yet. It is never asked at launch.
- **FR-A3.** If permission is denied, the switch stays off and the footer shows 「通知已關閉，需要到 iOS「設定」開啟。」 with a 「開啟設定」 button (the same pattern as 免費重置通知).
- **FR-A4.** After every refresh that returns items, the app checks each tier of each pool of each provider in `result.items`.
- **FR-A5.** A **level alert** fires for a tier when its `used` is at or above a level (80 or 95) and that level has not already been alerted for this window.
- **FR-A6.** If one refresh finds a tier past both 80 and 95 for the first time, only the 95 alert is sent, and 80 is marked as sent too.
- **FR-A7.** A **pace alert** fires for a tier when `PaceEstimate(tier:now:).status == .willRunOut` and no pace alert has been sent for this window.
- **FR-A8.** `[ASSUMPTION]` No pace alert fires for a tier whose `windowIsEstimate == true` (Cursor without a cycle start), because the estimated window can make the run-out time wrong. Level alerts still fire.
- **FR-A9.** No pace alert fires for a tier that already got the 95 % level alert in this window. That would repeat the same news.
- **FR-A10.** A window is identified by `providerId | poolId | tierId | resetsAt`. A new `resetsAt` value means a new window, so its alerts can fire again.
- **FR-A10a.** A saved window of the same provider, pool and tier whose reset time is within 10 minutes of the new one counts as the same window. Codex can send only `reset_after_seconds`, so the phone works the reset time out from its clock and it drifts slightly between refreshes.
- **FR-A11.** Sent-alert state is saved in UserDefaults under `opentokenusage_quota_alerts_sent`. Entries whose `resetsAt` is in the past are removed on each check so the state does not grow.
- **FR-A12.** No alert is sent and no state is changed while 示範資料 (`SettingsKey.sampleData`) is on.
- **FR-A13.** No alert fires for a tier whose reset time has already passed (stale data carried over from an earlier refresh).
- **FR-A14.** Alert text:
  - Level alert: title 「\(provider) · \(pool) 已用 \(level)%」, body 「\(tier label)，\(reset in) 後重置。」
  - Pace alert: title 「\(provider) · \(pool) 照目前速度會用完」, body 「約 \(run-out in) 後用完，比重置早 \(gap)。」 The durations use the same `span` formatting as 用量分析.
- **FR-A15.** Notification identifiers are `quota-<kind>-<windowKey>`, so iOS also collapses duplicates. `threadIdentifier` is the `providerId`, so a provider's alerts are grouped together.
- **FR-A16.** Tapping a quota alert switches the app to the 額度 tab (`userInfo["open"] = "quotas"`), handled in `NotificationRouter` next to the existing `"resets"` route.
- **FR-A17.** The switch has no effect on 免費重置通知, and the free-reset switch has no effect on this one.

## 5. Acceptance Criteria

### FR-A1 / FR-A2 / FR-A3
- **Given** a fresh install **When** the owner opens Settings **Then** 「額度警示通知」 is shown and is off.
- **Given** notification permission was never asked **When** the owner turns the switch on **Then** iOS shows the permission prompt once.
- **Given** the owner denies the permission **When** the prompt closes **Then** the switch is off and the footer shows 「通知已關閉…」 with 「開啟設定」.
- **Given** permission was already granted for free-reset alerts **When** the owner turns this switch on **Then** no prompt appears and the switch stays on.

### FR-A4 / FR-A5 / FR-A6
- **Given** the switch is on, and Claude Code 5h is at 78 % **When** a refresh returns 81 % **Then** one notification 「Claude Code · … 已用 80%」 is delivered.
- **Given** the 80 % alert was already sent for this window **When** a later refresh returns 86 % **Then** no notification is delivered.
- **Given** a tier at 70 % **When** a refresh returns 97 % **Then** exactly one notification is delivered, for 95 %. A later refresh at 98 % delivers nothing.
- **Given** the switch is off **When** a tier crosses 80 % **Then** no notification is delivered and the sent state is not changed.

### FR-A7 / FR-A8 / FR-A9
- **Given** a tier with a known window, 40 % used at 20 % elapsed (projected 200 %) **When** a refresh runs **Then** one pace notification is delivered, with the run-out time.
- **Given** the pace alert was sent for this window **When** later refreshes still show `.willRunOut` **Then** no further pace notification is delivered.
- **Given** a Cursor tier with `windowIsEstimate == true` and status `.willRunOut` **When** a refresh runs **Then** no pace notification is delivered.
- **Given** the 95 % alert was sent for this window **When** the status becomes `.willRunOut` **Then** no pace notification is delivered.
- **Given** a tier at 3 % elapsed (status `.unknown(.tooEarly)`) **When** a refresh runs **Then** no pace notification is delivered.

### FR-A10 / FR-A11
- **Given** the 80 % alert was sent for the window that resets at 14:00 **When** a refresh after 14:00 returns a new `resetsAt` and 82 % **Then** a new 80 % alert is delivered.
- **Given** stored state includes windows whose `resetsAt` passed yesterday **When** a check runs **Then** those entries are gone from `opentokenusage_quota_alerts_sent`.
- **Given** the app is killed and relaunched **When** a refresh returns the same window, still above 80 % **Then** no alert is delivered.

### FR-A12 / FR-A13
- **Given** 示範資料 is on and the switch is on **When** a refresh shows sample tiers above 95 % **Then** no notification is delivered and the stored state is unchanged.
- **Given** a provider was skipped this refresh (floor or 429), so its old item is carried over with a `resetsAt` in the past **When** the check runs **Then** no alert is delivered for its tiers.

### FR-A14 / FR-A15 / FR-A16
- **Given** a level alert is delivered **When** the owner reads it **Then** the title names the provider, the pool and the level, and the body names the window and the time to reset.
- **Given** two Claude Code alerts and one Codex alert are delivered **When** the owner opens Notification Center **Then** they are grouped as two stacks, one per provider.
- **Given** the app is in the background **When** the owner taps a quota alert **Then** the app opens on the 額度 tab.
- **Given** the owner taps a free-reset alert **When** the app opens **Then** the resets sheet still opens as before (no regression).

### FR-A17
- **Given** both switches are on **When** the owner turns 額度警示通知 off **Then** 免費重置通知 is still on and still fires.

## 6. Edge Cases and Failure Modes

- **Case:** The vendor revises usage down within a window (e.g. 82 % → 76 %), and it later rises past 80 % again. **Behavior:** No second 80 % alert. State is per window, not per crossing.
- **Case:** A tier has no `resetsAt`. **Behavior:** Its window key uses the literal `none`. Level alerts fire once and are never cleared by expiry. `[ASSUMPTION]` That is acceptable because every current vendor sends a reset time; see Q4.
- **Case:** `used` is already ≥ 100 % (exhausted) the first time it is seen. **Behavior:** Only the 95 % alert is sent (FR-A6). No pace alert, because the status is `.exhausted`.
- **Case:** A refresh fails for every provider (`state = .failed`). **Behavior:** No check runs, because `result.items` is not produced.
- **Case:** Many windows cross at once (e.g. the first run after enabling, with several tiers already high). **Behavior:** One notification per tier. `[ASSUMPTION]` There is no extra summary notification; the provider threads keep it readable.
- **Case:** The switch is turned on while tiers are already past 80 %. **Behavior:** The next refresh alerts for them once. That is intended, so the owner learns the current state.
- **Case:** The owner revokes notification permission in iOS Settings while the switch is on. **Behavior:** `add` fails silently, and the state is still recorded as sent. Settings handles it the same way 免費重置通知 does today (`ResetAlerts.authorizationDenied()`). `[ASSUMPTION]` That check runs when Settings appears; VERIFY in `SettingsView` before implementation.
- **Case:** A provider is signed out. **Behavior:** It is not in `result.items`, so it is not checked. Its old state expires by `resetsAt`.
- **Case:** Clock change or time zone travel. **Behavior:** Window keys use the vendor's `resetsAt` string, not local time, so nothing re-fires.
- **Case:** Background refresh never runs (Low Power Mode, iOS chooses not to). **Behavior:** Alerts arrive at the next foreground refresh. The Settings footer says 「背景檢查的時間由 iOS 決定。」

## 7. Non-Functional Requirements

- **Performance.** The check is a pure function over at most 50 tiers and finishes in under 5 ms on device. It makes no network calls and adds no requests to any vendor.
- **Reliability.** Delivery depends on iOS background refresh. No promise of timeliness is made in the UI.
- **Security & privacy.** Notifications contain only the provider, pool and window names plus percentages and durations. No tokens, account e-mail or plan price. Nothing leaves the phone.
- **Compatibility.** iOS 27.1, iPhone and iPhone Duo (both screens). Saved snapshots that lack `windowSeconds` still decode (existing behavior), and their tiers get level alerts only.
- **Accessibility.** The switch and footer work with VoiceOver and Dynamic Type, like the existing 免費重置通知 row. The alert text is plain text with no symbols needed to understand it.
- **Internationalization.** Traditional Chinese strings, matching the rest of the app. Durations use the existing `span` helper.
- **Testability.** The decision logic is a pure static function, `QuotaAlerts.due(items:sent:now:) -> (alerts: [QuotaAlert], sent: [String: …])`, with unit tests in `OpenTokenUsageTests` covering every acceptance criterion above that does not need the UI.

## 8. Dependencies

- `PaceEstimate` in `Model/Quota.swift` (implemented). Its `.willRunOut` status and `runOutDate` drive FR-A7 and FR-A14.
- `QuotaStore.refresh` (`Data/QuotaStore.swift`), where the check is called next to `ResetAlerts.check`.
- `NotificationRouter` and the permission helpers in `Data/ResetAlerts.swift`. The permission request should be shared, not copied.
- `BackgroundRefresh` / `.backgroundTask(.appRefresh)` in `App/OpenTokenUsageApp.swift` (implemented). No change.
- `RootView` tab selection (`QuotaStore.Tab.quotas`) for FR-A16.

## 9. Risks and Mitigations

- **Risk:** Alert fatigue if the levels are too low for the owner's habits. **Mitigation:** Only two levels, once per window, and a single switch to turn it off. Q1 decides whether the levels can be changed.
- **Risk:** Background refresh is rare, so an alert arrives after the window is already used up. **Mitigation:** The Settings footer states the iOS limit. The foreground check still catches it.
- **Risk:** A wrong pace alert on short windows (5h) after a single burst. **Mitigation:** `PaceEstimate` already refuses below 5 % elapsed. The pace alert is skipped for estimated windows (FR-A8). Q2 asks whether to also require a minimum time before the projected run-out.
- **Risk:** Vendor endpoints change shape (none are public APIs). **Mitigation:** Alerts read only the already-parsed `QuotaTier`. A parsing break shows as no data, not as false alerts.
- **Risk (existing, VERIFY):** `ResetAlerts.check` is called even while 示範資料 is on, so a demo-data refresh can show a free-reset notification. **Mitigation:** FR-A12 guards the new check. Fixing the old one is out of scope here; raise it as a separate small fix.

## 10. Open Questions

- **Q1.** `[OPEN_QUESTION]` Fixed 80 % / 95 %, or a picker in Settings (e.g. 70 / 80 / 90 / 95, choose up to two)? Default: fixed.
- **Q2.** `[OPEN_QUESTION]` Should a pace alert also require the projected run-out to be at least X minutes before the reset (e.g. 30 min) to avoid near-miss alerts? Default: no extra rule.
- **Q3.** `[OPEN_QUESTION]` Should tapping an alert open that provider's detail instead of just the 額度 tab? Default: the 額度 tab only.
- **Q4.** Answered from the parsers (`Data/ProviderSources.swift`), 2026-11-19: all three treat the reset time as optional. Claude Code uses `resets_at` (may be null); Codex uses `reset_at`, else `reset_after_seconds` from the clock (hence FR-A10a); Cursor uses `billingCycleEnd`. A tier with no reset time gets level alerts once under the `none` key, as specified. Still `VERIFY` on device how often each one is actually missing.

## 11. Success Metrics

This is a single-owner app with no analytics, so measurement is by the owner's own observation.
- **Leading:** The switch stays on after one week. Fewer than 3 alerts per day on a typical working day, checked in Notification Center history.
- **Lagging:** Over one month, the owner reports no case of a tool refusing a request because of quota without an alert arriving first (counting only times the app had refreshed in the hour before).
