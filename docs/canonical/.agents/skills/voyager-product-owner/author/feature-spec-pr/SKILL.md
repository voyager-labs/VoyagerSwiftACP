---
name: feature-spec-pr-author
description: "Draft Voyager feature-spec issue PR bodies from the current repo template, changed PRODUCT docs, and the repo's established PR writing style. Use whenever the user asks for a PR body, PR description, PR markdown, or `PR 써줘` for Voyager feature-spec issue work, especially after editing `PRODUCT/05_FEATURE_SPECS`, related inventory/IA/use-case docs, or when multiple specs must be summarized under one PR."
---

# Voyager Feature Spec PR Author

Draft ready-to-paste PR bodies for Voyager feature-spec issue work.

This skill is for PR authoring, not for editing SSOT itself. Use it when the user wants a PR body that matches the repo's actual review style and explains spec deltas clearly.

## Sources of truth

- `.github/PULL_REQUEST_TEMPLATE/voyager-feature-spec-issue-pr.md`
- `AGENTS.md`
- `assets/TEMPLATE-feature-spec-pr.md` for the local section shell that mirrors the repo template's visible structure
- `assets/examples/EXAMPLE-feature-spec-pr-body.md` for a concrete prose-first example
- `assets/examples/EXAMPLE-feature-spec-pr-context.md` for the commit grouping and branch narrative behind that example
- linked Linear issue body and comments when available
- parent or phase issue context when it materially explains why this PR exists
- changed files and their diffs in the current working tree
- adjacent IA/FI/FS truth for the touched specs
- any Linear issue link or issue id the user explicitly provides
- recent PR bodies in this repo when the user wants repo-native phrasing

## Resource Layout

- Use `assets/` for reusable output shells and applied examples that can be adapted directly into new PR bodies.
- Keep `references/` for rules, workflows, and other non-asset guidance only.

## Current repo writing pattern

Recent Voyager documentation PRs are not fully free-form. They usually:

- use a PR title in the format `[ISSUE-ID] {title}` when a linked Linear issue is known
- open with an `Intent` that keeps the `Linear 이슈` line visible and then explains the narrower decision boundary in a short prose paragraph
- use a `Validation` or `Validation Evidence` section for concrete commands or manual review evidence
- keep `Spec Delta` prose-first, with one short paragraph per changed spec and only a few supporting metadata lines
- avoid checklist-like filler sections when a short reviewer-facing paragraph communicates the same thing more naturally

When the current template and recent PR tone differ, follow the current template's visible section headers but write the content in this repo-native style.
Treat any HTML comments in the template as authoring hints only. Do not keep those comments in the drafted PR body unless the user explicitly asks for a template copy.
Use the local PR template for section shape and the example docs for tone and paragraph shape, not as a text fragment bank to copy blindly.

## Workflow

1. Load the template and current diff

- Read `.github/PULL_REQUEST_TEMPLATE/voyager-feature-spec-issue-pr.md` first.
- Use `assets/TEMPLATE-feature-spec-pr.md` as a local shell reference when the repo template's HTML comments make the output shape harder to parse quickly.
- Preserve the template's visible header structure unless the user explicitly asks to change the template itself.
- Inspect changed files and diffs before drafting the PR body.

1. Collect PR context

- Identify the linked Linear issue from explicit user input. If missing, leave a placeholder instead of inventing one.
- When the linked issue is available, use `[ISSUE-ID] {title}` as the default PR title format. Reuse the linked issue id verbatim and do not drop the square brackets.
- When the issue is available, read:
    - the issue title and body
    - issue comments when they contain product decisions or later clarifications
    - the parent or phase issue when it explains why this docs PR exists
- Determine which specs actually changed.
- Inspect adjacent SSOT truth for those specs when needed:
    - related FI rows
    - related IA keys or objects
    - adjacent or sibling specs that define the same contract boundary
- Gather supporting `feature_id`, `interaction_id`, `window_structure_key`, or `use case` ids only when they help reviewers understand the delta.
- If the linked issue and the current diff suggest different stories, prefer the latest explicit product decision you can point to and make the PR wording reflect that narrower truth.

1. Write `Spec Delta` in the repo's actual style

- Under `Spec Delta`, duplicate the `### \`...\`` block once per changed delta block.
- Prefer a literal `interaction_id` or other spec id when one changed unit maps cleanly to one spec.
- If one block needs to summarize multiple adjacent specs or shared artifacts, use a short stable title that a reviewer can understand immediately without pretending it is a fake spec id.
- Keep only the blocks that materially help review the changed decision boundary; remove unused example blocks.
- The first paragraph of each spec block should combine:
    - what problem or review friction existed before this PR
    - what this PR actually decided
    - what contract boundary or behavior slice is now considered locked
- After that paragraph, use only the supporting lines the template asks for:
    - `근거`: issue comment, parent context, adjacent SSOT, or diff fact that supports the decision
    - `남겨둔 범위`: what is still intentionally left open
    - `관련 ids / keys`: only stable ids or keys that help a reviewer map the paragraph back to real specs, contracts, flows, or catalog rows
- If a block title is broad but `관련 ids / keys` cannot point to anything stable, the block is probably too abstract for this template. Narrow the title, split the block, or remove that support line.
- Keep each block concise but not skeletal. It should read like a compressed decision note for reviewers, not like a TSV changelog or form field dump.
- Do not paste full feature or interaction descriptions from SSOT.

1. Fill the remaining sections

- `Intent`: keep the `Linear 이슈` line, then write one short paragraph below it.
  That paragraph should show what upstream issue context made this PR necessary and what narrower contract boundary this PR actually locks.
- `Validation` or `Validation Evidence`: list only checks or manual reviews that were actually performed. Prefer concrete commands and explicit manual review notes, matching merged PR style.
- If no automation was run, say so explicitly instead of implying validation happened.
- Do not add standalone `Scope`, `Risk`, `Follow-ups`, or `Rollback` sections unless the user explicitly asks for them.
- If a reviewer should notice unresolved scope or caution points, express them inside `Intent` or `Spec Delta` instead of creating filler sections.
- If the current diff produces so many unrelated spec blocks that the template feels awkward, say so explicitly and recommend splitting the PR or using a more general PR description instead of forcing a fake single-story summary.

1. Match repo-native tone

- Write Korean by default under the template headers.
- Prefer product-facing and contract-facing wording.
- Sound like an engineer documenting a reviewable change, not like a generated executive summary.
- Be specific about what changed and why it matters, but avoid repeating the entire diff.

1. Return the result

- Default output is ready-to-paste Markdown only.
- If the user asks for a PR title, PR creation, or a full PR draft, include a recommended title first. When a linked Linear issue is known, format it as `[ISSUE-ID] {title}`.
- If the user asks for rationale, add a short note after the draft explaining how the content was derived from the diff and current PR conventions.

## Guardrails

- Do not invent a Linear issue id, spec id, or validation command.
- Do not output a PR title that drops the linked Linear issue id when one is known.
- Do not invent rationale from memory when the issue or comments do not support it. If context is missing, say the wording is based on the current diff and visible SSOT only.
- Do not restate large sections of changed spec files in the PR body.
- Do not summarize untouched specs just because they are related.
- Prefer contract-level wording over implementation detail.
- Do not use vague section titles that cannot be tied back to stable artifacts through the paragraph or `관련 ids / keys`.
- Do not output template guide comments in the final drafted PR body unless the user explicitly wants the raw template form.
- If the PR is mostly repo maintenance or generic docs cleanup rather than feature-spec issue work, say this skill is not the right fit and switch to a generic PR drafting approach.

## Output standard

Good PR bodies from this skill should let a reviewer answer:

- which specs changed
- what upstream issue context this PR is responding to
- why each spec delta took this shape
- what decision boundary each spec delta now locks
- what the PR intentionally did not settle
- what checks were actually done
