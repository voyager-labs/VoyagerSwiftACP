# Voyager Dev macOS Architecture Shape

Use this file as the architecture navigation page for `voyager-dev`, not as the full architecture dump.

## Read this when

- The task touches Voyager architecture but you are not yet sure which deeper reference applies.
- You need to choose the next reference file without loading every architecture document.

## Reference map

- Layer choice, segment placement, dependency direction
- Read `../../reviewer/review/references/layer-and-segment-rules.md`
- Slice boundary, peer-slice imports, package-friendly public surfaces
- Read `../../reviewer/review/references/public-boundary-spec.md`
- Package extraction posture, extraction checks, current extracted targets
    - Read `../../planner/scaffold/references/package-extraction-posture.md`
- TCA ownership, dependency clients, effect and cancellation rules
    - Read `../../implementer/tca-contract/references/tca-contract.md`
- Parent/child reducer decomposition
    - Read `../../planner/decompose/references/orchestrator-spec.md`
- App-thin integration, package-to-app wiring, typealias bridges, XPC boundary contracts
    - Read `../../planner/scaffold/references/app-thin-integration-spec.md`
- Shell freeze, shared utility promotion into `06_Shared`, rollback/sunset guidance
    - Read `../../planner/reuse-evaluation/references/shell-freeze-and-shared-promotion.md`

## Escalation rule

- Do not load every referenced file by default.
- Start with the smallest file that matches the decision in front of you.
- Escalate to multiple references only when the task spans layer, boundary, and ownership concerns at the same time.
