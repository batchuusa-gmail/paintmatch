-- PaintMatch Supabase Schema
-- PM-7: Design Supabase color database schema
-- Run in Supabase SQL Editor

-- ============================================================
-- paint_colors
-- ============================================================
CREATE TABLE IF NOT EXISTS paint_colors (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    vendor          text NOT NULL CHECK (vendor IN ('sherwin_williams','benjamin_moore','behr','ppg','valspar')),
    color_name      text NOT NULL,
    color_code      text NOT NULL,          -- e.g. SW7015
    hex             text NOT NULL,          -- e.g. #B2B0A4
    lrv             numeric(5,2),           -- Light Reflectance Value 0-100
    finish_options  text[],                 -- ['matte','eggshell','satin','semi_gloss','gloss']
    price_per_gallon numeric(6,2),
    coverage_sqft   integer,
    created_at      timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_paint_colors_hex    ON paint_colors (hex);
CREATE INDEX IF NOT EXISTS idx_paint_colors_vendor ON paint_colors (vendor);
CREATE INDEX IF NOT EXISTS idx_paint_colors_code   ON paint_colors (color_code);

ALTER TABLE paint_colors ENABLE ROW LEVEL SECURITY;

-- Public read (anonymous users can query colors)
CREATE POLICY "public_read_paint_colors"
    ON paint_colors FOR SELECT USING (true);


-- ============================================================
-- color_matches
-- ============================================================
CREATE TABLE IF NOT EXISTS color_matches (
    source_color_id  uuid REFERENCES paint_colors(id) ON DELETE CASCADE,
    matched_color_id uuid REFERENCES paint_colors(id) ON DELETE CASCADE,
    delta_e          numeric(8,4) NOT NULL,
    created_at       timestamptz DEFAULT now(),
    PRIMARY KEY (source_color_id, matched_color_id)
);

CREATE INDEX IF NOT EXISTS idx_color_matches_source  ON color_matches (source_color_id);
CREATE INDEX IF NOT EXISTS idx_color_matches_delta_e ON color_matches (delta_e);

ALTER TABLE color_matches ENABLE ROW LEVEL SECURITY;

CREATE POLICY "public_read_color_matches"
    ON color_matches FOR SELECT USING (true);


-- ============================================================
-- user_projects
-- ============================================================
CREATE TABLE IF NOT EXISTS user_projects (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             uuid REFERENCES auth.users(id) ON DELETE CASCADE,
    project_name        text NOT NULL DEFAULT 'My Room',
    room_image_url      text,
    rendered_image_url  text,
    selected_hex        text,
    vendor_picks        jsonb,              -- [{vendor, color_name, color_code, hex, price, delta_e}]
    created_at          timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_user_projects_user_id ON user_projects (user_id);

ALTER TABLE user_projects ENABLE ROW LEVEL SECURITY;

-- Users can only access their own projects
CREATE POLICY "user_own_projects_select"
    ON user_projects FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "user_own_projects_insert"
    ON user_projects FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "user_own_projects_update"
    ON user_projects FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "user_own_projects_delete"
    ON user_projects FOR DELETE USING (auth.uid() = user_id);


-- ============================================================
-- Supabase Storage bucket
-- ============================================================
-- Run in Supabase dashboard: Storage → New bucket → "paintmatch-renders" (public)
-- INSERT INTO storage.buckets (id, name, public) VALUES ('paintmatch-renders', 'paintmatch-renders', true);
