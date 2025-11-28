# Voyager Backend

LLM 기반 자연어 파일 검색 API

## 테스트 환경 설정

### 1. 서버 실행

```bash
cd apps/backend
uv sync
uv run dev
```

서버: http://localhost:8000

### 2. Ollama 설치

```bash
brew install ollama
ollama pull qwen2.5:7b
```

### 3. 파일 인덱싱

```bash
uv run index --path ~/Downloads
```

---

## API 엔드포인트

### `GET /api/files/stats`
파일 통계 조회

```bash
curl http://localhost:8000/api/files/stats
```

### `GET /api/files/db-size`
DB 크기 및 파일 개수 조회

```bash
curl http://localhost:8000/api/files/db-size
```

### `POST /api/files/query`
자연어 검색

```bash
curl -X POST http://localhost:8000/api/files/query \
  -H "Content-Type: application/json" \
  -d '{"query":"PDF 파일"}'
```

**쿼리 예시:**
- "PDF 파일"
- "최근 1주일 이내 수정된 이미지"
- "큰 동영상 파일"
- "Downloads 폴더의 파일"

---

**상세 가이드**: [QUICK_START.md](QUICK_START.md)
