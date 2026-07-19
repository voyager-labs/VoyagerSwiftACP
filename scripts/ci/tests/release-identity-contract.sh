#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CI_DIR="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

released_at="$(python3 - <<'PY'
import datetime as dt
print((dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=1)).strftime("%Y-%m-%dT%H:%M:%SZ"))
PY
)"
identity_path="${WORK_DIR}/release-artifacts/identity/release-identity.env"
VOYAGER_RELEASED_AT="${released_at}" bash "${CI_DIR}/prepare-release-identity.sh" "${identity_path}"
# shellcheck source=/dev/null
source "${identity_path}"
[[ "${VOYAGER_RELEASED_AT}" == "${released_at}" ]]
[[ "${RELEASE_MANIFEST_RELEASED_AT}" == "${released_at}" ]]

if VOYAGER_RELEASED_AT="2026-07-16T12:00:00+09:00" bash "${CI_DIR}/prepare-release-identity.sh" "${WORK_DIR}/invalid.env"; then
  echo "Expected non-UTC release timestamp to fail" >&2
  exit 1
fi

zip_path="${WORK_DIR}/Voyager-0.8.2.zip"
artifact_url="https://downloads.voyager.fm/releases/versions/0.8.2/Voyager-0.8.2.zip"
sparkle_signature="$(python3 - <<'PY'
import base64
print(base64.b64encode(bytes(64)).decode())
PY
)"
cat > "${WORK_DIR}/appcast.xml" <<EOF
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item><enclosure url="${artifact_url}" sparkle:edSignature="${sparkle_signature}" /></item></channel></rss>
EOF
private_key="$(python3 - <<'PY'
import base64
print(base64.b64encode(bytes(range(32))).decode())
PY
)"
wrong_private_key="$(python3 - <<'PY'
import base64
print(base64.b64encode(bytes(range(1, 33))).decode())
PY
)"
cat > "${WORK_DIR}/derive-fixture-public-key.swift" <<'SWIFT'
import CryptoKit
import Foundation

guard let encodedPrivateKey = ProcessInfo.processInfo.environment["SPARKLE_PRIVATE_KEY"],
      let privateKeyData = Data(base64Encoded: encodedPrivateKey)
else {
    fatalError("Missing fixture private key")
}

let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: Data(privateKeyData.prefix(32)))
print(privateKey.publicKey.rawRepresentation.base64EncodedString())
SWIFT
xcrun swiftc "${WORK_DIR}/derive-fixture-public-key.swift" -o "${WORK_DIR}/derive-fixture-public-key"
fixture_public_key="$(SPARKLE_PRIVATE_KEY="${private_key}" "${WORK_DIR}/derive-fixture-public-key")"
xcrun swiftc \
  "${CI_DIR}/../../apps/macos/Packages/06_Shared/VoyagerShared/Sources/VoyagerShared/Model/AppVersionInfo.swift" \
  "${CI_DIR}/../../apps/macos/Packages/06_Shared/VoyagerShared/Sources/VoyagerShared/Model/ReleaseManifest.swift" \
  "${CI_DIR}/release-manifest-verifier/main.swift" \
  -o "${WORK_DIR}/verify-release-manifest-production"
xcrun swiftc \
  -D RELEASE_MANIFEST_VERIFIER_TESTING \
  "${CI_DIR}/../../apps/macos/Packages/06_Shared/VoyagerShared/Sources/VoyagerShared/Model/AppVersionInfo.swift" \
  "${CI_DIR}/../../apps/macos/Packages/06_Shared/VoyagerShared/Sources/VoyagerShared/Model/ReleaseManifest.swift" \
  "${CI_DIR}/release-manifest-verifier/main.swift" \
  -o "${WORK_DIR}/verify-release-manifest-fixture"
mkdir -p "${WORK_DIR}/Voyager.app/Contents"
cat > "${WORK_DIR}/Voyager.app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>VOYAGER_RELEASED_AT</key><string>${released_at}</string></dict></plist>
EOF
(cd "${WORK_DIR}" && /usr/bin/zip -qr "Voyager-0.8.2.zip" "Voyager.app")
SPARKLE_PRIVATE_KEY="${private_key}" python3 "${CI_DIR}/generate-release-manifest.py" \
  "${zip_path}" "${WORK_DIR}/appcast.xml" "${artifact_url}" "0.8.2" "${RELEASE_MANIFEST_RELEASED_AT}" "${WORK_DIR}/release-manifest-v1.json"
python3 - "${WORK_DIR}/release-manifest-v1.json" "${released_at}" <<'PY'
import json
import sys

with open(sys.argv[1]) as source:
    manifest = json.load(source)
assert manifest["released_at"] == sys.argv[2]
assert manifest["schema_version"] == 1
assert manifest["key_id"] == "sparkle-ed25519-v1"
assert list(manifest) == sorted(manifest)
assert len(manifest["signature"]) > 0
PY
if SPARKLE_PRIVATE_KEY="${private_key}" RELEASE_MANIFEST_TEST_PUBLIC_KEY="${fixture_public_key}" \
  "${WORK_DIR}/verify-release-manifest-production" \
  "${WORK_DIR}/release-manifest-v1.json" "${zip_path}" "${WORK_DIR}/appcast.xml" "${artifact_url}" "${released_at}"
then
  echo "Expected production verifier to reject fixture key" >&2
  exit 1
fi

if SPARKLE_PRIVATE_KEY="${wrong_private_key}" RELEASE_MANIFEST_TEST_PUBLIC_KEY="${fixture_public_key}" \
  "${WORK_DIR}/verify-release-manifest-fixture" \
  "${WORK_DIR}/release-manifest-v1.json" "${zip_path}" "${WORK_DIR}/appcast.xml" "${artifact_url}" "${released_at}"
then
  echo "Expected fixture verifier to reject mismatched signing key" >&2
  exit 1
fi

SPARKLE_PRIVATE_KEY="${private_key}" RELEASE_MANIFEST_TEST_PUBLIC_KEY="${fixture_public_key}" \
  "${WORK_DIR}/verify-release-manifest-fixture" \
  "${WORK_DIR}/release-manifest-v1.json" "${zip_path}" "${WORK_DIR}/appcast.xml" "${artifact_url}" "${released_at}"

cp "${zip_path}" "${WORK_DIR}/checksum-mismatch.zip"
printf 'x' >> "${WORK_DIR}/checksum-mismatch.zip"
if SPARKLE_PRIVATE_KEY="${private_key}" RELEASE_MANIFEST_TEST_PUBLIC_KEY="${fixture_public_key}" \
  "${WORK_DIR}/verify-release-manifest-fixture" \
  "${WORK_DIR}/release-manifest-v1.json" "${WORK_DIR}/checksum-mismatch.zip" "${WORK_DIR}/appcast.xml" "${artifact_url}" "${released_at}"
then
  echo "Expected checksum mismatch to fail" >&2
  exit 1
fi

if SPARKLE_PRIVATE_KEY="${private_key}" RELEASE_MANIFEST_TEST_PUBLIC_KEY="${fixture_public_key}" \
  "${WORK_DIR}/verify-release-manifest-fixture" \
  "${WORK_DIR}/release-manifest-v1.json" "${zip_path}" "${WORK_DIR}/appcast.xml" "${artifact_url}" "1970-01-01T00:00:00Z"
then
  echo "Expected bundle timestamp mismatch to fail" >&2
  exit 1
fi

cp "${WORK_DIR}/appcast.xml" "${WORK_DIR}/signature-mismatch-appcast.xml"
python3 - "${WORK_DIR}/signature-mismatch-appcast.xml" <<'PY'
import sys

path = sys.argv[1]
with open(path) as source:
    content = source.read()
with open(path, "w") as destination:
    destination.write(content.replace('edSignature="', 'edSignature="x', 1))
PY
if SPARKLE_PRIVATE_KEY="${private_key}" RELEASE_MANIFEST_TEST_PUBLIC_KEY="${fixture_public_key}" \
  "${WORK_DIR}/verify-release-manifest-fixture" \
  "${WORK_DIR}/release-manifest-v1.json" "${zip_path}" "${WORK_DIR}/signature-mismatch-appcast.xml" "${artifact_url}" "${released_at}"
then
  echo "Expected Sparkle signature mismatch to fail" >&2
  exit 1
fi

TAG=v0.8.2 bash "${CI_DIR}/release-macos-prod.sh" fetch-baseline

if TAG=v0.8.1 bash "${CI_DIR}/release-macos-prod.sh" fetch-baseline; then
  echo "Expected pre-v0.8.2 release to fail" >&2
  exit 1
fi

if TAG=0.8.2 bash "${CI_DIR}/release-macos-prod.sh" fetch-baseline; then
  echo "Expected malformed tag to fail" >&2
  exit 1
fi
