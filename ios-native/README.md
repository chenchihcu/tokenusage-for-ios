# OpenTokenUsage — iPhone app

SwiftUI app for iPhone Duo (iOS 27.1), no web view and no relay server. It asks each
service for usage directly from the phone, over Wi-Fi or cellular.

| Service | Sign-in (Settings › 帳號) | Shows |
|---|---|---|
| Codex | Device code, approved on OpenAI's page | 5 h / weekly windows, free-reset count when reported |
| Claude Code | Claude's page, then paste the code it shows | 5 h / weekly windows, free-reset count when reported |
| Cursor | Cursor's page; the app detects when sign-in finishes | Plan usage |
| Google Antigravity | Not supported on the phone yet | — |

Sign-in happens on each vendor's own page; the app never sees a password. Credentials stay
in the Keychain and are renewed on the phone. None of these sign-in or usage endpoints is a
documented public API, so a vendor change can break one service without affecting the others.
A manual token field remains under Settings › 帳號 › 進階 as a fallback.

## Using it

| Screen | Layout |
|---|---|
| Outer screen (compact width) | One column. Fast path in the thumb zone: 更新 · 重置 · 告警 · 頻率 (bottom right, or bottom left in left-hand mode) |
| Inner screen (both sides ≥ 600 pt) | List and detail panes meeting at the fold; the fast path sits in the toolbar |

- **Refresh** follows the chosen interval (15 s … 15 min, or manual) while the app is open. Each service has a floor (Claude Code 5 min, Codex and Cursor 1 min), and a 429 reply backs that service off. In the background iOS decides when to refresh.
- **Free resets**: shown only when the vendor reports them; otherwise 「免費重置：不提供」. Turn on 「免費重置通知」 to get one notification when Codex or Claude Code credits appear or increase.
- **Widget** (small, medium): remaining usage from the app's last refresh.
- **示範資料** in Settings shows sample figures for checking layouts; they are not your usage.

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
