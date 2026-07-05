# KRS Schüler-Hub

Zentraler Einstieg für die Schüler:innen der Kurpfalz-Realschule Schriesheim.
Login mit dem vorhandenen Projektwahl-Code (gleicher QR-Brief), Dashboard mit
App-Kacheln, Klassen-Kalender, Teams, Nachricht an Lehrkraft, Links & Downloads.

**Stack:** Preact + htm, Single-File (`index.html`), Dual-Mode (Demo/Produktiv),
Supabase (Schüler-DB = Projektwahl-Projekt, physisch getrennt von der Lehrer-DB).

## Modi

| Modus | Wann | Verhalten |
|---|---|---|
| Demo | `?forceMode=demo`, Code `MIA-TEST` | Mock-Daten, keine DB |
| Vorschau (Produktiv-Fallback) | Migration noch nicht eingespielt | Login über `get_schueler_status`, Kacheln + Links, Banner „Vorschau-Modus" |
| Produktiv | nach `migration-hub-v1.sql` | Volle Funktion (Teams, Termine, Nachrichten) |

## Entwicklung & Tests

```bash
npm install
npm test          # Playwright-Smoke-Tests (Demo-Modus, Port 4180)
```

Lokal ansehen: `npx http-server -p 4180 -c-1 .` → http://localhost:4180/index.html?forceMode=demo

## Deploy

Push auf `main` → GitHub Actions führt die Tests aus und deployt **nur bei Grün**
auf GitHub Pages (Source: GitHub Actions). Details: `.github/workflows/test-and-deploy.yml`.

## Wichtige Dateien

- `ARCHITEKTUR-SCHUELER-HUB.md` — Plan: Datentrennung, Module, Datenmodell, DSGVO, Phasen
- `migration-hub-v1.sql` — 7 `hub_`-Tabellen + 8 RPCs, additiv & idempotent (Einspielen erst nach den Projekttagen)
- `tenant.js` — Schul-Konfig (Branding, Modul-Kacheln, `teams_posting`-Schalter)
