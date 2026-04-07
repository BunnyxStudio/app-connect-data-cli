# app-connect-data-cli

`app-connect-data-cli` is a command-line tool for querying App Store Connect sales, finance, subscription, and review data over explicit time ranges.

Ask for a single day, a custom date window, or a preset such as `last-week`, and the CLI fetches the required data on demand. Raw files are cached locally, but caching stays in the background unless you want to control it.

## What it does

- Query sales and finance snapshots for a specific date range
- Build dashboard-style module views without a separate sync step
- Read and summarize customer reviews
- Return output as `json`, `table`, or `markdown`
- Provide a stable JSON spec entry point for agents and scripts

## Scope

This project focuses on App Store Connect data access and analysis.

It does not cover release automation, TestFlight distribution, metadata management, signing, or screenshot upload workflows. If you need a broader App Store Connect CLI, see [App Store Connect CLI](https://github.com/rudrankriyam/App-Store-Connect-CLI).

## Installation

Build from source:

```bash
git clone <your-repo-url> app-connect-data-cli
cd app-connect-data-cli
swift build -c release
```

## Configuration

You can configure credentials with environment variables:

```bash
export ASC_ISSUER_ID="YOUR_ISSUER_ID"
export ASC_KEY_ID="YOUR_KEY_ID"
export ASC_VENDOR_NUMBER="YOUR_VENDOR_NUMBER"
export ASC_P8_PATH="/absolute/path/AuthKey_XXXXXX.p8"
```

Or with a config file:

- Repo-local: `./.app-connect-data-cli/config.json`
- User-level: `~/.app-connect-data-cli/config.json`

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

`flags > environment variables > ./.app-connect-data-cli/config.json > ~/.app-connect-data-cli/config.json`

For local file safety, the CLI expects owner-only permissions on both `config.json` and the `.p8` file.
Use `chmod 600` if needed.

## Quick start

Validate credentials:

```bash
./.build/release/app-connect-data-cli auth validate --output table
```

Query sales for last week:

```bash
./.build/release/app-connect-data-cli query snapshot --source sales --range last-week --output table
```

Query a combined module view for the latest day:

```bash
./.build/release/app-connect-data-cli query modules --range last-day --output markdown
```

Summarize recent reviews:

```bash
./.build/release/app-connect-data-cli reviews summary --range last-week --output json
```

## Date selection

Use any one of these:

- `--date YYYY-MM-DD`
- `--from YYYY-MM-DD --to YYYY-MM-DD`
- `--range <preset>`

Supported presets:

- `today`
- `last-day`
- `last-week`
- `last-7d`
- `last-30d`
- `this-week`
- `this-month`
- `last-month`

Examples:

```bash
./.build/release/app-connect-data-cli query snapshot --date 2026-04-06
./.build/release/app-connect-data-cli query snapshot --from 2026-04-01 --to 2026-04-06
./.build/release/app-connect-data-cli query snapshot --range "last week"
./.build/release/app-connect-data-cli query snapshot --range last-month
```

## Query model

The default flow is direct query:

1. Resolve the requested time range
2. Fetch the required reports or reviews if credentials are available
3. Reuse local cache when possible
4. Return the result immediately

Use these flags when you want tighter control:

- `--offline` reads from local cache only
- `--refresh` ignores cached raw files and fetches again

## Privacy and security

This project does not run a project-owned backend and does not upload your credentials to any app-connect-data-cli server.

- Your `.p8` file stays on your machine
- The CLI reads the `.p8` file from a local path and keeps the PEM in memory only for signing
- The CLI does not write the `.p8` contents into config files, cache files, or generated output
- Repo-local credentials and cache live under `.app-connect-data-cli/`, which is ignored by git
- Cache directories and files are created with owner-only permissions
- Existing `config.json`, `.p8`, and cache files are checked for owner-only permissions before use

Network traffic goes directly to Apple App Store Connect endpoints for reports and reviews.

For USD normalization, the CLI may also call the Frankfurter FX API with only a date and a list of currency codes.
Those FX requests do not include your `.p8` file, JWT, vendor number, review text, or raw report contents.

## Agent and automation usage

The most stable interface for agents is:

```bash
app-connect-data-cli query run --spec <file|-> --output json
```

Example:

```bash
cat examples/queries/snapshot-30d.json | ./.build/release/app-connect-data-cli query run --spec - --output json
```

Supported `kind` values:

- `snapshot`
- `modules`
- `health`
- `trend`
- `top-products`
- `reviews.list`
- `reviews.summary`

See [docs/query-spec.md](docs/query-spec.md) and [docs/agent-guide.md](docs/agent-guide.md) for details.

## Common commands

```bash
app-connect-data-cli auth validate

app-connect-data-cli query snapshot --range last-week
app-connect-data-cli query modules --range last-day
app-connect-data-cli query health
app-connect-data-cli query trend --source finance --range last-month
app-connect-data-cli query top-products --territory US --range last-30d
app-connect-data-cli query run --spec -

app-connect-data-cli reviews list --range last-week
app-connect-data-cli reviews summary --range last-week
app-connect-data-cli reviews respond REVIEW_ID --body "Thanks for the feedback."

app-connect-data-cli doctor probe
app-connect-data-cli doctor audit
app-connect-data-cli doctor reconcile --range last-month

app-connect-data-cli cache clear
```

## Advanced prefetch

`sync` is still available for prefetching, warming cache, or debugging fetch coverage, but it is not required for normal use.

```bash
app-connect-data-cli sync sales --days 7
app-connect-data-cli sync subscriptions --days 7
app-connect-data-cli sync finance --months 2
app-connect-data-cli sync reviews --total-limit 200
```

## Local cache

This project uses local files instead of a database.

- Repo-local: `./.app-connect-data-cli/cache/`
- User-level: `~/.app-connect-data-cli/cache/`

Cached content includes:

- Raw report files
- `manifest.json`
- `reviews/latest.json`
- `fx-rates.json`

## Development

```bash
swift build
swift test
./.build/debug/app-connect-data-cli --help
```

## Support

- Usage questions: GitHub Discussions
- Bugs and feature requests: GitHub Issues
- Security issues: [SECURITY.md](SECURITY.md)
- Contribution guide: [CONTRIBUTING.md](CONTRIBUTING.md)

## License

MIT
