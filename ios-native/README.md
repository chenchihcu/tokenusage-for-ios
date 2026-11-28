# OpenTokenUsage — iPhone app

SwiftUI app for iPhone Duo (iOS 27.1), no web view. It asks Claude Code, Codex and Cursor
for usage directly from the phone, over Wi-Fi or cellular. Google Antigravity cannot sign in
on a phone, so its figures are relayed by your Mac through your Worker (below).

| Service | Sign-in (Settings › 帳號) | Shows |
|---|---|---|
| Codex | Device code, approved on OpenAI's page | 5 h / weekly windows, free-reset count when reported |
| Claude Code | Claude's page, then paste the code it shows | 5 h / weekly windows, free-reset count when reported |
| Cursor | Cursor's page; the app detects when sign-in finishes | Plan usage |
| Google Antigravity | No phone sign-in. Settings › 帳號 › Mac 轉送: your Mac reads usage with CodexBar and uploads it to your Worker | Gemini Models, Claude and GPT models, Gemini 4 Argon (5 h / weekly), with the Mac's data time |

Sign-in happens on each vendor's own page; the app never sees a password. Credentials stay
in the Keychain and are renewed on the phone. None of these sign-in or usage endpoints is a
documented public API, so a vendor change can break one service without affecting the others.
A manual token field remains under Settings › 帳號 › 進階 as a fallback.

## Google Antigravity through your Mac

Google does not allow signing in to Antigravity from the phone. Instead:

1. On the Mac, sign in to Antigravity and to CodexBar (its `codexbar` command must print Antigravity usage).
2. Deploy the Worker (`npm run worker:deploy`) and set a write secret: `npx wrangler secret put SYNC_TOKEN`.
3. Install the relay, which runs every 5 minutes while you are logged in:
   `SYNC_TOKEN=<same secret> scripts/install-antigravity-relay-mac.sh` (remove with `--uninstall`).
4. On the phone: Settings › 帳號 › Google Antigravity › Mac 轉送, confirm the Worker address.

The relay uploads nothing when CodexBar has no measured quota (for example "Antigravity CSRF
token not found" while Antigravity is restarting), so the phone never shows invented figures.
Figures more than an hour old are marked 「Mac 超過 1 小時未轉送」 with their real time.
Log: `~/Library/Logs/opentokenusage-antigravity-relay.log`.

## Using it

| Screen | Layout |
|---|---|
| Outer screen (compact width) | One column. Fast path in the thumb zone: 更新 · 重置 · 告警 · 頻率 (bottom right, or bottom left in left-hand mode) |
| Inner screen (both sides ≥ 600 pt) | List and detail panes meeting at the fold; the fast path sits in the toolbar |

- **Refresh** follows the chosen interval (15 s … 15 min, or manual) while the app is open. Each service has a floor (Claude Code 5 min, Codex and Cursor 1 min), and a 429 reply backs that service off. In the background iOS decides when to refresh.
- **Free resets**: shown only when the vendor reports them; otherwise 「免費重置：不提供」. Turn on 「免費重置通知」 to get one notification when Codex or Claude Code credits appear or increase.
- **Each provider row** shows when it last updated, or why it failed (sign in again, rate limited, response changed, offline) with its last figures marked 「上次資料」. Long-press a row for 「只更新這個服務」.
- **Widgets**: Home Screen (small, medium; all services or one service's pools) and Lock Screen (inline, circular, rectangular; one window, by default the tightest). Figures older than an hour are dimmed.
- **重置倒數 Live Activity**: 「在鎖定畫面追蹤」 on a window's detail starts a Lock Screen / Dynamic Island countdown (one at a time, about 8 hours at most). Also from the Control Center control 「追蹤下次重置」 or Siri (「用 OpenTokenUsage 追蹤下次重置」); 「用 OpenTokenUsage 查額度」 reads each service's tightest window.
- **Notifications** (Settings › 通知): free resets, level alerts (80/95 %, or 50/80/95 %), 用完與重置, 未用完提醒 (weekly windows, 12 h before reset), 每週摘要 (Monday 09:00), and 勿擾時段 that holds them and drops ones that are no longer true. See [`docs/spec-competitive-gap-v3.1.md`](../docs/spec-competitive-gap-v3.1.md).
- **未登入**的服務在額度頁顯示「未設定」，沒有百分比。點公司圖示進入該服務的登入；已登入則進入它的視窗。

## Build and install

```bash
brew install xcodegen
```

```bash
cd ios-native && xcodegen generate && open OpenTokenUsage.xcodeproj
```

Without a Mac: GitHub Actions `build-ios.yml` (runner `xcode-27`) builds an unsigned
`OpenTokenUsage.ipa` on every change to `ios-native/`. Download it from the run's
Artifacts and sign it with a free Apple ID (Xcode, or a sideloading tool on Windows).
Free-account builds expire after 7 days and must be reinstalled.

`ios-simulator-screenshots.yml` runs the unit tests and captures both iPhone Duo displays.

## Request an Antigravity update from the iPhone

Apply the Worker D1 migrations before running this version. Configure separate Worker
secrets: `SYNC_TOKEN` for the Mac uploader and `ANTIGRAVITY_REFRESH_TOKEN` for the
phone. Use independent random values. Reinstall the Mac relay with
`scripts/install-antigravity-relay-mac.sh` to enable polling every 20 seconds.
Scheduled measurements continue every five minutes when the Worker cannot accept requests.

On the iPhone, open 設定 › 帳號 › Google Antigravity › 檢查轉送. Enter the phone refresh
key and choose 請 Mac 立即更新. The app waits up to about 75 seconds for a measured
snapshot whose data timestamp is at or after the accepted request. The Mac must be awake,
online, and able to read Antigravity usage. A timeout keeps the last available snapshot.

## Release checklist (every version)

The version and the settings shown to the person must match the build. `SettingsAlignmentTests` fails when they drift.

1. Bump `MARKETING_VERSION` **and** `CURRENT_PROJECT_VERSION` in `project.yml`. Nowhere else: both Info.plists read them.
2. Align settings: every new or changed option appears in the app's 設定 page with an accurate footer; options that also live in the iOS Settings app (`OpenTokenUsage/Resources/Settings.bundle/Root.plist`) have the same key, default, choices and wording. Re-read every footer for statements the release made untrue.
3. Run the unit tests; check 設定 › 版本 in the app and iOS 設定 › OpenTokenUsage › 版本 show the new `version (build)`.

