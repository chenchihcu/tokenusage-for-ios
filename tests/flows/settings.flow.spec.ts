import { test, expect } from '../ui-gate/gate-fixture.mjs';
import { serveQuotas } from '../ui-gate/fixtures.mjs';

test('settings: refresh interval is saved and restored after reload', async ({ page }) => {
  await serveQuotas(page);
  await page.goto('/');
  await page.getByRole('button', { name: /設定/ }).click();
  await page.getByRole('radio', { name: '5 分鐘', exact: true }).check();
  await page.reload();
  await page.getByRole('button', { name: /設定/ }).click();
  await expect(page.getByRole('radio', { name: '5 分鐘', exact: true })).toBeChecked();
});
