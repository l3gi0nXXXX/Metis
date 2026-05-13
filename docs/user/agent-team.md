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

Create a PM/writer/reviewer team from the built-in template:

```bash
metis agents team create --team content --name "Content Team" --template pm-writer-reviewer
metis agents team list
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
metis agents team get --team content
metis agents team update --team content --name "Content Ops Team"
metis agents team delete --team content
```

The same operations are also available through Gateway RPC for automation:

```bash
metis gateway call agents.teams.create '{"id":"content","displayName":"Content Team","template":"pm-writer-reviewer"}'
metis gateway call agents.teams.list
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

`agents.models.get` also returns a redacted `credentialSource` summary. Metis resolves provider credential status in this order: the agent's `auth-profiles.json`, the agent's `models.json` provider entry, global `models.providers`, then environment fallback. Missing per-agent auth does not implicitly read another agent or the main auth file; copying `auth-profiles.json` into an agent must be explicit.

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

The binding CLI covers channel/account routing. More specific route matches such as peer, thread, team, or role matches are supported by the resolver and by Gateway RPC payloads. Use `agents.teams.create`, `agents.teams.update`, or `agents.bind` through `metis gateway call` when you need those richer JSON binding objects.

Team-level `bindings` are compiled into global runtime route bindings during team create/update. If a proposed route conflicts with an existing agent route, Metis rejects the team change without writing a partial config.

Team aliases can route group messages by text mention patterns, for example `/agent writer` or `@writer`, when the channel inbound event reaches Gateway with mention metadata.

## Migration Dry Run

Preview AgentTeam diagnostics and proposed route-binding changes without writing config:

```bash
metis agents migrate --dry-run
metis agents migrate --dry-run --json
```

To inspect an older config file without changing the active config:

```bash
metis agents migrate --dry-run --config ./legacy-metis.json --json
```

To preview route binding changes, pass one or more JSON binding objects:

```bash
metis agents migrate --dry-run --binding-json '{"type":"route","agentId":"content-writer","match":{"channel":"telegram","accountId":"bot-a"}}'
```

The underlying RPC is `agents.migration.dryRun`. It accepts `configRoot` and `proposedBindings` and returns a read-only report with doctor findings, summary, and binding apply preview.

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

- `metis agents bind` intentionally exposes the simple `channel[:account]` form. Use Gateway RPC JSON payloads for peer/thread/team/role binding matches.
- Migration dry-run is read-only. It previews diagnostics and route-binding application but does not rewrite `session.dmScope`, model state, auth profiles, or workspace files automatically.
- Live Telegram and Feishu operation still depends on the normal channel credentials and account setup. This guide does not require real Telegram or Feishu network access.
