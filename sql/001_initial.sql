-- ErgoLab: isolated database. Apply in the dedicated Neon project.
CREATE TABLE IF NOT EXISTS rooms (
  id text PRIMARY KEY CHECK (length(id) BETWEEN 8 AND 20),
  scenarios jsonb NOT NULL DEFAULT '[{"name":"Scénario A","objects":[],"notes":""}]'::jsonb,
  active_index integer NOT NULL DEFAULT 0,
  revision bigint NOT NULL DEFAULT 1,
  paused boolean NOT NULL DEFAULT false,
  locked boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS room_participants (
  room_id text NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  id uuid NOT NULL,
  secret_hash text NOT NULL,
  nickname varchar(32) NOT NULL,
  color varchar(7) NOT NULL,
  role text NOT NULL DEFAULT 'participant' CHECK (role IN ('host','participant')),
  avatar jsonb NOT NULL DEFAULT '{"x":980,"y":440,"action":"libre","trail":[]}'::jsonb,
  joined_at timestamptz NOT NULL DEFAULT now(),
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (room_id, id)
);
CREATE INDEX IF NOT EXISTS room_participants_recent ON room_participants(room_id, last_seen_at DESC);
CREATE TABLE IF NOT EXISTS room_events (
  seq bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  room_id text NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  actor_id uuid,
  kind varchar(24) NOT NULL,
  payload jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS room_events_room_seq ON room_events(room_id,seq);
