-- ============================================================
-- KRS Schüler-Hub — Migration v1 (2026-07-05)
-- Ziel-DB: krs-projektwahl (uzynvvtsyjfmtywsfxtz)
--
-- REIN ADDITIV + IDEMPOTENT: legt nur neue hub_*-Objekte an,
-- ändert KEINE Projektwahl-Tabelle. Mehrfach ausführbar.
-- Zugriff ausschließlich über SECURITY-DEFINER-RPCs —
-- RLS aktiviert, NULL Policies für anon (default-DENY).
--
-- Empfehlung: erst NACH den Projekttagen (23.07.) einspielen.
-- ============================================================

-- ============================================================
-- 1. TABELLEN
-- ============================================================

CREATE TABLE IF NOT EXISTS hub_lehrer (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  kuerzel TEXT UNIQUE NOT NULL,
  anzeigename TEXT NOT NULL,          -- z. B. "Herr Kotzan"
  aktiv BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS hub_teams (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  beschreibung TEXT DEFAULT '',
  typ TEXT NOT NULL DEFAULT 'sonstig'
    CHECK (typ IN ('projekt','ag','klasse','sonstig')),
  erstellt_von TEXT NOT NULL,         -- Lehrer-Kürzel (hub_lehrer.kuerzel)
  aktiv BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS hub_team_mitglieder (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id UUID NOT NULL REFERENCES hub_teams(id) ON DELETE CASCADE,
  schueler_code TEXT NOT NULL REFERENCES schueler(code) ON DELETE CASCADE,
  added_by TEXT NOT NULL DEFAULT 'admin',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (team_id, schueler_code)
);

CREATE TABLE IF NOT EXISTS hub_team_posts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id UUID NOT NULL REFERENCES hub_teams(id) ON DELETE CASCADE,
  autor_typ TEXT NOT NULL CHECK (autor_typ IN ('lehrer','schueler')),
  autor_name TEXT NOT NULL,           -- Anzeigename zum Zeitpunkt des Posts
  autor_code TEXT,                    -- nur bei autor_typ='schueler'
  inhalt TEXT NOT NULL CHECK (char_length(inhalt) BETWEEN 1 AND 2000),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_hub_team_posts_team
  ON hub_team_posts(team_id, created_at DESC);

CREATE TABLE IF NOT EXISTS hub_nachrichten (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  schueler_code TEXT NOT NULL REFERENCES schueler(code) ON DELETE CASCADE,
  lehrer_kuerzel TEXT NOT NULL,
  betreff TEXT NOT NULL CHECK (char_length(betreff) BETWEEN 1 AND 150),
  inhalt TEXT NOT NULL CHECK (char_length(inhalt) BETWEEN 1 AND 2000),
  antwort TEXT,                       -- von Lehrkraft (Phase 2: Lehrer-Panel)
  beantwortet_am TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_hub_nachrichten_schueler
  ON hub_nachrichten(schueler_code, created_at DESC);

CREATE TABLE IF NOT EXISTS hub_termine (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  titel TEXT NOT NULL,
  beschreibung TEXT DEFAULT '',
  datum DATE NOT NULL,
  typ TEXT NOT NULL DEFAULT 'termin'
    CHECK (typ IN ('klassenarbeit','termin','event','ferien')),
  klasse TEXT,                        -- z. B. '7b' → nur diese Klasse
  klassenstufe INT,                   -- z. B. 7 → ganze Stufe
  -- klasse+klassenstufe beide NULL → gilt für alle (global)
  quelle TEXT NOT NULL DEFAULT 'manuell',  -- 'manuell' | 'klassenarbeitsplan'
  sichtbar BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_hub_termine_datum ON hub_termine(datum);

CREATE TABLE IF NOT EXISTS hub_links (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  titel TEXT NOT NULL,
  url TEXT NOT NULL,
  beschreibung TEXT DEFAULT '',
  kategorie TEXT NOT NULL DEFAULT 'Allgemein',
  -- nur http(s) — verhindert javascript:-URLs (Review-Finding 🟡7)
  CONSTRAINT hub_links_url_https CHECK (url ~* '^https?://'),
  sortierung INT NOT NULL DEFAULT 100,
  aktiv BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================
-- 2. RLS — default-DENY (keine Policies für anon!)
-- ============================================================

ALTER TABLE hub_lehrer          ENABLE ROW LEVEL SECURITY;
ALTER TABLE hub_teams           ENABLE ROW LEVEL SECURITY;
ALTER TABLE hub_team_mitglieder ENABLE ROW LEVEL SECURITY;
ALTER TABLE hub_team_posts      ENABLE ROW LEVEL SECURITY;
ALTER TABLE hub_nachrichten     ENABLE ROW LEVEL SECURITY;
ALTER TABLE hub_termine         ENABLE ROW LEVEL SECURITY;
ALTER TABLE hub_links           ENABLE ROW LEVEL SECURITY;

-- Admin-Dashboard darf verwalten — aber NUR echte App-User (is_app_user()
-- aus migration-v35-rls-lockdown), NICHT jeder authenticated-JWT!
-- (Review-Finding 🔴3: "USING (true) TO authenticated" wäre offen, falls
--  Auth-Signups aktiv sind — Policies sind ODER-verknüpft.)
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='hub_lehrer' AND policyname='hub_lehrer_admin_all') THEN
    CREATE POLICY hub_lehrer_admin_all ON hub_lehrer FOR ALL TO authenticated USING (public.is_app_user()) WITH CHECK (public.is_app_user());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='hub_teams' AND policyname='hub_teams_admin_all') THEN
    CREATE POLICY hub_teams_admin_all ON hub_teams FOR ALL TO authenticated USING (public.is_app_user()) WITH CHECK (public.is_app_user());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='hub_team_mitglieder' AND policyname='hub_tm_admin_all') THEN
    CREATE POLICY hub_tm_admin_all ON hub_team_mitglieder FOR ALL TO authenticated USING (public.is_app_user()) WITH CHECK (public.is_app_user());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='hub_team_posts' AND policyname='hub_tp_admin_all') THEN
    CREATE POLICY hub_tp_admin_all ON hub_team_posts FOR ALL TO authenticated USING (public.is_app_user()) WITH CHECK (public.is_app_user());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='hub_nachrichten' AND policyname='hub_n_admin_all') THEN
    CREATE POLICY hub_n_admin_all ON hub_nachrichten FOR ALL TO authenticated USING (public.is_app_user()) WITH CHECK (public.is_app_user());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='hub_termine' AND policyname='hub_t_admin_all') THEN
    CREATE POLICY hub_t_admin_all ON hub_termine FOR ALL TO authenticated USING (public.is_app_user()) WITH CHECK (public.is_app_user());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='hub_links' AND policyname='hub_l_admin_all') THEN
    CREATE POLICY hub_l_admin_all ON hub_links FOR ALL TO authenticated USING (public.is_app_user()) WITH CHECK (public.is_app_user());
  END IF;
END $$;

-- ============================================================
-- 3. RPC-FUNKTIONEN (SECURITY DEFINER, Code-validiert)
-- ============================================================

-- Interner Helper: Code prüfen, Schüler-Record liefern (oder Exception)
CREATE OR REPLACE FUNCTION hub__check_code(p_code TEXT)
RETURNS schueler
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_s schueler;
BEGIN
  SELECT * INTO v_s FROM schueler
  WHERE code = UPPER(TRIM(p_code))
    AND COALESCE(aktiv, true) = true;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'code_unbekannt' USING ERRCODE = 'P0001';
  END IF;
  RETURN v_s;
END $$;
-- WICHTIG: auch PUBLIC entziehen — neue Funktionen haben default
-- EXECUTE für PUBLIC, ein REVOKE nur für anon reicht NICHT!
-- (Review-Finding 🔴2: sonst liefert der Helper die komplette
--  schueler-Zeile an jeden mit Publishable Key.)
REVOKE ALL ON FUNCTION hub__check_code(TEXT) FROM PUBLIC, anon, authenticated;

-- 3.1 Dashboard: alles in einem Roundtrip
CREATE OR REPLACE FUNCTION hub_get_dashboard(p_code TEXT)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_s schueler;
BEGIN
  BEGIN
    v_s := hub__check_code(p_code);
  EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('success', false, 'error', 'code_unbekannt');
  END;

  RETURN jsonb_build_object(
    'success', true,
    'schueler', jsonb_build_object(
      'code', v_s.code, 'vorname', v_s.vorname, 'nachname', v_s.nachname,
      'klasse', v_s.klasse, 'klassenstufe', v_s.klassenstufe
    ),
    'teams', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', t.id, 'name', t.name, 'beschreibung', t.beschreibung,
        'typ', t.typ, 'lehrer', t.erstellt_von,
        'letzter_post', (SELECT max(p.created_at) FROM hub_team_posts p WHERE p.team_id = t.id)
      ) ORDER BY t.name)
      FROM hub_teams t
      JOIN hub_team_mitglieder m ON m.team_id = t.id
      WHERE m.schueler_code = v_s.code AND t.aktiv
    ), '[]'::jsonb),
    'termine', COALESCE((
      -- LIMIT muss in der Subquery stehen (Review-Finding 🟡5) —
      -- auf dem Aggregat wäre es wirkungslos (jsonb_agg = 1 Zeile).
      SELECT jsonb_agg(jsonb_build_object(
        'id', e.id, 'titel', e.titel, 'beschreibung', e.beschreibung,
        'datum', e.datum, 'typ', e.typ, 'klasse', e.klasse
      ) ORDER BY e.datum)
      FROM (
        SELECT * FROM hub_termine t
        WHERE t.sichtbar
          AND t.datum >= CURRENT_DATE - 1
          AND (
            (t.klasse IS NULL AND t.klassenstufe IS NULL)
            OR LOWER(t.klasse) = LOWER(v_s.klasse)
            OR t.klassenstufe = v_s.klassenstufe
          )
        ORDER BY t.datum
        LIMIT 60
      ) e
    ), '[]'::jsonb),
    'links', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', l.id, 'titel', l.titel, 'url', l.url,
        'beschreibung', l.beschreibung, 'kategorie', l.kategorie
      ) ORDER BY l.kategorie, l.sortierung)
      FROM hub_links l WHERE l.aktiv
    ), '[]'::jsonb),
    'nachrichten_unbeantwortet', (
      SELECT count(*) FROM hub_nachrichten n
      WHERE n.schueler_code = v_s.code AND n.antwort IS NULL
    )
  );
END $$;

-- 3.2 Team-Posts lesen (nur Mitglieder aktiver Teams)
CREATE OR REPLACE FUNCTION hub_get_team_posts(p_code TEXT, p_team_id UUID)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_s schueler;
BEGIN
  BEGIN v_s := hub__check_code(p_code);
  EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('success', false, 'error', 'code_unbekannt');
  END;

  IF NOT EXISTS (SELECT 1 FROM hub_team_mitglieder m
                 JOIN hub_teams t ON t.id = m.team_id
                 WHERE m.team_id = p_team_id AND m.schueler_code = v_s.code AND t.aktiv) THEN
    RETURN jsonb_build_object('success', false, 'error', 'kein_mitglied');
  END IF;

  RETURN jsonb_build_object('success', true, 'posts', COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'id', p.id, 'autor_typ', p.autor_typ, 'autor_name', p.autor_name,
      'eigener', (p.autor_code = v_s.code),
      'inhalt', p.inhalt, 'created_at', p.created_at
    ) ORDER BY p.created_at ASC)
    FROM (SELECT * FROM hub_team_posts
          WHERE team_id = p_team_id
          ORDER BY created_at DESC LIMIT 200) p
  ), '[]'::jsonb));
END $$;

-- 3.3 In Team posten (Mitglied, Rate-Limit 10 Posts / 10 Minuten)
CREATE OR REPLACE FUNCTION hub_post_to_team(p_code TEXT, p_team_id UUID, p_inhalt TEXT)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_s schueler; v_inhalt TEXT;
BEGIN
  BEGIN v_s := hub__check_code(p_code);
  EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('success', false, 'error', 'code_unbekannt');
  END;

  v_inhalt := TRIM(COALESCE(p_inhalt, ''));
  IF char_length(v_inhalt) < 1 OR char_length(v_inhalt) > 2000 THEN
    RETURN jsonb_build_object('success', false, 'error', 'inhalt_laenge');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM hub_team_mitglieder m JOIN hub_teams t ON t.id = m.team_id
                 WHERE m.team_id = p_team_id AND m.schueler_code = v_s.code AND t.aktiv) THEN
    RETURN jsonb_build_object('success', false, 'error', 'kein_mitglied');
  END IF;

  IF (SELECT count(*) FROM hub_team_posts
      WHERE autor_code = v_s.code AND created_at > now() - interval '10 minutes') >= 10 THEN
    RETURN jsonb_build_object('success', false, 'error', 'rate_limit');
  END IF;

  INSERT INTO hub_team_posts (team_id, autor_typ, autor_name, autor_code, inhalt)
  VALUES (p_team_id, 'schueler', v_s.vorname || ' ' || LEFT(v_s.nachname, 1) || '.', v_s.code, v_inhalt);

  RETURN jsonb_build_object('success', true);
END $$;

-- 3.4 Lehrer-Liste (nur Opt-in, nur Kürzel + Anzeigename)
CREATE OR REPLACE FUNCTION hub_get_lehrer_liste()
RETURNS JSONB
LANGUAGE sql SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'kuerzel', kuerzel, 'anzeigename', anzeigename
  ) ORDER BY anzeigename), '[]'::jsonb)
  FROM hub_lehrer WHERE aktiv;
$$;

-- 3.5 Nachricht an Lehrkraft (Rate-Limit 5 / 24h)
CREATE OR REPLACE FUNCTION hub_send_nachricht(p_code TEXT, p_kuerzel TEXT, p_betreff TEXT, p_inhalt TEXT)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_s schueler; v_betreff TEXT; v_inhalt TEXT;
BEGIN
  BEGIN v_s := hub__check_code(p_code);
  EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('success', false, 'error', 'code_unbekannt');
  END;

  v_betreff := TRIM(COALESCE(p_betreff, ''));
  v_inhalt  := TRIM(COALESCE(p_inhalt, ''));
  IF char_length(v_betreff) < 1 OR char_length(v_betreff) > 150
     OR char_length(v_inhalt) < 1 OR char_length(v_inhalt) > 2000 THEN
    RETURN jsonb_build_object('success', false, 'error', 'inhalt_laenge');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM hub_lehrer WHERE kuerzel = p_kuerzel AND aktiv) THEN
    RETURN jsonb_build_object('success', false, 'error', 'lehrer_unbekannt');
  END IF;

  IF (SELECT count(*) FROM hub_nachrichten
      WHERE schueler_code = v_s.code AND created_at > now() - interval '24 hours') >= 5 THEN
    RETURN jsonb_build_object('success', false, 'error', 'rate_limit');
  END IF;

  INSERT INTO hub_nachrichten (schueler_code, lehrer_kuerzel, betreff, inhalt)
  VALUES (v_s.code, p_kuerzel, v_betreff, v_inhalt);

  RETURN jsonb_build_object('success', true);
END $$;

-- 3.6 Eigene Nachrichten + Antworten
CREATE OR REPLACE FUNCTION hub_get_meine_nachrichten(p_code TEXT)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_s schueler;
BEGIN
  BEGIN v_s := hub__check_code(p_code);
  EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('success', false, 'error', 'code_unbekannt');
  END;

  RETURN jsonb_build_object('success', true, 'nachrichten', COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'id', n.id,
      'lehrer', COALESCE((SELECT anzeigename FROM hub_lehrer hl WHERE hl.kuerzel = n.lehrer_kuerzel), n.lehrer_kuerzel),
      'betreff', n.betreff, 'inhalt', n.inhalt,
      'antwort', n.antwort, 'beantwortet_am', n.beantwortet_am,
      'created_at', n.created_at
    ) ORDER BY n.created_at DESC)
    FROM hub_nachrichten n WHERE n.schueler_code = v_s.code
  ), '[]'::jsonb));
END $$;

-- ============================================================
-- 4. GRANTS — anon darf NUR die RPCs aufrufen
-- ============================================================
GRANT EXECUTE ON FUNCTION hub_get_dashboard(TEXT)                    TO anon, authenticated;
GRANT EXECUTE ON FUNCTION hub_get_team_posts(TEXT, UUID)             TO anon, authenticated;
GRANT EXECUTE ON FUNCTION hub_post_to_team(TEXT, UUID, TEXT)         TO anon, authenticated;
GRANT EXECUTE ON FUNCTION hub_get_lehrer_liste()                     TO anon, authenticated;
GRANT EXECUTE ON FUNCTION hub_send_nachricht(TEXT, TEXT, TEXT, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION hub_get_meine_nachrichten(TEXT)            TO anon, authenticated;

-- ============================================================
-- 5. OPTIONAL: Teams aus Projektwahl-Zuteilungen erzeugen
--    (manuell vom Admin aufrufen, idempotent)
-- ============================================================
CREATE OR REPLACE FUNCTION hub_teams_aus_zuteilungen()
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_count INT := 0; r RECORD; v_team_id UUID;
BEGIN
  FOR r IN
    -- Lehrername nur anzeigen, wenn in hub_lehrer (Opt-in) —
    -- sonst generisch "Projektleitung" (Review-Finding 🟢10)
    SELECT p.id AS projekt_id, p.titel,
           COALESCE((SELECT hl.anzeigename FROM hub_lehrer hl
                     WHERE hl.aktiv AND hl.anzeigename = u.name LIMIT 1),
                    'Projektleitung') AS lehrer
    FROM projekte p LEFT JOIN users u ON p.lehrer_id = u.id
  LOOP
    SELECT id INTO v_team_id FROM hub_teams
    WHERE typ = 'projekt' AND name = 'Projekt: ' || r.titel;
    IF v_team_id IS NULL THEN
      INSERT INTO hub_teams (name, beschreibung, typ, erstellt_von)
      VALUES ('Projekt: ' || r.titel, 'Projektwoche 2026', 'projekt', r.lehrer)
      RETURNING id INTO v_team_id;
    END IF;
    INSERT INTO hub_team_mitglieder (team_id, schueler_code, added_by)
    SELECT v_team_id, z.schueler_code, 'zuteilung'
    FROM zuteilungen z WHERE z.projekt_id = r.projekt_id AND z.projekt_id IS NOT NULL
    ON CONFLICT (team_id, schueler_code) DO NOTHING;
    v_count := v_count + 1;
  END LOOP;
  RETURN jsonb_build_object('success', true, 'teams', v_count);
END $$;
-- Neue Funktionen haben default EXECUTE für PUBLIC — explizit entziehen,
-- sonst wäre die Funktion trotz "kein GRANT" von anon aufrufbar
-- (Review-Finding 🔴1). Nur service_role/SQL-Editor darf sie nutzen.
REVOKE ALL ON FUNCTION hub_teams_aus_zuteilungen() FROM PUBLIC, anon, authenticated;

-- ============================================================
-- 6. LÖSCHKONZEPT (Schuljahresende — manuell ausführen)
-- ============================================================
-- CHECK:  SELECT count(*) FROM hub_team_posts;  SELECT count(*) FROM hub_nachrichten;
-- ACTION: TRUNCATE hub_team_posts; TRUNCATE hub_nachrichten;
--         UPDATE hub_teams SET aktiv = false WHERE typ = 'projekt';
-- UNDO:   vorher Backup/Export ziehen (KRS-Backup.command).
