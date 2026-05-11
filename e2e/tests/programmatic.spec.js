import { test, expect } from '@playwright/test';
import { blockCDN, harvestToken, harvestUnconsumedToken } from './helpers.js';

/**
 * Intercept the backend /api/cap/verify request and capture token + status.
 */
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

/**
 * Wait for the next Cap /redeem response AFTER this function is called.
 * Used to capture the ProgrammaticDemo's solve token (not speculative widget solves).
 */
function waitForNextRedeem(page) {
  return new Promise((resolve) => {
    const handler = async (response) => {
      if (response.url().includes('/redeem') && response.status() === 200) {
        try {
          const body = await response.json();
          if (body.token) {
            page.off('response', handler);
            resolve(body.token);
          }
        } catch { /* ignore parse errors */ }
      }
    };
    page.on('response', handler);
  });
}

test.describe('Programmatic mode (Cap JS API)', () => {
  test('solves challenge via Cap API and backend returns 200', async ({ page }) => {
    blockCDN(page);
    const verifyResult = interceptVerify(page);

    await page.goto('/');

    const section = page.locator('section').filter({ hasText: '编程模式' });
    await expect(section).toBeVisible();

    // Set up redeem intercept AFTER page load (speculative solves may have already fired)
    const redeemToken = waitForNextRedeem(page);

    // Click "静默获取 Token" — triggers cap.solve() → /challenge → /redeem
    const solveBtn = section.getByRole('button', { name: '静默获取 Token' });
    await solveBtn.click();

    // Wait for token display to appear
    const tokenDisplay = section.locator('.token-display code');
    await expect(tokenDisplay).toBeVisible({ timeout: 60_000 });

    // Capture the full unconsumed token from the redeem response
    const fullToken = await redeemToken;
    expect(fullToken).toBeTruthy();

    // Harvest as unconsumed — this token exists in Redis, NOT yet sent to backend
    harvestUnconsumedToken(fullToken, 'programmatic-expiry');

    // Click "验证 Token" — this consumes the token via getdel
    const verifyBtn = section.getByRole('button', { name: '验证 Token' });
    await expect(verifyBtn).toBeEnabled();
    await verifyBtn.click();

    // Assert success result in UI
    const result = section.locator('.verification-result.success');
    await expect(result).toBeVisible({ timeout: 15_000 });

    // Verify backend returned 200
    const { token, status } = await verifyResult;
    expect(status).toBe(200);
    expect(token).toBeTruthy();

    // Harvest consumed token for replay/cap-down tests
    harvestToken(token, 'programmatic');
  });
});
