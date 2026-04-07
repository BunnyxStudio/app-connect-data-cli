# Changelog

## 0.1.0

- 初始化开源仓库结构
- 抽出 `ACDCore`
- 新增 `ACDAnalytics`
- 新增 `app-connect-data-cli`
- 支持 auth / sync / query / reviews / doctor / cache
- 新增 JSON-first `query run --spec`

## Unreleased

- 仓库名调整为 `app-connect-data-cli`
- CLI 改为直查优先
- 新增 `--date` / `--from` / `--to` / `--range`
- `query` 和 `reviews` 在有凭据时按需自动拉取数据
- `sync` 降为高级预热入口
