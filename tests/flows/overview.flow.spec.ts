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

test('[AC-1] overview: Codex and Google Antigravity render official brand badges', async ({ page }) => {
  await serveQuotas(page);
  await page.goto('/');
  await expect(page.getByRole('status').filter({ hasText: '已同步' })).toBeVisible();

  const codexIcons = page.locator('svg[data-brand-logo="codex"]');
  const agIcons = page.locator('svg[data-brand-logo="antigravity"]');
  await expect(codexIcons.first()).toBeVisible();
  await expect(agIcons.first()).toBeVisible();

  const iconAudit = await page.evaluate(() => {
    const check = (selector: string) => {
      const svgs = Array.from(document.querySelectorAll(selector));
      const ids = new Set<string>();
      let duplicateIds = 0;
      let brokenRefs = 0;
      for (const svg of svgs) {
        const localIds = new Set<string>();
        for (const el of svg.querySelectorAll('[id]')) {
          const id = el.getAttribute('id') || '';
          if (ids.has(id)) duplicateIds++;
          ids.add(id);
          localIds.add(id);
        }
        for (const el of svg.querySelectorAll('[fill^="url(#"], [mask^="url(#"], [filter^="url(#"]')) {
          for (const attr of ['fill', 'mask', 'filter']) {
            const val = el.getAttribute(attr);
            if (val && val.startsWith('url(#')) {
              const target = val.slice(5, -1);
              if (!localIds.has(target)) brokenRefs++;
            }
          }
        }
      }
      return { count: svgs.length, duplicateIds, brokenRefs };
    };
    return {
      codex: check('svg[data-brand-logo="codex"]'),
      antigravity: check('svg[data-brand-logo="antigravity"]'),
    };
  });

  expect(iconAudit.codex.count).toBeGreaterThan(0);
  expect(iconAudit.codex.duplicateIds).toBe(0);
  expect(iconAudit.codex.brokenRefs).toBe(0);
  expect(iconAudit.antigravity.count).toBeGreaterThan(0);
  expect(iconAudit.antigravity.duplicateIds).toBe(0);
  expect(iconAudit.antigravity.brokenRefs).toBe(0);
});
