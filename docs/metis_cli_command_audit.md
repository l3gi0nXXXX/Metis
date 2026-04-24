# CLI Audit: Metis vs Reference CLI

This document records the current CLI command audit for `metis`, with the upstream CLI used as the reference implementation.

The goal is to identify:

- commands that are already real and gateway-backed
- commands that are partial implementations
- commands that are preview/help shells only
- commands that are effectively fake and should not remain as first-class commands

## Reference Files

Reference command registration:

- upstream command registration sources

Metis command registration and local flows:

- `src/program/register_core_dispatch.cj`
- `src/program/register_gateway_dispatch.cj`
- `src/program/program_command_tree.cj`
- `src/program/cli_local_flows.cj`

## Classification Rules

Commands are classified using these labels:

- `real`
  The command is backed by real gateway/runtime behavior and is not just a local preview shell.
- `partial`
  The command has some real backend behavior, but does not yet match the reference CLI semantics or depth.
- `preview-shell`
  The command exists, but mainly returns local summary/preview JSON or recommended next steps.
- `help-only`
  The command is effectively a help surface with no real command implementation behind it.
- `custom-only`
  The command exists in Metis but does not have an obvious reference CLI counterpart.

## Root Command Audit

| Command | Reference Counterpart | Current Metis State | Classification | Evidence |
|---|---|---|---|---|
| `agent` | yes | real gateway-backed invoke path | `real` | `src/program/cli_local_flows.cj` |
| `agents` | yes | real gateway-backed management path | `real` | `src/program/cli_local_flows.cj`, `src/gateway/runtime/gateway_server_methods_agents.cj` |
| `status` | yes | gateway-backed status path | `real` | `src/program/register_gateway_dispatch.cj` |
| `health` | yes | gateway-backed health path | `real` | `src/program/register_gateway_dispatch.cj` |
| `doctor` | yes | gateway-backed remediation path | `real` | `src/program/register_gateway_dispatch.cj` |
| `dashboard` | yes | gateway-backed dashboard path | `real` | `src/program/register_gateway_dispatch.cj` |
| `gateway` | yes | gateway-backed runtime command surface | `real` | `src/program/register_gateway_dispatch.cj` |
| `channels` / `channel` | yes | gateway-backed channel path | `real` | `src/program/register_gateway_dispatch.cj` |
| `plugins` / `plugin` | yes | gateway-backed plugin path | `real` | `src/program/register_gateway_dispatch.cj` |
| `sessions` | yes | gateway-backed session path | `real` | `src/program/register_gateway_dispatch.cj` |
| `cron` | partial reference overlap | gateway-backed cron path | `real` | `src/program/register_gateway_dispatch.cj` |
| `config` | yes, but different surface | real local config edits plus local inspection | `partial` | `src/program/cli_local_flows.cj` |
| `models` | partial reference overlap | local config/runtime inspection, not full reference equivalent | `partial` | `src/program/cli_local_flows.cj` |
| `logs` | partial reference overlap | mostly local inventory/preview, not full log command set | `partial` | `src/program/cli_local_flows.cj` |
| `backup` | yes | preview/path/state only, no real create/verify | `preview-shell` | `src/program/cli_local_flows.cj`, compare upstream backup registration |
| `reset` | yes | preview/targets only, no real reset action | `preview-shell` | `src/program/cli_local_flows.cj`, compare upstream maintenance registration |
| `uninstall` | yes | preview/path/state only, no real uninstall action | `preview-shell` | `src/program/cli_local_flows.cj`, compare upstream maintenance registration |
| `message` | yes, but very different | payload preview/file inspection only, not real send/read/manage surface | `preview-shell` | `src/program/cli_local_flows.cj`, compare upstream message registration |
| `tasks` | yes, but very different | local workflow summary only | `preview-shell` | `src/program/cli_local_flows.cj`, compare upstream status/health/sessions registration |
| `docs` | no strong reference CLI equivalent | local docs URL/topic summary | `preview-shell` | `src/program/cli_local_flows.cj` |
| `system` | no strong reference CLI equivalent | local path/env/status summary | `preview-shell` | `src/program/cli_local_flows.cj` |
| `approvals` | partial overlap | local summary pointing users to gateway calls | `preview-shell` | `src/program/cli_local_flows.cj` |
| `sandbox` | partial overlap | static local policy summary, no real command action | `preview-shell` | `src/program/cli_local_flows.cj` |
| `node` | partial overlap | local summary pointing to gateway calls | `preview-shell` | `src/program/cli_local_flows.cj` |
| `nodes` | partial overlap | local summary pointing to gateway calls | `preview-shell` | `src/program/cli_local_flows.cj` |
| `devices` | partial overlap | local summary pointing to gateway calls | `preview-shell` | `src/program/cli_local_flows.cj` |
| `qa` | custom-only | local script catalog summary | `preview-shell` | `src/program/cli_local_flows.cj` |
| `hooks` | custom-only | local summary only | `preview-shell` | `src/program/cli_local_flows.cj` |
| `webhooks` | custom-only | local summary only | `preview-shell` | `src/program/cli_local_flows.cj` |
| `qr` | custom-only | local summary only | `preview-shell` | `src/program/cli_local_flows.cj` |
| `pairing` | custom-only | local summary only | `preview-shell` | `src/program/cli_local_flows.cj` |
| `daemon` | custom-only | local summary only | `preview-shell` | `src/program/cli_local_flows.cj` |
| `acp` | custom-only | local summary only | `preview-shell` | `src/program/cli_local_flows.cj` |
| `mcp` | yes, conceptually | prints help only | `help-only` | `src/program/register_core_dispatch.cj` |

## Commands Confirmed as Fake or Misleading

These commands should currently be treated as fake or misleading first-class CLI entries because they present themselves as commands but do not execute the kind of real behavior their names imply.

### `mcp`

`mcp` is the clearest help-only command.

In `src/program/register_core_dispatch.cj`:

- `if (command == "mcp") {`
- `printRegisteredRootCommandHelp(command)`
- `return Some(0)`

There is no real implementation behind it.

### `backup`

The reference CLI has:

- `backup create`
- `backup verify <archive>`

with real archive creation and verification in its backup registration flow.

Metis currently only supports:

- `backup state`
- `backup path`
- `backup preview`

and all of them only print local preview data.

### `reset`

The reference CLI has a real reset command with:

- `--scope`
- `--yes`
- `--non-interactive`
- `--dry-run`

Metis only exposes:

- `state`
- `preview`
- `targets`

which are inspection-only shells.

### `uninstall`

The reference CLI has a real uninstall command with:

- `--service`
- `--state`
- `--workspace`
- `--app`
- `--all`

Metis only exposes preview/path/state shells.

### `message`

The reference `message` surface is a large real command family:

- send
- read
- edit
- delete
- reactions
- pins
- poll
- thread
- permissions
- search
- emoji/sticker
- discord admin actions

Metis `message` currently only:

- previews inline text
- previews file payload
- suggests `agent --message`

So this is not a real equivalent command surface.

### `tasks`

The reference `tasks` surface is a real task management command family:

- list
- audit
- maintenance
- show
- notify
- cancel
- flow ...

Metis `tasks` currently only prints local workflow summaries such as:

- `agent --message`
- `message <text...>`
- `gateway cron list`

This is a preview shell, not real task management.

## Commands That Are Real but Still Divergent

These commands are not fake, but they still differ materially from the reference CLI and need continued convergence work.

### `config`

Current Metis `config` can:

- show config path
- show config file contents
- get/set some local model/provider/workspace fields

This is real local functionality, but it is not yet aligned with the broader reference config command structure.

### `models`

Current `models` is a real local inspection/config surface, but the reference CLI shape differs and the feature scope is not yet matched.

### `logs`

Current `logs` command is only partially real:

- real path reporting
- local preview of targets
- no deep log management parity

## Command Surface Mismatch vs Reference CLI

The reference CLI has several root command families that are implemented as real commands with concrete actions. Metis currently diverges in two ways:

1. It keeps many custom root commands that have only preview/help semantics.
2. It does not yet implement some reference command families to equivalent depth.

The biggest mismatch is not `agent` anymore. It is the large set of root commands that appear official in Metis but behave like preview shells.

## Stage 2 Plan: Remove or Demote Fake Commands

Recommended order:

1. `mcp`
2. `backup`
3. `reset`
4. `uninstall`
5. `message`
6. `tasks`

For each command, choose one of:

- implement to reference-equivalent real behavior
- demote to experimental/preview namespace
- remove from root command surface

Commands should not remain as first-class root commands if they only emit summary/help JSON.

## Stage 3 Plan: Converge the Remaining Real Surfaces

After fake commands are removed or made real, converge the remaining real commands:

- `config`
- `models`
- `logs`
- `status`
- `health`
- `sessions`
- `channels`
- `plugins`
- `cron`

## Stage 4 Plan: Command-Level Regression Matrix

For every surviving formal root command, add one regression row:

- command exists
- help text matches its real semantics
- reaches real backend or local side effect
- does not silently degrade to preview/help behavior

This should become the contract guardrail for CLI parity work.
