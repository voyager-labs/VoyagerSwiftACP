# Relation Taxonomy

Use this taxonomy for `relations` in knowledge entry frontmatter and `edges` in `index.json`.

## Allowed relation types

| Relation       | Use when                                                                                    |
| -------------- | ------------------------------------------------------------------------------------------- |
| `relates_to`   | Two nodes are generally related, but a more specific relation is not justified.             |
| `derived_from` | This entry was extracted from another artifact, session, plan, review, or entry.            |
| `affects`      | This entry changes or constrains future work on a plan, file, skill, rule, or runtime path. |
| `motivates`    | This entry provides the reason for a later proposal, decision, or implementation.           |
| `supersedes`   | This entry replaces an older entry. Mark the older entry `superseded` when possible.        |
| `contradicts`  | This entry conflicts with another entry and needs reconciliation.                           |
| `resolved_by`  | A later entry, plan, review, PR, or change resolves the issue in this entry.                |
| `evidence_for` | This entry supports a finding, decision, review, or proposal as evidence.                   |
| `verified_by`  | This entry was confirmed by a test, build, review, or explicit source.                      |
| `example_of`   | This entry is a concrete instance of a broader pattern or finding.                          |

## Direction rules

- `derived_from`: new entry → source artifact or source entry.
- `affects`: knowledge entry → affected artifact.
- `motivates`: reason/finding → proposal/decision.
- `supersedes`: newer entry → older entry.
- `resolved_by`: problem entry → resolver entry or artifact.
- `evidence_for`: evidence entry → finding or decision.
- `verified_by`: claim entry → verification artifact.
- `example_of`: concrete entry → abstract pattern entry.

## Anti-patterns

- Do not use `relates_to` when `motivates`, `affects`, or `derived_from` is accurate.
- Do not create one edge for every vague association; graph density should reflect useful retrieval paths.
- Do not invent synonyms such as `caused_by`, `linked_to`, or `mentions` unless the taxonomy is updated first.
