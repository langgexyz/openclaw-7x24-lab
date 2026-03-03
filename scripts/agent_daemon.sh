#!/usr/bin/env bash
set -euo pipefail

REPO="${OPENCLAW_REPO:-}"
POLL_SECONDS="${OPENCLAW_POLL_SECONDS:-120}"
DEV_AGENT_ID="${DEV_AGENT_ID:-dev}"
TEST_AGENT_ID="${TEST_AGENT_ID:-test}"
DRY_RUN="${DRY_RUN:-0}"
RUN_ONCE="${RUN_ONCE:-0}"
MOCK_ISSUES_FILE="${MOCK_ISSUES_FILE:-}"
STATE_DIR="${STATE_DIR:-.state}"
LOG_FILE="${STATE_DIR}/dispatcher.log"

if [[ -z "${REPO}" ]]; then
  echo "OPENCLAW_REPO is required (example: langgexyz/openclaw-7x24-lab)" >&2
  exit 1
fi

mkdir -p "${STATE_DIR}"
touch "${LOG_FILE}"

for cmd in jq; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "${cmd} is required" >&2
    exit 1
  fi
done

if [[ "${DRY_RUN}" != "1" ]]; then
  for cmd in gh openclaw; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
      echo "${cmd} is required" >&2
      exit 1
    fi
  done
fi

log() {
  local msg="$1"
  local ts
  ts="$(date '+%Y-%m-%d %H:%M:%S')"
  echo "[${ts}] ${msg}" | tee -a "${LOG_FILE}"
}

run_agent() {
  local agent_id="$1"
  local msg="$2"
  if [[ "${DRY_RUN}" == "1" ]]; then
    log "DRY_RUN agent:${agent_id} <- ${msg:0:120}"
    return 0
  fi
  openclaw agent --agent "${agent_id}" --message "${msg}" --json >/tmp/openclaw_agent_${agent_id}.json
}

mark_transition() {
  local issue="$1"
  local remove_label="$2"
  local add_label="$3"
  if [[ "${DRY_RUN}" == "1" ]]; then
    log "DRY_RUN issue #${issue}: ${remove_label} -> ${add_label}"
    return 0
  fi
  gh issue edit "${issue}" --repo "${REPO}" --remove-label "${remove_label}" --add-label "${add_label}" >/dev/null
}

process_issue() {
  local number="$1"
  local title="$2"
  local body="$3"
  local url="$4"

  mark_transition "${number}" "ready" "in-dev"
  if [[ "${DRY_RUN}" == "1" ]]; then
    log "DRY_RUN issue #${number}: comment dev_bot started"
  else
    gh issue comment "${number}" --repo "${REPO}" --body "dev_bot started: ${url}" >/dev/null
  fi

  local dev_prompt
  dev_prompt="[AUTO_DISPATCH][ISSUE #${number}] ${title}
URL: ${url}
Task: implement requirement with atomic commits and open PR.
Issue body:
${body}"

  if ! run_agent "${DEV_AGENT_ID}" "${dev_prompt}"; then
    if [[ "${DRY_RUN}" == "1" ]]; then
      log "DRY_RUN issue #${number}: dev failed -> blocked"
    else
      gh issue edit "${number}" --repo "${REPO}" --remove-label "in-dev" --add-label "blocked" >/dev/null
      gh issue comment "${number}" --repo "${REPO}" --body "dev_bot failed to execute. moved to blocked." >/dev/null
    fi
    return
  fi

  mark_transition "${number}" "in-dev" "in-test"
  if [[ "${DRY_RUN}" == "1" ]]; then
    log "DRY_RUN issue #${number}: comment test_bot started"
  else
    gh issue comment "${number}" --repo "${REPO}" --body "test_bot started for #${number}" >/dev/null
  fi

  local test_prompt
  test_prompt="[AUTO_TEST][ISSUE #${number}] ${title}
URL: ${url}
Task: validate implementation for acceptance criteria and report pass/fail with evidence."

  if ! run_agent "${TEST_AGENT_ID}" "${test_prompt}"; then
    if [[ "${DRY_RUN}" == "1" ]]; then
      log "DRY_RUN issue #${number}: test failed -> blocked"
    else
      gh issue edit "${number}" --repo "${REPO}" --remove-label "in-test" --add-label "blocked" >/dev/null
      gh issue comment "${number}" --repo "${REPO}" --body "test_bot failed to execute. moved to blocked." >/dev/null
    fi
    return
  fi

  mark_transition "${number}" "in-test" "ready-merge"
  if [[ "${DRY_RUN}" == "1" ]]; then
    log "DRY_RUN issue #${number}: comment pipeline complete ready-merge"
  else
    gh issue comment "${number}" --repo "${REPO}" --body "pipeline complete: ready-merge" >/dev/null
  fi
}

while true; do
  if [[ -n "${MOCK_ISSUES_FILE}" ]]; then
    issues_json="$(cat "${MOCK_ISSUES_FILE}")"
  else
    issues_json="$(gh issue list --repo "${REPO}" --state open --label ready --limit 20 --json number,title,body,url)"
  fi
  count="$(jq 'length' <<<"${issues_json}")"

  if [[ "${count}" -gt 0 ]]; then
    while IFS=$'\t' read -r number title body url; do
      process_issue "${number}" "${title}" "${body}" "${url}"
    done < <(jq -r '.[] | [.number, .title, (.body // ""), .url] | @tsv' <<<"${issues_json}")
  fi

  if [[ "${RUN_ONCE}" == "1" ]]; then
    log "RUN_ONCE complete"
    exit 0
  fi

  sleep "${POLL_SECONDS}"
done
