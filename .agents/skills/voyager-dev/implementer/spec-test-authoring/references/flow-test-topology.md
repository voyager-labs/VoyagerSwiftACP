# Flow Test Topology

## Must

- Treat canonical flow documents as the owner of production-composition journeys, cross-feature handoffs, and observable product outcomes.
- Treat `Specs/` as the owner of interaction-level AC detail, local reducer or effect behavior, and detailed branch semantics.
- Place each canonical flow suite under `VoyagerTests/Flows/<UPPER_CATEGORY>/` and name it `<PascalSlug>FlowTests.swift`.
- Use exactly one owner for every behavior assertion. `Specs/` and `Flows/` must not duplicate assertions.
- Use this mapping contract:

| Field           | Value                                                                                |
| --------------- | ------------------------------------------------------------------------------------ |
| Input flow ID   | `<lowercase-category>.<snake_case-slug>`                                             |
| Category regex  | `[a-z][a-z0-9]*`                                                                     |
| Slug regex      | `[a-z0-9]+(?:_[a-z0-9]+)*`                                                           |
| Document suffix | `_flow.md` (mandatory)                                                               |
| Document path   | `docs/canonical/PRODUCT/05_FEATURE_SPECS/<category>/flows/<slug>_flow.md`            |
| Swift file      | `apps/macos/Voyager/VoyagerTests/Flows/<UPPER_CATEGORY>/<PascalSlug>FlowTests.swift` |
| Class name      | `<PascalSlug>FlowTests` (matches filename minus `.swift`)                            |
| XCTest selector | `VoyagerTests/<PascalSlug>FlowTests` (directory components NEVER appear)             |
| File marker     | `// FLOW-ID: <category>.<slug>` (first code line in the file)                        |
| Path marker     | `// FLOW-PATH: <path_name>` (per scenario)                                           |

## Must not

- Put production-composition flow suites in `Specs/`.
- Duplicate behavior assertions between `Specs/` and `Flows/`.
- Normalize rejected forms:
    - Uppercase category, such as `ONB.access_unlock`.
    - Uppercase or dash slug, such as `onb.access-unlock` or `onb.AccessUnlock`.
    - Missing `_flow.md` suffix.
    - Directory components in a selector, such as `VoyagerTests/Flows/ONB/AccessUnlockFlowTests`.

## Execution steps

1. Validate the input flow ID against the category and slug regexes.
2. Resolve the mandatory `_flow.md` document path.
3. Derive the uppercase category, PascalCase slug, suite filename, class name, selector, and markers from that flow ID.
4. Put production-composition assertions in the flow suite. Keep interaction AC detail and local branch semantics in the owning `Specs/` suite.
5. Use the runner or checker exit code contract:
    - `0`: success, report, or list.
    - `1`: mapped-suite structural mismatch in checker mode.
    - `2`: invalid invocation, malformed flow ID, or explicitly requested missing document or suite.
    - XCTest child exit: preserve unchanged.

## Verification

- Confirm every flow document and suite maps as follows:

| Flow ID                       | Document                                    | Swift file                                       | Selector                                      |
| ----------------------------- | ------------------------------------------- | ------------------------------------------------ | --------------------------------------------- |
| `onb.access_unlock`           | `onb/flows/access_unlock_flow.md`           | `Flows/ONB/AccessUnlockFlowTests.swift`          | `VoyagerTests/AccessUnlockFlowTests`          |
| `cbw.chat_session_management` | `cbw/flows/chat_session_management_flow.md` | `Flows/CBW/ChatSessionManagementFlowTests.swift` | `VoyagerTests/ChatSessionManagementFlowTests` |

- Confirm the first code line is the matching `// FLOW-ID:` marker and each scenario has a `// FLOW-PATH:` marker.
- Confirm `Specs/` and `Flows/` do not assert the same behavior.
