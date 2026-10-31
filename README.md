# OpenTokenUsage Web & AI 語音駕駛艙 (Cloudflare 邊緣原生版)

[![Production Release](https://img.shields.io/badge/Release-v1.2.0-blue.svg)](https://github.com/chenchihcu/opentokenusage-web)
[![Cloudflare Workers](https://img.shields.io/badge/Cloudflare-Workers%20%7C%20Durable%20Objects%20%7C%20D1-orange.svg)](https://workers.cloudflare.com/)
[![E2E Tests](https://img.shields.io/badge/Playwright-36%2F36%20Passed-brightgreen.svg)](tests/e2e.spec.ts)
[![Apple HIG](https://img.shields.io/badge/Design-Apple%20HIG%20%26%20W3C%20Foldable-purple.svg)](docs/rfc-apple-hig-foldable-onehanded.md)

全端現代化 AI 額度與訂閱監控駕駛艙，具備 **一頁式全景極簡監控 (One-Page High-Density Cockpit)**、**Apple HIG 折疊屏滿版與單手盲操標準 (W3C CSS Viewport Segments API)**、**Cloudflare 邊緣原生架構 (Workers + Durable Objects + D1 + KV)**、**Gemini 3.8 Live API 實時雙向語音對話**與**企業級 AI 供應商六大治理維度**。

- 🌐 **正式公網端點 (Edge Live)**：[https://opentokenusage-web.chihfu-chen-tw.workers.dev](https://opentokenusage-web.chihfu-chen-tw.workers.dev)
- 📦 **當前發布版本**：`v1.2.0` (Production Ready)

---

## 🌟 核心架構與功能特色

### 1. 一頁式全景極簡監控駕駛艙 (One-Page High-Density Cockpit)
- **原生輕量 SVG 環形圖表 (`MiniRingChart`)**：
  - 徹底捨棄肥厚第三方圖表庫（如 Chart.js/ECharts），以純原生 SVG `<circle>` + `stroke-dashoffset` 實現 60fps 動態環形儀表盤。
  - 支援 5 大平台專屬主題光譜漸變、剩餘額度微標籤與耗盡警戒動態呼吸脈動。
- **頂部 Governing Bottleneck 監控中樞**：
  - 置頂捕捉 5 大平台中最嚴格瓶頸池（Governing Bottleneck），即時呈現全系統耗盡計數與在線心跳。
- **徹底去文字化 (Zero Fluff)**：
  - 移除所有贅字說明與冗長教學段落，全數改以高信噪比之狀態指示燈、微標籤與等寬數字 (`font-mono tabular-nums`)，實現秒級狀態感知。
- **雙重視圖模式無縫切換 (`ViewModeSelector`)**：
  - 支援 `⊞ ALL` 一頁式全景矩陣（一次瀏覽 Cursor、Codex、Antigravity、Claude Code、Grok 全部平台）與 `▤ DUO` 雙欄深入工作台切換，支援 URL 深度連結（`?view=cockpit&duo=1`）與 `localStorage` 持久化。

### 2. Apple HIG 折疊屏滿版瀏覽與單手人體工學 (Foldable & One-Handed Ergonomics)
- **Apple HIG 觸控指標全面落地**：
  - 全域互動元件嚴格遵循 Apple 官方標準，最小點擊熱區 **`≥ 44 × 44 pt`**（CSS px），元件間距保持 **`≥ 8 pt`**。
- **W3C CSS Viewport Segments 原生雙屏避讓**：
  - **水平雙屏書本模式 (`horizontal-viewport-segments: 2`)**：自動分流為左屏 Cockpit 與右屏 Detail 工作台，並以 `calc(env(viewport-segment-left 1 0) - env(viewport-segment-right 0 0))` 自動計算硬體鉸鏈中縫，保證 0 數據落於物理折縫。
  - **垂直雙屏筆電/帳篷模式 (`vertical-viewport-segments: 2`)**：上半部為 Glance 監控中樞、下半部為 Touch 操控控制台。
- **150ms 姿態轉態防抖 (Posture Debounce)**：
  - 螢幕折疊展開、收合或橫豎旋轉時，防白屏並 100% 保持 WebSocket / Gemini 3.8 Live 語音連線不中斷。
- **單手握持自然拇指區下沉 (Bottom-Heavy Reachability)**：
  - 螢幕上半部 40% 規劃為 Glance 視覺監控區，下半部 60% 規劃為 Touch 容易觸及區。
- **左右手握持偏好自適應 (Handedness Ergonomics)**：
  - 支援右手模式 (`right`，預設右側貼靠)、左手模式 (`left`，左側貼靠) 與雙手模式 (`dual`，左右分置懸浮軌道)；點擊伴隨 `navigator.vibrate` 微震觸覺盲操反饋。
- **風險優先單手過濾晶片**：
  - 剩餘配額 $\le 5\%$ 之耗盡平台自動置頂下沉至拇指第一熱區，並提供 `[ ALL 5 | ⚠️ ALERTS ]` 單手大熱區過濾晶片。
- **思維鏈預算大熱區快選膠囊**：
  - 針對手機單手操作微調不易之痛點，提供 `0K`、`16K`、`32K`、`64K`、`100K (o3-mini 頂峰)` 五大專屬大觸控膠囊（`min-h-[44px]`）。
- **動態島與手勢條滿版避讓**：
  - 橫向握持時精準避讓 iOS 動態島 59px 原生安全邊距（`pl-safe-island pr-safe-island`）與底部手勢條（`pb-safe`）。

### 3. 平台多配額池獨立架構 (Multi-Token Pools)
- **多模型家族配額池獨立監控**：
  - 支援單一供應商多配額池（例如 Google Antigravity 內部的 Gemini Flash、Gemini Pro、Thinking 等獨立池；以及 Grok / Claude 獨立池）。
- **獨立重置週期與進度呈現**：
  - 各配額池擁有獨立之消耗進度、使用比例與重置時間視窗。
- **池級粒度配額硬阻斷 (Pool-Level Hard Stop)**：
  - 配額耗盡時精準針對單一配額池實施阻斷，防範單點耗盡擴散性盲區。

### 4. Cloudflare 邊緣原生架構 (Edge-Native Architecture)
- **Cloudflare Workers Static Assets**：
  - 前端採用 React 19 + Tailwind CJK + Lucide 靜態資產，經 Anycast 邊緣網絡全球就近分發。
- **Durable Objects (`VoiceSessionDO`)**：
  - 狀態化雙向 WebSocket 會話管理，結合 **WebSocket Hibernation API**，靜默零 CPU 計費，節省 90% 運算成本。
- **Cloudflare D1 SQL**：
  - 邊緣分散式關聯資料庫，儲存 `ai_usage_ledger` 用量帳本（含思維鏈 Thinking Tokens 追蹤）與平台 Quota。
- **Cloudflare KV (`MODEL_CATALOG_KV`)**：
  - 邊緣動態模型型錄快取。

### 5. Gemini 3.8 Live API 實時雙向語音
- **極低延遲音訊串流**：
  - 16kHz PCM 音訊上行 / 24kHz PCM 下行，支援即時字幕同步與語音非同步調用 MCP 工具查詢額度。
- **離屏 Canvas 波形動畫**：
  - 60 FPS 流暢聲波渲染，零 DOM Reflow 與 Layout Shift。

### 6. AI 供應商六大治理維度與 MCP 支援
- **AES-256-GCM** 金鑰加密儲存，前端展示時強制動態掩碼（如 `sk-ant-api...3f8a`）。
- **SSRF 嚴格白名單過濾器**，杜絕私有內網與本機位址滲透。
- **Quota Hard Stop** 每日累計額度硬阻斷機制，杜絕帳單爆發。
- **標準 MCP (Model Context Protocol) 工具集**：
  - `get_provider_quota`：查詢指定平台額度。
  - `list_active_models`：取得在線有效模型清單。
  - `estimate_token_cost`：試算 Token 與思維鏈成本。
  - `trigger_model_sync`：手動觸發模型型錄同步。

### 7. 自適應桌面帳號同步守護程式
- `scripts/sync-desktop-accounts.py` 與 `scripts/sync-desktop-daemon.py`。
- 本機桌面快取自適應增量推送，具備指數退避重試與邊緣安全 User-Agent 標頭防護。

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
├── docs/                                # 系統架構規格書 (SSOT RFCs)
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
│   │   │   ├── ViewModeSelector.tsx     # 雙手熱區切換器與慣用手偏置
│   │   │   ├── DetailWorkbench.tsx      # 去文字化工作台與思考預算熱區膠囊
│   │   │   ├── SplitViewContainer.tsx   # W3C 折疊屏雙視區避讓滿版容器
│   │   │   ├── FloatingActionToolbar.tsx# 懸浮操作軌道與動態島安全避讓
│   │   │   ├── AudioVisualizer.tsx      # 離屏 Canvas 語音動畫
│   │   │   └── FrequencySelector.tsx    # 自適應更新頻率選擇器
│   │   ├── App.tsx                      # 根組件與全域狀態持久化
│   │   └── main.tsx                     # 前端入口
│   ├── server/                          # 後端核心邏輯與 MCP 工具
│   │   ├── crypto/encryption.ts         # AES-256-GCM 加解密模組
│   │   ├── ledger/usage-ledger.ts       # 用量帳本與配額硬阻斷引擎
│   │   └── mcp/quota-mcp-server.ts      # MCP 標準工具集伺服器
│   ├── worker/                          # Cloudflare Workers 與 Durable Objects
│   │   ├── durable-objects/
│   │   │   └── VoiceSessionDO.ts        # 語音對話 Durable Object (Hibernation)
│   │   └── index.ts                     # Worker HTTP / WebSocket 路由分發
│   └── types/quota.ts                   # 共享型別契約 (DTO)
├── tests/
│   └── e2e.spec.ts                      # 36 項 Playwright 自動化端到端測試
├── package.json                         # 專案依賴與腳本定義 (v1.2.0)
├── playwright.config.ts                 # 跨平台測試配置 (Desktop & iPhone Duo)
├── tailwind.config.js                   # Tailwind 配置 (動態島與安全邊距)
├── vite.config.ts                       # Vite 構建配置
└── wrangler.jsonc                       # Cloudflare Workers & 綁定配置
```

---

## 🛡️ 治理與驗證狀態 (Verification Status)

- **靜態類型與構建驗證**：TypeScript 5.x 零錯誤，Vite 生產構建成功。
- **Playwright 自動化測試**：36 / 36 項測試全通（跨 `Desktop Chrome` 與 `iPhone Duo Landscape`）。
- **邊緣雲即時探針檢驗**：
  - HTML 端點：`HTTP 200 OK`
  - `/api/quotas` 端點：`HTTP 200 OK`，`API Success: True`
  - 5 大平台在線狀態：Cursor、Codex、Google Antigravity、Claude Code、Grok 5 大平台健康度 100%。
