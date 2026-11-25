# OpenTokenUsage — AI 額度監控（iPhone Duo）

監控四個 AI 編程服務的剩餘額度與重置時間：**Codex、Claude Code、Cursor、Google Antigravity**。Codex 與 Claude Code 另顯示供應商給的**免費重置次數**。

## 這個 repo 裡有什麼

| 資料夾 | 是什麼 | 怎麼建置 |
|---|---|---|
| **`ios-native/`** | **iPhone App（正式版）**：原生 SwiftUI，iPhone Duo / iOS 27.1；App 內登入各服務、直接用手機網路更新、免費重置通知、主畫面小工具 | GitHub Actions `build-ios.yml`（xcode-27）產生未簽名 `.ipa`，以免費 Apple ID 側載；見 [`ios-native/README.md`](ios-native/README.md) |
| `src/` | 網站版（React）與 Cloudflare Worker API | `npm run build`、`npm run worker:deploy` |
| `scripts/` | 電腦端同步腳本：網站版資料，以及 iPhone App 的 Google Antigravity Mac 轉送（`relay-antigravity-mac.py`） | Python |
| `docs/` | 計畫、規格、研究紀錄 | — |

舊的 Capacitor 網頁外殼 App（`ios/`）已於 v1.4.0 移除，請只使用 `ios-native/`。

- 🌐 網站 / API：`https://opentokenusage-web.chihfu-chen-tw.workers.dev`
- 📦 網站版本：`v1.4.0`
- 🗺️ 計畫與規格：[`docs/plan-v3-native-duo.md`](docs/plan-v3-native-duo.md)、[`docs/spec-v3-native-duo.md`](docs/spec-v3-native-duo.md)

---

## 網站版功能

- **只顯示真實資料**：畫面只呈現 `/api/quotas` 回傳的資料；沒有資料時顯示「尚無額度資料」，不再有內建範例數字。
- **更新頻率**：15 秒 / 30 秒 / 1 分鐘 / 5 分鐘 / 15 分鐘 / 手動；App 在前景時依設定更新，背景由 iOS 決定。
- **免費重置監控**：Codex、Claude Code 顯示「免費重置 N 次」；供應商未提供時顯示「不提供」。重置時間已過但尚未有新資料時顯示「已到重置時間」，不再誤標 FREE。
- **右手快速操作（4 個圖示）**：更新、重置、告警（只看剩餘 ≤ 20%）、設定（更新頻率、慣用手）。左手模式移到左下，卡片內容不鏡像。
- **iPhone Duo 版面**：窄螢幕（外螢幕）單欄；寬螢幕（內螢幕）才出現「全景 / 雙欄」切換，雙欄為清單 + 詳情兩欄。內容可捲離快速操作列，不被遮住。
- **連線**：路徑由 iOS 選擇（Wi-Fi 或行動數據）；狀態列顯示「已同步 · 資料時間」或離線 / 錯誤原因與「重試」。

已移除：Gemini Live 語音與麥克風權限、Grok、模型型錄、思維鏈預算滑桿。

> **資料來源（網站版）**：Worker 的資料由電腦端 `scripts/sync-desktop-*.py` 上傳。iPhone App（`ios-native/`）直接向 Claude Code、Codex、Cursor 查詢；只有 Google Antigravity（手機無法登入）改讀 Mac 經 `scripts/relay-antigravity-mac.py` 上傳到 Worker 的資料。

---

## 📚 技術規格書與 RFC 索引 (RFCs)

本專案採規格驅動開發 (Specification-Driven Development)，所有架構決策與驗證標準均固化於以下 RFC 文件：

| RFC 編號 | 標題 | 領域 | 狀態 |
| :--- | :--- | :--- | :--- |
| **[RFC-001](docs/rfc-adaptive-network-sync.md)** | 連線感知與自適應頻率資料同步架構 | 桌面守護程式 / 邊緣同步 | `Implemented & Deployed` |
| **[RFC-002](docs/rfc-dashboard-onepage-viewmode.md)** | 一頁式極簡監控儀表板與 iPhone Duo 全覽視圖模式架構 | SVG 圖表 / 駕駛艙 / 視圖切換 | `Implemented & Deployed` |
| **[RFC-003](docs/rfc-multi-token-pools.md)** | 支援平台多配額池 (Multi-Token Pools) 與雙層瓶頸架構 | 多配額池 / 池級硬阻斷 | `Implemented & Deployed` |
| **[RFC-004](docs/rfc-apple-hig-foldable-onehanded.md)** | Apple HIG 折疊屏滿版瀏覽與單手人體工學架構 | W3C 折疊屏 / Apple HIG / 單手盲操 | `Implemented & Deployed` |

---

## 🚀 快速啟動指南

### 環境需求
- Node.js ≥ 18.0.0
- npm ≥ 9.0.0
- Python ≥ 3.10 (選用，執行桌面端同步守護程式時需要)

### 本地開發與邊緣模擬
```bash
# 1. 安裝依賴
npm install

# 2. 前端編譯構建
npm run build

# 3. 啟動 Vite 獨立前端開發伺服器
npm run dev

# 4. 啟動 Cloudflare Miniflare 3 本地邊緣模擬環境 (Workers + D1 + DO)
npm run worker:dev
```

### 執行端到端自動化測試 (Playwright E2E)
本專案配置桌面 Chrome 與 iPhone Duo 橫向雙視區並行測試：
```bash
# 執行全部 36 項自動化端到端測試
npx playwright test
```

### 部署至 Cloudflare Workers 邊緣雲
```bash
# 登入 Cloudflare CLI (初次使用)
npx wrangler login

# 發布靜態前端與 Worker 邊緣服務
npm run worker:deploy
```

---

## 📁 專案代碼結構導引

```text
opentokenusage-web/
├── ios-native/                          # iPhone App（SwiftUI，XcodeGen project.yml）
├── docs/                                # 計畫、規格與 RFC
│   ├── rfc-adaptive-network-sync.md     # RFC-001 連線感知自適應同步
│   ├── rfc-dashboard-onepage-viewmode.md# RFC-002 一頁式極簡駕駛艙
│   ├── rfc-multi-token-pools.md         # RFC-003 多配額池獨立架構
│   └── rfc-apple-hig-foldable-onehanded.md # RFC-004 Apple HIG 折疊屏單手盲操
├── migrations/                          # Cloudflare D1 SQL 遷移腳本
│   ├── 0001_init.sql                    # 基礎 Schema
│   ├── 0002_rich_account_metrics.sql    # 擴充指標
│   └── 0003_add_token_pools_json.sql    # 多配額池 JSON 支援
├── scripts/                             # 桌面端自動同步腳本與守護進程
│   ├── sync-desktop-accounts.py         # 桌面帳號資料同步器
│   ├── sync-desktop-daemon.py           # 背景自適應同步守護進程
│   └── install-sync-daemon.ps1          # Windows 排程自動安裝腳本
├── src/
│   ├── client/                          # 前端應用 (React 19 + Tailwind CJK)
│   │   ├── components/
│   │   │   ├── CockpitOverview.tsx      # 一頁式極簡全景駕駛艙 (Includes All)
│   │   │   ├── MiniRingChart.tsx        # 原生 SVG 60fps 動態環形儀表盤
│   │   │   ├── ViewModeSelector.tsx     # 全景 / 雙欄切換（僅寬螢幕）
│   │   │   ├── DetailWorkbench.tsx      # 服務詳情（數字、重置、免費重置）
│   │   │   ├── SplitViewContainer.tsx   # W3C 折疊屏雙視區避讓滿版容器
│   │   │   ├── FloatingActionToolbar.tsx# 右手 / 左手 4 個快速操作
│   │   │   ├── Sheet.tsx                # 重置與設定面板
│   │   │   └── FrequencySelector.tsx    # 自適應更新頻率選擇器
│   │   ├── App.tsx                      # 根組件與全域狀態持久化
│   │   └── main.tsx                     # 前端入口
│   ├── server/                          # 後端核心邏輯與 MCP 工具
│   │   ├── crypto/encryption.ts         # AES-256-GCM 加解密模組
│   │   ├── ledger/usage-ledger.ts       # 用量帳本與配額硬阻斷引擎
│   │   └── mcp/quota-mcp-server.ts      # MCP 標準工具集伺服器
│   ├── worker/                          # Cloudflare Worker
│   │   └── index.ts                     # Worker HTTP 路由
│   └── types/quota.ts                   # 共享型別契約 (DTO)
├── tests/
│   ├── e2e.spec.ts                      # Playwright UI 與後端測試
│   └── direct-internet.spec.ts          # 網路層測試
├── package.json                         # 專案依賴與腳本定義 (v1.4.0)
├── playwright.config.ts                 # 跨平台測試配置 (Desktop & iPhone Duo)
├── tailwind.config.js                   # Tailwind 配置 (動態島與安全邊距)
├── vite.config.ts                       # Vite 構建配置
└── wrangler.jsonc                       # Cloudflare Workers & 綁定配置
```

---

## 🛡️ 驗證狀態

- **iPhone App**：GitHub `xcode-27` runner（Xcode 27.1、iOS 27.1 SDK、iPhone Duo 模擬器）上編譯與單元測試通過；尚未在實機執行。
- **網站版（v1.4.0）**：`tests/e2e.spec.ts`、`tests/direct-internet.spec.ts` 68 / 68 通過（Chromium，Desktop 與 iPhone Duo 尺寸估算值）。前端 TypeScript 無錯誤；`src/worker`、`src/server` 有既存型別錯誤。
- 正式環境尚未部署 v1.3.0 之後的 Worker；部署需移除 `VoiceSessionDO`（`wrangler.jsonc` migration `v2`）。
