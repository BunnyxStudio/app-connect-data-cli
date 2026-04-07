#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/release_homebrew.sh <version> [tap_path]

Examples:
  scripts/release_homebrew.sh 0.1.1
  scripts/release_homebrew.sh 0.1.1 /opt/homebrew/Library/Taps/bunnyxstudio/homebrew-tap
EOF
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage
  exit 1
fi

VERSION="$1"
TAP_PATH="${2:-/opt/homebrew/Library/Taps/bunnyxstudio/homebrew-tap}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAG="v${VERSION}"
TARBALL_URL="https://github.com/BunnyxStudio/app-connect-data-cli/archive/refs/tags/${TAG}.tar.gz"
REPO_FORMULA="${REPO_ROOT}/Formula/adc.rb"
TAP_FORMULA="${TAP_PATH}/Formula/adc.rb"

if [[ ! -f "${REPO_ROOT}/Package.swift" ]]; then
  echo "Repository root is invalid: ${REPO_ROOT}" >&2
  exit 1
fi

if [[ ! -f "${REPO_FORMULA}" ]]; then
  echo "Missing repo formula: ${REPO_FORMULA}" >&2
  exit 1
fi

if [[ ! -f "${TAP_FORMULA}" ]]; then
  echo "Missing tap formula: ${TAP_FORMULA}" >&2
  exit 1
fi

if ! git -C "${REPO_ROOT}" rev-parse -q --verify "refs/tags/${TAG}" >/dev/null; then
  echo "Local tag not found: ${TAG}" >&2
  exit 1
fi

if ! git -C "${REPO_ROOT}" ls-remote --exit-code --tags origin "refs/tags/${TAG}" >/dev/null 2>&1; then
  echo "Remote tag not found on origin: ${TAG}" >&2
  exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

ARCHIVE_PATH="${TMP_DIR}/source.tar.gz"
curl -fsSL "${TARBALL_URL}" -o "${ARCHIVE_PATH}"
SHA256="$(shasum -a 256 "${ARCHIVE_PATH}" | awk '{print $1}')"

python3 - "${VERSION}" "${SHA256}" "${TARBALL_URL}" "${REPO_FORMULA}" "${TAP_FORMULA}" <<'PY'
import re
import sys
from pathlib import Path

version, sha256, url, *paths = sys.argv[1:]

for raw_path in paths:
    path = Path(raw_path)
    text = path.read_text()

    text, url_count = re.subn(
        r'^  url ".*"$',
        f'  url "{url}"',
        text,
        count=1,
        flags=re.MULTILINE,
    )
    text, version_count = re.subn(
        r'^  version ".*"$',
        f'  version "{version}"',
        text,
        count=1,
        flags=re.MULTILINE,
    )
    text, sha_count = re.subn(
        r'^  sha256 ".*"$',
        f'  sha256 "{sha256}"',
        text,
        count=1,
        flags=re.MULTILINE,
    )

    if url_count != 1 or version_count != 1 or sha_count != 1:
        raise SystemExit(f"Formula update failed: {path}")

    path.write_text(text)
    print(f"Updated {path}")
PY

HOMEBREW_NO_AUTO_UPDATE=1 brew reinstall BunnyxStudio/tap/adc
brew test BunnyxStudio/tap/adc
adc capabilities list --output json >/dev/null

echo "Updated formula to ${VERSION}"
echo "Tarball: ${TARBALL_URL}"
echo "SHA256: ${SHA256}"
