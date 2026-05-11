/**
 * Shared test helpers for Cap E2E tests.
 *
 * blockCDN     — hard-block all requests to cdn.jsdelivr.net (proves self-hosted assets work)
 * harvestToken — write consumed tokens to a JSON file for replay/cap-down tests
 * harvestUnconsumedToken — write tokens that were NOT sent to backend (for expiry test)
 */

import fs from 'node:fs';
import path from 'node:path';

const HARVEST_FILE = path.resolve('/tmp/cap-e2e-tokens.json');

/**
 * Block all CDN requests on a Playwright page.
 * If any request to cdn.jsdelivr.net fires, it will be aborted.
 */
export function blockCDN(page) {
  page.route('**/cdn.jsdelivr.net/**', (route) => route.abort());
}

function appendToFile(entry) {
  let tokens = [];
  try {
    tokens = JSON.parse(fs.readFileSync(HARVEST_FILE, 'utf-8'));
  } catch {
    // first write
  }
  tokens.push(entry);
  fs.writeFileSync(HARVEST_FILE, JSON.stringify(tokens, null, 2));
}

/**
 * Harvest a consumed token — was verified by backend (getdel'd).
 * Used for: replay test, cap-down test.
 */
export function harvestToken(token, label) {
  appendToFile({ token, label, consumed: true, harvestedAt: Date.now() });
}

/**
 * Harvest an unconsumed token — exists in Redis but was NOT sent to backend verify.
 * Used for: expiry test (wait for TTL, then verify → should be 401).
 */
export function harvestUnconsumedToken(token, label) {
  appendToFile({ token, label, consumed: false, harvestedAt: Date.now() });
}
