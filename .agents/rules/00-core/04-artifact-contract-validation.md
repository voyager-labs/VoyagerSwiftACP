---
alwaysApply: true
description: "Validate structured outputs against their documented schema, contract, or protocol before claiming compliance."
---

# Structured Output Compliance

## Applies when

- Creating or updating structured outputs that claim schema, contract, protocol, or format compliance.
- Reviewing sample outputs, fixture outputs, manifests, findings, reports, config-like documents, or other generated harness artifacts.

## Must

- Validate every claimed structured output against its canonical schema, contract, or protocol document before reporting success.
- Check required fields, required sections, and enum/value constraints explicitly.
- Verify references, links, lineage paths, and referenced files resolve to the exact expected targets.
- Distinguish degraded output, partial output, and failed output exactly as the governing contract defines.
- Report any drift as a contract violation, not as an acceptable approximation.

## Must not

- Claim an output is compliant because it "looks right" without field-by-field or section-by-section validation.
- Treat optional-input degradation as a hard failure when the contract says to degrade gracefully.
- Treat missing required inputs as a degraded success when the contract says to stop.
- Invent fallback field values, lineage, references, or status labels that the governing contract does not define.

## Execution steps

1. Locate the canonical schema, contract, or protocol document for the output family.
2. Compare the output field-by-field and section-by-section against that governing document.
3. Verify referenced paths, filenames, links, and lineage entries resolve exactly.
4. Check threshold logic, verdict labels, lifecycle states, and degradation/failure behavior.
5. Only report compliance after every required check passes.

## Verification

- Confirm the output uses only documented field names, section names, and enum values.
- Confirm every required section or key is present.
- Confirm referenced files, links, and lineage paths exist and match the claimed source set.
- Confirm degradation, partial-success, and failure behavior match the contract exactly.

## Few-shot examples

- **Bad:** A degraded compound-review run emits `FAILURE.md` because some optional facets are missing.
  **Good:** Keep the run successful, mark reduced confidence, and list the missing optional sources exactly as the contract defines.

- **Bad:** A findings artifact uses a "close enough" metadata shape because the intended owner/action class/verdict feels obvious.
  **Good:** Use the exact documented finding shape, even when the substitute looks semantically similar.

- **Bad:** A draft says "no findings met threshold" because the reviewer considers the issue low-risk, even though the documented threshold is met.
  **Good:** Apply the threshold mechanically and emit the proposal when the contract says it qualifies.

- **Bad:** A structured report swaps exact source linkage for inferred paths or cross-case references that seem equivalent.
  **Good:** Preserve the exact documented source linkage and artifact paths required by the protocol.
