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

test('view switcher: wide screens can switch to split view and see details', async ({ page }) => {
  test.skip(page.viewportSize()!.width < 600, 'the switcher only exists on wide screens');
  await serveQuotas(page);
  await page.goto('/');
  const switcher = page.getByRole('navigation', { name: '視圖模式切換器' });
  await expect(switcher).toBeVisible();
  await switcher.getByRole('button').nth(1).click();
  await expect(page.getByRole('main', { name: '服務詳情' })).toBeVisible();
});
