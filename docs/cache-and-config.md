# Cache And Config

## 配置加载顺序

1. flags
2. environment variables
3. `./.app-connect-data-cli/config.json`
4. `~/.app-connect-data-cli/config.json`

## 支持的环境变量

- `ASC_ISSUER_ID`
- `ASC_KEY_ID`
- `ASC_VENDOR_NUMBER`
- `ASC_P8_PATH`

## cache 位置

- repo-local: `./.app-connect-data-cli/cache/`
- user-level: `~/.app-connect-data-cli/cache/`

CLI 会优先使用当前仓库里的 repo-local 目录。
没有时再回退到用户级目录。

## cache 内容

- `reports/`
- `manifest.json`
- `reviews/latest.json`
- `fx-rates.json`

## cache 语义

- cache 是内部实现
- 默认查询会优先复用已有文件
- `--refresh` 会强制重新拉取
- `--offline` 会禁止联网

## 清理 cache

```bash
app-connect-data-cli cache clear
```
