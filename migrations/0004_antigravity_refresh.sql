CREATE TABLE antigravity_refresh (
  singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
  requested_at TEXT NOT NULL
);
