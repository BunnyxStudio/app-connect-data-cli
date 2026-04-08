# App Store Connect Data CLI

[![License: Apache-2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](./LICENSE)

`App Store Connect Data CLI` is a read-only CLI for querying App Store Connect sales, finance, customer reviews, and Apple Analytics reports over explicit time windows.

It is built for operators, indie developers, product teams, and agents that need structured Apple reporting data without building a separate backend.

The command name is `adc`.
The GitHub repository slug is `app-store-connect-data-cli`.

## What it does

- Query Apple sales, finance, reviews, and analytics data directly by date, range, year, or fiscal month
- Normalize monetary metrics into a configurable reporting currency such as `USD` or `CNY`
- Generate human-friendly multi-table summaries through `adc overview ...` or `adc brief ...`
- Return stable JSON through `adc query run --spec`
- Reuse local cache when possible and fetch on demand when credentials are available

## Start here

Use these first:

```bash
adc auth validate --output table
adc overview daily
adc overview weekly
adc overview monthly
adc brief last-month
adc sales aggregate --range last-7d --group-by territory --output table
```

Use `overview` if you want a guided summary.

Use `sales`, `reviews`, `finance`, `analytics`, or `query run --spec` if you want raw query control.

## Boundaries

- Read-only only
- Apple official reporting APIs and Apple official report downloads only for Apple data
- No project-owned backend
- No metadata, TestFlight, build, pricing, signing, or release management

## Privacy and security

This project does not run a project-owned server and does not upload your `.p8` key to any App Store Connect Data CLI service.

- Your `.p8` stays on your machine
- The CLI reads the key from a local path and keeps it in memory only for request signing
- The CLI does not write `.p8` contents into config, cache, logs, or output
- Config and cache files are stored locally under `./.app-connect-data-cli/` or `~/.app-connect-data-cli/`
- Config, cache, and report files are created with owner-only permissions
- Existing `config.json` and `.p8` files are rejected if permissions are too broad

Network behavior:

- Apple report requests go directly to Apple App Store Connect endpoints
- FX normalization uses [Frankfurter](https://frankfurter.dev/) only when a cross-currency rate is needed and no cached rate is available
- Apple credentials are never sent to the FX provider
- Use `--offline` to disable network reads and stay cache-only

## Installation

### Homebrew

```bash
brew install BunnyxStudio/tap/adc
```

The formula is published from the `homebrew-tap` repo and tracks the latest tagged release.

### Homebrew Bottle Automation (Maintainers)

- This repo opens a tap PR automatically after a GitHub Release is published:
  - `.github/workflows/homebrew-tap-pr.yml`
- Required secret in this repo:
  - `HOMEBREW_TAP_GH_TOKEN` (must be allowed to push branches and open PRs on `BunnyxStudio/homebrew-tap`)
- The tap repo then runs `brew test-bot`, auto-labels successful PRs with `pr-pull`, and publishes bottles through `brew pr-pull`.

### Build from source

```bash
git clone https://github.com/BunnyxStudio/app-store-connect-data-cli.git
cd app-store-connect-data-cli
swift build -c release
mkdir -p ~/.local/bin
install -m 755 ./.build/release/adc ~/.local/bin/adc
```

If `~/.local/bin` is not in your `PATH`, add it first.

## Configuration

Set credentials with environment variables:

```bash
export ASC_ISSUER_ID="YOUR_ISSUER_ID"
export ASC_KEY_ID="YOUR_KEY_ID"
export ASC_VENDOR_NUMBER="YOUR_VENDOR_NUMBER"
export ASC_P8_PATH="/absolute/path/AuthKey_XXXXXX.p8"
export ADC_REPORTING_CURRENCY="USD"
export ADC_DISPLAY_TIMEZONE="Asia/Shanghai"
```

### Where to get required IDs and `.p8` key

You need four credential values:

- `issuerID`
- `keyID`
- `vendorNumber`
- `p8Path` (path to your local `AuthKey_XXXXXX.p8` file)

Get `issuerID`, `keyID`, and `.p8`:

1. Open App Store Connect.
2. Go to `Users and Access` -> `Integrations` -> `App Store Connect API`.
3. Copy `Issuer ID` from this page.
4. Create a Team API key if you do not have one yet.
5. Copy the new key's `Key ID`.
6. Download the `.p8` file (`AuthKey_<KEY_ID>.p8`).

Important: Apple only lets you download the `.p8` file once.

Get `vendorNumber`:

1. Open App Store Connect.
2. Go to `Agreements, Tax, and Banking`.
3. Open your active agreement details.
4. Copy your `Vendor Number`.

Store your key safely:

```bash
mkdir -p ~/.keys/appstoreconnect
mv /path/to/AuthKey_XXXXXX.p8 ~/.keys/appstoreconnect/
chmod 600 ~/.keys/appstoreconnect/AuthKey_XXXXXX.p8
```

Never commit `.p8` into git.
Keep it outside your repo.
This repo already ignores `*.p8`.

Then set:

```bash
export ASC_ISSUER_ID="YOUR_ISSUER_ID"
export ASC_KEY_ID="YOUR_KEY_ID"
export ASC_VENDOR_NUMBER="YOUR_VENDOR_NUMBER"
export ASC_P8_PATH="$HOME/.keys/appstoreconnect/AuthKey_XXXXXX.p8"
```

Validate your setup:

```bash
adc auth validate --output table
```

Or create one of these files:

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

Manage defaults from the CLI:

```bash
adc config currency show
adc config currency set CNY
adc config currency set USD --local

adc config timezone show
adc config timezone set Asia/Shanghai
adc config timezone set America/Los_Angeles --local
```

Resolution order:

`flags > environment > ./.app-connect-data-cli/config.json > ~/.app-connect-data-cli/config.json`

## Quick start

```bash
./.build/release/adc auth validate --output table
./.build/release/adc config currency show --output table
./.build/release/adc config timezone show --output table
./.build/release/adc capabilities list --output table
./.build/release/adc overview daily
./.build/release/adc overview weekly --output markdown
./.build/release/adc brief last-month
./.build/release/adc sales aggregate --range last-7d --group-by territory --output table
```

## Command surface

```bash
adc auth validate

adc config currency show
adc config currency set CNY
adc config timezone show
adc config timezone set Asia/Shanghai

adc capabilities list

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

## Time semantics

Apple business dates use Pacific Time (`America/Los_Angeles`).

The CLI does not assume a fixed China-only update time such as “8pm Beijing”.

Instead it resolves summaries from Apple’s PT reporting cadence:

- `daily` means the latest complete Apple business day
- `weekly` means this week to date, ending on the latest complete day
- `monthly` means this month to date, ending on the latest complete day
- `last-7d` means the last 7 complete days
- `last-30d` means the last 30 complete days
- `last-month` means the previous full month

The summary header shows:

- the PT business-date range used for the data
- the configured reporting currency
- the next daily rollover in your display time zone

Apple can still return a not-ready response before a requested report is published.

A common Sales and Trends response is:

`The request expected results but none were found - Report is not available yet.`

Treat that as "Apple has not published this report yet", not as zero sales or zero activity.

For daily Sales and Trends reports, Apple Reporter guidance says availability is staggered:

- Americas by 5 am Pacific Time
- Japan, Australia, and New Zealand by 5 am Japan Standard Time
- Other territories by 5 am Central European Time

Use the CLI rollover hint as a planning aid, not a guarantee that every Apple daily report is already ready.
If you already have local cache, use `--offline` to avoid replacing a known-good cached result with an Apple not-ready response.

Display time zone comes from:

- `ADC_DISPLAY_TIMEZONE`
- `displayTimeZone` in config
- otherwise your current system time zone

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

## Brief and overview

`brief` and `overview` return the same summary.

`overview` is the friendlier name for humans.

`brief` stays as the compact name for users and agents that already depend on it.

Summary behavior:

- `adc overview daily`
  - Current: latest complete day
  - Compare: previous complete day
- `adc overview weekly`
  - Current: this week to date
  - Compare: previous week, same progress
- `adc overview monthly`
  - Current: this month to date
  - Compare: previous month, same progress
- `adc overview last-7d`
  - Current: last 7 complete days
  - Compare: previous 7 days
- `adc overview last-30d`
  - Current: last 30 complete days
  - Compare: previous 30 days
- `adc overview last-month`
  - Current: previous full month
  - Compare: month before last
  - Includes finance reconcile tables

Monetary metrics are normalized to the configured reporting currency.

Raw mixed-currency totals are not shown in CLI outputs.

## Direct query model

The CLI resolves the requested window, fetches Apple data on demand when credentials are available, reuses local cache when possible, and returns the result immediately.

Use:

- `--offline` for cache-only reads
- `--refresh` to ignore cached raw files and fetch again

There is no public `sync` command in the default workflow.

## Agent usage

The canonical machine interface is:

```bash
adc query run --spec <file|-> --output json
```

For `sales`, `reviews`, `finance`, and `analytics`, this returns the shared `QueryResult` JSON model.

For `brief`, this returns the same `BriefSummaryReport` shape used by `adc brief ...` and `adc overview ...`.

Example:

```bash
cat examples/queries/sales-aggregate-last-week.json | ./.build/release/adc query run --spec - --output json
cat examples/queries/brief-weekly.json | ./.build/release/adc query run --spec - --output json
```

See [docs/query-spec.md](./docs/query-spec.md), [docs/data-model.md](./docs/data-model.md), and [docs/agent-guide.md](./docs/agent-guide.md).

## Examples

### 1. Indie developer checking revenue

```bash
adc overview daily
adc overview weekly
adc sales aggregate --range last-7d --group-by territory --output table
```

### 2. Ops review before Monday meeting

```bash
adc overview weekly --output markdown
adc reviews aggregate --range last-7d --group-by rating --output table
adc analytics aggregate --range last-7d --source-report usage --group-by app --output table
```

### 3. Full previous month finance check

```bash
adc brief last-month --output markdown
adc finance aggregate --fiscal-month 2026-03 --group-by territory --group-by currency --output table
```

### 4. Agent workflow in Codex

Recommended pattern:

1. Schedule it after the local rollover shown by `adc config timezone show`
2. Run `adc overview daily --output markdown`
3. Give that markdown to Codex
4. Ask Codex to summarize anomalies, rank the biggest changes, and suggest the next `adc` drill-down commands

Prompt example:

```text
Run every weekday after the local rollover. Read the latest daily markdown summary, find the biggest KPI changes, explain likely causes, and tell me the next 3 adc commands I should run.
```

### 5. Agent workflow in Claude Code

Recommended pattern:

1. Schedule it after the local rollover or before your weekly review meeting
2. Run `adc query run --spec examples/queries/brief-weekly.json --output json`
3. Give that JSON to Claude Code
4. Ask Claude Code to turn it into a weekly operating memo

Prompt example:

```text
Run every Monday evening in my display time zone. Read this weekly brief JSON and turn it into a concise operating memo. Keep the top-line KPI changes first, then territory, product, subscription, reviews, and data quality.
```

### 6. Local scheduled job with cron

Run after the local rollover shown by `adc config timezone show`:

```bash
15 20 * * 1-5 cd /path/to/app-store-connect-data-cli && ./.build/release/adc overview daily --output markdown > reports/daily.md
```

For weekly and monthly reports:

```bash
30 20 * * 1 cd /path/to/app-store-connect-data-cli && ./.build/release/adc overview weekly --output markdown > reports/weekly.md
45 20 1 * * cd /path/to/app-store-connect-data-cli && ./.build/release/adc brief last-month --output markdown > reports/last-month.md
```

## Local cache

Local cache is file-based.

- Repo-local: `./.app-connect-data-cli/cache/`
- User-level: `~/.app-connect-data-cli/cache/`

Cached content includes:

- Raw Apple report files
- `manifest.json`
- `reviews/latest.json`
- cached FX rates used for reporting-currency normalization

## Development

```bash
swift build
swift test
./scripts/full_cli_smoke.sh
./.build/debug/adc --help
```

## Support

- Usage questions: GitHub Discussions
- Bugs and feature requests: GitHub Issues
- Security issues: [SECURITY.md](./SECURITY.md)
- Contribution guide: [CONTRIBUTING.md](./CONTRIBUTING.md)

## License

Licensed under the Apache License, Version 2.0.

Forking, modification, redistribution, and commercial use are allowed.
Redistributed or derivative versions must retain the license and the original project attribution in [NOTICE](./NOTICE).
