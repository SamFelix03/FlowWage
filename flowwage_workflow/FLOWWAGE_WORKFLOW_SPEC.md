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

- primary channel (`xmtp`, `telegram`, `both`)
- recipient endpoints (wallet addr for XMTP, chat id for Telegram)

---

## 5) Plugin Actions Used

### 5.1 Income/Event Layer

- `sablier/subscribe-to-stream-events`
- `sablier/get-unlockable-amount`
- `sablier/get-stream-state`
- `superfluid/get-stream-events`
- `superfluid/get-real-time-balance`
- `request-finance/subscribe-invoice-events`
- `request-finance/get-payment-history`

### 5.2 Allocation + Routing + Execution

- `offramp/get-best-quote`
- `offramp/get-rate-history`
- `offramp/trigger-conversion`
- `offramp/get-conversion-status`
- `offramp/get-supported-corridors`
- `superchain/get-route-quote`
- `superchain/initiate-transfer`
- `superchain/poll-transfer-status`
- `web3/check-token-balance`
- `web3/transfer-token` (or equivalent transfer action)

### 5.3 Persona Gate

- `persona/check-verification-status`
- `persona/create-inquiry`
- `persona/get-cleared-corridors`
- `persona/get-transaction-limits`
- `persona/subscribe-verification-webhook`

### 5.4 Messaging

- `xmtp/send-message`
- `xmtp/send-transaction-receipt`
- `xmtp/parse-payment-intent`
- `xmtp/subscribe-to-inbox`

---

## 6) Workflow Topology

## 6.1 Main Path (Income Arrival)

1. Trigger income event.
2. Read balances + stream state.
3. Run allocation engine.
4. Run Persona gate if conversion bucket > 0.
5. Execute sequencing:
   - settle/withdraw stream funds
   - route cross-chain if required
   - deploy yield
   - off-ramp conversion
   - recurring payouts
6. Publish notifications + receipts.
7. Persist execution log/state.

## 6.2 Deferred Path (KYC/Rate Deferral)

1. If KYC not approved:
   - create Persona inquiry
   - send inquiry link
   - move conversion bucket to deferred queue.
2. Resume trigger:
   - Persona webhook completion OR periodic recheck.
3. Re-evaluate status and corridor eligibility.
4. Execute deferred conversion when conditions satisfied.

## 6.3 Weekly Maintenance Path

1. Read active yield positions.
2. Compare route/net APY alternatives.
3. Rebalance only if threshold crossed.

---

## 7) Decision Logic

## 7.1 Allocation

Given:

- `income_amount`
- policy percentages

Compute:

- `liquid_amt = income * liquid_percent`
- `yield_amt = income * yield_percent`
- `convert_amt = income * convert_percent`

## 7.2 KYC Gate

If `convert_amt > 0`:

1. `persona/check-verification-status` (prefer `inquiryId`; fallback `referenceId`)
2. Require:
   - status approved
   - corridor supported
   - limits sufficient

Else:

- skip Persona branch entirely.

## 7.3 Rate Deferral

If quote is below baseline by policy threshold:

- defer conversion
- re-quote every `rerate_interval_hours`
- force execute at `max_deferral_hours`

---

## 8) State Machine (Conversion Bucket)

States:

1. `pending_kyc`
2. `pending_rate_window`
3. `ready_to_execute`
4. `executing`
5. `settled`
6. `failed`

Transitions:

- `pending_kyc -> ready_to_execute` when Persona approved.
- `pending_rate_window -> ready_to_execute` when rate condition met or timeout.
- `ready_to_execute -> executing` when sequencer starts conversion.
- `executing -> settled` on provider settled status.
- any state -> `failed` on terminal error (with reason, retry policy).

---

## 9) Data Contracts (Canonical)

## 9.1 Trigger Event Payload

```json
{
  "event_type": "income_detected",
  "source": "superfluid|sablier|request_finance|polling",
  "wallet_address": "0x...",
  "token": "USDC",
  "amount": "250.00",
  "chain": "base",
  "tx_hash": "0x...",
  "timestamp": "ISO8601"
}
```

## 9.2 Allocation Output

```json
{
  "income_amount": "250.00",
  "liquid_amt": "75.00",
  "yield_amt": "100.00",
  "convert_amt": "75.00",
  "routing_plan": {
    "yield_route": "base->optimism",
    "offramp_provider": "best_quote_provider_x"
  }
}
```

## 9.3 Deferred Queue Record

```json
{
  "queue_id": "dq_...",
  "user_reference_id": "flowwage-user-003",
  "convert_amt": "75.00",
  "fiat_currency": "NGN",
  "status": "pending_kyc",
  "persona_inquiry_id": "inq_...",
  "created_at": "ISO8601",
  "retry_count": 0
}
```

---

## 10) Failure Handling

## 10.1 Categorization

1. `transient_external`
   - rate limits
   - network timeouts
   - temporary upstream errors

2. `policy_block`
   - kyc not approved
   - unsupported corridor
   - exceeded limit

3. `hard_config_error`
   - missing integration creds
   - missing wallet
   - malformed input

## 10.2 Retries

- Transient errors: exponential backoff, bounded attempts.
- Policy blocks: do not hammer retries; move to deferred state.
- Hard config errors: fail fast + alert.

## 10.3 Idempotency

- every execution step carries deterministic idempotency key:
  - `user_reference_id + source_tx_hash + action_slug + bucket_type`
- duplicate event ingestion must not double-spend buckets.

---

## 11) Security & Compliance

1. No PII in logs beyond required references.
2. Persona secrets only in encrypted integration config.
3. Webhook signature verification mandatory.
4. Receipt messages should avoid sensitive personal content.
5. Every transaction action logged with execution id and traceable audit link.

---

## 12) Typical Real User Example (End-to-End)

## Persona

**User:** Amina, freelancer in Lagos  
**Wallet:** receives USDC on Base  
**Preferences:** 30% liquid, 40% yield, 30% convert to NGN  
**Min trigger:** 50 USDC  
**Off-ramp rule:** wait up to 72h if quote worse than 0.5% vs baseline  
**Notification:** XMTP + Telegram

## Timeline

1. Amina receives `500 USDC` from a client invoice.
2. Workflow trigger fires from Request Finance payment event.
3. Allocation:
   - liquid `150`
   - yield `200`
   - convert `150`
4. Persona check:
   - status not approved
5. Workflow creates inquiry with template `itmpl_A41AqAmnmHDJ7Rm6Q3ur1BbnaEwwXe`.
6. Amina receives verification link and completes KYC on phone.
7. Persona webhook fires completion.
8. Resume conversion queue:
   - re-check status + limits + corridor
   - now approved
9. Sequencer:
   - deploys yield bucket to best net route
   - fetches off-ramp best quote for NGN
   - executes conversion of `150 USDC`
10. Receipt sent:
    - tx hash(es)
    - converted amount
    - provider status
    - updated wallet/yield summary

Expected outcome:

- Amina does zero manual protocol operations.
- Liquidity, yield, and local cashflow are all handled automatically.

---

## 13) Implementation Notes for KeeperHub Graph Build

1. Keep Persona inquiry id in workflow context/store after create call.
2. Use inquiryId-based status checks for deterministic behavior.
3. Branch conversion pipeline behind Persona gate node.
4. Keep execution coordinator deterministic and idempotent.
5. Add explicit dead-letter state for deferred items that exceed retries.

---

## 14) Acceptance Criteria

1. Income trigger causes allocation within one run cycle.
2. If KYC not approved, inquiry created successfully and conversion paused.
3. On approval webhook, deferred conversion resumes automatically.
4. Off-ramp conversions respect rate deferral policy.
5. Yield deployment and conversion are independently traceable.
6. Notifications include success/failure receipts with execution id.
7. Duplicate income events do not duplicate payouts/conversions.

