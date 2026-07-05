# Übergabe — Schüler-Hub S1 (Rich-Text) + DSB-Anfrage · 05.07.2026 (abends)

**Kontext:** Sprint-Plan `SPRINT-PLAN-SCHUELER-HUB-AUSBAU-2026-07-05.md`. Diese Session (Sonnet-tauglich gearbeitet): DSB-Anfrage gebündelt + **S1 komplett umgesetzt**. Nächste Session = **Opus-Sprint** (S3 Makerspace/RLS, nach dem 23.07. bzw. Vorbereitung jetzt).

---

## 1. Was in dieser Session passiert ist

### DSB-Anfrage gebündelt ✅
- Neue Datei: `../DSB-Anfrage-GEBUENDELT-Hub-Makerspace-SMV-2026-07-05.md` — **eine** Anfrage an Petra/DSB für alle drei Module (Hub + Makerspace + SMV), ersetzt den Einzel-Entwurf vom Mittag.
- Enthält Mail-Text (du-Ton) + DSB-Anlage mit Tabellen pro Modul (Datenkategorien, Zugriffsschutz, Löschkonzept, Zeitplan).
- ⚠️ **Vor Versand gegenlesen:** Die Makerspace-/SMV-Detailvorlagen (`C-SPRINT-DSGVO-VORLAGEN.md` im Makerspace-Ordner, `smv/SUPABASE-PLAN.md`) waren in dieser Session **nicht gemountet** — die Abschnitte basieren auf Sprint-Plan + Architektur-Doku. Bitte prüfen, ob dort Punkte stehen, die fehlen.
- Wichtig korrigiert: „nur reiner Text" aus dem alten Entwurf ist raus — mit S1 gibt es formatierten Text + eingebettete Bilder (steht jetzt ehrlich drin).

### S1 Rich-Text-Editor ✅ (Posts UND Nachrichten — Entscheidung Norbert)
Geänderte Dateien: `index.html`, `migration-hub-v1.sql`, neu `tests/e2e/smoke-richtext.spec.ts`.

| Baustein | Umsetzung |
|---|---|
| DOMPurify | cdnjs 3.0.9 gepinnt + jsdelivr-Fallback + Legacy-Sanitizer im Code (Skill `dompurify-cdn`) |
| **Zwei-Stufen-Falle gelöst** | Paste-Simplifier **ist wörtlich dieselbe Funktion** wie der Render-Sanitizer (`simplifyPastedHtml = sanitizeHtml`) → Whitelist-Drift/silent data loss **per Konstruktion unmöglich** (Connect-Kernlektion) |
| Helfer | `safeColorVal`, `filterSafeStyle`, `isSafeImageSrc` 1:1 aus Skill `wysiwyg-paste-farben-bilder`; nur Farb-Styles, Bilder nur `http(s)` + `data:image/*` |
| Farb-Toolbar | `styleWithCSS=true` vor `foreColor` (keine `<font>`-Falle); F/K/U + 5 Farben + Formatierung-entfernen; `aria-label`s, 44px-Targets |
| Zeichen-Limit | sichtbarer Text via `htmlToText` ≤ 2000; Gesamt-HTML ≤ 200 000 (Notbremse); Base64-Bilder zählen NICHT als Text |
| Rendering | `ContentView`: Rich-HTML → `sanitizeHtml` + `dangerouslySetInnerHTML`; Alt-/Plaintext-Posts weiter wie bisher (`pre-wrap`) — abwärtskompatibel |
| Editor | `RichEditor` (contentEditable, unkontrolliert, Clear nach Senden via Effect) — stale-closure-sicher, Paste behält Fett/Farben/Listen/Bilder |
| Migration | `migration-hub-v1.sql`: CHECKs + RPC-Validierung 2000 → 200 000; zusätzlich idempotenter ALTER-Block (Abschnitt 5b) falls v1 schon alt eingespielt war. **Migration weiterhin NICHT eingespielt** (bewusst, nach 23.07.) |
| Test-Hooks | `window.__sanitizeHtml`, `__simplifyPastedHtml`, `__htmlToText`, `__richLimits` |
| E2E | `smoke-richtext.spec.ts`: 9 neue Tests (4 Hook-basiert inkl. Negativ-Fälle `javascript:`-Bild, `data:text/html`, `url()`-Style; 5 UI). Gesamt jetzt **16 Tests** |

### Verifikation (Sandbox)
- `node --check` auf beiden Inline-Scripts: grün.
- `playwright test --list`: 16 Tests kompilieren.
- **16/16 Offline-Logik-Checks** (jsdom + dompurify gegen den ECHTEN extrahierten Quellcode): alle grün — inkl. Idempotenz-Check (kein Drift), XSS-Negativfälle, htmlToText-Bildignorierung.
- ⚠️ Voller Browser-E2E-Lauf in der Sandbox nicht möglich (Chromium-Install schlägt fehl, bekannte Einschränkung). **Läuft im Test-&-Deploy-Gate beim Push** bzw. lokal: `cd schueler-hub && npm test`.

## 2. Entscheidungen aus dieser Session (nicht neu diskutieren)
1. **Rich-Text für Posts UND Nachrichten** (Norbert, 05.07.) — nicht nur Posts.
2. **`ms_*` und `smv_*` in die geteilte Schüler-DB** `uzynvvtsyjfmtywsfxtz` (Norbert, 05.07.) — ein Code, eine Liste, ein Backup.
3. Nur-Bild-Posts ohne Text sind **nicht sendbar** (sichtbarer Text erforderlich) — bewusst konservativ für v1; bei Bedarf später lockern.
4. Sanitizer-Architektur: EINE Funktion für beide Stufen statt zwei synchron zu haltender Configs.

## 3. Offene Punkte / bekannte Grenzen
- `execCommand` ist deprecated, funktioniert aber in allen Zielbrowsern (gleiches Muster wie Connect) — kein Handlungsbedarf.
- Screenshot-Paste (Bild-**Datei** im Clipboard) wird in v1 **nicht** eingefügt (nur HTML-Inline-Bilder aus Word/Webseiten). Datei-Upload kommt ohnehin nicht für Schüler (DSGVO) — ok so.
- Demo-Post p1 ist jetzt Rich (zeigt Fett + Farbe im Demo-Modus).
- DSB-Anfrage: Makerspace-/SMV-Abschnitte gegen die Original-Vorlagen prüfen (Ordner nicht gemountet, s. o.).

## 4. Was nur Norbert kann (vor dem Opus-Sprint)
| Wann | Aktion |
|---|---|
| Jetzt | DSB-Anfrage gegenlesen + an Petra schicken |
| Jetzt | S1 committen/pushen → Gate läuft die 16 Tests (Repo `kurpfalz-realschule/krs-schueler-hub`; vorher ggf. `.git/*.lock`-Dateien löschen, s. Übergabe vom Mittag) |
| Vor S3 | GitHub-Settings Makerspace-Repo (Pages Source „GitHub Actions", Workflow-Rechte) |
| Vor S3 | Backup/PITR der Schüler-DB bestätigen ([Dashboard](https://supabase.com/dashboard/project/uzynvvtsyjfmtywsfxtz)) |
| Nach 23.07. | `migration-hub-v1.sql` einspielen ([SQL-Editor](https://supabase.com/dashboard/project/uzynvvtsyjfmtywsfxtz/sql/new)) |

## 5. Nächster Sprint (Opus) — S3 Makerspace + ein Code für alles
Laut Sprint-Plan: `ms_*`-Tabellen in die Schüler-DB, Migration A1/A2 dort einspielen (CHECK→ACTION→UNDO), A3–A6 (RLS default-DENY, Buchungs-RPCs aufs `hub__check_code`-Muster, Anti-Enumeration, `SET search_path` + `REVOKE FROM PUBLIC`), Lehrer-Buchungsaufsicht via `is_app_user()`, Kachel scharf schalten. Skills: `supabase-rls-haertung`, `dsgvo-rls-pii-lockdown`, `sichere-massen-sql-migration`, `krs-projekt-playbook`.
**Achtung Zeitanker:** DB-Migrationen erst **nach dem 23.07.** — vorher kann Opus aber Migrations-SQL + Review vorbereiten.

---

## Einstiegs-Prompt für den Opus-Sprint (kopieren)

> Lies im Ordner „teams 2.0 update macbook pro": `schueler-hub/UEBERGABE-SCHUELER-HUB-S1-RICHTEXT-2026-07-05.md`, `schueler-hub/SPRINT-PLAN-SCHUELER-HUB-AUSBAU-2026-07-05.md` und `schueler-hub/ARCHITEKTUR-SCHUELER-HUB.md`. Stand: S1 (Rich-Text) fertig + verifiziert, DSB-Anfrage liegt zum Versand bereit, Migration v1 bewusst noch nicht eingespielt. Entscheidungen: Rich-Text für Posts UND Nachrichten; `ms_*`/`smv_*` kommen in die geteilte Schüler-DB `uzynvvtsyjfmtywsfxtz`. Jetzt kommt **S3 (Opus): Makerspace in die Schüler-DB + Code-Login vereinheitlichen** — Migrations-SQL nach dem Muster CHECK→ACTION→UNDO vorbereiten, RLS A3–A6 (default-DENY, `hub__check_code`-Muster, Anti-Enumeration, `SET search_path` + `REVOKE FROM PUBLIC`), Lehrer-Buchungsaufsicht über `is_app_user()`. Der Makerspace-Projektordner muss dafür gemountet werden. Kein Einspielen in die DB vor dem 23.07. — nur vorbereiten und reviewen.
