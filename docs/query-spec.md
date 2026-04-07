# Query Spec

`adc query run --spec <file|->` accepts a JSON payload.

## Shared request shape

```json
{
  "dataset": "sales",
  "operation": "aggregate",
  "time": {
    "rangePreset": "last-7d"
  },
  "compare": "previous-period",
  "filters": {
    "territory": ["US", "CA"],
    "sourceReport": ["summary-sales"]
  },
  "groupBy": ["territory", "version"]
}
```

## Datasets

- `sales`
- `reviews`
- `finance`
- `analytics`
- `brief`

## Operations

- `records`
- `aggregate`
- `compare`
- `brief`

## Time fields

- `datePT`
- `startDatePT`
- `endDatePT`
- `rangePreset`
- `year`
- `fiscalMonth`
- `fiscalYear`

Supported presets:

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

## Compare

- `previous-period`
- `week-over-week`
- `month-over-month`
- `year-over-year`
- `custom`

`compareTime` is valid only with `compare: "custom"`.

## Filters

Supported keys:

- `app`
- `version`
- `territory`
- `currency`
- `device`
- `sku`
- `subscription`
- `platform`
- `sourceReport`
- `rating`
- `responseState`

## Group by

Supported values:

- `day`
- `week`
- `month`
- `fiscalMonth`
- `app`
- `version`
- `territory`
- `device`
- `sku`
- `rating`
- `responseState`
- `reportType`
- `platform`
- `sourceReport`
- `subscription`

## Response shape

For `sales`, `reviews`, `finance`, and `analytics`, `query run` returns the shared `QueryResult` JSON model.

For `brief`, `query run` returns `BriefSummaryReport`.

That is the same summary shape used by:

- `adc brief ...`
- `adc overview ...`

## Brief spec rules

`brief` is intentionally narrower than raw datasets.

Use:

```json
{
  "dataset": "brief",
  "operation": "brief",
  "time": {
    "rangePreset": "this-week"
  }
}
```

Supported `brief` presets:

- `last-day`
- `this-week`
- `this-month`
- `last-7d`
- `last-30d`
- `last-month`

Do not send:

- `filters`
- `groupBy`
- `limit`
- `compare`
- `compareTime`

## Examples

- [`examples/queries/sales-aggregate-last-week.json`](../examples/queries/sales-aggregate-last-week.json)
- [`examples/queries/reviews-compare-last-week.json`](../examples/queries/reviews-compare-last-week.json)
- [`examples/queries/finance-aggregate-month.json`](../examples/queries/finance-aggregate-month.json)
- [`examples/queries/analytics-records-last-week.json`](../examples/queries/analytics-records-last-week.json)
- [`examples/queries/brief-weekly.json`](../examples/queries/brief-weekly.json)
