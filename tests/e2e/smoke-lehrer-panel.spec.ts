// Smoke-Tests KRS Schüler-Hub — Lehrer-Panel (Demo-Modus).
// Deckt die Brücke Lehrer→Schüler ab: Postfach, Antworten, enger Sicht-Modus,
// Ankündigungen, Schüler-Vorschau, Protokoll. Kein Backend nötig.
import { test, expect, Page } from '@playwright/test';

const URL = '/lehrer-panel.html?forceMode=demo';

async function login(page: Page) {
  await page.goto(URL);
  await page.getByTestId('demo-login').click();
  await expect(page.getByTestId('tab-postfach')).toBeVisible();
}

test.describe('Lehrer-Panel Smoke (Demo)', () => {

  test('Demo-Login zeigt Panel mit Tabs', async ({ page }) => {
    await login(page);
    await expect(page.getByTestId('mode-badge')).toHaveText(/Demo/i);
    await expect(page.getByTestId('tab-ankuendigungen')).toBeVisible();
    await expect(page.getByTestId('tab-vorschau')).toBeVisible();
    await expect(page.getByTestId('tab-protokoll')).toBeVisible();
  });

  test('Enger Modus: nur an mich adressierte Nachrichten sichtbar', async ({ page }) => {
    await login(page);
    await expect(page.getByTestId('sicht-banner')).toContainText(/Enger Modus/i);
    // n1 + n2 sind an "Ko" (an mich), n3 an "Mu" → darf NICHT erscheinen
    await expect(page.getByTestId('postfach-msg')).toHaveCount(2);
    await expect(page.locator('body')).not.toContainText('Lena Beispiel');
    await expect(page.locator('body')).toContainText('Mia Muster');
  });

  test('Offene Nachricht beantworten', async ({ page }) => {
    await login(page);
    const reply = page.getByTestId('reply-input').first();
    await expect(reply).toBeVisible();
    await reply.fill('Klar, komm einfach Donnerstag vorbei!');
    await page.getByTestId('reply-send').first().click();
    await expect(page.locator('body')).toContainText('Antwort gesendet');
    await expect(page.getByTestId('postfach-msg').first()).toContainText('Klar, komm einfach Donnerstag vorbei!');
  });

  test('Ankündigung erstellen erscheint in der Liste', async ({ page }) => {
    await login(page);
    await page.getByTestId('tab-ankuendigungen').click();
    await page.getByTestId('ank-titel').fill('Test-Ankündigung Sporttag');
    await page.getByTestId('ank-inhalt').fill('Bitte Sportsachen mitbringen.');
    await page.getByTestId('ank-senden').click();
    await expect(page.locator('body')).toContainText('veröffentlicht');
    await expect(page.getByTestId('ank-item').first()).toContainText('Test-Ankündigung Sporttag');
  });

  test('Schüler-Vorschau zeigt Ankündigung der Klasse', async ({ page }) => {
    await login(page);
    await page.getByTestId('tab-vorschau').click();
    await expect(page.getByTestId('vorschau')).toBeVisible();
    // Demo-Ankündigung a1 (Wandertag) ist für Klasse 7b
    await expect(page.getByTestId('vorschau')).toContainText('Wandertag');
  });

  test('Protokoll enthält Einträge', async ({ page }) => {
    await login(page);
    await page.getByTestId('tab-protokoll').click();
    await expect(page.getByTestId('audit-row').first()).toBeVisible();
  });

  test('Sanitizer entfernt Script (Test-Hook)', async ({ page }) => {
    await login(page);
    const clean = await page.evaluate(() => (window as any).__lp_sanitizeHtml('<b>Hi</b><script>alert(1)<\/script><img src="x" onerror="alert(2)">'));
    expect(clean).toContain('<b>Hi</b>');
    expect(clean).not.toContain('<script');
    expect(clean).not.toContain('onerror');
  });

});
