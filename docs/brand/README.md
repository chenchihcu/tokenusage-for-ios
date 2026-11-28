# Official Brand Logo Sources

These committed SVGs are the single source of truth for the Codex and Google Antigravity vendor badges across web and iOS (app + widget):

- `codex.svg` — OpenAI Codex product mark (blue-to-purple gradient blob with `>_`), normalized from `@lobehub/icons-static-svg` (`codex-color.svg`, white backdrop path removed so the badge tile provides the neutral background).
- `antigravity.svg` — Google Antigravity arch / "A" multicolor mark, normalized from `@lobehub/icons-static-svg` (`antigravity-color.svg`).

## Derived outputs

- **Web:** inline SVG inside `src/client/components/PlatformIcon.tsx` (per-instance IDs via React `useId()` so gradients, masks, and filters never collide across multiple cards).
- **iOS (app + widget):** `ios-native/OpenTokenUsage/Shared/BrandLogos.xcassets` (`logo-codex`, `logo-antigravity`), exported as 512 × 512 transparent PNGs via:

```bash
node scripts/render-brand-logos.mjs
```

> Note: Owner explicitly approved bundling the official Codex and Google Antigravity marks (accepting trademark risk) in `docs/spec-vendor-badges-app-icon.md`.
