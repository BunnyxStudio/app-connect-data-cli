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

Use only the selectors supported by the current dataset.

- `sales`, `reviews`, `analytics`
  - `datePT`
  - `startDatePT`
  - `endDatePT`
  - `rangePreset`
  - `year`
- `finance`
  - `fiscalMonth`
  - `fiscalYear`
  - `rangePreset`
  - `year` is accepted as a compatibility alias for `fiscalYear`
- `brief`
  - `rangePreset` only

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

`compare` and `compareTime` are only valid when `operation` is `compare`.

- `previous-period`
- `week-over-week`
- `month-over-month`
- `year-over-year`
- `custom`

`compareTime` is valid only with `compare: "custom"`.

## Filters

Use only the filters supported by the current dataset.

- `sales`
  - all sales reports:
    - `app`
    - `territory`
    - `currency`
    - `device`
    - `sku`
    - `sourceReport`
  - `summary-sales`, `pre-order`, `subscription-offer-redemption` only:
    - `version`
  - `subscription`, `subscription-event`, `subscriber` only:
    - `subscription`
- `reviews`
  - `app`
  - `territory`
  - `rating`
  - `responseState`
  - `sourceReport`
- `finance`
  - `territory`
  - `currency`
  - `sku`
  - `sourceReport`
- `analytics`
  - all analytics reports:
    - `app`
    - `territory`
    - `device`
    - `platform`
    - `sourceReport`
  - `acquisition`, `usage`, `performance` only:
    - `version`

For `sales` and `finance`, `currency` matches source rows.

Displayed monetary values are still normalized to the configured reporting currency when FX data is available.

## Group by

`groupBy` is only valid with `aggregate` and `compare`.

Unsupported values now fail fast.

Common values:

- `day`
- `week`
- `month`
- `fiscalMonth`
- `app`
- `territory`
- `reportType`
- `sourceReport`

Dataset-specific values:

- `sales`
  - `version` for `summary-sales`, `pre-order`, `subscription-offer-redemption`
  - `currency`, `device`, `sku` across all sales report families
  - `subscription` for `subscription`, `subscription-event`, `subscriber`
- `reviews`: `rating`, `responseState`
- `finance`: `currency`, `sku`
- `analytics`
  - `device`, `platform` across all analytics report families
  - `version` for `acquisition`, `usage`, `performance`

If you request multiple `sales` source reports for `aggregate` or `compare`, include `sourceReport` or `reportType` in `groupBy`.

Finance defaults to `financial` when `sourceReport` is omitted.

If you request both `financial` and `finance-detail` for `aggregate` or `compare`, include `sourceReport` or `reportType` in `groupBy`.

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

Shortcut mapping:

- `adc overview daily` and `adc brief daily` map to `last-day`
- `adc overview weekly` and `adc brief weekly` map to `this-week`
- `adc overview monthly` and `adc brief monthly` map to `this-month`

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
