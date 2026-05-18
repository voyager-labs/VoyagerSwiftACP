# Skill Map

This map records which existing skills and project-scoped agents `product-owner` is expected to orchestrate.

## Why This Exists

The goal is to keep `product-owner` as an orchestration entrypoint inside the `voyager-product-owner/` group without absorbing the underlying author/reviewer skills into one giant skill body.

## Independent Skill Surfaces

- `.agents/skills/voyager-product-owner/author/feature-spec/`
- `.agents/skills/voyager-product-owner/checker/feature-spec/`
- `.agents/skills/voyager-product-owner/checker/bundle-consistency/`
- `.agents/skills/voyager-product-owner/author/linear-issue/`
- `.agents/skills/voyager-product-owner/author/feature-spec-issue/`
- `.agents/skills/voyager-product-owner/author/feature-inventory/`
- `.agents/skills/voyager-product-owner/checker/feature-inventory/`
- `.agents/skills/voyager-product-owner/checker/category-audit/`

These remain separate skills with their own references, scripts, and eval assets.

## Project-scoped Agent Surfaces

Source of truth:

- `.codex/agents/README.md`
- `.codex/agents/*.toml`

Primary delegate agents:

- `product_interviewer`
- `scope_reviewer`
- `inventory_author`
- `spec_author`
- `bundle_reviewer`
- `spec_style_reviewer`
- `product_researcher`
- `linear_issue_author`
- `feature_spec_issue_author`

## Routing Principle

`product-owner` chooses among these stable delegate surfaces.

It does not redefine them and it does not replace their local workflows.
