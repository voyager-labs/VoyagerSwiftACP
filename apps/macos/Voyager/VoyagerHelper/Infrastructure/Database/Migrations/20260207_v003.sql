-- 0) directories 테이블 생성
CREATE TABLE IF NOT EXISTS directories (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    volume_identifier TEXT,
    file_resource_identifier TEXT,
    path TEXT NOT NULL,
    parent_id INTEGER,
    name_full TEXT,
    name_stem TEXT,
    depth_from_home INTEGER,
    relative_path_from_home TEXT,
    is_invisible BOOLEAN,
    creation_date DATETIME,
    modification_date DATETIME,
    content_creation_date DATETIME,
    content_modification_date DATETIME,
    added_date DATETIME,
    last_used_date DATETIME,
    original_metadata TEXT,
    UNIQUE (volume_identifier, file_resource_identifier),
    UNIQUE (path),
    FOREIGN KEY (parent_id) REFERENCES directories(id)
);

-- 0.1) entries에 directory_id 컬럼 추가
ALTER TABLE entries ADD COLUMN directory_id INTEGER;

-- 1) entries 경로를 기준으로 directories 경로 집합(상위 경로 포함) 적재
WITH RECURSIVE
seed(path) AS (
    SELECT DISTINCT e.dir_path
    FROM entries e
    WHERE e.dir_path IS NOT NULL
    UNION
    SELECT DISTINCT e.path
    FROM entries e
    WHERE
        e.uniform_type_identifier = 'public.folder'
        OR (
            e.original_metadata IS NOT NULL
            AND json_valid(e.original_metadata) = 1
            AND json_extract(e.original_metadata, '$.kMDItemContentType') = 'public.folder'
        )
        OR (
            e.file_kind IS NOT NULL
            AND lower(e.file_kind) LIKE '%folder%'
        )
),
ancestors(path) AS (
    SELECT path FROM seed
    UNION ALL
    SELECT
        (
            WITH RECURSIVE
            seq(pos) AS (
                SELECT 1
                UNION ALL
                SELECT pos + 1 FROM seq WHERE pos < length(path)
            ),
            last_slash AS (
                SELECT max(pos) AS pos
                FROM seq
                WHERE substr(path, pos, 1) = '/'
            )
            SELECT CASE
                WHEN path = '/' THEN NULL
                WHEN (SELECT pos FROM last_slash) IS NULL THEN NULL
                WHEN (SELECT pos FROM last_slash) = 1 THEN '/'
                ELSE substr(path, 1, (SELECT pos FROM last_slash) - 1)
            END
        )
    FROM ancestors
    WHERE path IS NOT NULL AND path <> '/'
)
INSERT OR IGNORE INTO directories (
    volume_identifier,
    file_resource_identifier,
    path,
    name_full,
    name_stem,
    depth_from_home,
    relative_path_from_home,
    is_invisible,
    creation_date,
    modification_date,
    content_creation_date,
    content_modification_date,
    added_date,
    last_used_date,
    original_metadata
)
SELECT DISTINCT
    e.volume_identifier,
    e.file_resource_identifier,
    a.path,
    e.name_full,
    e.name_stem,
    e.depth_from_home,
    e.relative_path_from_home,
    e.is_invisible,
    e.creation_date,
    e.modification_date,
    e.content_creation_date,
    e.content_modification_date,
    e.added_date,
    e.last_used_date,
    e.original_metadata
FROM ancestors a
LEFT JOIN entries e ON e.path = a.path
WHERE a.path IS NOT NULL;

-- 2) directories.parent_id 채우기
UPDATE directories
SET parent_id = (
    SELECT parent_dir.id
    FROM directories parent_dir
    WHERE parent_dir.path = (
        WITH RECURSIVE
        seq(pos) AS (
            SELECT 1
            UNION ALL
            SELECT pos + 1 FROM seq WHERE pos < length(directories.path)
        ),
        last_slash AS (
            SELECT max(pos) AS pos
            FROM seq
            WHERE substr(directories.path, pos, 1) = '/'
        )
        SELECT CASE
            WHEN directories.path = '/' THEN NULL
            WHEN (SELECT pos FROM last_slash) IS NULL THEN NULL
            WHEN (SELECT pos FROM last_slash) = 1 THEN '/'
            ELSE substr(directories.path, 1, (SELECT pos FROM last_slash) - 1)
        END
    )
    LIMIT 1
)
WHERE parent_id IS NULL;

-- 3) entries.directory_id 백필
UPDATE entries
SET directory_id = (
    SELECT d.id
    FROM directories d
    WHERE d.path = entries.dir_path
    LIMIT 1
)
WHERE directory_id IS NULL;

-- 3.1) directories 조회 인덱스 생성
CREATE INDEX IF NOT EXISTS idx_directories_parent_id ON directories(parent_id);
CREATE INDEX IF NOT EXISTS idx_directories_relative_path ON directories(relative_path_from_home);

-- 4) 제거 대상 컬럼 제외한 entries_new 테이블 생성
CREATE TABLE IF NOT EXISTS entries_new (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    volume_identifier TEXT NOT NULL,
    file_resource_identifier TEXT NOT NULL,
    path TEXT NOT NULL,
    dir_path TEXT NOT NULL,
    name_full TEXT NOT NULL,
    name_stem TEXT NOT NULL,
    extension TEXT NOT NULL,
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
    directory_id INTEGER,
    UNIQUE (volume_identifier, file_resource_identifier)
);

-- 4.1) entries 데이터를 entries_new로 복사
INSERT INTO entries_new (
    id,
    volume_identifier,
    file_resource_identifier,
    path,
    dir_path,
    name_full,
    name_stem,
    extension,
    size,
    uniform_type_identifier,
    file_kind,
    is_invisible,
    creation_date,
    modification_date,
    content_creation_date,
    content_modification_date,
    added_date,
    last_used_date,
    original_metadata,
    directory_id
)
SELECT
    id,
    volume_identifier,
    file_resource_identifier,
    path,
    dir_path,
    name_full,
    name_stem,
    extension,
    size,
    uniform_type_identifier,
    file_kind,
    is_invisible,
    creation_date,
    modification_date,
    content_creation_date,
    content_modification_date,
    added_date,
    last_used_date,
    original_metadata,
    directory_id
FROM entries;

-- 4.2) 기존 entries 제거 후 entries_new를 files로 이름 변경
DROP TABLE entries;
ALTER TABLE entries_new RENAME TO files;

-- 4.3) files 조회 인덱스 생성
CREATE INDEX IF NOT EXISTS idx_files_directory_id ON files(directory_id);
CREATE INDEX IF NOT EXISTS idx_files_dir_path ON files(dir_path);
