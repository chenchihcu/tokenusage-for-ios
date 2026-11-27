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

// ---------------------------------------------------------------------------
// UI (P0): the app shows only what /api/quotas returns. Tests serve a fixed
// payload through page.route so no built-in sample numbers are needed.
// ---------------------------------------------------------------------------
type Page = import('@playwright/test').Page;

function iso(hoursFromNow: number): string {
  return new Date(Date.now() + hoursFromNow * 3_600_000).toISOString();
}

function quotaPayload() {
  const tier = (id: string, label: string, used: number, h: number, governing: boolean) => ({
    id, label, used, limit: 100, remaining: 100 - used, resetsAt: iso(h), resetDurationText: '', isGoverning: governing,
  });
  const row = (id: string, name: string, plan: string, remaining: number, metrics: unknown[], pools?: unknown[]) => ({
    provider_id: id, name, plan_name: plan, total_quota: 100, used_quota: 100 - remaining, remaining_percent: remaining,
    reset_time: iso(48), status: 'active', metrics_json: JSON.stringify(metrics),
    token_pools_json: pools ? JSON.stringify(pools) : null, fetched_at: new Date().toISOString(),
  });
  return {
    success: true,
    data: [
      row('codex', 'Codex', 'Plus', 3, [{ label: 'Resets', value: '1 available' }], [
        { id: 'codex_shared', name: 'Codex CLI & Cloud', effectiveRemaining: 3, effectiveUsed: 97, primaryResetTime: iso(20), isCritical: true,
          tiers: [tier('weekly', 'Weekly limit', 97, 20, true), tier('5h', '5h Session', 40, 3, false)] },
      ]),
      row('claude', 'Claude Code', 'Pro', 58, [{ label: 'Resets', value: '0 available' }]),
      row('cursor', 'Cursor', 'Pro', 41, [{ label: 'Total usage', used: 59, limit: 100, kind: 'percent' }]),
      row('antigravity', 'Google Antigravity', 'Google AI Pro', 77, []),
      row('grok', 'Grok', 'SuperGrok', 0, []),
    ],
  };
}

async function serveQuotas(page: Page, body: unknown = quotaPayload()) {
  await page.route('**/api/quotas', (route) =>
    route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(body) }),
  );
}

test.describe('2. 資料與狀態', () => {
  test('只顯示四個服務（無 Grok），成功時不顯示連線列', async ({ page }) => {
    await serveQuotas(page);
    await page.goto('/');
    for (const name of ['Codex', 'Claude Code', 'Cursor', 'Google Antigravity']) {
      await expect(page.getByRole('heading', { name, exact: true }).first()).toBeVisible();
    }
    await expect(page.getByText('已同步')).toHaveCount(0);
    await expect(page.getByRole('button', { name: '重試' })).toHaveCount(0);
    await expect(page.getByText('Grok')).toHaveCount(0);
  });

  test('伺服器沒有資料時顯示空狀態，不顯示內建數字', async ({ page }) => {
    await serveQuotas(page, { success: true, data: [] });
    await page.goto('/');
    await expect(page.getByText('尚無額度資料')).toBeVisible();
    await expect(page.getByText(/\d+%/)).toHaveCount(0);
  });

  test('Codex 與 Claude Code 的免費重置次數在重置面板', async ({ page }) => {
    await serveQuotas(page);
    await page.goto('/');
    await expect(page.getByRole('heading', { name: 'Codex', exact: true }).first()).toBeVisible();
    await expect(page.getByRole('region', { name: /免費重置/ })).toHaveCount(0);
    await page.getByRole('button', { name: '免費重置，1 項可用' }).click();
    const sheet = page.getByRole('dialog', { name: '免費重置與重置時間' });
    await expect(sheet.getByText('免費重置 1 次')).toBeVisible();
    await expect(sheet.getByText('免費重置 0 次')).toBeVisible();
    await sheet.getByRole('button', { name: '完成' }).click();
  });

  test('服務忙碌時顯示原因，沒有重試按鈕', async ({ page }) => {
    await page.route('**/api/quotas', (route) => route.fulfill({ status: 500, body: 'nope' }));
    await page.goto('/');
    await expect(page.getByText('服務忙碌，請稍後再試')).toBeVisible();
    await expect(page.getByRole('button', { name: '重試' })).toHaveCount(0);
  });

  test('沒有語音功能（無麥克風按鈕、無語音字幕）', async ({ page }) => {
    await serveQuotas(page);
    await page.goto('/');
    await expect(page.getByRole('button', { name: /語音|麥克風|Gemini/ })).toHaveCount(0);
    await expect(page.getByText(/TRANSCRIPT|語音/)).toHaveCount(0);
  });
});

test.describe('3. 右手快速操作（4 個圖示）', () => {
  test('四個操作都有文字標題且至少 44×44', async ({ page }) => {
    await serveQuotas(page);
    await page.goto('/');
    const nav = page.getByRole('navigation', { name: '快速操作' });
    for (const label of ['更新', '重置', '告警', '設定']) {
      const box = await nav.getByRole('button').filter({ hasText: label }).boundingBox();
      expect(box).not.toBeNull();
      expect(box!.width).toBeGreaterThanOrEqual(44);
      expect(box!.height).toBeGreaterThanOrEqual(44);
    }
  });

  test('重置徽章顯示可用次數，點擊開啟重置面板', async ({ page }) => {
    await serveQuotas(page);
    await page.goto('/');
    await page.getByRole('button', { name: '免費重置，1 項可用' }).click();
    const sheet = page.getByRole('dialog', { name: '免費重置與重置時間' });
    await expect(sheet.getByText('免費重置 1 次')).toBeVisible();
    await sheet.getByRole('button', { name: '完成' }).click();
    await expect(sheet).toHaveCount(0);
  });

  test('設定：更新頻率持久化', async ({ page }) => {
    await serveQuotas(page);
    await page.goto('/');
    await page.getByRole('button', { name: /設定/ }).click();
    await page.getByRole('radio', { name: '5 分鐘', exact: true }).check();
    await page.reload();
    await page.getByRole('button', { name: /設定/ }).click();
    await expect(page.getByRole('radio', { name: '5 分鐘', exact: true })).toBeChecked();
  });

  test('左手模式：操作列移到左下，卡片內容不鏡像', async ({ page }) => {
    await serveQuotas(page);
    await page.goto('/?handed=left');
    const nav = await page.getByRole('navigation', { name: '快速操作' }).boundingBox();
    const vw = page.viewportSize()!.width;
    expect(nav!.x + nav!.width / 2).toBeLessThan(vw / 2);
  });

  test('只看告警：只留剩餘 ≤ 20% 的服務', async ({ page }) => {
    await serveQuotas(page);
    await page.goto('/?view=cockpit');
    await page.getByRole('button', { name: /只看告警/ }).click();
    await expect(page.getByRole('heading', { name: 'Codex', exact: true }).first()).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Google Antigravity', exact: true })).toHaveCount(0);
  });

});

test.describe('4. 版面', () => {
  test('窄螢幕不顯示全景/雙欄切換，寬螢幕才顯示', async ({ page }) => {
    await serveQuotas(page);
    await page.setViewportSize({ width: 375, height: 812 });
    await page.goto('/');
    await expect(page.getByRole('navigation', { name: '視圖模式切換器' })).toHaveCount(0);
    await page.setViewportSize({ width: 890, height: 626 });
    await expect(page.getByRole('navigation', { name: '視圖模式切換器' })).toBeVisible();
  });

  test('所有可見按鈕都在視窗寬度內', async ({ page }) => {
    await serveQuotas(page);
    await page.setViewportSize({ width: 375, height: 812 });
    await page.goto('/');
    const overflow = await page.evaluate(() =>
      [...document.querySelectorAll('button')]
        .map((b) => b.getBoundingClientRect())
        .filter((r) => r.width > 0 && (r.right > window.innerWidth + 1 || r.left < -1)).length,
    );
    expect(overflow).toBe(0);
  });

  // iPhone Duo（PR #4）：Apple 未公布點數，以下為第三方估算的內外螢幕尺寸
  for (const [label, width, height, twoColumns] of [
    ['外螢幕直向', 466, 678, false],
    ['外螢幕橫向', 678, 466, true],
    ['內螢幕直向', 669, 951, true],
    ['內螢幕直向 (626pt 估算)', 626, 890, true],
    ['內螢幕橫向', 951, 669, true],
  ] as const) {
    test(`iPhone Duo ${label} (${width}x${height})：頂列與按鈕不溢出，雙欄時顯示詳情`, async ({ page }) => {
      await serveQuotas(page);
      await page.setViewportSize({ width, height });
      await page.goto('/?view=split');

      const detail = page.getByRole('main', { name: '服務詳情' });
      if (twoColumns) await expect(detail).toBeVisible();
      else await expect(detail).toHaveCount(0);

      const buttons = page.locator('header button, nav[aria-label="快速操作"] button');
      const count = await buttons.count();
      expect(count).toBeGreaterThan(0);
      for (let i = 0; i < count; i++) {
        const box = await buttons.nth(i).boundingBox();
        expect(box).not.toBeNull();
        if (!box) continue;
        expect(box.x).toBeGreaterThanOrEqual(0);
        expect(box.x + box.width).toBeLessThanOrEqual(width);
        expect(box.height).toBeGreaterThanOrEqual(44);
      }

      const scrollWidth = await page.evaluate(() => document.documentElement.scrollWidth);
      expect(scrollWidth).toBeLessThanOrEqual(width);
    });
  }
});
