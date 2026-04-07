# Data Model

Most public query commands share one request model.

## Shared request model

```json
{
  "dataset": "sales",
  "operation": "aggregate",
  "time": {
    "rangePreset": "last-7d"
  },
  "compare": "previous-period",
  "compareTime": null,
  "filters": {
    "territory": ["US", "CA"],
    "sourceReport": ["summary-sales"]
  },
  "groupBy": ["territory", "version"],
  "limit": null
}
```

## Core fields

- `dataset`
- `operation`
- `time`
- `compare`
- `compareTime`
- `filters`
- `groupBy`
- `limit`

## Shared response model

These datasets return `QueryResult`:

- `sales`
- `reviews`
- `finance`
- `analytics`

`QueryResult` contains:

- `dataset`
- `operation`
- `time`
- `filters`
- `source`
- `data`
- `comparison`
- `warnings`
- `tableModel`

## Brief response model

`brief` is intentionally different.

It returns `BriefSummaryReport` instead of `QueryResult`.

That model contains:

- `period`
- `title`
- `currentLabel`
- `compareLabel`
- `reportingCurrency`
- `timeBasis`
- `sections`
- `warnings`

Each `section` contains:

- `title`
- `note`
- `table`

## Why brief is separate

`brief` is designed to be a ready-made operating summary.

It is not a low-level records or aggregate response.

That is why:

- humans can read it directly in `table` or `markdown`
- agents can consume the same structure through `query run --spec`
