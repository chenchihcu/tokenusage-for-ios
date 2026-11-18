# Feature Spec: Home-screen widget aligned with the 額度 list

Status: implemented 2026-11-18 (owner approved, defaults taken for all open questions) · builds on `spec-vendor-badges-app-icon.md` (FR-B1…B7).

## 1. Summary

The 「AI 額度」 home-screen widget looks unlike the app's 額度 page:
- its badges show 2-letter codes (CC, CX, CU) instead of the vendor symbols;
- its vendor order is Codex, Claude Code, Cursor, while the app shows Claude Code, Codex, Cursor;
- it has no progress bar, per-model line or reset time.

The owner (single user, iPhone / iPhone Duo) should be able to read the widget the same way as the app. Success: a widget row and the matching 額度 row show the same badge, order, colours, bar and per-model figures.

## 2. Scope

**In scope**
- Small and medium widgets (the two sizes that exist today).
- The same symbol badges, vendor order, level colours and progress bar as `QuotaRow`.
- In the medium widget only, the per-model pool line (`PoolSummary`) and reset time (`ResetText`).
- Moving the shared row pieces into `OpenTokenUsage/Shared/`, so the app and widget draw from one source. This covers `QuotaLevel.tint`, `PoolSummary`, `ResetText` and the vendor order.
- Correcting the widget's gallery description to list vendors in app order.

**Out of scope**
- Large widget, Lock Screen (accessory) widgets, StandBy layouts, Control Center. `[ASSUMPTION]` next iteration if wanted.
- Interactive widget buttons (refresh from the widget).
- Pace status (「會不會用完」) in the widget.
- Changing how or when the widget's data is refreshed (still the app's last snapshot, timeline fallback 30 min).
- Antigravity data. The phone can't sign in to it, so it never has a row; its badge is defined but unused here.

## 3. User Stories

- As the owner, I want the widget rows to look like the 額度 rows, so that I recognise each vendor and its state at a glance without learning a second layout.
- As the owner, I want the medium widget to show which model pool is low and when it resets, so that I don't need to open the app for the common question.

## 4. Functional Requirements

- **FR-W1.** Widget rows are ordered Claude Code, Codex, Cursor (then Antigravity, then unknown ids). This is the same fixed order as the 額度 list, from one shared definition, and is never sorted by remaining %.
- **FR-W2.** Each row shows the vendor's symbol badge (FR-B1):
  - side ≥ 22 pt in small, 26 pt in medium, so the symbol is used, not the 2-letter code;
  - the code fallback (FR-B4) still applies if Dynamic Type shrinks it below 20 pt.
- **FR-W3.** Each row shows remaining % in the level colour (`QuotaLevel.tint`: red ≤ 5 %, orange < 30 %, green otherwise), the same thresholds as the app, from the shared code.
- **FR-W4.** Each row shows a progress bar of remaining % tinted with the level colour, as in `QuotaRow`.
- **FR-W5.** Small widget layout per row: badge · bar · %.
  - No vendor name: the badge identifies the vendor (FR-B3).
  - Up to 3 rows.
- **FR-W6.** Medium widget layout per row:
  - badge · name · plan · % on the first line;
  - the bar under it;
  - one secondary line: the pools when the vendor has more than one, then the reset time (e.g. 「所有模型 19% · Opus 88% · Sonnet 45% · 2 days, 11 hr後重置」), or just the reset time for single-pool vendors;
  - up to 3 rows.
  - The pool and reset lines from `QuotaRow` are merged here because separate lines don't fit three rows in the medium height (checked in a mock).
- **FR-W7.** The medium widget keeps the free-reset count (gift + number) when > 0, as today.
- **FR-W8.** The small widget keeps the footer 「更新於 … 前」 from the snapshot time. `[OPEN_QUESTION]` The medium widget has no room for it under three rows; the default is to drop it there, since the app and the small widget show freshness.
- **FR-W9.** The gallery description reads 「Claude Code、Codex、Cursor 的剩餘額度與免費重置。」.

## 5. Acceptance Criteria

### FR-W1
- **Given** a snapshot with Codex, Cursor and Claude Code in that stored order **When** the widget renders **Then** rows appear Claude Code, Codex, Cursor.
- **Given** Cursor at 0 % and Codex at 65 % **When** the widget renders **Then** Codex stays above Cursor (no urgency sort).

### FR-W2
- **Given** default text size **When** the small widget renders **Then** each badge shows its symbol (asterisk, `</>`, arrow pointer), never 「CC/CX/CU」.

### FR-W3 / FR-W4
- **Given** Claude Code at 19 % **When** the widget renders **Then** its % and bar are orange, matching the 額度 row.
- **Given** Cursor at 0 % **When** the widget renders **Then** its % is red and its bar is empty.

### FR-W5
- **Given** the small widget **When** it renders three vendors **Then** each row is badge, bar and % with no name text, and nothing is truncated with 「…」.

### FR-W6 / FR-W7
- **Given** Claude Code with pools 所有模型 19 %, Opus 88 %, Sonnet 45 % **When** the medium widget renders **Then** its row shows that pool line with each % in its own level colour.
- **Given** Codex with one pool **When** the medium widget renders **Then** no pool line is shown for Codex.
- **Given** Codex reports 2 free resets **When** the medium widget renders **Then** a green gift with 「2」 appears on the Codex row.
- **Given** 0 free resets **When** the medium widget renders **Then** no gift appears.

### FR-W8 / FR-W9
- **Given** a snapshot saved 3 minutes ago **When** the small widget renders **Then** the footer reads 「更新於 3 min前」 (system relative format).
- **Given** the widget gallery **When** the owner adds a widget **Then** the description lists Claude Code、Codex、Cursor in that order.

## 6. Edge Cases and Failure Modes

- **Case:** No snapshot yet (fresh install). **Behavior:** keep today's empty state (「AI 額度」 / 「開啟 App 以更新」), aligned to the top-leading corner.
- **Case:** Only one vendor configured. **Behavior:** one row, top-aligned, footer at the bottom; no empty placeholder rows.
- **Case:** A vendor's reset time is in the past (stale). **Behavior:** `ResetText` shows 「重置時間已過 · <date>」, as in the app.
- **Case:** Pool line too wide for the medium widget. **Behavior:** the pool figures truncate and the reset time stays whole at the end of the line; pool order is unchanged. It never wraps to a second line, because widget height is fixed.
- **Case:** Home Screen in Tinted or Clear mode (accented rendering). **Behavior:**
  - badge backgrounds and bars go monochrome as iOS renders them;
  - symbols still tell vendors apart (FR-B3);
  - % and text stay readable.
  - `[ASSUMPTION]` Bars and %s are marked `widgetAccentable()` so they take the accent tint.
- **Case:** Dark mode. **Behavior:** Codex's near-black badge gets its hairline border (FR-B edge case), as in the app.
- **Case:** Accessibility text sizes. **Behavior:** the medium widget drops the pool line before truncating vendor names; the small widget keeps badge and %, and the bar may shrink.

## 7. Non-Functional Requirements

- **Accessibility.**
  - Each row is one VoiceOver element reading 「<name>，剩餘 <n>%，<level>」, the same wording as `QuotaRow`'s value.
  - Colour is never the only cue, because % text is always shown.
- **Compatibility.** iOS 27.1. Renders on iPhone Duo outer (~466 pt) and inner (~951 pt) home screens and in light, dark and tinted modes.
- **Performance.** The view reads only the cached snapshot. No network or file work beyond `QuotaCache.load()` per timeline.

## 8. Dependencies

- The shared badge code (`OpenTokenUsage/Shared/ProviderBadge.swift`) is already compiled into the widget.
- Moving `QuotaLevel.tint`, `PoolSummary`, `ResetText` and the vendor order to `OpenTokenUsage/Shared/` needs no `project.yml` change, since that folder is already in both targets. A new file there needs `xcodegen generate`, which now keeps the signing team.

## 9. Risks and Mitigations

- **Risk:** Three rows still overflow the medium height (~155 pt) at larger text sizes. **Mitigation:**
  - the secondary line truncates and is the first thing dropped at accessibility sizes (see Edge Cases);
  - check on the Duo outer screen.
- **Risk:** The widget can't be checked on the simulator, because adding a widget needs home-screen taps and simulator input has been unreliable this session. **Mitigation:**
  - (as built) a unit test renders both sizes in light and dark from sample data to PNG (`WidgetAlignmentTests.testRenderWidgetSizes`; set `TEST_RUNNER_TEST_RENDER_DIR`). This replaces Xcode previews, because the sample data lives in the app target, not the widget;
  - the owner places the widget once on the simulator or a device for the final look.
- **Risk:** Moving `QuotaLevel.tint` and `PoolSummary` out of the app's view files breaks app code. **Mitigation:** move them without changes; build both schemes and run tests.

## 10. Open Questions

1. Small widget without vendor names. The default relies on badges alone, since that's what the new badges are for. The owner may prefer names, at the cost of truncation.
2. Should the small widget show the tightest pool's % (e.g. Claude Code 19 %) or the headline %? Default: the headline `remainingPercent`, same as the 額度 row.
3. Medium widget freshness footer (FR-W8). Default: dropped for room. Alternative: show it in place of the third row's secondary line.

## 11. Success Metrics

- **Leading:** at review, a side-by-side screenshot of the medium widget and the 額度 page shows matching badges, order, colours and figures for every vendor.
- **Lagging:** the owner checks quota from the widget instead of opening the app for routine looks. Informal, owner-reported.
