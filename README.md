# Metis— High Performance & Personal  AI Assistant

![log](./docs/figures/metis.svg)



Metis is a high performance and personal AI assistant which is build with Cangjie program language. And this project is based on magic-cli and CangjeMagic.

It combines an interactive CLI, a unified Gateway-first runtime, channel adapters, skills, persistent sessions, and operational surfaces for running agents in real workflows instead of one-off chat demos. Supported channels include: Telegram, QQ, Feishu.

## Why Metis

Metis is designed around one practical idea: the same agent runtime should be able to serve local CLI conversations, managed sessions, gateway APIs, and IM channels without splitting product behavior across unrelated code paths.

That gives the project a few defining characteristics:

- Gateway-first runtime for default chat, automation, and channel delivery paths
- Cangjie-based agent implementation with Cangjie Magic integration
- Interactive CLI for development, debugging, and daily use
- Skills system built on `SKILL.md` packages with workspace and user-level discovery
- MCP integration for external tools and service extension
- Persistent conversations, transcript-backed sessions, and workspace memory
- Cron scheduling for recurring agent tasks
- Channel delivery for Feishu, QQ, Telegram, and plugin-driven IM integrations
- Control and observability surfaces for dashboard, HTTP, and runtime inspection

## High performance

Without undergoing any specialized performance optimization, Metis has achieved a more than 20-fold leap in startup and shutdown efficiency, thereby completely resolving the critical issue of slow startup times associated with OpenClaw.

Absent any specialized performance optimization, Metis has realized a qualitative leap in its startup and shutdown efficiency:

| Comparison Item               | openclaw Average Duration | Metis Average Duration | Magnification Factor |
| ----------------------------- | ------------------------- | ---------------------- | -------------------- |
| onboard（Cold Start）         | 2\.591s                   | 0\.122s                | 21\.2 times          |
| gateway restart（Cold Start） | 2\.366s                   | 0\.073s                | 32\.4 times          |
| gateway start（Cold Start）   | 2\.174s                   | 0\.074s                | 29\.4 times          |
| gateway stop（Cold Start）    | 1\.979s                   | 0\.073s                | 27\.1 times          |

The detailed data is presented below; notably, these figures were achieved without any performance optimizations whatsoever (perhaps because Metis's feature set is not yet fully comprehensive?).

| Num     | openclaw onboard | openclaw gateway restart | openclaw gateway start | openclaw gateway stop |
| ------- | ---------------: | -----------------------: | ---------------------: | --------------------: |
| 1       |           3.563s |                   1.989s |                 2.462s |                2.136s |
| 2       |           2.470s |                   2.044s |                 2.397s |                1.955s |
| 3       |           2.476s |                   2.555s |                 2.108s |                1.950s |
| 4       |           2.473s |                   2.381s |                 2.089s |                1.962s |
| 5       |           2.474s |                   2.391s |                 2.103s |                1.970s |
| 6       |           2.493s |                   2.491s |                 2.118s |                1.957s |
| 7       |           2.468s |                   2.421s |                 2.135s |                1.972s |
| 8       |           2.505s |                   2.545s |                 2.099s |                1.966s |
| 9       |           2.491s |                   2.432s |                 2.114s |                1.959s |
| 10      |           2.500s |                   2.413s |                 2.117s |                1.961s |
| average |           2.591s |                   2.366s |                 2.174s |                1.979s |

| Num     | Metis onboard | Metis gateway restart | Metis gateway run | Metis gateway stop |
| :------ | ------------: | --------------------: | ----------------: | -----------------: |
| 1       |        0.562s |                0.072s |            0.075s |             0.071s |
| 2       |        0.068s |                0.071s |            0.073s |             0.073s |
| 3       |        0.076s |                0.074s |            0.077s |             0.073s |
| 4       |        0.074s |                0.076s |            0.073s |             0.074s |
| 5       |        0.076s |                0.073s |            0.074s |             0.073s |
| 6       |        0.071s |                0.075s |            0.074s |             0.075s |
| 7       |        0.071s |                0.075s |            0.073s |             0.077s |
| 8       |        0.076s |                0.072s |            0.075s |             0.071s |
| 9       |        0.072s |                0.074s |            0.073s |             0.073s |
| 10      |        0.071s |                0.073s |            0.073s |             0.072s |
| average |        0.122s |                0.073s |            0.074s |             0.073s |

Test Environment:

* MacBook Air 2026 M5 (10-core CPU + 10-core GPU) | 16GB RAM + 256GB SSD
* macOS 26.4 (25E246)

## Quick Start

### Prerequisites

- Cangjie `1.0.0+`
- A working `MAGIC_PATH` that points to your Cangjie Magic installation: https://gitcode.com/Cangjie-TPC/CangjieMagic
- install openssl3 and config DYLD_LIBRARY_PATH in env
- Model provider credentials stored in `~/.metis/metis.json`

### 1. Configure env

```bash
export MAGIC_PATH="/path/to/CangjieMagic"
brew install openssl@3
export DYLD_LIBRARY_PATH="/opt/homebrew/opt/openssl@3/lib:$DYLD_LIBRARY_PATH"
```

### 2. Start the interactive CLI

```bash
cjpm run --name metis
cjpm run --skip-build --name metis --run-args "onboard"
cjpm run --skip-build --name metis --run-args "chat"
```

### 3. Start the Gateway runtime

```bash
cjpm run --skip-build --name metis --run-args "gateway run"
cjpm run --skip-build --name metis --run-args "gateway serve"
```

### 4. Others

```bash
cjpm run --skip-build --name metis --run-args "dashboard"
cjpm run --skip-build --name metis --run-args "gateway help"
```

## Common Workflows

### Interactive Work

Use the CLI when you want a local conversational interface with memory, commands, skills, and project instructions.

```bash
cjpm run --name metis
```

Inside the shell, common commands include:

- `/help`
- `/conversation list`
- `/conversation save <name>`
- `/conversation resume <name>`
- `/memory`
- `/skills list`
- `/mcp`
- `/cron`

### Gateway-Backed Agent Calls

Use the gateway runtime when you want a long-lived operational surface for CLI chat, APIs, managed sessions, channels, cron jobs, and delivery workflows.

```bash
metis gateway status
metis gateway health
metis gateway discover
```

### Skills

Skills are packaged as directories containing `SKILL.md` and can be discovered from bundled, user, and workspace locations.

Examples:

```text
/skills list
/skills info weather
/skills search weather
/weather Shanghai
```

### MCP

Metis can manage MCP servers and expose its unified runtime through an MCP bridge.

```bash
metis mcp list
metis mcp serve --url ws://127.0.0.1:18788/ws
```

### Sessions and Agents

Metis supports managed agent sessions, bindings, and operational inspection through the gateway path.

```bash
metis agents list
metis sessions list
metis subagents list
```

Background subagents can be started from CLI or IM sessions without blocking the current conversation:

```text
/subagents spawn explorer "analyze the gateway runtime and notify this session when done"
```

See `docs/user/subagents.md` for CLI, Telegram, natural-language, custom agent, policy, and control-ui usage.

### Control UI Slash Commands

The dashboard chat input supports the same slash menu shown by `/help` and `/commands`.
Local Control UI commands return readable chat summaries and do not print raw JSON by default.

Common Control UI commands:

```text
/help
/commands
/stop
/kill <id|all>
/steer [id] <message>
/redirect [id] <message>
```

`/stop` aborts only the current Control UI chat turn. `/kill` targets matching sub-agent sessions in the current Control UI session subtree. `/steer` soft-injects guidance into an active run without restarting it; use `/redirect` when the run should be aborted and restarted with a new message.

### Scheduled Jobs

Cron jobs let you run agent work on recurring schedules and optionally route successful results back into channels or session targets.

```bash
metis gateway cron list
metis gateway cron run <job-id>
```

## Configuration

Metis stores user-facing runtime configuration under `~/.metis/`.

Important files and directories:

- `~/.metis/metis.json` for model, provider, gateway, tool, and MCP configuration
- `~/.metis/skills/` for user-managed skills
- `~/.metis/agents/` for custom subagents
- `~/.metis/conversation-history/` for saved conversations
- project `AGENTS.md` for workspace-specific instructions

## Architecture at a Glance

The repository is organized around a few major surfaces:

- `src/app/` for CLI interaction and command handling
- `src/gateway/` for the unified runtime, channels, toolsets, transport, dashboard, and control UI
- `src/core/` for conversations, memory, policies, and shared runtime behavior
- `src/cron/` for recurring job scheduling and delivery
- `src/mcp/` for MCP bridge and server support
- `src/lsp/` for richer code-assistance infrastructure
- `docs/` for runtime, parity, control, skills, and integration documentation
- `skills/` for bundled skills
- `tools/` for channel plugin tooling and supporting integrations

## Channel and Plugin Story

Metis ships with built-in channel support and also supports plugin-style integrations for external IM systems. The gateway/plugin model is designed so channels can feed normalized inbound events into the runtime and reuse the same agent, session, and delivery infrastructure.

That makes Metis suitable for:

- terminal-first agent workflows
- workspace-aware coding assistants
- private personal assistants with persistent context
- channel-connected bots for teams or personal messaging
- scheduled and semi-autonomous agent tasks

## Documentation

Useful project documents:

- `README.md` for the current project intro and command overview
- `docs/user/runtime-execution-model.md` for how Gateway-first execution works
- `docs/user/telegram.md` for Telegram channel configuration, media usage, and troubleshooting
- `docs/user/subagents.md` for background subagent usage and control-ui operations
- `docs/user/skills-guide.md` for skills discovery, commands, and installation
- `docs/user/gateway-im-plugins.md` for IM plugin integration
- `docs/mcp.md` for MCP-related configuration

## Development Notes

Metis is a source-first Cangjie project. In practice, the most important setup steps are making `MAGIC_PATH` valid, configuring provider credentials in `~/.metis/metis.json`, and deciding whether you are operating in interactive CLI mode, explicit local mode, or Gateway service mode.

If you are evaluating the codebase, start with:

1. `cjpm.toml`
2. `src/program_runner.cj`
3. `src/app/`
4. `src/gateway/`
5. `docs/user/runtime-execution-model.md`

## Thanks

This is a personal project which is based on magic-cli and CangjieMagic. I found a lot of inspiration from the OpenClaw, Evolver,  hermes-agent project.

* https://gitcode.com/Cangjie-TPC/CangjieMagic
* https://gitcode.com/cangjie-sig/magic-cli
* https://github.com/openclaw/openclaw#
* https://github.com/nousresearch/hermes-agent
* https://github.com/EvoMap/evolver
