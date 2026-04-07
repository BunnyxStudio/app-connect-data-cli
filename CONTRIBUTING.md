# Contributing

Thanks for contributing to `app-connect-data-cli`.

## Development environment

- macOS
- Xcode 26+
- Swift 6.2+

## Local development

```bash
swift build
swift test
./.build/debug/app-connect-data-cli --help
```

## Before opening a pull request

Please run at least:

```bash
swift build
swift test
```

If you change CLI behavior, also update:

- `README.md`
- `docs/`
- `examples/queries/`

## Project scope

This repository accepts contributions in these areas:

- App Store Connect data fetching
- Report parsing
- File-based caching
- Aggregation and query flows
- Review sync and summaries
- CLI output and agent-facing interfaces

This repository is not intended for:

- iOS app UI
- Widgets
- StoreKit monetization logic
- App Store release automation

## Issue labels

Each issue should use these label groups when possible:

- `type/*`
- `priority/*`
- `difficulty/*`

Common values:

- `type/bug`
- `type/feature`
- `priority/p1`
- `priority/p2`
- `difficulty/easy`
- `difficulty/medium`
- `difficulty/hard`

## Contribution license

By submitting a contribution, you agree that your contribution will be licensed under the Apache License, Version 2.0, together with the rest of the project.

If your change adds or modifies attribution material, keep the existing project attribution in `NOTICE`.

## Security requirements

Do not commit:

- `.p8` files
- private keys
- full bearer tokens
- raw logs with sensitive fields

If you need to reproduce an auth issue, redact secrets first.
