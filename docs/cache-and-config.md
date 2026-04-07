# Cache And Config

## Config resolution

The CLI loads credentials in this order:

1. Flags
2. Environment variables
3. `./.app-connect-data-cli/config.json`
4. `~/.app-connect-data-cli/config.json`

## Supported environment variables

- `ASC_ISSUER_ID`
- `ASC_KEY_ID`
- `ASC_VENDOR_NUMBER`
- `ASC_P8_PATH`

## Local paths

- Repo-local base: `./.app-connect-data-cli/`
- User-level base: `~/.app-connect-data-cli/`

The CLI prefers the repo-local path when it exists.
Otherwise it falls back to the user-level path.

## Cache contents

- `reports/`
- `manifest.json`
- `reviews/latest.json`

Analytics report downloads are stored locally as Apple returns them.

## Security rules

- `.p8` stays on the local machine
- Config and cache files must be owner-only
- The CLI should refuse unsafe files instead of silently relaxing permissions
- No config value should be echoed back in plain text

## User controls

- `--offline` reads local cache only
- `--refresh` re-fetches raw data from Apple
- `cache clear` removes local cache only
