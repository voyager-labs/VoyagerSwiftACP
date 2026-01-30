WITH to_update AS (
  SELECT
    e.id,
    CASE
      -- 0) JSON 리터럴 null(루트 null) => {}
      WHEN json_valid(e.original_metadata) = 1
       AND json_type(e.original_metadata) = 'null'
      THEN '{}'

      -- 1) 최상위 object에서 null 값인 키 제거
      WHEN json_valid(e.original_metadata) = 1
       AND json_type(e.original_metadata) = 'object'
       AND EXISTS (
         SELECT 1
         FROM json_each(e.original_metadata) je
         WHERE je.type = 'null'
         LIMIT 1
       )
      THEN COALESCE(
        (
          SELECT json_group_object(je.key, je.value)
          FROM json_each(e.original_metadata) je
          WHERE je.type <> 'null'
        ),
        '{}' -- 전부 null이라 비면 NULL 나오니 방어
      )

      ELSE e.original_metadata
    END AS new_json
  FROM entries e
  WHERE e.original_metadata IS NOT NULL
    AND json_valid(e.original_metadata) = 1
    AND (
      json_type(e.original_metadata) = 'null'
      OR (
        json_type(e.original_metadata) = 'object'
        AND EXISTS (
          SELECT 1
          FROM json_each(e.original_metadata) je
          WHERE je.type = 'null'
          LIMIT 1
        )
      )
    )
)
UPDATE entries
SET original_metadata = (
  SELECT t.new_json
  FROM to_update t
  WHERE t.id = entries.id
)
WHERE id IN (SELECT id FROM to_update);
