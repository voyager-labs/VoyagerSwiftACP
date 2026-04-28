#!/usr/bin/env bash
set -euo pipefail

TAG="${1:-${TAG:-${GITHUB_REF_NAME:-}}}"
if [[ -z "${TAG}" ]]; then
  echo "Missing tag name." >&2
  exit 1
fi
if [[ ! "${TAG}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]]; then
  echo "Expected semantic version like v1.2.3 or v1.2.3-beta.1, got: ${TAG}" >&2
  exit 1
fi

VERSION="${TAG#v}"

if [[ -n "${GITHUB_ENV:-}" ]]; then
  echo "VERSION=${VERSION}" >> "${GITHUB_ENV}"
  echo "TAG=${TAG}" >> "${GITHUB_ENV}"
fi

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "version=${VERSION}" >> "${GITHUB_OUTPUT}"
fi

