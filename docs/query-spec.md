# Query Spec

`app-connect-data-cli query run --spec <file|->` 接收 JSON。

## Schema

```json
{
  "kind": "snapshot",
  "source": "sales",
  "filters": {
    "rangePreset": "last-week",
    "territory": "US",
    "device": "iPhone",
    "limit": 10
  }
}
```

## `kind`

- `snapshot`
- `modules`
- `health`
- `trend`
- `top-products`
- `reviews.list`
- `reviews.summary`

## `source`

只对这些 `kind` 生效：

- `snapshot`
- `trend`
- `top-products`

可选值：

- `sales`
- `finance`

默认值：

- `sales`

## `filters`

时间字段三选一：

- `datePT`: `YYYY-MM-DD`
- `startDatePT` + `endDatePT`
- `rangePreset`

其他字段：

- `territory`
- `device`
- `limit`

## 示例

见：

- [`examples/queries/snapshot-30d.json`](../examples/queries/snapshot-30d.json)
- [`examples/queries/finance-reconcile-month.json`](../examples/queries/finance-reconcile-month.json)
- [`examples/queries/reviews-summary.json`](../examples/queries/reviews-summary.json)
- [`examples/queries/top-products-us.json`](../examples/queries/top-products-us.json)
