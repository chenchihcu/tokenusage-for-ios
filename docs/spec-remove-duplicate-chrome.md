# Feature Spec: 拿掉重複的連線列、重置橫條與詳情尾綴

## 1. Summary

全景一屏上，連線狀態、免費重置和詳情尾綴各說了一次主列已經有的事。擁有者（唯一使用者）已勾選要拿掉：連線列（已同步、資料時間、重試）、免費重置橫條，以及雙欄詳情的方案名稱、連線文字和「已用／剩餘」。成功條件：iPhone Duo 橫向打開全景時，這五項不在畫面上，四個服務的名稱、模型、5 小時、每週和費用仍在同一屏。

## 2. Scope

**In scope**

- 主畫面不再畫連線列，也不再畫「重試」。
- 主畫面不再畫 Codex／Claude Code 的免費重置橫條。次數與倒數改由既有「重置」按鈕打開的面板閱讀。
- 雙欄詳情不再畫方案名稱、連線文字，以及「已用 N% · 剩餘 N%」。
- 跟著改的畫面測試與 `.ui-gate.json` 的就緒條件。

**Out of scope**

- 服務名稱、服務圖示、水位字（耗盡／偏低）、模型、5 小時、每週、費用、分組標籤、標題 OpenTokenUsage、全景／雙欄切換、快速操作（更新、重置、告警、設定）。
- 重置面板裡的次數與倒數、設定面板、API、額度解析、簽章與 iOS 原生 App。
- 把「未提供」改成空白。

## 3. User Stories

- 作為擁有者，我要主畫面不再重複連線與重置資訊，以便一屏只看各服務的模型、5 小時、每週和費用。
- 作為擁有者，我要在連線失敗時仍看到一句可讀的原因，以便知道該按「更新」。
- 作為擁有者，我要點「重置」仍能看到免費重置次數與倒數，以便橫條拿掉後這個資訊還在。

## 4. Functional Requirements

- **FR-1.** 同步成功時，主畫面不顯示連線列，也不顯示「已同步」、「資料時間」、「使用行動網路」、「重試」或「請稍候」。
- **FR-2.** [ASSUMPTION] 同步失敗、離線、登入失效、無權限或服務忙碌時，主畫面顯示 `presentStatus` 的那一句原因與既有的檢查提示；不顯示「重試」。重新取得資料只靠「更新」。
- **FR-3.** 主畫面不顯示區域「Codex 與 Claude Code 免費重置與重置時間」。點「重置」打開的面板仍列出各服務的免費重置次數、5 小時倒數與每週倒數。
- **FR-4.** 雙欄詳情只保留服務名稱、隱藏清單按鈕，以及模型、5 小時、每週、費用四格。不顯示方案名稱、連線文字，以及「已用／剩餘」。
- **FR-5.** 全景主列仍顯示四個服務的名稱、模型、5 小時已用、每週已用和費用。分組排序行為不變。
- **FR-6.** 空資料仍顯示「尚無額度資料」，且不出現百分比。讀取中仍顯示「正在讀取額度…」。

## 5. Acceptance Criteria

### FR-1

- **Given** 伺服器回了四個服務 **When** 打開 `/` **Then** 畫面上沒有「已同步」、「資料時間」和「重試」。
- **Given** 同上 **When** 打開 `/` **Then** 四個服務名稱仍然可見。

### FR-2

- **Given** `/api/quotas` 回 500 **When** 主畫面載入結束 **Then** 可見「服務忙碌，請稍後再試」或「無法連接服務，請稍後重試」，且沒有「重試」按鈕。
- **Given** 連線成功 **When** 主畫面顯示四個服務 **Then** 沒有連線列。

### FR-3

- **Given** 測試資料裡 Codex 有 1 次、Claude Code 有 0 次 **When** 主畫面打開且未點重置 **Then** 沒有「免費重置 1 次」這段橫條文字。
- **Given** 同上 **When** 點「重置」 **Then** 面板「免費重置與重置時間」同時看得到「免費重置 1 次」和「免費重置 0 次」。

### FR-4

- **Given** 寬螢幕雙欄且選中 Codex **When** 詳情出現 **Then** 看得到「Codex CLI & Cloud」、5 小時、每週和費用。
- **Given** 同上 **When** 詳情出現 **Then** 看不到方案名稱「Plus」、連線文字，也看不到「已用」和「剩餘」。

### FR-5

- **Given** 四個服務都在 **When** 點分組「每週」 **Then** Codex 仍排在第一個服務名稱。
- **Given** 只看告警 **When** 按下告警 **Then** Codex 仍在，Google Antigravity 不在。

### FR-6

- **Given** 伺服器回空陣列 **When** 打開 `/` **Then** 可見「尚無額度資料」，且沒有百分比。
- **Given** 請求尚未返回 **When** 主畫面還在等 **Then** 可見「正在讀取額度…」。

## 6. Edge Cases and Failure Modes

- **Case:** 後來的自動更新失敗，畫面上仍有上一筆四個服務。 **Behavior:** 顯示 FR-2 的失敗句，四個服務的上一筆數字留著，不改成空狀態。
- **Case:** Codex 或 Claude Code 不在這次回應裡。 **Behavior:** 重置面板只列實際回到的服務；主畫面本來就沒有重置橫條。
- **Case:** 免費重置次數是 0。 **Behavior:** 面板寫「免費重置 0 次」，不寫成空白。
- **Case:** 廠商沒給模型、5 小時、每週或費用。 **Behavior:** 主列與詳情四格仍寫「未提供」。
- **Case:** 短橫向螢幕裡重置或設定面板比 85dvh 高。 **Behavior:** 面板內容可直向捲動，完成按鈕留在面板頂端。主畫面本身不捲動。
- **Case:** 左手模式。 **Behavior:** 快速操作仍在左側；拿掉的五項在兩側都不出現。

## 7. Non-Functional Requirements

- **Performance.** 拿掉兩列後，iPhone Duo 橫向（852×393）主畫面 `scrollingElement` 的 `scrollHeight − clientHeight` ≤ 1。
- **Accessibility.** 失敗句是文字，不只靠顏色。留下的按鈕觸控區維持至少 44×44 CSS px。重置面板與設定面板的名稱不變。
- **Compatibility.** `/api/quotas` 的請求與回應不變。`planName` 仍留在客戶端資料列，只是詳情不畫。

## 8. Dependencies

- 現有 `presentStatus` 文案。就緒，不改句子。
- 現有「重置」按鈕與面板。就緒。
- UI gate 的頁面就緒條件目前是 `[role="status"]:has-text("已同步")`。這條會在實作時改成四個服務名稱可見；否則拿掉連線列後 gate 會一直等。

## 9. Risks and Mitigations

- **Risk:** e2e 與 flow 直接斷言可見的「已同步」和主畫面上的「免費重置 N 次」。 **Mitigation:** 同步成功改斷言四個服務名稱；重置次數改在打開面板後斷言。
- **Risk:** 視覺基準圖全部會變。 **Mitigation:** 實作後看 home、cockpit、split、left-hand、empty 的新圖，再 `--accept` 這五頁。
- **Risk:** 失敗句被一起拿掉，使用者不知道為何沒有新數字。 **Mitigation:** FR-2 保留失敗句。

## 10. Open Questions

_None._

## 11. Success Metrics

- **Leading:** 852×393 打開全景，DOM 裡沒有可見的「已同步」或主畫面重置橫條；點重置後面的面板仍有兩次免費重置文字。
- **Lagging:** 擁有者無須捲動主畫面，就能讀完四個服務的模型、5 小時、每週和費用。

## 12. Implementation plan

依序做，做完才跑 UI gate。不要先改基準圖。

1. `App.tsx`：同步成功時不掛 `ConnectionStatus`。失敗、離線、登入失效、無權限、服務忙碌時才掛，並拿掉其中的「重試」按鈕。卸下 `ResetMonitorBar`。重置面板與「重置」按鈕留著。
2. `DetailWorkbench.tsx`：刪方案名稱、`connectionLabel`、底部「已用／剩餘」。`SplitViewContainer.tsx` 不再傳 `connectionLabel`。
3. 測試：`tests/e2e.spec.ts`、`tests/flows/overview.flow.spec.ts`、`tests/flows/views.flow.spec.ts`、`tests/flows/sync-api.flow.spec.ts` 的成功斷言改看四個服務名稱。`tests/e2e.spec.ts` 與 `tests/flows/reset.flow.spec.ts` 先點「重置」，再在面板裡檢查「免費重置 1 次」和「免費重置 0 次」。
4. `.ui-gate.json` 的 home、cockpit、split、left-hand 就緒條件改成四個服務名稱都可見。empty 仍等「尚無額度資料」。
5. 跑 `node ~/.agents/skills/validate-app-ui/scripts/ui-gate.mjs`。G4 會因這五頁的預期改動失敗；看過 actual.png 後對 home、cockpit、split、left-hand、empty 執行 `--accept`，再跑一次完整 gate，直到 PASS。
6. 不改 `presentStatus` 的句子、不改 `/api/quotas`、不刪 `QuotaCardProps.planName`。

## 13. Architecture note

資料流不變：`useDirectInternet` 仍把額度交給 `App`，`buildAgentUsage` 仍產生主列與詳情四格。改變的是掛載點。`ConnectionStatus` 從常駐列變成失敗時才掛的一句。`ResetMonitorBar` 不再掛在主畫面；`creditsLabel` 與 `extractResetWindowSummary` 只留給重置面板。沒有 feature flag。要退回就還原這次的 UI 與測試變更。
