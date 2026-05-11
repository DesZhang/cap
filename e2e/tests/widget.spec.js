import { test, expect } from '@playwright/test';
import { blockCDN, harvestToken } from './helpers.js';

function interceptVerify(page) {
  return new Promise((resolve) => {
    page.on('request', async (request) => {
      if (request.url().includes('/api/cap/verify') && request.method() === 'POST') {
        const body = request.postDataJSON();
        const response = await request.response();
        resolve({
          token: body?.token || '',
          status: response?.status() || 0,
        });
      }
    });
  });
}

test.describe('Widget mode (standard component)', () => {
  test('widget auto-solves, hidden token injected, backend returns 200', async ({ page }) => {
    blockCDN(page);

    const verifyResult = interceptVerify(page);

    await page.goto('/');

    // Find the WidgetDemo section
    const section = page.locator('section').filter({ hasText: 'Widget 模式' });
    await expect(section).toBeVisible();

    // Wait for cap-widget to auto-solve (speculative solve)
    // The widget auto-solves when visible — wait for the hidden input to get a value
    const widgetContainer = section.locator('.widget-container');
    const hiddenInput = widgetContainer.locator('input[name="cap-token"]');
    await expect(hiddenInput).toHaveValue(/.+/, { timeout: 60_000 });

    // Click "提交并验证"
    const submitBtn = section.getByRole('button', { name: '提交并验证' });
    await submitBtn.click();

    // Assert success result in UI
    const result = section.locator('.verification-result.success');
    await expect(result).toBeVisible({ timeout: 15_000 });

    // Verify backend returned 200
    const { token, status } = await verifyResult;
    expect(status).toBe(200);
    expect(token).toBeTruthy();

    harvestToken(token, 'widget');
  });
});
