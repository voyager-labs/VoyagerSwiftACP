# 04 — Repository-Aware Review Execution

Run after `03-context-gathering.md` has completed and any background exploration results have been collected.

## Policy sections to apply

Apply the current `.greptile/rules.md` policy sections in priority order. Do not restate their policy text in review output.

1. §Repository-aware review priority
2. §Voyager architecture model
3. §TCA and segment ownership
4. §Reuse and duplicate detection
5. §Cross-feature command routing
6. §AppKit coordinator review
7. §Async lifecycle and cancellation
8. §File-backed storage and credentials
9. §Backend API contracts
10. §Environment, secrets, and build settings
11. §Helper and XPC contracts
12. §Package and public boundaries
13. §Local-only artifacts
14. §Test review

## Reference playbook

Load `references/review-playbook.md` for concrete check methods per review area. The playbook operationalizes checks with commands and patterns without duplicating `.greptile/rules.md` policy.

## Conditional reference load

If the diff touches `apps/macos/Hosts/**`, host `.xcodeproj`, `*Host*Fixture*`, or `*Preview*`, load `references/host-review-checks.md` before executing checks in those areas.

## Finding discipline

Only produce P0/P1 findings with concrete evidence. Do not flag speculative issues or generic improvement suggestions.
