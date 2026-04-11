# Changelog

## Unreleased

## 0.1.9 - 2026-04-11

- Fixed online `compare` queries for sales, finance, and analytics so both the current and comparison windows fetch fresh data instead of mixing fresh rows with stale cache.
- Fixed online query freshness rules so `sales`, `finance`, and `analytics` no longer silently fall back to older cached files when Apple has not returned fresh data yet.
- Fixed sales source-report handling:
  - `summary-sales` remains the default.
  - mixed sales families in `aggregate` and `compare` now fail fast unless grouped by `sourceReport` or `reportType`.
  - full-month summary queries fall back to cached daily rows when monthly rows are not available yet.
- Fixed finance source-report handling:
  - `financial` is now the default when `sourceReport` is omitted.
  - mixed `financial` and `finance-detail` aggregate/compare queries now fail fast unless grouped by `sourceReport` or `reportType`.
  - `currency` filters now match finance source rows explicitly.
- Fixed sales and analytics filter validation so unsupported time selectors, filters, and `groupBy` values now fail fast instead of being accepted and ignored.
- Fixed `sales`, `reviews`, `finance`, and `analytics` subcommand help so each dataset only exposes the flags that actually work for that dataset.
- Fixed `--app-version` naming across the CLI, help output, and capability descriptions, while keeping JSON/query-spec field names stable as `version`.
- Fixed analytics report selection and parsing:
  - recent queries now prefer `ONGOING`, yearly queries prefer `ONE_TIME_SNAPSHOT`.
  - missing request/report/instance paths now emit explicit waiting warnings.
  - quoted CSV fields and numeric app/version dimensions now parse correctly.
  - rows without a valid date are now rejected instead of leaking into arbitrary windows.
- Fixed analytics app filtering so bundle ID and app ID queries stay exact online and offline, and same-named sibling apps no longer leak into results.
- Fixed analytics cache identity and deduplication so newer segment refreshes replace older rows instead of double-counting them, while shared checksums from different apps remain separate.
- Fixed vendor-scoped cache isolation for sales, reviews, finance, and analytics:
  - offline reads now prefer the configured vendor.
  - safe legacy cache reuse still works during upgrades.
  - ambiguous multi-account cache mixes now fail fast instead of returning wrong results.
- Fixed reviews behavior:
  - `rating` and `response-state` filters now apply correctly.
  - multi-app review sync now fails if any app fetch fails instead of silently returning partial data.
  - vendor-scoped review caches are now read and written consistently, including upgrade fallback rules.
- Fixed subscription report filtering and grouping:
  - `subscription`, `subscription-event`, and `subscriber` now honor `sku`.
  - app and subscription Apple IDs now work in filters.
  - same-named apps and subscriptions no longer collapse into one aggregate group.
- Fixed `brief` / `overview` data integrity:
  - subscription snapshots now keep the latest row per entity instead of using one global latest date.
  - sales and review coverage now reflect actual loaded dates.
  - summaries now warn when the current window has no source data instead of implying confirmed zero activity.
  - summary warm-up now preserves subscription and finance warnings instead of swallowing them.
- Fixed output and support ergonomics:
  - empty tables now render a clear no-data message.
  - review tables no longer duplicate or expose misleading raw rating columns.
  - warning codes are now surfaced in text output and issue templates for easier triage.
- Fixed the daily rollover baseline to `5 am PT` so default date presets match the documented Apple availability guidance.
- Added stronger offline/example/test coverage for cache ambiguity, analytics identity, comparison windows, source-report validation, summary coverage, and Homebrew/release-facing CLI output.

## 0.1.8 - 2026-04-08

- Added explicit platform requirements in `README.md`.
- Clarified that `scripts/full_cli_smoke.sh` requires real credentials and network access.
- Added `scripts/check_version_consistency.sh` and wired it into CI.
- Standardized community-facing docs to English (`SUPPORT.md`, `CODE_OF_CONDUCT.md`).
- Fixed `examples/queries/sales-aggregate-last-week.json` to remove invalid `compare` usage under `operation=aggregate`.
- Fixed `docs/data-model.md` request example to use `operation=compare` when including `compare` fields.
- Added `scripts/check_example_specs.sh` and wired it into CI to verify all example specs are executable offline.

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
