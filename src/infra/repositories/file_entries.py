from __future__ import annotations

from typing import Any, Mapping, Optional, Sequence, cast

from sqlalchemy.dialects.sqlite import insert as sqlite_insert
from sqlalchemy.sql.schema import Table
from sqlmodel import Session, select
from sqlmodel.sql.expression import SelectOfScalar

from infra.db.engine import get_max_variables
from infra.schemas.file_entry_schema import FileEntrySchema


class FileEntriesRepository:
    def __init__(self, session: Session):
        self.session = session

    def get_by_id(self, id_: int) -> Optional[FileEntrySchema]:
        """기본 키(FileEntrySchema.id)로 단건 조회"""

        stmt = select(FileEntrySchema).where(FileEntrySchema.id == id_)

        return self.session.exec(stmt).first()

    def get_by_path(self, path: str) -> Optional[FileEntrySchema]:
        """고유 경로 컬럼(FileEntrySchema.path)로 단건 조회"""

        stmt = select(FileEntrySchema).where(FileEntrySchema.path == path)

        return self.session.exec(stmt).first()

    def delete_by_id(self, id_: int) -> int:
        """기본 키 컬럼(FileEntrySchema.id)로 단건 삭제"""

        row = self.get_by_id(id_)
        if row is None:
            return 0

        self.session.delete(row)
        self.session.flush()

        return 1

    def delete_by_path(self, path: str) -> int:
        """고유 경로 컬럼(FileEntrySchema.path)로 단건 삭제"""

        row = self.get_by_path(path)
        if row is None:
            return 0

        self.session.delete(row)
        self.session.flush()

        return 1

    def update_by_id(self, id_: int, fields: Mapping[str, Any]) -> Optional[FileEntrySchema]:
        """기본 키로 일부 필드를 갱신하고 갱신된 레코드를 반환합니다.

        동작
        - 대상이 없으면 None 반환(예외 없음).
        - 전달된 키 중 스키마(FileEntrySchema)에 존재하는 속성만 반영합니다. `id` 키는 무시됩니다.
        - 세션 커밋은 외부 컨텍스트에 위임하며, 본 메서드는 flush만 수행합니다.

        참고
        - 허용되는 키 셋은 런타임에 `FileEntrySchema.model_fields`에서 추출하여 사용합니다
        (스키마 정의 변경 시 자동 동기화)
        """

        row = self.get_by_id(id_)
        if row is None:
            return None

        allowed_keys = FileEntrySchema.model_fields.keys()
        for k, v in fields.items():
            if k == "id" or k not in allowed_keys:
                continue
            if getattr(row, k) != v:
                setattr(row, k, v)

        self.session.add(row)
        self.session.flush()
        return row

    def upsert_one(self, item: FileEntrySchema) -> FileEntrySchema:
        """단일 업서트 — INSERT .. ON CONFLICT(path) DO UPDATE RETURNING

        - path를 고유 키로 업서트하고, 최종 ORM 객체를 반환합니다.
        - flush는 내부에서 수행되며, 커밋은 외부에서 진행합니다.
        """
        table = cast(Table, getattr(FileEntrySchema, "__table__"))

        payload = item.model_dump(exclude={"id"})
        stmt = sqlite_insert(table).values(payload)
        excluded = cast(Any, stmt.excluded)
        update_cols = {c.name: getattr(excluded, c.name) for c in table.c if c.name != "id"}
        stmt = stmt.on_conflict_do_update(index_elements=[table.c.path], set_=update_cols)
        stmt = stmt.returning(*table.c)

        result = self.session.exec(cast(SelectOfScalar[FileEntrySchema], stmt))
        row = result.one()
        self.session.flush()
        return row

    def batch_upsert(self, items: Sequence[FileEntrySchema]) -> list[FileEntrySchema]:
        """배치 업서트(INSERT .. ON CONFLICT DO UPDATE)

        - 고유 키: path
        - 상위 레이어에서 배치 내 path 유니크를 보장한다고 가정합니다.
        - SQLite의 공식 UPSERT 문법으로 처리합니다.
        - SQLite 바인딩 변수 한도(예: 999)를 넘지 않도록 내부적으로 청크 분할합니다.
        - flush는 1회 수행하며, 커밋은 외부에서 진행합니다.
        - 반환: 입력 순서와 동일한 최종 ORM 객체 리스트

        - TODO: 배치 업서트 중 에러 발생 시 개선 방안 고려 필요
        """
        if not items:
            return []

        table = cast(Table, getattr(FileEntrySchema, "__table__"))

        insert_cols = [c for c in table.c if c.name != "id"]

        # SQLite 변수 한도는 엔진 초기화 시 캐시된 값을 사용
        max_vars = get_max_variables()

        num_cols = max(1, len(insert_cols))
        max_rows_per_stmt = max(1, (max_vars // num_cols))
        all_rows: list[FileEntrySchema] = []

        # 내부 청크 분할로 변수 한도 회피
        for start in range(0, len(items), max_rows_per_stmt):
            chunk = items[start : start + max_rows_per_stmt]
            payloads = [x.model_dump(exclude={"id"}) for x in chunk]

            stmt = sqlite_insert(table).values(payloads)
            excluded = cast(Any, stmt.excluded)
            update_cols = {c.name: getattr(excluded, c.name) for c in insert_cols}
            stmt = stmt.on_conflict_do_update(index_elements=[table.c.path], set_=update_cols)
            stmt = stmt.returning(*table.c)

            result = self.session.exec(cast(SelectOfScalar[FileEntrySchema], stmt))
            all_rows.extend(result.all())

        self.session.flush()

        by_path: dict[str, FileEntrySchema] = {r.path: r for r in all_rows}
        order = [x.path for x in items]
        return [by_path[p] for p in order]


__all__ = [
    "FileEntriesRepository",
]
