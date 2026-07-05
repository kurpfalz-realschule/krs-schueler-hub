// Smoke-Tests KRS Schüler-Hub — Demo-Modus (forceMode=demo), User MIA-TEST.
// Konvention: Logik über Demo-DataService, UI über data-testid.
import { test, expect, Page } from '@playwright/test';

const DEMO_URL = '/index.html?forceMode=demo';

async function loginAlsMia(page: Page) {
  await page.goto(DEMO_URL);
  await page.getByTestId('code-input').fill('MIA-TEST');
  await page.getByTestId('login-btn').click();
  await expect(page.getByTestId('user-chip')).toContainText('Mia Muster');
}

test.describe('Schüler-Hub Smoke (Demo)', () => {

  test('Login mit gültigem Code zeigt Dashboard', async ({ page }) => {
    await loginAlsMia(page);
    await expect(page.getByTestId('mode-badge')).toHaveText(/Demo/i);
    await expect(page.getByTestId('tile-kalender')).toBeVisible();
    await expect(page.getByTestId('tile-teams')).toBeVisible();
    await expect(page.getByTestId('user-chip')).toContainText('Klasse 7b');
  });

  test('Login mit unbekanntem Code zeigt Fehlermeldung', async ({ page }) => {
    await page.goto(DEMO_URL);
    await page.getByTestId('code-input').fill('XX-FALSCH');
    await page.getByTestId('login-btn').click();
    await expect(page.getByTestId('login-error')).toContainText('nicht bekannt');
  });

  test('Deep-Link ?code= loggt automatisch ein', async ({ page }) => {
    await page.goto(DEMO_URL + '&code=MIA-TEST');
    await expect(page.getByTestId('user-chip')).toContainText('Mia Muster');
  });

  test('Kalender zeigt Termine und filtert Klassenarbeiten', async ({ page }) => {
    await loginAlsMia(page);
    await page.getByTestId('tile-kalender').click();
    await expect(page.getByTestId('termin').first()).toBeVisible();
    const alle = await page.getByTestId('termin').count();
    await page.getByRole('button', { name: 'Klassenarbeiten' }).click();
    const kas = await page.getByTestId('termin').count();
    expect(kas).toBeGreaterThan(0);
    expect(kas).toBeLessThan(alle);
    for (const el of await page.getByTestId('termin').all()) {
      await expect(el).toContainText('Klassenarbeit');
    }
  });

  test('Team öffnen und Beitrag posten', async ({ page }) => {
    await loginAlsMia(page);
    await page.getByTestId('tile-teams').click();
    await expect(page.getByTestId('team-row').first()).toBeVisible();
    await page.getByTestId('team-row').first().click();
    await expect(page.getByTestId('posts')).toBeVisible();
    await page.getByTestId('post-input').fill('Hallo Team, ich bringe eine Gießkanne mit!');
    await page.getByTestId('post-send').click();
    await expect(page.getByTestId('posts')).toContainText('Gießkanne');
    await expect(page.getByTestId('posts')).toContainText('Mia M.');
  });

  test('Nachricht an Lehrkraft senden', async ({ page }) => {
    await loginAlsMia(page);
    await page.getByTestId('tile-nachrichten').click();
    await page.getByTestId('neue-nachricht').click();
    await page.getByTestId('lehrer-select').selectOption('Ko');
    await page.getByTestId('betreff-input').fill('Frage zur Probe');
    await page.getByTestId('inhalt-input').fill('Findet die Probe diese Woche statt?');
    await page.getByTestId('nachricht-senden').click();
    await expect(page.getByTestId('nachricht').first()).toContainText('Frage zur Probe');
    await expect(page.getByTestId('nachricht').first()).toContainText('wartet auf Antwort');
  });

  test('Abmelden führt zurück zum Login', async ({ page }) => {
    await loginAlsMia(page);
    await page.getByTestId('logout').click();
    await expect(page.getByTestId('code-input')).toBeVisible();
  });
});
