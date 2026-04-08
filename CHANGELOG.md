# Changelog

## Unreleased

- No unreleased changes yet.

## 0.1.5 - 2026-04-08

- 修复 `brief` / `overview` 在部分环境下出现 `freed pointer was not the last allocation` 崩溃
- 将摘要构建阶段改为稳定优先执行路径，避免高并发查询触发运行时内存错误

## 0.1.4 - 2026-04-08

- 修复并发场景下 `DateFormatter` 非线程安全导致的 `brief` / `overview` 进程崩溃风险
- 为维护者新增 Homebrew 自动发布链路：
  - 本仓库发版后自动创建 `homebrew-tap` 升级 PR
  - tap 仓库在 `brew test-bot` 通过后自动标记 `pr-pull`

## 0.1.3 - 2026-04-08

- 校验 `source-report` 输入并补齐 report-not-ready 警告透传
- 当订阅报表返回 `Invalid vendor number specified` 时，`brief` / `overview` 自动回退为仅拉取 `summary-sales`

## 0.1.2 - 2026-04-07

- 修正 `SALES/SUMMARY/DAILY` 请求版本为 `1_0`
- 避免部分账号在 `brief daily` / `overview daily` 上触发 `Invalid vendor number specified`

## 0.1.1 - 2026-04-07

- 项目显示名更新为 `App Store Connect Data CLI`
- 仓库 slug 更新为 `app-store-connect-data-cli`
- 保留稳定标识 `adc` 和 `.app-connect-data-cli` 本地目录
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
