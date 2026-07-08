// Smoke-Tests Schüler-Hub — Ankündigungen + Transparenz-Hinweis (Demo).
import { test, expect, Page } from '@playwright/test';

const DEMO_URL = '/index.html?forceMode=demo';

async function loginAlsMia(page: Page) {
  await page.goto(DEMO_URL);
  await page.getByTestId('code-input').fill('MIA-TEST');
  await page.getByTestId('login-btn').click();
  await expect(page.getByTestId('user-chip')).toContainText('Mia Muster');
}

test.describe('Schüler-Hub Ankündigungen & Transparenz (Demo)', () => {

  test('Dashboard zeigt Ankündigungs-Block', async ({ page }) => {
    await loginAlsMia(page);
    await expect(page.getByTestId('ankuendigungen')).toBeVisible();
    await expect(page.getByTestId('ankuendigungen')).toContainText('Wandertag');
  });

  test('Nachrichten-View zeigt Transparenz-Hinweis', async ({ page }) => {
    await loginAlsMia(page);
    await page.getByTestId('tile-nachrichten').click();
    await expect(page.getByTestId('transparenz-hinweis')).toBeVisible();
    await expect(page.getByTestId('transparenz-hinweis')).toContainText(/Lehrkräfte/i);
  });

});
