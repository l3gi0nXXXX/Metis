# Metis Subagents

Metis subagents run through the existing Gateway session runtime. CLI, Telegram, control-ui, and natural-language tool calls all use the same managed session store, run records, policy checks, and completion notice path.

## CLI

Spawn a background subagent:

```text
/subagents spawn explorer "分析 gateway restart 的执行链路，完成后通知当前会话"
```

Control existing runs:

```text
/subagents list
/subagents list active
/subagents list stale
/subagents list recorded
/subagents list history
/subagents list all
/subagents status <runId>
/subagents logs <runId>
/subagents cleanup stale
/subagents kill <runId>
/subagents steer <runId> "补充检查配置读取路径"
```

Batch delegation is available through the Gateway tool `sessions_batch_delegate`; natural language can request several background tasks in one turn.

## Telegram

Use the same command shape in a chat or thread:

```text
/subagents spawn reviewer "审查当前任务的风险和测试缺口"
```

The accepted response is sent immediately. Completion, failure, timeout, or cancellation notices are routed back to the requester session/thread recorded on the run.

## State Model

The persisted run record keeps the lifecycle `status`, while the Gateway process knows whether a live future or process still exists. User-facing commands and UI expose the derived `effectiveState` so stale records are not mistaken for active subagents.

- `running` or `queued`: a live background run exists.
- `stale`: the run record is non-terminal, but no live future/process exists in the current Gateway process.
- `recorded`: the task was recorded by design, usually from `background: false`, and no live run was started.
- `succeeded`, `failed`, `cancelled`, `timed_out`: terminal history rows.

Use `effectiveState` or `isActive` to decide whether a subagent is really running. Do not use persisted `status=running` alone for that decision.

## Natural Language

The main agent can trigger subagents when the user asks for background or parallel work:

```text
启动一个 explorer subagent 后台分析 gateway runtime，完成后回到当前会话通知我。
```

For parallel work:

```text
并行启动三个 subagent：explorer 分析代码路径，reviewer 审查风险，test_generator 设计测试。完成后分别通知当前会话。
```

## Custom AGENT.md Agents

Custom subagents live under:

```text
~/.metis/agents/<agent-id>/AGENT.md
```

Example:

```markdown
id: reviewer
name: Reviewer
description: Review code changes and find bugs.
model: openai/gpt-4.1
tools: fileRead,grepSearch
background: true
isolation: worktree
maxTurns: 7
---
# Instructions
Focus on correctness, regressions, and missing tests.
```

Custom agents must be enabled by policy before they can run.

## Policy And Safety

Subagents are governed by `gateway.subagents` in `metis.json`. The policy controls:

- enabled/disabled state
- allow and deny lists
- custom agent permission
- write-agent permission
- maximum concurrent subagents
- maximum children per session
- maximum spawn depth
- default and maximum timeout
- allowed context modes
- allowed isolation modes
- whether write-capable agents require worktree isolation

Write-capable subagents should use `worktree` isolation unless a user explicitly accepts shared-workspace risk.

## Control UI

The Gateway control-ui exposes a Subagents panel. It shows active and historical run rows with:

- `runId`
- `sessionKey`
- `effectiveState`
- persisted status
- agent id
- runtime
- live process/future state
- notice status

Available actions:

- `Status`: fetch current run record.
- `Logs`: fetch transcript-backed logs.
- `Kill`: cancel a non-terminal run.

The panel uses the Gateway API routes:

```text
GET/POST /api/subagents/list
POST     /api/subagents/status
POST     /api/subagents/logs
POST     /api/subagents/kill
```

The underlying RPC methods are:

```text
subagents.list
subagents.status
subagents.logs
subagents.kill
subagents.cleanup
```

These routes do not bypass Gateway. They call the same managed subagent control path as CLI and Telegram commands.
