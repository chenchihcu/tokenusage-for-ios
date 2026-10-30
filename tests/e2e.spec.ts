import { test, expect } from '@playwright/test';
import { encryptApiKey, decryptApiKey, maskApiKey } from '../src/server/crypto/encryption';
import { validateUpstreamUrl, discoverLatestModels } from '../src/server/catalog/discovery';
import { UsageLedgerService } from '../src/server/ledger/usage-ledger';
import { handleMcpToolCall, OPENTOKENUSAGE_MCP_TOOLS } from '../src/server/mcp/quota-mcp-server';

test.describe('1. 安全性與後端 MCP 核心單元驗證', () => {
  test('AES-256-GCM 加密、解密與前端掩碼完整性', () => {
    const rawKey = 'AIzaSyA8B7C9D1E2F3G4H5I6J7K8L9M0N1O2P3';
    const masterKey = 'super-secret-master-key-32-bytes!';

    const encrypted = encryptApiKey(rawKey, masterKey);
    expect(encrypted.ciphertext).toBeTruthy();
    expect(encrypted.iv).toHaveLength(24); // 12 bytes hex
    expect(encrypted.authTag).toHaveLength(32); // 16 bytes hex

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

    // 正常記錄 $2.0
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

    // 超額調用 ($4.0，累計達 $6.0 > $5.0) 應觸發硬阻斷
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

  test('MCP 標準工具集與處理器契約驗證', async () => {
    expect(OPENTOKENUSAGE_MCP_TOOLS.length).toBeGreaterThanOrEqual(4);

    const quotaResult = await handleMcpToolCall('get_provider_quota', { provider: 'cursor' }, {});
    expect(quotaResult.remainingPercent).toBe(100);
    expect(quotaResult.status).toBe('active');

    // 驗證 Codex (ChatGPT) MCP 額度查詢
    const codexResult = await handleMcpToolCall('get_provider_quota', { provider: 'codex' }, {});
    expect(codexResult.remainingPercent).toBe(28);
    expect(codexResult.sessionUsedPercent).toBe(72);
    expect(codexResult.plan).toBe('Plus');

    const estimate = await handleMcpToolCall(
      'estimate_token_cost',
      { modelId: 'gemini-3.8-flash', promptTokens: 10000, completionTokens: 2000, thinkingTokens: 4000 },
      {}
    );
    expect(estimate.totalTokens).toBe(16000);
    expect(estimate.estimatedCostUsd).toBeGreaterThan(0);
  });
});

test.describe('2. Apple HIG iPhone Duo 雙欄與 UI/UX 驗證', () => {
  test('橫向雙欄佈局 (38%:62%)、動態島避讓與持續高亮', async ({ page }) => {
    await page.goto('/');

    // 驗證主容器
    const masterList = page.getByRole('complementary', { name: 'AI 平台清單' });
    const detailWorkbench = page.getByRole('main', { name: 'AI 平台詳情與語音工作台' });

    await expect(masterList).toBeVisible();
    await expect(detailWorkbench).toBeVisible();

    // 驗證 Cursor 平台卡片與數值
    const cursorCard = page.locator('div[role="button"]:has-text("Cursor")');
    await expect(cursorCard).toBeVisible();
    await expect(cursorCard.locator('.tabular-nums').first()).toContainText('100%');

    // 驗證持續性選取指示
    await cursorCard.click();
    await expect(cursorCard).toHaveClass(/border-\[#0071e3\]/);
  });

  test('Focus Mode 專注模式全寬切換', async ({ page }) => {
    await page.goto('/');

    const masterList = page.getByRole('complementary', { name: 'AI 平台清單' });
    await expect(masterList).toBeVisible();

    // 點擊收合按鈕
    const focusBtn = page.locator('button[title*="專注全寬模式"]');
    if (await focusBtn.isVisible()) {
      await focusBtn.click();
      // Master 寬度應收縮為 0
      await expect(masterList).toHaveClass(/w-0/);

      // 再次點擊還原
      const restoreBtn = page.locator('button[title*="展開導覽列"]');
      await restoreBtn.click();
      await expect(masterList).not.toHaveClass(/w-0/);
    }
  });

  test('右手拇指操作列尺寸符合 Apple HIG (≥48pt) 與模型同步視窗', async ({ page }) => {
    await page.goto('/');

    const toolbar = page.getByRole('complementary', { name: '即時浮動控制列' });
    await expect(toolbar).toBeVisible();

    // 麥克風通話鈕尺寸驗證 (>= 48x48 pt)
    const micBtn = toolbar.locator('button[title*="語音"]');
    const box = await micBtn.boundingBox();
    expect(box).toBeTruthy();
    expect(box!.width).toBeGreaterThanOrEqual(48);
    expect(box!.height).toBeGreaterThanOrEqual(48);

    // 點擊同步模型按鈕
    const syncBtn = toolbar.locator('button[title*="同步最新模型型錄"]');
    await syncBtn.click();

    // 驗證彈出視窗
    const modalTitle = page.locator('text=即時遠端動態模型型錄');
    await expect(modalTitle).toBeVisible();
    await expect(page.locator('.fixed').getByText('Gemini 3.8 Live (Audio & Vision)')).toBeVisible();
    await expect(page.locator('.fixed').getByText('OpenAI o3-mini (High Reasoning)')).toBeVisible();
  });

  test('Codex (ChatGPT) 平台卡片與雙重限額明細展示', async ({ page }) => {
    await page.goto('/');

    const codexCard = page.locator('div[role="button"]:has-text("Codex (ChatGPT)")');
    await expect(codexCard).toBeVisible();
    await expect(codexCard.locator('.tabular-nums').first()).toContainText('28%');

    await codexCard.click();
    await expect(page.locator('text=ChatGPT Plus 雙重限額明細')).toBeVisible();
    await expect(page.locator('text=72% 已用')).toBeVisible();
    await expect(page.locator('text=100% 已達')).toBeVisible();
  });
});
