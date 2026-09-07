# Repository Guidance

## Release Workflow

- Before a release, refresh the branch state with `git status --short --branch`, confirm the target branch is `main`, and check existing tags/releases with `git tag --sort=-v:refname`, `git ls-remote --tags origin`, and `gh release list --repo wiedymi/swift-acp --limit 20`.
- Validate the final tree before tagging. At minimum run `git diff --check` and `swift test`.
- Commit all release changes together when the user asks to release. Include source, tests, docs, and updated reference submodule pointers in the same release commit when they are part of the same upstream sync.
- Push the release commit to `origin main` before creating the release tag.
- Use semantic version tags prefixed with `v`. If there are no existing tags, start at `v0.1.0`; otherwise increment the most appropriate component for the release scope.
- Create an annotated git tag from the pushed commit, then push the tag:
  - `git tag -a vX.Y.Z -m "vX.Y.Z"`
  - `git push origin vX.Y.Z`
- Publish a GitHub release with `gh release create`, using the tag as both the tag and title.
- Include a changelog in the release notes. Summarize user-visible changes, compatibility notes, refreshed upstream references, and validation performed.
- After publishing, verify the release exists with `gh release view vX.Y.Z --repo wiedymi/swift-acp`.
