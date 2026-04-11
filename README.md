# App Store Connect Data CLI

[![License: Apache-2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](./LICENSE)

`App Store Connect Data CLI` (`adc`) is a read-only CLI for App Store Connect reporting data.

It queries sales, finance, customer reviews, and Apple Analytics over explicit time windows.

It is built for operators, indie developers, product teams, and agents that need structured Apple reporting data without building a backend.

## Start Here (3-Minute Flow)

Use this exact order:

1. Install `adc`.
2. Get `issuerID`, `keyID`, `vendorNumber`, and `.p8`.
3. Configure credentials.
4. Validate auth.
5. Run your first summary.

```bash
brew install BunnyxStudio/tap/adc

export ASC_ISSUER_ID="YOUR_ISSUER_ID"
export ASC_KEY_ID="YOUR_KEY_ID"
export ASC_VENDOR_NUMBER="YOUR_VENDOR_NUMBER"
export ASC_P8_PATH="/absolute/path/AuthKey_XXXXXX.p8"
export ADC_REPORTING_CURRENCY="USD"
export ADC_DISPLAY_TIMEZONE="Asia/Shanghai"

adc auth validate --output table
adc overview daily
```

If `auth validate` passes, your credentials are valid.

Your first analytics query may still return a waiting warning until Apple creates and publishes the first Analytics report instance.

## Navigation

- New user setup: [Credentials and Configuration](#credentials-and-configuration)
- Daily/weekly reporting: [Common Workflows](#common-workflows)
- JSON for agents: [Agent and JSON Usage](#agent-and-json-usage)
- Full commands: [Command Reference](#command-reference)
- Time logic and rollover: [Time Semantics](#time-semantics)

## Scope

What this CLI does:

- Read-only queries for Apple sales, finance, reviews, and analytics reports
- Human-friendly summary output via `adc overview ...` and `adc brief ...`
- Stable JSON output via `adc query run --spec`
- Monetary metrics normalized to your configured reporting currency
- Fresh online reads with optional cache-only reruns

What this CLI does not do:

- Metadata management
- TestFlight and build management
- Pricing and subscription setup
- Signing or release automation
- User/access management

## Installation

### Requirements

- macOS 14 or later
- App Store Connect API key access (`issuerID`, `keyID`, `vendorNumber`, `.p8`)
- Homebrew (for `brew install`) or Xcode 26+ with Swift 6.2+ (for source builds)

### Homebrew (recommended)

```bash
brew install BunnyxStudio/tap/adc
```

### Build from source

```bash
git clone https://github.com/BunnyxStudio/app-store-connect-data-cli.git
cd app-store-connect-data-cli
swift build -c release
mkdir -p ~/.local/bin
install -m 755 ./.build/release/adc ~/.local/bin/adc
```

If `~/.local/bin` is not in your `PATH`, add it first.

## Credentials and Configuration

Required values:

- `issuerID`
- `keyID`
- `vendorNumber`
- `p8Path` (path to `AuthKey_XXXXXX.p8`)

### Where to get IDs and `.p8`

Get `issuerID`, `keyID`, and `.p8`:

1. Open App Store Connect.
2. Go to `Users and Access` -> `Integrations` -> `App Store Connect API`.
3. Copy `Issuer ID`.
4. Create a Team API key if needed.
5. Copy `Key ID`.
6. Download `AuthKey_<KEY_ID>.p8`.

Important: Apple lets you download `.p8` only once.

Get `vendorNumber`:

1. Open App Store Connect.
2. Go to `Agreements, Tax, and Banking`.
3. Open the active agreement.
4. Copy `Vendor Number`.

### Store key securely

```bash
mkdir -p ~/.keys/appstoreconnect
mv /path/to/AuthKey_XXXXXX.p8 ~/.keys/appstoreconnect/
chmod 600 ~/.keys/appstoreconnect/AuthKey_XXXXXX.p8
```

Never commit `.p8` into git.

This repo already ignores `*.p8`.

### Configure via environment variables

```bash
export ASC_ISSUER_ID="YOUR_ISSUER_ID"
export ASC_KEY_ID="YOUR_KEY_ID"
export ASC_VENDOR_NUMBER="YOUR_VENDOR_NUMBER"
export ASC_P8_PATH="$HOME/.keys/appstoreconnect/AuthKey_XXXXXX.p8"
export ADC_REPORTING_CURRENCY="USD"
export ADC_DISPLAY_TIMEZONE="Asia/Shanghai"
```

### Configure via config file

Create either:

- `./.app-connect-data-cli/config.json`
- `~/.app-connect-data-cli/config.json`

Example:

```json
{
  "issuerID": "YOUR_ISSUER_ID",
  "keyID": "YOUR_KEY_ID",
  "vendorNumber": "YOUR_VENDOR_NUMBER",
  "p8Path": "/absolute/path/AuthKey_XXXXXX.p8",
  "reportingCurrency": "USD",
  "displayTimeZone": "Asia/Shanghai"
}
```

Resolution order:

`flags > environment > ./.app-connect-data-cli/config.json > ~/.app-connect-data-cli/config.json`

### Validate and manage defaults

```bash
adc auth validate --output table

adc config currency show
adc config currency set CNY
adc config currency set USD --local

adc config timezone show
adc config timezone set Asia/Shanghai
adc config timezone set America/Los_Angeles --local
```

## Common Workflows

### Daily health check

Who this is for: indie developers and PMs who check trend shifts every day.

When to run: after Apple daily rollover, before your first work block.

```bash
adc overview daily
adc sales aggregate --range last-7d --group-by territory --output table
```

### Weekly ops review

Who this is for: ops owners preparing weekly KPI review.

When to run: before Monday or weekly team meeting.

```bash
adc overview weekly --output markdown
adc reviews aggregate --range last-7d --group-by rating --output table
adc analytics aggregate --range last-7d --source-report usage --group-by app --output table
```

### Previous month finance review

Who this is for: founders or finance owners closing monthly numbers.

When to run: after month-close when Apple finance data is ready.

```bash
adc brief last-month --output markdown
adc finance aggregate --fiscal-month 2026-03 --group-by territory --group-by currency --output table
```

Finance defaults to the consolidated `FINANCIAL` report. Add `--source-report finance-detail` when you need row-level detail.

### Local cron scheduling

Who this is for: users who want unattended local report generation.

Run after the daily rollover shown inside `adc overview ...` or `adc brief ...`.

`adc config timezone show` only tells you which display time zone the summaries use.

Use the installed `adc` binary via its absolute path.

If you rely on repo-local `./.app-connect-data-cli`, keep cron running from the repo root:

```bash
15 20 * * 1-5 cd /path/to/app-store-connect-data-cli && /absolute/path/to/adc overview daily --output markdown > /path/to/reports/daily.md
30 20 * * 1 cd /path/to/app-store-connect-data-cli && /absolute/path/to/adc overview weekly --output markdown > /path/to/reports/weekly.md
45 20 1 * * cd /path/to/app-store-connect-data-cli && /absolute/path/to/adc brief last-month --output markdown > /path/to/reports/last-month.md
```

## Example Output

Example `adc overview daily --output table`:

```text
==== Daily Summary ====

Current: latest complete day (2026-04-09 PT)

Compare: previous complete day (2026-04-08 PT)

Currency: USD

Time basis: Apple business dates use PT. Next daily rollover in America/Los_Angeles: 2026-04-11 05:00 PDT.

==== Overview ====

Subscription metrics use the latest snapshot inside each range.

Metric                | Current  | Compare  | % Change
----------------------|----------|----------|---------
Sales Proceeds        | USD 0.00 | USD 0.00 | 0.00%
Install Units         | 0        | 0        | 0.00%
Active Subscriptions  | 0        | 0        | 0.00%
Average Rating        | 0.00     | 0.00     | 0.00%

==== Data Health ====

Item                        | Value
----------------------------|-------------------------
Reporting Currency          | USD
Display Time Zone           | America/Los_Angeles
Current Range               | 2026-04-09 to 2026-04-09
Compare Range               | 2026-04-08 to 2026-04-08
```

Example `adc brief last-month --output markdown`:

```markdown
# Last Month Summary

- Current: previous full month
- Compare: month before last
- Currency: USD
- Time basis: Apple business dates use PT.

## Overview

| Metric | Current | Compare | % Change |
| --- | --- | --- | --- |
| Sales Proceeds | USD 2,481.20 | USD 2,302.70 | +7.75% |
| Finance Proceeds | USD 2,430.10 | USD 2,260.50 | +7.50% |
| Active Subscriptions | 9,842 | 9,511 | +3.48% |

## Data Health

| Item | Value |
| --- | --- |
| Reporting Currency | USD |
| Current Range | 2026-03-01 to 2026-03-31 |
| Sales Coverage Days | 31 |
| Finance Fiscal Month | 2026-03 |
```

## Command Reference

Most-used commands:

```bash
adc --version

adc auth validate

adc overview daily
adc overview weekly
adc overview monthly
adc overview last-7d
adc overview last-30d
adc overview last-month

adc sales records --range last-7d
adc sales aggregate --range last-7d --group-by territory
adc sales compare --range last-7d --compare previous-period

adc reviews records --range last-7d
adc reviews aggregate --range last-7d --group-by rating
adc reviews compare --range last-7d --compare previous-period

adc finance records --fiscal-month 2026-02
adc finance aggregate --fiscal-month 2026-02 --group-by territory --group-by currency
adc finance compare --fiscal-month 2026-02 --compare month-over-month

adc analytics records --range last-7d --source-report usage
adc analytics aggregate --range last-7d --source-report usage --group-by app
adc analytics compare --range last-7d --source-report usage --compare previous-period

adc brief daily
adc brief weekly
adc brief monthly
adc brief last-7d
adc brief last-30d
adc brief last-month

adc query run --spec -
adc cache clear
```

For capability boundaries, see [docs/capabilities.md](./docs/capabilities.md).

Cache controls:

- Online queries fetch fresh data when credentials are available
- Use `--offline` for cache-only reads and reproducible reruns

There is no public `sync` command in the default workflow.

## Time Semantics

Apple business dates use Pacific Time (`America/Los_Angeles`).

Summary presets are resolved against Apple reporting cadence:

- `daily`: latest complete Apple business day
- `weekly`: this week to date, ending on latest complete day
- `monthly`: this month to date, ending on latest complete day
- `last-7d`: last 7 complete days
- `last-30d`: last 30 complete days
- `last-month`: previous full month

A common Apple not-ready response is:

`The request expected results but none were found - Report is not available yet.`

Treat this as "not published yet", not zero activity.

Use `--offline` if you want cache-only reads.

If you use `--offline` with summaries or aggregates that normalize mixed currencies, local FX rates must already be cached.

If local FX is missing, either:

- run once without `--offline` to cache FX
- or set `reportingCurrency` to a currency that does not need conversion for your query

### Analytics not ready does not mean zero

Sales or reviews data existing does not guarantee analytics files exist yet.

A not-ready analytics warning usually means one of these:

- Apple has not created the report request yet
- Apple created the request, but has not published the first report
- Apple has not published the requested daily, weekly, or monthly instance yet
- Apple suppressed or delayed the report because of coverage or completeness rules

Treat `analytics-request-missing`, `analytics-report-missing`, and `analytics-instance-missing` as a waiting state, not as zero activity.

`analytics-privacy` means Apple may omit rows or metric values even when a report exists. That is a data caveat, not a waiting state.

Display time zone comes from:

- `ADC_DISPLAY_TIMEZONE`
- `displayTimeZone` in config
- otherwise your system time zone

Supported range presets:

- `last-day`
- `this-week`
- `last-week`
- `last-7d`
- `this-month`
- `last-30d`
- `last-month`
- `year-to-date`
- `previous-week`
- `previous-month`

### `overview` and `brief`

`overview` and `brief` return the same summary model.

`overview` is friendlier for humans.

`brief` is the compact command name for users and agents that already depend on it.

## Agent and JSON Usage

Canonical machine interface:

```bash
adc query run --spec <file|-> --output json
```

Example:

```bash
cat examples/queries/sales-aggregate-last-week.json | adc query run --spec - --output json
cat examples/queries/brief-weekly.json | adc query run --spec - --output json
```

Reference docs:

- [docs/query-spec.md](./docs/query-spec.md)
- [docs/data-model.md](./docs/data-model.md)
- [docs/agent-guide.md](./docs/agent-guide.md)
- [examples/queries](./examples/queries)

## Privacy and Security

This project does not run a project-owned server.

This project does not upload your `.p8` key to any project service.

- `.p8` stays on your machine
- `.p8` is read from local path and kept in memory only for signing
- `.p8` content is not written to config, cache, logs, or output
- Config and cache live under `./.app-connect-data-cli/` or `~/.app-connect-data-cli/`
- Config, cache, and report files are owner-only
- Existing `config.json` and `.p8` files are rejected if permissions are too broad

Network behavior:

- Apple report requests go directly to Apple App Store Connect endpoints
- FX normalization uses [Frankfurter](https://frankfurter.dev/) only when needed and not cached
- Apple credentials are never sent to the FX provider
- `--offline` disables network reads

## Local Cache

Cache paths:

- Repo-local: `./.app-connect-data-cli/cache/`
- User-level: `~/.app-connect-data-cli/cache/`

Cached content includes:

- Raw Apple report files
- `manifest.json`
- `reviews/latest-<vendor>.json`
- Cached FX rates

More details: [docs/cache-and-config.md](./docs/cache-and-config.md).

## Development

```bash
swift build
swift test
./.build/debug/adc --help
```

Optional end-to-end smoke (requires real App Store Connect credentials and network access):

```bash
./scripts/full_cli_smoke.sh
```

## Support

- Before opening an issue:
  - run `adc --version`
  - re-run once with `--output json`
  - include the warning `code` if one is present
  - say whether you used live mode or `--offline`
  - if the failure was offline, say whether local FX rates were already cached
- Usage questions: GitHub Discussions
- Bugs and feature requests: GitHub Issues
- Security issues: [SECURITY.md](./SECURITY.md)
- Contribution guide: [CONTRIBUTING.md](./CONTRIBUTING.md)

## License

Licensed under the Apache License, Version 2.0.

Forking, modification, redistribution, and commercial use are allowed.

Redistributed or derivative versions must retain the license and the original project attribution in [NOTICE](./NOTICE).

## Maintainer Notes

<details>
<summary>Homebrew bottle automation</summary>

- This repo opens a tap PR automatically after a GitHub Release is published:
  - `.github/workflows/homebrew-tap-pr.yml`
- Required secret in this repo:
  - `HOMEBREW_TAP_GH_TOKEN` (must be allowed to push branches and open PRs on `BunnyxStudio/homebrew-tap`)
- The tap repo then runs `brew test-bot`, auto-labels successful PRs with `pr-pull`, and publishes bottles through `brew pr-pull`.

</details>
