# Feature Spec: 用量分析 — "Will I run out?" pace charts

Status: implemented 2026-11-18 (owner approved) · supersedes the donut part of FR-35 in `spec-v3-native-duo.md`.

## 1. Summary

Today the 用量分析 tab shows a trend line of daily % use, a bar chart of the latest period, and a donut per pool of current remaining %. None of them says whether the owner will hit a limit before it resets: the trend mixes different units on one axis, the bars compare pools whose % mean different things, and the donuts repeat the 額度 page. The owner (single user of the app on iPhone / iPhone Duo) wants the tab to answer "will I run out before reset?" for every quota window. Success: opening the tab shows, per window, how far into the window we are, how much is used, where the current pace lands at reset, and — if it runs out first — roughly when.

## 2. Scope

**In scope**
- A new 「會不會用完」 (pace) section at the top of 用量分析, one row per quota window (tier) of every configured provider.
- Pace math computed on the phone from the latest readings: time elapsed in window, used %, projected % at reset, estimated run-out time.
- Storing each tier's window length so elapsed time can be computed.
- Replacing the 目前額度（環圈圖） donut section with the pace section.
- Unit tests for the pace math.

**Out of scope**
- Weekday × hour usage heatmap. `[ASSUMPTION]` possible later iteration.
- Per-pool small-multiple burn-rate charts.
- Changing the 用量趨勢 line chart or the 橫條圖 (see Open Questions).
- Notifications / alerts based on projected run-out (ResetAlerts stays as is).
- Widget changes.
- Any server, Worker, or web (`src/`) change. Phone-only, as decided for FR-34.
- Exact token counts (vendors do not give them to the phone; FR-34 note still holds).

## 3. User Stories

- As the owner, I want to see for each quota window whether my current pace will use it up before it resets, so that I can slow down or switch model/provider in time.
- As the owner, I want an estimated run-out time when the pace is too fast, so that I know how much working time I have left.

## 4. Functional Requirements

- **FR-P1.** Each `QuotaTier` carries an optional window length in seconds (`windowSeconds`). Sources:
  - Claude `five_hour` → 18 000 s; `seven_day*` → 604 800 s.
  - Codex `limit_window_seconds` from the response.
  - Cursor: `billingCycleEnd − billingCycleStart` when the response has `billingCycleStart`. `[OPEN_QUESTION]` Whether Cursor's usage response includes a start date; if not, `[ASSUMPTION]` one calendar month before `billingCycleEnd`.
  - Sample data sets matching values.
- **FR-P2.** For a tier with a reset date and window length, the app computes `elapsed% = (now − (reset − window)) / window × 100`, clamped to 0…100.
- **FR-P3.** The app computes `projected% = used% / elapsed% × 100` (straight-line pace since window start) when elapsed% ≥ 5.
- **FR-P4.** When projected% > 100 and used% < 100, the app computes run-out time `= windowStart + window × (100 / projected%)` and shows it as relative time (e.g. 「約 1 天 3 小時後用完」) plus how long before the reset that is.
- **FR-P5.** Each tier is classified:
  - 已用完 — used ≥ 100.
  - 會用完 — projected > 100.
  - 偏快 — projected 85…100.
  - 正常 — projected < 85.
  - 無法估算 — see Edge Cases.
- **FR-P6.** The pace section shows one row per tier, grouped by provider then pool, in the same fixed provider order as the 額度 page (Claude Code, Codex, Cursor). Rows are not sorted by status.
- **FR-P7.** (revised 2026-11-19: same direction as the 額度 page, where a long bar is good) Each row draws a horizontal bullet bar 0–100 %:
  - a filled bar for remaining % (100 − used);
  - a vertical marker at time left % (100 − elapsed); a bar shorter than the marker means use is ahead of time;
  - a dashed line from remaining % back to what the current pace leaves at the reset (100 − projected), stopping at 0.
- **FR-P8.** (revised 2026-11-19) Rows are grouped in one section per provider, headed 「會不會用完 · <provider>」. Each row shows text next to the bar:
  - pool · window label (e.g. 「Opus · 每週」), or the window label alone when the provider has one pool;
  - status word;
  - 「剩餘 X% · 時間剩 Y% · 重置時約剩 Z%」 (「重置前會用完」 when the projection passes 100 %);
  - reset countdown;
  - the run-out sentence from FR-P4 when it applies.
- **FR-P9.** The donut section (目前額度（環圈圖）) is removed from 用量分析.
- **FR-P10.** The pace section appears even when usage history is empty, because it needs only current readings.

## 5. Acceptance Criteria

### FR-P1
- **Given** a Codex response with `limit_window_seconds = 604800` **When** it is parsed **Then** that tier's `windowSeconds` is 604800.
- **Given** a cached snapshot saved by the current version (no `windowSeconds`) **When** the app starts **Then** it decodes without error, and those tiers show 無法估算 until the next refresh.

### FR-P2 / FR-P3
- **Given** a weekly tier resetting in 3.5 days with 40 % used **When** pace is computed **Then** elapsed is 50 % and projected is 80 % (status 正常).
- **Given** a 5-hour tier that reset 10 minutes ago (elapsed ≈ 3 %) **When** pace is computed **Then** no projection is shown and the row says 「剛重置，資料不足」.

### FR-P4
- **Given** a weekly tier resetting in 3.5 days with 70 % used (projected 140 %) **When** the row renders **Then** it says it will run out about 1 day 12 hours from now, about 2 days before reset.
- **Given** projected ≤ 100 % **When** the row renders **Then** no run-out sentence appears.

### FR-P5
- **Given** used = 100 % **When** the row renders **Then** the status is 已用完 and the row shows the reset countdown and no projection.
- **Given** projected = 90 % **When** the row renders **Then** the status is 偏快.

### FR-P6 / FR-P7 / FR-P8
- **Given** Claude Code (5 小時, 每週, Opus 每週, Sonnet 每週), Codex (5 小時, 每週) and Cursor (Auto, API) are configured **When** 用量分析 opens **Then** eight rows appear: Claude Code's four first, then Codex, then Cursor.
- **Given** a row with used 40 % and elapsed 50 % **When** it renders **Then** the used bar ends left of the elapsed marker.
- **Given** VoiceOver is on **When** a row is focused **Then** it reads the same facts as the visible text in one sentence (e.g. 「Claude Code 每週，已用 70%，時間已過 50%，照目前速度約 1 天 12 小時後用完，比重置早 2 天」).

### FR-P9 / FR-P10
- **Given** the new version **When** 用量分析 opens **Then** no donut section is present.
- **Given** a fresh install with readings but no history **When** 用量分析 opens **Then** the pace section shows rows and the history empty-state still appears for the trend part.

## 6. Edge Cases and Failure Modes

- **Case:** Tier has no reset date. **Behavior:** row shows used % only, status 無法估算, text 「沒有重置時間」.
- **Case:** Window length unknown (old snapshot or unknown vendor key). **Behavior:** same as above with 「不知道週期長度」; fixed after the next refresh where the source provides it.
- **Case:** Elapsed < 5 %. **Behavior:** no projection, 「剛重置，資料不足」.
- **Case:** Used = 0. **Behavior:** status 正常, 「尚未使用」, no projection.
- **Case:** Reset date is in the past (stale data, offline). **Behavior:** row is dimmed with 「資料已過期，請更新」, no projection.
- **Case:** Provider fetch failed this refresh and the previous reading is kept. **Behavior:** pace uses the kept reading. The row shows the 額度 page's existing "updated N ago" time if the reading is older than 1 hour. `[ASSUMPTION]`
- **Case:** Used > 100 (vendor overage). **Behavior:** clamp to 100, status 已用完.
- **Case:** Provider not configured. **Behavior:** no rows for it. The 額度 page's 未設定 section is the place to set it up.
- **Case:** Sample-data mode on. **Behavior:** rows use sample tiers with sample window lengths.

## 7. Non-Functional Requirements

- **Performance.** Pace computed on the main actor from at most ~20 tiers. No network. Section renders within one frame of tab open (no visible delay on iPhone 17-class simulator).
- **Accessibility.**
  - Status is never colour-only: a status word is always present.
  - Each row is one VoiceOver element (FR-P6 criterion).
  - Text supports Dynamic Type up to AX3 without truncating the status word.
  - Contrast meets WCAG 2.1 AA.
- **Compatibility.**
  - Works on iPhone Duo outer screen (~466 pt wide) and inner screen (~951 pt wide), light and dark mode.
  - On the inner screen, rows may lay out in two columns. `[ASSUMPTION]`
- **Internationalization.** UI strings in Traditional Chinese like the rest of the app. Relative times use the system formatter (consistent with 「2 days, 11 hr後重置」 on the 額度 page).
- **Privacy.** No new data leaves the phone. `windowSeconds` is stored in the same local cache as the snapshot.

## 8. Dependencies

- Vendor responses already fetched in `ProviderSources.swift`. No new endpoints.
- Cursor `billingCycleStart` availability (Open Question 1).
- `QuotaTier` is a `Codable` cache schema. Adding an optional field must decode old caches and old widget snapshots (`QuotaWidget.swift` reads the same model).

## 9. Risks and Mitigations

- **Risk:** Straight-line pace overstates run-out after one heavy burst early in a window. **Mitigation:** label it 「照目前速度」. Show elapsed/used side by side so the owner can judge. A recent-rate variant can be a later iteration.
- **Risk:** Wrong window length (e.g. Cursor month guess) gives a wrong elapsed %. **Mitigation:** prefer vendor-provided start or length. Mark guessed lengths with 「（估計週期）」 in the row. `[ASSUMPTION]`
- **Risk:** Removing donuts loses a quick visual the owner likes. **Mitigation:** the bullet bar shows the same used % plus pace. Owner confirms at review.

## 10. Open Questions

1. Does Cursor's usage response include `billingCycleStart`? Not yet confirmed against a live response. Implemented both ways: the start date is used when present; otherwise the cycle is assumed to be one month, and the row is marked 「（估計週期）」.
2. Keep, change or remove the 用量趨勢 line and the 橫條圖? Both stay unchanged in this iteration. Owner decides after seeing the pace section.
3. Show every tier (8 rows today) or only the governing/tightest tier per pool? Default: every tier, because the 5-hour and weekly windows run out independently.
4. Thresholds for 偏快 (85 %) and the "too early" cut-off (5 %) are defaults. Owner may tune them.

## 11. Success Metrics

- **Leading:** the owner opens 用量分析 and can say, for each window, "on pace" or "runs out ~X before reset" without opening the 額度 detail view. Checked at review on iPhone Duo.
- **Lagging:** fewer surprise 已耗盡 states. Over the next month, a window hitting 0 % without first showing 會用完 or 偏快 in the pace section should be rare. Measured informally by the owner.

## Test plan (for the implementer)

- Unit tests (`OpenTokenUsageTests`) for a pure `PaceEstimate` function covering every FR-P2…FR-P5 criterion and each edge case above, with fixed `now`.
- Decode test: a cached `ProviderQuota` JSON without `windowSeconds` still decodes.
- Visual check on iPhone Duo simulator, outer and inner screen, light and dark, with sample data on.
