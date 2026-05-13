# Metis AgentTeam

AgentTeam lets one Gateway runtime manage multiple named agents, route IM accounts to specific agents, and keep each agent's workspace, model state, and session state separate. The current user-facing surface is a mix of stable `metis agents ...` CLI commands and Gateway RPC calls for team operations.

## Start Gateway

Agent and AgentTeam management goes through the Gateway runtime. Start it before using the commands below:

```bash
cjpm run --skip-build --name metis --run-args "gateway run"
```

`gateway serve` is accepted as an alias:

```bash
cjpm run --skip-build --name metis --run-args "gateway serve"
```

In another shell, check that Gateway is reachable:

```bash
metis gateway status
metis gateway health
```

## Create One Agent

Create a managed agent with its own workspace, agent directory, and sessions directory:

```bash
metis agents add --agent content-writer --name "Content Writer" --model openai:gpt-4o-mini
metis agents list
metis agents summary
```

`metis agents add` bootstraps the agent workspace and reports the created `workspace` and `agentDir`. By default, managed agents use:

```text
~/.metis/workspaces/<agent-id>
~/.metis/agents/<agent-id>/agent
~/.metis/agents/<agent-id>/sessions
```

Update identity fields stored on the agent entry:

```bash
metis agents set-identity --agent content-writer --name "Content Writer" --theme "concise writing partner"
```

## Create A Team

Team creation currently uses Gateway RPC. There is no `metis agents team ...` CLI command yet.

Create a PM/writer/reviewer team from the built-in template:

```bash
metis gateway call agents.teams.create '{"id":"content","displayName":"Content Team","template":"pm-writer-reviewer"}'
metis gateway call agents.teams.list
```

The template creates these member agents if they do not already exist:

```text
content-pm
content-writer
content-reviewer
```

You can also create a team with explicit members:

```bash
metis gateway call agents.teams.create '{"id":"support","displayName":"Support Team","members":[{"agentId":"support-triage","role":"triage","name":"Support Triage"},{"agentId":"support-reply","role":"reply","name":"Support Reply"}],"defaultAgentId":"support-triage"}'
```

Inspect, update, or delete teams with RPC:

```bash
metis gateway call agents.teams.get '{"id":"content"}'
metis gateway call agents.teams.update '{"id":"content","displayName":"Content Ops Team"}'
metis gateway call agents.teams.delete '{"id":"content"}'
```

Deleting a team removes the team entry. It does not delete the member agent directories.

## Edit Agent Workspace Files

Each managed agent has a workspace with these bootstrapped files:

```text
AGENTS.md
SOUL.md
TOOLS.md
IDENTITY.md
USER.md
HEARTBEAT.md
MEMORY.md
```

Use `agents.files.*` RPC to list, read, and write files safely inside the selected agent workspace:

```bash
metis gateway call agents.files.list '{"agentId":"content-writer"}'
metis gateway call agents.files.get '{"agentId":"content-writer","name":"SOUL.md"}'
metis gateway call agents.files.set '{"agentId":"content-writer","name":"SOUL.md","content":"# Soul\n\nWrite concise, source-grounded drafts.\n"}'
```

Common file roles:

| File | Use |
| --- | --- |
| `SOUL.md` | Agent purpose, tone, boundaries, and decision preferences. |
| `AGENTS.md` | Durable operating rules, delegation notes, and handoff conventions. |
| `IDENTITY.md` | Human-facing name, theme, avatar note, and identity details. |
| `USER.md` | User preferences that are safe to share with this agent. Do not store credentials. |
| `TOOLS.md` | Workspace-specific tool expectations, allowed workflows, and local caveats. |
| `MEMORY.md` | Durable facts, goals, and decisions for future sessions. |

The RPC path rejects absolute paths, `~`, URI schemes, and `..` traversal. Keep file names workspace-relative.

## Configure Per-Agent Models

For a simple default model on the agent entry, use `metis agents add --model` when creating the agent:

```bash
metis agents add --agent reviewer --name Reviewer --model qwen:qwen-plus
```

For runtime model state in the agent's `models.json`, use `agents.models.*` RPC:

```bash
metis gateway call agents.models.get '{"agentId":"content-writer"}'
metis gateway call agents.models.set '{"agentId":"content-writer","state":{"primaryModelRef":"openai:gpt-4o-mini","runtimePrimaryModelRef":"openai:gpt-4o-mini","providers":[]}}'
```

The response redacts secret-like fields. Do not put provider secrets into workspace markdown files.

## Bind Telegram Or Feishu Accounts

Current CLI binding accepts `channel[:account]` and writes route bindings for one agent:

```bash
metis agents bind --agent content-writer --bind telegram:bot-a
metis agents bind --agent content-reviewer --bind feishu:default
metis agents bindings
metis agents bindings --agent content-writer
```

Use `telegram:<accountId>` for Telegram bot accounts and `feishu:<accountId>` for Feishu accounts. If the account id is omitted, the channel default is used:

```bash
metis agents bind --agent content-writer --bind telegram
```

Unbind a route when needed:

```bash
metis agents unbind --agent content-writer --bind telegram:bot-a
```

The binding CLI currently covers channel/account routing only. More specific route matches such as peer, thread, team, or role matches are understood by the resolver but do not yet have a complete friendly CLI.

## Recommended Session Scope

For multi-account Telegram or Feishu usage, set:

```json
{
  "session": {
    "dmScope": "per-account-channel-peer"
  }
}
```

This keeps direct-message session keys separated by agent, channel, account, and peer. It avoids sharing one direct-message history across different bot accounts or IM channels.

After editing `~/.metis/metis.json`, restart Gateway so the running process loads the new setting.

## Current Limits

- `agents.teams.*` exists as Gateway RPC today. A dedicated `metis agents team ...` CLI and Control UI panel are planned in later phases.
- `agentTeams[].bindings` is stored on the team object today, but it is not automatically compiled into global `bindings[]` runtime routing yet.
- `agentTeams[].aliases` can update member `groupChat.mentionPatterns`, but IM inbound alias or mention based member selection depends on later runtime work.
- `metis agents bind` currently exposes only `channel[:account]` binding. Use it for Telegram and Feishu account routing, and treat finer-grained team binding as a later phase.
- This guide does not require real Telegram or Feishu network access. Configure credentials and accounts through the normal channel setup docs for live operation.
