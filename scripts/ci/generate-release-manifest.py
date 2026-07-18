#!/usr/bin/env python3
import base64
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as element_tree
from pathlib import Path

KEY_ID = "sparkle-ed25519-v1"
SCHEMA_VERSION = 1


def fail(message: str) -> None:
    raise SystemExit(message)


def sparkle_signature(appcast_path: Path, artifact_url: str) -> str:
    root = element_tree.parse(appcast_path).getroot()
    signature_key = "{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature"
    for enclosure in root.findall(".//enclosure"):
        if enclosure.attrib.get("url") == artifact_url:
            signature = enclosure.attrib.get(signature_key)
            if signature and len(base64.b64decode(signature, validate=True)) == 64:
                return signature
    fail(f"No Sparkle Ed25519 signature for artifact: {artifact_url}")


def main() -> None:
    if len(sys.argv) != 7:
        fail("Usage: generate-release-manifest.py <zip> <appcast> <artifact-url> <version> <released-at> <out>")

    zip_path = Path(sys.argv[1])
    appcast_path = Path(sys.argv[2])
    artifact_url = sys.argv[3]
    version = sys.argv[4]
    released_at = sys.argv[5]
    out_path = Path(sys.argv[6])
    if not zip_path.is_file() or not appcast_path.is_file():
        fail("Release ZIP and appcast must exist")

    payload = {
        "artifact": {
            "sha256": hashlib.sha256(zip_path.read_bytes()).hexdigest(),
            "size_bytes": zip_path.stat().st_size,
            "sparkle_ed25519_signature": sparkle_signature(appcast_path, artifact_url),
            "url": artifact_url,
        },
        "key_id": KEY_ID,
        "released_at": released_at,
        "schema_version": SCHEMA_VERSION,
        "version": version,
    }
    canonical_payload = json.dumps(payload, separators=(",", ":"), sort_keys=True).encode("utf-8")
    with tempfile.TemporaryDirectory() as temporary_directory:
        signer_path = Path(temporary_directory) / "release-manifest-sign"
        subprocess.run(
            [
                "xcrun",
                "swiftc",
                str(Path(__file__).with_name("release-manifest-sign.swift")),
                "-o",
                str(signer_path),
            ],
            check=True,
            env=os.environ,
        )
        signature = subprocess.run(
            [str(signer_path)],
            input=canonical_payload,
            check=True,
            env=os.environ,
            stdout=subprocess.PIPE,
        ).stdout.decode("utf-8").strip()
    if len(base64.b64decode(signature, validate=True)) != 64:
        fail("Manifest signature must be an Ed25519 signature")

    manifest = {**payload, "signature": signature}
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_bytes(json.dumps(manifest, separators=(",", ":"), sort_keys=True).encode("utf-8"))


if __name__ == "__main__":
    main()
