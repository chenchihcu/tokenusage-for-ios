# Feature Spec: Token 用量 for Codex and Cursor (phone only)

Status: **Implemented 2026-11-28 in iOS v3.2.0 (6)** · 2026-11-28 (dual-endpoint Cursor parser, list & detail UI, unified non-token wording across Claude Code/Codex/Antigravity, non-PII failure diagnostics, temporary `CursorTokenProbeView` removed)
Tags: untagged = stated by the owner or verified; `[ASSUMPTION]` = author default, confirm yes/no; `[OPEN_QUESTION]` = must be answered before the affected step; `VERIFY` = check on a real device.

## 1. Summary

**Problem.** The app shows quota percentages only. The owner also wants to see how many tokens Codex and Cursor have used, in the same simple way on every screen that shows these services.
**Actor.** The owner, the only user, on iPhone / iPhone Duo. Data comes from the phone's own refresh over Wi-Fi or cellular.
**Decision (owner, 2026-11-25).** All data is fetched by the phone over the internet. **Nothing goes through the Mac** (no CodexBar, no relay, no Worker).
**Success condition.** On the 額度 list and in each service's detail, Cursor shows tokens used this billing cycle, split by type and model, from Cursor's own figures. Codex shows the same block if OpenAI reports tokens to the phone. Otherwise it says plainly that the service doesn't provide them. No number is invented.

## 2. Scope

**In scope**
- One shared **Token block**, the same layout for every service that reports tokens:
  - **Row line** on the 額度 list, under the reset time: 「本期 12.3M tokens · ≈ $4.10」.
  - **「Token 用量」 section** in the service's detail screen: total, four types (輸入 / 快取寫入 / 快取讀取 / 輸出), one row per model, the period, and the data time.
- **Cursor tokens** from Cursor's dashboard data with the session already stored on the phone, for the current billing cycle.
- **Codex tokens** only if a phone-reachable OpenAI source reports them (step P0). Otherwise the Codex detail says 「Token：服務未提供」.
- Token figures are saved with the cached quota, so the app shows the last figures offline.
- 示範資料 includes sample token figures for both services.

**Out of scope**
- Anything through the Mac: CodexBar `cost`, local Codex CLI logs, the relay script or the Worker. This was the owner's decision.
- Claude Code tokens. `[ASSUMPTION]` Its OAuth usage endpoint reports only percentages; adding it later reuses the same block.
- Google Antigravity tokens.
- Widgets, Lock Screen widgets, Live Activity, Siri / App Intents, alerts.
- Token history charts in 分析, CSV export, per-project or per-session breakdowns, and choosing a date range.
- Turning tokens into percentages or into the quota bar.

## 3. User Stories

- **US-1.** As the owner, I want to see Cursor's tokens used this billing cycle on the 額度 list, so that I know my real usage at a glance.
- **US-2.** As the owner, I want a breakdown by type and model in Cursor's detail, so that I can see where the tokens went.
- **US-3.** As the owner, I want Codex to show tokens the same way when OpenAI provides them, and to say so clearly when it doesn't, so that I am never shown made-up numbers.

## 4. Functional Requirements

**Shared block**
- **TR-1.** A service with token data shows one extra line on its 額度 row: 「本期 <total> tokens」, followed by 「 · ≈ $<cost>」 when a cost is known.
- **TR-2.** Its detail screen shows a section 「Token 用量」 with:
  - the period, e.g. 「11/3 – 12/3」;
  - the total;
  - the four types 輸入, 快取寫入, 快取讀取, 輸出 (a type the service doesn't report is left out, not shown as 0);
  - one row per model (name, tokens, ≈ $), largest first;
  - 「資料時間 <time>」.
- **TR-3.** Token counts use the app's existing short format (`1.2K`, `3.4M`, `1.1B`), the same as the 模型與費用 price matrix.
- **TR-4.** Cost is shown with 「≈」 and the footer 「依服務回報的 API 價格估算，不是帳單金額。」.
- **TR-5.** A service that does not report tokens shows no row line. Its detail shows the 「Token 用量」 section with the single text 「Token：服務未提供」.
- **TR-6.** If fetching tokens fails, the quota figures on the same row still show as normal. The token block keeps the last saved figures, labelled with their data time.
- **TR-7.** Token figures are stored with each provider's cached quota and survive a relaunch.
- **TR-8.** With 示範資料 on, Cursor and Codex show sample token figures and make no network request.

**Cursor**
- **TR-C1.** After a successful Cursor quota refresh, the phone asks Cursor's dashboard for the usage of the current billing cycle (`billingCycleStart` … `billingCycleEnd` from `usage-summary`). It uses the same cookie and needs no extra sign-in.
- **TR-C2.** Source: `POST https://cursor.com/api/dashboard/get-filtered-usage-events` (the endpoint CodexBar uses for Cursor token cost), summed per model on the phone. `[ASSUMPTION]` Each event carries `inputTokens`, `outputTokens`, `cacheWriteTokens`, `cacheReadTokens` and `totalCents`; `get-aggregated-usage-events` is used instead if it returns the same per model in one call. Not a public API. The response shape is confirmed by step P1 (§12).
- **TR-C3.** The token request follows Cursor's existing refresh floor (1 min) and 429 back-off. It never runs more often than the quota request.
- **TR-C4.** If `billingCycleStart` is missing, the period is the 30 days up to now and the label says 「最近 30 天」.

**Codex**
- **TR-X1.** Step P0 checks, on a real phone signed in to Codex, whether any chatgpt.com endpoint reachable with the stored token returns token counts. The Codex usage page's "usage breakdown" is the first candidate.
- **TR-X2.** If P0 finds one, Codex uses the shared block (TR-1…TR-7) for that endpoint's period. If not, Codex shows TR-5 (「Token：服務未提供」) and this spec is done for Codex.
- **TR-X3.** Codex never derives tokens from percentages, credits or prices.

## 5. Acceptance Criteria

### TR-1 / TR-3 / TR-4
- **Given** Cursor reports 12,345,678 tokens and 410 cents this cycle **When** the 額度 list shows **Then** the Cursor row reads 「本期 12.3M tokens · ≈ $4.10」.
- **Given** Cursor reports tokens but no cents **When** the list shows **Then** the row reads 「本期 12.3M tokens」 with no cost.

### TR-2
- **Given** two Cursor models with 9M and 3M tokens **When** the owner opens Cursor's detail **Then** 「Token 用量」 lists both models, 9M first, under the period and the four type totals.
- **Given** Cursor reports no cache-write tokens **When** the detail shows **Then** 快取寫入 is not listed.

### TR-5
- **Given** P0 found no Codex token source **When** the owner opens Codex's detail **Then** 「Token 用量」 shows only 「Token：服務未提供」.
- **Given** the same **When** the 額度 list shows **Then** the Codex row has no token line.

### TR-6
- **Given** the quota request succeeds and the token request fails (e.g. 500) **When** the refresh ends **Then** the Cursor percentage updates and the token line shows the previous figures with their older data time.
- **Given** no token figures were ever saved **When** the token request fails **Then** no token line shows on the row.

### TR-7 / TR-8
- **Given** Cursor token figures were saved **When** the app relaunches offline **Then** the row shows the same token line.
- **Given** 示範資料 is on **When** the list shows **Then** both Cursor and Codex show sample token lines, and no request reaches cursor.com or chatgpt.com.

### TR-C1 / TR-C3 / TR-C4
- **Given** a Cursor cycle of 11/3 – 12/3 **When** tokens are fetched **Then** the request covers exactly that range and the detail shows 「11/3 – 12/3」.
- **Given** Cursor answered 429 **When** the next refresh comes before the back-off ends **Then** neither the quota nor the token request is sent.
- **Given** `billingCycleStart` is missing **When** tokens are fetched **Then** the period label reads 「最近 30 天」.

### TR-X1 / TR-X3
- **Given** P0 is not done **When** the feature ships **Then** Codex shows 「Token：服務未提供」, never a number.

## 6. Edge Cases and Failure Modes

- **Case:** Cursor's dashboard answers 401 while `usage-summary` works. **Behavior:** The token block keeps its last figures. The app does not sign out or show a sign-in error, because the quota still works.
- **Case:** The response has an unknown or missing model name. **Behavior:** That row is labelled 「其他」.
- **Case:** 0 tokens this cycle. **Behavior:** The row shows 「本期 0 tokens」. The detail shows the total 0 and no model rows.
- **Case:** Very large totals (≥ 1 billion). **Behavior:** Shown as `1.1B`; no overflow (values stored as 64-bit integers).
- **Case:** A new billing cycle starts. **Behavior:** The next fetch uses the new range. The old cycle's figures are replaced, not added.
- **Case:** A team Cursor account. **Behavior:** `[OPEN_QUESTION]` Q2 decides whether to show team or personal totals. The default is personal.
- **Case:** A narrow outer screen with large Dynamic Type. **Behavior:** The row line wraps to a second line and is never cut off.

## 7. Non-Functional Requirements

- **Network.** At most one extra request per Cursor refresh, with the 15 s timeout used by the other requests. No extra request for Codex unless P0 finds a source.
- **Privacy.** Only the phone talks to cursor.com and chatgpt.com, with the credentials already in the Keychain. Nothing is sent to the Mac, the Worker or any other server.
- **Compatibility.** iOS 27.1, iPhone and iPhone Duo (both screens). Cached quotas saved before this change still load; they just have no token block.
- **Accessibility.** VoiceOver reads the row line as 「本期一千兩百三十萬 tokens，約 4.10 美元」 (full numbers, not 「M」), with Dynamic Type up to AX5.
- **Testability.** Response parsing and the formatting of the row line are pure functions, unit-tested with saved sample responses.

## 8. Dependencies

- The Cursor session cookie and the refresh/back-off logic in `Data/ProviderSources.swift` and `Data/QuotaStore.swift` (implemented).
- `billingCycleStart` / `billingCycleEnd` from Cursor's `usage-summary` (already parsed).
- The short token format used by the 模型與費用 price matrix (implemented).
- **Not ready:** a confirmed Cursor dashboard endpoint (TR-C2) and any Codex token source (TR-X1). Both need P0 on a signed-in phone.

## 9. Risks and Mitigations

- **Risk:** The Cursor dashboard endpoint is undocumented and may change. The signed-in dashboard page already redirects to grok.com (§12). **Mitigation:** A failure only hides the token block (TR-6); quotas are unaffected. P1 confirms the response before any UI work.
- **Risk:** OpenAI gives the phone no token counts, so Codex shows nothing. **Mitigation:** This is stated up front (TR-5, TR-X2). Codex token counts exist only in the computer's local Codex CLI logs. Using those means going through the Mac, which the owner ruled out; it stays possible as a later choice.
- **Risk:** Cost figures look like a bill. **Mitigation:** 「≈」 and the footer (TR-4).

## 10. Open Questions

- **Q1.** Answered by P0: no. Codex shows 「Token：服務未提供」 (§12).
- **Q2.** `[OPEN_QUESTION]` Cursor team accounts: personal or team totals? Default: personal.
- **Q3.** `[ASSUMPTION]` Show tokens only on the 額度 row and in the detail screen, not on widgets. Confirm yes/no.

## 11. Success Metrics

- **Leading:** After a week, the owner can read Cursor's cycle tokens from the 額度 list without opening another app.
- **Lagging:** Cursor's token total in the app matches cursor.com's dashboard for the same cycle to within 1 %, checked once per cycle.

## 12. P0 results (2026-11-25)

**Codex: no token source the phone can reach.**
- `GET chatgpt.com/backend-api/wham/usage` (what the phone already calls) returns only the 5 h and weekly windows (`usedPercent`, `resetsAt`), credits and reset credits. No token counts (checked through CodexBar 0.85's OAuth reading on the owner's Mac).
- The other chatgpt.com addresses CodexBar knows (`/wham/rate-limit-reset-credits`, `/accounts`, `/me`, `/subscriptions`, `/settings/usage`, `/codex/cloud/settings/analytics`) cover plan, credits and limits. The web "usage breakdown" is **credits used per day per service**, read from a chart, not tokens.
- CodexBar's Codex token figures (`codexbar cost --provider codex`, `source: local`) come only from the computer's Codex CLI logs, which the owner ruled out.
- **Result:** TR-X2 applies, so Codex shows 「Token：服務未提供」. No Codex token request is added.

**Cursor: source identified; response shape still to confirm.**
- The session works for `GET cursor.com/api/usage-summary` (billing cycle 2026-11-01 → 2026-12-01; plan keys `used`, `limit`, `remaining`, `breakdown`, `autoPercentUsed`, `apiPercentUsed`, `totalPercentUsed`; no token counts).
- CodexBar reads Cursor tokens from `/api/dashboard/get-filtered-usage-events` (also seen: `/api/dashboard/v2/usage-status`, `/api/dashboard/get-sand-usage-status`).
- The POST response could not be read in this check: the app's browser pane blocks scripted requests, and CodexBar has no Cursor session on the Mac.
- **Observed:** opening `cursor.com/dashboard/usage` while signed in now moves the browser to `grok.com/dashboard/usage` (HTTP 403 challenge page). The JSON API on cursor.com still answers. This raises the risk that the dashboard API moves (§9).

**P1 (first implementation step).** In the simulator, which already has a Cursor session, call `get-filtered-usage-events` for the current cycle, save one response as a test fixture (with personal fields removed), and confirm the token fields. If they are missing or the call fails, stop and report before building the UI.
