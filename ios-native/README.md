# OpenTokenUsage — native iPhone app

SwiftUI app with no web view. It reads the same API as the website
(`GET /api/quotas` on the Cloudflare Worker) and is built for the iPhone Duo.

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
