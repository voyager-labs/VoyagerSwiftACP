# `codegraph_explore` Query Guide

## Query design

| Goal            | Query shape                          |
| --------------- | ------------------------------------ |
| Definition      | Exact symbol or file name            |
| Callers/callees | `Who calls X?` / `What does X call?` |
| Flow            | `A B call path`                      |
| Impact          | `impact of changing X`               |
| Module context  | Bag of related symbols and files     |

Use `maxFiles` when the expected surface is broad. Use `projectPath` only when querying a second indexed workspace.

## Response handling

- Source blocks are current Read-equivalent context.
- Call-path and blast-radius sections are structural guidance, not compiler proof.
- A pending-index banner names the only files that require direct rereading.
- If auto-sync is disabled, direct reads are required for files that may have changed.
- If no index exists, stop CodeGraph calls for that project and use repository tools.

## Fallbacks

- Structural syntax search: load the OMO `ast-grep` skill.
- Exact semantic rename: LSP prepare/rename.
- Text, comments, or strings: grep.
- Compile and runtime behavior: owning build/test executor.
