import { test, expect } from '../ui-gate/gate-fixture.mjs';
import { serveQuotas } from '../ui-gate/fixtures.mjs';

test('reset monitor: the badge opens the reset sheet and Done closes it', async ({ page }) => {
  await serveQuotas(page);
  await page.goto('/');
  const bar = page.getByRole('region', { name: /免費重置/ });
  await expect(bar.getByText('免費重置 1 次')).toBeVisible();
  await page.getByRole('button', { name: '免費重置，1 項可用' }).click();
  const sheet = page.getByRole('dialog', { name: '免費重置與重置時間' });
  await expect(sheet.getByText('免費重置 1 次')).toBeVisible();
  await sheet.getByRole('button', { name: '完成' }).click();
  await expect(sheet).toHaveCount(0);
});
