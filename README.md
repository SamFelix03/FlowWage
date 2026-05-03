# FlowWage: Autonomous Stablecoin Payment Lifecycle Manager

FlowWage is a KeeperHub-native automation workflow for users who **earn in stablecoins** and need that money to do real work immediately: comply, route, deploy yield, off-ramp to fiat, and send private receipts.  
It converts a fragmented multi-app manual process into one execution graph with verifiable outputs.

## Table of Contents

1. [Workflow File](#workflow-file)
2. [Product Introduction](#product-introduction)
3. [Why This Is Necessary](#why-this-is-necessary)
4. [Architecture and Scope](#architecture-and-scope)
5. [Added Integrations and Why Each Was Required](#added-integrations-and-why-each-was-required)
6. [Deep Implementation Walkthrough (with code)](#deep-implementation-walkthrough-with-code)
7. [Plugin Functional Reference](#plugin-functional-reference)
8. [Route-by-Route Workflow Explanation](#route-by-route-workflow-explanation)
9. [How to Run from KeeperHub UI](#how-to-run-from-keeperhub-ui)
10. [Verification Checklist](#verification-checklist)
11. [Troubleshooting](#troubleshooting)
12. [Conclusion](#conclusion)

## Workflow File

- Importable E2E workflow JSON:
  - [flowwage_workflow/workflows/FLOWWAGE_FULL_E2E.workflow.json](https://github.com/SamFelix03/FlowWage/blob/master/flowwage_workflow/workflows/FLOWWAGE_FULL_E2E.workflow.json)

## Product Introduction

stablecoin income is growing, but post-receipt operations are still mostly manual. Users receive USDC, then separately handle compliance checks, chain routing, conversion timing, yield deployment, and notifications.

FlowWage unifies those steps in one keeper workflow:

1. Detect income context (invoice/stream/balance).
2. Parse encrypted payment intent.
3. Allocate funds by policy (liquid/yield/convert).
4. Enforce KYC gate before off-ramp.
5. Route and execute cross-chain transfer.
6. Deploy yield position.
7. Trigger and track fiat conversion.
8. Send wallet-native encrypted receipts.

## Why This Is Necessary

From the requirements narrative: a user paid in USDC often faces:

- idle funds earning nothing,
- manual corridor selection for conversion,
- failed off-ramp attempts due to compliance not being pre-validated,
- and poor traceability for what happened after payment.

Real-world example:

A freelancer in Lagos receives 800 USDC. They need NGN for expenses and want the rest earning yield. Without orchestration, this means manually checking KYC status, searching off-ramp rates, deciding chain movement, approving contracts, and documenting transaction proofs.  
FlowWage does this as one execution with structured outcomes (`depositTxnRef`, `conversionReference`, XMTP conversation/message proof).

## Architecture and Scope

This implementation uses a single full graph workflow:

- Entry and income context:
  - `request-finance/*`
  - `sablier/*`
  - `superfluid/*`
  - `web3/check-token-balance`
- Control/intent rail:
  - `xmtp/subscribe-to-inbox`
  - `xmtp/parse-payment-intent`
- Compliance gate:
  - `persona/*`
- Conversion rail:
  - `offramp/*`
- Cross-chain execution:
  - `superchain/*` (Across testnet API paths)
- Yield rail:
  - `web3/approve-token`
  - `aave-v3/supply`
- Proof/notification rail:
  - `xmtp/send-transaction-receipt`
  - `xmtp/send-message`

## Added Integrations and Why Each Was Required

### 1) XMTP (`xmtp`)

Required to support encrypted wallet-to-wallet intent and receipts:

- `xmtp/send-message`
- `xmtp/subscribe-to-inbox`
- `xmtp/parse-payment-intent`
- `xmtp/send-transaction-receipt`

### 2) Persona (`persona`)

Required for pre-offramp compliance gating:

- `persona/check-verification-status`
- `persona/create-inquiry`
- `persona/get-cleared-corridors`
- `persona/subscribe-verification-webhook`
- `persona/get-transaction-limits`

### 3) Offramp (`offramp`)

Required for quote/convert/status lifecycle:

- `offramp/get-supported-corridors`
- `offramp/get-best-quote`
- `offramp/get-rate-history`
- `offramp/trigger-conversion`
- `offramp/get-conversion-status`

### 4) Superchain (`superchain`)

Required for route discovery and transfer execution:

- `superchain/get-supported-routes`
- `superchain/get-route-quote`
- `superchain/initiate-transfer`
- `superchain/poll-transfer-status`

### 5) Request Finance (`request-finance`)

Required for invoice-centric payment context:

- `request-finance/subscribe-invoice-events`
- `request-finance/get-payment-history`

### 6) Existing protocol and signal integrations

- `sablier/*`, `superfluid/*` for stream context.
- `web3/*` and `aave-v3/supply` for approvals + yield deployment.

## Deep Implementation Walkthrough (with code)

This section highlights concrete code paths and implementation patterns.

### XMTP inbox subscription context initialization

File: [keeperhub/plugins/xmtp/steps/subscribe-to-inbox.ts](https://github.com/SamFelix03/keeperhub/blob/staging/plugins/xmtp/steps/subscribe-to-inbox.ts)

```ts
const env = resolveXmtpEnv(input.xmtpEnv || credentials.XMTP_ENV);
const xmtp = await createXmtpClientForOrganization({
  organizationId,
  env,
  dbPath: input.xmtpDbPath || credentials.XMTP_DB_PATH,
});
senderAddress = xmtp.senderAddress;
```

Why this matters:

- Enforces org wallet identity for XMTP operations.
- Uses persisted DB path to keep inbox identity stable across runs.

### Persona verification snapshot resolution

File: [keeperhub/plugins/persona/steps/check-verification-status.ts](https://github.com/SamFelix03/keeperhub/blob/staging/plugins/persona/steps/check-verification-status.ts)

```ts
const snapshot = await getPersonaVerificationSnapshot(input, credentials);
return {
  success: true,
  status: snapshot.status,
  tier: snapshot.tier,
  corridors: snapshot.corridors,
  limits: snapshot.limits,
  raw: snapshot.raw,
};
```

Why this matters:

- Produces normalized gate fields used directly by downstream conditions.
- Keeps provider payload in `raw` for audit/debug.

### Offramp quote ranking logic

File: [keeperhub/plugins/offramp/steps/get-best-quote.ts](https://github.com/SamFelix03/keeperhub/blob/staging/plugins/offramp/steps/get-best-quote.ts)

```ts
const ranked = [...quotes].sort(
  (a, b) => (b.estimatedReceive || 0) - (a.estimatedReceive || 0)
);
return {
  success: true,
  bestQuote: ranked[0],
  quotes: ranked,
  count: ranked.length,
};
```

Why this matters:

- Supports multi-provider comparison with deterministic ranking.
- Allows `auto` provider mode without hard-coding a single vendor.

### Superchain initiate execution with nonce-safe sequencing

File: [keeperhub/plugins/superchain/steps/initiate-transfer.ts](https://github.com/SamFelix03/keeperhub/blob/staging/plugins/superchain/steps/initiate-transfer.ts)

```ts
const signer = await initializeWalletSigner(organizationId, rpcUrl, originChainId);
let nextNonce = await signer.getNonce("pending");

const approvalResponse = await signer.sendTransaction({
  to: approvalTx.to,
  data: approvalTx.data,
  value: approvalTx.value ? BigInt(approvalTx.value) : undefined,
  nonce: nextNonce,
});
nextNonce += 1;

const txResponse = await signer.sendTransaction({
  to: swapTx.to,
  data: swapTx.data,
  value: swapTx.value ? BigInt(swapTx.value) : undefined,
  nonce: nextNonce,
});
```

Why this matters:

- Prevents nonce reuse race in repeated E2E runs.
- Keeps approvals + swap in one explicit sequence.

### Across route preflight

File: [keeperhub/plugins/superchain/steps/route-preflight.ts](https://github.com/SamFelix03/keeperhub/blob/staging/plugins/superchain/steps/route-preflight.ts)

Use in `initiate-transfer`/`get-route-quote` ensures route/token-chain compatibility before execution attempt.

### Aave V3 support updates for Base Sepolia

Files:

- [keeperhub/protocols/aave-v3.ts](https://github.com/SamFelix03/keeperhub/blob/staging/protocols/aave-v3.ts)
- [keeperhub/protocols/abis/aave-v3-pool.json](https://github.com/SamFelix03/keeperhub/blob/staging/protocols/abis/aave-v3-pool.json)
- [keeperhub/protocols/abis/aave-v3-data-provider.json](https://github.com/SamFelix03/keeperhub/blob/staging/protocols/abis/aave-v3-data-provider.json)

Why this matters:

- Ensures protocol ABI + pool mapping availability for testnet supply path in this workflow.

## Plugin Functional Reference

### `xmtp` plugin

- Purpose: encrypted payment intent + receipt rail.
- Actions:
  - `send-message`
  - `subscribe-to-inbox`
  - `parse-payment-intent`
  - `send-transaction-receipt`
- Primary files:
  - [keeperhub/plugins/xmtp/index.ts](https://github.com/SamFelix03/keeperhub/blob/staging/plugins/xmtp/index.ts)
  - [keeperhub/plugins/xmtp/steps/xmtp-core.ts](https://github.com/SamFelix03/keeperhub/blob/staging/plugins/xmtp/steps/xmtp-core.ts)
  - [keeperhub/plugins/xmtp/steps/parse-payment-intent.ts](https://github.com/SamFelix03/keeperhub/blob/staging/plugins/xmtp/steps/parse-payment-intent.ts)
  - [keeperhub/plugins/xmtp/steps/send-message.ts](https://github.com/SamFelix03/keeperhub/blob/staging/plugins/xmtp/steps/send-message.ts)
  - [keeperhub/plugins/xmtp/steps/subscribe-to-inbox.ts](https://github.com/SamFelix03/keeperhub/blob/staging/plugins/xmtp/steps/subscribe-to-inbox.ts)
  - [keeperhub/plugins/xmtp/steps/send-transaction-receipt.ts](https://github.com/SamFelix03/keeperhub/blob/staging/plugins/xmtp/steps/send-transaction-receipt.ts)

### `persona` plugin

- Purpose: KYC and corridor eligibility gate.
- Actions:
  - `check-verification-status`
  - `create-inquiry`
  - `get-cleared-corridors`
  - `subscribe-verification-webhook`
  - `get-transaction-limits`
- Files:
  - [keeperhub/plugins/persona/index.ts](https://github.com/SamFelix03/keeperhub/blob/staging/plugins/persona/index.ts)
  - [keeperhub/plugins/persona/steps/persona-core.ts](https://github.com/SamFelix03/keeperhub/blob/staging/plugins/persona/steps/persona-core.ts)
  - [keeperhub/plugins/persona/steps/check-verification-status.ts](https://github.com/SamFelix03/keeperhub/blob/staging/plugins/persona/steps/check-verification-status.ts)
  - [keeperhub/plugins/persona/steps/create-inquiry.ts](https://github.com/SamFelix03/keeperhub/blob/staging/plugins/persona/steps/create-inquiry.ts)
  - [keeperhub/plugins/persona/steps/get-cleared-corridors.ts](https://github.com/SamFelix03/keeperhub/blob/staging/plugins/persona/steps/get-cleared-corridors.ts)
  - [keeperhub/plugins/persona/steps/get-transaction-limits.ts](https://github.com/SamFelix03/keeperhub/blob/staging/plugins/persona/steps/get-transaction-limits.ts)
  - [keeperhub/plugins/persona/steps/subscribe-verification-webhook.ts](https://github.com/SamFelix03/keeperhub/blob/staging/plugins/persona/steps/subscribe-verification-webhook.ts)

### `offramp` plugin

- Purpose: fiat corridor execution lifecycle.
- Actions:
  - `get-supported-corridors`
  - `get-best-quote`
  - `get-rate-history`
  - `trigger-conversion`
  - `get-conversion-status`
- Files:
  - [keeperhub/plugins/offramp/index.ts](https://github.com/SamFelix03/keeperhub/blob/staging/plugins/offramp/index.ts)
  - [keeperhub/plugins/offramp/steps/offramp-core.ts](https://github.com/SamFelix03/keeperhub/blob/staging/plugins/offramp/steps/offramp-core.ts)
  - [keeperhub/plugins/offramp/steps/get-supported-corridors.ts](https://github.com/SamFelix03/keeperhub/blob/staging/plugins/offramp/steps/get-supported-corridors.ts)
  - [keeperhub/plugins/offramp/steps/get-best-quote.ts](https://github.com/SamFelix03/keeperhub/blob/staging/plugins/offramp/steps/get-best-quote.ts)
  - [keeperhub/plugins/offramp/steps/get-rate-history.ts](https://github.com/SamFelix03/keeperhub/blob/staging/plugins/offramp/steps/get-rate-history.ts)
  - [keeperhub/plugins/offramp/steps/trigger-conversion.ts](https://github.com/SamFelix03/keeperhub/blob/staging/plugins/offramp/steps/trigger-conversion.ts)
  - [keeperhub/plugins/offramp/steps/get-conversion-status.ts](https://github.com/SamFelix03/keeperhub/blob/staging/plugins/offramp/steps/get-conversion-status.ts)

### `superchain` plugin

- Purpose: Across-backed route quote/execute/poll.
- Actions:
  - `get-supported-routes`
  - `get-route-quote`
  - `initiate-transfer`
  - `poll-transfer-status`
- Files:
  - [keeperhub/plugins/superchain/index.ts](https://github.com/SamFelix03/keeperhub/blob/staging/plugins/superchain/index.ts)
  - [keeperhub/plugins/superchain/steps/superchain-core.ts](https://github.com/SamFelix03/keeperhub/blob/staging/plugins/superchain/steps/superchain-core.ts)
  - [keeperhub/plugins/superchain/steps/route-preflight.ts](https://github.com/SamFelix03/keeperhub/blob/staging/plugins/superchain/steps/route-preflight.ts)
  - [keeperhub/plugins/superchain/steps/get-supported-routes.ts](https://github.com/SamFelix03/keeperhub/blob/staging/plugins/superchain/steps/get-supported-routes.ts)
  - [keeperhub/plugins/superchain/steps/get-route-quote.ts](https://github.com/SamFelix03/keeperhub/blob/staging/plugins/superchain/steps/get-route-quote.ts)
  - [keeperhub/plugins/superchain/steps/initiate-transfer.ts](https://github.com/SamFelix03/keeperhub/blob/staging/plugins/superchain/steps/initiate-transfer.ts)
  - [keeperhub/plugins/superchain/steps/poll-transfer-status.ts](https://github.com/SamFelix03/keeperhub/blob/staging/plugins/superchain/steps/poll-transfer-status.ts)

### `request-finance` plugin

- Purpose: invoice signal context and history.
- Actions:
  - `subscribe-invoice-events`
  - `get-payment-history`
- Files:
  - [keeperhub/plugins/request-finance/index.ts](https://github.com/SamFelix03/keeperhub/blob/staging/plugins/request-finance/index.ts)
  - [keeperhub/plugins/request-finance/steps/request-finance-core.ts](https://github.com/SamFelix03/keeperhub/blob/staging/plugins/request-finance/steps/request-finance-core.ts)
  - [keeperhub/plugins/request-finance/steps/subscribe-invoice-events.ts](https://github.com/SamFelix03/keeperhub/blob/staging/plugins/request-finance/steps/subscribe-invoice-events.ts)
  - [keeperhub/plugins/request-finance/steps/get-payment-history.ts](https://github.com/SamFelix03/keeperhub/blob/staging/plugins/request-finance/steps/get-payment-history.ts)

### Signal plugins used by the same E2E graph

- Sablier:
  - [keeperhub/plugins/sablier/steps/subscribe-to-stream-events.ts](https://github.com/SamFelix03/keeperhub/blob/staging/plugins/sablier/steps/subscribe-to-stream-events.ts)
  - [keeperhub/plugins/sablier/steps/get-stream-state.ts](https://github.com/SamFelix03/keeperhub/blob/staging/plugins/sablier/steps/get-stream-state.ts)
  - [keeperhub/plugins/sablier/steps/get-unlockable-amount.ts](https://github.com/SamFelix03/keeperhub/blob/staging/plugins/sablier/steps/get-unlockable-amount.ts)
- Superfluid:
  - [keeperhub/plugins/superfluid/steps/get-stream-events.ts](https://github.com/SamFelix03/keeperhub/blob/staging/plugins/superfluid/steps/get-stream-events.ts)
  - [keeperhub/plugins/superfluid/steps/get-incoming-streams.ts](https://github.com/SamFelix03/keeperhub/blob/staging/plugins/superfluid/steps/get-incoming-streams.ts)
  - [keeperhub/plugins/superfluid/steps/get-real-time-balance.ts](https://github.com/SamFelix03/keeperhub/blob/staging/plugins/superfluid/steps/get-real-time-balance.ts)

## Route-by-Route Workflow Explanation

Workflow file: [FLOWWAGE_FULL_E2E.workflow.json](https://github.com/SamFelix03/FlowWage/blob/master/flowwage_workflow/workflows/FLOWWAGE_FULL_E2E.workflow.json)

1. `request-finance/subscribe-invoice-events` and `request-finance/get-payment-history`
   - bootstrap invoice payment signal.
2. `sablier/subscribe-to-stream-events` and `sablier/get-stream-state`
   - bootstrap stream signal.
3. `superfluid/get-stream-events` and `superfluid/get-incoming-streams`
   - collect live stream context.
4. `web3/check-token-balance`
   - baseline balance state.
5. `xmtp/subscribe-to-inbox`
   - initialize encrypted inbound trigger channel.
6. `xmtp/parse-payment-intent`
   - parse structured intent payload.
7. `code/run-code`
   - split into liquid/yield/convert buckets.
8. Persona branch:
   - `check-verification-status`
   - `get-cleared-corridors`
   - `get-transaction-limits`
   - `subscribe-verification-webhook`
   - condition node decides approved vs inquiry path.
9. Approved execution:
   - `offramp/get-supported-corridors`
   - `offramp/get-best-quote`
   - `offramp/get-rate-history`
   - `superchain/get-route-quote`
   - `superchain/initiate-transfer`
   - `superchain/poll-transfer-status`
10. Yield path:
    - `web3/check-token-balance` (Base Sepolia token)
    - `web3/approve-token`
    - `aave-v3/supply`
11. Conversion path:
    - `offramp/trigger-conversion`
    - `offramp/get-conversion-status`
12. Receipt path:
    - `xmtp/send-transaction-receipt`
    - `xmtp/send-message`
13. Non-approved path:
    - `persona/create-inquiry`
    - `xmtp/send-message` with inquiry URL.

## How to Run from KeeperHub UI

### Prerequisites

1. KeeperHub app running locally.
2. Environment configured (minimum):
   - `DATABASE_URL`
   - `BETTER_AUTH_SECRET`
   - `INTEGRATION_ENCRYPTION_KEY`
   - `WALLET_ENCRYPTION_KEY`
   - `TURNKEY_API_PUBLIC_KEY`
   - `TURNKEY_API_PRIVATE_KEY`
   - `TURNKEY_ORGANIZATION_ID`
3. Valid service credentials for:
   - XMTP
   - Persona
   - Offramp provider(s)
   - Superchain/Across
   - Request Finance

### UI Execution Steps

1. Create account and organization.
2. Create org wallet in KeeperHub (UI wallet flow).
3. Add integrations in UI and save keys/secrets.
4. Import:
   - [flowwage_workflow/workflows/FLOWWAGE_FULL_E2E.workflow.json](workflows/FLOWWAGE_FULL_E2E.workflow.json)
5. Open the imported workflow and assign each node’s `integrationId` to matching integration records.
6. Confirm wallet/token/chain parameters for your funded testnet wallet.
7. Run manually.
8. Inspect execution details/logs for:
   - `depositTxnRef` / tx hash
   - `conversionReference`
   - XMTP conversation/message proof fields.

## Troubleshooting

1. XMTP inbox mismatch:
   - Symptom: stored InboxID mismatch after wallet rotation.
   - Action: clear XMTP runtime DB path and rerun.
2. Turnkey signing errors:
   - Check org/key alignment and signer wallet ownership.
3. Nonce-related send errors:
   - Current implementation explicitly sequences nonce in superchain initiate.
4. No routes/quotes:
   - Validate token-chain pair against Across testnet supported routes.
5. Missing off-ramp results:
   - Verify corridor, fiat code, and provider credentials.

## Conclusion

FlowWage implements the requirements narrative as a concrete KeeperHub workflow: from income signal and encrypted intent through compliance, cross-chain execution, yield deployment, conversion, and encrypted receipts.  
It is built with minimal, pattern-consistent KeeperHub plugin changes and produces verifiable execution artifacts suitable for technical demos and real integration testing.
