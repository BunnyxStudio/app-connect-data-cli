#!/usr/bin/env bash
set -u -o pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ADC_BIN="${ADC_BIN:-$REPO_ROOT/.build/arm64-apple-macosx/release/adc}"
RUN_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/adc-full-smoke.XXXXXX")"
WORKDIR="$RUN_ROOT/workdir"
LOG_DIR="$RUN_ROOT/logs"
CONFIG_DIR="$WORKDIR/.app-connect-data-cli"
PASS_COUNT=0
FAIL_COUNT=0
declare -a FAILED_CASES=()

mkdir -p "$WORKDIR" "$LOG_DIR" "$CONFIG_DIR"
chmod 700 "$CONFIG_DIR"

prepare_config() {
  local user_config="$HOME/.app-connect-data-cli/config.json"

if [[ -f "$user_config" ]]; then
    install -m 600 "$user_config" "$CONFIG_DIR/config.json"
    return
  fi

  if [[ -n "${ASC_ISSUER_ID:-}" && -n "${ASC_KEY_ID:-}" && -n "${ASC_VENDOR_NUMBER:-}" && -n "${ASC_P8_PATH:-}" ]]; then
    python3 - "$CONFIG_DIR/config.json" <<'PY'
import json
import os
import sys

path = sys.argv[1]
payload = {
    "issuerID": os.environ["ASC_ISSUER_ID"],
    "keyID": os.environ["ASC_KEY_ID"],
    "vendorNumber": os.environ["ASC_VENDOR_NUMBER"],
    "p8Path": os.environ["ASC_P8_PATH"],
}
with open(path, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, indent=2)
    handle.write("\n")
os.chmod(path, 0o600)
PY
    return
  fi

  echo "Missing credentials. Expected ~/.app-connect-data-cli/config.json or ASC_* environment variables." >&2
  exit 1
}

build_binary() {
  swift build -c release >/dev/null
  ADC_BIN="$(swift build -c release --show-bin-path)/adc"
}

validate_json() {
  local file="$1"
  shift
  python3 - "$file" "$@" <<'PY'
import json
import sys

path = sys.argv[1]
checks = {}
for arg in sys.argv[2:]:
    key, value = arg.split("=", 1)
    checks[key] = value

with open(path, "r", encoding="utf-8") as handle:
    payload = json.load(handle)

expected_type = checks.pop("type", None)
if expected_type == "object" and not isinstance(payload, dict):
    raise SystemExit("expected JSON object")
if expected_type == "array" and not isinstance(payload, list):
    raise SystemExit("expected JSON array")

if "status" in checks and payload.get("status") != checks["status"]:
    raise SystemExit(f"expected status={checks['status']}, got {payload.get('status')}")
if "dataset" in checks and payload.get("dataset") != checks["dataset"]:
    raise SystemExit(f"expected dataset={checks['dataset']}, got {payload.get('dataset')}")
if "operation" in checks and payload.get("operation") != checks["operation"]:
    raise SystemExit(f"expected operation={checks['operation']}, got {payload.get('operation')}")
if "title" in checks and payload.get("title") != checks["title"]:
    raise SystemExit(f"expected title={checks['title']}, got {payload.get('title')}")
if "min_len" in checks:
    if not isinstance(payload, list) or len(payload) < int(checks["min_len"]):
        raise SystemExit(f"expected array length >= {checks['min_len']}")
if "contains_names" in checks:
    if not isinstance(payload, list):
        raise SystemExit("contains_names requires JSON array")
    actual = {item.get("name") for item in payload if isinstance(item, dict)}
    required = {name for name in checks["contains_names"].split(",") if name}
    missing = sorted(required - actual)
    if missing:
        raise SystemExit(f"missing names: {', '.join(missing)}")
PY
}

record_pass() {
  local name="$1"
  PASS_COUNT=$((PASS_COUNT + 1))
  printf 'PASS %s\n' "$name"
}

record_fail() {
  local name="$1"
  local reason="$2"
  FAIL_COUNT=$((FAIL_COUNT + 1))
  FAILED_CASES+=("$name")
  printf 'FAIL %s: %s\n' "$name" "$reason"
}

run_text_case() {
  local name="$1"
  local pattern="$2"
  shift 2
  local stdout_file="$LOG_DIR/${name}.stdout"
  local stderr_file="$LOG_DIR/${name}.stderr"

  if (cd "$WORKDIR" && "$@") >"$stdout_file" 2>"$stderr_file"; then
    if grep -q "$pattern" "$stdout_file"; then
      record_pass "$name"
    else
      record_fail "$name" "output missing pattern: $pattern"
    fi
  else
    record_fail "$name" "command exited non-zero"
  fi
}

run_json_case() {
  local name="$1"
  shift
  local validator=()
  while [[ $# -gt 0 && "$1" == *=* ]]; do
    validator+=("$1")
    shift
  done

  local stdout_file="$LOG_DIR/${name}.stdout"
  local stderr_file="$LOG_DIR/${name}.stderr"

  if (cd "$WORKDIR" && "$@") >"$stdout_file" 2>"$stderr_file"; then
    if validate_json "$stdout_file" "${validator[@]}"; then
      record_pass "$name"
    else
      record_fail "$name" "JSON validation failed"
    fi
  else
    record_fail "$name" "command exited non-zero"
  fi
}

prepare_config
build_binary

SPEC_FILE="$RUN_ROOT/query-spec.json"
cat >"$SPEC_FILE" <<'JSON'
{
  "dataset": "sales",
  "operation": "aggregate",
  "time": {
    "rangePreset": "last-7d"
  },
  "filters": {
    "sourceReport": ["summary-sales"]
  },
  "groupBy": ["territory"]
}
JSON

BRIEF_SPEC_FILE="$RUN_ROOT/brief-spec.json"
cat >"$BRIEF_SPEC_FILE" <<'JSON'
{
  "dataset": "brief",
  "operation": "brief",
  "time": {
    "rangePreset": "this-week"
  }
}
JSON

run_text_case help_root USAGE: "$ADC_BIN" --help
for cmd in auth config capabilities overview sales reviews finance analytics brief query cache; do
  run_text_case "help_${cmd}" USAGE: "$ADC_BIN" "$cmd" --help
done

run_json_case auth_validate type=object status=ok "$ADC_BIN" auth validate --output json
run_json_case capabilities_list type=array min_len=4 contains_names=sales,reviews,finance,analytics "$ADC_BIN" capabilities list --output json
run_json_case config_timezone_show type=object "$ADC_BIN" config timezone show --output json

run_json_case sales_records type=object dataset=sales operation=records "$ADC_BIN" sales records --range last-7d --limit 5 --output json
run_json_case sales_aggregate type=object dataset=sales operation=aggregate "$ADC_BIN" sales aggregate --range last-7d --group-by territory --output json
run_json_case sales_compare type=object dataset=sales operation=compare "$ADC_BIN" sales compare --range last-7d --compare previous-period --output json

run_json_case reviews_records type=object dataset=reviews operation=records "$ADC_BIN" reviews records --range last-7d --limit 5 --output json
run_json_case reviews_aggregate type=object dataset=reviews operation=aggregate "$ADC_BIN" reviews aggregate --range last-7d --group-by rating --output json
run_json_case reviews_compare type=object dataset=reviews operation=compare "$ADC_BIN" reviews compare --range last-7d --compare previous-period --output json

run_json_case finance_records type=object dataset=finance operation=records "$ADC_BIN" finance records --range last-month --limit 5 --output json
run_json_case finance_aggregate type=object dataset=finance operation=aggregate "$ADC_BIN" finance aggregate --range last-month --group-by territory --group-by currency --output json
run_json_case finance_compare type=object dataset=finance operation=compare "$ADC_BIN" finance compare --range last-month --compare month-over-month --output json

analytics_records_cmd=("$ADC_BIN" analytics records --range last-7d --source-report usage --limit 5 --output json)
analytics_aggregate_cmd=("$ADC_BIN" analytics aggregate --range last-7d --source-report usage --group-by app --output json)
analytics_compare_cmd=("$ADC_BIN" analytics compare --range last-7d --source-report usage --compare previous-period --output json)

if [[ -n "${ADC_TEST_APP:-}" ]]; then
  analytics_records_cmd+=(--app "$ADC_TEST_APP")
  analytics_aggregate_cmd+=(--app "$ADC_TEST_APP")
  analytics_compare_cmd+=(--app "$ADC_TEST_APP")
fi

run_json_case analytics_records type=object dataset=analytics operation=records "${analytics_records_cmd[@]}"
run_json_case analytics_aggregate type=object dataset=analytics operation=aggregate "${analytics_aggregate_cmd[@]}"
run_json_case analytics_compare type=object dataset=analytics operation=compare "${analytics_compare_cmd[@]}"

run_json_case brief_daily type=object title="Daily Summary" "$ADC_BIN" brief daily --output json
run_json_case brief_weekly type=object title="Week to Date Summary" "$ADC_BIN" brief weekly --output json
run_json_case brief_monthly type=object title="Month to Date Summary" "$ADC_BIN" brief monthly --output json
run_json_case brief_last7d type=object title="Last 7 Days Summary" "$ADC_BIN" brief last-7d --output json
run_json_case brief_last30d type=object title="Last 30 Days Summary" "$ADC_BIN" brief last-30d --output json
run_json_case brief_lastmonth type=object title="Last Month Summary" "$ADC_BIN" brief last-month --output json
run_json_case overview_daily type=object title="Daily Summary" "$ADC_BIN" overview daily --output json

run_json_case query_run type=object dataset=sales operation=aggregate "$ADC_BIN" query run --spec "$SPEC_FILE" --output json
run_json_case query_run_brief type=object title="Week to Date Summary" "$ADC_BIN" query run --spec "$BRIEF_SPEC_FILE" --output json
run_json_case cache_clear type=object status=cleared "$ADC_BIN" cache clear --output json

printf '\nSummary: %d passed, %d failed\n' "$PASS_COUNT" "$FAIL_COUNT"
printf 'Logs: %s\n' "$LOG_DIR"

if [[ $FAIL_COUNT -ne 0 ]]; then
  printf 'Failed cases: %s\n' "${FAILED_CASES[*]}"
  exit 1
fi
