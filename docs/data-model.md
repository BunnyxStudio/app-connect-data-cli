# Data Model

## Raw inputs

- `SALES/SUMMARY`
- `SALES/SUMMARY_MONTHLY`
- `SUBSCRIPTION/SUMMARY`
- `SUBSCRIPTION_EVENT/SUMMARY`
- `SUBSCRIBER/DETAILED`
- `FINANCIAL/ZZ`
- `FINANCE_DETAIL/Z1`
- customer reviews

## Time model

所有日级时间都按 PT。

用户可以用三种方式给时间：

- `datePT`
- `startDatePT` + `endDatePT`
- `rangePreset`

`rangePreset` 支持：

- `today`
- `last-day`
- `last-week`
- `last-7d`
- `last-30d`
- `this-week`
- `this-month`
- `last-month`

## Core outputs

### `DashboardSnapshot`

- units
- installs
- purchases
- refunds
- proceeds by currency
- trend
- top products

### `DashboardModuleSnapshot`

- overview
- growth
- subscription
- finance
- dataHealth

### `DataHealthSnapshot`

- sales as-of
- subscription as-of
- finance as-of
- coverage counts
- lag counts
- confidence
- issues

### `ReviewsSummarySnapshot`

- total
- average rating
- histogram
- territory breakdown
- unresolved responses
