# FlowWage Gap-Close Report (Against `docs/requirements.md`)

Last updated: 2026-05-03

## 1) Implemented + Outcome-Proven

- Persona identity gate path:
  - `persona/check-verification-status`
  - `persona/get-cleared-corridors`
  - `persona/get-transaction-limits`
  - `persona/create-inquiry`
  - `persona/subscribe-verification-webhook`
  - Proven in workflow runs with successful node execution and output payloads.

- XMTP plugin path:
  - `xmtp/subscribe-to-inbox`
  - `xmtp/parse-payment-intent`
  - `xmtp/send-message`
  - `xmtp/send-transaction-receipt`
  - Proven in workflow runs with successful node execution and message metadata captured in execution logs.

- Offramp decision + conversion intent path:
  - `offramp/get-supported-corridors`
  - `offramp/get-best-quote`
  - `offramp/get-rate-history`
  - `offramp/trigger-conversion`
  - `offramp/get-conversion-status`
  - Proven as provider API flow execution (quote/trigger/status), with references captured from logs.

- Superchain route intelligence path:
  - `superchain/get-supported-routes`
  - `superchain/get-route-quote`
  - `superchain/initiate-transfer`
  - `superchain/poll-transfer-status`
  - Proven for route/transfer lifecycle API flow and status payloads.

## 2) Implemented But Not Fully Outcome-Proven Yet

- Deterministic “money moved” proof for every financial leg in one single run:
  - On-chain tx hash for all intended transfer/write legs
  - Explorer URL for each hash
  - Recipient-side XMTP inbox screenshot/confirmation for every expected message
  - End-state accounting report (before/after balances + conversion settlement state)

- Yield deployment as a finalized production leg:
  - Requirement asks for real yield deployment proof, but current suite does not enforce a dedicated write-to-yield step with mandatory tx hash output in all branches.

## 3) Not Implemented (or intentionally out of current scope)

- Guaranteed fiat settlement attestation from provider (bank/mobile-money arrival) within test run window.
  - Providers can return conversion intent/processing states; final fiat settlement usually completes asynchronously outside short demo run windows.

## 4) What Was Added Now To Close Evidence Gaps

- `flowwage_workflow/run_full_flow_suite.sh` now generates:
  - `SUITE_LOG=...` (human-readable run log)
  - `SUITE_REPORT=...report.json` (structured proof artifact)
- The structured report captures, per workflow part:
  - execution status
  - discovered tx hashes
  - XMTP message IDs / conversation IDs
  - conversion references
  - transfer proof fields (e.g., depositId/fill references)
  - node-level outputs for auditability

## 5) Final Step To Reach “Demo-Ready Financial Proof”

Use funded wallet + live testnet-ready integrations and run:

```bash
flowwage_workflow/run_full_flow_suite.sh
```

Then verify in the produced report:
- each intended money-moving node has tx hash/reference evidence
- those hashes resolve in OP Sepolia explorer
- XMTP message IDs map to messages visible in recipient wallet inbox.
