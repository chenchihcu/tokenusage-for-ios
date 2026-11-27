import { test, expect } from '../ui-gate/gate-fixture.mjs';
import { quotaRows } from '../ui-gate/fixtures.mjs';

// Real Worker + local D1 (no route mocks): the sync endpoint stores rows that the UI then shows.
test('sync API: pushed quotas are stored and still shown after a reload', async ({ page }) => {
  const res = await page.request.post('/api/quotas/sync', {
    headers: { Authorization: 'Bearer ui-gate-token' },
    data: { quotas: quotaRows(new Date().toISOString()) },
  });
  expect(res.ok(), await res.text()).toBeTruthy();
  await page.goto('/');
  await expect(page.getByRole('heading', { name: 'Codex', exact: true }).first()).toBeVisible();
  await page.reload();
  await expect(page.getByRole('heading', { name: 'Codex', exact: true }).first()).toBeVisible();
  await page.getByRole('navigation', { name: '快速操作' }).getByRole('button').filter({ hasText: '更新' }).click();
  await expect(page.getByRole('status').filter({ hasText: '已同步' })).toBeVisible();
});
