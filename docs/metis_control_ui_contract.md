# Metis Control UI Contract

This document defines the minimum gateway RPC contract that the bundled reference
Control UI expects from Metis.

Goal:
- Freeze a stable compatibility baseline.
- Avoid ad hoc fixes in `gateway_control_ui_ws.cj`.
- Only expand fields incrementally after the current minimum shape is stable.

## Rules

1. Stability first.
   For high-frequency methods, prefer a small safe payload over a richer payload
   that can destabilize the WS session.
2. No speculative fields.
   Only return fields the reference UI actually reads.
3. One layer at a time.
   For complex pages such as `Channels`, add one sub-structure at a time and
   validate before expanding further.
4. Never route compatibility through an expensive local RPC if the shape is
   incompatible or the method is known to destabilize the process.

## Priority Methods

These methods are the current compatibility baseline.

## AgentTeam IM Scope

Telegram and Feishu are the first-priority IM objects for AgentTeam control-plane flows. The UI should model them as channel/account/peer/thread route targets owned by Gateway. Other IMs should be added through the same ChannelAdapter and route-binding semantics, not by introducing IM-specific agent selectors in the UI contract.

Feishu fields in Control UI are configuration and diagnostics fields. They must not imply that the full OpenClaw Lark plugin surface is complete. Plugin-level capabilities such as Feishu docs, wiki, drive, task, calendar, resource download, OAuth/auth, and native `/feishu ...` commands should be shown only when the backing Gateway method exists.

## Chat Slash Commands

Control UI chat slash command metadata is maintained in `ui/src/ui/chat/slash-command-manifest.ts`.
The command palette, UI `/help` output, and local executor semantics must stay derived from that manifest.

Current local Control UI semantics:

| Command | Semantics | Output contract |
| --- | --- | --- |
| `/help` and `/commands` | Render the Control UI slash command list from the UI manifest. | Human-readable markdown; no raw JSON. |
| `/stop` | Abort only the current Control UI chat turn. It does not kill subagents and is not a Telegram-wide stop. | Short human-readable status. |
| `/kill <id|all>` | Abort matching sub-agent sessions in the current Control UI session subtree. `all` means active subagents under this session only. | Human-readable count/no-op/error summary; no duplicate raw RPC output. |
| `/steer [id] <message>` | Soft-inject guidance into the current active run or a named subagent. It requires an active run and does not restart the run. | Human-readable success/no-op/error summary. |
| `/redirect [id] <message>` | Abort and restart the current run or named subagent with a new message. | Human-readable success/error summary; current-session redirects may track the returned run id. |

Slash command defaults must be readable in the chat transcript. Raw JSON is reserved for explicit API/RPC consumers, not command output shown to users.

### 1. `channels.status`

Used by:
- upstream UI channel/controller sources

Request:
- `probe?: boolean`
- `timeoutMs?: number`

Minimum stable response:

```json
{
  "ts": 0,
  "channelOrder": ["qq", "feishu", "telegram", "discord", "slack"],
  "channelLabels": { "qq": "QQ" },
  "channelDetailLabels": { "qq": "QQ" },
  "channelSystemImages": { "qq": "" },
  "channelMeta": [
    { "id": "qq", "label": "QQ", "detailLabel": "QQ" }
  ],
  "channels": {},
  "channelAccounts": {
    "qq": []
  },
  "channelDefaultAccountId": {
    "qq": ""
  }
}
```

Hard requirements:
- `channelMeta` must be an array, not an object.
- `channels` must be an object keyed by channel id, not an array.
- `channelAccounts` must be an object keyed by channel id.
- `channelDefaultAccountId` must be an object keyed by channel id.

Expansion order:
1. `channelMeta[]`
2. `channelAccounts{}`
3. `channelDefaultAccountId{}`
4. `channels{}`

Current status:
- Stable minimal compatibility is in place.
- Rich `channels.status` expansion previously caused WS reconnects and `Out of memory`.
- Do not expand this method in bulk.

### 2. `agents.list`

Used by:
- upstream UI agent controller sources

Minimum response:

```json
{
  "defaultId": "general",
  "mainKey": "general",
  "scope": "gateway",
  "agents": [
    {
      "id": "general",
      "name": "General",
      "description": "",
      "avatar": "",
      "emoji": ""
    }
  ]
}
```

Hard requirements:
- `agents` must be an array.
- UI immediately calls `.some(...)` on `agents`.

### 3. `agent.identity.get`

Used by:
- Agent detail panels

Minimum response:

```json
{
  "agentId": "general",
  "name": "General",
  "avatar": "",
  "emoji": ""
}
```

### 4. `agents.teams.*`

Used by:
- Agents page `Teams` panel

Control UI calls:
- `agents.teams.list` with `{}`
- `agents.teams.get` with `{ "id": "<teamId>" }`
- `agents.teams.create` with `id`, `displayName`, and either `template` or `members`
- `agents.teams.update` with `id` plus changed `displayName`, `defaultAgentId`, `members`, `aliases`, or `bindings`
- `agents.teams.delete` with `{ "id": "<teamId>" }`

Minimum list response:

```json
{
  "teams": [
    {
      "id": "content",
      "displayName": "Content Team",
      "defaultAgentId": "content-writer",
      "members": [{ "agentId": "content-writer", "role": "writer", "name": "Writer" }],
      "aliases": [],
      "bindings": []
    }
  ],
  "count": 1
}
```

Hard requirements:
- `teams` must be an array.
- Team mutation responses must include `team`.
- Control UI treats `bindings` on the team as editable team metadata; applying an executable route uses `agents.bind` / `agents.unbind`.

### 5. `agents.models.get` / `agents.models.set`

Used by:
- Agents page `Teams` panel member model editor

Control UI calls:
- `agents.models.get` with `{ "agentId": "<memberAgentId>" }`
- `agents.models.set` with `{ "agentId": "<memberAgentId>", "state": { ... } }`

Minimum response:

```json
{
  "models": {
    "agentId": "content-writer",
    "path": "/abs/agentDir/models.json",
    "present": true,
    "primaryModelRef": "openai:gpt-5-mini",
    "runtimePrimaryModelRef": "openai:gpt-5-mini",
    "providerCount": 0,
    "diagnostics": [],
    "state": { "providers": [] }
  }
}
```

Hard requirements:
- `models.state` must be redacted before returning to the browser.
- Control UI sends the edited state back through Gateway only; it must not read or write agent directories directly.

### 6. `agents.bind` / `agents.unbind`

Used by:
- Agents page `Teams` panel binding builder

Control UI calls:
- `agents.bind` with `{ "agentId": "<memberAgentId>", "bind": "channel[:accountId]" }`
- `agents.unbind` with `{ "agentId": "<memberAgentId>", "bind": "channel[:accountId]" }`
- For structured routes, `agents.bind` / `agents.unbind` may use
  `{ "agentId": "<memberAgentId>", "bindings": [{ "type": "route", "agentId": "<memberAgentId>", "match": { ... } }] }`.
  The UI builds a read-only preview locally before submit because no dedicated
  binding preview RPC is currently part of this contract.

Minimum response:

```json
{
  "agentId": "content-writer",
  "added": ["telegram accountId=bot-a"],
  "skipped": [],
  "conflicts": []
}
```

### 7. `agents.migration.dryRun`

Used by:
- future team create/update previews
- migration diagnostics panels

Minimum response:

```json
{
  "kind": "agent-team-migration",
  "mode": "dry-run",
  "readOnly": true,
  "doctor": {},
  "bindingApply": {
    "added": [],
    "updated": [],
    "skipped": [],
    "conflicts": [],
    "configPreview": {}
  },
  "feishuMigration": {
    "channel": "feishu",
    "readOnly": true,
    "currentShape": "single-account",
    "defaultAccount": {
      "suggested": "default",
      "targetPath": "channels.feishu.defaultAccountId"
    },
    "accounts": {
      "suggested": [],
      "targetPath": "channels.feishu.accounts"
    },
    "threadSession": {
      "suggested": "enabled",
      "targetPath": "channels.feishu.threadSession"
    },
    "groups": {
      "currentCount": 0,
      "groupIds": [],
      "suggestedPath": "channels.feishu.groups"
    }
  }
}
```

Hard requirements:
- The method is read-only and must not write `~/.metis/metis.json`.
- `bindingApply.configPreview` must redact secret-like fields before returning to the browser.
- Feishu `defaultAccount`, `accounts`, `threadSession`, and `groups` are preview suggestions until an explicit apply workflow exists.

### 8. `agents.files.list`

Used by:
- upstream UI agent file controller sources
- Agents page `Teams` panel workspace profile editor

Minimum response:

```json
{
  "workspace": "/abs/path",
  "files": [
    {
      "name": "AGENTS.md",
      "path": "/abs/path/AGENTS.md",
      "exists": true,
      "size": 100,
      "updatedAtMs": 0
    }
  ]
}
```

Hard requirements:
- `files` must be an array.
- UI checks `list.files.some(...)`.
- Teams workspace profile editor filters the returned files to `SOUL.md`,
  `AGENTS.md`, `IDENTITY.md`, `USER.md`, `TOOLS.md`, `HEARTBEAT.md`,
  `BOOTSTRAP.md`, and `MEMORY.md`. `BOOTSTRAP.md` is supported but not
  auto-created; it can appear with `missing: true` until written explicitly.

### 9. `agents.files.get`

Minimum response:

```json
{
  "file": {
    "name": "AGENTS.md",
    "path": "/abs/path/AGENTS.md",
    "exists": true,
    "content": "..."
  }
}
```

### 10. `agents.files.set`

Minimum response:

```json
{
  "file": {
    "name": "AGENTS.md",
    "path": "/abs/path/AGENTS.md",
    "exists": true,
    "content": "..."
  }
}
```

### 11. `cron.status`

Used by:
- upstream UI cron controller sources

Minimum response:

```json
{
  "enabled": true,
  "jobs": 0,
  "nextWakeAtMs": 0
}
```

### 12. `cron.list`

Minimum response:

```json
{
  "jobs": [],
  "total": 0,
  "limit": 50,
  "offset": 0,
  "nextOffset": null,
  "hasMore": false
}
```

### 13. `cron.runs`

Minimum response:

```json
{
  "entries": [],
  "total": 0,
  "limit": 50,
  "offset": 0,
  "nextOffset": null,
  "hasMore": false
}
```

### 14. `sessions.usage`

Used by:
- upstream UI usage controller sources

Minimum response:

```json
{
  "updatedAt": 0,
  "startDate": "",
  "endDate": "",
  "sessions": [],
  "totals": {},
  "aggregates": {
    "messages": {},
    "tools": {},
    "byProvider": [],
    "byModel": [],
    "byAgent": [],
    "byChannel": [],
    "daily": []
  }
}
```

### 15. `usage.cost`

Minimum response:

```json
{
  "updatedAt": 0,
  "days": 0,
  "daily": [],
  "totals": {}
}
```

### 16. `config.get`

Minimum response:

```json
{
  "path": "gateway",
  "exists": true,
  "raw": "{}",
  "hash": "compat-hash",
  "parsed": {},
  "valid": true,
  "config": {},
  "issues": []
}
```

### 17. `config.schema`

Minimum response:

```json
{
  "path": "gateway",
  "schema": {
    "type": "object"
  }
}
```

### 18. `system-presence`

Minimum response:

```json
{
  "ts": 0,
  "uptimeMs": 0,
  "gateway": {}
}
```

### 19. `last-heartbeat`

Minimum response:

```json
{
  "ts": 0
}
```

### 20. `node.list`

Minimum response:

```json
{
  "ts": 0,
  "nodes": []
}
```

### 21. `device.pair.list`

Minimum response:

```json
{
  "pending": [],
  "paired": []
}
```

### 22. `sessions.list`

Minimum response:

```json
{
  "sessions": [],
  "defaults": {}
}
```

## Current Status

Stable enough:
- `agents.list`
- `agent.identity.get`
- `agents.teams.*`
- `agents.models.*`
- `agents.bind`
- `agents.unbind`
- `agents.migration.dryRun`
- `agents.files.*`
- `cron.status`
- `cron.list`
- `cron.runs`
- `sessions.usage`
- `usage.cost`
- `config.get`
- `config.schema`
- `system-presence`
- `last-heartbeat`
- `node.list`
- `device.pair.list`
- `sessions.list`

Still incomplete:
- `channels.status`

## Next Step

Phase 2 should focus only on `channels.status`, with this order:

1. return stable `channelMeta[]`
2. add real `channelAccounts{}`
3. add `channelDefaultAccountId{}`
4. finally add real `channels{}`

Do not change all four layers at once.
