# Capabilities

This CLI only exposes Apple-supported, read-only reporting capabilities.

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
  - `version`
  - `territory`
  - `device`
  - `sku`
  - `subscription`
  - `sourceReport`

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
  - `app`
  - `territory`
  - `sku`
  - `sourceReport`

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
  - `version`
  - `territory`
  - `device`
  - `platform`
  - `sourceReport`

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
- Reviews are limited to Apple-provided review fields.
- Analytics may return waiting, privacy, or completeness warnings.
- First analytics access may create an Apple report request and wait for Apple to generate instances.
