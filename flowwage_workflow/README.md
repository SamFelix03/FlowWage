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
  - [flowwage_workflow/workflows/FLOWWAGE_FULL_E2E.workflow.json](workflows/FLOWWAGE_FULL_E2E.workflow.json)

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
