# VoyagerSwiftACP upstream and subtree policy

## Branch policy

- `main` is the upstream-compatible mirror line. Keep it close to `wiedymi/swift-acp/main`; do not use it as the app's moving integration source.
- `production` is the long-lived Voyager distribution line. It contains only reviewed Voyager compatibility/vendoring patches on top of the upstream baseline and is the branch consumed by `voyager-app`.
- `feature/*` branches are temporary issue/review branches. Merge verified work into `production`, then delete the feature branch when no longer needed.
- ACP protocol experiments such as upstream `feature/acp-v2` remain separate until explicitly promoted through review and conformance testing.

## Upstream

- Upstream repository: `https://github.com/wiedymi/swift-acp.git`
- Voyager fork: `https://github.com/voyager-labs/VoyagerSwiftACP.git`
- ACP protocol reference: `https://agentclientprotocol.com/protocol/v1/overview`

## Repository roles

- The fork contains the maintained Swift ACP package and Voyager-specific compatibility patches.
- The Voyager app consumes the fork under `apps/macos/Packages/VoyagerSwiftACP/` as a Git subtree.
- `05_Entities/Ai/VoyagerACPClient` owns Voyager-specific provider and Runtime mapping; this package owns only generic ACP client/transport behavior.

## Vendoring policy

- The `reference/` upstream documentation/SDK submodules are intentionally not vendored into the app subtree. They are not required to build or test the Swift package and would create nested submodule checkout requirements in `voyager-app`.
- Package source and tests remain in the subtree. Any change to the vendored source is made in the app integration PR, validated there, and then pushed back to this fork through the documented subtree sync flow.
- Record the upstream revision, Voyager patch commits, subtree import/sync commit, and focused `swift test` result for each update.
- Do not store credentials, provider auth material, customer payloads, or Voyager-private product code in this public repository.

## Two-way subtree sync

For app-to-fork push-back, preserve subtree ancestry and avoid squashed imports.
The app worktree has no `voyager-swift-acp` remote alias; use the fork URL directly:

1. Validate the app subtree and its app consumer.
2. Export package-only changes to a temporary fork review branch:

    ```bash
    git subtree push --prefix=apps/macos/Packages/VoyagerSwiftACP git@github.com:voyager-labs/VoyagerSwiftACP.git feature/voy-886
    ```

3. In the independent fork, run package/strict-concurrency checks and review the
   candidate against `production`. Merge the reviewed candidate into `production`.
4. Pull the confirmed production revision back into the app without squashing:

    ```bash
    git subtree pull --prefix=apps/macos/Packages/VoyagerSwiftACP git@github.com:voyager-labs/VoyagerSwiftACP.git production
    ```

5. Check merge parents, the imported package tree, and app consumer verification.
   Record the fork production SHA and app sync commit. Retire the review branch
   only after production reachability is confirmed.

Do not push an unreviewed candidate directly to `production`. These commands are
the promotion procedure, not evidence that the candidate has already been promoted.

## Upstream-compatible behavior changes (VOY-886)

The VOY-886 candidate intentionally diverges from upstream `main` in the areas below.
These patches require review and promotion before they are available on `production`.
Upstream leniency conflicts with strict ACP v1 conformance; every change is
covered by the conformance suites in `docs/CONFORMANCE.md`:

| Area                  | Upstream behavior                                                          | Voyager `production` behavior                                                                   |
| --------------------- | -------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| JSON-RPC envelope     | Malformed `id` demoted to notification; `jsonrpc` version accepted loosely | Strict `"2.0"` envelope; malformed `id` rejected; null-id messages remain requests              |
| `protocolVersion`     | Coerced strings/null/bool to `1`                                           | Integer `0...65535` only; unsupported versions fail initialization                              |
| Client capabilities   | `fs`/`terminal` required on decode                                         | Omitted capabilities default to "not supported"; wrong types rejected                           |
| stdio framing         | Non-JSON stdout discarded and resynchronized                               | LF-delimited strict framing; malformed/oversized frames fail the connection with typed evidence |
| Params shape          | `params: null` tolerated on requests                                       | `params` must be omitted, an object, or an array                                                |
| `AnyCodable` encoding | Unsupported values silently encoded as `null`                              | Unsupported values throw `EncodingError`                                                        |
| Subprocess lifecycle  | `terminate()` did not await child exit                                     | Bounded shutdown (TERM 2s → KILL 1s) with immutable `TransportTermination` evidence             |
| Process registry      | Automatic disk registry writes on launch                                   | Removed from the default path; `ProcessRegistry` remains an opt-in utility                      |
| Request correlation   | Timeout task group could leave continuations unsettled                     | Single-completion pending table; deadline tasks settle at the actual deadline                   |
| Debug stream          | `DebugMessage.rawData` exposed raw wire bytes                              | Metadata-only by default; compatibility rawData/jsonString expose sanitizer output only         |
| Agent ingress         | Request handlers awaited inline, blocking cancel processing                | Handlers run in tracked tasks; `-32601/-32602/-32603` error mapping per JSON-RPC                |
| Swift language mode   | tools 5.9, Swift 5 mode                                                    | tools 6.0, Swift 6 language mode with strict concurrency                                        |

## Candidate provenance

- Upstream source baseline: `9498537769d1309b6519fbb87d0c22fcf9317f3e`.
- Fork production baseline: `3097d3b9e8f3192c70a41ad180ead063f0448ae0`.
- App imports preserve the fork commits as merge parents (non-squashed).
- The candidate adds strict wire validation, transport injection, bounded queues,
  request/session lifecycle handling, Swift 6 isolation, and offline fixtures.
- CI package/consumer jobs, API comparison, fork production promotion, and the
  subsequent app subtree sync remain separate promotion gates. Local checks do
  not constitute evidence that those remote gates have run.
