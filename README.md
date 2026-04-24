# Metis— High Performance & Personal  AI Assistant

![log](./docs/figures/metis.svg)



Metis is a Cangjie-native agent runtime for building a personal AI assistant that can work through the terminal, structured tools, MCP, scheduled jobs, workspace memory, and multi-channel gateways.

It combines an interactive CLI, a unified Gateway-first runtime, channel adapters, skills, persistent sessions, and operational surfaces for running agents in real workflows instead of one-off chat demos.

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

## Highlights

### Unified Runtime

Metis routes its default interactive and `agent --message` flows through the unified Gateway main runtime rather than treating the gateway as an optional sidecar. CLI, dashboard, control UI, and IM-facing entry points are converging on the same runtime profile and tool surface.

### Practical Tooling

The runtime includes real toolsets for filesystem access, shell execution, weather, planning, session transcripts, managed sessions, gateway operations, message delivery, memory access, and cron orchestration.

### Skills and Memory

Metis supports discoverable skills from bundled, user, and workspace directories. It also maintains durable memory and session transcripts, with local indexing and promotion flows for workspace knowledge.

### Channel and Gateway Operations

Metis is not limited to a terminal assistant. It can serve as a gateway-backed agent system that connects to built-in or plugin-based channels and exposes status, configuration, policy, session, and runtime controls.

## Feature Overview

### Core Agent Experience

- Interactive CLI chat
- Single-turn agent execution
- Explicit embedded local fallback mode
- Conversation save and resume flows
- Project-level instruction injection through `AGENTS.md`
- Custom prompt commands via `/cmd`
- Custom subagents via `AGENT.md`

### Runtime and Operations

- Unified Gateway runtime
- Gateway control and health surfaces
- Dashboard and control UI support
- Managed sessions and transcript inspection
- Runtime policy and authorization hooks
- Telemetry and OpenTelemetry-related modules

### Automation and Extension

- Cron-based recurring agent jobs
- MCP server management and MCP bridge support
- Skill discovery, inspection, installation, and execution
- Plugin-based channel and gateway integrations

### Channel Support

- Feishu
- QQ
- Telegram
- Plugin-backed IM channels such as DingTalk, Weixin, and generic webhook-style integrations

## Quick Start

### Prerequisites

- Cangjie `1.0.0+`
- A working `MAGIC_PATH` that points to your Cangjie Magic installation
- brew install openssl3 
- export DYLD_LIBRARY_PATH="/opt/homebrew/opt/openssl@3/lib:$DYLD_LIBRARY_PATH"
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
cjpm run --skip-build --name metis --run-args "serve"
```

### 4. Others

```bash
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
/weather Shanghai
/skills list
/skills info weather
/skills search weather
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
```

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

## Inspiration for This README Structure

This README intentionally follows a structure closer to project-facing agent repositories that lead with product positioning, fast onboarding, operational workflows, and system capabilities, while still reflecting Metis-specific behavior and commands.

Reference repositories consulted for structure and tone:

- OpenClaw: https://github.com/openclaw/openclaw
- Hermes Agent: https://github.com/NousResearch/hermes-agent
- Evolver: https://github.com/EvoMap/evolver
