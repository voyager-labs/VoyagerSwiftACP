---
name: feature-spec-issue-author
description: "Draft Linear FOUNDATION_DOCS / feature-spec-definition issue bodies from Voyager parent phase issues and current IA/FI/FS truth. Use when creating or refining `기능 스펙 정의`, `기능 스펙 정의 및 정리`, `FOUNDATION_DOCS`, or other docs-first issue descriptions that exist to decide what IA, FI, and FS artifacts should be authored or reinforced before design/build. Do not use for build/implementation issues; use `linear-issue-author` for those."
---

# Voyager Feature Spec Issue Author

Draft ready-to-paste Linear issue bodies for docs-first feature-spec definition work.

This skill is for issue authoring, not for directly editing SSOT.
Use it when the output should be a Product team's `FOUNDATION_DOCS` issue that locks product behavior before design or build.
This lane exists before `Phase 1. AI Draft Authoring` and should define the handoff into that lifecycle instead of silently doing the authoring work itself.

## What This Issue Type Means

In this repo, these issues usually:

- sit under a phase or parent issue as the docs-first slice,
- land before `AI Draft Complete` work starts,
- define the product contract before downstream design/build issues move,
- explain which IA/FI/FS surfaces are expected to be created or reinforced,
- keep implementation detail deferred while making behavior, state, and scope concrete.

Typical title shapes:

- `{surface} 기능 스펙 정의`
- `{surface} 기능 스펙 정의 및 정리`

## Sources of truth

- Linear parent issue and target issue context
- live Linear issue template content fetched through `.agents/skills/linear-cli/`
- `.agents/skills/linear-cli/SKILL.md`
- `.agents/skills/linear-cli/references/schema.md`
- `.agents/skills/linear-cli/references/api.md`
- `.agents/skills/voyager-product-owner/author/feature-spec-issue/assets/FEATURE_SPEC_ISSUE_TEMPLATE.md` as fallback only when the live Linear template cannot be read
- `PRODUCT/03_INFORMATION_ARCHITECTURE/`
- `PRODUCT/04_FEATURE_INVENTORY/`
- `PRODUCT/05_FEATURE_SPECS/`
- `PRODUCT/06_USE_CASES/` when it materially helps explain the behavior slice
- thesis/persona docs only as reference context when the request is ambiguous
- external product references for `Reference products / patterns`:
    - official product pages
    - official help/docs pages
    - official demos, launch posts, or product tours when available
    - secondary visual inspiration sources such as Pinterest, Mobbin, Dribbble, or Behance only when they help with visual density or composition judgment

## Resource Layout

- Use `assets/` for reusable output shells and any future applied issue examples.
- Keep `references/` for rules, live-template fallback guidance, schemas, APIs, or workflow docs only.

## Workflow

1. Confirm the issue lane

- This skill is for docs-first issue authoring.
- If the request is really a build slice with concrete engineering scope, switch to `linear-issue-author`.

2. Read the parent issue first

- Pull the parent or phase issue from Linear when available.
- Reuse parent-owned project, milestone, cycle, label, and stage framing rather than inventing a parallel structure.
- Identify whether the requested issue is the `FOUNDATION_DOCS` slice, or another docs-first clarification slice.

3. Inspect the live Linear issue template first

- Use the installed `linear-cli` skill as the primary route for template inspection.
- Prefer `linear` if the CLI is already on PATH; otherwise use `npx @schpet/linear-cli`.
- Start by reading the GraphQL schema, then search for template-related types and fields before writing any query.
- Typical discovery flow:
    - `linear schema -o "${TMPDIR:-/tmp}/linear-schema.graphql"`
    - `rg -n "IssueTemplate|Template" "${TMPDIR:-/tmp}/linear-schema.graphql"`
    - derive the exact query shape from the schema
    - fetch the actual template content via `linear api`
- If the live Linear template body is accessible, preserve its section order, heading style, placeholder style, and fixed wording as the primary format contract.
- If the live Linear template uses structured rich-content nodes such as `collapsible_section`, tables, or todo lists, treat `descriptionData` as the canonical write path.
- In that case, do not use plain markdown updates through MCP issue save/update helpers as the final write path, because they flatten the template structure.
- Only fall back to the repo-local asset `FEATURE_SPEC_ISSUE_TEMPLATE.md` when the live Linear template cannot be read from the current environment.

4. Classify the expected document touch set

- Decide which layers are likely to move:
    - IA only when structure keys, surfaces, or regions are missing or stale
    - FI when feature or interaction rows are missing, unclear, or need status/wording alignment
    - FS when behavior/state/flow contracts need to be concretized
- Say which layers should stay untouched when the issue should remain narrow.

5. Read current repo truth before drafting

- Check the relevant IA/FI/FS rows and specs.
- Preserve unresolved truth:
    - `-` means intentionally empty / not applicable
    - `TBD` means unresolved and should surface as an open decision
- Never invent a `feature_id`, `interaction_id`, or `structure_key` just to make the issue look complete.

6. Research real reference products and capture links

- Do not write `Reference products / patterns` from memory only.
- Look up actual product pages before drafting that section.
- Prefer this source order:
    - official product or feature page
    - official help center / docs
    - official demo, launch post, video, or product tour
    - secondary visual reference such as Pinterest, Mobbin, Dribbble, or Behance
- When a secondary visual board is used, treat it as visual inspiration only, not as the behavioral source of truth.
- Keep 2 to 4 references per issue unless the behavior slice genuinely needs more.
- Include direct links inline in the issue body so reviewers can open the exact reference without re-searching.

7. Draft with the active template source

- If the live Linear template was fetched successfully, draft against that template first.
- Use `.agents/skills/voyager-product-owner/author/feature-spec-issue/assets/FEATURE_SPEC_ISSUE_TEMPLATE.md` only as fallback.
- Fill all sections with concrete product-language content while preserving the active template's structure.
- When the live template contains structured nodes, write the final issue body back through `linear api` / GraphQL using `issueUpdate(... descriptionData: ...)` and set `lastAppliedTemplateId` when appropriate.
- Remove unused guidance lines and empty bullets before returning the result.

8. Return the issue in a reusable package

- Provide:
    - suggested issue title
    - recommended parent/project/milestone/labels inheritance
    - expected doc touch set
    - the expected `Phase 1` entry point and success gates
    - which template source was used: live Linear template or local fallback
    - ready-to-paste issue body

## Writing rules

- Keep the issue product-facing and contract-facing.
- `Summary` should say what behavioral slice this issue locks, not how to implement it.
- `Candidate capability` should describe what users or the system must be able to do after the docs are settled.
- `Product behavior to define` should lock visible rules, states, and flow boundaries.
- `Reference products / patterns` should say what to borrow and what not to borrow, and should use direct Markdown links to real sources.
- `Core flow` should describe the happy path plus the one or two critical branches that change product meaning.
- `Main states` should say what the user sees, what is possible, and how the state is entered or recovered.
- `Open questions` should include only real product decision gaps.
- `Handoff` should be useful to both downstream design and downstream build issues.
- the issue should make it clear that `Phase 2. Human Review` starts only after the bundle reaches `AI Draft Complete`

## Guardrails

- Do not silently rewrite SSOT when asked only to author the issue.
- Do not collapse unresolved product questions into implementation placeholders.
- Do not overstate scope; docs-first issues should describe the contract to settle, not every eventual implementation task.
- Do not invent missing IDs. If the repo still has `TBD`, call that out explicitly in the issue.
- Do not silently prefer the repo-local fallback when the live Linear template is reachable.
- Do not finish with an MCP markdown write when the live template is structured. That drops collapsible and other rich-template nodes.
- Do not cite vague references like just `Figma`, `Notion`, or `Pinterest` without a concrete page, article, board, or demo link.
- Keep Korean prose by default, but preserve settled English UI labels, product names, status names, and CTA text when they are part of product truth.
- If the issue is mostly about implementation breakdown, acceptance criteria, data contracts, or build ownership, switch to `linear-issue-author`.
