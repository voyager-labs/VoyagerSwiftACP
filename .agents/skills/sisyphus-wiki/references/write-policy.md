# Write Policy

Use this policy to decide when to create, update, or skip `.sisyphus/knowledge/` entries.

## Write a new entry when

- The user states a durable preference, naming decision, workflow direction, or constraint.
- A review or investigation discovers a reusable failure mode, traceability gap, or process issue.
- A planless conversation materially changes how future work should be planned, implemented, reviewed, or verified.
- A rejected idea is important enough that future agents might otherwise repeat it.
- A correction explains why prior work was wrong and how it was fixed.
- A project-specific pattern emerges across multiple plans, sessions, or reviews.

## Update an existing entry when

- New evidence strengthens, weakens, resolves, or supersedes an existing claim.
- A relation should be added to a plan, review, skill, rule, file, or external source.
- A status changes from `active` to `resolved`, `superseded`, or `archived`.

## Skip writing when

- The information is a raw command log, tool output, or temporary execution detail with no durable implication.
- The same knowledge already exists and no new relation or evidence is added.
- The content belongs in plan-scoped evidence, notepads, or reviews and has no cross-session value.
- The note would expose secrets, credentials, or sensitive payloads.

## Body guidance

- Keep entries compact and source-linked.
- Prefer one durable insight per entry.
- Include why the knowledge matters for future agents.
- Link to scoped artifacts instead of copying them.

## Safety

- Redact secrets and sensitive data.
- Treat `.sisyphus/knowledge/` as local-only unless explicitly exported.
- Do not represent unverified guesses as high-confidence knowledge.
