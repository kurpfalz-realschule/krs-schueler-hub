import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './tests/e2e',
  timeout: 30_000,
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI ? 'github' : 'list',
  use: {
    baseURL: 'http://localhost:4180',
    screenshot: 'only-on-failure',
    trace: 'retain-on-failure',
    locale: 'de-DE',
  },
  webServer: {
    command: 'npx http-server -p 4180 -c-1 --silent .',
    url: 'http://localhost:4180/index.html',
    reuseExistingServer: !process.env.CI,
  },
});
