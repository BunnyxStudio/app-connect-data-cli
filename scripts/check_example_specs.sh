#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

ADC_BIN="${ADC_BIN:-${REPO_ROOT}/.build/debug/adc}"
if [[ ! -x "${ADC_BIN}" ]]; then
  ADC_BIN="$(swift build --show-bin-path)/adc"
fi

RUN_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/adc-example-specs.XXXXXX")"
HOME_DIR="${RUN_ROOT}/home"
WORKDIR="${RUN_ROOT}/workdir"
trap 'rm -rf "${RUN_ROOT}"' EXIT

mkdir -p "${HOME_DIR}" "${WORKDIR}"
chmod 700 "${HOME_DIR}" "${WORKDIR}"

for spec in examples/queries/*.json; do
  echo "Checking ${spec}"
  (
    cd "${WORKDIR}"
    HOME="${HOME_DIR}" "${ADC_BIN}" query run --spec "${REPO_ROOT}/${spec}" --offline --output json >/dev/null
  )
done

echo "All example specs passed."
