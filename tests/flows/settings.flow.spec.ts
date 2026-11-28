import { test, expect } from '../ui-gate/gate-fixture.mjs';
import { serveQuotas } from '../ui-gate/fixtures.mjs';

test('settings: refresh interval and color scheme are saved and restored after reload', async ({ page }) => {
  await serveQuotas(page);
  await page.goto('/');
  await page.getByRole('button', { name: /設定/ }).click();
  await page.getByRole('radio', { name: '60 分鐘', exact: true }).check();
  await page.getByRole('radio', { name: '深色', exact: true }).check();
  await expect(page.locator('meta[name="color-scheme"]')).toHaveAttribute('content', 'dark');
  await page.reload();
  await expect(page.locator('meta[name="color-scheme"]')).toHaveAttribute('content', 'dark');
  await page.getByRole('button', { name: /設定/ }).click();
  await expect(page.getByRole('radio', { name: '60 分鐘', exact: true })).toBeChecked();
  await expect(page.getByRole('radio', { name: '深色', exact: true })).toBeChecked();
});
