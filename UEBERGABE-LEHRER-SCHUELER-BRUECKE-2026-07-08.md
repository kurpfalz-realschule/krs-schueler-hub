# Übergabe — Lehrer-Schüler-Brücke fertiggebaut · 08.07.2026

**Kontext:** Umsetzung des Plans `PLAN-LEHRER-SCHUELER-BRUECKE-2026-07-08.md`.
Komplett gebaut bis zum Deploy-Befehl. DB-Migration bewusst NICHT eingespielt (nach 23.07.).

---

## 1. Was gebaut wurde

| Datei | Neu/Geändert | Inhalt |
|---|---|---|
| `migration-hub-v2.sql` | **neu** | 3 Tabellen (hub_ankuendigungen, hub_zugriff_log, hub_einstellungen), hub_lehrer +auth_id/+email, 12 Funktionen, RLS default-DENY, alle Lehrer-RPCs `is_app_user()`-gated + anon-revoked |
| `lehrer-panel.html` | **neu** | Standalone Preact-Panel: Login, Postfach+Antworten, Ankündigungen, Schüler-Vorschau, Protokoll; Dual-Mode (Demo/Produktiv) |
| `index.html` | geändert | Ankündigungs-Block im Dashboard, Transparenz-Hinweise (Nachrichten + Teams), `getAnkuendigungen` mit Fallback |
| `.github/workflows/test-and-deploy.yml` | geändert | `lehrer-panel.html` in die Deploy-Kopierliste aufgenommen (sonst nicht deployed!) |
| `tests/e2e/smoke-lehrer-panel.spec.ts` | **neu** | 8 Tests (Login, enger Filter, Antworten, Ankündigung, Vorschau, Protokoll, Sanitizer) |
| `tests/e2e/smoke-ankuendigungen.spec.ts` | **neu** | 2 Tests (Ankündigungs-Block, Transparenz-Hinweis) |
| `../krs-hub/index.html` | geändert | Kachel „Schüler-Hub" (Lehrer-Panel) im Lehrer-Hub |

## 2. Architektur der Brücke (kurz)

- Keine DB-Zusammenlegung. Das Panel spricht **nur** die Schüler-DB (`uzynvvtsyjfmtywsfxtz`).
- Lehrkraft meldet sich im Panel an (Produktiv: Supabase-Auth in der Schüler-DB) → alle Zugriffe über `hub_lehrer_*`-RPCs, intern durch `is_app_user()` abgesichert, `anon` explizit entzogen.
- **Sicht-Modus** `lehrer_sicht` in `hub_einstellungen`, Default `nur_eigene`. „breit" erst nach DSB-Freigabe per UPDATE (Snippet in der Migration §7b).
- **Jeder** Lehrer-Zugriff (Postfach ansehen, antworten, Ankündigung, Vorschau) wird in `hub_zugriff_log` protokolliert → Reiter „Protokoll" im Panel.
- Deine 3 Entscheidungen sind umgesetzt: breiter Einblick (hinter DSB-Gate), Ankündigungen als eigener Kanal **und** Team-Post möglich, alle Lehrkräfte dürfen posten.

## 3. Verifikation (in dieser Session gelaufen)

- `node --check` auf allen Inline-Scripts (index.html + lehrer-panel.html): **grün**.
- `playwright test --list`: **25 Tests** kompilieren (16 alt + 9 neu).
- **14/14 Offline-Logikchecks** gegen den echten Panel-Quellcode (Node-VM, forceMode=demo): grün — u. a. enger Filter zeigt nur eigene, Fremd-Antwort im engen Modus verweigert, klassen-scoped Vorschau, Audit wächst.
- SQL-Strukturcheck: `$$` paarig, Klammern balanciert, 12 Funktionen, alle Lehrer-RPCs mit GRANT authenticated + REVOKE anon.
- ⚠️ Voller Browser-E2E in der Sandbox nicht möglich (fehlende System-Libs, kein sudo — bekannte Grenze). **Läuft im Test-&-Deploy-Gate beim Push.**

### Experten-Review — behobene/offene Punkte
- 🔴 **Postgres-Cast-Falle** `ziel_wert::INT` → auf Text-Vergleich (`ziel_wert = stufe::TEXT`) umgestellt, damit `'7b'` einer Klassen-Zeile keinen Laufzeitfehler wirft. **Behoben.**
- 🟢 Trennung Schüler/Lehrer-DB gewahrt (kein Lehrer-Key im Panel).
- 🟢 Default-DENY + is_app_user()-Gate + anon-Revoke auf allen neuen RPCs.
- 🟡 **Keine Rate-Limits** auf den Lehrer-RPCs (Lehrkräfte = vertraut/authentifiziert) — bewusst; bei Bedarf später ergänzbar.
- 🟡 Panel im Produktiv-Modus **vor** eingespielter Migration zeigt Verbindungsfehler — unkritisch, da erst nach dem 23.07. produktiv genutzt; Demo läuft immer.

## 4. Was nur Norbert kann

| Wann | Aktion |
|---|---|
| Jetzt | Deployen (2 Befehle unten) → Gate läuft die 25 Tests, deployt bei Grün |
| Vor Scharfschaltung | „breiter Einblick" in die DSB-Anfrage an Petra ergänzen + Freigabe abwarten |
| Nach 23.07. | `migration-hub-v2.sql` im SQL-Editor einspielen (setzt v1 voraus) |
| Nach Migration | je Lehrkraft `hub_lehrer.email` (oder `auth_id`) setzen — §7a der Migration |
| Nach DSB-OK | `UPDATE hub_einstellungen SET wert='breit' WHERE schluessel='lehrer_sicht';` |

## 5. Deploy (Terminal)

**Schüler-Hub (Panel + Migration + Tests):**
```
cd "/Users/nk/Downloads/Codex playground/teams 2.0 update macbook pro/schueler-hub" && git add -A && git commit -m "Lehrer-Schueler-Bruecke: Lehrer-Panel, Ankuendigungen, Migration hub_v2, Transparenz+Audit, E2E" && git push
```

**Lehrer-Hub (Kachel):**
```
cd "/Users/nk/Downloads/Codex playground/teams 2.0 update macbook pro/krs-hub" && git add index.html && git commit -m "Hub: Kachel Schueler-Hub (Lehrer-Panel) verlinkt" && git push
```

**Links nach dem Push:**
- Gate/Actions Schüler-Hub: https://github.com/kurpfalz-realschule/krs-schueler-hub/actions
- Live Lehrer-Panel: https://kurpfalz-realschule.github.io/krs-schueler-hub/lehrer-panel.html
- Live Schüler-Hub: https://kurpfalz-realschule.github.io/krs-schueler-hub/index.html
- Actions Lehrer-Hub: https://github.com/kurpfalz-realschule/krs-hub/actions
- SQL-Editor (Migration nach 23.07.): https://supabase.com/dashboard/project/uzynvvtsyjfmtywsfxtz/sql/new

**Lokal vorab ansehen (Demo, ohne Deploy):**
```
cd "/Users/nk/Downloads/Codex playground/teams 2.0 update macbook pro/schueler-hub" && npx http-server -p 4180 -c-1 .
```
Dann öffnen: http://localhost:4180/lehrer-panel.html?forceMode=demo
