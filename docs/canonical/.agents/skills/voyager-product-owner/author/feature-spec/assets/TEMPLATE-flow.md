# {Flow Title}

<!-- 작성 규칙: 본문 내용(문장)은 한국어 우선으로 작성 -->

## Intent

{intent}

## Contract References

- [{contract_label}](../contracts/{contract_filename})

## Interaction Coverage

- [{interaction_label}](../{interaction_relative_path})

## Flow Overview

```mermaid
%% Choose the direction that fits the flow: TD, LR, RL, or BT.
flowchart TD
  A[{Step A}] --> B[{Step B}]
```

## Happy Path

1. {happy_path_step_1}
2. {happy_path_step_2}

## Alternate Paths

### {Branch Title}

1. {branch_step_1}
2. {branch_step_2}

## Boundary Notes

{boundary_notes}

## Source

- Category: `{category_key}`
- Related contracts: [{contract_filename}](../contracts/{contract_filename})
