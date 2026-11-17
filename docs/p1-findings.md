# P1 findings — vendor sign-in, usage endpoints, free Apple ID, SDK

Date: 2026-11-17 · Plan: `docs/plan-v3-native-duo.md` · Spec: `docs/spec-v3-native-duo.md`

**Method and limits.** Desk research only. This cloud container cannot reach most vendor hosts (chatgpt.com, cursor.com, console.anthropic.com, api2.cursor.sh: blocked; api.anthropic.com: reachable) and holds no tokens, so **no live sign-in or usage call was made**. Every vendor row below is `[ASSUMPTION]` until the on-device sign-in test (P3 step 1) succeeds. None of these endpoints is a documented public API.

## 1. Vendors

| Vendor | Phone sign-in method (FR-21a) | Usage endpoint (community-documented) | Free-reset credits | Main risk | Verdict |
|---|---|---|---|---|---|
| **Codex** | (b) **OAuth device code** — the official Codex CLI has `--device-auth`. App shows a code; you approve on the OpenAI page in the browser sheet. | `GET https://chatgpt.com/backend-api/wham/usage`, Bearer ChatGPT OAuth token. Codex CLI's internal surface, not a public contract. | `VERIFY` — whether `wham/usage` returns the "Resets: N available" value is unknown. | Reuses the Codex CLI's OAuth client from a third-party app (terms risk); endpoint can change. | **Feasible** |
| **Claude Code** | (a) **OAuth + PKCE** in the browser sheet, with the "copy the code" page as the return path if no app redirect is allowed. | `GET https://api.anthropic.com/api/oauth/usage`, Bearer OAuth token + `anthropic-beta: oauth-2025-04-20`. Returns `five_hour` / `seven_day` with `utilization` and `resets_at`. API keys are not accepted. | `VERIFY` — not seen in the reported fields (`five_hour`, `seven_day`, `extra_usage` on Pro). | **Aggressive HTTP 429** reported for this endpoint: 15 s polling will be refused. Same terms risk as Codex. | **Feasible with a slower floor** (see §3) |
| **Cursor** | **Browser sign-in + polling** (how the Cursor CLI logs in) `[ASSUMPTION]`; the spec's "web session cookie" option (c) cannot work in the system browser sheet because the app cannot read its cookies. | `GET https://cursor.com/api/usage-summary` with cookie `WorkosCursorSessionToken=<user_id>::<jwt>`; or `api2.cursor.sh/auth/usage` with Bearer. | Not applicable (no free resets known). | Sources disagree on which field matches the percentage Cursor shows. | **Feasible, method must be confirmed** |
| **Antigravity** | Google OAuth with Antigravity's own client. Google normally blocks sign-in from clients that aren't the official app, and the desktop flow uses a localhost redirect an iPhone app cannot host cleanly. | `cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels` (`quotaInfo.remainingFraction`, `resetTime`); reports say it now always returns 1.0 and `retrieveUserQuotaSummary` replaces it. | Not applicable. | Highest: sign-in may be refused outright; quota numbers reported unreliable. | **Likely unsupported on phone** — shown as 「此服務暫不支援手機登入」 unless the device test succeeds |

### Account risk you should know about (decision for you)
Signing in from this app means presenting the vendors' **own CLI sign-in clients** from an app they did not make. Community tools do this, but it may break each vendor's terms of use; the realistic worst case is that the vendor blocks the sign-in or, rarely, flags the account. Nothing here asks for your password — the vendor page handles it.

## 2. Free Apple ID (plan D9)

- App Groups and Keychain Sharing are reported to work on a free Personal Team; Keychain Sharing is on for every App ID by default. → The widget can share data with the app. `VERIFY` at first install.
- Limits: profile expires after 7 days; up to 3 devices; about 10 App ID changes per 7 days — so App ID / App Group setup should be done once and not churned.
- Local notifications need no special entitlement (no push server). Background refresh needs the Background Modes capability, reported available.

## 3. Changes this forces on the spec

1. **Per-vendor minimum refresh interval** (new FR-12a): the app setting stays 15 s … manual, but each vendor is polled no faster than its floor. `[ASSUMPTION]` starting floors, tuned on device: Claude Code **5 min**, Codex **1 min**, Cursor **1 min**, Antigravity **5 min**. A 429 still backs off by `Retry-After` (FR-12). The UI shows the effective interval per agent ("每 5 分鐘") so it never looks stuck.
2. **FR-21a Cursor**: replace the "web session cookie" option with "browser sign-in + polling".
3. **FR-13/14 free resets**: until the device test shows a reset-credit field for Codex or Claude Code, the app shows 「免費重置：不提供」 (FR-14) and the notification (FR-31) never fires. If neither vendor exposes it, the free-reset feature cannot work phone-only — that would need your decision.
4. **Antigravity**: expected to ship as "not supported on phone" unless the device test passes.

## 4. SDK check (IOS_SPEC §4.4)

Run by `.github/workflows/sdk-probe.yml` (`scripts/sdk-probe.sh`).

**Unblocked 2026-11-17** after the repo was made public. Run [44031060815](https://github.com/chenchihcu/tokenusage-for-ios/actions/runs/44031060815):

| Runner | Xcode / SDK / Swift | iPhone Duo simulator | Duo APIs |
|---|---|---|---|
| `xcode-27` | 27.1 (27.0–27.2 installed) / iOS 27.1 / Swift 6.4 | **Yes** (`SimDeviceType.iPhone-Duo`; runtimes 27.0, 27.1, 27.2) | **All FOUND**: `reservedRegions`, `UIViewReservedRegion`, `ArrangementView` / `arrangementViewStyle` / `overlayArrangementZIndex`, `UIArrangementViewController`, `onHingeChange`, `UIHingeInteraction`, `defaultTabBarPlacement`, `ConcentricRectangle`, `UICornerConfiguration`, `BGAppRefreshTask` |
| `macos-latest` | 26.6 / iOS 26.5 | No | Duo APIs missing → **not usable**; all iOS jobs must use `xcode-27` |

`ASWebAuthenticationSession` reported MISSING on both — a probe-pattern miss (API dates from iOS 12); `VERIFY` by compiling the sign-in code. The earlier runner block (first run 44027472527, no runner assigned) was the private-repo minutes limit.

## 5. Existing native work — PR #4

PR #4 (`claude/laughing-einstein-vlp4cu`, open, merge conflicts) already contains `ios-native/`: a SwiftUI app with XcodeGen, folded single column / unfolded two panes that meet at the fold, pull to refresh, foreground auto refresh, offline cache, unit tests, and direct provider fetch for Claude, Codex and Cursor using tokens pasted into Settings (Keychain). It has **never been compiled** (same runner block).
Decision (Claude, technical): **P2 starts from PR #4's `ios-native/` instead of a new skeleton.** Gaps against this spec to close in P2–P4: pasted tokens → in-app sign-in (D4); its "auto-reset" rule shows numbers the vendor never sent (remove, as in P0); add Antigravity status, free-reset credits, 4-icon fast path, per-vendor floors (§3), notifications (FR-30…33).

## Sources
- Codex: [Codex CLI reference (`--device-auth`)](https://developers.openai.com/codex/cli/reference), [codex-usage](https://github.com/AnandChowdhary/codex-usage), [ai-usage #5](https://github.com/sebastian-suarez/ai-usage/issues/5)
- Claude Code: [claude-code #31637 (429)](https://github.com/anthropics/claude-code/issues/31637), [claude-code #34346](https://github.com/anthropics/claude-code/issues/34346), [openusage Claude Code](https://openusage.sh/docs/providers/claude-code/), [claude_usage](https://github.com/thiswillbeyourgithub/claude_usage)
- Cursor: [caam #109](https://github.com/Dicklesworthstone/coding_agent_account_manager/issues/109), [openusage #1551](https://github.com/robinebers/openusage/issues/1551), [dashboard API gist](https://gist.github.com/dmwyatt/1e9359b1862e7cbfe1e754fe4c8db764)
- Antigravity: [API spec](https://github.com/NoeFabris/opencode-antigravity-auth/blob/main/docs/ANTIGRAVITY_API_SPEC.md), [AIUsage #81](https://github.com/sylearn/AIUsage/issues/81), [CLIProxyAPI #1015](https://github.com/router-for-me/CLIProxyAPI/issues/1015)
- Free Apple ID: [Expo: free vs paid](https://expo.dev/blog/apple-developer-program-explained-free-vs-paid.md), [flaviocopes](https://flaviocopes.com/apple-developer-free-vs-paid/), [Apple forums 834802](https://developer.apple.com/forums/thread/834802), [Apple: sharing keychain items](https://developer.apple.com/tutorials/data/documentation/security/sharing-access-to-keychain-items-among-a-collection-of-apps.md)
