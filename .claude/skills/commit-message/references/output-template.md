# Output Template

정상 케이스에서는 아래 템플릿 중 하나만 사용합니다.

## 1) Subject only

`type(scope): summary`

또는

`type: summary`

## 2) Subject + Body

헤더(subject)와 본문(body) 사이에 빈 줄을 둡니다.

```text
type(scope): summary

- 변경 의도
- 영향 범위
- 리스크/주의점
```

본문 불릿 규칙:

- 각 줄은 `- `로 시작
- 문장 종결형(`-합니다`) 대신 명사형/간결형의 개조식 형태를 우선
- 3-5개 항목 유지
