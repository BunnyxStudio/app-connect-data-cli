# Architecture

The CLI has three layers.

## `ACDCore`

The lowest layer owns Apple-facing primitives:

- JWT signing
- `.p8` import
- App Store Connect HTTP requests
- Sales report download
- Finance report download
- Review retrieval
- Review response support is not part of the public command surface for this release
- PT time parsing

This layer does not know about table rendering or brief generation.

## `ACDAnalytics`

This layer owns local analysis over Apple data:

- Raw report cache
- Manifest management
- Review cache
- Record normalization
- Aggregates and comparisons
- Weekly and monthly briefs
- Table models for terminal output

This layer is local-first.
It does not depend on a project-owned server.

## `ACDCLI`

This layer owns the command surface:

- Credential resolution
- Time range parsing
- On-demand data fetch
- JSON spec execution
- Output rendering

## Data flow

1. The user calls a command such as `sales aggregate`, `reviews compare`, or `query run`.
2. The CLI resolves the requested time window and filters.
3. If credentials are available, the CLI fetches the required Apple data on demand.
4. Raw files and review payloads are stored locally.
5. `ACDAnalytics` computes aggregates, comparisons, and briefs.
6. The CLI renders `json`, `table`, or `markdown`.

## Design rules

- Keep the command surface read-only.
- Keep Apple as the only external data source.
- Keep cache behavior internal.
- Keep JSON as the canonical machine format.
- Keep table rendering derived from the same data model, not from a separate code path.
