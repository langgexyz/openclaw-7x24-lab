#!/usr/bin/env bash
set -euo pipefail

REPO="${OPENCLAW_REPO:-}"
if [[ -z "${REPO}" ]]; then
  echo "OPENCLAW_REPO is required (example: langgexyz/openclaw-7x24-lab)" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LABELS_JSON="${ROOT_DIR}/ops/labels.json"

if ! command -v gh >/dev/null 2>&1; then
  echo "gh is required" >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 1
fi

jq -c '.[]' "${LABELS_JSON}" | while IFS= read -r item; do
  name="$(jq -r '.name' <<<"${item}")"
  color="$(jq -r '.color' <<<"${item}")"
  desc="$(jq -r '.description' <<<"${item}")"

  if gh label list --repo "${REPO}" --search "${name}" --json name | jq -e --arg n "${name}" 'any(.[]; .name==$n)' >/dev/null; then
    gh label edit "${name}" --repo "${REPO}" --color "${color}" --description "${desc}" >/dev/null
    echo "updated label: ${name}"
  else
    gh label create "${name}" --repo "${REPO}" --color "${color}" --description "${desc}" >/dev/null
    echo "created label: ${name}"
  fi
done

echo "done"
