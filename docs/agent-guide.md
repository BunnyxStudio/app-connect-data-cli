# Agent Guide

如果你是外部 agent，推荐只走这条路径：

```bash
acd query run --spec <file|-> --output json
```

原因很简单：

- 输出结构稳定
- 不需要猜 flags
- 更适合把查询模板版本化

## 推荐流程

1. 先做 `sync`
2. 再做 `query run`
3. 只消费 JSON

## 示例

### health

```json
{
  "kind": "health",
  "filters": {}
}
```

### snapshot

```json
{
  "kind": "snapshot",
  "source": "sales",
  "filters": {
    "startDatePT": "2026-03-01",
    "endDatePT": "2026-03-30"
  }
}
```

### reviews summary

```json
{
  "kind": "reviews.summary",
  "filters": {}
}
```

## 注意

- `query` 命令默认只读本地 cache
- `sync` 和 `reviews respond` 需要 ASC 凭据
- 如果 cache 为空，`health` 会返回 low confidence 和缺失项
