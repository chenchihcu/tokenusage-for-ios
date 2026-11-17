# OpenTokenUsage — native iPhone app

SwiftUI app with no web view. It asks each provider (Claude, Codex,
Cursor) for usage directly from the phone, using account tokens kept in the
Keychain, with no relay server. Built for the iPhone Duo. Launch with
`-opentokenusage_sample_data YES` (or Settings → 示範資料) to see bundled figures.

| Screen | Layout |
|---|---|
| Folded (outer screen) or any phone-sized window | One column: list → tap → detail, standard back button and edge swipe |
| Unfolded (inner screen, both sides ≥ 600 pt) | Two panes meeting at the middle of the display, where the fold is: side by side when held as a book, stacked when turned upright |

Pull to refresh. It refreshes automatically only while open (interval in the app's
Settings sheet or in the iOS Settings app), shows the last data when offline, and
plays haptics on selection and successful refresh.

## Build

```bash
brew install xcodegen
```

```bash
cd ios-native && xcodegen generate && open OpenTokenUsage.xcodeproj
```

CI: `.github/workflows/build-ios.yml` (unsigned IPA) and
`.github/workflows/ios-simulator-screenshots.yml` (unit tests + simulator screenshots).

## Not ported from the web app

Gemini Live voice, the model catalog sheet and the thinking-budget presets.
