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

## Core outputs

### `DashboardSnapshot`

基础汇总：

- units
- installs
- purchases
- refunds
- proceeds by currency
- trend
- top products

### `DashboardModuleSnapshot`

组合输出：

- overview
- growth
- subscription
- finance
- dataHealth

### `DataHealthSnapshot`

数据完整度和滞后情况：

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
