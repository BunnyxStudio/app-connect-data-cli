# Contributing

感谢你愿意参与 `acd`。

## 开发环境

- macOS
- Xcode 26+
- Swift 6.2+

## 本地开发

```bash
swift build
swift test
./.build/debug/acd --help
```

## 提 PR 前

请至少完成这几步：

```bash
swift build
swift test
```

如果你改了 CLI 行为，也请同步更新：

- `README.md`
- `docs/`
- `examples/queries/`

## 代码范围

这个仓库只接收这些方向的改动：

- App Store Connect 数据下载
- 报表解析
- 文件缓存
- 聚合与查询
- 评论同步与摘要
- CLI 输出与 agent 入口

默认不接收这些方向：

- iOS app UI
- Widget
- StoreKit 付费逻辑
- App Store 发布自动化

## Issue 标签

建议每个 issue 都有三类标签：

- `type/*`
- `priority/*`
- `difficulty/*`

推荐值：

- `type/bug`
- `type/feature`
- `priority/p1`
- `priority/p2`
- `difficulty/easy`
- `difficulty/medium`
- `difficulty/hard`

## 安全要求

不要提交：

- `.p8`
- 私钥
- 完整 bearer token
- 含敏感字段的原始日志

如果你需要复现 auth 问题，请先脱敏。
