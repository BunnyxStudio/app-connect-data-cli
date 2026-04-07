# Agent Guide

推荐只走这一条：

```bash
app-connect-data-cli query run --spec <file|-> --output json
```

原因：

- 入口稳定
- 输出结构稳定
- 时间范围可以直接写在 spec 里
- 不需要先手动 `sync`

## 推荐流程

1. 生成一个 JSON spec
2. 直接调用 `query run --spec`
3. 默认让 CLI 自己按需拉数据
4. 只有明确要求离线时才加 `--offline`

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
    "rangePreset": "last-week",
    "territory": "US"
  }
}
```

### reviews summary

```json
{
  "kind": "reviews.summary",
  "filters": {
    "rangePreset": "last-week"
  }
}
```

## 注意

- `query` 和 `reviews` 默认会在有凭据时自动补齐所需数据
- `--offline` 才是纯本地读取
- `reviews respond` 一直需要 ASC 凭据
