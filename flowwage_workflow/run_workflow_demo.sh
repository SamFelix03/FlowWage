#!/usr/bin/env bash
set -euo pipefail

API_BASE_URL="${API_BASE_URL:-http://localhost:3000}"
API_KEY="${API_KEY:-}"
WORKFLOW_JSON="${WORKFLOW_JSON:-/Users/sam/FlowWage/flowwage_workflow/FLOWWAGE_WORKFLOW_IMPORT.json}"
PERSONA_INTEGRATION_ID="${PERSONA_INTEGRATION_ID:-}"
XMTP_INTEGRATION_ID="${XMTP_INTEGRATION_ID:-}"
OFFRAMP_INTEGRATION_ID="${OFFRAMP_INTEGRATION_ID:-}"
XMTP_RECIPIENT_ADDRESS="${XMTP_RECIPIENT_ADDRESS:-}"

if [[ -z "${API_KEY}" ]]; then
  echo "Missing required API_KEY"
  exit 1
fi

if [[ -z "${PERSONA_INTEGRATION_ID}" || -z "${XMTP_INTEGRATION_ID}" || -z "${OFFRAMP_INTEGRATION_ID}" ]]; then
  echo "Missing required integration IDs. Set PERSONA_INTEGRATION_ID, XMTP_INTEGRATION_ID, OFFRAMP_INTEGRATION_ID."
  exit 1
fi

echo "Checking org wallet prerequisite"
wallet_payload="$(curl -sS -X GET "${API_BASE_URL}/api/user/wallet" \
  -H "Authorization: Bearer ${API_KEY}")"
has_wallet="$(jq -r '.hasWallet // false' <<<"${wallet_payload}")"
if [[ "${has_wallet}" != "true" ]]; then
  echo "Wallet prerequisite failed: organization must have an active Turnkey wallet before running workflow."
  echo "${wallet_payload}" | jq .
  exit 1
fi

tmp_import_response="$(mktemp)"
tmp_workflow="$(mktemp)"
tmp_execute_response="$(mktemp)"

echo "Importing workflow from ${WORKFLOW_JSON}"
curl -sS -X POST "${API_BASE_URL}/api/workflows/import" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  --data-binary "@${WORKFLOW_JSON}" > "${tmp_import_response}"

workflow_id="$(jq -r '.id // empty' "${tmp_import_response}")"
if [[ -z "${workflow_id}" ]]; then
  echo "Import failed:"
  cat "${tmp_import_response}"
  exit 1
fi
echo "Imported workflow: ${workflow_id}"

echo "Fetching workflow for integration wiring"
