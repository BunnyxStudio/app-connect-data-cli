# Architecture

仓库分三层：

## `ACDCore`

负责最底层能力：

- JWT 签名
- `.p8` 导入
- ASC HTTP client
- 报表下载
- 报表解析
- 评论接口

这一层不关心 CLI。
也不关心数据库和 UI。

## `ACDAnalytics`

负责纯数据层：

- manifest
- 原始报表缓存
- FX 缓存
- 聚合计算
- health / snapshot / trend / top-products
- 评论摘要

这一层不依赖 SwiftData。
只读本地文件。

## `ACDCLI`

负责命令行：

- 配置解析
- 命令路由
- 输出格式
- agent query spec

## 数据流

1. `sync` 命令调用 `ACDCore`
2. 原始报表写入 `.acd/cache/reports`
3. manifest 记录下载元数据
4. `query` 命令调用 `ACDAnalytics`
5. `ACDAnalytics` 读取报表并按需做 FX 转换和聚合
6. `ACDCLI` 把结果输出为 `json` / `table` / `markdown`
