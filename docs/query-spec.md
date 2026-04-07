# Query Spec

`app-connect-data-cli query run --spec <file|->` accepts a `DataQuerySpec` JSON payload.

## Example

```json
{
  "dataset": "sales",
  "operation": "aggregate",
  "time": {
    "rangePreset": "last-week"
  },
  "compare": "previous-period",
  "filters": {
    "territory": ["US", "CA"],
    "sourceReport": ["summary-sales"]
  },
  "groupBy": ["territory", "version"]
}
```

## Fields

### `dataset`

- `sales`
- `reviews`
- `finance`
- `analytics`
- `brief`

### `operation`

- `records`
- `aggregate`
- `compare`
- `brief`

### `time`

Supported keys:

- `datePT`
- `startDatePT`
- `endDatePT`
- `rangePreset`
- `year`
- `fiscalMonth`
- `fiscalYear`

Supported presets:

- `last-day`
- `last-7d`
- `last-week`
- `last-30d`
- `last-month`
- `year-to-date`
- `previous-week`
- `previous-month`

### `compare`

- `previous-period`
- `week-over-week`
- `month-over-month`
- `year-over-year`
- `custom`

### `compareTime`

Use only with `compare: "custom"`.

### `filters`

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

### `groupBy`

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

## Examples

- [`examples/queries/sales-aggregate-last-week.json`](../examples/queries/sales-aggregate-last-week.json)
- [`examples/queries/reviews-compare-last-week.json`](../examples/queries/reviews-compare-last-week.json)
- [`examples/queries/finance-aggregate-month.json`](../examples/queries/finance-aggregate-month.json)
- [`examples/queries/analytics-records-last-week.json`](../examples/queries/analytics-records-last-week.json)
- [`examples/queries/brief-weekly.json`](../examples/queries/brief-weekly.json)
