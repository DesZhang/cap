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

test.describe('Floating/Invisible mode', () => {
  test('floating widget triggers, solves, backend returns 200', async ({ page }) => {
    blockCDN(page);

    const verifyResult = interceptVerify(page);

    await page.goto('/');

    // Find the InvisibleDemo section
    const section = page.locator('section').filter({ hasText: '浮动/隐形模式' });
    await expect(section).toBeVisible();

    // Click "触发浮动验证" — this activates the floating widget
    const triggerBtn = section.getByRole('button', { name: '触发浮动验证' });
    await triggerBtn.click();

    // Wait for the widget to auto-solve and submit the verify request
    // The floating widget fires a 'complete' event which triggers verifyToken in the component
    const result = section.locator('.verification-result.success');
    await expect(result).toBeVisible({ timeout: 60_000 });

    // Verify backend returned 200
    const { token, status } = await verifyResult;
    expect(status).toBe(200);
    expect(token).toBeTruthy();

    harvestToken(token, 'floating');
  });
});
