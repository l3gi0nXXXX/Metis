# Metis AgentTeam series13 Phase 6 Control UI setup wizard completion

Date: 2026-05-15

Scope: Control UI worker for branch `work/agentteam-s13-ui-20260515`.

## Implemented

- Added an Agents -> Teams Feishu setup/repair wizard.
- Wizard checklist covers app credentials, event subscription, scope repair, group/thread routing, OAuth device flow, OAPI readiness, and card readiness.
- Repair guidance is copyable and redacted before clipboard writes.
- UI remains read-only for Feishu credentials and token state. Real changes are limited to existing Gateway RPC actions or explicit operator-managed backend configuration.
- Existing Teams profile support remains the eight-file set: `AGENTS.md`, `SOUL.md`, `TOOLS.md`, `IDENTITY.md`, `USER.md`, `HEARTBEAT.md`, `BOOTSTRAP.md`, and `MEMORY.md`.

## Tests Added

- Missing Feishu configuration renders the setup/repair wizard and clear guidance.
- Scope repair copy button writes redacted repair steps and does not expose bearer token text.

## Verification Notes

- Focused view test passed after red/green cycle: `npm --prefix ui test -- src/ui/views/agents-panel-teams.metis.test.ts`.
- Full required verification is recorded in the worker final report and commit.
