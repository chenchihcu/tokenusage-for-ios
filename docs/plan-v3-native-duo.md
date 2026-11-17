# Plan v3 — Native SwiftUI for iPhone Duo (iOS 27.1), direct phone refresh

Status: **Draft — awaiting user approval** · Date: 2026-11-17 · Baseline SHA: `669f04d`
Governs: `Institution/ios/IOS_SPEC.md` (SwiftUI, iOS 27.1 SDK, Gates G0–G5), `00-core-rules.md`, `06-ui-ux-universal.md`.

## 0. Decisions (made by user, 2026-11-17)

| # | Decision |
|---|---|
| D1 | Vendor tokens live in the **iPhone Keychain**. The phone calls each vendor directly over Wi-Fi/cellular. No PC sync in the data path. |
| D2 | **Native SwiftUI rewrite** (iOS 27.1 SDK, Swift 6.4). Capacitor shell is retired at the end. |
| D3 | **Dual review = Claude + Codex.** Claude implements + self-reviews against IOS_SPEC; Codex reviews each PR before merge. |

Assumptions (stated, change if wrong):
- A1. Four agents only: **Codex, Claude Code, Cursor, Antigravity**. Grok is removed.
- A2. Gemini Live voice and model catalog are **not** carried into v3 (not requested). → Confirm, or they become Phase 7.
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
| B10 | Grok shown (user tracks 4 agents); no 3–4 icon right-hand fast path (only refresh + mic). | UI capture. |

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
- Optional: keep Worker only if A2 changes.

## 4. Verification & dual review per PR

| Step | Who | Evidence |
|---|---|---|
| Self-review vs IOS_SPEC §4.2/§4.3/§6/§7 checklist | Claude | checklist in PR body |
| G1 Core tests, forbidden-API grep | Claude (this container) | command output |
| G2/G3 build + XCTest/XCUITest on iPhone Duo sim | `xcode-27` GitHub runner | Actions link + xcresult |
| Code review | **Codex** (you trigger) | PR review |
| G4 posture screenshots | human + Agent | `docs/evidence/<date>-<feature>/matrix.md` |
| G5 TestFlight on your iPhone Duo | you | sign-off |

Claude reports the highest Gate actually reached; never "verified" below G2.

## 5. Blockers / what I need from you

1. **Mac build path**: confirm the repo may use the `xcode-27` GitHub runner (billing), or provide a cloud Mac. Without it, nothing above G1 can be verified.
2. **Tokens for P1 spikes** — one per vendor, entered via the session credential form or on-device, never pasted in chat.
3. **Signing / TestFlight** stays with you (IOS_SPEC §8).
4. Confirm A1 (drop Grok) and A2 (drop voice + model catalog).

## 6. Risks

- Vendor usage endpoints are undocumented and can change or be blocked; tokens expire (re-entry flow needed). Mitigation: per-provider error state, never fabricated numbers.
- Background refresh cadence is controlled by iOS, not the app.
- Duo simulator cannot run most extensions (IOS_SPEC §9.2) → widget verified on device only.
