# VoyagerSwiftACP upstream and subtree policy

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

For app-to-fork push-back, preserve subtree ancestry and avoid squashed imports:

```bash
git subtree pull --prefix=apps/macos/Packages/VoyagerSwiftACP voyager-swift-acp <branch>
git subtree push --prefix=apps/macos/Packages/VoyagerSwiftACP voyager-swift-acp <branch>
```

Run package tests in the fork and app integration tests before publishing or updating the fork's default branch.