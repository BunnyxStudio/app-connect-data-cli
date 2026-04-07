# Security

如果你发现安全问题，请不要直接公开发 issue。

请私下联系维护者，或先提交一个不暴露细节的占位 issue。

## 本仓库的敏感信息

- `AuthKey_XXXXXX.p8`
- JWT bearer token
- App Store Connect 账号标识
- 任何包含真实财务数据的缓存文件

## 日志与截图要求

发日志前请先脱敏：

- `issuerID`
- `keyID`
- `vendorNumber`
- 任何 token
- 本地绝对路径里可能暴露身份的信息

## 默认安全原则

- 不把凭据写进 git
- 不把 `.p8` 放进 examples
- 不把真实业务缓存上传到 issue
