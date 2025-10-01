# Voyager File Manager App Backend

### 필수 요구사항

- uv 패키지 매니저
- Python 3.13 이상

### 설치 및 실행 방법

1. **프로젝트 클론**

   ```bash
   git clone https://github.com/voyager-labs/voyager-app-backend.git
   cd voyager-app-backend
   ```

2. **의존성 설치**

   ```bash
   uv sync && uv run pre-commit install
   ```

3. **개발 서버 실행**

   ```bash
   uv run dev
   ```

4. **프로덕션 서버 실행**

   ```bash
   uv run prod
   ```

### DB 마이그레이션 (Alembic)

SQLite 데이터베이스 스키마 변경 관리를 위해 Alembic을 사용함
SQLModel Schema 정의가 변경되면, 아래 절차로 마이그레이션 파일을 생성하고 DB 스키마를 최신 상태로 유지할 수 있음.

1. **마이그레이션 파일 생성** (모델 변경 감지 후 자동 코드 생성)
   ```bash
   uv run alembic revision --autogenerate -m "변경 내용 설명"
   ```

2. **마이그레이션 적용** (DB를 최신 상태로 업데이트)
   ```bash
   uv run alembic upgrade head
   ```
