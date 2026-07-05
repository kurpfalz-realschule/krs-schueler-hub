// Rich-Text & Sanitizing (S1) — Demo-Modus, User MIA-TEST.
// Konvention: Logik hermetisch über Test-Hooks (window.__sanitizeHtml …),
// UI über data-testid. Negativ-Fälle nach Skill wysiwyg-paste-farben-bilder.
import { test, expect, Page } from '@playwright/test';

const DEMO_URL = '/index.html?forceMode=demo';

async function loginAlsMia(page: Page) {
  await page.goto(DEMO_URL);
  await page.getByTestId('code-input').fill('MIA-TEST');
  await page.getByTestId('login-btn').click();
  await expect(page.getByTestId('user-chip')).toContainText('Mia Muster');
}

// contentEditable gezielt mit HTML befüllen (simuliert formatierten Inhalt)
async function setRichContent(page: Page, testid: string, htmlContent: string) {
  await page.getByTestId(testid).evaluate((el, content) => {
    el.innerHTML = content;
    el.dispatchEvent(new InputEvent('input', { bubbles: true }));
  }, htmlContent);
}

test.describe('Rich-Text Sanitizing (Hooks)', () => {

  test('XSS-Vektoren fliegen raus', async ({ page }) => {
    await page.goto(DEMO_URL);
    const r = await page.evaluate(() => {
      const s = (window as any).__sanitizeHtml as (h: string) => string;
      return {
        script: s('<p>ok</p><script>alert(1)<' + '/script>'),
        jsImg: s('<img src="javascript:alert(1)">bild'),
        dataHtml: s('<img src="data:text/html,<script>alert(1)<' + '/script>">x'),
        urlStyle: s('<span style="background-image:url(https://evil.example)">t</span>'),
        posFixed: s('<span style="position:fixed;top:0;color:#C0392B">t</span>'),
        onerror: s('<img src="https://x.example/y.png" onerror="alert(1)">'),
        jsLink: s('<a href="javascript:alert(1)">klick</a>'),
      };
    });
    expect(r.script).not.toContain('script');
    expect(r.jsImg).not.toContain('<img');
    expect(r.dataHtml).not.toContain('<img');
    expect(r.urlStyle).not.toContain('url(');
    expect(r.posFixed).not.toContain('position');
    expect(r.posFixed).toContain('color');           // sichere Farbe bleibt
    expect(r.onerror).not.toContain('onerror');
    expect(r.jsLink).not.toContain('javascript:');
  });

  test('Farben, Fett und data:image-Bilder bleiben erhalten', async ({ page }) => {
    await page.goto(DEMO_URL);
    const r = await page.evaluate(() => {
      const s = (window as any).__sanitizeHtml as (h: string) => string;
      const png = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUg==';
      return {
        color: s('<span style="color: rgb(192, 57, 43)">rot</span>'),
        bold: s('<b>fett</b> und <strong>stark</strong>'),
        img: s('<img src="' + png + '" alt="Bild">'),
        list: s('<ul><li>eins</li><li>zwei</li></ul>'),
        link: s('<a href="https://realschule-schriesheim.de/">KRS</a>'),
      };
    });
    expect(r.color).toContain('color');
    expect(r.color).toContain('rot');
    expect(r.bold).toContain('<b>');
    expect(r.img).toContain('data:image/png');
    expect(r.img).toContain('loading="lazy"');
    expect(r.img).toContain('referrerpolicy="no-referrer"');
    expect(r.list).toContain('<li>');
    expect(r.link).toContain('rel="noopener noreferrer"');
    expect(r.link).toContain('target="_blank"');
  });

  test('Zwei-Stufen-Regel: Sanitizer ist idempotent (kein Whitelist-Drift)', async ({ page }) => {
    await page.goto(DEMO_URL);
    const drift = await page.evaluate(() => {
      const s = (window as any).__sanitizeHtml as (h: string) => string;
      const p = (window as any).__simplifyPastedHtml as (h: string) => string;
      const proben = [
        '<p><b>Fett</b> <span style="color: #1E8449">grün</span></p>',
        '<img src="data:image/jpeg;base64,/9j/4AAQ==" alt="a">',
        '<ul><li><u>unterstrichen</u></li></ul>',
      ];
      // Was Stufe 1 (Paste) behält, muss Stufe 2 (Render) unverändert lassen
      return proben.filter(x => s(p(x)) !== p(x));
    });
    expect(drift).toEqual([]);
  });

  test('htmlToText zählt sichtbaren Text — Bilddaten zählen nicht', async ({ page }) => {
    await page.goto(DEMO_URL);
    const r = await page.evaluate(() => {
      const t = (window as any).__htmlToText as (h: string) => string;
      const big = '<p>Hi</p><img src="data:image/png;base64,' + 'A'.repeat(50000) + '">';
      return { visible: t(big), plain: t('<p>Zeile 1</p><p>Zeile 2</p>'), limits: (window as any).__richLimits };
    });
    expect(r.visible).toBe('Hi');
    expect(r.plain).toContain('Zeile 1');
    expect(r.plain).toContain('Zeile 2');
    expect(r.limits.text).toBe(2000);
    expect(r.limits.html).toBe(200000);
  });
});

test.describe('Rich-Text UI (Demo)', () => {

  test('Team-Post mit Formatierung überlebt das Absenden', async ({ page }) => {
    await loginAlsMia(page);
    await page.getByTestId('tile-teams').click();
    await page.getByTestId('team-row').first().click();
    await expect(page.getByTestId('posts')).toBeVisible();
    await setRichContent(page, 'post-input',
      '<b>Fett</b> und <span style="color: rgb(192, 57, 43)">rot</span>');
    await page.getByTestId('post-send').click();
    const posts = page.getByTestId('posts');
    await expect(posts).toContainText('Fett');
    await expect(posts.locator('b', { hasText: 'Fett' })).toBeVisible();
    await expect(posts.locator('span[style*="color"]', { hasText: 'rot' })).toBeVisible();
  });

  test('Demo-Post der Lehrkraft wird als Rich-Text gerendert', async ({ page }) => {
    await loginAlsMia(page);
    await page.getByTestId('tile-teams').click();
    await page.getByTestId('team-row').first().click();
    // MOCK p1 enthält <b>Dienstag</b> + farbige Gartenhandschuhe
    await expect(page.getByTestId('posts').locator('b', { hasText: 'Dienstag' })).toBeVisible();
  });

  test('Nachricht mit Rich-Text senden', async ({ page }) => {
    await loginAlsMia(page);
    await page.getByTestId('tile-nachrichten').click();
    await page.getByTestId('neue-nachricht').click();
    await page.getByTestId('lehrer-select').selectOption('Ko');
    await page.getByTestId('betreff-input').fill('Rich-Text-Frage');
    await setRichContent(page, 'inhalt-input', 'Findet die <u>Probe</u> statt?');
    await page.getByTestId('nachricht-senden').click();
    const karte = page.getByTestId('nachricht').first();
    await expect(karte).toContainText('Rich-Text-Frage');
    await expect(karte.locator('u', { hasText: 'Probe' })).toBeVisible();
  });

  test('Leerer Editor: Senden-Button bleibt deaktiviert', async ({ page }) => {
    await loginAlsMia(page);
    await page.getByTestId('tile-teams').click();
    await page.getByTestId('team-row').first().click();
    await expect(page.getByTestId('post-send')).toBeDisabled();
    // Nur ein Bild ohne Text zählt als sichtbarer Text 0 → weiterhin deaktiviert
    await setRichContent(page, 'post-input', '<img src="data:image/png;base64,iVBORw0KGgo=">');
    await expect(page.getByTestId('post-send')).toBeDisabled();
  });

  test('Toolbar ist vorhanden und beschriftet', async ({ page }) => {
    await loginAlsMia(page);
    await page.getByTestId('tile-teams').click();
    await page.getByTestId('team-row').first().click();
    const toolbar = page.getByRole('toolbar', { name: 'Formatierung' });
    await expect(toolbar).toBeVisible();
    await expect(toolbar.getByRole('button', { name: 'Fett' })).toBeVisible();
    await expect(toolbar.getByRole('button', { name: /Textfarbe/ }).first()).toBeVisible();
  });
});
