# Data Model

All public query commands map to one shared model.

## Request

```json
{
  "dataset": "sales",
  "operation": "aggregate",
  "time": {
    "rangePreset": "last-week"
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

## Filters

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

## Grouping

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

## Response

Every result returns:

- `dataset`
- `operation`
- `time`
- `filters`
- `source`
- `data`
- `comparison`
- `warnings`
- `tableModel`
