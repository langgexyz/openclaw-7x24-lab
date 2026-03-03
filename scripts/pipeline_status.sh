#!/usr/bin/env bash

set -euo pipefail

if [[ -z "${OPENCLAW_REPO:-}" || ! "${OPENCLAW_REPO}" =~ ^[^/]+/[^/]+$ ]]; then
  echo "Error: OPENCLAW_REPO must be set in owner/repo format" >&2
  exit 1
fi

labels=(new ready in-dev in-test ready-merge blocked done)

printf 'Pipeline Status: %s\n' "$OPENCLAW_REPO"

for label in "${labels[@]}"; do
  count=$(gh issue list \
    --label "$label" \
    --repo "$OPENCLAW_REPO" \
    --state all \
    --json number \
    --limit 1000 | jq 'length')
  printf '%-12s%3d\n' "${label}:" "$count"
done
