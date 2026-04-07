# Changelog

## Unreleased

- No unreleased changes yet.

## 0.1.1 - 2026-04-07

- 项目显示名更新为 `App Store Connect Data CLI`
- 保留稳定标识 `adc`、仓库 slug `app-connect-data-cli` 和 `.app-connect-data-cli` 本地目录
- 调整 README、CONTRIBUTING、NOTICE 和 Homebrew 文案
- 修正 CONTRIBUTING 中的本地调试命令为 `./.build/debug/adc --help`

## 0.1.0 - 2026-04-07

- 初始化开源仓库结构
- 抽出 `ACDCore`
- 新增 `ACDAnalytics`
- 新增 `App Store Connect Data CLI`
- 支持 auth / sync / query / reviews / doctor / cache
- 新增 JSON-first `query run --spec`
- 仓库名调整为 `app-connect-data-cli`
- CLI 改为直查优先
- 新增 `--date` / `--from` / `--to` / `--range`
- `query` 和 `reviews` 在有凭据时按需自动拉取数据
- `sync` 降为高级预热入口
- 许可证从 MIT 调整为 Apache-2.0，并新增 `NOTICE` 署名要求
- 新增 `brief` / `overview` 多表摘要
- 新增 Homebrew tap 安装支持
