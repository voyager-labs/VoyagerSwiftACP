# Repository Guidance

This subtree is the vendored `VoyagerSwiftACP` package. Its distribution line is the
Voyager-owned fork `voyager-labs/VoyagerSwiftACP`, whose long-lived release branch is
`production`. `main` on the fork is the upstream-compatible mirror of
`wiedymi/swift-acp` and is never a release target. See
`.agents/skills/acp-fork-subtree-workflow/SKILL.md` in the app repository for the
full boundary.

## Release Workflow

- Before a release, refresh the branch state with `git status --short --branch`, confirm the target branch is `production` on `voyager-labs/VoyagerSwiftACP`, and check existing tags/releases with `git tag --sort=-v:refname`, `git ls-remote --tags origin`, and `gh release list --repo voyager-labs/VoyagerSwiftACP --limit 20`.
- Land verified changes on `production` first (feature branches merge into `production`, never directly into `main`), then tag from `production`.
- Validate the final tree before tagging. At minimum run `git diff --check` and `swift test` from both the fork checkout and this app subtree path.
- Commit all release changes together when the user asks to release. Include source, tests, docs, and updated reference submodule pointers in the same release commit when they are part of the same upstream sync.
- Push the release commit to `origin production` before creating the release tag.
- Use semantic version tags prefixed with `v`. If there are no existing tags, start at `v0.1.0`; otherwise increment the most appropriate component for the release scope.
- Create an annotated git tag from the pushed commit, then push the tag:
  - `git tag -a vX.Y.Z -m "vX.Y.Z"`
  - `git push origin vX.Y.Z`
- Publish a GitHub release with `gh release create --repo voyager-labs/VoyagerSwiftACP`, using the tag as both the tag and title.
- Include a changelog in the release notes. Summarize user-visible changes, compatibility notes, refreshed upstream references, and validation performed.
- After publishing, verify the release exists with `gh release view vX.Y.Z --repo voyager-labs/VoyagerSwiftACP`.
