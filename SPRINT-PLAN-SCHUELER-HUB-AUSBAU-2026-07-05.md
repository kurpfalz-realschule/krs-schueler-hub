# Sprint-Plan: Schüler-Hub Ausbau (Stand 05.07.2026)

**Leitidee:** Ein Schüler-Konto (= Anmelde-Code), eine Schüler-Datenbank (`uzynvvtsyjfmtywsfxtz`), alle Schüler-Apps unter einem Dach. Alles, was in Connect/Projektwahl/Makerspace teuer gelernt wurde, wird hier wiederverwendet — nicht neu erfunden.

**Zeitanker:** Projekttage 21.–23.07. · Schulfest 24.07. · Sommerferien ab 30.07.
→ S1–S2 sind vor den Projekttagen gefahrlos (nur Frontend/Demo). Alles mit DB-Migration (S3 ff.) **nach dem 23.07.** Go-Live für Schüler realistisch: **Schuljahresbeginn September** — sauber, mit DSB-Freigabe, statt gehetzt in der letzten Schulwoche.

---

## Sprint-Übersicht

| # | Sprint | Modell | Hängt ab von | Aufwand |
|---|--------|--------|--------------|---------|
| S1 | Rich-Text-Editor (Posts + Nachrichten) | Sonnet (Muster liegt vor) | — | 0,5–1 Tag |
| S2 | Dateiablage + IServ/Office-Anbindung | Opus (Storage-Policies) → Sonnet | — | 1 Tag |
| S3 | Makerspace live + Code-Login vereinheitlichen | Opus (RLS A3–A6) | Migration-Fenster nach 23.07. | 1–2 Tage |
| S4 | SMV auf Supabase + Kachel scharf | Opus (Migration) → Sonnet (UI) | S3-Erfahrung, deine Freigaben | 1–2 Tage |
| S5 | Lehrer-Panel + Klassenarbeitsplan-Sync | Opus | hub-Migration eingespielt | 2 Tage |
| S6 | Politur, PWA, Deploy-Gate, Go-Live | Sonnet | S1–S5 | 1 Tag |

---

## S1 — Rich-Text wie in KRS Connect 📝

**Skills:** `wysiwyg-paste-farben-bilder`, `dompurify-cdn`, `stale-closure-cdn-react-falle`

Team-Posts (und optional Nachrichten) bekommen das erprobte Connect-Eingabefeld: contentEditable, Paste behält **Fett/Farben/Listen/Bilder**, Farb-Button-Toolbar.

- [ ] DOMPurify via CDN + Legacy-Fallback einbinden (`dompurify-cdn`)
- [ ] **Zwei-Stufen-Sanitizing** — die teuerste Connect-Lektion: Paste-Simplifier UND Render-Sanitizer müssen dieselben Tags/Attrs erlauben (`style`, `img`, `ADD_DATA_URI_TAGS`), sonst verschwinden Farben/Bilder nach dem Absenden (silent data loss)
- [ ] `filterSafeStyle` / `safeColorVal` / `isSafeImageSrc` 1:1 aus dem Skill übernehmen (nur Farb-Styles, nur `http(s)` + `data:image/*`)
- [ ] Farb-Button mit `styleWithCSS=true` vor `foreColor` (sonst `<font>`-Falle)
- [ ] Zeichen-Limit: **sichtbaren Text** zählen (`htmlToText`), separates HTML-Gesamtlimit (~1 MB in `hub_team_posts` — kleiner als Connect, Schüler-Posts brauchen keine 4 MB)
- [ ] DB-Anpassung in Migration v2: `hub_team_posts.inhalt`-CHECK von 2000 auf Text-Länge umstellen (Prüfung clientseitig via htmlToText, serverseitig `char_length ≤ 200000` als Notbremse); Render immer durch `sanitizeHtml`
- [ ] Stale-Closure-Check am neuen Composer (Submit per `useRef`, `setState(prev=>…)`)
- [ ] E2E: Negativ-Fälle als Test-Hooks (`window.__sanitizeHtml`) — `javascript:`-Bild, `data:text/html`, `url()`-Style müssen rausfliegen

**Entscheidung für dich:** Rich-Text auch für Nachrichten an Lehrkräfte, oder dort bewusst Plaintext (einfacher zu moderieren)? *Mein Vorschlag: Posts rich, Nachrichten plain.*

## S2 — Dateiablage + IServ/Office 📁

**Skills:** `supabase-webapp-integration`, Lektion „Signed URLs" aus dem Plattform-Härtungs-Sprint (S1, 03.07.)

Zwei Ebenen — schnell und sauber getrennt:

**2a Sofort (reine Konfig, heute machbar):** Schüler haben IServ-Konten und darüber das Office-Paket → Kacheln in `tenant.js`:
- [x] IServ-Kachel (Mail, Dateien, Stundenplan) — *bereits eingetragen*
- [x] Office/M365-Kachel — *bereits eingetragen; URL bitte prüfen: nutzt ihr login.microsoftonline.com oder den IServ-Office-Einstieg?*

**2b Hub-Dateiablage (nach Migration):** Lehrkräfte stellen Dateien bereit (AB, Elternbriefe, Pläne), Schüler laden herunter — **kein Schüler-Upload in v1** (DSGVO/Moderation).
- [ ] Storage-Bucket `hub-dateien` (privat, kein public read!)
- [ ] Tabelle `hub_dateien` (titel, pfad, team_id ODER klasse ODER global, hochgeladen_von, größe, mime)
- [ ] Auslieferung über **Signed URLs** via SECURITY-DEFINER-RPC `hub_get_datei_url(p_code, p_datei_id)` — prüft Team-Mitgliedschaft/Klasse, TTL 5 min (exakt das Muster aus dem Härtungs-Sprint der Lehrer-Plattform)
- [ ] Upload nur über Lehrer-Panel (S5) bzw. übergangsweise Table-Editor
- [ ] Anzeige: eigener Bereich „Dateien" + Datei-Chips im Team
- [ ] MIME/Größen-Whitelist beim Upload (Office-Formate, PDF, Bilder; ≤ 20 MB)

## S3 — Makerspace live + ein Code für alles 🛠️

**Skills:** `supabase-rls-haertung`, `dsgvo-rls-pii-lockdown`, `sichere-massen-sql-migration`, `krs-projekt-playbook`

Stand Makerspace (Handover 04.07.): Zeitmodell-Migration A1/A2 fertig + reviewt, 52 Logik-Tests grün, CI steht. **Harte Regel: kein Go-Live vor A3–A6.** Genau die ziehen wir jetzt durch — und zwar so, dass der Makerspace die **Schüler-DB mitnutzt**:

- [ ] **Architektur-Entscheidung (Vorschlag):** `ms_*`-Tabellen in die Schüler-DB `uzynvvtsyjfmtywsfxtz` statt eigenes Projekt — ein Code, eine Schülerliste, ein Backup; Projektwahl-Tabellen bleiben unberührt (additiv, wie `hub_`)
- [ ] Migration A1/A2 dorthin einspielen (CHECK → ACTION → UNDO)
- [ ] A3–A6: RLS default-DENY, Buchungs-RPCs auf `hub__check_code`-Muster umstellen (**ein** Anmelde-Code statt separatem Makerspace-Code!), Anti-Enumeration, alle Definer-RPCs mit `SET search_path` + `REVOKE FROM PUBLIC` (unsere Default-Grant-Lektion)
- [ ] Lehrer-Seite: Buchungsaufsicht über Projektwahl-Admin-Login (`is_app_user()`)
- [ ] Deploy: GitHub Pages Source „GitHub Actions" + Workflow-Rechte (**machst du**, siehe `DEPLOY-makerspace.md`), kein `--force` auf main
- [ ] Kachel im Schüler-Hub scharf: `url` eintragen, `passCode:true` reicht — Rest ist Konfig
- [ ] Echten KRS-Pausenplan in `SETTINGS.pausen` (**nur du**)
- [ ] DSB-Vorlagen aus `C-SPRINT-DSGVO-VORLAGEN.md` mit dem Schüler-Hub-Anschreiben **bündeln** (eine DSB-Anfrage für Hub+Makerspace+SMV statt drei)

## S4 — SMV auf Supabase + Kachel scharf 🏛️

**Skills:** `sichere-massen-sql-migration`, `dual-login-schul-app`, `dsgvo-rls-pii-lockdown`

Der SMV-Plan (`smv/SUPABASE-PLAN.md`) sieht genau das vor: `smv_*`-Namensraum im **geteilten Schüler-Projekt**, strikt additiv, jede SQL vor Ausführung von dir freigegeben. Umsetzung nach Plan:

- [ ] Read-only-Inventur der Schüler-DB (Namenskollisionen ausschließen)
- [ ] Additive `smv_*`-Migration (Events, Polls, Ideas, …) + RLS default-DENY, Zugriff per RPC
- [ ] Rollen: Klassensprecher-Erkennung über neue Spalte/Tabelle `smv_rollen(schueler_code, rolle)` → Login mit demselben Anmelde-Code, SMV-Funktionen nur für Klassensprecher; Ideenbox bleibt anonym (QR)
- [ ] DataService der SMV-App von localStorage auf Dual-Mode umstellen (Muster: Schüler-Hub/Projektwahl)
- [ ] Deploy als `krs-smv` + Kachel scharf schalten
- [ ] **Nur du:** Backup/PITR bestätigen, jede Migration freigeben

## S5 — Lehrer-Panel + Klassenarbeitsplan-Sync 👨‍🏫

**Skills:** `modul-hub-iframe-shell`, `admin-role-guard`, `gas-supabase-sync`, `krs-klassenarbeitsplan`

Damit Teams, Nachrichten-Antworten, Termine und Dateien nicht ewig über den Table-Editor laufen:

- [ ] `schueler-hub-lehrer.html` (eigene kleine App, gleiche Schüler-DB, Login = Projektwahl-Admin-Auth/`is_app_user()`): Teams anlegen + Mitglieder per **CSV-Import** (`csv-personenliste-import-export`: Header-Erkennung, Vorschau, BOM), Nachrichten-Inbox mit Antworten, Termine + Links + Dateien pflegen, Posts moderieren/löschen (Betroffenenrechte!)
- [ ] Als Kachel in den **Lehrer**-Hub einhängen (ein `CONFIG.MODULES`-Eintrag, iframe-Muster)
- [ ] `hub_lehrer`-Self-Service: Opt-in/Opt-out für „Schüler dürfen mich anschreiben"
- [ ] **Klassenarbeitsplan-Schnittstelle:** im Lehrer-Klassenarbeitsplan (GAS-Backend) pro Eintrag Checkbox „für Klasse sichtbar" (Default aus); GAS-Sync schreibt freigegebene Einträge als `hub_termine` (quelle='klassenarbeitsplan') — Push Lehrer→Schüler, minimale Felder (Klasse, Fach, Datum), nie umgekehrt (`gas-supabase-sync`-Muster)
- [ ] Danach `teams_posting` produktiv auf `true` (Moderationsweg existiert jetzt)

## S6 — Politur, PWA & Go-Live ✨

**Skills:** `unread-badge-system`, `pwa-offline-cache`, `sw-update-notification`, `mobile-touch-a11y-quickwins`, `playwright-webapp-testing`, `dsgvo-schul-webapp-bw`, `live-gang-testlauf-protokoll`

- [ ] Unread-Badges auf Kacheln (neue Posts seit letztem Besuch, beantwortete Nachrichten) — localStorage-Lesestände, Muster aus Connect
- [ ] PWA: Manifest + Service Worker (network-first für index.html!) + **Update-Banner** (`sw-update-notification` — sonst stale-Version-Falle nach jedem Deploy)
- [ ] A11y-Quickwins: Touch-Targets ≥ 44 px prüfen, ESC-Hierarchie, aria-labels, Empty-States (Checkliste aus dem Skill)
- [ ] Deploy-Repo `kurpfalz-realschule/krs-schueler-hub` mit **Test-&-Deploy-Gate** (Playwright vor Pages-Deploy, `workflow_dispatch`-Fallback wegen der Re-run-Artefakt-Falle)
- [ ] DSGVO-Ampel (`dsgvo-schul-webapp-bw`) über das Gesamtpaket: VVT, Art.-13-Elterninfo, Löschkonzept, AVV — **eine** Doku für Hub+Makerspace+SMV
- [ ] **Live-Gang-Protokoll:** Test-Schüler-Code komplett durchspielen (Login → Post → Nachricht → Makerspace-Buchung → Datei), Go-Live-Termin ankündigen, Phase-Gates prüfen — v42-Lektion: nie still live

---

## Was nur du tun kannst (gesammelt)

| Wann | Aktion |
|------|--------|
| Jetzt | Office/M365-Einstiegs-URL bestätigen (IServ-Office oder microsoftonline?) |
| Jetzt | Entscheidung: Rich-Text auch für Lehrer-Nachrichten? `ms_*`/`smv_*` in die Schüler-DB (Empfehlung) oder getrennt? |
| Vor S3 | **Eine gebündelte DSB/Petra-Anfrage** (Hub + Makerspace + SMV) — Vorlagen liegen vor, ich baue sie zusammen |
| Vor S3 | GitHub-Settings Makerspace-Repo (Pages Source, Workflow-Rechte) + Push per SSH |
| Vor S3/S4 | Backup/PITR der Schüler-DB bestätigen; Migrationen im SQL-Editor ausführen ([SQL-Editor](https://supabase.com/dashboard/project/uzynvvtsyjfmtywsfxtz/sql/new)) |
| S3 | Echter KRS-Pausenplan für Makerspace |
| S6 | Go-Live-Termin festlegen + ankündigen (Schuljahresbeginn empfohlen) |

## Reihenfolge-Empfehlung

**Diese Woche (vor Projekttagen):** S1 (Rich-Text) + S2a erledigt + DSB-Anfrage raus.
**Nach dem 23.07. / Ferien:** hub-Migration v1 einspielen → S3 Makerspace → S2b Dateien → S4 SMV.
**Vor Schuljahresbeginn:** S5 Lehrer-Panel → S6 Go-Live-Paket.

*Jeder Sprint endet mit Expertenreview + Übergabe (wie gehabt). Nächster konkreter Schritt auf Zuruf: S1 starten oder DSB-Anschreiben formulieren.*
