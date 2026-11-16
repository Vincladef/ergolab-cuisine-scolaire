-- Atelier ergonomique. Toutes les tables sont isolées par salle.
CREATE TABLE IF NOT EXISTS room_workshops (
  room_id text PRIMARY KEY REFERENCES rooms(id) ON DELETE CASCADE,
  script jsonb NOT NULL DEFAULT '[]'::jsonb,
  design_criteria jsonb NOT NULL DEFAULT '[]'::jsonb,
  recommendations jsonb NOT NULL DEFAULT '[]'::jsonb,
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS room_runs (
  id uuid PRIMARY KEY,
  room_id text NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  scenario_index integer NOT NULL DEFAULT 0,
  title varchar(120) NOT NULL,
  started_by uuid NOT NULL,
  started_at timestamptz NOT NULL DEFAULT now(),
  ended_at timestamptz,
  status varchar(12) NOT NULL DEFAULT 'active' CHECK(status IN ('active','completed'))
);
CREATE INDEX IF NOT EXISTS room_runs_recent ON room_runs(room_id,started_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS one_active_run_per_room ON room_runs(room_id) WHERE status='active';
CREATE TABLE IF NOT EXISTS room_observations (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  room_id text NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  run_id uuid REFERENCES room_runs(id) ON DELETE SET NULL,
  actor_id uuid NOT NULL,
  scenario_index integer NOT NULL,
  category varchar(32) NOT NULL,
  severity smallint NOT NULL DEFAULT 2 CHECK(severity BETWEEN 1 AND 3),
  comment varchar(1200) NOT NULL,
  location jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS room_observations_recent ON room_observations(room_id,created_at DESC);
