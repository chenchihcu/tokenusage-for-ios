# Plan v3.2 — Device check of v3.1, then intraday history, display options and CSV export

Status: **Draft — waiting for owner approval** · Date: 2026-11-19 · Baseline: `main` @ `274eb9a` (v3.1.0, PR #9)
Source: `docs/spec-competitive-gap-v3.1.md` §A.4, tranche **P3**. P4 items stay separate specs (see §6).
Tags: `[ASSUMPTION]` = author default, confirm yes/no; `[OPEN_QUESTION]` = owner decides before that step starts; `[VERIFY]` = check on device.

## 0. Why this next

| Option | Value to the owner | Cost / risk | Call |
|---|---|---|---|
| **Check v3.1 on the phone** | v3.1 shipped with Lock Screen widgets, the Control Center control, Siri phrases and free-Apple-ID install **unverified** | Small; needs the owner's phone | **Do first (Step 0)** |
| **P3: intraday history, 14-day range, display options, CSV** | Closes the last gaps against the competitor that need no new data source | Medium; one history format change, no new endpoints, no new credentials | **v3.2** |
| P4: GitHub Copilot, Google Antigravity on phone, Anthropic/OpenAI Admin API cost, multi-account | New providers or a different product | New undocumented endpoints or new credentials, each its own risk | Separate specs after v3.2 |

## 1. Decisions and assumptions

- D1. v3.2 = Step 0 (device check and fixes) + P3. No new providers, no server, no paid Apple account.
- D2. Same delivery rules as v3.1: work on `work/*`, one PR per step, local `xcodebuild test` + CI (`build-ios.yml`, `ios-simulator-screenshots.yml`) green before merge.
- A1. `[ASSUMPTION]` Hourly history kept **30 days** (≈ 24 × 30 × ~6 pools ≈ 4,300 rows); daily history keeps its 400 days.
- A2. `[ASSUMPTION]` The display options (used vs remaining, relative vs exact reset) apply to the app **and** the widgets. A running Live Activity keeps the format it started with; the next one follows the setting.
- A3. `[ASSUMPTION]` CSV export is **disabled while 示範資料 is on**: demo numbers must never leave the phone looking like real ones.
- A4. `[ASSUMPTION]` CSV is UTF-8 **with BOM** (so Excel on Windows opens 繁中 names correctly), comma-separated, English column headers so other tools can read it.

## 2. Steps

### Step 0 — Verify v3.1 on the real phone (owner + Claude), fix what fails
Install the `main` IPA from `build-ios.yml` with the free Apple ID, then run this checklist. Each failure becomes a small fix PR before Step 1.

| # | Check | Pass when | Covers |
|---|---|---|---|
| 0.1 | Free-Apple-ID install with the widget extension (Live Activity, Control, Lock widgets inside it) | App and widget install; no "App ID limit" or entitlement error | v3.1 §9 risk |
| 0.2 | Add a rectangular Lock Screen widget, set to 「最緊的窗口」 | Shows the tightest window, % and reset; tap opens 額度 | FR-8…FR-12 |
| 0.3 | Configure a Lock widget for a signed-out provider | Shows 「未登入」; tap opens 設定 | FR-13 |
| 0.4 | Add the Control Center control 「追蹤下次重置」, tap while locked | Live Activity starts without opening the app | FR-23, FR-24 |
| 0.5 | Siri: 「用 OpenTokenUsage 查額度」 | One line per signed-in provider, no network wait | FR-25, FR-26 |
| 0.6 | Leave a Live Activity running across a reset | Shows 「已重置」, gone within ~15 min after the next refresh | FR-20 |
| 0.7 | Turn on 用完與重置 + 勿擾時段 23:00–08:00; check pending notifications next morning | Nothing between 23:00 and 08:00; held alerts arrive at 08:00 or are dropped if untrue | FR-30, FR-34, FR-35 |
| 0.8 | One provider signed out on purpose | Only its row shows 「需要重新登入」; the others update normally | FR-1…FR-5 |

Known gap to fix in Step 0 regardless: the detail page reads `ResetActivity.trackedRef` only on appear, so if iOS ends the activity while the page is open the button still says 「停止追蹤」. Fix: refresh `trackedRef` on `scenePhase == .active` and after every store refresh.

### Step 1 — Hourly history (data, no UI) · PR 1
- **P3-1.** `UsageHistory` gains `hours: [UsageHour]` (`hour` = start of local hour, `key`, `providerName`, `poolName`, `consumed`), filled by the same `record(_:)` call that fills `days`, using the same rise/reset rule.
- **P3-2.** Hours older than 30 days are dropped on every `record`.
- **P3-3.** Backward compatible: a v3.1 `usage-history-v1.json` (no `hours` key) decodes with `hours = []` and keeps all `days`. Needs an explicit `init(from:)` with `decodeIfPresent`; Swift's synthesized `Decodable` does not use property defaults for missing keys.
- **P3-4.** `totals(byHourFor range: ClosedRange<Date>)` returns per-pool hourly sums for charts.
- Tests: legacy JSON fixture decodes unchanged; rise/reset across an hour boundary; 30-day pruning; DST change hour (Asia/Taipei has none, but test with a calendar that does).
- Files: `Data/UsageHistory.swift`, `OpenTokenUsageTests/AnalyticsCatalogTests.swift` (or a new `UsageHistoryTests.swift`).

### Step 2 — 用量分析 ranges: 24 小時 / 7 天 / 14 天 / 30 天 / 每週 / 每月 · PR 2
- **P3-5.** The 期間 picker becomes a range picker with those six options. Default 7 天. `[ASSUMPTION]` it replaces the current 每日/每週/每月 picker; 每日 ≈ the new 7/14/30 天.
- **P3-6.** 24 小時 draws hourly bars from `hours`; 7/14/30 天 draw daily points from `days` limited to that many days; 每週/每月 keep today's aggregation.
- **P3-7.** With no data in the range the chart area shows 「這段期間沒有用量紀錄」, never an empty axis.
- **P3-8.** VoiceOver label states range and per-series total, as today's charts do.
- **P3-9.** The chosen range is remembered (`@AppStorage`).
- Check: both iPhone Duo screens in `ios-simulator-screenshots.yml`; Dynamic Type at AX sizes does not clip the segmented picker (fall back to a menu picker at accessibility sizes).
- Files: `Views/AnalyticsView.swift`, `Data/UsageHistory.swift` (range enum), `Shared/SampleQuotas.swift` / `SampleData.history()` (add sample hours).

### Step 3 — Display options: used vs remaining, relative vs exact reset · PR 3
- **P3-10.** Settings › 顯示: 「百分比」 = 剩餘 (default) / 已用; 「重置時間」 = 倒數 (default) / 確切時間.
- **P3-11.** Stored in the App Group defaults (`UserDefaults(suiteName: QuotaCache.appGroup)`) so widgets read the same choice; widgets reload when it changes.
- **P3-12.** One formatter, `Shared/QuotaFormat.swift`: `percentText(remaining:)` and `resetText(_:)`. Every place that prints a % or reset goes through it: `QuotaRow`, `PoolSummary`, `SummaryHeader`, `TierRow`, `ResetText`, `QuotaWidgetContent`, `LockQuotaView`, Live Activity views, Siri answer.
- **P3-13.** Wording: remaining 「剩餘 42%」; used 「已用 58%」. Reset relative 「2 小時 10 分後重置」; exact 「今天 14:30 重置」 / 「11月21日 09:00 重置」.
- **P3-14.** Colour and level (偏低 / 已耗盡) still follow **remaining**, whatever is displayed, so red always means "little left".
- **P3-15.** VoiceOver always says both: 「已用 58%，剩餘 42%」, so the option never hides meaning.
- Tests: formatter unit tests for both modes, boundaries (0 %, 100 %, reset today / tomorrow / past); `WidgetAlignmentTests` re-run in both modes.
- Risk: many call sites. Mitigation: land `QuotaFormat` with remaining/relative only first (no behaviour change, tests prove identical strings), then add the options.

### Step 4 — CSV export · PR 4
- **P3-16.** 用量分析 toolbar gets 「匯出 CSV」 (`ShareLink` with a `Transferable` file), offering 每日 (all kept days) and 每小時 (last 30 days).
- **P3-17.** Columns — daily: `date,provider,pool,used_pct_points`; hourly: `hour,provider,pool,used_pct_points`. Dates ISO 8601 with offset. File name `opentokenusage-daily-2026-11-19.csv`.
- **P3-18.** Quoting per RFC 4180 (pool names with commas or quotes are escaped).
- **P3-19.** Disabled with 「示範資料開啟時無法匯出」 while 示範資料 is on (A3). Empty history → disabled with 「還沒有用量紀錄」.
- **P3-20.** Export happens on the phone only; the file goes wherever the owner shares it (Files, AirDrop, mail). No network.
- Tests: CSV builder unit tests (escaping, BOM, empty, ordering); export of 400 days × 6 pools finishes in < 200 ms on simulator.
- Files: new `Data/UsageExport.swift`, `Views/AnalyticsView.swift`.

### Step 5 — Release v3.2.0 · PR 5 (or folded into PR 4)
Follows the release alignment rule (owner, 2026-11-19; see `ios-native/README.md` › Release checklist):
- `MARKETING_VERSION` 3.2.0 **and** `CURRENT_PROJECT_VERSION` +1 in `project.yml` (the only place versions are set).
- Settings alignment: every setting added in Steps 2–4 (range picker memory, 顯示 options, export) is reflected in the in-app 設定 and, where it belongs there, in `Settings.bundle/Root.plist`; footers re-read for anything no longer true.
- `SettingsAlignmentTests` green; Settings › 版本 and iOS Settings › OpenTokenUsage › 版本 both read 3.2.0 (3).
- `ios-native/README.md` usage section, spec status lines, screenshot workflow on both Duo screens.

## 3. Order and dependencies

```
Step 0 (device check + fixes) ──► Step 1 (hourly data) ──► Step 2 (ranges UI)
                                         │
Step 3 (display options) ── independent ─┤
                                         └──► Step 4 (CSV; needs Step 1 for hourly rows) ──► Step 5
```
Steps 2 and 3 touch different files and can run in parallel sessions; Step 4 waits for Step 1.

## 4. Acceptance for v3.2 (summary; each PR carries its own Given/When/Then tests)
- Given a v3.1 history file, when v3.2 first launches, then every past day still shows and 24 小時 starts filling from the next refresh.
- Given 已用 is chosen, when the 額度 list, a widget and Siri report Claude Code 5 小時 at 58 % used, then each says 「已用 58%」 and the bar is still coloured by 42 % remaining.
- Given 確切時間 is chosen, when a reset is today 14:30, then rows show 「今天 14:30 重置」.
- Given 30 days of history, when 匯出 CSV › 每日 is shared to Files, then the file opens in Numbers/Excel with readable 繁中 pool names and one row per pool per day.
- Given 示範資料 is on, when the owner opens 用量分析, then 匯出 CSV is disabled with its reason.

## 5. Risks
- **History format change** could lose data → explicit decoder, legacy fixture test, and write to the same file only after a successful decode.
- **Display option drift** (one view forgets the setting) → single `QuotaFormat`, grep gate in review for raw `remainingPercent` string interpolation in views.
- **Widget reload budget** when toggling display options → reload only on change, not on every app launch.
- **CI minutes** (free plan, macOS 10× multiplier) → simulator-screenshot job only on PRs touching `ios-native/**`, as today.

## 6. After v3.2 — P4 candidates (each needs its own spec)
| Candidate | Why | Main risk |
|---|---|---|
| Google Antigravity on the phone | Already one of the owner's four tools; today shows 「暫不支援手機登入」 | Undocumented sign-in and usage endpoints |
| GitHub Copilot quota | Competitor A has it | Needs a GitHub token on the phone; endpoint stability |
| Anthropic / OpenAI Admin API spend (competitor B's product) | Dollar view alongside quota | Admin keys are powerful; must be read-only and Keychain-only |
| Multiple accounts per provider | Personal + work accounts | Touches every store, cache key and widget entity |

## 7. Open questions
- `[OPEN_QUESTION]` Q1. Which P4 item comes after v3.2? Default recommendation: **Google Antigravity**, because it is the one tool the owner already uses that the phone still cannot show.
- `[OPEN_QUESTION]` Q2. Confirm A2: should a running Live Activity switch format immediately when the display option changes (needs an activity update), or only from the next start (default)?
- `[OPEN_QUESTION]` Q3. Keep 每週/每月 in the range picker, or drop them for a simpler 24 h / 7 / 14 / 30 d set? Default: keep.
