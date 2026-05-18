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
| Broadcast | Team broadcast settings persist selected member fanout, Gateway runs selected members as isolated turns, and aggregate rows expose per-agent status, error, detail, elapsed placeholder, delivery id, and answer. | Channel-specific live UX diagnostics still need Telegram/Feishu opt-in validation. |
| Workspace profiles | Control UI and RPC can list, read, and write `AGENTS.md`, `SOUL.md`, `TOOLS.md`, `IDENTITY.md`, `USER.md`, `HEARTBEAT.md`, `BOOTSTRAP.md`, and `MEMORY.md` through Gateway only. | `BOOTSTRAP.md` is supported but not auto-created. |
| Model state | Control UI and RPC can read/write per-agent `models.json` state, render provider/model chips from `agents.models.*`, and display redacted credential-source summaries. | Operators still need to configure real provider credentials explicitly per agent or allowed fallback source. |
| Telegram | Existing Telegram adapter has broad fake-tested group/topic/media/native-command coverage and AgentTeam alias routing baseline. | Telegram remains the first full IM validation path for future ChannelAdapter route extensions. |
| Feishu | Built-in Feishu support includes unified route context, account id, group/thread context, rich-event baselines, native `/feishu ...` command replies, OAuth lifecycle RPC/buttons, native OAPI client/toolset baseline, user/TAT/bot/app token provider support, tool-level repair actions, 108 action parity reporting, streaming-card controller, redacted status/doctor surfaces, and Feishu DM pairing visibility for policy, pending count, and approved count. | Real tenant UAT/TAT/app-token behavior, operator-executed app-scope grants, historical resource fetch, complete CardKit parity, and live event matrix validation remain release gates. |
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

Telegram acceptance is split between fake tests and an opt-in live smoke. The fake coverage checks account routes, group/topic session isolation, alias routing, and team broadcast aggregate rows without real Telegram network access. The live smoke is manual and skipped by default; only set `METIS_AGENTTEAM_LIVE_TELEGRAM=1` with an isolated `METIS_HOME`, a configured test bot account, `METIS_AGENTTEAM_TELEGRAM_ACCOUNT_ID`, and `METIS_AGENTTEAM_TELEGRAM_TEST_CHAT_ID`. Record only redacted account, group, topic, route, and pass/fail evidence. Do not paste bot tokens, proxy credentials, Telegram authorization headers, or real `~/.metis` paths into reports.

Feishu: create the Feishu app/bot manually in the Feishu developer console, configure the app credentials and event subscription in Metis, then use native `/feishu start`, `/feishu doctor`, `/feishu auth`, and `/feishu info --all` from Feishu conversations when available. Bind `feishu:<accountId>` or structured group/thread routes to member agents. Metis can guide setup, validate status, and save Gateway-backed configuration, but it cannot non-interactively create a Feishu bot/app or grant tenant permissions on your behalf. OAuth/OAPI and card behavior remain Gateway-backed and are not handled by browser-local files.

Control UI: open Agents -> Teams to create teams, edit members and aliases, preview bindings, apply Gateway RPC changes, edit allowed profile files, inspect per-agent model state, and review Feishu readiness/doctor guidance. The browser is a Gateway RPC client only.

## Feishu DM Access Policy

Feishu direct-message access is account-scoped. New Feishu accounts created through `metis agents add --feishu ...` use `dmPolicy="pairing"` and an empty `allowFrom` list by default. Operators can inspect the effective state without exposing sender details or secrets:

```bash
metis gateway channel get feishu
metis gateway channel runtime feishu
```

From Feishu itself, these native commands show the same redacted state for the active account:

```text
/feishu start
/feishu doctor
/feishu info --all
```

The summaries include `dmPolicy`, `allowFrom` count, `pairing pending=<n> approved=<n>`, and advice for the next operator action. They do not print pending codes, approved sender IDs, app secrets, tenant tokens, or authorization headers.

### Direct Configuration Allow

This path is currently available and is suitable for tests, one-person bots, or tightly trusted tenants. Edit `~/.metis/metis.json` and restart the target account.

Allow all Feishu DM users for a test account:

```json
{
  "gateway": {
    "feishu": {
      "accounts": {
        "feishu-writer": {
          "dmPolicy": "open",
          "allowFrom": ["*"]
        }
      }
    }
  }
}
```

Allow only specific Feishu user IDs:

```json
{
  "gateway": {
    "feishu": {
      "accounts": {
        "feishu-writer": {
          "dmPolicy": "allowlist",
          "allowFrom": ["ou_test_user"]
        }
      }
    }
  }
}
```

Restart the account after editing:

```bash
metis gateway channel restart feishu --account feishu-writer
```

Use `/feishu doctor` or `metis gateway channel get feishu` to verify the policy and counts. `dmPolicy="open"` intentionally allows any Feishu user who can DM the bot to reach the account, so prefer pairing outside short-lived tests.

### Pairing Authorization Loop

The recommended production path is the Feishu pairing loop. Confirm the pairing CLI target exists with:

```bash
metis pairing help
```

The expected operator flow is:

1. Keep the account on `dmPolicy="pairing"` with `allowFrom=[]`.
2. Restart the account:

```bash
metis gateway channel restart feishu --account feishu-writer
```

3. Ask the unapproved user to send a Feishu DM to the bot.
4. The user receives a pairing prompt in the same Feishu DM.
5. The operator approves the displayed code:

```bash
metis pairing approve feishu <CODE> --account feishu-writer
```

6. The user sends another DM. It should enter normal Gateway routing and receive an agent reply.

Operational checks:

```bash
metis gateway channel get feishu
metis gateway channel runtime feishu
```

Expected evidence is `pairing pending=<n> approved=<n>` changing as users request pairing and operators approve them. The default human-readable output must not be a raw JSON dump; use `--json` only for automation.

## Team Collaboration Semantics

`agents.teams.list`, `agents.teams.get`, `agents.teams.create`, `agents.teams.update`, and `agents.teams.delete` include a `semantics` object so CLI, UI, and automation can present the same product contract:

```json
{
  "singleRoute": "deterministic-single-agent",
  "broadcast": "explicit-fan-out",
  "manager": "member-or-default-agent-only",
  "autonomousManagerRuntime": false
}
```

Normal CLI, Telegram, and Feishu turns resolve to one route and one agent-scoped session. Broadcast is opt-in fan-out through `broadcast.enabled=true` and an explicit `broadcast.members` list. A manager is just another configured agent member or `defaultAgentId`; manager-style behavior comes from profile instructions and route bindings, not from a separate autonomous manager runtime.

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

### Create One Agent With Channel Credentials

This shortcut creates one managed agent. It does not create an agent team. Use `metis agents team create` only when you want a team template or a managed group of multiple agents. This capability also does not add a new subcommand; it extends the existing `metis agents add` command with optional channel credential parameters.

Metis does not create Telegram bots, Feishu apps, or QQ bots for you. Create those in the provider consoles first, then pass their test credentials to `metis agents add`. The credentials are stored in the existing Gateway channel account configuration, and the routing connection is stored in existing route bindings. They are not written into agent markdown files and are not stored under the agent entry itself.

Do not use production secrets while testing this flow. The examples below use obvious fake values. Bare command-line credentials may be saved by your shell history and are written to the local Metis configuration. CLI output, Gateway JSON responses, channel account inspection, logs, and errors must redact bot tokens and app secrets.

Create one agent and configure Telegram:

```bash
metis agents add \
  --agent tg-writer \
  --name "Telegram Writer" \
  --model qwen/qwen3.6-plus \
  --telegram-bot-token "123456789:fake-telegram-token"
```

Create one agent and configure Feishu:

```bash
metis agents add \
  --agent feishu-writer \
  --name "Feishu Writer" \
  --model qwen/qwen3.6-plus \
  --feishu "cli_fake_app_id:fake-feishu-secret"
```

Create one agent and configure QQ Bot:

```bash
metis agents add \
  --agent qq-writer \
  --name "QQ Writer" \
  --model qwen/qwen3.6-plus \
  --qqbot "1020000000:fake-qq-secret"
```

Create one agent and configure all three IM channels:

```bash
metis agents add \
  --agent zhihu-strategist \
  --name "Zhihu Strategist" \
  --model qwen/qwen3.6-plus \
  --feishu "cli_fake_app_id:fake-feishu-secret" \
  --qqbot "1020000000:fake-qq-secret" \
  --telegram-bot-token "123456789:fake-telegram-token"
```

When a channel credential is provided, Metis also creates the corresponding route binding for that agent. By default, the channel account id is the agent id. Use explicit account ids when the provider account name should differ:

```bash
metis agents add \
  --agent support-router \
  --name "Support Router" \
  --model qwen/qwen3.6-plus \
  --telegram-account support-test-bot \
  --telegram-bot-token "123456789:fake-telegram-token" \
  --feishu-account support-test-feishu \
  --feishu "cli_fake_app_id:fake-feishu-secret" \
  --qqbot-account support-test-qq \
  --qqbot "1020000000:fake-qq-secret"
```

Check the created agent, route bindings, and configured channel account summaries:

```bash
metis agents list
metis agents bindings --agent support-router
metis gateway channel get telegram
metis gateway channel get feishu
metis gateway channel get qq
```

Expected output:

- Default command output is human-readable, not a raw JSON object dump.
- `--json` output is still redacted.
- The `metis agents add` output includes a `Configured channel accounts` section for the requested test accounts, with secrets redacted.
- `metis agents bindings --agent support-router` shows route bindings for `telegram:support-test-bot`, `feishu:support-test-feishu`, and `qq:support-test-qq`.
- `metis gateway channel get <id>` is the configured channel account summary. It must show an `Accounts` section with the expected `<channel>/<accountId>` row, default account marker, `binding=<channel>:<accountId>`, and redacted credentials. A channel-level `configured=true` line alone is not enough to prove a specific bot/account is configured correctly.
- `metis gateway channel runtime <id>` is live adapter runtime state, not the full configured account list. Use it to check whether the adapter is registered/running, and use `gateway channel get <id>` for configured account summaries.
- Feishu and QQ app secret fields display as `[redacted]`.
- Fake raw values such as `fake-telegram-token`, `fake-feishu-secret`, and `fake-qq-secret` do not appear in stdout, stderr, logs, or Gateway RPC results.
- Bindings show routes such as `telegram:support-test-bot -> support-router`.

If a target channel account already exists with the same credential, Metis may reuse it. If it exists with a different credential, the command fails by default and must not create a partial agent, account, or binding. To intentionally replace that channel account, pass `--channel-overwrite`:

```bash
metis agents add \
  --agent support-router-replacement \
  --name "Support Router Replacement" \
  --feishu-account support-test-feishu \
  --feishu "cli_fake_app_id:fake-replacement-feishu-secret" \
  --channel-overwrite
```

If route binding ownership conflicts with another agent, the command must fail clearly and must not leave a half-created configuration. Confirm with `metis agents list`, `metis agents bindings --agent <id>`, and the channel account inspection commands above.

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
6. Check the channel readiness board for Telegram/Feishu runtime state, route coverage, repair steps, and the evidence-pack command.
7. Preview simple `channel[:account]` bindings or structured JSON route bindings, then read the binding conflict preview before applying.
8. Apply non-conflicting bindings through Gateway RPC.
9. List, load, edit, and save workspace profile files through `agents.files.*`.
10. Load and save per-agent model JSON through `agents.models.*`.
11. Review memory, heartbeat, Feishu account/status guidance, and local doctor checks.

The current Phase A/C management workflow also includes:

- model/provider chips derived from the selected member's `agents.models.get` response;
- a redacted credential-source preview so operators can see whether the member is using agent-local auth, model-local provider state, global config, or environment fallback;
- a Metis capabilities panel that lists only Metis-owned Gateway RPC surfaces, built-in profile files, built-in tools, built-in skills, and channel capabilities;
- a Feishu setup/repair wizard covering app credentials, event subscriptions, scope repair, group/thread routing, OAuth, OAPI, and card readiness with copyable redacted operator steps;
- a Telegram/Feishu readiness board that separates local setup from live evidence, links the manual evidence-pack command, and keeps Feishu repair scoped to linking an existing app/bot;
- a binding conflict preview that compares the current route preview with team binding metadata before `agents.bind`;
- a Feishu Auth & Doctor panel that consumes redacted `channels.status.channels.feishu.auth` or `.oauth`, `.doctor` or `.diagnostics`, and advertised OAPI capability strings when the Gateway provides them;
- a cultivation, memory, and heartbeat panel that summarizes `MEMORY.md`, `HEARTBEAT.md`, the currently loaded redacted file preview, and recent Feishu doctor findings from `channels.status`;
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
metis agents add --agent custom-reviewer --name Reviewer --model qwen/qwen3.6-plus
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

The broadcast aggregate response is deterministic in team member order and includes one `agents[]` row per planned turn:

```json
{
  "kind": "agent-team-broadcast-aggregate",
  "teamId": "content",
  "status": "partial",
  "deliveredCount": 1,
  "agents": [
    {
      "agentId": "content-writer",
      "status": "delivered",
      "delivered": true,
      "deliveryStatus": "delivered",
      "error": "",
      "detail": "delivered",
      "elapsedMs": 0,
      "answer": "writer answer"
    },
    {
      "agentId": "content-reviewer",
      "status": "not-delivered",
      "delivered": false,
      "deliveryStatus": "send-failed",
      "error": "synthetic send failure",
      "detail": "send-failed: synthetic send failure",
      "elapsedMs": 0,
      "answer": ""
    }
  ]
}
```

`elapsedMs` is present for every row. The current aggregate builder does not receive precise per-agent runner timing, so it emits `0` as a stable placeholder and uses `detail` for the testable human-facing reason. `detail` is derived from delivery status and error, and missing execution results are reported as `missing-result: no execution result for broadcast member`.

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

The Control UI Teams page shows redacted `channels.status` account state, the default account, thread-session configuration, group count, and whether OAuth/OAPI/doctor capability signals are visible in the current Gateway status contract. Feishu account status now also carries route diagnostics (`channel`, `accountId`, binding status, group/thread/session settings) and live-readiness next steps so operators can distinguish missing credentials, disabled accounts, stopped runtimes, and true live-routing blockers without exposing app credentials.

The Teams page is read-only for secrets and token files. Configure Feishu accounts, app credentials, and OAuth state through Gateway configuration, Gateway-backed commands/RPCs, or operator-managed backend files, not by writing browser-local files. Secret-like values are redacted in status display and repair copy text; they should not be stored in workspace profile files.

### Feishu OAPI Repair Results

Feishu OAPI tools return structured JSON instead of writing auth files from the tool layer. When a user token is absent, user scopes are missing, app scopes are missing, or app credentials are missing, the tool result includes a redacted `repair_action` that Gateway, IM commands, and Control UI can consume. User-auth repair actions point at `channels.feishu.auth.start`; app-scope and credential repair actions are `operator_required` and do not start network calls.

Multiple `auth_required` or `scope_missing` tool failures in the same turn, account, and user context are merged into one repair payload with `merged_scopes`. The merge is a diagnostic/UX contract only; tools must not directly write real token files, app secrets, or authorization headers.

Each OAPI `scope_diagnostic` includes mode-specific repair hints for `user_access_token`, `tenant_access_token`, `bot_access_token`, and `app_access_token`. User authorization hints point to `/feishu auth` / `channels.feishu.auth.start`; app-scope and app-credential hints stay operator-required and point to Feishu Developer Console guided setup.

To prepare read/write OAPI smoke requests without credentials or network, use the `feishu_oapi_smoke_plan` tool from the normal tool runtime:

```json
{
  "cases_json": "[{\"tool\":\"feishu_fetch_doc\",\"action\":\"default\",\"accountId\":\"tenant-a\",\"params\":{\"document_id\":\"doccn_demo\"}}]",
  "default_account_id": "tenant-a"
}
```

The planner returns redacted method/path/query/body metadata, required scopes, token mode, and read/write classification. It never performs token lookup, never sends Feishu network traffic, and marks write smoke as external-resource-required until a real test tenant/resource is provided.

Feishu OAPI live validation is also opt-in. Without `METIS_FEISHU_OAPI_LIVE_SMOKE=1`, `feishuOapiLiveSmokeHarnessFromEnv()` returns `skipped`; when `METIS_FEISHU_OAPI_LIVE_REPORT_DIR` is set, it also writes a redacted `report.json` in that directory. Real OAPI smoke additionally requires `METIS_FEISHU_OAPI_LIVE_ACCESS_TOKEN`, `METIS_FEISHU_OAPI_LIVE_USER_SCOPES`, `METIS_FEISHU_OAPI_LIVE_APP_SCOPES`, and `METIS_FEISHU_OAPI_LIVE_CASES_JSON`.

### Feishu OAuth Live Smoke

Feishu OAuth live validation is opt-in. By default, Metis does not contact the real Feishu network and does not write OAuth token files under the user's normal `~/.metis` token store. To prepare an operator-visible runbook/checklist without live network access, call:

```bash
metis gateway call channels.feishu.auth.liveSmoke '{"accountId":"tenant-a","outputDir":"/tmp/metis-feishu-auth-smoke"}'
```

Without `METIS_FEISHU_LIVE_AUTH_SMOKE=1`, the result is `skipped` with a redacted `report.json` under the output directory. The report still lists the live acceptance fixture paths for `start.json`, `status.json`, `poll.json`, `complete.json`, `refresh.json`, and `revoke.json`.

For a real test tenant, use a temporary home and explicit report directory:

```bash
export METIS_HOME="/tmp/metis-feishu-live-auth-home"
export METIS_FEISHU_LIVE_AUTH_SMOKE=1
export METIS_FEISHU_LIVE_AUTH_REPORT_DIR="/tmp/metis-feishu-live-auth-report"
metis gateway call channels.feishu.auth.liveSmoke '{"accountId":"tenant-a"}'
```

The live smoke uses temporary token/session stores under the report directory, runs the Feishu OAuth lifecycle in order (`start`, `status`, `poll`, `complete`, `refresh`, `revoke`), and writes only redacted JSON fixtures. The fixtures must not contain `appSecret`, `accessToken`, `refreshToken`, device codes, or `Authorization` headers. If app credentials are missing, the smoke writes a `configuration_error` report and performs no network call.

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

If a running Gateway does not expose one of these fields, the UI should show a clear unavailable diagnostic for that capability instead of pretending that Feishu OAuth, OAPI, or doctor status is fully wired.

### Feishu Card, Event, And Resource Validation

Feishu streaming replies can use the native interactive-card path when the account config sets `streaming` to `partial` or `card`. The fake gateway tests cover card create, patch, final update, abort, text fallback, unavailable-card termination, footer metrics, long text, markdown tables, image-key replacement, and rate-limit fallback. If card creation or patching fails with a recoverable status such as `rate_limited`, `table_size_limit`, or `message_unavailable`, Metis sends a text fallback instead of silently dropping the answer.

Rich Feishu inbound events are normalized into Gateway `InboundMessage` rows with safe system-event kinds for card actions, reactions, drive comments, bot membership, VC invitations, and bitable field changes. Message replay fixtures cover text, post, image, file, audio, video, interactive card messages, merge-forward metadata, unsupported events, unsupported message types, malformed messages, dedup, account id, app ownership, and thread projection.

Current-turn Feishu media stays metadata-only unless `media.downloadEnabled` is explicitly enabled in the backend config. Historical message/resource reads use the OAPI media tool boundary and return structured `auth_required`, `scope_missing`, or success results in fake tests. Live historical resource validation must use a test tenant and temporary cache directory; do not fetch production files or write media under a real user home during acceptance.

Card and event replay live checks are opt-in only:

```bash
export METIS_FEISHU_LIVE_CARD_SMOKE=1
export METIS_FEISHU_LIVE_EVENT_REPLAY_SMOKE=1
```

Live evidence must be redacted before it is committed or shared. Remove bot tokens, app secrets, access tokens, refresh tokens, `Authorization` headers, user private content, tenant secrets, and raw media bytes. Record only stable resource identifiers, status values, missing scope names, and pass/fail notes.

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

## Manual Acceptance Gate

Use an isolated test home for manual AgentTeam checks. Copy these commands into the current terminal before running the manual checks. `export METIS_HOME=...` means this terminal and the processes it starts will use `/tmp/metis-agentteam-manual-acceptance` as the Metis home; it is not a permanent setting and must be repeated in a new terminal. Do not point live Telegram or Feishu tests at production bots, tenants, groups, or the real `~/.metis` unless that is an explicit release decision:

```bash
export CANGJIE_HOME="/path/to/cangjie-sdk-1.0.0"
source "$CANGJIE_HOME/envsetup.sh"
export DYLD_LIBRARY_PATH="/opt/homebrew/opt/openssl@3/lib:$DYLD_LIBRARY_PATH"
export METIS_HOME="/tmp/metis-agentteam-manual-acceptance"
```

`source "$CANGJIE_HOME/envsetup.sh"` is expected because it loads the Cangjie SDK into the current shell. Do not source the acceptance gate itself; run that gate with `bash`.

Run the helper before recording manual acceptance. Run it as a separate process; do not use `source` or `.`, because the helper exits with a process status and sourcing it can close your current shell.

```bash
bash scripts/agentteam-manual-acceptance-gate.sh
```

The helper disables interactive pagers for its own process (`GIT_PAGER=cat`, `PAGER=cat`, `LESS=-F -X`), so it must not open `less` and must not require pressing `q` to return to your shell. A successful run ends with these lines:

```text
[agentteam-gate] manual acceptance gate completed
[agentteam-gate] report JSON: /tmp/metis-agentteam-manual-acceptance/agentteam-manual-acceptance-report/report.json
[agentteam-gate] manual template: /tmp/metis-agentteam-manual-acceptance/agentteam-manual-acceptance-report/manual-acceptance-template.md
```

The helper rejects the default real home, checks this doc for stale Feishu/AgentTeam claims, verifies the Feishu OAPI capability baseline, runs non-interactive `git --no-pager diff --check`, and runs the browser smoke only when `METIS_AGENTTEAM_CONTROL_UI_URL` is set. For example, after building the UI and starting Gateway or a static preview:

```bash
export METIS_AGENTTEAM_CONTROL_UI_URL="http://127.0.0.1:3000/"
bash scripts/agentteam-manual-acceptance-gate.sh
```

The helper also writes a redacted acceptance evidence pack. With the commands above, the directory is `/tmp/metis-agentteam-manual-acceptance/agentteam-manual-acceptance-report` unless you explicitly set `METIS_AGENTTEAM_REPORT_DIR`. To use a shorter fixed directory, run `export METIS_AGENTTEAM_REPORT_DIR="/tmp/metis-agentteam-manual-acceptance-report"` before the helper. After the helper finishes, check the files with:

```bash
REPORT_DIR="${METIS_AGENTTEAM_REPORT_DIR:-$METIS_HOME/agentteam-manual-acceptance-report}"
echo "REPORT_DIR=$REPORT_DIR"
ls -l "$REPORT_DIR/report.json" "$REPORT_DIR/manual-acceptance-template.md"
```

`report.json` is the machine-readable status report. `manual-acceptance-template.md` is the human record template where the operator records pass/fail notes and redacted evidence. The pack records skipped live Telegram/Feishu/OAuth/OAPI/CardKit/rich-event gates when the opt-in variables are absent, records `external-resource-required` when an opted-in gate is missing test resources, and scans the pack for secret-like token/header patterns before passing.

The browser smoke verifies `customElements.get("metis-app")`, visible Metis UI content, no page errors, and no failed JavaScript/CSS requests. Live Telegram and Feishu steps are opt-in manual checks; set `METIS_AGENTTEAM_LIVE_TELEGRAM=1` or `METIS_AGENTTEAM_LIVE_FEISHU=1` only with test credentials and record account, tenant, date, scopes, pass/fail, and skipped items. When Telegram live smoke is opted in, also set `METIS_AGENTTEAM_TELEGRAM_ACCOUNT_ID` and `METIS_AGENTTEAM_TELEGRAM_TEST_CHAT_ID`; the gate still does not read bot tokens or access real Telegram by itself. `report.json` includes a `releaseVerification` section covering the Cangjie clean/build/test command, UI build, browser smoke URL state, the manual gate itself, and live-gate opt-in status. If default `cjpm test` concurrency flakes, record that result and a `cjpm test -j 1` run rather than treating it as an AgentTeam feature failure.

Before handing an AgentTeam change to the release branch, run the focused checks for the touched area and the repository gate:

```bash
cjpm test src/gateway/core --filter GatewayAgentTeamBroadcastTest --no-color
cjpm test src/gateway/runtime --filter GatewayServerMethodsAgentsTest --no-color
git diff --check
```

For full integration, use:

```bash
cjpm clean
cjpm build -i
cjpm test
npm --prefix ui test
npm --prefix ui run build
bash scripts/agentteam-manual-acceptance-gate.sh
```

Record redacted live evidence in the generated `manual-acceptance-template.md` and the matching release evidence document.

## Current Limits

- `metis agents bind` intentionally exposes the simple `channel[:account]` form. Use Gateway RPC JSON payloads for peer/thread/team/role binding matches.
- Migration dry-run is read-only. It previews diagnostics and route-binding application but does not rewrite `session.dmScope`, model state, auth profiles, or workspace files automatically.
- Manager delegation is currently a configuration/profile pattern using a normal manager agent. Deterministic fan-out is the implemented team collaboration mode when `broadcast.enabled=true`; full manager-delegation product policy remains planned work.
- Feishu AgentTeam routing is not the same as a complete Feishu plugin platform. Message routing, native command replies, OAuth lifecycle RPC/buttons, native OAPI client/toolset baseline, user/TAT/bot/app token provider support, tool-level repair diagnostics, streaming-card controller, redacted status, and dry-run diagnostics exist. Real tenant token behavior, operator-completed scope repair, historical resource downloads, complete CardKit parity, and live tenant event/OAPI validation remain release gates unless a later release note says otherwise.
- Metis does not automatically create Feishu apps or bots. `application:application:self_manage` is treated as a diagnostic/setup permission for scope/app inspection, not as proof that Metis can create an app, enable a bot, configure event subscriptions, import scopes, publish, or pass review through OAPI. Use guided setup to link an existing Feishu app/bot until Feishu platform evidence proves a supported API path.
- The Control UI capability panel is not a plugin marketplace. It lists Metis-owned built-in tools, skills, profile files, channel capabilities, and RPC surfaces only.
- Feishu auth controls in Control UI call Gateway-backed auth lifecycle RPCs when available. Browser code must not create, edit, or delete Feishu token files.
- Live Telegram and Feishu operation still depends on the normal channel credentials and account setup. This guide does not require real Telegram or Feishu network access.
