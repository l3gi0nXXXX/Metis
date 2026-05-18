# Metis Channel Parity Contract

This document defines the current channel parity target for Metis relative
to the upstream gateway channel subsystem.

## Scope

The parity target covers:

- plugin registry and catalog
- configured binding registry
- account-level channel runtime manager
- gateway bootstrap and configured binding priming
- channel health policy, health monitor, and status patching
- channel gateway methods and MCP exposure
- bundled default channel breadth for common builtins
- focused regression coverage

It does not attempt to freeze exact internal implementation style. The target is
surface, runtime behavior, and policy parity.

## Catalog And Registry

Metis must provide channel and plugin catalog metadata equivalent to the
reference channel catalog layer.

Required fields:

- `id`
- `label`
- `detailLabel`
- `systemImage`
- `origin`
- `docsUrl`
- `order`
- `installed`
- `registered`
- `setupSupported`

Required surfaces:

- `discover.detail`
- `channels.status`
- `plugins.status`
- `channels.bindings`
- `plugins.bindings`

## Configured Bindings

Metis must maintain a configured binding registry independent from method
assembly code.

Required binding fields:

- `channelId`
- `pluginId`
- `accountId`
- `configuredBinding`
- `bindingState`
- `primed`
- `autoEnabled`
- `primedAtMs`

Configured bindings must be derived from user configuration and merged with
runtime accounts into a binding snapshot.

## Runtime Manager

Metis must provide an account-level runtime manager equivalent in intent to
the upstream `server-channels.ts`.

Required runtime fields:

- `running`
- `manualStop`
- `taskState`
- `taskGeneration`
- `abortState`
- `monitorState`
- `monitorEnabledAtMs`
- `lastMonitorAtMs`
- `restartBudget`
- `restartBudgetState`
- `lastEventAtMs`
- `lastError`
- `nextRestartAtMs`

Required manager surfaces:

- `channels.runtime`
- `plugins.runtime`
- `channels.manager`
- `plugins.manager`
- `channels.logout`

## Bootstrap And Priming

Gateway startup must prime configured channel bindings and expose bootstrap state.

Required bootstrap fields:

- `bootstrapped`
- `bootstrappedAtMs`
- `channelIds`
- `pluginIds`
- `configuredBindings`
- `primedBindings`
- `configuredBindingCount`
- `primedBindingCount`

Bootstrap state must be visible through runtime surfaces.

## Health Policy And Monitor

Channel health must be derived from explicit policy and monitor logic rather than
only raw runtime rows.

Required health fields:

- `policyState`
- `byHealthState`
- `healthyCount`
- `degradedCount`
- `actionsNeeded`
- `actions`
- per-item `monitor`

Required health surfaces:

- `channels.health`
- `plugins.health`
- `channels.health.actions`
- `plugins.health.actions`

## Method Semantics

The following method semantics must be present and stable:

- `channels.status`
  - supports `probe`
  - supports `timeoutMs`
  - returns `channelOrder`
  - returns `channelLabels`
  - returns `channelDetailLabels`
  - returns `channelSystemImages`
  - returns `channelMeta`
  - returns `channelAccounts`
  - returns `channelDefaultAccountId`
- `plugins.status`
  - supports `probe`
  - supports `timeoutMs`
  - returns `pluginOrder`
  - returns `pluginMeta`
  - returns plugin account snapshots
- `channels.bindings` and `plugins.bindings`
  - expose registry-backed binding snapshots
- `channels.policy` and `plugins.policy`
  - expose policy aggregates and remediation intent
- `plugins.approvals`
- `plugins.package_state`
- `plugins.setup`

## Default Channel Breadth

Bundled default channel coverage must include these common builtins:

- `feishu`
- `qq`
- `telegram`
- `slack`
- `discord`

These channels must appear in catalog-driven gateway discovery and status
surfaces when enabled or registered.

## MCP Contract

The MCP gateway surface must expose channel tools covering:

- `gateway.channels.bindings`
- `gateway.channels.policy`
- `gateway.channels.manager`
- `gateway.channels.health.actions`
- `gateway.plugins.bindings`
- `gateway.plugins.policy`
- `gateway.plugins.manager`
- `gateway.plugins.health.actions`
- `gateway.plugins.approvals`
- `gateway.plugins.package_state`
- `gateway.plugins.setup`

## Regression Contract

Channel parity must be covered by two levels of verification:

- `scripts/gateway-regression.sh`
- `scripts/channel-regression.sh`

The focused channel regression must validate:

- catalog metadata
- configured binding registry
- runtime manager snapshots
- every current `channels.*` surface
- every current `plugins.*` surface
- `probe` and `timeoutMs` semantics
- logout semantics
- health and health-actions surfaces
- approvals, package-state, and setup surfaces
- MCP tools list and MCP tool calls
- bundled builtin channels `telegram`, `slack`, and `discord`
- one reference-style fixture plugin path with host-backed setup/binding/runtime data
