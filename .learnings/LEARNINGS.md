# Learnings

Corrections, insights, and knowledge gaps captured during development.

**Categories**: correction | insight | knowledge_gap | best_practice

---

## [LRN-20260517-001] user_facing_command_output_no_raw_json

**Logged**: 2026-05-17T00:00:00+08:00
**Category**: best_practice
**Priority**: high

### Learning
Metis user-facing command surfaces must not show raw `toJsonString()` output by default. Users should
see concise human summaries; raw JSON is reserved for explicit machine-output paths such as `--json`,
exports, protocol responses, persisted files, logs, or internal tool/RPC payloads that are not
displayed directly.

### Required Practice
When adding or changing CLI, IM native command, or Control UI command output, route structured data
through `gatewayFormatCommandOutput` / `gatewayPrintCommandOutput` or an equivalent human renderer.
Add tests that assert default output does not contain raw JSON keys.

### Tags
cli, im, control-ui, output-contract, json

---
