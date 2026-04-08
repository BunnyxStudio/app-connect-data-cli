#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

extract_cli_version() {
  sed -n 's/^private let adcVersion = "\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)"$/\1/p' \
    Sources/ACDCLI/Commands/ACDCommand.swift
}

extract_formula_version() {
  sed -n 's#^  url "https://github.com/BunnyxStudio/app-store-connect-data-cli/archive/refs/tags/v\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)\.tar\.gz"$#\1#p' \
    Formula/adc.rb
}

extract_changelog_latest_version() {
  sed -n 's/^## \([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\) - .*/\1/p' CHANGELOG.md | head -n 1
}

CLI_VERSION="$(extract_cli_version)"
FORMULA_VERSION="$(extract_formula_version)"
CHANGELOG_VERSION="$(extract_changelog_latest_version)"

if [[ -z "${CLI_VERSION}" ]]; then
  echo "Unable to parse CLI version from Sources/ACDCLI/Commands/ACDCommand.swift" >&2
  exit 1
fi

if [[ -z "${FORMULA_VERSION}" ]]; then
  echo "Unable to parse formula version from Formula/adc.rb" >&2
  exit 1
fi

if [[ -z "${CHANGELOG_VERSION}" ]]; then
  echo "Unable to parse latest released version from CHANGELOG.md" >&2
  exit 1
fi

if [[ "${CLI_VERSION}" != "${FORMULA_VERSION}" || "${CLI_VERSION}" != "${CHANGELOG_VERSION}" ]]; then
  echo "Version mismatch detected:" >&2
  echo "  CLI:       ${CLI_VERSION}" >&2
  echo "  Formula:   ${FORMULA_VERSION}" >&2
  echo "  Changelog: ${CHANGELOG_VERSION}" >&2
  exit 1
fi

echo "Version check passed: ${CLI_VERSION}"
