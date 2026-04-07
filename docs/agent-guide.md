# Agent Guide

The stable agent interface is:

```bash
app-connect-data-cli query run --spec <file|-> --output json
```

## Recommended flow

1. Build one `DataQuerySpec` JSON payload.
2. Pass it to `query run`.
3. Read the JSON response.
4. Treat `warnings` as real result data.

## Canonical JSON shape

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

## Time fields

- `datePT`
- `startDatePT`
- `endDatePT`
- `rangePreset`
- `year`
- `fiscalMonth`
- `fiscalYear`

## Comparison fields

- `compare`
- `compareTime`

Supported comparison modes:

- `previous-period`
- `week-over-week`
- `month-over-month`
- `year-over-year`
- `custom`

## Notes

- Use `--offline` only for cache-only reads.
- Use `--refresh` only when you need a fresh Apple fetch.
- Analytics queries may create an Apple report request on first use.
- Analytics responses may include privacy and completeness warnings.
