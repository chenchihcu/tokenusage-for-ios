# Feature Spec: Vendor badges and app icon redesign

Status: implemented 2026-11-18 (owner approved) · extends FR-38 in `spec-v3-native-duo.md`.

## 1. Summary

Inside the app, Claude Code, Codex and Cursor all show the same white "C" on a coloured square, so the owner (single user, iPhone / iPhone Duo) has to read the name to know which vendor a row is. The home-screen app icon is a generic blue mark that says nothing about the app.

This spec gives each AI vendor (Claude Code, Codex, Cursor, Google Antigravity) an original badge that can be told apart at a glance by both colour and shape. It also refreshes the app icon so it reads as "quota across several AI tools".

Success: on the 額度 list, the widget and the home screen, the owner can tell which vendor is which without reading text, including in grayscale.

## 2. Scope

**In scope**
- Four original vendor badges: colour, symbol and 2-letter code. They are built into the app and need no files from the owner.
- Using the badges everywhere a vendor is shown:
  - 額度 list rows;
  - the detail header;
  - 「未設定」 rows;
  - 設定 sign-in rows;
  - 用量分析 pace rows;
  - home-screen widget rows.
- A new home-screen app icon in three variants: light (default), dark and tinted.
- Keeping FR-38: an owner-supplied `Resources/Logos/logo-<id>.png` still overrides the built-in badge.

**Out of scope**
- Bundling official logos for vendors other than Codex and Google Antigravity (revised 2026-11-28: owner approved bundling official Codex and Google Antigravity marks from `docs/brand/` into web + iOS app/widget badges, accepting trademark risk).
- Alternate app icons the owner can switch between (Settings → App icon). `[ASSUMPTION]` possible later.
- Lock-screen / StandBy widget families, Control Center controls.
- Changing chart series colours in 用量分析 (they stay per pool, `SeriesPalette`).
- App Store marketing artwork.

## 3. User Stories

- As the owner, I want each vendor's row to carry its own unmistakable badge, so that I find Cursor or Codex instantly without reading names.
- As the owner, I want the home-screen icon to look like a multi-vendor quota meter, so that I recognise the app among other icons.

## 4. Functional Requirements

### Vendor badges

- **FR-B1.** Each vendor has a fixed badge definition:

  | id | Vendor | Background | Symbol (SF Symbols) | Code |
  |---|---|---|---|---|
  | `claude` | Claude Code | terracotta `#B5532F` | `asterisk` | CC |
  | `codex` | Codex | near-black `#1F1F1F` | `chevron.left.forwardslash.chevron.right` | CX |
  | `cursor` | Cursor | deep teal `#0A7A76` | `cursorarrow` | CU |
  | `antigravity` | Google Antigravity | blue `#2F5FD6` | `arrow.up.to.line` | AG |

  - The symbol is white, centred, at 55 % of the badge side.
  - `[ASSUMPTION]` Colours and symbols are proposals the owner approves at review. Any pair must still meet FR-B3.
- **FR-B2.** The badge is a continuous rounded square, corner radius 25 % of its side. Its side follows Dynamic Type (`@ScaledMetric`, base 36 pt, as today).
- **FR-B3.** Any two badges differ in symbol shape, so they can be told apart in grayscale. Their background hues are ≥ 40° apart on the colour wheel; Codex is achromatic. Every background gives white ≥ 4.5:1 contrast. (A lightness-gap rule was considered and dropped: four mid-tone backgrounds cannot all carry white at 4.5:1 and also be 15 L* apart.)
- **FR-B4.** Below 20 pt side (widget rows, compact places), the badge shows the 2-letter code instead of the symbol, in a bold rounded font.
- **FR-B5.** (revised 2026-11-28) Codex (`codex`) and Google Antigravity (`antigravity`) bundle their official brand marks from `docs/brand/` into `Shared/BrandLogos.xcassets` (`logo-codex`, `logo-antigravity`) so both the iOS app and widget extension render them centered with 15% padding on a neutral tile (white in light mode, `#18181B` in dark mode) with a 1 pt hairline border; the web `PlatformIcon` renders the same official SVGs on `#18181B`. For other vendors, an owner-supplied `Resources/Logos/logo-<id>.png` in the app bundle still replaces the built-in badge, clipped to the same shape (FR-38).
- **FR-B6.** An unknown provider id shows a grey badge with the first two letters of its name in upper case.
- **FR-B7.** Badges appear in every place listed under "In scope" and are hidden from VoiceOver, because the vendor name is always read next to them.

### App icon

- **FR-I1.** The light app icon is a quota gauge on a deep navy background (`#101828`):
  - an open ring of four arcs, one per vendor, in fixed order (Claude Code, Codex, Cursor, Antigravity);
  - arc colours follow the badge colours, lightened where needed to show on navy: Claude `#B5532F`, Codex light grey `#9AA3AF` (near-black would vanish), Cursor `#14A39D`, Antigravity `#4A7BEA`;
  - a white needle pointing at about two o'clock;
  - no text and no vendor symbols.
- **FR-I2.** A dark variant uses the same art on a transparent background, so iOS supplies its own dark backdrop (Apple's guidance for dark icons; changed from "pure black" at implementation).
- **FR-I3.** A tinted variant is a single-colour grayscale version that iOS can tint.
- **FR-I4.** The icon art lives as an SVG source in the repo: `docs/icon/app-icon.svg`, plus the dark and tinted SVGs. PNGs at 1024 × 1024 are exported from it into `AppIcon.appiconset` with the three iOS appearances.
- **FR-I5.** The four arcs are distinguishable at 60 × 60 pt (home screen) and remain a recognisable gauge at 29 pt (Settings, Spotlight).

## 5. Acceptance Criteria

### FR-B1 / FR-B3
- **Given** Claude Code, Codex and Cursor are configured **When** 額度 opens **Then** the three rows show three different symbols on three different colours.
- **Given** the simulator's Color Filters are set to Grayscale **When** 額度 opens **Then** each badge is still identified by its symbol alone.
- **Given** the four badge colours **When** contrast with white and hue are computed **Then** each contrast is ≥ 4.5:1 (today 4.95, 16.5, 5.17, 5.63) and the chromatic hues are ≥ 40° apart (16°, 178°, 223°). A unit test asserts this.

### FR-B2 / FR-B4
- **Given** Dynamic Type at AX3 **When** 額度 opens **Then** badges grow with the text and the symbol is not clipped.
- **Given** a small widget **When** it renders on the home screen **Then** each row shows the 2-letter code badge (CC, CX, CU, AG) before the name.

### FR-B5
- **Given** `logo-cursor.png` is added to `Resources/Logos` **When** the app is built and opened **Then** Cursor's rows show that image in the rounded-square shape.
- **Given** no logo files **When** the app opens **Then** all rows show the built-in badges and no letter-only "C" badge appears anywhere.

### FR-B6
- **Given** a provider id `foo` named 「Foo AI」 **When** it is shown **Then** its badge is grey with 「FO」.

### FR-B7
- **Given** VoiceOver is on **When** a 額度 row is focused **Then** it reads the vendor name once; the badge itself is not read.

### FR-I1 – FR-I5
- **Given** the new build is installed **When** the home screen is shown in light mode **Then** the app icon shows the navy gauge with four coloured arcs.
- **Given** Home Screen appearance is set to Dark **When** the home screen is shown **Then** the black-background variant is used.
- **Given** Home Screen appearance is set to Tinted **When** the home screen is shown **Then** the tinted variant is used with no colour artefacts.
- **Given** the icon at 29 pt in Settings **When** viewed **Then** it is still a ring with a needle. Checked against an exported 58 px PNG.

## 6. Edge Cases and Failure Modes

- **Case:** A configured SF Symbol name doesn't exist on the running iOS. **Behavior:** the badge falls back to the 2-letter code (FR-B4 style) and never shows an empty square.
- **Case:** Owner logo file is not square. **Behavior:** it is scaled to fit inside the square, centred, with the badge colour behind it.
- **Case:** Owner logo file is under 180 × 180 px. **Behavior:** still used. `[ASSUMPTION]` no size check at runtime, since the owner controls the file.
- **Case:** Dark mode in the app. **Behavior:** badge colours stay the same. Codex's near-black badge gets a 1 pt hairline border (`separator` colour) so it doesn't vanish on dark backgrounds.
- **Case:** Increase Contrast enabled. **Behavior:** symbols stay white and the hairline border appears on every badge.
- **Case:** A new vendor is added later. **Behavior:** it gets a badge row in the FR-B1 table. Until then it uses FR-B6.

## 7. Non-Functional Requirements

- **Accessibility.**
  - Badge symbol vs background contrast ≥ 4.5:1 (WCAG 2.1 AA, non-text treated as text for safety).
  - Identification never relies on colour alone (FR-B3).
- **Compatibility.**
  - iOS 27.1 (project deployment target).
  - Icon appearances use the asset catalog's light / dark / tinted slots.
  - Badges render the same on iPhone Duo outer (~466 pt) and inner (~951 pt) screens.
- **Performance.** Badges are vector (SF Symbols + shapes), with no image decoding per row.
- **Legal / trademark.**
  - Revised 2026-11-28 (owner approved): Codex and Google Antigravity badges use official brand artwork stored in `docs/brand/codex.svg` and `docs/brand/antigravity.svg` (owner accepts trademark risk for personal/app use).
  - Other built-in badges (`claude`, `cursor`) and the home-screen app icon continue to use original non-trademarked geometry.
  - Vendor names appear only as text, to identify the service (nominative use).

## 8. Dependencies

- SF Symbols available on iOS 27 (`asterisk`, `chevron.left.forwardslash.chevron.right`, `cursorarrow`, `arrow.up.to.line`).
- An SVG → PNG export step for the icon. `[OPEN_QUESTION]` Use a small Swift/AppKit script in `scripts/`, or a tool such as `rsvg-convert`. Decide at implementation by what is installed.
- The widget extension must share `ProviderStyle` / `ProviderBadge`: move them to a file in both targets via `project.yml`, then `xcodegen generate`.

## 9. Risks and Mitigations

- **Risk:** The Claude Code `asterisk` reads as too close to a vendor's logo. **Mitigation:** use the plain SF Symbol, not a traced spark shape. The owner can swap to `terminal` at review.
- **Risk:** Teal (Cursor) and blue (Antigravity) look alike for some colour-vision types. **Mitigation:**
  - their symbols differ (arrow pointer vs up-to-line);
  - their hues are 45° apart (FR-B3);
  - check in the simulator with Color Filters → Deuteranopia.
- **Risk:** Moving badge code into the widget needs a project regeneration that could disturb other settings. **Mitigation:** diff `project.pbxproj` after `xcodegen generate` and run both schemes' builds and the tests.

## 10. Open Questions

1. Final colours and symbols. The table in FR-B1 is a proposal; the owner confirms or swaps at review.
2. SVG export tool (see Dependencies).
3. Should the app icon's arcs show real proportions (e.g. current remaining %)? Default no: iOS app icons are static. A live gauge belongs in the widget.

## 11. Success Metrics

- **Leading:** at review, the owner identifies all four vendors on a grayscale screenshot of 額度 within a couple of seconds, without reading names.
- **Lagging:** the owner no longer opens the wrong vendor's detail by mistake, and finds the app on the home screen by its icon. Informal, owner-reported.

## Test plan (for the implementer)

- Unit test: each badge colour gives ≥ 4.5:1 contrast with white, and the chromatic hues are ≥ 40° apart. Every FR-B1 symbol name resolves via `UIImage(systemName:)`.
- Visual checks on iPhone Duo (outer and inner), light and dark, and Grayscale and Deuteranopia color filters:
  - 額度;
  - detail header;
  - 設定;
  - 用量分析;
  - small and medium widgets;
  - home screen icon in light, dark and tinted.
