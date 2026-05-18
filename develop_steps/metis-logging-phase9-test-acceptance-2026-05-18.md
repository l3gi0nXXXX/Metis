# Metis Logging Phase 9 Test Acceptance Notes

Date: 2026-05-18

This note tracks the runnable Phase 9 test coverage added or verified in the
`logging-tests-20260518232846` worktree. OpenClaw source evidence remains in the
series-02 landing plan and is intentionally not duplicated here.

## Runnable Coverage

| Area | Automated check | Isolation strategy |
| --- | --- | --- |
| Logger redaction baseline | `src/gateway/logging/gateway_logging_test.cj` covers supported Authorization, Bearer, Telegram token, app secret, api_key, and URL password redaction in message and meta fields. | Sets `METIS_HOME`, `METIS_LOG_FILE`, and `METIS_CONSOLE_LEVEL` to temp values; no real token values. |
| Logger file cap baseline | `src/gateway/logging/gateway_logging_test.cj` verifies a small `maxFileBytes` suppresses later payloads. | Uses temp `metis.json` and temp log file under `/tmp`. |
| Structured logger meta | `src/gateway/logging/gateway_logging_test.cj` verifies direct logger meta is emitted as top-level JSON fields, not a `fields` string. | Writes one JSONL row to a temp log file. |
| Info message-body boundary | `src/gateway/core/gateway_service_telegram_native_test.cj` verifies the Telegram native fake flow logs message events and `textLen` without the full inbound body. | Uses fake adapter and fake model; no Telegram network. |
| Adapter fake lifecycle | `src/gateway/core/gateway_channel_runtime_test.cj` verifies fake multi-account channel start emits `channel.started` at info and keeps timing detail at debug. | Uses fake adapters only; no IM network. |
| Sidecar stdout/stderr | `scripts/metis-sidecar-logger.test.mjs` verifies protocol frames stay on stdout, diagnostics and patched console methods go to stderr, and known/query/key secrets are redacted. | Spawns Node with inline fixture code only. |
| Logs CLI | `src/core/support_surface_tests/program_cli_local_flows_test.cj` verifies default human `metis logs` output and `--json` machine output. | Uses temp `METIS_HOME` and temp log files. |
| Logs RPC | `src/gateway/runtime/gateway_rpc_server_methods_test.cj` verifies `logs.tail` uses the configured current log file and returns `file/cursor/size/lines/truncated/reset`. | Uses temp `METIS_HOME`, temp `METIS_LOG_FILE`, and local dispatcher. |

## Known Implementation Gaps Not Marked Passing

These are real gaps in the current implementation, so the test changes do not
pretend they are complete:

| Area | Current gap | Acceptance test to enable after implementation |
| --- | --- | --- |
| Timestamp offset | JSONL `time` is still formatted without timezone offset. | Assert `time` matches a local ISO timestamp with `+HH:MM`, `-HH:MM`, or `Z` equivalent. |
| OpenClaw-level redaction parity | Current redaction does not yet cover every planned class such as `sk-` tokens, PEM private keys, and CLI `--api-key` flags. | Extend logger redaction test inputs to those classes and assert the raw secrets are absent. |
| File cap warning and cached size | Current file cap suppresses later writes, but does not emit the one-time warning or prove cached/stat size accounting. | Assert one warning row is written once, later records are suppressed, and repeated cap hits do not add warnings. |
| Gateway event helper structured meta | Direct logger meta is structured, but `gatewayLogEventInfo/Debug/Error` still stores a `fields` string. | Assert message/channel helper output exposes `channel/accountId/status/textLen` as direct JSON fields and has no `fields` key. |
| Logs status recent-file edge case | `logs.status` currently errors when the logs directory contains fewer than the requested recent-file limit because recent-file iteration can reach an invalid index. | Add a temp-home `logs.status` test for 0, 1, and many log files after the implementation is fixed. |
| Gate clean state | The repo still has allowed legacy output points, and `scripts/logging-output-gate.sh` is outside this worker's write boundary. | After implementation workers clear legacy output, run the gate and require all disallowed counts to be zero. |

## Safety Rules

- Tests must set `METIS_HOME` to a temp directory before reading or writing Metis config.
- Tests must set `METIS_LOG_FILE` for logger/RPC log checks instead of relying on a user log file.
- IM tests must use fake adapters, fake transports, or local dispatcher calls only.
- Test secrets must be synthetic strings that cannot be real credentials.
- Sidecar tests must spawn local Node fixtures and must not contact external services.
