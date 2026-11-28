# Project Rules (`tokenusage`)

> 本檔記錄僅適用本專案的執行與驗證紅線；跨專案與核心規範見全域 `00-core-rules` 與 [CLAUDE.md](CLAUDE.md)。

## Web UI Acceptance Gate (`.ui-gate.json`)

- **規則**：不要同時執行 `npm run verify:ui`（`ui-gate.mjs`）與 `xcodebuild` / `scripts/verify-mac.sh ios`；先等其中一個完成再跑另一個。
  - **檢查**：`.ui-gate/result.json` 的 `env.load1 <= env.cpus * 3`，且未出現 `runner-timeout` / `exit timeout`。
  - **出處**：`f94cdb8c`（`2026-11-28T04-04` `load1=568.7`）、`1a419a2a`（`2026-11-28T05-02` `load1=243.8`）。

- **規則**：不要直接對 `.ui-gate/run/playwright.gate.config.mjs` 執行 `--update-snapshots=all` 覆寫 `tests/ui-baseline/`；有意圖的視覺改動必須先建立並鎖定 `.ui-gate/intent.json`（`--lock-intent`），檢視報告差異後再執行 `--accept <p1,p2>` 或 `--accept-intended`。
  - **檢查**：`git diff` 若含 `tests/ui-baseline/*.png`，`.ui-gate/intent.lock.json` 必須存在且與 `.ui-gate/intent.json` SHA-256 一致。
  - **出處**：`1a419a2a`（`task-208`、`task-212`、`task-284`）。

## Git & Worker Release Guards

- **規則**：在已有其他未提交修改的工作樹中執行針對性 `git add <path>` 前，先檢查 `git diff <path>`，確認不夾帶本次任務以外的未審查改動。
  - **檢查**：`git diff --cached --stat` 只含本次審查範圍的檔案與區塊。
  - **出處**：`2dc14202`（2026-11-28，commit `896128c` 夾帶前置工作樹改動）。

- **規則**：`src/worker/index.ts` 新增任何會寫入 KV/D1 或強制觸發上游 API 的端點或參數（例如 `POST /api/models/sync`、`?force=true`）時，必須套用 `bearerMatches(request, env.SYNC_TOKEN)` 驗證。
  - **檢查**：未攜帶有效 `Authorization: Bearer` 呼叫上述路由回傳 `401`，且已納入 `tests/flows/sync-api.flow.spec.ts`。
  - **出處**：`2dc14202`（2026-11-28 release audit）。
