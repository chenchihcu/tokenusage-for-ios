import { test, expect } from '../ui-gate/gate-fixture.mjs';
import { serveQuotas, empty } from '../ui-gate/fixtures.mjs';

test('overview: four services load and a manual refresh re-fetches', async ({ page }) => {
  await serveQuotas(page);
  let calls = 0;
  page.on('request', (r) => { if (new URL(r.url()).pathname === '/api/quotas') calls++; });
  await page.goto('/');
  await expect(page.getByRole('status').filter({ hasText: '已同步' })).toBeVisible();
  for (const name of ['Codex', 'Claude Code', 'Cursor', 'Google Antigravity']) {
    await expect(page.getByRole('heading', { name, exact: true }).first()).toBeVisible();
  }
  const before = calls;
  await page.getByRole('navigation', { name: '快速操作' }).getByRole('button').filter({ hasText: '更新' }).click();
  await expect.poll(() => calls).toBeGreaterThan(before);
  await expect(page.getByRole('status').filter({ hasText: '已同步' })).toBeVisible();
});

test('overview: an empty server shows the empty state and no numbers', async ({ page }) => {
  await serveQuotas(page, empty());
  await page.goto('/');
  await expect(page.getByText('尚無額度資料')).toBeVisible();
  await expect(page.getByText(/\d+%/)).toHaveCount(0);
});
