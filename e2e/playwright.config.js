import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './tests',
  timeout: 120_000,        // PoW solve can take a while
  expect: { timeout: 30_000 },
  fullyParallel: false,     // sequential — tests share service stack
  workers: 1,              // single worker — avoid overwhelming the Cap container
  retries: 0,
  reporter: 'list',
  use: {
    baseURL: 'http://localhost:5173',
    actionTimeout: 15_000,
  },
});
