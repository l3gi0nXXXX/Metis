# Metis AgentTeam

AgentTeam lets one Gateway runtime manage multiple named agents, route IM accounts to specific agents, and keep each agent's workspace, model state, and session state separate. The current user-facing surface is a mix of stable `metis agents ...` CLI commands, Gateway RPC calls, and the Control UI Agents -> Teams page.

Telegram and Feishu are the first-priority IM targets for AgentTeam. Other IM adapters should extend through the same `ChannelAdapter` inbound model, route binding, account, peer, and thread semantics instead of adding agent routing inside each adapter.

## Collaboration Modes

The default product semantics are deterministic Gateway routing plus optional deterministic fan-out. A normal route resolves one inbound CLI, Telegram, or Feishu turn to one agent and one agent-scoped session. When team `broadcast.enabled` is `true`, Gateway fans the same inbound turn out to the configured `broadcast.members` list, keeps each member's workspace/model/session isolated, and builds an aggregate response with per-agent status.

Manager delegation can coexist with this model, but it is not a separate productized runtime yet. Today, configure a manager as a normal team member or `defaultAgentId`, give it profile instructions in `AGENTS.md`/`SOUL.md`, and bind IM routes to that manager when you want manager-style triage. Any handoff still runs through normal Gateway route/session boundaries; Metis does not yet provide autonomous manager task decomposition, cross-agent handoff policy, or a separate manager-delegation execution engine.

## Supported Capability Matrix

| Area | Supported now | Remaining gap |
| --- | --- | --- |
| Agent isolation | Managed agents have separate workspace, `agentDir`, `models.json`, auth profile path, and sessions path. | Some runtime fallback diagnostics still need broader end-to-end coverage. |
| Team management | `agents.teams.*` and Control UI can create, list, update, delete, edit members, set default member, edit aliases, edit bindings JSON, and reject binding conflicts without partial writes. | Template library and assisted onboarding remain intentionally small. |
| Route bindings | Telegram and Feishu can use shared route semantics for channel, account, peer, thread, team, and role matches through Gateway RPC. The Control UI binding builder previews simple and structured payloads before apply. | Feishu real-account thread capability cache and deeper group-policy diagnostics are still being expanded. |
| Broadcast | Team broadcast settings persist selected member fanout and the Control UI can select or clear broadcast members. | Runtime failure aggregation and channel-specific UX diagnostics remain partial. |
| Workspace profiles | Control UI and RPC can list, read, and write `AGENTS.md`, `SOUL.md`, `TOOLS.md`, `IDENTITY.md`, `USER.md`, `HEARTBEAT.md`, `BOOTSTRAP.md`, and `MEMORY.md` through Gateway only. | `BOOTSTRAP.md` is supported but not auto-created. |
| Model state | Control UI and RPC can read/write per-agent `models.json` state, render provider/model chips from `agents.models.*`, and display redacted credential-source summaries. | Operators still need to configure real provider credentials explicitly per agent or allowed fallback source. |
| Telegram | Existing Telegram adapter has broad fake-tested group/topic/media/native-command coverage and AgentTeam alias routing baseline. | Telegram remains the first full IM validation path for future ChannelAdapter route extensions. |
| Feishu | Built-in Feishu adapter maps fake webhook payloads to unified route context, account id, group/thread context, gate diagnostics, metadata-only attachments, native `/feishu ...` command replies, redacted account status surfaces, and Control UI auth/doctor fallback rows. | Full OpenClaw Lark-style OAuth/UAT runtime, real OAPI tools, historical resource fetch, streaming cards, and thread-capable real-client cache are partial or planned. |
| Migration | `agents.migration.dryRun` is read-only, previews doctor findings, binding apply, redacted config preview, and Feishu single-account migration suggestions. | Future migration may add apply-mode helpers after dry-run acceptance, but it must not rewrite user config silently. |

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

## Use AgentTeam From Each Surface

CLI: use `metis agents team create/list/get/update/delete` for the common team lifecycle, `metis agents bind/unbind` for simple channel/account routes, and `metis gateway call agents.teams.update ...` for richer structured bindings or broadcast settings. The CLI does not create Telegram bots, Feishu apps, or provider credentials for you; create those in their provider consoles and then configure Metis.

Telegram: configure the built-in Telegram channel with an existing bot token, then bind `telegram:<accountId>` or a structured route with group/topic peer data to a member agent. Native Telegram commands such as `/focus`, `/unfocus`, `/agents`, and `/subagents` continue to enter the same Gateway route/session path.

Feishu: create the Feishu app/bot manually in the Feishu developer console, configure the app credentials and event subscription in Metis, then use native `/feishu start`, `/feishu doctor`, `/feishu auth`, and `/feishu info --all` from Feishu conversations when available. Bind `feishu:<accountId>` or structured group/thread routes to member agents. Metis can guide setup, validate status, and save Gateway-backed configuration, but it cannot non-interactively create a Feishu bot/app or grant tenant permissions on your behalf. OAuth/OAPI and card behavior remain Gateway-backed and are not handled by browser-local files.

Control UI: open Agents -> Teams to create teams, edit members and aliases, preview bindings, apply Gateway RPC changes, edit allowed profile files, inspect per-agent model state, and review Feishu readiness/doctor guidance. The browser is a Gateway RPC client only.

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

## Manage Teams In Control UI

Open the Gateway Control UI and go to Agents -> Teams. The page is a Gateway RPC client; it does not write local files directly from the browser.

The Teams page supports this workflow:

1. Create a template-backed team or switch the template field to custom members.
2. Add or edit members with `agentId`, role, and display name.
3. Choose the default member used when a route does not resolve to a more specific member.
4. Add aliases such as `@writer` or `/agent review`.
5. Configure broadcast and select the exact members included in fanout.
6. Preview and apply simple `channel[:account]` bindings or structured JSON route bindings.
7. List, load, edit, and save workspace profile files through `agents.files.*`.
8. Load and save per-agent model JSON through `agents.models.*`.
9. Review Feishu account/status guidance and local doctor checks.

The current Phase A/C management workflow also includes:

- model/provider chips derived from the selected member's `agents.models.get` response;
- a redacted credential-source preview so operators can see whether the member is using agent-local auth, model-local provider state, global config, or environment fallback;
- a Metis capabilities panel that lists only Metis-owned Gateway RPC surfaces, built-in profile files, built-in tools, built-in skills, and channel capabilities;
- a Feishu Auth & Doctor panel that consumes redacted `channels.status.channels.feishu.auth` or `.oauth`, `.doctor` or `.diagnostics`, and advertised OAPI capability strings when the Gateway provides them;
- explicit fallback rows when those Feishu status fields are missing.

The page keeps advanced JSON textareas for compatibility with automation. Before sending create/update RPCs, the controller trims member and alias fields, drops incomplete alias/member rows, de-duplicates broadcast members, and keeps selected broadcast members inside the configured member set.

The UI redacts secret-like status text before display. Do not paste app secrets, access tokens, refresh tokens, bot tokens, provider keys, or authorization headers into team names, aliases, workspace markdown, or comments.

The UI does not write `~/.metis`, token files, Feishu app credentials, or agent workspace files directly from browser code. Profile files and model state are saved only through Gateway RPC. Feishu auth start, token refresh, and doctor probes must stay behind Gateway RPC or native `/feishu ...` commands.

## Edit Agent Workspace Files

Each managed agent has its own workspace, `agentDir`, sessions directory, `models.json`, `auth-profiles.json`, and supported profile-file set. One agent's profile, model state, auth profile, and session history are not shared with another agent unless an operator explicitly copies or configures that state.

Each managed agent workspace has these auto-created profile files:

```text
AGENTS.md
SOUL.md
TOOLS.md
IDENTITY.md
USER.md
HEARTBEAT.md
MEMORY.md
```

Metis also supports `BOOTSTRAP.md` as an explicit setup-state file. It is not auto-created, but `agents.files.list` returns it as a missing supported profile file until the operator creates it with `agents.files.set`.

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
| `HEARTBEAT.md` | Lightweight status, recurring check notes, and continuity hints. |
| `BOOTSTRAP.md` | Optional explicit setup state loaded for full non-IM prompts when present. |
| `MEMORY.md` | Durable facts, goals, and decisions for future sessions. |

All eight supported profile names are agent-scoped:

```text
AGENTS.md
SOUL.md
TOOLS.md
IDENTITY.md
USER.md
HEARTBEAT.md
BOOTSTRAP.md
MEMORY.md
```

`BOOTSTRAP.md` is the only supported profile name in this list that Metis does not create automatically.

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

## Configure Broadcast Fanout

Team broadcast sends one inbound request to selected member agents while preserving isolated member workspaces, model paths, and sessions. Configure it through Control UI or RPC:

```bash
metis gateway call agents.teams.update '{"id":"content","broadcast":{"enabled":true,"members":["content-writer","content-reviewer"]}}'
```

When broadcast is disabled, Gateway falls back to normal single-agent route resolution. When broadcast is enabled with selected members, only those members participate in fanout.

Keep broadcast member ids aligned with the team's `members` array. The Control UI filters duplicate or unknown selected members during save.

## Feishu Startup And Status

Metis does not create a Feishu app or bot automatically. Before Metis can receive Feishu events, an operator must create or select a Feishu app in the Feishu developer console, enable the bot and event subscriptions, configure the app credentials in the Gateway-backed Metis config, and install or authorize the app for the target tenant/chat. Metis then provides setup guidance, status checks, OAuth start/status helpers, route binding, and redacted diagnostics.

Feishu channel startup still uses the normal Gateway channel configuration. After the Gateway is running, use the native Feishu commands from a Feishu conversation when available:

```text
/feishu start
/feishu doctor
/feishu auth
/feishu info --all
/feishu help
```

The Control UI Teams page shows redacted `channels.status` account state, the default account, thread-session configuration, group count, and whether OAuth/OAPI/doctor capability signals are visible in the current Gateway status contract.

Current Feishu status guidance is display-only in the Teams page. Configure Feishu accounts, app credentials, and OAuth state through Gateway configuration and Gateway-backed commands/RPCs, not by writing browser-local files. Secret-like values are redacted in status display; they should not be stored in workspace profile files.

For the richer Teams page, the preferred redacted Gateway status shape is:

```json
{
  "channels": {
    "feishu": {
      "capabilities": ["oauth:device-flow", "oapi:docs", "doctor"],
      "auth": {
        "accountId": "default",
        "status": "authorized",
        "tokenStatus": "authorized",
        "scopeSummary": "docs:read im:message"
      },
      "doctor": {
        "status": "ok",
        "findings": 0,
        "lastProbeAt": 1710000000000
      }
    }
  }
}
```

If the Gateway does not expose those fields yet, the UI shows "Auth status RPC missing", "Doctor status RPC missing", or "OAPI status RPC missing" rather than pretending that Feishu OAuth or OAPI is fully wired.

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

The underlying RPC is `agents.migration.dryRun`. It accepts `configRoot` and `proposedBindings` and returns a read-only report with doctor findings, summary, binding apply preview, and Feishu migration suggestions. The Feishu section previews `defaultAccountId`, `accounts`, `threadSession`, and `groups` target paths; it does not write config and redacts secret-like fields from the config preview.

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
- Manager delegation is currently a configuration/profile pattern using a normal manager agent. Deterministic fan-out is the implemented team collaboration mode when `broadcast.enabled=true`; full manager-delegation product policy remains planned work.
- Feishu AgentTeam routing is not the same as the full OpenClaw Lark plugin surface. Message routing, native command replies, redacted status, and dry-run diagnostics exist; real OAPI tools, historical resource downloads, streaming card parity, and complete OAuth/UAT runtime remain partial unless a later release note says otherwise.
- The Control UI capability panel is not a plugin marketplace. It lists Metis-owned built-in tools, skills, profile files, channel capabilities, and RPC surfaces only.
- Feishu auth controls in Control UI are status and guidance only until a stable Gateway auth-start/status RPC is present. Browser code must not create, edit, or delete Feishu token files.
- Source-backed AgentTeam parity tracking lives under `develop_steps/`, with the series-07 source recheck and Phase 8-9 closure notes as the current UI/docs baseline.
- Live Telegram and Feishu operation still depends on the normal channel credentials and account setup. This guide does not require real Telegram or Feishu network access.
