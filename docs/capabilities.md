# Capabilities

This CLI only exposes Apple-supported, read-only reporting capabilities.

Unless noted otherwise, filter names below use JSON/query-spec field names such as `sourceReport` and `responseState`.

The CLI flags use dashed names such as `--source-report`, `--response-state`, and `--app-version`.

## Included

### Sales and Trends reports

- Included status: `included`
- What you can query:
  - `SALES/SUMMARY`
  - `SALES/SUMMARY_MONTHLY`
  - `SUBSCRIPTION/SUMMARY`
  - `SUBSCRIPTION_EVENT/SUMMARY`
  - `SUBSCRIBER/DETAILED`
  - `PRE_ORDER/SUMMARY`
  - `SUBSCRIPTION_OFFER_CODE_REDEMPTION/SUMMARY`
- What you cannot query:
  - Free-form UI-only Trends pivots
  - User-level identity exports
  - `WIN_BACK_ELIGIBILITY` in v1
- Time support:
  - `datePT`
  - `startDatePT` / `endDatePT`
  - `rangePreset`
  - `year`
- Filters:
  - `app`
  - `territory`
  - `currency`
  - `device`
  - `sku`
  - `sourceReport`
- Notes:
  - If you combine multiple sales `sourceReport` values in `aggregate` or `compare`, group by `sourceReport` or `reportType`.
  - `summary-sales`, `pre-order`, and `subscription-offer-redemption` support `version`.
  - `subscription`, `subscription-event`, and `subscriber` support `subscription`.

### Customer reviews

- Included status: `included`
- What you can query:
  - Official review records
  - Rating, territory, app, and response-state breakdowns
  - Period comparison for count, average rating, reply rate, and low-rating ratio
- What you cannot query:
  - Review reply write actions
  - App version filter
  - User profile data
- Time support:
  - `datePT`
  - `startDatePT` / `endDatePT`
  - `rangePreset`
  - `year`
- Filters:
  - `app`
  - `territory`
  - `rating`
  - `responseState`
  - `sourceReport`

### Finance reports

- Included status: `included`
- What you can query:
  - `FINANCIAL`
  - `FINANCE_DETAIL`
  - Fiscal-month aggregates and comparisons
- What you cannot query:
  - Daily finance
  - Real-time finance
- Time support:
  - `fiscalMonth`
  - `fiscalYear`
  - `last-month`
  - `previous-month`
- Filters:
  - `territory`
  - `currency`
  - `sku`
  - `sourceReport`
- Notes:
  - Defaults to `FINANCIAL` when `sourceReport` is omitted.

### Apple Analytics Reports

- Included status: `included`
- What you can query:
  - `acquisition`
  - `engagement`
  - `usage`
  - `performance`
- What you cannot query:
  - Unsupported report families
  - UI-only analytics pivots
  - Instant data before Apple generates the first report instance
- Time support:
  - `datePT`
  - `startDatePT` / `endDatePT`
  - `rangePreset`
  - `year`
- Filters:
  - `app`
  - `territory`
  - `device`
  - `platform`
  - `sourceReport`
- Notes:
  - `engagement` does not support `version`.
  - `acquisition`, `usage`, and `performance` support `version`.

## Excluded

These App Store Connect capabilities are outside this CLI:

- Metadata management
- In-app purchase and subscription management
- Pricing management
- Build and TestFlight management
- Signing and provisioning
- User and access management
- Xcode Cloud
- Webhooks
- Release automation

## Operational notes

- Sales data availability depends on Apple report family and report cadence.
- Finance is fiscal-month based.
- Finance defaults to `financial` when `sourceReport` is omitted.
- `currency` filters select source rows, while displayed money is normalized to your configured reporting currency.
- Reviews are limited to Apple-provided review fields.
- Analytics may return waiting, privacy, or completeness warnings.
- First analytics access may create an Apple report request and wait for Apple to generate instances.
- Sales or reviews data being present does not guarantee analytics files are available yet.
