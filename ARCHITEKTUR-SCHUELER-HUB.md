# KRS Schüler-Hub — Architekturplan v1

**Stand:** 5. Juli 2026 · **Autor:** Claude (mit Norbert)
**Ziel:** Ein zentraler Einstiegspunkt für alle ~455 Schüler:innen der KRS — Login so einfach wie bei der Projektwahl (Code `7B-A7K2`), Zugang zu allen Schüler-Apps, Klassen-Kalender, Teams und Lehrer-Kontakt. **Strikte Trennung von Lehrerdaten.**

---

## 1. Grundprinzip: Zwei Welten, zwei Datenbanken

| | Lehrer-Welt | Schüler-Welt |
|---|---|---|
| Supabase-Projekt | `ooejsfixxiuobrpqgfqm` (krs-connect) | `uzynvvtsyjfmtywsfxtz` (krs-projektwahl) |
| Login | E-Mail + Passwort (Supabase Auth) | Anmelde-Code `7B-A7K2` (RPC, kein Account) |
| Apps | Hub, Connect, Klassenarbeitsplan, iPad-Buchung | **Schüler-Hub (neu)**, Projektwahl, Makerspace*, SMV* |
| Frontend-Zugriff | authenticated + RLS | ausschließlich SECURITY-DEFINER-RPCs |

**Die Trennung ist physisch:** Der Schüler-Hub kennt die Lehrer-Datenbank nicht — kein Key, keine URL, keine Tabelle. Es gibt keinen Code-Pfad, über den Schüler an Connect-Posts, Kollegiumslisten oder Lehrer-Kommunikation kommen könnten. Lehrer-Informationen erscheinen in der Schüler-Welt nur als **Kürzel + Anzeigename** in der neuen Tabelle `hub_lehrer` (Opt-in, vom Admin gepflegt) — das ist dieselbe Öffentlichkeitsstufe wie auf der Schulhomepage.

**Warum die Projektwahl-DB mitnutzen (Entscheidung Norbert, 05.07.2026):**
1. Die 455 Anmelde-Codes sind bereits verteilt (Serienbriefe mit QR) — kein neuer Rollout nötig.
2. `get_schueler_status(code)` als Login-RPC existiert, ist getestet und produktiv.
3. Die Schülerliste (`schueler`) wird bereits dort gepflegt.
4. Alle neuen Tabellen tragen das Präfix `hub_` — sie berühren keine Projektwahl-Tabelle und sind später als Block in ein eigenes Projekt umziehbar.

## 2. Login-Flow (wiederverwendet)

```
QR/Link ?code=7B-A7K2  ──►  Schüler-Hub index.html
                              │ 1. code aus URL oder localStorage (krs_sh_code)
                              │ 2. rpc get_schueler_status(p_code)
                              │ 3. success → Dashboard (Name, Klasse, Klassenstufe)
                              └ 4. Kachel-Klick "Projektwoche" → Deep-Link mit ?code= weiter
```

- **Derselbe Code, derselbe QR-Brief** funktioniert für Projektwahl UND Schüler-Hub.
- Persistenz in `localStorage` (`krs_sh_code`), Abmelden-Button löscht ihn.
- Der Code ist das Bearer-Token — wie bei der Projektwahl. Konsequenz: keine hochsensiblen Inhalte im Hub (siehe §7 DSGVO).

## 3. Module (Kacheln) — v1 und Ausbau

| Modul | v1 | Umsetzung |
|---|---|---|
| 🎨 Projektwoche | ✅ Link | Deep-Link `…/krs-projektwahl-2026/schueler-frontend-v3.html?code=<CODE>` — Schüler sieht dort sein Projekt/Wahl/Tausch |
| 📅 Klassen-Kalender | ✅ nativ | `hub_termine`, gefiltert nach Klasse/Stufe/global; Typen: Klassenarbeit, Termin, Event, Ferien |
| 👥 Meine Teams | ✅ nativ | `hub_teams` + Mitgliedschaften; Posts lesen + schreiben (Projektgruppen, AGs, Schulband …) |
| ✉️ Lehrkraft kontaktieren | ✅ nativ | `hub_nachrichten` an Lehrkräfte aus `hub_lehrer` (Opt-in-Liste); Antwort sichtbar im Hub |
| 🔗 Links & Downloads | ✅ nativ | `hub_links` (Homepage, Formulare, Pläne …), Kategorien |
| 🛠 Makerspace | ✅ Kachel (konfig.) | Link-Kachel; sobald Makerspace-App live ist: `?code=`-Durchreichung (App plant Code-RPC bereits) |
| 🏛 SMV | ✅ Kachel (konfig.) | Link-Kachel auf SMV-App (Ideenbox ist dort ohnehin anonym per QR geplant) |
| 📚 Perpustakaan (Bibliothek) | 🔜 Phase 2/3 | Schnittstelle offen — klären, was das System kann (Link? iframe? API?) |
| 📝 Klassenarbeitsplan-Import | 🔜 Phase 2 | Siehe §5 — Freigabe-Option im Lehrer-Klassenarbeitsplan nachrüsten, Sync nach `hub_termine` |
| 👨‍🏫 Lehrer-Panel | 🔜 Phase 2 | Teams anlegen/verwalten, Nachrichten beantworten — als Modul im **Lehrer**-Hub |

Kacheln sind reine Konfiguration (`CONFIG.MODULES` im Frontend) — neue App = ein Eintrag, Muster aus dem Lehrer-Hub übernommen. v1 öffnet Module als Links (mobil-freundlich), iframe-Shell wie im Lehrer-Hub ist als Phase-3-Option dokumentiert.

## 4. Datenmodell (neu, alles Präfix `hub_`, additive Migration)

| Tabelle | Zweck | Wichtige Spalten |
|---|---|---|
| `hub_lehrer` | Opt-in-Empfängerliste | kuerzel, anzeigename, aktiv |
| `hub_teams` | Teams/Gruppen | name, beschreibung, typ, erstellt_von (Lehrer-Kürzel), aktiv |
| `hub_team_mitglieder` | Zuordnung | team_id, schueler_code, UNIQUE(team_id, schueler_code) |
| `hub_team_posts` | Beiträge im Team | team_id, autor_typ (lehrer/schueler), autor_name, autor_code, inhalt |
| `hub_nachrichten` | Schüler→Lehrkraft | schueler_code, lehrer_kuerzel, betreff, inhalt, antwort, beantwortet_am |
| `hub_termine` | Klassen-Kalender | klasse ODER klassenstufe ODER global, datum, titel, typ, quelle |
| `hub_links` | Links & Downloads | titel, url, kategorie, sortierung, aktiv |

**Zugriffsmodell — kein einziges anon-SELECT:**
- RLS auf allen `hub_`-Tabellen aktiviert, **null Policies für anon** → default-DENY.
- Alle Lese-/Schreibzugriffe laufen über SECURITY-DEFINER-RPCs, die den Code validieren:

| RPC | Prüft | Liefert/Tut |
|---|---|---|
| `hub_get_dashboard(p_code)` | Code existiert + aktiv | Schüler-Info, Teams, nächste Termine (Klasse), Links, Zähler — 1 Roundtrip |
| `hub_get_team_posts(p_code, p_team_id)` | Mitgliedschaft | Posts des Teams |
| `hub_post_to_team(p_code, p_team_id, p_inhalt)` | Mitgliedschaft, Länge ≤ 2000, Rate-Limit 10/10 min | Post anlegen |
| `hub_get_lehrer_liste()` | — (nur aktive) | kuerzel + anzeigename |
| `hub_send_nachricht(p_code, p_kuerzel, p_betreff, p_inhalt)` | Code, Lehrer aktiv, Längen, Rate-Limit 5/Tag | Nachricht anlegen |
| `hub_get_meine_nachrichten(p_code)` | Code | eigene Nachrichten + Antworten |

- Ein Schüler sieht **nur eigene** Nachrichten und **nur Teams, in denen er Mitglied ist** — serverseitig erzwungen (Lektion aus dem Projektwahl-Phase-Gate).
- Inhalte werden als **Plaintext** gerendert (kein innerHTML) → kein XSS-Vektor.
- Rate-Limits in den RPCs bremsen Spam (Code-Weitergabe unter Schülern ist realistisch).

## 5. Schnittstelle Klassenarbeitsplan (Phase 2, wie von Norbert skizziert)

Der Lehrer-Klassenarbeitsplan (Preact-PWA, Google-Sheets/GAS-Backend) bekommt pro Eintrag eine Option **„für Klasse sichtbar"** (Standard: aus). Ein kleiner Sync (GAS-Trigger oder manueller Export) schreibt freigegebene Einträge als `hub_termine` (quelle='klassenarbeitsplan', typ='klassenarbeit') in die Schüler-DB — **Push von Lehrer-Welt → Schüler-Welt, nie umgekehrt**, und nur explizit freigegebene Einträge mit minimalen Feldern (Klasse, Fach/Titel, Datum). v1 enthält den Kalender bereits vollständig; Termine kommen bis dahin manuell/per Admin.

## 6. Frontend

- **Eine Datei** `index.html` (Preact + htm via esm.sh, kein Build-Tool) + `tenant.js` + `krs-supabase-config.js` — exakt das Projektwahl-Muster.
- **DataService Dual-Mode:** Demo (Mock: „Mia Muster, 7b") ↔ Produktiv (Supabase). `?forceMode=demo` als Test-Hook.
- KRS-Branding: Stahlblau `#4A6A83`, Orange `#E87722`, Gelb `#F5B335`; mobil-first (Schüler = Handy), Touch-Targets ≥ 44 px.
- Views: Login → Dashboard (Kacheln + „Demnächst"-Terminleiste) → Kalender / Teams / Nachrichten / Links.

## 7. DSGVO & Sicherheit (vor Go-Live zu erledigen)

1. **Neuer Verarbeitungszweck:** Teams-Posts + Schüler-Nachrichten sind neue Datenkategorien Minderjähriger → **DSB/Petra informieren**, Eltern-Info (Art. 13) um Schüler-Hub ergänzen. Der bestehende Projektwahl-Rahmen (EU-Frankfurt, AVV Supabase) trägt die technische Seite.
2. **Code = Bearer-Token:** bewusst akzeptiertes Modell (wie Projektwahl). Gegenmaßnahmen: Rate-Limits, keine sensiblen Inhalte, Lehrer-Moderation der Teams, Codes bei Verlust einzeln neu generierbar.
3. **Löschkonzept:** `hub_team_posts` und `hub_nachrichten` nach Schuljahresende löschen (SQL-Snippet liegt der Migration bei); Schülerabgang = Code inaktiv.
4. **Live-Gang-Protokoll:** kompletter Testlauf mit Test-Code VOR Verteilung an echte Schüler; Ankündigung wann es live geht (v42-Lektion).
5. Migration ist **idempotent + rein additiv** (`IF NOT EXISTS`), berührt keine Projektwahl-Tabelle — Projektwoche (21.–23.07.!) bleibt ungefährdet. Empfehlung: **Migration erst NACH den Projekttagen einspielen**, Demo-Modus reicht für Review/Abstimmung.

## 8. Phasenplan

| Phase | Inhalt | Status |
|---|---|---|
| **1 (jetzt)** | Plan, SQL-Migration, Schüler-Hub v1 (Demo voll lauffähig), Tests, Review | ✅ dieses Paket |
| **1b** | DSB/Petra-Freigabe, Migration einspielen, `hub_lehrer` + Links befüllen, Testlauf, Deploy als `krs-schueler-hub` (GitHub Pages, Org) | nach Projekttagen |
| **2** | Lehrer-Panel (Teams verwalten, Nachrichten beantworten) als Kachel im Lehrer-Hub; Klassenarbeitsplan-Freigabe-Sync | August/September |
| **3** | Makerspace-/SMV-Code-Durchreichung, Perpustakaan-Klärung, optional iframe-Shell + Unread-Badges | ab Herbst |

## Offene Punkte

- Perpustakaan: Welches System ist das konkret, gibt es eine URL/API?
- Sollen Teams automatisch aus Projektwahl-Zuteilungen erzeugt werden? (RPC-Snippet `hub_teams_aus_zuteilungen()` liegt der Migration bei — optional)
- Deploy-Ziel-Repo: Vorschlag `kurpfalz-realschule/krs-schueler-hub`
