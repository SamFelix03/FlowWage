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
curl -sS -X GET "${API_BASE_URL}/api/workflows/${workflow_id}" \
  -H "Authorization: Bearer ${API_KEY}" > "${tmp_workflow}"

echo "Injecting integration IDs for persona/xmtp/offramp action nodes"
jq \
  --arg personaId "${PERSONA_INTEGRATION_ID}" \
  --arg xmtpId "${XMTP_INTEGRATION_ID}" \
  --arg offrampId "${OFFRAMP_INTEGRATION_ID}" \
  --arg xmtpRecipient "${XMTP_RECIPIENT_ADDRESS}" \
  '
  .nodes |= map(
    if .id == "parse-intent" and ($xmtpRecipient | length) > 0 then
      .data.config.messageBody = ("{\"type\":\"payment\",\"amount\":500,\"token\":\"USDC\",\"chain\":\"optimism\",\"recipient\":\"" + $xmtpRecipient + "\"}")
    elif .data.type == "action" and (.data.config.actionType | startswith("persona/")) then
      .data.config.integrationId = $personaId
    elif .data.type == "action" and (.data.config.actionType | startswith("xmtp/")) then
      .data.config.integrationId = $xmtpId
      | (if ($xmtpRecipient | length) > 0 and (.data.config.recipientAddress? != null) then .data.config.recipientAddress = $xmtpRecipient else . end)
    elif .data.type == "action" and (.data.config.actionType | startswith("offramp/")) then
      .data.config.integrationId = $offrampId
    else
      .
    end
  )
  | { nodes: .nodes, edges: .edges }
  ' "${tmp_workflow}" > "${tmp_workflow}.patched"

curl -sS -X PATCH "${API_BASE_URL}/api/workflows/${workflow_id}" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  --data-binary "@${tmp_workflow}.patched" > /dev/null

echo "Executing workflow"
curl -sS -X POST "${API_BASE_URL}/api/workflow/${workflow_id}/execute" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"input":{"source":"flowwage-demo","timestamp":"2026-05-03T00:00:00.000Z"}}' > "${tmp_execute_response}"

execution_id="$(jq -r '.executionId // empty' "${tmp_execute_response}")"
if [[ -z "${execution_id}" ]]; then
  echo "Execution start failed:"
  cat "${tmp_execute_response}"
  exit 1
fi
echo "Execution started: ${execution_id}"

for _ in $(seq 1 20); do
  sleep 2
  status_payload="$(curl -sS -X GET "${API_BASE_URL}/api/workflows/executions/${execution_id}/status" \
    -H "Authorization: Bearer ${API_KEY}")"
  status="$(jq -r '.status // "unknown"' <<<"${status_payload}")"
  echo "Status: ${status}"
  if [[ "${status}" == "completed" || "${status}" == "success" || "${status}" == "error" || "${status}" == "cancelled" ]]; then
    echo "${status_payload}" | jq .
    exit 0
  fi
done

echo "Timed out waiting for terminal status"
echo "Last response:"
echo "${status_payload}" | jq .
