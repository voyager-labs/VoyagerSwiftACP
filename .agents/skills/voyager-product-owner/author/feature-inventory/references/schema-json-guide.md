# Schema JSON Guide

Use this guide when `feature-inventory-author` work also requires editing a table's `schema.json`.

This repo uses `schema.json` as a lightweight structural contract for `data.tsv`, not as a full database schema.

## Purpose

- describe TSV column order and meaning
- declare required vs optional fields
- declare enum-like allowed values when they are stable
- declare cross-table references with `ref`

## Core rules

- `columns[].name` order must match the TSV header order exactly
- prefer `required` over nullable-style flags
- treat `-` as the null sentinel
- `TBD` is allowed for unresolved required content, but never for primary-key values
- use `ref` metadata instead of free-text relationship notes when a table really depends on another table
- keep schema changes narrow and local to the table being edited

## Top-level shape

Common fields:

- `schema_version`: optional string such as `"1.0"`
- `name`: table name
- `primary_key`: optional string array
- `null_values`: optional string array
- `columns`: ordered array of column objects

Example:

```json
{
    "schema_version": "1.0",
    "name": "FEATURES",
    "primary_key": ["feature_id"],
    "null_values": ["-"],
    "columns": [
        {
            "name": "feature_id",
            "type": "string",
            "required": true,
            "description": "Stable feature identifier."
        }
    ]
}
```

## Column fields

Supported column metadata:

- `name`: column name
- `type`: primitive type such as `string` or `number`
- `required`: optional boolean
- `description`: optional string
- `enum`: optional string array
- `ref`: optional object describing a table reference

## Required semantics

- `required: true` means the row needs a real value or an explicit unresolved placeholder
- `required: true` should not use `-`
- `required: true` may use `TBD` only for non-key fields
- `required: false` may use `-` or `TBD`

## Enum semantics

Use `enum` only when the allowed values are stable and reviewable.

Example:

```json
{
    "name": "interaction_type",
    "type": "string",
    "required": true,
    "enum": ["command", "input", "display", "background"],
    "description": "Interaction type."
}
```

Do not add `-` to `enum`; treat `-` through `null_values`.

## Ref semantics

Use `ref` when a column or column-set points to another table's stable key.

Single-column example:

```json
{
    "name": "category_key",
    "type": "string",
    "required": true,
    "ref": {
        "table": "FEATURE_CATEGORIES",
        "column": "category_key"
    }
}
```

Composite example:

```json
{
    "name": "parent_region_id",
    "type": "string",
    "required": false,
    "ref": {
        "table": "WINDOW_STRUCTURE",
        "columns": ["window_id", "parent_region_id"],
        "references": ["window_id", "region_id"]
    }
}
```

## When to edit schema.json

Edit `schema.json` in the same pass when you:

- add a TSV column
- rename a TSV column
- reorder TSV columns
- add or remove a stable enum constraint
- add or update a real cross-table reference

Usually do not edit `schema.json` when you only:

- add or modify row data under the existing header
- rewrite long-text values
- reorder rows without changing the header

## Review checklist

Before finishing a schema-aware edit, verify:

- TSV header and `columns[].name` are identical in order
- primary key columns are stable and not `TBD`
- `required` flags still match placeholder usage
- new `enum` values match actual TSV usage
- new `ref` metadata points at real table/column names
- no unrelated schema churn was introduced
