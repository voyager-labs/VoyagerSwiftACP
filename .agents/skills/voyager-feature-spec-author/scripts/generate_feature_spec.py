#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import re
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Tuple


REPO_MARKERS = [
    Path("PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv"),
    Path("PRODUCT/04_FEATURE_INVENTORY/FEATURES/data.tsv"),
    Path("PRODUCT/05_FEATURE_SPECS"),
]


class Args(argparse.Namespace):
    interaction_ids: List[str]
    output_dir: Optional[Path] = None
    overwrite: bool = False
    dry_run: bool = False
    template: Optional[Path] = None


def find_repo_root(start: Path) -> Path:
    for candidate in [start, *start.parents]:
        if all((candidate / marker).exists() for marker in REPO_MARKERS):
            return candidate
    raise RuntimeError("Could not locate voyager-documentation repo root")


def read_tsv_rows(path: Path) -> List[Tuple[int, Dict[str, str]]]:
    with path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        rows: List[Tuple[int, Dict[str, str]]] = []
        for line_no, row in enumerate(reader, start=2):
            rows.append((line_no, {key: (value if value is not None else "") for key, value in row.items()}))
        return rows


def slugify(value: str, fallback: str) -> str:
    val = (value or "").strip().lower()
    if not val:
        return fallback
    val = re.sub(r"[^0-9a-zA-Z]+", "-", val)
    val = re.sub(r"-{2,}", "-", val)
    val = val.strip("-_")
    return val or fallback


def normalize(value: Optional[str], default: str = "-") -> str:
    if value is None:
        return default
    stripped = value.strip()
    return stripped if stripped else default


def concrete_or_fallback(value: Optional[str], fallback: str) -> str:
    raw = normalize(value, "")
    if raw and raw not in {"-", "TBD"}:
        return raw
    return fallback


def yaml_quote(value: str) -> str:
    escaped = value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
    return f'"{escaped}"'


def load_template(repo_root: Path, template_arg: Optional[Path]) -> str:
    if template_arg:
        custom = template_arg if template_arg.is_absolute() else repo_root / template_arg
        if not custom.exists():
            raise FileNotFoundError(f"Template not found: {template_arg}")
        return custom.read_text(encoding="utf-8")

    skill_template = repo_root / ".agents/skills/voyager-feature-spec-author/references/TEMPLATE-feature-spec.md"
    if skill_template.exists():
        return skill_template.read_text(encoding="utf-8")

    product_template = repo_root / "PRODUCT/05_FEATURE_SPECS/template.md"
    if product_template.exists():
        return product_template.read_text(encoding="utf-8")

    raise FileNotFoundError("No template found for feature spec generation.")


def build_bullets(values: Iterable[str], default: str = "TBD") -> str:
    items: List[str] = []
    for value in values:
        item = (value or "").strip()
        if not item:
            continue
        while item.startswith("- "):
            item = item[2:].lstrip()
        if item.startswith("[ ] "):
            item = item[4:].lstrip()
        items.append(item)
    if not items:
        return f"- {default}"
    return "\n".join(f"- {item}" for item in items)


def section_from_summary(summary: str, interaction_title: str, interaction_type: str) -> str:
    summary_clean = normalize(summary, "")
    if summary_clean and summary_clean not in {"-", "TBD"}:
        return summary_clean
    return f"{interaction_title} 인터랙션({interaction_type}) 실행 결과를 사용자 입장에서 확인할 수 있다."


def build_acceptance_criteria(interaction_title: str, summary: str, related_region: str) -> str:
    summary_text = normalize(summary, "요구된 결과가 사용자에게 표시된다")
    if summary_text in {"-", "TBD"}:
        summary_text = "요구된 결과가 사용자에게 표시된다"
    region_hint = normalize(related_region, "해당 UI 범위")

    lines = [
        f"현재 사용자 작업 맥락이 유효한 상황에서, {interaction_title}을(를) 수행하면, 결과가 사용자에게 관측 가능하게 반영되어야 한다.",
        f"{region_hint}이(가) 준비되지 않은 상황에서, 사용자가 {interaction_title}을(를) 실행하면, 실패 이유가 명확하게 전달되고 안전하게 중단되어야 한다.",
        f"{summary_text} 상황에서, {interaction_title} 실행이 부분 실패를 동반하더라도, 성공 항목과 실패 항목이 구분되어 표시되어야 한다.",
    ]
    return "\n".join(lines)


def get_related_interactions(feature_id: str, interactions: List[Tuple[int, Dict[str, str]]]) -> List[Dict[str, str]]:
    rows = [row for _, row in interactions if normalize(row.get("feature_id")) == feature_id]
    rows.sort(key=lambda row: normalize(row.get("interaction_id"), ""))
    return rows


def infer_feature_dir(base_dir: Path, feature_id: str, feature_title: str) -> Path:
    base_dir.mkdir(parents=True, exist_ok=True)
    matches = [path for path in sorted(base_dir.glob(f"{feature_id}-*")) if path.is_dir()]
    if matches:
        return matches[0]
    return base_dir / f"{feature_id}-{slugify(feature_title, 'feature')}"


def render_spec(
    template: str,
    interaction: Dict[str, str],
    feature: Dict[str, str],
    related_interactions: List[Dict[str, str]],
    source_line: int,
    feature_slug: str,
    interaction_slug: str,
    interaction_id: str,
) -> str:
    interaction_title = normalize(interaction.get("interaction_title"))
    interaction_type = normalize(interaction.get("interaction_type"))
    feature_title = normalize(feature.get("feature_title"))
    category_key = normalize(interaction.get("category_key"))
    feature_id = normalize(interaction.get("feature_id"))
    status = normalize(interaction.get("status"), "")
    if status in {"", "-"}:
        status = normalize(feature.get("status"), "-")

    summary = concrete_or_fallback(interaction.get("summary"), section_from_summary("", interaction_title, interaction_type))
    related_region = normalize(interaction.get("related_region"), "-")
    menu = concrete_or_fallback(interaction.get("menu"), "메뉴 없음")
    shortcut = concrete_or_fallback(interaction.get("shortcut"), "바인딩 없음")

    trigger_lines: List[str]
    if menu != "메뉴 없음" or shortcut != "바인딩 없음":
        trigger_lines = [
            f"메뉴 경로({menu})에서 인터랙션을 호출하는 경우",
            f"단축키({shortcut})로 인터랙션을 호출하는 경우",
        ]
    else:
        trigger_lines = [f"현재 화면/상태에서 {interaction_title}이(가) 노출되는 경로에서 호출되는 경우"]
    if related_region != "-":
        trigger_lines.append(f"{related_region} 연관 구간에서 노출되는 경우")

    preconditions = [
        f"{interaction_type} 인터랙션이 유효한 대상에 대해 호출 가능한 상태",
        "필요한 데이터/권한 조건이 충족됨",
    ]
    state_changes = [
        "관측 가능한 상태 변화가 요구되는 경우, 상태가 사용자 동작 단위로 갱신됨",
        "요건 충족이 실패한 경우, 기존 상태를 보존하고 피드백을 노출함",
    ]
    feedback = [
        "실행 전/중/후 사용자 피드백이 누락되지 않음",
        "오류/실패 메시지 및 재시도 경로가 노출됨",
    ]
    edge_cases = [
        "동일 인터랙션이 반복 호출되는 경우, 중복 처리 동작이 안정적이어야 함",
        "대상 데이터가 없거나 권한이 없는 경우 graceful fallback가 필요함",
        "비동기 처리 지연/취소가 발생한 경우 상태 일관성이 유지되어야 함",
    ]
    permissions = [
        "권한 또는 시스템 상태 선행 조건 점검이 선결되어야 함",
        "네트워크/로컬 서비스 연결 상태를 반영할 수 있어야 함",
    ]
    observability = [
        "인터랙션 진입 이벤트",
        "성공/실패 이벤트",
        "재시도 이벤트",
    ]
    related_md = [
        f"- `{row.get('interaction_id', '-')}` - {normalize(row.get('interaction_title', '-'))}"
        for row in related_interactions
    ] or ["- -"]

    replacements = {
        "{Interaction Title}": interaction_title,
        "{interaction_id}": interaction_id,
        "{interaction_type}": interaction_type,
        "{feature_title}": feature_title,
        "{category_key}": category_key,
        "{feature_id}": feature_id,
        "{status}": status,
        "{summary}": summary,
        "{related_region}": related_region,
        "{menu}": menu,
        "{shortcut}": shortcut,
        "{interaction_id_yaml}": yaml_quote(interaction_id),
        "{interaction_type_yaml}": yaml_quote(interaction_type),
        "{feature_title_yaml}": yaml_quote(feature_title),
        "{category_key_yaml}": yaml_quote(category_key),
        "{feature_id_yaml}": yaml_quote(feature_id),
        "{status_yaml}": yaml_quote(status),
        "{summary_yaml}": yaml_quote(summary),
        "{related_region_yaml}": yaml_quote(related_region),
        "{menu_yaml}": yaml_quote(menu),
        "{shortcut_yaml}": yaml_quote(shortcut),
        "{intent}": build_bullets([section_from_summary(summary, interaction_title, interaction_type)]),
        "{trigger_section}": build_bullets(trigger_lines),
        "{preconditions_section}": build_bullets(preconditions),
        "{expected_outcome_section}": build_bullets([section_from_summary(summary, interaction_title, interaction_type)]),
        "{state_changes_section}": build_bullets(state_changes),
        "{feedback_section}": build_bullets(feedback),
        "{edge_cases_section}": build_bullets(edge_cases),
        "{acceptance_criteria}": "\n".join(
            f"- [ ] {line}" for line in build_acceptance_criteria(interaction_title, summary, related_region).split("\n")
        ),
        "{permissions_section}": build_bullets(permissions),
        "{observability_section}": build_bullets(observability),
        "{related_interactions_section}": "\n".join(related_md),
        "{source_line}": str(source_line),
        "{feature_slug}": feature_slug,
        "{interaction_slug}": interaction_slug,
    }

    rendered = template
    for old, new in replacements.items():
        rendered = rendered.replace(old, new)
    return rendered.strip() + "\n"


def parse_args() -> Args:
    parser = argparse.ArgumentParser(description="Generate Voyager FEATURE_SPEC draft from interaction_id")
    parser.add_argument("interaction_ids", nargs="+", help="Target interaction_id list")
    parser.add_argument("--output-dir", type=Path, default=None, help="Write outputs to this dir")
    parser.add_argument("--overwrite", action="store_true", help="Overwrite existing files")
    parser.add_argument("--dry-run", action="store_true", help="Print generated draft without writing")
    parser.add_argument("--template", type=Path, default=None, help="Template path")
    return parser.parse_args(namespace=Args())


def main() -> int:
    args = parse_args()

    repo_root = find_repo_root(Path(__file__).resolve().parent)
    interactions = read_tsv_rows(repo_root / "PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv")
    features = read_tsv_rows(repo_root / "PRODUCT/04_FEATURE_INVENTORY/FEATURES/data.tsv")
    feature_by_id = {normalize(row.get("feature_id", "")): row for _, row in features}
    interaction_map = {normalize(row.get("interaction_id", "")): (line_no, row) for line_no, row in interactions}
    template = load_template(repo_root, args.template)

    generated_count = 0
    for input_interaction_id in args.interaction_ids:
        if not input_interaction_id.strip():
            continue
        interaction_id = normalize(input_interaction_id, "")
        if interaction_id not in interaction_map:
            available = ", ".join(sorted(interaction_map.keys())[:10])
            print(f"Error: interaction_id not found: {interaction_id}")
            print(f"Hint: available ids include {available}...")
            return 1

        source_line, interaction = interaction_map[interaction_id]
        feature_id = normalize(interaction.get("feature_id"), "")
        feature = feature_by_id.get(feature_id, {})
        if not feature_id or not feature:
            print(f"Error: feature_id missing or not found for {interaction_id}")
            return 1

        interaction_title = normalize(interaction.get("interaction_title"), interaction_id)
        interaction_slug = slugify(interaction_title, "interaction")
        feature_title = normalize(feature.get("feature_title"), "feature")
        feature_slug = slugify(feature_title, "feature")
        category_key = normalize(interaction.get("category_key"), "")
        category_dir = repo_root / "PRODUCT/05_FEATURE_SPECS" / category_key.lower()
        feature_dir = infer_feature_dir(category_dir, feature_id, feature_title)

        content = render_spec(
            template=template,
            interaction=interaction,
            feature=feature,
            related_interactions=get_related_interactions(feature_id, interactions),
            source_line=source_line,
            feature_slug=feature_slug,
            interaction_slug=interaction_slug,
            interaction_id=interaction_id,
        )

        if args.output_dir:
            output_path = args.output_dir / f"{interaction_id}-{interaction_slug}.md"
        else:
            output_path = feature_dir / f"{interaction_id}-{interaction_slug}.md"

        if output_path.exists() and not args.overwrite:
            print(f"Error: output exists: {output_path}. Use --overwrite to replace.")
            return 1

        if args.dry_run:
            print(f"--- {output_path}\n{content}")
        else:
            output_path.parent.mkdir(parents=True, exist_ok=True)
            output_path.write_text(content, encoding="utf-8")
            print(f"Wrote {output_path}")
        generated_count += 1

    if generated_count == 0:
        print("Error: no interaction_id processed")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
