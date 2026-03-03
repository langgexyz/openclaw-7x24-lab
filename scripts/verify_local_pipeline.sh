#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="${ROOT_DIR}/.state"
MOCK_JSON="${STATE_DIR}/mock_issues.json"
LOG_FILE="${STATE_DIR}/dispatcher.log"

mkdir -p "${STATE_DIR}"
rm -f "${LOG_FILE}"

cat > "${MOCK_JSON}" <<JSON
[
  {
    "number": 101,
    "title": "[BUG] demo regression",
    "body": "Repro: A->B->C\\nExpected: pass\\nAcceptance: tests green",
    "url": "https://github.com/example/openclaw-7x24-lab/issues/101"
  }
]
JSON

bash -n "${ROOT_DIR}/scripts/agent_daemon.sh"

OPENCLAW_REPO="local/mock" \
DRY_RUN=1 \
RUN_ONCE=1 \
MOCK_ISSUES_FILE="${MOCK_JSON}" \
STATE_DIR="${STATE_DIR}" \
"${ROOT_DIR}/scripts/agent_daemon.sh"

echo "----- dispatcher.log -----"
cat "${LOG_FILE}"

echo "----- assertions -----"
for expected in \
  "issue #101: ready -> in-dev" \
  "issue #101: in-dev -> in-test" \
  "issue #101: in-test -> ready-merge" \
  "RUN_ONCE complete"; do
  if grep -Fq "${expected}" "${LOG_FILE}"; then
    echo "PASS: ${expected}"
  else
    echo "FAIL: missing '${expected}'" >&2
    exit 1
  fi
done

echo "local pipeline verification: PASS"
