# apple-connect-trends-cli

`acd` 是一个从 ACD 项目里抽出来的开源 Swift CLI。

它专注于 App Store Connect 的数据分析层。
它做认证、报表下载、评论同步、缓存、聚合查询。
它默认输出 JSON，适合 agent、脚本和 CI。

它不是一个全能版 `asc` 替代品。
它不处理发布、TestFlight、metadata、证书、截图上传。
如果你要做完整发版流程，请优先看 [rudrankriyam/App-Store-Connect-CLI](https://github.com/rudrankriyam/App-Store-Connect-CLI)。

## 它是什么

- 一个 macOS-first 的 Swift CLI
- 一个可复用的 `ACDCore` + `ACDAnalytics` 单仓库
- 一个面向 agent 的 JSON-first 查询入口
- 一个本地缓存驱动的数据分析工具

## 它不是什么

- 不是 ACD iOS app 本体
- 不是 SwiftUI dashboard
- 不是付费、Widget、通知、Onboarding 代码集合
- 不是完整 App Store 发布平台

## 为什么和 `asc` 不同

`asc` 的目标是覆盖更广的 App Store Connect 工作流。

`acd` 的目标更窄。
它只关心报表和评论这条链路：

- 拉 Sales / Subscription / Finance 报表
- 解析 TSV / GZ
- 做本地缓存
- 统一 PT 时间口径
- 输出 snapshot / modules / health / trend / top-products
- 给 agent 一个稳定的 `query run --spec` 入口

## 5 分钟 Quick Start

### 1. 构建

```bash
git clone <your-repo-url> apple-connect-trends-cli
cd apple-connect-trends-cli
swift build -c release
```

### 2. 配置

支持四个环境变量：

```bash
export ASC_ISSUER_ID="YOUR_ISSUER_ID"
export ASC_KEY_ID="YOUR_KEY_ID"
export ASC_VENDOR_NUMBER="YOUR_VENDOR_NUMBER"
export ASC_P8_PATH="/absolute/path/AuthKey_XXXXXX.p8"
```

也支持配置文件：

- repo-local: `./.acd/config.json`
- user-level: `~/.acd/config.json`

示例：

```json
{
  "issuerID": "YOUR_ISSUER_ID",
  "keyID": "YOUR_KEY_ID",
  "vendorNumber": "YOUR_VENDOR_NUMBER",
  "p8Path": "/absolute/path/AuthKey_XXXXXX.p8"
}
```

优先级固定为：

`flags > env > ./.acd/config.json > ~/.acd/config.json`

### 3. 验证凭据

```bash
./.build/release/acd auth validate --output table
```

### 4. 第一次 sync

```bash
./.build/release/acd sync sales --days 7
./.build/release/acd sync subscriptions --days 7
./.build/release/acd sync finance --months 2
./.build/release/acd sync reviews --total-limit 200
```

### 5. 第一次 query

```bash
./.build/release/acd query snapshot --source sales --output table
./.build/release/acd query modules --output markdown
./.build/release/acd query health --output json
```

## Agent 用法

最稳定的入口是：

```bash
acd query run --spec <file|-> --output json
```

示例：

```bash
cat examples/queries/snapshot-30d.json | ./.build/release/acd query run - --output json
```

支持的 `kind`：

- `snapshot`
- `modules`
- `health`
- `trend`
- `top-products`
- `reviews.list`
- `reviews.summary`

详情见 [docs/query-spec.md](docs/query-spec.md) 和 [docs/agent-guide.md](docs/agent-guide.md)。

## 常用命令

```bash
acd auth validate

acd sync sales
acd sync subscriptions
acd sync finance
acd sync reviews

acd query snapshot
acd query modules
acd query health
acd query trend
acd query top-products
acd query run --spec -

acd reviews list
acd reviews summary
acd reviews respond REVIEW_ID --body "Thanks for the feedback."

acd doctor probe
acd doctor audit
acd doctor reconcile

acd cache clear
```

## 缓存

默认不使用数据库。
只使用本地文件缓存。

- 如果当前目录存在 `./.acd/`，优先用 repo-local cache
- 否则使用 `~/.acd/cache/`

缓存内容包括：

- 原始报表
- manifest
- 评论快照
- FX rates

## 开发

```bash
swift build
swift test
./.build/debug/acd --help
```

## 支持与反馈

- 使用问题：GitHub Discussions
- Bug 和功能请求：GitHub Issues
- 安全问题：见 [SECURITY.md](SECURITY.md)
- 开发贡献：见 [CONTRIBUTING.md](CONTRIBUTING.md)

## License

MIT
