# Design Version Workflow

Use one Storybook state matrix to compare the accepted UI with multiple in-tree design candidates.

## Version contract

- `current` is the accepted implementation. It may claim native parity only with the native evidence required elsewhere in this skill.
- Candidate IDs use `candidate-<semantic-slug>`, such as `candidate-material` or `candidate-compact-layout`.
- A candidate is a proposal, not native or product truth.
- Keep Appearance, OS Baseline, UI State, and Geometry as separate Storybook axes. Do not encode them into IDs such as `candidate-material-dark-sequoia-processing`.

Derive the ID union from one typed registry so the toolbar, CSS selectors, and structural branches share the same vocabulary.

## Reuse before variation

Start from the closest existing current variation:

1. Reuse its deterministic fixture and story args.
2. Reuse its semantic token chain and shared primitives.
3. Express only the candidate delta.

Do not copy the Ready/Processing/Context matrix, fork fixture data, or duplicate the full File Manager composition merely to change one design decision. Existing variations are reference inputs, not templates to clone wholesale.

## Choose the narrowest seam

| Candidate changes                            | Implementation seam                                                                                           |
| -------------------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| Color, material, border, typography, spacing | Scope CSS under `[data-design-version="candidate-…"]`; override only changed declarations.                    |
| One component or its placement               | Branch at the owning component or composition boundary; reuse unchanged children.                             |
| Window or region layout                      | Select current/candidate layouts at the nearest stable layout owner; share fixtures, regions, and primitives. |
| New UI state                                 | Add the state once to the shared matrix, then render it across every applicable design version.               |

Avoid leaf-level version checks scattered through the tree. Move the decision upward until each branch owns a coherent visual unit.

## Storybook surface

- Default the Design Version control to `current`.
- Expose all active candidate IDs through the same global or root arg.
- Keep the existing stories and fixtures; switching Design Version changes the rendering, not the state catalog.
- Add a side-by-side comparison story only when simultaneous viewing resolves a real review question; do not duplicate every state for comparison.

## Candidate lifecycle

### Accept

1. Implement and verify the adopted native behavior when the product surface is native-owned.
2. Move the adopted delta into `current`.
3. Delete the superseded current implementation and candidate registry entry.
4. Remove candidate-only CSS and branches that no longer carry a distinct decision.

### Reject

Delete the candidate registry entry and its scoped delta. Shared stories and fixtures remain unchanged.

The source tree should contain only `current` plus candidates with an unresolved review question.

## Boundaries

- Do not require a Linear issue, Git branch, worktree, duplicate Storybook server, or screenshot baseline merely to compare design versions.
- Do not add version fields to product domain state; Design Version is a Design Lab rendering axis.
- Do not preserve candidates as permanent compatibility modes after a decision.
- Do not describe candidate rendering as native parity.
