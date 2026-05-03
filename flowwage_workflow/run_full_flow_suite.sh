#!/usr/bin/env bash
set -euo pipefail

API_BASE_URL="${API_BASE_URL:-http://localhost:3000}"
API_KEY="${API_KEY:-}"

PERSONA_INTEGRATION_ID="${PERSONA_INTEGRATION_ID:-}"
XMTP_INTEGRATION_ID="${XMTP_INTEGRATION_ID:-}"
OFFRAMP_INTEGRATION_ID="${OFFRAMP_INTEGRATION_ID:-}"
SUPERCHAIN_INTEGRATION_ID="${SUPERCHAIN_INTEGRATION_ID:-}"
REQUEST_FINANCE_INTEGRATION_ID="${REQUEST_FINANCE_INTEGRATION_ID:-}"

XMTP_RECIPIENT_ADDRESS="${XMTP_RECIPIENT_ADDRESS:-}"
WALLET_ADDRESS="${WALLET_ADDRESS:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"
XMTP_DB_PATH="${XMTP_DB_PATH:-/private/tmp/keeperhub-xmtp}"
FORCE_FULL_PATH="${FORCE_FULL_PATH:-0}"
TEST_INVOICE_AMOUNT="${TEST_INVOICE_AMOUNT:-20}"

if [[ -z "${API_KEY}" ]]; then
  echo "Missing API_KEY"
  exit 1
fi

for required in PERSONA_INTEGRATION_ID XMTP_INTEGRATION_ID OFFRAMP_INTEGRATION_ID SUPERCHAIN_INTEGRATION_ID REQUEST_FINANCE_INTEGRATION_ID XMTP_RECIPIENT_ADDRESS WALLET_ADDRESS; do
  if [[ -z "${!required}" ]]; then
    echo "Missing ${required}"
    exit 1
  fi
done

wallet_payload="$(curl -sS -X GET "${API_BASE_URL}/api/user/wallet" -H "Authorization: Bearer ${API_KEY}")"
has_wallet="$(jq -r '.hasWallet // false' <<<"${wallet_payload}")"
if [[ "${has_wallet}" != "true" ]]; then
  echo "Wallet prerequisite failed"
  echo "${wallet_payload}" | jq .
  exit 1
fi

mkdir -p /Users/sam/FlowWage/flowwage_workflow/logs
mkdir -p "${XMTP_DB_PATH}"
SUITE_LOG="/Users/sam/FlowWage/flowwage_workflow/logs/full-flow-suite-$(date +%Y%m%d-%H%M%S).log"
SUITE_REPORT="${SUITE_LOG%.log}.report.json"

echo "[]" > "${SUITE_REPORT}"

run_one() {
  local file="$1"
  local tag="$2"
  local tmp_import tmp_workflow tmp_patch tmp_exec tmp_status tmp_logs tmp_entry
  tmp_import="$(mktemp)"
  tmp_workflow="$(mktemp)"
  tmp_patch="$(mktemp)"
  tmp_exec="$(mktemp)"
  tmp_status="$(mktemp)"
  tmp_logs="$(mktemp)"
  tmp_entry="$(mktemp)"

  echo "=== ${tag} ===" | tee -a "${SUITE_LOG}"
  echo "Importing ${file}" | tee -a "${SUITE_LOG}"

  curl -sS -X POST "${API_BASE_URL}/api/workflows/import" \
    -H "Authorization: Bearer ${API_KEY}" \
    -H "Content-Type: application/json" \
    --data-binary "@${file}" > "${tmp_import}"

  local workflow_id
  workflow_id="$(jq -r '.id // empty' "${tmp_import}")"
  if [[ -z "${workflow_id}" ]]; then
    echo "Import failed: $(cat "${tmp_import}")" | tee -a "${SUITE_LOG}"
    return 1
  fi

  echo "workflow_id=${workflow_id}" | tee -a "${SUITE_LOG}"

  curl -sS -X GET "${API_BASE_URL}/api/workflows/${workflow_id}" \
    -H "Authorization: Bearer ${API_KEY}" > "${tmp_workflow}"

  jq \
    --arg personaId "${PERSONA_INTEGRATION_ID}" \
    --arg xmtpId "${XMTP_INTEGRATION_ID}" \
    --arg offrampId "${OFFRAMP_INTEGRATION_ID}" \
    --arg superchainId "${SUPERCHAIN_INTEGRATION_ID}" \
    --arg requestFinanceId "${REQUEST_FINANCE_INTEGRATION_ID}" \
    --arg walletAddress "${WALLET_ADDRESS}" \
    --arg xmtpRecipient "${XMTP_RECIPIENT_ADDRESS}" \
    --arg xmtpDbPath "${XMTP_DB_PATH}" \
    --arg forceFullPath "${FORCE_FULL_PATH}" \
    --arg testInvoiceAmount "${TEST_INVOICE_AMOUNT}" \
    '
    .nodes |= map(
      if .data.type == "action" and (.data.config.actionType | startswith("persona/")) then
        .data.config.integrationId = $personaId
      elif .data.type == "action" and (.data.config.actionType | startswith("xmtp/")) then
        .data.config.integrationId = $xmtpId
      elif .data.type == "action" and (.data.config.actionType | startswith("offramp/")) then
        .data.config.integrationId = $offrampId
      elif .data.type == "action" and (.data.config.actionType | startswith("superchain/")) then
        .data.config.integrationId = $superchainId
      elif .data.type == "action" and (.data.config.actionType | startswith("request-finance/")) then
        .data.config.integrationId = $requestFinanceId
      else
        .
      end
      | (if .data.config.walletAddress? != null then .data.config.walletAddress = $walletAddress else . end)
      | (if .data.config.address? != null then .data.config.address = $walletAddress else . end)
      | (if .data.config.depositor? != null then .data.config.depositor = $walletAddress else . end)
      | (if .data.config.recipient? != null then .data.config.recipient = $walletAddress else . end)
      | (if .data.config.recipientAddress? != null then .data.config.recipientAddress = $xmtpRecipient else . end)
      | (if .data.config.actionType? != null and (.data.config.actionType | startswith("xmtp/")) then .data.config.xmtpDbPath = $xmtpDbPath else . end)
      | (if .data.config.chatId? != null then .data.config.chatId = "" else . end)
      | (if .id == "xmtp-parse" then .data.config.messageBody = ("{\"type\":\"payment\",\"amount\":" + $testInvoiceAmount + ",\"token\":\"USDC\",\"chain\":\"op-sepolia\",\"recipient\":\"" + $xmtpRecipient + "\"}") else . end)
      | (if $forceFullPath == "1" and (.id == "persona-approved" or .id == "convert-check" or .id == "rebalance-check" or .id == "apyrule") then
          .data.config.condition = "true == true"
          | .data.config.conditionConfig = {
              group: {
                id: (.id + "-force"),
                logic: "AND",
                rules: [
                  {
                    id: (.id + "-force-rule"),
                    operator: "=",
                    leftOperand: "true",
                    rightOperand: "true"
                  }
                ]
              }
            }
        else
          .
        end)
    )
    | { nodes: .nodes, edges: .edges }
    ' "${tmp_workflow}" > "${tmp_patch}"

  curl -sS -X PATCH "${API_BASE_URL}/api/workflows/${workflow_id}" \
    -H "Authorization: Bearer ${API_KEY}" \
    -H "Content-Type: application/json" \
    --data-binary "@${tmp_patch}" > /dev/null

  curl -sS -X POST "${API_BASE_URL}/api/workflow/${workflow_id}/execute" \
    -H "Authorization: Bearer ${API_KEY}" \
    -H "Content-Type: application/json" \
    -d "{\"input\":{\"walletAddress\":\"${WALLET_ADDRESS}\",\"amount\":${TEST_INVOICE_AMOUNT},\"liquidPercent\":30,\"yieldPercent\":40,\"convertPercent\":30,\"minIncomeTriggerUsd\":50}}" > "${tmp_exec}"

  local execution_id
  execution_id="$(jq -r '.executionId // empty' "${tmp_exec}")"
  if [[ -z "${execution_id}" ]]; then
    echo "Execution start failed: $(cat "${tmp_exec}")" | tee -a "${SUITE_LOG}"
    return 1
  fi

  echo "execution_id=${execution_id}" | tee -a "${SUITE_LOG}"

  local status_payload status
  for _ in $(seq 1 60); do
    sleep 2
    status_payload="$(curl -sS -X GET "${API_BASE_URL}/api/workflows/executions/${execution_id}/status" -H "Authorization: Bearer ${API_KEY}")"
    status="$(jq -r '.status // "unknown"' <<<"${status_payload}")"
    echo "status=${status}" | tee -a "${SUITE_LOG}"
    if [[ "${status}" == "success" || "${status}" == "completed" || "${status}" == "error" || "${status}" == "cancelled" ]]; then
      echo "${status_payload}" > "${tmp_status}"
      echo "${status_payload}" | jq . | tee -a "${SUITE_LOG}"
      break
    fi
  done

  curl -sS -X GET "${API_BASE_URL}/api/workflows/executions/${execution_id}/logs" \
    -H "Authorization: Bearer ${API_KEY}" > "${tmp_logs}"

  jq \
    --arg tag "${tag}" \
    --arg workflowId "${workflow_id}" \
    --arg executionId "${execution_id}" \
    '
    def to_pairs:
      if type == "object" then
        to_entries[] as $e
        | ({k: $e.key, v: $e.value} , ($e.value | to_pairs))
      elif type == "array" then
        .[] | to_pairs
      else
        empty
      end;
    {
      part: $tag,
      workflowId: $workflowId,
      executionId: $executionId,
      status: (input.status // "unknown"),
      txHashes: [
        (.logs // [])[]?.output? | .. | strings | select(test("^0x[a-fA-F0-9]{64}$"))
      ] | unique,
      xmtpMessageIds: [
        (.logs // [])[]?.output? | to_pairs | select((.k | ascii_downcase) | test("messageid$|message_id$")) | .v | strings
      ] | unique,
      xmtpConversationIds: [
        (.logs // [])[]?.output? | to_pairs | select((.k | ascii_downcase) | test("conversationid$|conversation_id$")) | .v | strings
      ] | unique,
      conversionReferences: [
        (.logs // [])[]?.output? | to_pairs | select((.k | ascii_downcase) | test("conversionreference$|conversion_reference$|orderid$|order_id$")) | .v | strings
      ] | unique,
      transferProof: [
        (.logs // [])[]?.output? | to_pairs | select((.k | ascii_downcase) | test("depositid$|deposit_id$|filltx$|fill_tx$|txhash$|tx_hash$")) | {key: .k, value: .v}
      ],
      nodeOutputs: [
        (.logs // [])[] | {
          nodeId,
          nodeName,
          status,
          output
        }
      ]
    }
    ' "${tmp_logs}" "${tmp_status}" > "${tmp_entry}"

  jq --slurpfile entry "${tmp_entry}" '. += [$entry[0]]' "${SUITE_REPORT}" > "${SUITE_REPORT}.tmp"
  mv "${SUITE_REPORT}.tmp" "${SUITE_REPORT}"
}

run_one "/Users/sam/FlowWage/flowwage_workflow/workflows/FLOWWAGE_01_INCOME_SENTINEL.workflow.json" "PART-01-INCOME-SENTINEL"
run_one "/Users/sam/FlowWage/flowwage_workflow/workflows/FLOWWAGE_05_XMTP_INBOX_TRIGGER.workflow.json" "PART-02-XMTP-INBOX-TRIGGER"
run_one "/Users/sam/FlowWage/flowwage_workflow/workflows/FLOWWAGE_02_EXECUTION_GATE.workflow.json" "PART-03-EXECUTION-GATE"
run_one "/Users/sam/FlowWage/flowwage_workflow/workflows/FLOWWAGE_03_DEFERRED_RESUME.workflow.json" "PART-04-DEFERRED-RESUME"
run_one "/Users/sam/FlowWage/flowwage_workflow/workflows/FLOWWAGE_04_WEEKLY_REBALANCER.workflow.json" "PART-05-WEEKLY-REBALANCER"

echo "SUITE_LOG=${SUITE_LOG}" | tee -a "${SUITE_LOG}"
echo "SUITE_REPORT=${SUITE_REPORT}" | tee -a "${SUITE_LOG}"
