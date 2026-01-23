DROP TABLE IF EXISTS migration_version;

CREATE TABLE IF NOT EXISTS entries (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    volume_identifier TEXT NOT NULL,
    file_resource_identifier TEXT NOT NULL,
    path TEXT NOT NULL,
    dir_path TEXT NOT NULL,
    name_full TEXT NOT NULL,
    name_stem TEXT NOT NULL,
    extension TEXT NOT NULL,
    parent_dir_name TEXT NOT NULL,
    depth_from_home INTEGER NOT NULL,
    relative_path_from_home TEXT,
    size INTEGER NOT NULL,
    uniform_type_identifier TEXT,
    file_kind TEXT,
    is_invisible BOOLEAN NOT NULL DEFAULT 0,
    creation_date DATETIME NOT NULL,
    modification_date DATETIME NOT NULL,
    content_creation_date DATETIME NOT NULL,
    content_modification_date DATETIME NOT NULL,
    added_date DATETIME NOT NULL,
    last_used_date DATETIME,
    original_metadata TEXT NOT NULL,
    UNIQUE (volume_identifier, file_resource_identifier)
);

CREATE TABLE IF NOT EXISTS indexing_state (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    key TEXT NOT NULL,
    value TEXT NOT NULL,
    updated_at DATETIME NOT NULL,
    UNIQUE (key)
);

INSERT INTO indexing_state (key, value, updated_at)
SELECT 'watched_paths', '[]', CURRENT_TIMESTAMP
WHERE NOT EXISTS (
    SELECT 1 FROM indexing_state WHERE key = 'watched_paths'
);

INSERT INTO indexing_state (key, value, updated_at)
SELECT 'last_sync_at', 'null', CURRENT_TIMESTAMP
WHERE NOT EXISTS (
    SELECT 1 FROM indexing_state WHERE key = 'last_sync_at'
);
