# Plan v3 — Native SwiftUI for iPhone Duo (iOS 27.1), direct phone refresh

Status: **Draft — awaiting user approval** · Date: 2026-11-17 · Baseline SHA: `669f04d`
Spec: `docs/spec-v3-native-duo.md` (FR-1…FR-29, acceptance criteria, open questions Q1–Q7).
Governs: `Institution/ios/IOS_SPEC.md` (SwiftUI, iOS 27.1 SDK, Gates G0–G5), `00-core-rules.md`, `06-ui-ux-universal.md`.

## 0. Decisions (made by user, 2026-11-17)

| # | Decision |
|---|---|
| D1 | Vendor tokens live in the **iPhone Keychain**. The phone calls each vendor directly over Wi-Fi/cellular. No PC sync in the data path. |
| D2 | **Native SwiftUI rewrite** (iOS 27.1 SDK, Swift 6.4). Capacitor shell is retired at the end. |
| D3 | **Dual review = Claude + Codex.** Claude implements + self-reviews against IOS_SPEC; Codex reviews each PR before merge. |
| D4 | **Sign in inside the app** (vendor page in a system browser sheet), never via PC. Per-vendor method decided in P1 (spec FR-21a). |
| D5 | **All voice functions removed** (decided 2026-11-17): no Gemini Live, no microphone button, no voice commands, no microphone permission. VoiceOver accessibility is kept (it is not a voice-command feature). |
| D6 | **Free resets: badge + local phone notification** (decided 2026-11-17). See spec FR-30…FR-33. |
| D7 | **Build path without paid accounts** (decided 2026-11-17, Claude's call): GitHub-hosted macOS runner on the free plan (private repo ≈ 2,000 min/month at 10× macOS multiplier ≈ 200 macOS min). macOS jobs run **manually (`workflow_dispatch`) only**, never on every push. Simulator build/test needs no Apple account. |
| D8 | **Order: P0 first, then P1→P6.** |
| D9 | **Free Apple ID only — no paid Apple Developer Program** (decided 2026-11-17). No TestFlight. Install path: CI builds an unsigned `.ipa` on the free GitHub macOS runner (manual run) → user signs and installs it from Windows with a free Apple ID using a sideloading tool (e.g. Sideloadly or AltServer; `[ASSUMPTION]` third-party, user's choice) or from a Mac with Xcode if one is available. Limits: the app expires after **7 days** and must be re-installed; at most 3 sideloaded apps per device. |

Assumptions (stated, change if wrong):
- A1. **Confirmed 2026-11-17:** four agents only — Codex, Claude Code, Cursor, Antigravity. Grok removed.
- A2. **Confirmed 2026-11-17:** model catalog removed.
- A3. Deployment target iOS 27.1 (IOS_SPEC §1 default).

## 1. Verified problems in the current build (from `/verify`, 669f04d)

| # | Problem | Evidence |
|---|---|---|
| B1 | Every API call fails: `fetch` stored on a class and called as a method → `Illegal invocation`. App only ever shows a hard-coded snapshot. | `src/client/network/apiClient.ts:84`; browser error captured 7×; one-line bind restored 15 s / 60 s / manual cadence exactly. |
| B2 | Status stuck on 「正在確認連線…」 even after 200/304 responses. | Observed at 5 s, 20 s, 65 s; candidate cause: generation race in `useDirectInternet` + `reducer.ts`. |
| B3 | Data never refreshes without the PC: phone reads Worker D1 that only the PC daemon writes; empty D1 serves hard-coded `DEFAULT_REAL_QUOTAS` as if real. | `src/worker/index.ts:361-376`, `scripts/sync-desktop-*.py`. |
| B4 | Vendor "free reset" credits (`Resets: N available`) never shown; the "FREE" badge only means the weekly window date passed (all show FREE today because data is 18 days old). | `utils/resetMonitor.ts`, UI text capture. |
| B5 | Outer screen (375 pt): header clips DUO button; refresh-interval control off-screen (x=424). | Playwright geometry. |
| B6 | Floating buttons cover card text. | Screenshot. |
| B7 | 9–10 tap targets < 44 pt; 76–80 text nodes < 12 px; 46 forbidden font weights; dark-only theme. | DOM audit vs HIG / 06-ui-ux. |
| B8 | Widget likely never receives data: Capacitor `Preferences.configure({group})` is a key prefix, not an App Group. | INFERENCE — verify on device. |
| B9 | iOS target 14.0, Swift 5.0, CI `macos-14` → not built with iOS 27.1 SDK. | `project.pbxproj`, `Podfile`, `build-ios.yml`. |
| B10 | Grok shown (user tracks 4 agents); no 3–4 icon right-hand fast path (only refresh + voice mic, which D5 removes). | UI capture. |

## 2. Target architecture

```
project.yml (XcodeGen, single source; .xcodeproj generated, git-ignored)
Packages/Core/         pure Swift (Foundation only) — testable on Linux/Windows
  Models/              Agent, UsageWindow(5h/weekly/…), UsageSnapshot, ResetCredits
  Providers/           CodexProvider, ClaudeCodeProvider, CursorProvider, AntigravityProvider
                       (request builders + response parsers; HTTP injected)
  Refresh/             RefreshPolicy (15s/30s/1m/5m/15m/manual), backoff, staleness
App/
  AppMain.swift        @main, UIScene lifecycle
  Features/Dashboard/  CompactLayout (outer) / WideLayout (inner) — size class only
  Features/AgentDetail/
  Features/Settings/   tokens (Keychain), interval, handedness
  Features/FastPath/   3–4 thumb-zone actions
  DesignSystem/        semantic colors (light default + dark), Dynamic Type styles
  Resources/           Localizable.xcstrings (zh-Hant, en), PrivacyInfo.xcprivacy
Widget/                WidgetKit extension, reads shared Keychain/App Group snapshot
AppTests/, AppUITests/, scripts/ (check-toolchain.sh, test.sh, audit.sh)
.github/workflows/ios-ci.yml  (runs-on: xcode-27; build + test only, never deploy)
```

Data path: **iPhone → vendor HTTPS** (Wi-Fi or cellular, system-chosen). No Worker, no PC.

## 3. Phases

Each phase = one PR on a `claude/*` / `work/*` branch → Claude self-review → **Codex review** → merge.

### P0 — Hotfix current Capacitor app (small, so you have a working app meanwhile)
- Fix B1 (bind fetch), B2 (status race), B5 header overflow.
- **Remove voice from the current app:** mic button, `AudioVisualizer`, Gemini Live WebSocket (`/ws/live`), `VoiceSessionDO` + its Durable Object binding, voice text in `LiveBar`/`DetailWorkbench`/`SplitViewContainer`, `NSMicrophoneUsageDescription` in `Info.plist`, voice sections in README. Durable Object removal needs a `deleted_classes` migration on deploy (user-approved deploy only).
- DoD: at Duo outer/inner sizes, status shows 「已同步」, `/api/quotas` cadence = setting (15 s/60 s/manual) — verified in browser.
- Still PC-fed (B3) until P3 ships.

### P1 — Spikes that gate everything (no product code)
1. **Vendor endpoints** (all unofficial → `[ASSUMPTION]` until a live call succeeds):
   Codex (ChatGPT usage, OAuth token), Claude Code (OAuth usage incl. 5h/weekly + reset credits), Cursor (session usage), Antigravity (Google). For each: URL, auth header, token lifetime/refresh, fields for 5h/weekly/resetsAt/**free-reset credits**, rate limits.
   Needs: you supply one token per vendor **on your device or as a session credential — never in chat**.
2. **SDK API check** (IOS_SPEC §4.4) on Xcode 27.1: `reservedRegions`, `ArrangementView`, vertical toolbar opt-out, `onHingeChange`, Liquid Glass APIs.
- DoD: written table of confirmed endpoints/fields; SDK grep output. Any vendor without a workable endpoint → reported, shown as "not available" (no fake data).

### P2 — Skeleton + Core
- `project.yml`, app + widget targets, Keychain access group, `Packages/Core` models & parsers with fixtures from P1.
- G1: `swift build && swift test` for Core; §4.3 forbidden-API grep = 0.
- G2/G3: `ios-ci.yml` on `xcode-27` builds an empty app on the iPhone Duo simulator.

### P3 — Providers + refresh engine
- 4 providers; Keychain token storage with Settings screen (paste token; masked; delete).
- Foreground refresh honours the setting exactly; manual pull-to-refresh; backoff on 429/5xx; offline shows last-good data with timestamp.
- Background: `BGAppRefreshTask` + widget timeline. **iOS decides background timing** — 15 s is foreground-only; this is stated in the Settings UI.
- **Reset monitor:** Codex + Claude Code show 5h and weekly windows with countdowns **and free-reset credits available** (when the vendor reports them); an alert badge when credits > 0 or a window resets within 24 h.

### P4 — Duo UI (HIG for iPhone Duo)
- Two branches by size class only (outer compact / inner regular), same features both.
- Inner: `NavigationSplitView` (agent list | detail); `.toolbar` items with title + SF Symbol (system moves them to the vertical bar); no controls on the crease (`reservedRegions(kind: .division)` if confirmed in P1).
- **Right-hand fast path — 4 icons** (thumb zone, bottom-trailing on outer; toolbar on inner; mirrors for left-hand):
  1. `arrow.clockwise` Refresh now
  2. `gift` / `arrow.counterclockwise.circle` Free-reset & next-reset view (Codex, Claude Code)
  3. `exclamationmark.triangle` Alerts only (≤ 5 % remaining)
  4. `timer` Refresh interval
- Light theme default + dark; Dynamic Type; ≥ 44 pt targets; VoiceOver labels; Reduce Motion/Transparency.
- G4 posture matrix P01–P13 × C1–C6 (needs Mac screen-share or device — you/human).

### P5 — Widget
- Small/medium widgets: 4 agents + next reset + free-reset credits. Reads shared snapshot written by the app.

### P6 — Retire old stack
- Remove Capacitor/React/Worker quota path and PC daemon from the build (kept in git history). README updated.
- Worker retired entirely (voice was its only other use).

## 4. Verification & dual review per PR

| Step | Who | Evidence |
|---|---|---|
| Self-review vs IOS_SPEC §4.2/§4.3/§6/§7 checklist | Claude | checklist in PR body |
| G1 Core tests, forbidden-API grep | Claude (this container) | command output |
| G2/G3 build + XCTest/XCUITest on iPhone Duo sim | `xcode-27` GitHub runner | Actions link + xcresult |
| Code review | **Codex** (you trigger) | PR review |
| G4 posture screenshots | human + Agent | `docs/evidence/<date>-<feature>/matrix.md` |
| G5 Sideloaded build (free Apple ID, D9) on your iPhone Duo | you | sign-off |

Claude reports the highest Gate actually reached; never "verified" below G2.

## 5. Blockers / what I need from you

1. **Mac build path** — resolved by D7. **Device install** — resolved by D9 (free Apple ID, 7-day re-install). `VERIFY` in P1: which capabilities a free (personal team) signing allows — Keychain sharing and local notifications are expected to work; **App Groups for the widget are uncertain**. If App Groups are refused, the widget reads its snapshot through the shared Keychain access group instead.
2. **Tokens for P1 spikes** — one per vendor, entered via the session credential form or on-device, never pasted in chat.
3. **Signing and installing** stay with you (IOS_SPEC §8): your free Apple ID is entered only in your own signing tool, never in this repo or chat.
4. ~~A1/A2~~ confirmed.

## 6. Risks

- Vendor usage endpoints are undocumented and can change or be blocked; tokens expire (re-entry flow needed). Mitigation: per-provider error state, never fabricated numbers.
- Background refresh cadence is controlled by iOS, not the app.
- Duo simulator cannot run most extensions (IOS_SPEC §9.2) → widget verified on device only.

## 7. View-by-view review (2026-11-17, current build, rendered at Duo sizes)

Rendered: ALL 全景 / DUO 雙欄 × outer portrait 375×812, outer landscape 812×375, inner portrait 626×890, inner landscape 890×626, plus left-hand, two-hand and alerts-only. Sizes are `[ASSUMPTION]` approximations; no Duo simulator here.

| # | View | Finding | Fix (where) |
|---|---|---|---|
| V1 | All | Four stacked bars (header, status, reset strip, live bar) take 329/812 pt on outer portrait and leave only 164/375 pt of content in outer landscape. | P0: merge into one status line + reset strip; hide live bar when list shows the same data. P4: system nav bar + one summary row. |
| V2 | All | Floating buttons cover card numbers in 10 of 12 views. | P0: reserve bottom inset equal to the cluster. P4: FR-18 safe-area cluster / toolbar. |
| V3 | DUO, inner portrait | Three columns (icon rail + list + detail) squeezed into 626 pt: agent name truncated to 「C…」, 「確認中」 wraps one character per line. | P0: drop the icon rail when the list is visible. P4: `NavigationSplitView` two columns only. |
| V4 | DUO, inner both | Detail pane leads with Gemini Live waveform + transcript; the usage numbers are below the fold. | P0: remove voice panels (D5); numbers first. |
| V5 | DUO, inner | Detail contains 0K–100K "thinking budget" chips, partly off-screen; unrelated to usage monitoring. | P0: remove. Not in v3. |
| V6 | Left-hand | Whole card content is mirrored (ring/arrow swapped, text right-aligned) and 「ALL 全景」 is pushed off-screen. HIG moves controls, not reading order. | P0: mirror only the button cluster. P4: FR-19. |
| V7 | Two-hand | Identical to right-hand; the mode does nothing visible. | P0: remove the mode (right/left only, FR-19). |
| V8 | DUO, outer portrait | 「DUO 雙欄」 selected but shows one column — the label promises something the screen can't do. | P0: hide the ALL/DUO switch on narrow widths. P4: layout follows size class automatically (FR-27); no manual switch. |
| V9 | DUO list | Search field for 5 items; 「SSOT 有效」/「5 Platforms Bonded」 badges claim status the app hasn't verified. | P0: remove the search field and both badges. |
| V10 | All | Refresh-interval menu and handedness control off-screen on outer portrait; reset chips cut off with no scroll hint. | P0: move interval + handedness into a Settings sheet reachable from the fast-path cluster; wrap reset chips. |

## 8. P0 status (2026-11-17) — implemented, browser-verified, awaiting Codex review

Fixed: B1 (fetch binding), B2 (first network snapshot reset API state), B4 (free-reset credits shown; passed reset ≠ "FREE"), B5/V10, B6/V2, V1, V3–V9; voice, Grok, model catalog and hard-coded sample data removed; Worker returns an empty list instead of sample rows; macOS CI manual-only (D7); v1.3.0.
Evidence (local Worker + Chromium at Duo-approximate sizes): status 「已同步」; 15 s setting → requests at 0.1 / 15.1 / 30.1 s, manual → 1; a pushed credit change 0 → 2 appeared on the next refresh; 16/16 view × hand combinations scroll clear of the cluster with 0 off-screen controls and 0 targets < 44 pt; Playwright 58/58.
Not done in P0 (by plan): B3 phone-direct data (P3), B7 light theme / small text (P4), B8 widget App Group (P5), B9 iOS 27.1 target (P2). Highest gate: G1-equivalent (web); no Duo simulator or device run.
Deploy pending (needs user OK): Worker removal of `VoiceSessionDO` via migration `v2`.
