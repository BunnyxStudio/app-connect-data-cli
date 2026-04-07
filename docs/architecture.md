# Architecture

仓库分三层。

## `ACDCore`

负责最底层能力：

- JWT 签名
- `.p8` 导入
- ASC HTTP client
- 报表下载
- 报表解析
- 评论接口
- PT 时间范围解析

这一层不关心 CLI。
也不关心 UI。

## `ACDAnalytics`

负责纯数据层：

- 原始报表 cache
- manifest
- FX cache
- 聚合计算
- health / snapshot / modules / trend / top-products
- 评论摘要

这一层只读本地文件。
不依赖 SwiftData。

## `ACDCLI`

负责用户入口：

- 配置解析
- 时间参数解析
- 按需补数据
- 输出格式
- agent query spec

## 数据流

1. 用户直接执行 `query` 或 `reviews`
2. CLI 先解析 `--date / --from / --to / --range`
3. 有凭据时，CLI 按需拉取需要的报表或评论
4. 原始数据写入 `.app-connect-data-cli/cache/`
5. `ACDAnalytics` 读取 cache 并聚合
6. CLI 输出 `json` / `table` / `markdown`

`sync` 仍然存在。
但它只是高级预热入口，不是默认流程。
