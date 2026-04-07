# Security

If you discover a security issue, please do not open a public issue with sensitive details.

Contact the maintainer privately first, or open a minimal placeholder issue without exposing secrets.

## Privacy model

This project does not operate a project-owned backend.

- The `.p8` key is read from a local file path only
- The key material is used in memory for JWT signing
- The CLI does not save the `.p8` contents to config, cache, logs, or generated output
- Repo-local cache and config live under `.app-connect-data-cli/`, which is git-ignored

The CLI talks directly to Apple App Store Connect endpoints for report and review access.

For FX normalization, it may also call the Frankfurter FX API with only date and currency metadata.
Those requests do not include your `.p8` file, JWT, vendor number, review text, or raw report contents.

## Sensitive data in this repository

- `AuthKey_XXXXXX.p8`
- JWT bearer tokens
- App Store Connect account identifiers
- Real cached report, finance, and review data

## Logging and screenshots

Please redact the following before sharing logs or screenshots:

- `issuerID`
- `keyID`
- `vendorNumber`
- Any token or authorization header
- Any local absolute path that reveals identity or account structure

## Safe defaults

- Do not commit credentials
- Do not commit `.p8` files
- Do not upload real cached business data to issues
- Keep `config.json` and `.p8` files owner-readable only
