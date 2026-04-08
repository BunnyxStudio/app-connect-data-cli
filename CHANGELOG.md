# Changelog

## Unreleased

- Added explicit platform requirements in `README.md`.
- Clarified that `scripts/full_cli_smoke.sh` requires real credentials and network access.
- Added `scripts/check_version_consistency.sh` and wired it into CI.
- Standardized community-facing docs to English (`SUPPORT.md`, `CODE_OF_CONDUCT.md`).

## 0.1.7 - 2026-04-08

- Added `adc --version` output for easier issue triage and Homebrew diagnostics.
- `sales|reviews|finance|analytics aggregate` no longer accepts `--compare*` options that had no effect.
- Added filter capability validation in query execution; unsupported filters now fail explicitly.
- Fixed `reviews` `rating` / `response-state` filters not being applied.
- Added compare parameter constraints in `query run`:
  - `compare` / `compareTime` are only allowed when `operation=compare`.
  - `compareTime` requires `compare=custom`.

## 0.1.6 - 2026-04-08

- Fixed a concurrency crash in `brief` / `overview` by replacing `async let` with `TaskGroup` in summary queries.
- Changed warm-up behavior for `brief` / `overview`: ensure `summary-sales` first, then fetch subscription reports best-effort with graceful downgrade.

## 0.1.5 - 2026-04-08

- Fixed `brief` / `overview` crashes in some environments (`freed pointer was not the last allocation`).
- Switched summary building to a stability-first execution path to avoid runtime memory errors under high concurrency.
- Fixed Homebrew tap audit by removing a redundant `version` field and restoring bottle automation.

## 0.1.4 - 2026-04-08

- Fixed a `DateFormatter` thread-safety issue that could crash `brief` / `overview` in concurrent execution.
- Added automated Homebrew release wiring for maintainers:
  - Publish a release in this repo -> open a formula bump PR in `homebrew-tap`.
  - Tap repo auto-labels successful `brew test-bot` PRs with `pr-pull`.

## 0.1.3 - 2026-04-08

- Added validation for `source-report` input and propagated report-not-ready warnings.
- When subscription reports return `Invalid vendor number specified`, `brief` / `overview` now fall back to `summary-sales` automatically.

## 0.1.2 - 2026-04-07

- Corrected `SALES/SUMMARY/DAILY` request version to `1_0`.
- Avoided `Invalid vendor number specified` errors for some accounts on `brief daily` / `overview daily`.

## 0.1.1 - 2026-04-07

- Updated project display name to `App Store Connect Data CLI`.
- Updated repository slug to `app-store-connect-data-cli`.
- Kept stable identifiers `adc` and `.app-connect-data-cli` for local paths.
- Updated README, CONTRIBUTING, NOTICE, and Homebrew wording.
- Corrected the local debugging command in CONTRIBUTING to `./.build/debug/adc --help`.

## 0.1.0 - 2026-04-07

- Initialized the open-source repository layout.
- Extracted `ACDCore`.
- Added `ACDAnalytics`.
- Added `App Store Connect Data CLI`.
- Added support for `auth / sync / query / reviews / doctor / cache`.
- Added JSON-first `query run --spec`.
- Renamed repository slug to `app-connect-data-cli`.
- Switched CLI behavior to direct-query first.
- Added `--date` / `--from` / `--to` / `--range`.
- `query` and `reviews` now fetch on demand when credentials are available.
- Demoted `sync` to an advanced warm-up entrypoint.
- Changed license from MIT to Apache-2.0 and added attribution requirements in `NOTICE`.
- Added multi-table `brief` / `overview` summaries.
- Added Homebrew tap installation support.
