# Plan: Lehrer-Schüler-Brücke (Schüler-Hub ↔ Lehrer-Hub)

**Stand:** 8. Juli 2026 · **Autor:** Claude (mit Norbert)
**Kontext:** Baut auf `ARCHITEKTUR-SCHUELER-HUB.md` + Migration `hub_v1` auf. Ergänzt die
fehlende **Lehrer-Seite** (Phase 2 / Sprint S5). DB-Einspielung erst **nach dem 23.07.**

---

## 0. Ziel (Anforderung Norbert, 08.07.2026)

- Schüler ↔ Lehrer sollen sich **gegenseitig** schreiben können.
- **Trennung** von *Lehrer-Chat* (Kollegium) und *Lehrer-Schüler-Chat*.
- Lehrkräfte sollen den **Schüler-Hub sehen**, dort **reinschreiben** (z. B. Klassenlehrer-
  Ankündigungen) und die **Schüleransicht** einsehen können.

---

## 1. Zwei-Kanal-Modell (die Trennung ist Pflicht, nicht Kür)

| Kanal | Wer ↔ Wer | DB | Status |
|---|---|---|---|
| **Lehrer-Chat** | Lehrer ↔ Lehrer (Kollegium, sensibel) | Lehrer-DB `ooejsfixxiuobrpqgfqm` (Connect) | ✅ läuft |
| **Lehrer-Schüler-Chat** | Lehrer ↔ Schüler | Schüler-DB `uzynvvtsyjfmtywsfxtz` | ⏳ Schüler-Seite fertig, Lehrer-Seite = dieser Plan |

Zwei getrennte DBs → Kollegiums-Interna können **physisch nicht** in einen Schüler-Kanal
rutschen. Die Brücke legt die DBs **nicht** zusammen und gibt Schülern **keinen** Zugriff
auf die Lehrer-DB. Nur die Gegenrichtung (Lehrer → Schüler-DB, authentifiziert) wird geöffnet.

---

## 2. Was im Datenmodell schon steht

- `hub_nachrichten` mit `antwort` + `beantwortet_am` → Antwortrichtung Lehrer→Schüler ist eingeplant.
- `hub_lehrer` (kuerzel, anzeigename, aktiv) = Opt-in-Kontaktliste, Schüler schreiben heute schon dorthin.
- `is_app_user()` (aus `migration-v35-rls-lockdown`) → nur echte Lehrer-Accounts dürfen verwalten.
- **Wichtig:** `is_app_user()` läuft in der Schüler-DB → betroffene Lehrkräfte haben dort
  einen authentifizierten Account. Genau darüber läuft die Brücke.

---

## 3. Die Brücke: Lehrer-Panel als Modul im Lehrer-Hub

Lehrkraft meldet sich im Lehrer-Hub an → Kachel „Schüler-Hub" → Modul spricht die
**Schüler-DB** über **neue Lehrer-RPCs** an (SECURITY DEFINER, gated by `is_app_user()`).
Spiegelbild zu den vorhandenen Schüler-RPCs.

| Neue Lehrer-RPC | Tut |
|---|---|
| `hub_lehrer_get_postfach()` | eingegangene Schüler-Nachrichten der Lehrkraft |
| `hub_lehrer_antworten(id, text)` | setzt `antwort` + `beantwortet_am` → Schüler sieht Antwort |
| `hub_lehrer_ankuendigung(ziel, text)` | Ankündigung an Klasse/Stufe/global |
| `hub_lehrer_vorschau(ziel)` | liefert die Schüleransicht (wie `hub_get_dashboard`), read-only |
| `hub_lehrer_audit_log(...)` | schreibt jeden Lese-/Antwortzugriff (siehe §4) |

Bidirektional: Schüler → `hub_send_nachricht` (existiert), Lehrer → `hub_lehrer_antworten` (neu).

---

## 4. Deine Entscheidungen (08.07.2026) — eingebaut

| Frage | Entscheidung | Umsetzung |
|---|---|---|
| Sichtbarkeit Lehrer in Schüler-Nachrichten | **Breiter Einblick** | ⚠️ nur mit 3 Schutzplanken (unten) + DSB-Freigabe; Default bis dahin „nur an mich adressierte" |
| Ankündigungen | **Beides** | eigener Ankündigungs-Kanal (`hub_ankuendigungen`, prominent oben im Dashboard) **und** Posten in bestehende Teams/Termine |
| Wer darf schreiben/ankündigen | **Alle Lehrkräfte** | jede aktive Lehrkraft (`is_app_user()`) darf jede Klasse anschreiben/ankündigen |

### ⚠️ Schutzplanken für „Breiter Einblick" (nicht verhandelbar, weil Minderjährige)
1. **Transparenz-Hinweis** im Schüler-Hub: „Lehrkräfte können Beiträge und Nachrichten einsehen."
2. **Audit-Log** (`hub_zugriff_log`): jeder Lehrer-Lese-/Antwortzugriff protokolliert (wer, wann, was).
3. **DSB-Gate:** breiter Einblick geht ausdrücklich in die Petra/DSB-Anfrage; Config-Schalter
   `LEHRER_SICHT = 'nur_eigene' | 'breit'`, Default `nur_eigene`, bis Freigabe vorliegt.

> Begründung: „jede Lehrkraft liest still alles" wäre ohne Transparenz + Rechenschaft
> eine Überwachung Minderjähriger. Mit den 3 Planken bleibt der breite Einblick
> (Fürsorge/Safeguarding) verteidigbar und schützt auch Norbert rechtlich.

---

## 5. Ankündigungen (beides)

- Neue Tabelle `hub_ankuendigungen` (ziel: klasse|stufe|global, titel, inhalt, von_kuerzel, gültig_bis).
- Anzeige: eigener Block „📢 Ankündigungen" oben im Schüler-Dashboard, farblich abgesetzt von Team-Posts.
- Zusätzlich weiterhin Posten in `hub_team_posts` / Termin in `hub_termine` möglich.

---

## 6. Bauplan (phasenweise, DB-Teil erst nach 23.07.)

| Schritt | Inhalt | Modell | Wann |
|---|---|---|---|
| B1 | Migration `hub_v2`: `hub_ankuendigungen`, `hub_zugriff_log`, Lehrer-RPCs, Config-Flag | Opus (RLS/Review) | SQL jetzt vorbereiten, einspielen n. 23.07. |
| B2 | Lehrer-Panel-Modul im Lehrer-Hub (Postfach, Antworten, Ankündigung, Schülervorschau) | Sonnet | nach B1 |
| B3 | Transparenz-Hinweis + Ankündigungs-Block im Schüler-Hub-Frontend | Sonnet | parallel |
| B4 | Kachel „Schüler-Hub" im Lehrer-Hub (`CONFIG.MODULES`) + ggf. „Lehrer-Bereich" im Schüler-Hub | Sonnet | parallel, ohne DB |
| B5 | Playwright-E2E (Postfach, Antwort sichtbar b. Schüler, Ankündigung, Audit-Eintrag, Flag-Default) | Sonnet | gleicher Commit wie Fix |
| B6 | DSB-Anfrage um „breiter Einblick + Audit" ergänzen; Go-Live-Testlauf mit Test-Code | — | vor Scharfschaltung |

---

## 7. Was nur Norbert kann

| Wann | Aktion |
|---|---|
| Vor B1 | bestätigen, dass die Brücke gebaut wird (dieser Plan) |
| Vor Scharfschaltung | „breiter Einblick" in DSB-Anfrage an Petra ergänzen + Freigabe |
| Nach 23.07. | Migration `hub_v2` im [SQL-Editor](https://supabase.com/dashboard/project/uzynvvtsyjfmtywsfxtz/sql/new) einspielen |
| Vor Go-Live | Lehrer-Accounts (die Schüler betreuen sollen) in der Schüler-DB anlegen/bestätigen |

---

## 8. Experten-Review — Kurz-Risiken

- 🔴 **Minderjährigen-Daten / breiter Einblick:** ohne Transparenz + Audit + DSB-Freigabe rechtswidrig. → §4 Schutzplanken, Default `nur_eigene`.
- 🟠 **Kanal-Vermischung:** Lehrkraft postet versehentlich Kollegiums-Inhalt im Schüler-Kanal. → zwei getrennte DBs + optisch klar getrennte UI, Vorschau read-only.
- 🟠 **Alle Lehrkräfte dürfen alle Klassen anschreiben:** operativ ok bei ~35 vertrauten Kolleg:innen, in Kombination mit breitem Einblick aber Grund, das Audit-Log ernst zu nehmen.
- 🟡 **Cross-Projekt-Auth:** Lehrer-JWT der Lehrer-DB gilt nicht automatisch in der Schüler-DB → Brücke nutzt Lehrer-Account **in der Schüler-DB** (`is_app_user()`), nicht das Connect-JWT.
- 🟡 **Rate-Limits/Spam** auch auf den neuen Lehrer-RPCs (analog Schüler-Seite).
