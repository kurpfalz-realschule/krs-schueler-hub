-- ============================================================
-- KRS Schüler-Hub — Migration v2 (2026-07-08)
-- Ziel-DB: krs-projektwahl (uzynvvtsyjfmtywsfxtz)
-- Thema: LEHRER-SEITE der Brücke Schüler-Hub ↔ Lehrer-Hub
--
-- SETZT migration-hub-v1.sql VORAUS (hub_lehrer, hub_nachrichten,
-- hub_teams, hub_termine, hub__check_code, is_app_user).
--
-- REIN ADDITIV + IDEMPOTENT. Ändert KEINE Projektwahl-Tabelle.
-- Neue Lehrer-RPCs: nur für authenticated App-User (is_app_user()),
-- NICHT für anon. Jeder lesende/schreibende Lehrer-Zugriff wird
-- in hub_zugriff_log protokolliert (Rechenschaftspflicht,
-- Voraussetzung für den "breiten Einblick", DSGVO/Minderjährige).
--
-- Einspielen: erst NACH den Projekttagen (23.07.).
-- ============================================================

-- ============================================================
-- 1. NEUE TABELLEN
-- ============================================================

-- 1.1 Ankündigungen (Klassenlehrer → Klasse/Stufe/global)
CREATE TABLE IF NOT EXISTS hub_ankuendigungen (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ziel_typ TEXT NOT NULL CHECK (ziel_typ IN ('global','klasse','stufe')),
  ziel_wert TEXT,                     -- 'klasse' → '7b'; 'stufe' → '7'; 'global' → NULL
  titel TEXT NOT NULL CHECK (char_length(titel) BETWEEN 1 AND 150),
  inhalt TEXT NOT NULL CHECK (char_length(inhalt) BETWEEN 1 AND 200000),
  von_kuerzel TEXT,                   -- Lehrer-Kürzel (falls verknüpft)
  von_name TEXT NOT NULL,             -- Anzeigename zum Zeitpunkt der Ankündigung
  gueltig_bis DATE,                   -- NULL = unbefristet
  aktiv BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_hub_ankuendigungen_ziel
  ON hub_ankuendigungen(ziel_typ, ziel_wert, created_at DESC);

-- 1.2 Zugriffs-/Audit-Log (Lehrer-Aktionen im Schüler-Hub)
CREATE TABLE IF NOT EXISTS hub_zugriff_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  actor TEXT NOT NULL,                -- Kürzel oder Login-E-Mail der Lehrkraft
  aktion TEXT NOT NULL,              -- postfach_ansehen | antwort | ankuendigung_neu | ...
  ziel TEXT,                          -- freies Ziel-Feld (Modus, ID, Klasse …)
  detail JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_hub_zugriff_log_zeit
  ON hub_zugriff_log(created_at DESC);

-- 1.3 Einstellungen (Key/Value) — u. a. der Sicht-Modus
CREATE TABLE IF NOT EXISTS hub_einstellungen (
  schluessel TEXT PRIMARY KEY,
  wert TEXT NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- Default: enger Modus. "breit" erst NACH DSB-Freigabe (siehe §7).
INSERT INTO hub_einstellungen (schluessel, wert)
VALUES ('lehrer_sicht', 'nur_eigene')
ON CONFLICT (schluessel) DO NOTHING;

-- 1.4 hub_lehrer um Identitäts-Verknüpfung erweitern (additiv)
ALTER TABLE hub_lehrer ADD COLUMN IF NOT EXISTS auth_id UUID;
ALTER TABLE hub_lehrer ADD COLUMN IF NOT EXISTS email   TEXT;
CREATE INDEX IF NOT EXISTS idx_hub_lehrer_auth  ON hub_lehrer(auth_id);
CREATE INDEX IF NOT EXISTS idx_hub_lehrer_email ON hub_lehrer(LOWER(email));

-- 1.5 Index für den engen Postfach-Filter (nach Kürzel)
CREATE INDEX IF NOT EXISTS idx_hub_nachrichten_lehrer
  ON hub_nachrichten(lehrer_kuerzel, created_at DESC);

-- ============================================================
-- 2. RLS — default-DENY; nur is_app_user() darf direkt verwalten
-- ============================================================
ALTER TABLE hub_ankuendigungen ENABLE ROW LEVEL SECURITY;
ALTER TABLE hub_zugriff_log    ENABLE ROW LEVEL SECURITY;
ALTER TABLE hub_einstellungen  ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='hub_ankuendigungen' AND policyname='hub_ank_admin_all') THEN
    CREATE POLICY hub_ank_admin_all ON hub_ankuendigungen FOR ALL TO authenticated USING (public.is_app_user()) WITH CHECK (public.is_app_user());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='hub_zugriff_log' AND policyname='hub_log_admin_read') THEN
    -- Log NUR lesbar für App-User; Schreiben ausschließlich über SECURITY-DEFINER-RPCs.
    CREATE POLICY hub_log_admin_read ON hub_zugriff_log FOR SELECT TO authenticated USING (public.is_app_user());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='hub_einstellungen' AND policyname='hub_set_admin_all') THEN
    CREATE POLICY hub_set_admin_all ON hub_einstellungen FOR ALL TO authenticated USING (public.is_app_user()) WITH CHECK (public.is_app_user());
  END IF;
END $$;

-- ============================================================
-- 3. INTERNE HELPER (SECURITY DEFINER, nicht direkt aufrufbar)
-- ============================================================

-- 3.1 Identität der aufrufenden Lehrkraft auflösen.
-- Gate: is_app_user() MUSS true sein (echter App-User), sonst Exception.
-- Mapping: hub_lehrer via auth_id = auth.uid() ODER email = JWT-E-Mail.
-- Liefert immer einen Actor (Kürzel > E-Mail > 'lehrkraft') fürs Log.
CREATE OR REPLACE FUNCTION hub__lehrer_ident()
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_mail TEXT; v_l hub_lehrer; v_actor TEXT; v_name TEXT;
BEGIN
  IF NOT public.is_app_user() THEN
    RAISE EXCEPTION 'nicht_berechtigt' USING ERRCODE = 'P0001';
  END IF;
  v_mail := NULLIF(auth.jwt() ->> 'email', '');
  SELECT * INTO v_l FROM hub_lehrer
   WHERE aktiv AND (auth_id = auth.uid() OR (email IS NOT NULL AND LOWER(email) = LOWER(v_mail)))
   LIMIT 1;
  IF FOUND THEN
    v_actor := v_l.kuerzel;
    v_name  := v_l.anzeigename;
  ELSE
    v_actor := COALESCE(v_mail, 'lehrkraft');
    v_name  := COALESCE(v_mail, 'Lehrkraft');
  END IF;
  RETURN jsonb_build_object(
    'kuerzel', v_l.kuerzel,           -- NULL, falls nicht verknüpft
    'anzeigename', v_name,
    'actor', v_actor
  );
END $$;
REVOKE ALL ON FUNCTION hub__lehrer_ident() FROM PUBLIC, anon, authenticated;

-- 3.2 Log-Helper
CREATE OR REPLACE FUNCTION hub__log(p_actor TEXT, p_aktion TEXT, p_ziel TEXT, p_detail JSONB)
RETURNS VOID
LANGUAGE sql SECURITY DEFINER SET search_path = public, pg_temp AS $$
  INSERT INTO hub_zugriff_log (actor, aktion, ziel, detail)
  VALUES (p_actor, p_aktion, p_ziel, COALESCE(p_detail, '{}'::jsonb));
$$;
REVOKE ALL ON FUNCTION hub__log(TEXT, TEXT, TEXT, JSONB) FROM PUBLIC, anon, authenticated;

-- Aktuellen Sicht-Modus lesen (Default nur_eigene)
CREATE OR REPLACE FUNCTION hub__sicht()
RETURNS TEXT
LANGUAGE sql SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT COALESCE((SELECT wert FROM hub_einstellungen WHERE schluessel='lehrer_sicht'), 'nur_eigene');
$$;
REVOKE ALL ON FUNCTION hub__sicht() FROM PUBLIC, anon, authenticated;

-- ============================================================
-- 4. LEHRER-RPCs (SECURITY DEFINER, nur authenticated App-User)
-- ============================================================

-- 4.1 Postfach: eingegangene Schüler-Nachrichten.
-- nur_eigene → nur an das eigene Kürzel adressierte; breit → alle.
CREATE OR REPLACE FUNCTION hub_lehrer_get_postfach()
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_id JSONB; v_sicht TEXT; v_kuerzel TEXT;
BEGIN
  v_id := hub__lehrer_ident();
  v_kuerzel := v_id->>'kuerzel';
  v_sicht := hub__sicht();
  PERFORM hub__log(v_id->>'actor', 'postfach_ansehen', v_sicht,
                   jsonb_build_object('kuerzel', v_kuerzel));

  RETURN jsonb_build_object(
    'success', true, 'sicht', v_sicht, 'ich', v_id,
    'nachrichten', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', n.id,
        'schueler', COALESCE((SELECT s.vorname || ' ' || s.nachname || ' (' || s.klasse || ')'
                              FROM schueler s WHERE s.code = n.schueler_code), n.schueler_code),
        'an_kuerzel', n.lehrer_kuerzel,
        'an_mich', (v_kuerzel IS NOT NULL AND n.lehrer_kuerzel = v_kuerzel),
        'betreff', n.betreff, 'inhalt', n.inhalt,
        'antwort', n.antwort, 'beantwortet_am', n.beantwortet_am,
        'created_at', n.created_at
      ) ORDER BY (n.antwort IS NOT NULL), n.created_at DESC)
      FROM hub_nachrichten n
      WHERE (v_sicht = 'breit') OR (v_kuerzel IS NOT NULL AND n.lehrer_kuerzel = v_kuerzel)
    ), '[]'::jsonb));
END $$;

-- 4.2 Nachricht beantworten
CREATE OR REPLACE FUNCTION hub_lehrer_antworten(p_id UUID, p_antwort TEXT)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_id JSONB; v_sicht TEXT; v_kuerzel TEXT; v_n hub_nachrichten; v_antwort TEXT;
BEGIN
  v_id := hub__lehrer_ident();
  v_kuerzel := v_id->>'kuerzel';
  v_sicht := hub__sicht();

  SELECT * INTO v_n FROM hub_nachrichten WHERE id = p_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'nicht_gefunden');
  END IF;

  -- enger Modus: nur an die eigene Person adressierte beantworten
  IF v_sicht <> 'breit' AND (v_kuerzel IS NULL OR v_n.lehrer_kuerzel <> v_kuerzel) THEN
    RETURN jsonb_build_object('success', false, 'error', 'nicht_berechtigt');
  END IF;

  v_antwort := TRIM(COALESCE(p_antwort, ''));
  IF char_length(v_antwort) < 1 OR char_length(v_antwort) > 200000 THEN
    RETURN jsonb_build_object('success', false, 'error', 'inhalt_laenge');
  END IF;

  UPDATE hub_nachrichten
     SET antwort = v_antwort, beantwortet_am = now()
   WHERE id = p_id;

  PERFORM hub__log(v_id->>'actor', 'antwort', p_id::text,
                   jsonb_build_object('an_kuerzel', v_n.lehrer_kuerzel, 'sicht', v_sicht));
  RETURN jsonb_build_object('success', true);
END $$;

-- 4.3 Ankündigung anlegen (alle Lehrkräfte dürfen an jede Klasse)
CREATE OR REPLACE FUNCTION hub_lehrer_ankuendigung(
  p_ziel_typ TEXT, p_ziel_wert TEXT, p_titel TEXT, p_inhalt TEXT, p_gueltig_bis DATE)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_id JSONB; v_titel TEXT; v_inhalt TEXT; v_wert TEXT; v_new UUID;
BEGIN
  v_id := hub__lehrer_ident();
  IF p_ziel_typ NOT IN ('global','klasse','stufe') THEN
    RETURN jsonb_build_object('success', false, 'error', 'ziel_ungueltig');
  END IF;
  v_wert := CASE WHEN p_ziel_typ = 'global' THEN NULL ELSE NULLIF(TRIM(COALESCE(p_ziel_wert,'')), '') END;
  IF p_ziel_typ <> 'global' AND v_wert IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'ziel_wert_fehlt');
  END IF;

  v_titel  := TRIM(COALESCE(p_titel, ''));
  v_inhalt := TRIM(COALESCE(p_inhalt, ''));
  IF char_length(v_titel) < 1 OR char_length(v_titel) > 150
     OR char_length(v_inhalt) < 1 OR char_length(v_inhalt) > 200000 THEN
    RETURN jsonb_build_object('success', false, 'error', 'inhalt_laenge');
  END IF;

  INSERT INTO hub_ankuendigungen (ziel_typ, ziel_wert, titel, inhalt, von_kuerzel, von_name, gueltig_bis)
  VALUES (p_ziel_typ, v_wert, v_titel, v_inhalt, v_id->>'kuerzel', v_id->>'anzeigename', p_gueltig_bis)
  RETURNING id INTO v_new;

  PERFORM hub__log(v_id->>'actor', 'ankuendigung_neu', p_ziel_typ,
                   jsonb_build_object('ziel_wert', v_wert, 'id', v_new));
  RETURN jsonb_build_object('success', true, 'id', v_new);
END $$;

-- 4.4 Eigene/alle Ankündigungen für die Verwaltung im Panel
CREATE OR REPLACE FUNCTION hub_lehrer_get_ankuendigungen()
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_id JSONB;
BEGIN
  v_id := hub__lehrer_ident();
  RETURN jsonb_build_object('success', true, 'ankuendigungen', COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'id', a.id, 'ziel_typ', a.ziel_typ, 'ziel_wert', a.ziel_wert,
      'titel', a.titel, 'inhalt', a.inhalt, 'von_name', a.von_name,
      'gueltig_bis', a.gueltig_bis, 'aktiv', a.aktiv, 'created_at', a.created_at
    ) ORDER BY a.created_at DESC)
    FROM hub_ankuendigungen a WHERE a.aktiv
  ), '[]'::jsonb));
END $$;

-- 4.5 Ankündigung zurückziehen (soft delete)
CREATE OR REPLACE FUNCTION hub_lehrer_ankuendigung_loeschen(p_id UUID)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_id JSONB;
BEGIN
  v_id := hub__lehrer_ident();
  UPDATE hub_ankuendigungen SET aktiv = false WHERE id = p_id;
  PERFORM hub__log(v_id->>'actor', 'ankuendigung_loeschen', p_id::text, '{}'::jsonb);
  RETURN jsonb_build_object('success', true);
END $$;

-- 4.6 Als Lehrkraft in ein Team posten
CREATE OR REPLACE FUNCTION hub_lehrer_team_post(p_team_id UUID, p_inhalt TEXT)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_id JSONB; v_inhalt TEXT;
BEGIN
  v_id := hub__lehrer_ident();
  v_inhalt := TRIM(COALESCE(p_inhalt, ''));
  IF char_length(v_inhalt) < 1 OR char_length(v_inhalt) > 200000 THEN
    RETURN jsonb_build_object('success', false, 'error', 'inhalt_laenge');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hub_teams WHERE id = p_team_id AND aktiv) THEN
    RETURN jsonb_build_object('success', false, 'error', 'team_unbekannt');
  END IF;
  INSERT INTO hub_team_posts (team_id, autor_typ, autor_name, autor_code, inhalt)
  VALUES (p_team_id, 'lehrer', v_id->>'anzeigename', NULL, v_inhalt);
  PERFORM hub__log(v_id->>'actor', 'team_post', p_team_id::text, '{}'::jsonb);
  RETURN jsonb_build_object('success', true);
END $$;

-- 4.7 Schüler-Vorschau: was ein Kind einer Klasse/Stufe sieht (read-only).
-- Gibt NUR gemeinsame Flächen zurück (Termine, Ankündigungen, Links,
-- Team-Namen) — KEINE privaten 1:1-Nachrichten einzelner Schüler.
CREATE OR REPLACE FUNCTION hub_lehrer_vorschau(p_ziel_typ TEXT, p_ziel_wert TEXT)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_id JSONB; v_klasse TEXT; v_stufe INT;
BEGIN
  v_id := hub__lehrer_ident();
  IF p_ziel_typ = 'klasse' THEN v_klasse := TRIM(COALESCE(p_ziel_wert,''));
  ELSIF p_ziel_typ = 'stufe' THEN v_stufe := NULLIF(TRIM(COALESCE(p_ziel_wert,'')),'')::INT;
  END IF;
  PERFORM hub__log(v_id->>'actor', 'vorschau', p_ziel_typ,
                   jsonb_build_object('ziel_wert', p_ziel_wert));

  RETURN jsonb_build_object(
    'success', true,
    'kontext', jsonb_build_object('ziel_typ', p_ziel_typ, 'klasse', v_klasse, 'stufe', v_stufe),
    'ankuendigungen', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', a.id, 'titel', a.titel, 'inhalt', a.inhalt,
        'von_name', a.von_name, 'created_at', a.created_at
      ) ORDER BY a.created_at DESC)
      FROM hub_ankuendigungen a
      WHERE a.aktiv AND (a.gueltig_bis IS NULL OR a.gueltig_bis >= CURRENT_DATE)
        AND (a.ziel_typ = 'global'
             OR (a.ziel_typ = 'klasse' AND v_klasse IS NOT NULL AND LOWER(a.ziel_wert) = LOWER(v_klasse))
             -- Text-Vergleich statt ::INT-Cast: sonst könnte Postgres '7b' einer
             -- Klassen-Zeile casten und mit Fehler abbrechen (Bedingungsreihenfolge
             -- ist nicht garantiert).
             OR (a.ziel_typ = 'stufe'  AND v_stufe  IS NOT NULL AND a.ziel_wert = v_stufe::TEXT))
    ), '[]'::jsonb),
    'termine', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', e.id, 'titel', e.titel, 'beschreibung', e.beschreibung,
        'datum', e.datum, 'typ', e.typ, 'klasse', e.klasse
      ) ORDER BY e.datum)
      FROM (
        SELECT * FROM hub_termine t
        WHERE t.sichtbar AND t.datum >= CURRENT_DATE - 1
          AND ((t.klasse IS NULL AND t.klassenstufe IS NULL)
               OR (v_klasse IS NOT NULL AND LOWER(t.klasse) = LOWER(v_klasse))
               OR (v_stufe  IS NOT NULL AND t.klassenstufe = v_stufe))
        ORDER BY t.datum LIMIT 60
      ) e
    ), '[]'::jsonb),
    'links', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('id', l.id, 'titel', l.titel, 'url', l.url,
        'beschreibung', l.beschreibung, 'kategorie', l.kategorie) ORDER BY l.kategorie, l.sortierung)
      FROM hub_links l WHERE l.aktiv
    ), '[]'::jsonb),
    'teams', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('id', t.id, 'name', t.name, 'typ', t.typ) ORDER BY t.name)
      FROM hub_teams t WHERE t.aktiv
    ), '[]'::jsonb)
  );
END $$;

-- 4.8 Audit-Log lesen (Rechenschaft)
CREATE OR REPLACE FUNCTION hub_lehrer_audit(p_limit INT DEFAULT 100)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_id JSONB;
BEGIN
  v_id := hub__lehrer_ident();
  RETURN jsonb_build_object('success', true, 'eintraege', COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'actor', z.actor, 'aktion', z.aktion, 'ziel', z.ziel,
      'detail', z.detail, 'created_at', z.created_at
    ) ORDER BY z.created_at DESC)
    FROM (SELECT * FROM hub_zugriff_log ORDER BY created_at DESC LIMIT GREATEST(1, LEAST(p_limit, 1000))) z
  ), '[]'::jsonb));
END $$;

-- ============================================================
-- 5. STUDENT-RPC: Ankündigungen (anon, code-validiert)
-- ============================================================
CREATE OR REPLACE FUNCTION hub_get_ankuendigungen(p_code TEXT)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_s schueler;
BEGIN
  BEGIN v_s := hub__check_code(p_code);
  EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('success', false, 'error', 'code_unbekannt');
  END;
  RETURN jsonb_build_object('success', true, 'ankuendigungen', COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'id', a.id, 'titel', a.titel, 'inhalt', a.inhalt,
      'von_name', a.von_name, 'created_at', a.created_at
    ) ORDER BY a.created_at DESC)
    FROM hub_ankuendigungen a
    WHERE a.aktiv AND (a.gueltig_bis IS NULL OR a.gueltig_bis >= CURRENT_DATE)
      AND (a.ziel_typ = 'global'
           OR (a.ziel_typ = 'klasse' AND LOWER(a.ziel_wert) = LOWER(v_s.klasse))
           -- Text-Vergleich statt ::INT-Cast (siehe hub_lehrer_vorschau)
           OR (a.ziel_typ = 'stufe'  AND a.ziel_wert = v_s.klassenstufe::TEXT))
  ), '[]'::jsonb));
END $$;

-- ============================================================
-- 6. GRANTS
-- ============================================================
-- Lehrer-RPCs: NUR authenticated (nicht anon!). is_app_user() gated intern.
GRANT EXECUTE ON FUNCTION hub_lehrer_get_postfach()                         TO authenticated;
GRANT EXECUTE ON FUNCTION hub_lehrer_antworten(UUID, TEXT)                  TO authenticated;
GRANT EXECUTE ON FUNCTION hub_lehrer_ankuendigung(TEXT, TEXT, TEXT, TEXT, DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION hub_lehrer_get_ankuendigungen()                   TO authenticated;
GRANT EXECUTE ON FUNCTION hub_lehrer_ankuendigung_loeschen(UUID)            TO authenticated;
GRANT EXECUTE ON FUNCTION hub_lehrer_team_post(UUID, TEXT)                  TO authenticated;
GRANT EXECUTE ON FUNCTION hub_lehrer_vorschau(TEXT, TEXT)                   TO authenticated;
GRANT EXECUTE ON FUNCTION hub_lehrer_audit(INT)                            TO authenticated;
-- Explizit anon entziehen (Defense-in-Depth; Default-PUBLIC-EXECUTE killen)
REVOKE ALL ON FUNCTION hub_lehrer_get_postfach()                         FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION hub_lehrer_antworten(UUID, TEXT)                  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION hub_lehrer_ankuendigung(TEXT, TEXT, TEXT, TEXT, DATE) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION hub_lehrer_get_ankuendigungen()                   FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION hub_lehrer_ankuendigung_loeschen(UUID)            FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION hub_lehrer_team_post(UUID, TEXT)                  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION hub_lehrer_vorschau(TEXT, TEXT)                   FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION hub_lehrer_audit(INT)                            FROM PUBLIC, anon;

-- Student-RPC: anon + authenticated (wie die übrigen hub_get_*)
GRANT EXECUTE ON FUNCTION hub_get_ankuendigungen(TEXT) TO anon, authenticated;

-- ============================================================
-- 7. SCHARFSCHALTEN & VERKNÜPFEN (manuell, NACH Freigabe)
-- ============================================================
-- 7a. Lehrkraft mit ihrem Login verknüpfen (eine Zeile je Lehrkraft) —
--     nötig für "nur eigene" Postfach + korrekte Autor-/Audit-Zuordnung:
--     UPDATE hub_lehrer SET email = 'kotzan@realschule-schriesheim.de' WHERE kuerzel = 'Ko';
--     -- ODER stattdessen per auth_id:
--     UPDATE hub_lehrer SET auth_id = '<AUTH-UUID>' WHERE kuerzel = 'Ko';
--
-- 7b. Breiten Einblick freischalten — ERST NACH DSB/Petra-Freigabe:
--     CHECK:  SELECT wert FROM hub_einstellungen WHERE schluessel = 'lehrer_sicht';
--     ACTION: UPDATE hub_einstellungen SET wert = 'breit', updated_at = now()
--             WHERE schluessel = 'lehrer_sicht';
--     UNDO:   UPDATE hub_einstellungen SET wert = 'nur_eigene', updated_at = now()
--             WHERE schluessel = 'lehrer_sicht';
--
-- ============================================================
-- 8. LÖSCHKONZEPT (Schuljahresende, manuell)
-- ============================================================
-- CHECK:  SELECT count(*) FROM hub_ankuendigungen; SELECT count(*) FROM hub_zugriff_log;
-- ACTION: UPDATE hub_ankuendigungen SET aktiv = false;
--         DELETE FROM hub_zugriff_log WHERE created_at < now() - interval '12 months';
-- UNDO:   vorher Backup/Export ziehen.
