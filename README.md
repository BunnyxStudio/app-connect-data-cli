# app-connect-data-cli

[![License: Apache-2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](./LICENSE)

`app-connect-data-cli` is a read-only CLI for querying App Store Connect sales, finance, customer reviews, and Apple Analytics reports over explicit time windows.

It is built for operations, product, business analysis, and agent workflows that need structured Apple reporting data without a separate `sync` step.

## What it does

- Query Apple sales, finance, reviews, and analytics data directly by date, range, year, or fiscal month
- Aggregate and compare periods with stable JSON output
- Generate weekly and monthly briefs
- Render the same result as `json`, `table`, or `markdown`
- Accept a canonical JSON spec through `query run --spec`

## Boundaries

- Read-only only
- Apple official reporting APIs and Apple official report downloads only
- No project-owned backend
- No metadata, TestFlight, build, pricing, signing, or release management

## Privacy and security

This project does not run a project-owned server and does not upload your `.p8` key to any app-connect-data-cli backend.

- Your `.p8` stays on your machine
- The CLI reads the key from a local path and keeps it in memory only for request signing
- The CLI does not write `.p8` contents into config, cache, logs, or output
- Config and cache files are stored locally under `./.app-connect-data-cli/` or `~/.app-connect-data-cli/`
- Config, cache, and report files are created with owner-only permissions
- Existing `config.json` and `.p8` files are rejected if permissions are too broad

All network requests go directly to Apple App Store Connect endpoints.

## Installation

```bash
git clone <your-repo-url> app-connect-data-cli
cd app-connect-data-cli
swift build -c release
```

## Configuration

Set credentials with environment variables:

```bash
export ASC_ISSUER_ID="YOUR_ISSUER_ID"
export ASC_KEY_ID="YOUR_KEY_ID"
export ASC_VENDOR_NUMBER="YOUR_VENDOR_NUMBER"
export ASC_P8_PATH="/absolute/path/AuthKey_XXXXXX.p8"
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
  "p8Path": "/absolute/path/AuthKey_XXXXXX.p8"
}
```

Resolution order:

`flags > environment > ./.app-connect-data-cli/config.json > ~/.app-connect-data-cli/config.json`

## Quick start

```bash
./.build/release/app-connect-data-cli auth validate --output table
./.build/release/app-connect-data-cli capabilities list --output table
./.build/release/app-connect-data-cli sales records --range last-week --output json
./.build/release/app-connect-data-cli reviews aggregate --range last-week --group-by territory --output table
./.build/release/app-connect-data-cli brief weekly --output markdown
```

## Command surface

```bash
app-connect-data-cli auth validate
app-connect-data-cli capabilities list

app-connect-data-cli sales records --range last-week
app-connect-data-cli sales aggregate --range last-week --group-by territory
app-connect-data-cli sales compare --range last-week --compare previous-period

app-connect-data-cli reviews records --range last-week
app-connect-data-cli reviews aggregate --range last-week --group-by rating
app-connect-data-cli reviews compare --range last-week --compare previous-period

app-connect-data-cli finance records --fiscal-month 2026-02
app-connect-data-cli finance aggregate --fiscal-month 2026-02 --group-by territory --group-by currency
app-connect-data-cli finance compare --fiscal-month 2026-02 --compare month-over-month

app-connect-data-cli analytics records --range last-week --source-report usage
app-connect-data-cli analytics aggregate --range last-week --source-report acquisition --group-by app
app-connect-data-cli analytics compare --range last-week --source-report performance --compare previous-period

app-connect-data-cli brief weekly
app-connect-data-cli brief monthly
app-connect-data-cli query run --spec -
app-connect-data-cli cache clear
```

## Time selection

Use one of these:

- `--date YYYY-MM-DD`
- `--from YYYY-MM-DD --to YYYY-MM-DD`
- `--range <preset>`
- `--year YYYY`
- `--fiscal-month YYYY-MM`
- `--fiscal-year YYYY`

Supported presets:

- `last-day`
- `last-7d`
- `last-week`
- `last-30d`
- `last-month`
- `year-to-date`
- `previous-week`
- `previous-month`

## Direct query model

The CLI resolves the requested window, fetches Apple data on demand when credentials are available, reuses local cache when possible, and returns the result immediately.

Use:

- `--offline` for cache-only reads
- `--refresh` to ignore cached raw files and fetch again

There is no public `sync` command in the default workflow.

## Agent usage

The canonical machine interface is:

```bash
app-connect-data-cli query run --spec <file|-> --output json
```

Example:

```bash
cat examples/queries/sales-aggregate-last-week.json | ./.build/release/app-connect-data-cli query run --spec - --output json
```

See [docs/query-spec.md](./docs/query-spec.md) and [docs/agent-guide.md](./docs/agent-guide.md).

## Local cache

Local cache is file-based.

- Repo-local: `./.app-connect-data-cli/cache/`
- User-level: `~/.app-connect-data-cli/cache/`

Cached content includes:

- Raw Apple report files
- `manifest.json`
- `reviews/latest.json`

## Development

```bash
swift build
swift test
./.build/debug/app-connect-data-cli --help
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
