# Voyager Backend 빠른 시작 가이드

## 🚀 5분만에 시작하기

### 1. 백엔드 서버 실행

```bash
cd apps/backend

# 의존성 설치
uv sync

# 개발 서버 실행
uv run dev
```

서버가 실행되면: http://localhost:8000

---

## 🤖 Ollama 설치 (LLM 검색용)

### macOS

```bash
# 방법 1: Homebrew
brew install ollama

# 방법 2: 공식 사이트
# https://ollama.com/download 에서 다운로드
```

### 모델 다운로드

```bash
# qwen2.5:7b 모델 다운로드 (약 4.7GB)
ollama pull qwen2.5:7b

# 모델 확인
ollama list
```

Ollama는 백그라운드에서 자동으로 실행됩니다.

---

## 📂 파일 크롤링 (인덱싱)

```bash
# Downloads 폴더 크롤링 (기본)
uv run index

# 특정 폴더 크롤링
uv run index --path ~/Documents

# 전체 홈 디렉토리 (시간 오래 걸림)
uv run index --path ~/

# 특정 폴더 제외
uv run index --path ~/ --exclude node_modules .git Library/Caches
```

**진행 상황 모니터링:**
```bash
# 다른 터미널에서
curl http://localhost:8000/api/files/db-size
```

---

## 🧪 API 테스트

### 1. 파일 통계 조회

```bash
curl http://localhost:8000/api/files/stats
```

**응답:**
```json
{
  "total_files": 1769,
  "total_size_mb": 87887.53,
  "extension_stats": [
    {"extension": "jpg", "count": 706},
    {"extension": "mp4", "count": 357}
  ]
}
```

### 2. DB 크기 조회

```bash
curl http://localhost:8000/api/files/db-size
```

**응답:**
```json
{
  "db_size_mb": 12.68,
  "total_files": 1769
}
```

### 3. 자연어 검색 (LLM)

```bash
curl -X POST http://localhost:8000/api/files/query \
  -H "Content-Type: application/json" \
  -d '{"query":"PDF 파일","limit":5}'
```

**응답:**
```json
{
  "query": "PDF 파일",
  "where_clause": "extension = 'pdf'",
  "count": 31,
  "items": [
    {
      "id": 24,
      "path": "/Users/.../file.pdf",
      "name": "file.pdf",
      "size": 65073055,
      "extension": "pdf",
      "modification_date": "2025-10-19 21:49:37"
    }
  ]
}
```

---

## 📚 API 문서

서버 실행 후 브라우저에서:
- **Swagger UI**: http://localhost:8000/docs
- **ReDoc**: http://localhost:8000/redoc

---

**작성일**: 2025-10-30
**버전**: 0.1.0
**이슈**: [VOY-65](https://linear.app/voyager-fm/issue/VOY-65)
