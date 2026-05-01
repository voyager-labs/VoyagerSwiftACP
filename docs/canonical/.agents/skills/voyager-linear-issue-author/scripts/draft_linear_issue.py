#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import re
import sys
from pathlib import Path
from textwrap import shorten


class Args(argparse.Namespace):
    feature_ids: list[str] = []
    output_dir: Path | None = None
    scope_limit: int = 6
    ac_limit: int = 3
    overwrite: bool = False


def find_repo_root(start: Path) -> Path:
    for candidate in [start, *start.parents]:
        if (candidate / "PRODUCT/04_FEATURE_INVENTORY").exists() and (
            candidate / "PRODUCT/LINEAR_ISSUE_DRAFTS"
        ).exists():
            return candidate
    raise RuntimeError("Could not locate repo root from script path")


def read_tsv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f, delimiter="\t")
        return [dict(row) for row in reader]


def clean(value: str | None) -> str:
    if value is None:
        return ""
    return re.sub(r"\s+", " ", value).strip()


def short(value: str | None, width: int = 120) -> str:
    v = clean(value)
    if not v:
        return "-"
    return shorten(v, width=width, placeholder="...")


def load_template(repo_root: Path) -> str:
    candidates = [
        repo_root
        / ".agents"
        / "skills"
        / "voyager-linear-issue-author"
        / "templates"
        / "TEMPLATE-feature-implementation.md",
        repo_root / "PRODUCT/LINEAR_ISSUE_DRAFTS" / "TEMPLATE-feature-implementation.md",
    ]
    for path in candidates:
        if path.exists():
            return path.read_text(encoding="utf-8")

    raise FileNotFoundError(
        "Template not found. Expected .agents/skills/voyager-linear-issue-author/templates/TEMPLATE-feature-implementation.md"
    )


def find_use_case_hits(
    repo_root: Path, feature_id: str, interaction_ids: list[str]
) -> list[str]:
    hits: list[str] = []
    use_case_dir = repo_root / "PRODUCT/06_USE_CASES"

    patterns = [feature_id, *interaction_ids]
    for md_path in sorted(use_case_dir.glob("*.md")):
        if md_path.name == "index.md":
            continue
        try:
            body = md_path.read_text(encoding="utf-8")
        except OSError:
            continue

        if any(token and token in body for token in patterns):
            hits.append(md_path.name)

    return hits


def render_issue_markdown(
    feature: dict[str, str],
    interactions: list[dict[str, str]],
    use_case_hits: list[str],
    scope_limit: int,
    ac_limit: int,
    template: str,
) -> str:
    feature_id = clean(feature.get("feature_id"))
    feature_title = clean(feature.get("feature_title")) or feature_id
    release_phase = clean(feature.get("release_phase")) or "-"
    status = clean(feature.get("status")) or "-"
    description = short(feature.get("description"), width=180)

    title = f"{feature_title} 구현"

    interaction_ids = [
        clean(row.get("interaction_id"))
        for row in interactions
        if clean(row.get("interaction_id"))
    ]
    interaction_link_value = (
        ", ".join(f"`{iid}`" for iid in interaction_ids[:6]) if interaction_ids else "-"
    )
    use_case_link_value = (
        ", ".join(f"`{name}`" for name in use_case_hits[:6]) if use_case_hits else "-"
    )

    scope_rows = interactions[:scope_limit]
    in_scope_items = [
        f"{clean(row.get('interaction_title')) or '세부 인터랙션 구현'} ({'`' + clean(row.get('interaction_id')) + '`' if clean(row.get('interaction_id')) else '`interaction_id TBD`'})"
        for row in scope_rows
    ]
    if not in_scope_items:
        in_scope_items = [f"{feature_title}의 핵심 플로우 구현 (`{feature_id}`)"]
    in_scope_text = "\n".join(f"- [ ] {item}" for item in in_scope_items)

    requirements: list[str] = []
    for row in interactions:
        summary = clean(row.get("summary"))
        if not summary or summary == "-":
            continue
        iid = clean(row.get("interaction_id"))
        requirements.append(
            f"- [ ] {short(summary, width=120)} ({'`' + iid + '`' if iid else '`interaction_id TBD`'})"
        )
        if len(requirements) >= 2:
            break

    if not requirements:
        requirements.append(
            f"- [ ] `{feature_id}` 기능 요구사항을 구현 가능한 단위로 구체화"
        )

    requirements.extend(
        [
            "- [ ] 권한/가드 조건",
            "- [ ] 에러/예외 처리 기준",
        ]
    )

    ac_rows = interactions[:ac_limit]
    ac_lines: list[str] = []
    for i, row in enumerate(ac_rows, start=1):
        interaction_title = clean(row.get("interaction_title")) or "핵심 인터랙션"
        summary = short(row.get("summary"), width=140)
        given = "해당 기능을 사용할 수 있는 상태에서"
        ac_lines.append(
            f"{i}. **Given** {given}, **When** 사용자가 `{interaction_title}` 인터랙션을 수행하면, **Then** {summary}"
        )

    while len(ac_lines) < 3:
        index = len(ac_lines) + 1
        ac_lines.append(
            f"{index}. **Given** 사전조건이 충족된 상태, **When** 사용자가 기능을 실행하면, **Then** 기대한 결과가 일관되게 반영된다"
        )

    rendered = template
    rendered = rendered.replace("{한 줄 요약}", title)
    rendered = rendered.replace(
        "- 현재 상태:",
        f"- 현재 상태: `{feature_id}` / release_phase `{release_phase}` / status `{status}`",
    )
    rendered = rendered.replace("- 문제:", f"- 문제: {description}")
    rendered = rendered.replace(
        "- 기대 효과:",
        "- 기대 효과: 구현 범위와 수용 기준을 명확히 정리해 개발/리뷰/QA 커뮤니케이션 비용을 줄인다.",
    )
    rendered = rendered.replace("{section}", "관련 UI 구조 확인")
    rendered = rendered.replace("{feature_id / interaction_id}", f"`{feature_id}`")
    rendered = rendered.replace("{use_case_id}", use_case_link_value)
    rendered = rendered.replace(
        "{link}",
        f"`PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv` - {interaction_link_value}",
    )

    rendered = rendered.replace(
        "- [ ] {구현 항목 1}\n- [ ] {구현 항목 2}",
        in_scope_text,
    )
    rendered = rendered.replace(
        "{이번 이슈에서 제외할 항목}",
        "인접 feature_id의 동작 변경 및 대규모 리팩토링, 데이터 마이그레이션 정책 변경",
    )
    rendered = rendered.replace(
        "기능 요구사항 A", requirements[0].replace("- [ ] ", "")
    )
    rendered = rendered.replace(
        "기능 요구사항 B", requirements[1].replace("- [ ] ", "")
    )
    rendered = rendered.replace(
        "- 정상:",
        "- 정상: 사용자가 의도한 인터랙션을 실행하면 UI/동작 결과가 즉시 반영된다.",
    )
    rendered = rendered.replace(
        "- 로딩:",
        "- 로딩: 비동기 처리 구간에서 진행 상태를 사용자에게 명확히 보여준다.",
    )
    rendered = rendered.replace(
        "- 빈 상태:",
        "- 빈 상태: 표시할 대상이 없는 경우 안내 문구/행동 유도를 제공한다.",
    )
    rendered = rendered.replace(
        "- 오류:",
        "- 오류: 실패 원인을 사용자가 이해할 수 있는 메시지로 노출하고 재시도 경로를 제공한다.",
    )
    rendered = rendered.replace(
        "- 엣지 케이스:",
        "- 엣지 케이스: 중복 호출, 권한 부족, 대상 소실/비가용 상태를 안전하게 처리한다.",
    )
    rendered = rendered.replace("- API:", "- API: TBD")
    rendered = rendered.replace("- DB/Storage:", "- DB/Storage: -")
    rendered = rendered.replace("- 이벤트/로깅:", "- 이벤트/로깅: TBD")

    rendered = rendered.replace(
        "1. **Given** {사전조건}, **When** {행동}, **Then** {결과}",
        ac_lines[0],
    )
    rendered = rendered.replace(
        "2. **Given** {사전조건}, **When** {행동}, **Then** {결과}",
        ac_lines[1],
    )
    rendered = rendered.replace(
        "3. **Given** {예외조건}, **When** {행동}, **Then** {처리결과}",
        ac_lines[2],
    )

    return rendered.strip() + "\n"


def parse_args() -> Args:
    parser = argparse.ArgumentParser(
        description="Draft Linear feature implementation issue markdown from Voyager feature inventory"
    )
    _ = parser.add_argument(
        "feature_ids", nargs="+", help="Target feature_id values (e.g., EVM-002)"
    )
    _ = parser.add_argument(
        "--output-dir",
        type=Path,
        help="Write one markdown file per feature_id to this directory",
    )
    _ = parser.add_argument(
        "--scope-limit",
        type=int,
        default=6,
        help="Maximum interaction rows to include in In Scope section",
    )
    _ = parser.add_argument(
        "--ac-limit",
        type=int,
        default=3,
        help="Maximum interaction rows to seed GWT acceptance criteria",
    )
    _ = parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Allow overwriting existing files when --output-dir is used",
    )
    return parser.parse_args(namespace=Args())


def main() -> int:
    args = parse_args()
    script_path = Path(__file__).resolve()
    repo_root = find_repo_root(script_path.parent)

    features_path = repo_root / "PRODUCT/04_FEATURE_INVENTORY" / "FEATURES" / "data.tsv"
    interactions_path = repo_root / "PRODUCT/04_FEATURE_INVENTORY" / "INTERACTIONS" / "data.tsv"

    features = read_tsv(features_path)
    interactions = read_tsv(interactions_path)
    template = load_template(repo_root)

    feature_by_id = {
        clean(row.get("feature_id")): row
        for row in features
        if clean(row.get("feature_id"))
    }

    missing = [fid for fid in args.feature_ids if fid not in feature_by_id]
    if missing:
        print(f"Error: feature_id not found: {', '.join(missing)}", file=sys.stderr)
        return 1

    if len(args.feature_ids) > 1 and args.output_dir is None:
        print(
            "Error: pass --output-dir when generating multiple feature drafts",
            file=sys.stderr,
        )
        return 1

    for fid in args.feature_ids:
        feature = feature_by_id[fid]
        related_interactions = [
            row for row in interactions if clean(row.get("feature_id")) == fid
        ]
        related_interactions.sort(key=lambda row: clean(row.get("interaction_id")))

        interaction_ids = [
            clean(row.get("interaction_id"))
            for row in related_interactions
            if clean(row.get("interaction_id"))
        ]
        use_case_hits = find_use_case_hits(repo_root, fid, interaction_ids)

        markdown = render_issue_markdown(
            feature=feature,
            interactions=related_interactions,
            use_case_hits=use_case_hits,
            scope_limit=max(1, args.scope_limit),
            ac_limit=max(1, args.ac_limit),
            template=template,
        )

        if args.output_dir is None:
            print(markdown)
            continue

        args.output_dir.mkdir(parents=True, exist_ok=True)
        output_path = args.output_dir / f"{fid}.md"
        if output_path.exists() and not args.overwrite:
            print(
                f"Error: output file exists: {output_path}. Use --overwrite to replace.",
                file=sys.stderr,
            )
            return 1

        _ = output_path.write_text(markdown, encoding="utf-8")
        print(f"Wrote {output_path}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
