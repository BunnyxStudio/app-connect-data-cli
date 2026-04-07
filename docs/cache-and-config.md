# Cache And Config

## Config resolution

The CLI loads config in this order:

1. Flags
2. Environment variables
3. `./.app-connect-data-cli/config.json`
4. `~/.app-connect-data-cli/config.json`

## Supported environment variables

- `ASC_ISSUER_ID`
- `ASC_KEY_ID`
- `ASC_VENDOR_NUMBER`
- `ASC_P8_PATH`
- `ADC_REPORTING_CURRENCY`
- `ADC_DISPLAY_TIMEZONE`

## Config fields

- `issuerID`
- `keyID`
- `vendorNumber`
- `p8Path`
- `reportingCurrency`
- `displayTimeZone`

## Local paths

- Repo-local base: `./.app-connect-data-cli/`
- User-level base: `~/.app-connect-data-cli/`

The CLI prefers the repo-local path when it exists.

Otherwise it falls back to the user-level path.

## Cache contents

- `reports/`
- `manifest.json`
- `reviews/latest.json`
- cached FX rate files

Analytics report downloads are stored locally as Apple returns them.

## Security rules

- `.p8` stays on the local machine
- Config and cache files must be owner-only
- The CLI should refuse unsafe files instead of silently relaxing permissions
- Apple credentials should not be passed through shell history when config or environment variables can be used instead

## User controls

- `--offline` reads local cache only
- `--refresh` re-fetches raw data from Apple
- `cache clear` removes local cache only
- `config currency show` prints the effective reporting currency
- `config currency set <CODE>` saves a default reporting currency to user config
- `config currency set <CODE> --local` saves a repo-local override
- `config timezone show` prints the effective display time zone
- `config timezone set <IANA_ID>` saves a default display time zone to user config
- `config timezone set <IANA_ID> --local` saves a repo-local override
