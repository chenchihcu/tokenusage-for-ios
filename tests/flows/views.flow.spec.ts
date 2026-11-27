import { test, expect } from '../ui-gate/gate-fixture.mjs';
import { serveQuotas } from '../ui-gate/fixtures.mjs';

test('quick actions: left-hand mode moves the action bar to the left', async ({ page }) => {
  await serveQuotas(page);
  await page.goto('/?handed=left');
  const nav = await page.getByRole('navigation', { name: '快速操作' }).boundingBox();
  expect(nav).not.toBeNull();
  expect(nav!.x + nav!.width / 2).toBeLessThan(page.viewportSize()!.width / 2);
  await page.getByRole('navigation', { name: '快速操作' }).getByRole('button').filter({ hasText: '更新' }).click();
  await expect(page.getByRole('status').filter({ hasText: '已同步' })).toBeVisible();
});

test('cockpit: "only alerts" keeps services at or below 20 %', async ({ page }) => {
  await serveQuotas(page);
  await page.goto('/?view=cockpit');
  await page.getByRole('button', { name: /只看告警/ }).click();
  await expect(page.getByRole('heading', { name: 'Codex', exact: true }).first()).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Google Antigravity', exact: true })).toHaveCount(0);
});

test('[AC-1] 打開全景，一屏看到四個服務且沒有整頁捲軸', async ({ page }) => {
  await serveQuotas(page);
  await page.goto('/?view=cockpit');
  await expect(page.getByRole('status').filter({ hasText: '已同步' })).toBeVisible();
  for (const name of ['Codex', 'Claude Code', 'Cursor', 'Google Antigravity']) {
    await expect(page.getByRole('heading', { name, exact: true })).toBeVisible();
  }
  const scroll = await page.evaluate(() => {
    const root = document.scrollingElement;
    const board = document.querySelector('[data-usage-board]');
    return {
      pageOverflow: root ? root.scrollHeight - root.clientHeight : 0,
      boardOverflow: board ? board.scrollHeight - board.clientHeight : 0,
    };
  });
  expect(scroll.pageOverflow).toBeLessThanOrEqual(1);
  expect(scroll.boardOverflow).toBeLessThanOrEqual(1);
});

test('[AC-2] 點分組「模型」，顯示服務回報的模型名稱', async ({ page }) => {
  await serveQuotas(page);
  await page.goto('/?view=cockpit');
  await page.getByRole('tab', { name: '模型' }).click();
  await expect(page.getByText('Codex CLI & Cloud')).toBeVisible();
  await expect(page.getByText('high', { exact: true })).toHaveCount(0);
  await expect(page.getByText('fast', { exact: true })).toHaveCount(0);
});

test('[AC-3] 點分組「每週」，Codex 排在最前', async ({ page }) => {
  await serveQuotas(page);
  await page.goto('/?view=cockpit');
  await page.getByRole('tab', { name: '每週' }).click();
  await expect(page.getByRole('heading', { level: 3 }).first()).toHaveText('Codex');
});

test('[AC-4] 點分組「費用」，沒有金額時顯示未提供', async ({ page }) => {
  await serveQuotas(page);
  await page.goto('/?view=cockpit');
  await page.getByRole('tab', { name: '費用' }).click();
  await expect(page.getByText('未提供').first()).toBeVisible();
  await expect(page.getByText(/\$\d/)).toHaveCount(0);
});

test('view switcher: wide screens can switch to split view and see details', async ({ page }) => {
  test.skip(page.viewportSize()!.width < 600, 'the switcher only exists on wide screens');
  await serveQuotas(page);
  await page.goto('/');
  const switcher = page.getByRole('navigation', { name: '視圖模式切換器' });
  await expect(switcher).toBeVisible();
  await switcher.getByRole('button').nth(1).click();
  await expect(page.getByRole('main', { name: '服務詳情' })).toBeVisible();
});
