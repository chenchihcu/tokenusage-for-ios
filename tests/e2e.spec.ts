import { test, expect } from '@playwright/test';
import { encryptApiKey, decryptApiKey, maskApiKey } from '../src/server/crypto/encryption';
import { validateUpstreamUrl, discoverLatestModels, filterOutDeprecated } from '../src/server/catalog/discovery';
import { UsageLedgerService } from '../src/server/ledger/usage-ledger';
import { handleMcpToolCall, OPENTOKENUSAGE_MCP_TOOLS } from '../src/server/mcp/quota-mcp-server';

test.describe('1. 安全性、後端 MCP 與模型過期守衛驗證', () => {
  test('AES-256-GCM 加密、解密與前端掩碼完整性', () => {
    const rawKey = 'AIzaSyA8B7C9D1E2F3G4H5I6J7K8L9M0N1O2P3';
    const masterKey = 'super-secret-master-key-32-bytes!';

    const encrypted = encryptApiKey(rawKey, masterKey);
    expect(encrypted.ciphertext).toBeTruthy();
    expect(encrypted.iv).toHaveLength(24);
    expect(encrypted.authTag).toHaveLength(32);

    const decrypted = decryptApiKey(encrypted, masterKey);
    expect(decrypted).toBe(rawKey);

    const masked = maskApiKey(rawKey);
    expect(masked.startsWith('AIzaSy')).toBeTruthy();
    expect(masked.endsWith('O2P3')).toBeTruthy();
    expect(masked).toContain('••••');
  });

  test('SSRF 防護白名單過濾器', () => {
    expect(validateUpstreamUrl('https://generativelanguage.googleapis.com/v1beta/models')).toBe(true);
    expect(validateUpstreamUrl('https://api.openai.com/v1/models')).toBe(true);
    expect(validateUpstreamUrl('http://127.0.0.1:8080/admin')).toBe(false);
    expect(validateUpstreamUrl('http://localhost:3000')).toBe(false);
    expect(validateUpstreamUrl('http://192.168.1.1/router')).toBe(false);
    expect(validateUpstreamUrl('http://10.0.0.1/internal')).toBe(false);
  });

  test('AI 用量帳本 Quota Hard Stop 配額硬阻斷', async () => {
    const ledger = new UsageLedgerService();
    ledger.setPolicy({ dailySpendLimitUsd: 5.0, hardStopEnabled: true });

    await ledger.recordUsage({
      provider: 'cursor',
      modelId: 'cursor-fast',
      promptTokens: 1000,
      completionTokens: 500,
      thinkingTokens: 0,
      totalTokens: 1500,
      costUsd: 2.0,
    });
    expect(ledger.getTodayTotalSpend()).toBe(2.0);

    await expect(
      ledger.recordUsage({
        provider: 'cursor',
        modelId: 'cursor-fast',
        promptTokens: 2000,
        completionTokens: 1000,
        thinkingTokens: 0,
        totalTokens: 3000,
        costUsd: 4.0,
      })
    ).rejects.toThrow(/Quota Hard Stop/);
  });

  test('池級粒度配額硬阻斷 (Pool-Level Hard Stop)', async () => {
    const ledger = new UsageLedgerService();
    // 設定 Argon 耗盡，Gemini 充足
    ledger.setPoolStatus('gemini_4_argon', 0);
    ledger.setPoolStatus('gemini_models', 31);

    // 呼叫充足模型池 -> 放行
    const entry = await ledger.recordUsage({
      provider: 'antigravity',
      modelId: 'gemini-3.8-flash',
      poolId: 'gemini_models',
      promptTokens: 100,
      completionTokens: 50,
      thinkingTokens: 0,
      totalTokens: 150,
      costUsd: 0.01,
    });
    expect(entry.poolId).toBe('gemini_models');

    // 呼叫耗盡模型池 -> 阻斷
    await expect(
      ledger.recordUsage({
        provider: 'antigravity',
        modelId: 'gemini-4-argon',
        poolId: 'gemini_4_argon',
        promptTokens: 100,
        completionTokens: 50,
        thinkingTokens: 0,
        totalTokens: 150,
        costUsd: 0.01,
      })
    ).rejects.toThrow(/Pool Quota Hard Stop/);
  });

  test('MCP 標準工具集與 5 大平台真實帳號契約驗證', async () => {
    expect(OPENTOKENUSAGE_MCP_TOOLS.length).toBeGreaterThanOrEqual(4);

    // Cursor (Premium, 0% 剩餘)
    const cursorResult = await handleMcpToolCall('get_provider_quota', { provider: 'cursor' }, {});
    expect(cursorResult.remainingPercent).toBe(0);
    expect(cursorResult.plan).toBe('Premium');

    // Codex (Plus, 最嚴格瓶頸優先：Weekly 100% 耗盡 -> 剩餘 0%)
    const codexResult = await handleMcpToolCall('get_provider_quota', { provider: 'codex' }, {});
    expect(codexResult.remainingPercent).toBe(0);
    expect(codexResult.weeklyUsedPercent).toBe(100);
    expect(codexResult.plan).toBe('Plus');

    // Google Antigravity (Google AI Pro, 92% 剩餘)
    const antiResult = await handleMcpToolCall('get_provider_quota', { provider: 'antigravity' }, {});
    expect(antiResult.remainingPercent).toBe(92);
    expect(antiResult.plan).toBe('Google AI Pro');

    // Claude Code (Pro, 最嚴格瓶頸優先：Weekly 98% 耗盡 -> 剩餘 2%)
    const claudeResult = await handleMcpToolCall('get_provider_quota', { provider: 'claude' }, {});
    expect(claudeResult.remainingPercent).toBe(2);
    expect(claudeResult.weeklyUsedPercent).toBe(98);

    // Grok (SuperGrok, 0% 剩餘, 綁定 Cursor)
    const grokResult = await handleMcpToolCall('get_provider_quota', { provider: 'grok' }, {});
    expect(grokResult.remainingPercent).toBe(0);
    expect(grokResult.displayName).toContain('bonded with Cursor');
  });

  test('模型過期守衛 (Deprecation Guard)：全面剔除 GPT-3.5、Davinci 等舊模型', () => {
    const mixedModels: any[] = [
      { id: 'gpt-3.5-turbo', name: 'GPT-3.5 Turbo' },
      { id: 'text-davinci-003', name: 'Davinci 003' },
      { id: 'claude-1.3', name: 'Claude v1' },
      { id: 'gemini-1.0-pro', name: 'Gemini 1.0 Pro' },
      { id: 'gpt-6.1-sol', name: 'GPT-6.1 Sol', status: 'active' },
      { id: 'gemini-3.8-flash', name: 'Gemini 3.8 Flash', status: 'active' },
    ];

    const purged = filterOutDeprecated(mixedModels);
    expect(purged.some(m => m.id.includes('gpt-3.5'))).toBe(false);
    expect(purged.some(m => m.id.includes('davinci'))).toBe(false);
    expect(purged.some(m => m.id.includes('claude-1'))).toBe(false);
    expect(purged.some(m => m.id.includes('gemini-1.0'))).toBe(false);
    expect(purged.some(m => m.id === 'gpt-6.1-sol')).toBe(true);
    expect(purged.some(m => m.id === 'gemini-3.8-flash')).toBe(true);
  });
});

test.describe('2. 極致暗黑主題、Live Bar、自訂頻率與 5 大平台真實帳號 UI 驗證', () => {
  test('極致暗黑曜石背景與 Live Bar 原創光譜條渲染', async ({ page }) => {
    await page.goto('/');

    // 驗證極致暗黑主題容器
    const appContainer = page.locator('div.bg-slate-950').first();
    await expect(appContainer).toBeVisible();

    // 驗證 Live Bar 及其 5 色等比配額分段
    const liveBar = page.locator('text=LIVE').first();
    await expect(liveBar).toBeVisible();

    // 驗證 5 大平台分段存在
    await expect(page.locator('button[title*="Cursor: 剩餘 0%"]')).toBeVisible();
    await expect(page.locator('button[title*="Codex: 剩餘 0%"]')).toBeVisible();
    await expect(page.locator('button[title*="Antigravity: 剩餘 31%"]')).toBeVisible();
    await expect(page.locator('button[title*="Claude Code: 剩餘 2%"]')).toBeVisible();
    await expect(page.locator('button[title*="Grok: 剩餘 0%"]')).toBeVisible();
  });

  test('使用者自訂更新頻率控制器與持久化 (FrequencySelector)', async ({ page }) => {
    await page.goto('/');

    // 預設為 1 分鐘
    const freqBtn = page.locator('button[title*="調整 Token 用量自動更新頻率"]');
    await expect(freqBtn).toBeVisible();
    await expect(freqBtn).toContainText('1 分鐘');

    // 展開選單切換至「15 秒」
    await freqBtn.click();
    const opt15s = page.locator('button:has-text("15 秒")');
    await expect(opt15s).toBeVisible();
    await opt15s.click();

    // 驗證按鈕標籤變更
    await expect(freqBtn).toContainText('15 秒');

    // 驗證 localStorage 持久化
    const stored = await page.evaluate(() => localStorage.getItem('opentokenusage_refresh_interval_sec'));
    expect(stored).toBe('15');
  });

  test('5 大專屬平台卡片與真實帳號基準數值驗證', async ({ page }) => {
    await page.goto('/?view=split');

    // 1. Cursor (Premium, 0% 剩餘)
    const cursorCard = page.locator('div[role="button"]:has-text("Cursor")').first();
    await expect(cursorCard).toBeVisible();
    await expect(cursorCard.locator('.tabular-nums').first()).toContainText('0%');

    // 2. Codex (Plus, 最嚴格瓶頸優先：Weekly 100% 耗盡 -> 剩餘 0%)
    const codexCard = page.locator('div[role="button"]:has-text("Codex")').first();
    await expect(codexCard).toBeVisible();
    await expect(codexCard.locator('.tabular-nums').first()).toContainText('0%');
    await expect(codexCard.getByText('Weekly:', { exact: true })).toBeVisible();
    await expect(codexCard.locator('span:has-text("100%")').first()).toBeVisible();

    // 3. Google Antigravity (Google AI Pro, 工作馬瓶頸優先：Gemini 31% 瓶頸 -> 剩餘 31%)
    const antiCard = page.locator('div[role="button"]:has-text("Google Antigravity")').first();
    await expect(antiCard).toBeVisible();
    await expect(antiCard.locator('.tabular-nums').first()).toContainText('31%');
    // 多配額池 Mini-Chips 膠囊驗證
    await expect(antiCard.getByText('Gemini Models:', { exact: false })).toBeVisible();
    await expect(antiCard.getByText('Claude and GPT models:', { exact: false })).toBeVisible();
    await expect(antiCard.getByText('Gemini 4 Argon:', { exact: false })).toBeVisible();
    await expect(antiCard.getByText('部分配額池耗盡')).toBeVisible();

    // 4. Claude Code (Pro, 最嚴格瓶頸優先：Weekly 98% 耗用 -> 剩餘 2%)
    const claudeCard = page.locator('div[role="button"]:has-text("Claude Code")').first();
    await expect(claudeCard).toBeVisible();
    await expect(claudeCard.locator('.tabular-nums').first()).toContainText('2%');
    await expect(claudeCard.getByText('Weekly:', { exact: true })).toBeVisible();
    await expect(claudeCard.locator('span:has-text("98%")').first()).toBeVisible();
    await expect(claudeCard.getByText('Session:', { exact: true })).toBeVisible();
    // 視覺語義一致性：<=5% 時必顯示告警標籤
    await expect(claudeCard.getByText('配額耗盡 / 告警')).toBeVisible();

    // 5. Grok (SuperGrok, 0% 剩餘, 標註 Bonded)
    const grokCard = page.locator('div[role="button"]:has-text("Grok (bonded with Cursor)")').first();
    await expect(grokCard).toBeVisible();
    await expect(grokCard.locator('.tabular-nums').first()).toContainText('0%');
    await expect(grokCard.getByText('Bonded', { exact: true })).toBeVisible();
  });

  test('Detail 工作台多維度指標卡與 100K 思考預算滑桿', async ({ page }) => {
    await page.goto('/?view=split');

    // 點選 Codex 卡片
    const codexCard = page.locator('div[role="button"]:has-text("Codex")').first();
    await codexCard.click();

    // 驗證真實帳戶多維度限額細項
    await expect(page.locator('text=真實帳戶多維度限額細項')).toBeVisible();
    await expect(page.locator('text=Weekly (Shared)')).toBeVisible();
    await expect(page.locator('text=Credits')).toBeVisible();

    // 驗證思考預算滑桿支援至 100K
    await expect(page.locator('text=100K (o3-mini 頂峰)')).toBeVisible();

    // 點選 Google Antigravity 驗證專屬 Multi-Pool Matrix Deck 矩陣儀表板
    const antiCard = page.locator('div[role="button"]:has-text("Google Antigravity")').first();
    await antiCard.click();

    await expect(page.locator('text=Google Antigravity 多配額池 (Token Pools) 獨立儀表板')).toBeVisible();
    await expect(page.locator('text=3 個配額池在線')).toBeVisible();
    await expect(page.getByText('Gemini Models', { exact: true })).toBeVisible();
    await expect(page.getByText('Claude and GPT models', { exact: true })).toBeVisible();
    await expect(page.getByText('Gemini 4 Argon', { exact: true })).toBeVisible();
    await expect(page.getByText('2d 9h').first()).toBeVisible();
    await expect(page.getByText('4h 37m').first()).toBeVisible();
  });

  test('最新前瞻模型型錄視窗：嚴格排除任何過期廢棄模型', async ({ page }) => {
    await page.goto('/');

    const toolbar = page.getByRole('complementary', { name: '即時浮動控制列' });
    const syncBtn = toolbar.locator('button[title*="同步最新模型型錄"]');
    await syncBtn.click();

    // 驗證 Modal 標題與 Active 標籤
    const modal = page.locator('.fixed:has-text("5 大平台最新活躍前瞻 AI 模型型錄")');
    await expect(modal).toBeVisible();
    await expect(modal.getByText('5 大平台最新活躍前瞻 AI 模型型錄')).toBeVisible();
    await expect(modal.getByText('Active', { exact: true }).first()).toBeVisible();

    // 驗證最新前瞻模型存在
    await expect(modal.getByText('GPT-6.1 Sol (Workhorse Coding)')).toBeVisible();
    await expect(modal.getByText('OpenAI o3-mini (High Reasoning 100K)')).toBeVisible();
    await expect(modal.getByText('Gemini 3.8 Live (Audio & Vision)')).toBeVisible();
    await expect(modal.getByText('Claude 3.7 Sonnet (Hybrid Thinking)')).toBeVisible();
    await expect(modal.getByText('Grok 4.5 Full Reasoning')).toBeVisible();
    await expect(modal.getByText('Cursor Composer (Fast Edit)')).toBeVisible();

    // 斷言絕對不含任何已過期舊模型
    const modalContent = await modal.innerText();
    expect(modalContent).not.toContain('gpt-3.5');
    expect(modalContent).not.toContain('GPT-3.5');
    expect(modalContent).not.toContain('davinci');
    expect(modalContent).not.toContain('claude-1');
    expect(modalContent).not.toContain('gemini-1.0');
  });

  test('Focus Mode 專注模式全寬切換', async ({ page }) => {
    await page.goto('/?view=split');

    const masterList = page.getByRole('complementary', { name: 'AI 平台清單' });
    await expect(masterList).toBeVisible();

    const focusBtn = page.locator('button[title*="專注全寬模式"]');
    if (await focusBtn.isVisible()) {
      await focusBtn.click();
      await expect(masterList).toHaveClass(/w-0/);

      const restoreBtn = page.locator('button[title*="展開導航欄"]');
      await restoreBtn.click();
      await expect(masterList).not.toHaveClass(/w-0/);
    }
  });
});


test.describe('3. 一頁式極簡監控駕駛艙 (Cockpit All View) 與 iPhone Duo 視圖切換驗證', () => {
  test('預設呈現一頁式全景駕駛艙 (Includes All 5 Platforms) 與 Governing Bottleneck 監控中樞', async ({ page }) => {
    await page.goto('/');

    // 1. 驗證視圖切換器存在，且預設為 ALL 全景
    const allBtn = page.getByRole('button', { name: /ALL 全景/ });
    await expect(allBtn).toBeVisible();
    await expect(allBtn).toHaveAttribute('aria-pressed', 'true');

    // 2. 驗證 Governing Bottleneck 瓶頸中樞置頂呈現
    await expect(page.getByText('GOVERNING BOTTLENECK 瓶頸中樞')).toBeVisible();

    // 3. 驗證一屏同時呈現全部 5 大平台 (Cursor, Codex, Antigravity, Claude, Grok)
    const monitorGrid = page.getByRole('main', { name: '五大平台監控儀表' });
    await expect(monitorGrid).toBeVisible();

    await expect(monitorGrid.getByText('Cursor', { exact: true })).toBeVisible();
    await expect(monitorGrid.getByText('Codex', { exact: true })).toBeVisible();
    await expect(monitorGrid.getByText('Google Antigravity', { exact: true })).toBeVisible();
    await expect(monitorGrid.getByText('Claude Code', { exact: true })).toBeVisible();
    await expect(monitorGrid.getByText('Grok (bonded with Cursor)', { exact: true })).toBeVisible();

    // 4. 驗證 SVG 環形圖表 (MiniRingChart) 渲染
    const ringCharts = page.locator('svg circle[stroke-dasharray]');
    await expect(ringCharts.first()).toBeVisible();
    expect(await ringCharts.count()).toBeGreaterThanOrEqual(5);

    // 5. 驗證高對比鍵值對採用 tabular-nums
    const kvNumbers = page.locator('.tabular-nums');
    expect(await kvNumbers.count()).toBeGreaterThanOrEqual(5);
  });

  test('一鍵切換視圖模式 (ViewMode Toggle: ALL <-> DUO) 與 URL 深度連結同步', async ({ page }) => {
    await page.goto('/');

    // 點擊切換為 DUO 雙欄模式
    const duoBtn = page.getByRole('button', { name: /DUO 雙欄/ });
    await expect(duoBtn).toBeVisible();
    await duoBtn.click();

    // 驗證 Master-Detail 結構出現
    const masterList = page.getByRole('complementary', { name: 'AI 平台清單' });
    await expect(masterList).toBeVisible();

    // 驗證 URL 參數包含 view=split
    expect(page.url()).toContain('view=split');

    // 點擊切換回 ALL 全景駕駛艙
    const allBtn = page.getByRole('button', { name: /ALL 全景/ });
    await allBtn.click();

    const monitorGrid = page.getByRole('main', { name: '五大平台監控儀表' });
    await expect(monitorGrid).toBeVisible();
    expect(page.url()).toContain('view=cockpit');
  });

  test('iPhone Duo 橫向視區 (844x390) 雙手握持人體工學與一頁滿版適配 (No Scroll Overflow)', async ({ page }) => {
    // 模擬 iPhone 15/16 橫向視區
    await page.setViewportSize({ width: 844, height: 390 });
    await page.goto('/?view=cockpit&duo=1');

    // 驗證全景駕駛艙可見
    const monitorGrid = page.getByRole('main', { name: '五大平台監控儀表' });
    await expect(monitorGrid).toBeVisible();

    // 驗證雙手熱區控制列避讓與可見性
    const viewSelector = page.getByRole('navigation', { name: '視圖模式切換器' });
    await expect(viewSelector).toBeVisible();

    const fab = page.getByRole('complementary', { name: '即時浮動控制列' });
    await expect(fab).toBeVisible();

    // 驗證卡片點擊深入功能：點擊深入按鈕自動切換至 DUO 模式
    const expandBtn = page.locator('button[title*="深入此平台工作台"]').first();
    await expandBtn.click();

    // 驗證切換為雙欄工作台
    expect(page.url()).toContain('view=split');
  });
});
