# FlowWage Autonomous Stablecoin Lifecycle Workflow

## 1) Objective

Automate the full lifecycle of stablecoin income from the instant funds are detected to final execution of:

- liquidity retention
- yield deployment
- fiat off-ramp conversion
- recurring obligations
- compliance-gated resume flows
- user notifications and receipts

This specification maps directly to KeeperHub plugin actions and workflow graph behavior.

---

## 2) Scope

### In Scope

1. Income detection from:
   - Sablier events
   - Superfluid events
   - Request Finance invoice settlement
   - fallback scheduled polling
2. Allocation split:
   - liquid %
   - yield %
   - convert %
3. Off-ramp quote/deferral logic.
4. Persona KYC gate before conversion execution.
5. Deferred queue and webhook-based resume after KYC completion.
6. Cross-chain route selection for yield/off-ramp execution.
7. Notification and signed receipt delivery.
8. Weekly rebalance checks.

### Out of Scope (for first production cut)

1. Advanced portfolio optimization beyond rule-based thresholds.
2. Dynamic tax estimation/reporting.
3. Multi-tenant admin dashboard customization.
4. Non-EVM chain execution.

---

## 3) Actors

1. **End User (Freelancer/Worker)**  
   configures preferences once and receives status updates.

2. **FlowWage Workflow**  
   autonomous orchestration layer running in KeeperHub.

3. **External Service Providers**
   - Persona (KYC)
   - Offramp providers/aggregators
   - Sablier/Superfluid/Request Finance
   - XMTP (receipts/intents)

---

## 4) Required User Inputs (Minimum Contract)

### 4.1 Identity + Compliance

- `user_reference_id` (stable external id, e.g. `flowwage-user-003`)
- Persona template id (currently: `itmpl_A41AqAmnmHDJ7Rm6Q3ur1BbnaEwwXe`)
- optional `persona_inquiry_id` cache after inquiry creation

### 4.2 Wallet & Chain

- `primary_wallet_address`
- allowed chains (e.g. `base`, `optimism`, `op-sepolia`, `arbitrum`, `polygon`)

### 4.3 Allocation Policy

- `liquid_percent` (0-100)
- `yield_percent` (0-100)
- `convert_percent` (0-100)
- must sum to 100
- `min_income_trigger_usd` (e.g. `20`)

### 4.4 Off-ramp Policy

- `target_country_code` (e.g. `NG`)
- `target_fiat_currency` (e.g. `NGN`)
- `max_deferral_hours` (e.g. `72`)
- `rerate_interval_hours` (e.g. `6`)
- `min_rate_delta_to_execute` (e.g. `0.5%` from rolling baseline)

### 4.5 Recurring Rules (Optional)

- list of obligations:
  - `recipient`
  - `token`
  - `amount` or `%`
  - trigger condition (e.g. every income > 300 USDC)

### 4.6 Notification Preferences
