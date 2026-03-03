#!/usr/bin/env bash
set -euo pipefail

REPO="${OPENCLAW_REPO:-}"
POLL_SECONDS="${OPENCLAW_POLL_SECONDS:-120}"
DEV_AGENT_ID="${DEV_AGENT_ID:-dev}"
TEST_AGENT_ID="${TEST_AGENT_ID:-test}"

if [[ -z "${REPO}" ]]; then
  echo "OPENCLAW_REPO is required (example: langgexyz/openclaw-7x24-lab)" >&2
  exit 1
fi

for cmd in gh jq openclaw; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "${cmd} is required" >&2
    exit 1
  fi
done

run_agent() {
  local agent_id="$1"
  local msg="$2"
  openclaw agent --agent "${agent_id}" --message "${msg}" --json >/tmp/openclaw_agent_${agent_id}.json
}

mark_transition() {
  local issue="$1"
  local remove_label="$2"
  local add_label="$3"
  gh issue edit "${issue}" --repo "${REPO}" --remove-label "${remove_label}" --add-label "${add_label}" >/dev/null
}

process_issue() {
  local number="$1"
  local title="$2"
  local body="$3"
  local url="$4"

  mark_transition "${number}" "ready" "in-dev"
  gh issue comment "${number}" --repo "${REPO}" --body "dev_bot started: ${url}" >/dev/null

  local dev_prompt
  dev_prompt="[AUTO_DISPATCH][ISSUE #${number}] ${title}
URL: ${url}
Task: implement requirement with atomic commits and open PR.
Issue body:
${body}"

  if ! run_agent "${DEV_AGENT_ID}" "${dev_prompt}"; then
    gh issue edit "${number}" --repo "${REPO}" --remove-label "in-dev" --add-label "blocked" >/dev/null
    gh issue comment "${number}" --repo "${REPO}" --body "dev_bot failed to execute. moved to blocked." >/dev/null
    return
  fi

  mark_transition "${number}" "in-dev" "in-test"
  gh issue comment "${number}" --repo "${REPO}" --body "test_bot started for #${number}" >/dev/null

  local test_prompt
  test_prompt="[AUTO_TEST][ISSUE #${number}] ${title}
URL: ${url}
Task: validate implementation for acceptance criteria and report pass/fail with evidence."

  if ! run_agent "${TEST_AGENT_ID}" "${test_prompt}"; then
    gh issue edit "${number}" --repo "${REPO}" --remove-label "in-test" --add-label "blocked" >/dev/null
    gh issue comment "${number}" --repo "${REPO}" --body "test_bot failed to execute. moved to blocked." >/dev/null
    return
  fi

  mark_transition "${number}" "in-test" "ready-merge"
  gh issue comment "${number}" --repo "${REPO}" --body "pipeline complete: ready-merge" >/dev/null
}

while true; do
  issues_json="$(gh issue list --repo "${REPO}" --state open --label ready --limit 20 --json number,title,body,url)"
  count="$(jq 'length' <<<"${issues_json}")"

  if [[ "${count}" -gt 0 ]]; then
    while IFS=$'\t' read -r number title body url; do
      process_issue "${number}" "${title}" "${body}" "${url}"
    done < <(jq -r '.[] | [.number, .title, (.body // ""), .url] | @tsv' <<<"${issues_json}")
  fi

  sleep "${POLL_SECONDS}"
done
