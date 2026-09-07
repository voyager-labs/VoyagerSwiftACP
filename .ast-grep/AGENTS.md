# ast-grep Lint Rules

Use the version pinned in `mise.toml`. Rule severity is owned by each YAML file;
never describe all rules as warnings or swallow a scan failure with `|| true`.

## Execution owner

`python3 -m scripts.run_swift_checks --staged` is the read-only hook entrypoint.
It exports the Git index, reads code and rule/config files from that snapshot,
passes paths as argv (NUL-delimited Git discovery), and retains every failure.
`--base-ref <ref>` reads HEAD content; `--working-tree` inspects local edits;
`--all` selects tracked sources. These scopes must not be represented as equal.
Changes to a rule/config expand the affected engine to all tracked Swift sources.
No source change means notApplicable, not evidence that a tool was run.

`--checks ast`, `--checks format`, and `--checks lint` select explicit stages.
A partial-stage receipt does not prove compilation, native tests, or unselected
stages. Missing tools/inputs/timeouts are blocked and return non-zero.

## Rule scopes

- `model/`, `reducer/`, `common/`: production Swift files, including Ui sources.
- `ui/`: production Swift files inside a `Ui/` path component.
- Test files: SwiftFormat and the test SwiftLint config; production AST policies
  do not apply to fixture definitions. Rule fixture code is tested separately.
- Unknown rule directories fail closed until the runner has an explicit scope.

## Severity and proof limits

Macro misuse and forbidden external access are errors. Inline State/Action,
missing model aliases and case-path annotations are architectural review signals:
small local reducers and opaque struct Actions are legitimate. Do not weaken an
error solely to pass an unrelated edit. Promote a policy to an error only after
its applicability is explicit and its valid/invalid corpus passes.

The Coordinator allowance for native observation is syntactic. It does not prove
that a callback is geometry-only or that cleanup is correct. Reducer-owned domain
observation stays behind clients; native bounds/frame observation can remain in
the adapter with mount/unmount and late-callback tests. Do not wrap scroll events
in new dependency clients solely to appease this lint rule.

## Adding/changing rules

1. Define applicability, severity, rationale and allowed cases.
2. Add valid, invalid and bypass/descendant cases in `.ast-grep/rule-tests/`.
3. Run `mise exec -- ast-grep test --skip-snapshot-tests` (match/no-match corpus).
4. Run `python3 -m scripts.run_swift_checks --all --checks ast` and inspect impact.
5. Keep all source and fixture failures visible. Regex/AST matching is not a
   type checker or a complete single-writer/cancellation proof.

`sgconfig.yml` contains only directories that actually exist. The PR workflow
runs the same pinned ast-grep release through npm as a Linux installation adapter;
it does not install a second repository dependency or change the version policy.
