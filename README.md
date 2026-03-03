# openclaw-7x24-lab

A minimal 7x24 validation pipeline for OpenClaw multi-agent delivery:

- User files bug/feature in GitHub Issue
- Dispatcher picks `ready` issues
- `dev` agent starts implementation
- `test` agent validates
- Labels move through a strict state machine

## State Machine

`new -> ready -> in-dev -> in-test -> ready-merge -> done`

Failure path: `blocked`

## Labels

Required labels are defined in `ops/labels.json`.

Bootstrap once:

```bash
./scripts/bootstrap_labels.sh
```

## Local 7x24 Daemon (MVP)

Run dispatcher loop:

```bash
OPENCLAW_REPO=langgexyz/openclaw-7x24-lab ./scripts/agent_daemon.sh
```

Environment:

- `OPENCLAW_REPO` (required): `owner/repo`
- `OPENCLAW_POLL_SECONDS` (optional, default `120`)
- `DEV_AGENT_ID` (optional, default `dev`)
- `TEST_AGENT_ID` (optional, default `test`)

Prerequisites:

- `gh` logged in with repo write permission
- `jq` installed
- `openclaw` gateway running
- `dev` / `test` agents configured

## GitHub Automation

Workflow `.github/workflows/issue_state_machine.yml` keeps labels consistent and closes linked issues on merge.

## Notes

- This repository validates orchestration and lifecycle, not full autonomous coding quality.
- Keep one requirement per commit in implementation repos.
