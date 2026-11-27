---
name: verify-mac
description: Verify OpenTokenUsage on this Mac — TypeScript, web build, Worker bundle, Playwright and Python tests, plus the native iOS app (xcodegen, XCTest on an iPhone Duo simulator, light/dark/landscape screenshots). Use after changing src/, tests/, scripts/ or ios-native/, before saying a change works. In the Linux cloud container use the `verify` skill instead.
---

# Verify on a Mac

All gates live in one script, so Claude and people run the same checks. From the repo root:

```bash
scripts/verify-mac.sh web      # tsc, vite build, Worker bundle (dry run), Playwright, scripts/test_*.py
scripts/verify-mac.sh ios      # xcodegen, then XCTest on the dedicated simulator
scripts/verify-mac.sh shots    # build, then portrait dark/light + landscape dark, every display
scripts/verify-mac.sh          # all of the above
```

Pick the narrowest target that covers the change: `web` for `src/`, `tests/` or `scripts/`;
`ios` for `ios-native/`; add `shots` for any visible iOS change. Measured on this Mac
(2026-11-27): `web` about 6 s; the first `ios` run about 20 min (simulator creation plus a cold
build); `shots` alone about 7 min. Run `ios` and `shots` in the background.

## Reading the result

- The summary lists each gate as PASS, FAIL or BLOCKED, with its log. Each run keeps
  `logs/`, `test.xcresult`, `shots/` and `worker-bundle/` under
  `~/Library/Caches/otu-verify/runs/<time>/`.
- Exit code: 0 all passed, 1 a gate failed, 2 nothing failed but a gate was blocked.
- Quote the summary's `Gate:` line as the highest gate reached. Per
  `docs/plan-v3-native-duo.md`, nothing is "verified" below G2, and the script never covers
  G4 (posture matrix) or G5 (device).
- BLOCKED is not a pass. Report it with the fix it names. Playwright's Chromium is a one-time
  download (`npx playwright install chromium`): ask the person before running it.
- A FAIL in a gate your change doesn't touch may predate it: check the same gate on the base
  commit before blaming the change, and report it either way. As of 2026-11-27, `tsc` fails on
  `origin/main` with 2 errors in `src/worker/index.ts` (Workers types not in `tsconfig.json`).

## Screenshots and postures

- Everything runs on a dedicated simulator, "OTU Verify" (an iPhone Duo), created on first use.
  Never point the script at the person's own simulator: it uninstalls the app and turns on
  sample data (`opentokenusage_sample_data`).
- GUI changes need before/after images of the same element and view: run `shots` before
  editing and again after, open both sets of PNGs, and compare. Copy the ones you cite to
  `docs/evidence/<date>-<feature>/`.
- A new Duo simulator starts with only the outer display lit, so the inner display's frames are
  all black. The script moves them to `shots/unlit/`; don't cite those. The gate fails if no
  lit frame was captured.
- The script does not move the Duo hinge. For posture evidence (G4), use the iOS Simulator tool on
  device "OTU Verify": `set_posture` closed / half_open / open, then `screenshot`, after a
  `shots` run has installed the app with sample data. Set `OTU_KEEP_SIM=1` so the script
  leaves the simulator booted.

## Gotchas

- `ios-native/*.xcodeproj` is generated and ignored (`ios-native/.gitignore`). Edit
  `ios-native/project.yml`; the script regenerates the project on every iOS run.
- Builds use `CODE_SIGNING_ALLOWED=NO`, as CI does, so the App Group shared with the widget is
  not exercised. Widget behaviour needs a device (G5).
- DerivedData lives in the cache folder, not in the repo (`ios-native/build` is not ignored).
- The Worker gate only bundles (`wrangler deploy --dry-run`); it uploads nothing. For API
  behaviour against a local D1, run the Worker from `.claude/launch.json` ("worker", port 8787)
  and follow the `verify` skill's Worker steps.
- If the first frame isn't ready when a screenshot is taken, raise `OTU_SHOT_WAIT` (default 12 s).
