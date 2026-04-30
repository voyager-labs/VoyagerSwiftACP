# Agent Skill Authoring Pipeline

This directory uses a grouped skill-authoring stack instead of the previous monolithic `skill-creator` skill.

## Skill roles

- `skill-standardization`: preflight spec gate for `SKILL.md` structure, frontmatter, directory layout, and basic eval scaffolding.
- `skill-maker`: primary authoring loop for capturing intent, drafting skills, designing evals, benchmarking, refining, and packaging.
- `skill-judge`: qualitative design review for knowledge delta, trigger quality, progressive disclosure, anti-patterns, and practical usability.
- `skillgrade-setup` / `skillgrade-graders`: executable regression/eval harness setup and grading patterns for smoke, reliable, and regression runs.

## Required pipeline

Use this order when creating or significantly changing a skill:

1. Run `skill-standardization` first to normalize the skill shape and catch spec problems.
2. Use `skill-maker` for the authoring and iteration loop.
3. Use `skill-judge` before publishing or adopting the skill to catch design-quality failures.
4. Use `skillgrade-setup` and `skillgrade-graders` for behavior-level regression checks when the skill has verifiable outputs.
5. If runtime evals fail, return to `skill-maker`; if spec checks fail, return to `skill-standardization`.

## Boundaries

- Treat `skill-standardization` as the source of truth for spec compliance.
- Treat `skill-maker` as the source of truth for iterative authoring workflow and eval artifact layout.
- Treat `skill-judge` as advisory design review, not proof that the skill works.
- Treat `skillgrade` results as behavior evidence, but only when eval prompts are discriminating enough to fail without the skill.

## Anthropic independence

Prefer deterministic/local evaluation paths by default:

- For `skillgrade`, prefer deterministic graders first.
- Use `--provider=local` in CI-like environments when appropriate.
- Avoid Anthropic-only description/eval loops unless explicitly requested.
- If an LLM rubric is needed, prefer the provider already configured in the environment (Gemini, OpenAI, Codex, or ACP) rather than adding a Claude API dependency.

## Failure modes to watch

- Passing spec validation does not prove the skill is useful.
- A high `skill-judge` score does not prove runtime behavior.
- Easy `skillgrade` evals create false confidence; include edge cases and baseline-failing scenarios.
- Avoid overfitting `skill-maker` iterations to a tiny eval set.
- Do not duplicate the same rule across many skills; keep shared authoring rules here.
