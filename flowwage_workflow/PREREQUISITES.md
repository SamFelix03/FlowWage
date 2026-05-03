# FlowWage Workflow Prerequisites (Production-Style)

These are mandatory before running the workflow.

1. Active KeeperHub organization wallet (Turnkey-backed).
2. Valid API key for that same organization.
3. Persona integration configured and accessible.
4. XMTP integration configured and accessible.
5. Offramp integration configured and accessible.
6. Recipient wallet address that is XMTP-reachable for message actions.
7. For real on-chain execution paths, the organization wallet must be funded on the target chain.

## Required Environment Variables for `run_workflow_demo.sh`

- `API_KEY`
- `PERSONA_INTEGRATION_ID`
- `XMTP_INTEGRATION_ID`
- `OFFRAMP_INTEGRATION_ID`
- Optional: `XMTP_RECIPIENT_ADDRESS`
- Optional: `API_BASE_URL` (default `http://localhost:3000`)

The script now fails fast if wallet/integration prerequisites are missing.
