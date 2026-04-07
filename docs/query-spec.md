# Query Spec

`acd query run --spec <file|->` 接收 JSON。

## Schema

```json
{
  "kind": "snapshot",
  "source": "sales",
  "filters": {
    "startDatePT": "2026-03-01",
    "endDatePT": "2026-03-30",
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

- `startDatePT`: `YYYY-MM-DD`
- `endDatePT`: `YYYY-MM-DD`
- `territory`
- `device`
- `limit`

## 示例

见：

- [`examples/queries/snapshot-30d.json`](../examples/queries/snapshot-30d.json)
- [`examples/queries/finance-reconcile-month.json`](../examples/queries/finance-reconcile-month.json)
- [`examples/queries/reviews-summary.json`](../examples/queries/reviews-summary.json)
- [`examples/queries/top-products-us.json`](../examples/queries/top-products-us.json)
