# Agent Guide

The stable machine interface is:

```bash
adc query run --spec <file|-> --output json
```

## Recommended flow

1. Build one JSON payload.
2. Pass it to `query run`.
3. Read the JSON response.
4. Treat `warnings` as real data.
5. Use follow-up `adc` drill-down commands when needed.

## Good defaults for agents

- Use `overview` or `brief` when the task starts with “summarize”.
- Use `sales aggregate`, `reviews aggregate`, or `analytics aggregate` when the task starts with “find why”.
- Use `query run --spec` when you need reproducible JSON.

## Supported datasets

- `sales`
- `reviews`
- `finance`
- `analytics`
- `brief`

## Supported operations

- `records`
- `aggregate`
- `compare`
- `brief`

## Time model

Apple business dates use PT.

Important presets:

- `last-day`
- `this-week`
- `this-month`
- `last-7d`
- `last-30d`
- `last-month`

Summary semantics:

- `brief + last-day` means latest complete Apple business day
- `brief + this-week` means week to date
- `brief + this-month` means month to date
- `brief + last-month` means previous full month

## Response model

For `sales`, `reviews`, `finance`, and `analytics`:

- output type: `QueryResult`

For `brief`:

- output type: `BriefSummaryReport`
- this is the same multi-table summary used by `adc brief ...` and `adc overview ...`

## Suggested prompts

Daily:

```text
Summarize the biggest KPI changes. Rank the top 3 anomalies. Suggest the next adc commands to verify the cause.
```

Weekly:

```text
Turn this weekly brief into an operating memo. Keep top-line KPIs first, then territory, product, subscriptions, reviews, and data quality.
```

Monthly:

```text
Summarize this month-to-date performance. Call out whether I should also run adc brief last-month for finance reconciliation.
```

## Notes

- Use `--offline` only for cache-only reads.
- Use `--refresh` only when you need a fresh Apple fetch.
- Analytics queries may create an Apple report request on first use.
- FX normalization may require a public exchange-rate lookup when no cached rate is available.
