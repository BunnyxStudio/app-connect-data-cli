# Cache And Config

## 配置加载顺序

1. flags
2. environment variables
3. `./.acd/config.json`
4. `~/.acd/config.json`

## 支持的环境变量

- `ASC_ISSUER_ID`
- `ASC_KEY_ID`
- `ASC_VENDOR_NUMBER`
- `ASC_P8_PATH`

## cache 位置

优先规则：

- 如果当前目录存在 `./.acd/`，使用 repo-local cache
- 否则使用 `~/.acd/cache/`

## cache 内容

- `reports/`
- `manifest.json`
- `reviews/latest.json`
- `fx-rates.json`

## 清理 cache

```bash
acd cache clear
```
