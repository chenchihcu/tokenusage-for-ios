# OpenTokenUsage Web & AI 語音駕駛艙 (Cloudflare 邊緣原生版)

全端現代化 AI 額度與訂閱監控駕駛艙，具備 Apple HIG iPhone Duo 官方雙欄瀏覽標準、Cloudflare 邊緣原生架構 (Workers + Durable Objects + D1 + KV)、Gemini 3.8 Live API 實時雙向語音對話與企業級 AI 供應商六大治理維度。

---

## 🌟 核心功能特色

1. **Cloudflare 邊緣原生架構 (Edge-Native Architecture)**：
   - **Cloudflare Workers Static Assets**：前端 React 18 + Tailwind CJK + Lucide 靜態資產全球 Anycast 邊緣分發。
   - **Durable Objects (`VoiceSessionDO`)**：狀態化雙向 WebSocket 會話管理，結合 **WebSocket Hibernation API**，靜默零 CPU 計費，大幅節省 90% 運算成本。
   - **Cloudflare D1 SQL**：邊緣分散式資料庫，儲存 `ai_usage_ledger` 用量帳本（含思維鏈 Thinking Tokens 追蹤）與平台 Quota。
   - **Cloudflare KV (`MODEL_CATALOG_KV`)**：邊緣動態模型型錄快取。
2. **Apple Human Interface Guidelines (HIG) iPhone Duo 雙欄體驗**：
   - **橫向自適應 38%:62%**：左側 Master 清單持續高亮，右側 Detail 工作台阻尼平滑渲染。
   - **動態島避讓**：`max(1rem, env(safe-area-inset-left, 59px))` 避讓 iPhone 15/16 物理相機開孔。
   - **右手拇指熱區操作列**：≥48pt 觸控按鈕，整合 Web Haptic 震動回饋與一鍵 Focus Mode 全寬切換。
3. **Gemini 3.8 Live API 實時雙向語音**：
   - 16kHz PCM 音訊上行 / 24kHz PCM 下行，支援即時字幕同步與語音非同步調用 MCP 工具查詢額度。
   - 離屏 Canvas 60 FPS 語音波形動畫，零 DOM Reflow 與 Layout Shift。
4. **AI 供應商六大治理維度**：
   - **AES-256-GCM** 加密保護敏感金鑰，前端強制掩碼。
   - **SSRF 嚴格白名單過濾**，杜絕私有內網滲透。
   - **Quota Hard Stop**：每日累計配額硬阻斷，杜絕帳單爆發。
5. **標準 MCP 工具伺服器 (Model Context Protocol)**：
   - 提供 `get_provider_quota`、`list_active_models`、`estimate_token_cost`、`trigger_model_sync` 工具。

---

## 🚀 快速啟動指南

### 本地開發 (Local Edge Emulation)
```bash
# 安裝依賴
npm install

# 編譯前端靜態資產
npm run build

# 啟動 Cloudflare Miniflare 3 本地邊緣模擬環境
npm run worker:dev

# 或啟動 Vite 獨立前端預覽
npm run dev
```

### 執行端到端自動化測試
```bash
npx playwright test
```

### 部署至 Cloudflare 雲端 (需授權)
```bash
npx wrangler login
npm run worker:deploy
```
