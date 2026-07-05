# Übergabe — KRS Schüler-Hub v1 (05.07.2026)

## Was ist das?
Zentraler Einstieg für alle ~455 Schüler:innen: Login mit dem **vorhandenen Projektwahl-Code** (`7B-A7K2`, gleicher QR-Brief), Dashboard mit App-Kacheln (Projektwoche mit Code-Durchreichung, Makerspace, SMV, Homepage), Klassen-Kalender, Teams mit Posts, Nachricht an Lehrkraft, Links & Downloads. **Lehrerdaten bleiben physisch getrennt** (anderes Supabase-Projekt, kein Code-Pfad dorthin).

## Dateien (Ordner `teams 2.0 …/schueler-hub/`)

| Datei | Inhalt |
|---|---|
| `ARCHITEKTUR-SCHUELER-HUB.md` | Ausführlicher Plan: Datentrennung, Module, Datenmodell, DSGVO, Phasen |
| `index.html` | Die App (Preact+htm, Single-File, Dual-Mode Demo/Produktiv) |
| `tenant.js` | Schul-Konfig: Branding, Modul-Kacheln, `teams_posting`-Schalter, Rechtliches |
| `krs-supabase-config.js` | Schüler-DB-Credentials (Publishable Key, Projektwahl-Projekt) |
| `migration-hub-v1.sql` | 7 neue `hub_`-Tabellen + 8 RPCs, additiv & idempotent, **noch nicht eingespielt** |
| `tests/e2e/smoke-schueler-hub.spec.ts` | 7 Playwright-Smoke-Tests — **alle grün** (7,8 s) |
| `playwright.config.ts`, `package.json` | Test-Setup (http-server Port 4180) |

## Stand
- ✅ App im **Demo-Modus voll lauffähig** (Demo-Code `MIA-TEST`), 7/7 E2E-Tests grün, mobil getestet (390 px Screenshots)
- ✅ **Produktiv-Fallback eingebaut:** Solange die Migration nicht eingespielt ist, loggt die App über das bestehende `get_schueler_status` ein und zeigt App-Kacheln + Links („Vorschau-Modus"-Banner). Sie funktioniert also **heute schon live**, ohne die DB anzufassen.
- ✅ Multi-Experten-Review durchgeführt; alle 🔴- und 🟡-Findings gefixt:
  - `REVOKE … FROM PUBLIC` auf `hub__check_code` + `hub_teams_aus_zuteilungen` (Default-Grant-Falle)
  - Admin-Policies an `is_app_user()` gebunden statt `USING (true)`
  - `SET search_path = public, pg_temp` auf allen 8 SECURITY-DEFINER-RPCs
  - Termine-LIMIT in Subquery; `t.aktiv`-Check beim Posts-Lesen
  - Code wird nach Login aus der URL entfernt (`history.replaceState`), `no-referrer`, `noopener noreferrer`
  - Nur-http(s)-Filter für Links (Frontend + DB-CHECK); supabase-js gepinnt (@2.45.4)
  - Datenschutz/Impressum-Footer; `teams_posting:false`-Schalter (Teams nur lesbar bis Lehrer-Panel da ist)
- ⬜ Migration einspielen (bewusst NACH den Projekttagen 21.–23.07.)
- ⬜ DSB/Petra: neuer Verarbeitungszweck (Schüler-Posts/-Nachrichten), Eltern-Info Art. 13, VVT-Ergänzung
- ⬜ Deploy als eigenes Repo

## Nächste Schritte (in Reihenfolge)

1. **Jetzt möglich — Review durch dich:** lokal öffnen:
   ```
   cd "/Users/nk/Downloads/Codex playground/teams 2.0 update macbook pro/schueler-hub" && npx http-server -p 4180 -c-1 .
   ```
   dann [http://localhost:4180/index.html?forceMode=demo](http://localhost:4180/index.html?forceMode=demo) → Code `MIA-TEST`
2. **Nachricht an Petra/DSB** (Vorlage kann ich formulieren) — parallel zur Projektwoche
3. **Nach den Projekttagen:** `migration-hub-v1.sql` im [SQL-Editor der Schüler-DB](https://supabase.com/dashboard/project/uzynvvtsyjfmtywsfxtz/sql/new) ausführen; danach prüfen, dass [Auth-Signups deaktiviert](https://supabase.com/dashboard/project/uzynvvtsyjfmtywsfxtz/auth/providers) sind
4. `hub_lehrer` (Opt-in-Kollegium) + `hub_links` + `hub_termine` befüllen (Admin-UI dafür = Phase 2, bis dahin SQL/Table-Editor)
5. Optional: `SELECT hub_teams_aus_zuteilungen();` → erzeugt Teams aus den Projektwoche-Zuteilungen
6. **Deploy:** neues Repo `kurpfalz-realschule/krs-schueler-hub` (GitHub Pages + Test-Gate wie gehabt); Live-Gang nach Testlauf-Protokoll (Test-Code komplett durchspielen, Termin ankündigen)

## Wichtige Entscheidungen (nicht neu diskutieren)
- Schüler-Hub nutzt die **Projektwahl-DB** (Codes bereits verteilt!) — `hub_`-Tabellen, später als Block umziehbar
- **Code = Bearer-Token** (bewusst, wie Projektwahl) → Rate-Limits in RPCs (10 Posts/10 min, 5 Nachrichten/24 h), keine sensiblen Inhalte, Plaintext-Rendering
- Kein anon-SELECT auf irgendeiner Tabelle — alles über SECURITY-DEFINER-RPCs
- Module = Konfig-Einträge in `tenant.js`; v1 verlinkt Apps (kein iframe), Projektwoche bekommt `?code=` durchgereicht

## Offene Punkte
- Perpustakaan-Schnittstelle: klären, was das System ist/kann
- Klassenarbeitsplan-Sync (Lehrkraft gibt Eintrag frei → `hub_termine`): Phase 2, GAS-Seite
- Lehrer-Panel (Teams verwalten, Nachrichten beantworten): Phase 2, als Kachel im **Lehrer**-Hub

## Einstiegs-Prompt für neuen Chat
> Lies `schueler-hub/UEBERGABE-schueler-hub-2026-07-05.md` und `schueler-hub/ARCHITEKTUR-SCHUELER-HUB.md` im Ordner „teams 2.0 update macbook pro". Der KRS Schüler-Hub v1 ist gebaut und reviewt (7/7 Tests grün), Migration noch nicht eingespielt. Weiter geht's mit: [Nachricht an Petra/DSB | Migration + Befüllung | Deploy krs-schueler-hub | Lehrer-Panel Phase 2].

*Hinweis Testumgebung: In der Cowork-Sandbox laufen Playwright-Tests nur aus einem lokalen Verzeichnis (nicht vom gemounteten Ordner) — auf deinem Mac normal per `npm test`.*
