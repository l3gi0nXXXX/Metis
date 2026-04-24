#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { pathToFileURL } from "node:url";

function parseArgs(argv) {
  const out = { _: [] };
  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    if (!token.startsWith("--")) {
      out._.push(token);
      continue;
    }
    const key = token.slice(2);
    const next = argv[i + 1];
    if (next == null || next.startsWith("--")) {
      out[key] = "true";
      continue;
    }
    out[key] = next;
    i += 1;
  }
  return out;
}

function runtimeDir(pluginRoot) {
  const dir = path.join(pluginRoot, ".runtime");
  fs.mkdirSync(dir, { recursive: true });
  return dir;
}

function log(pluginRoot, text) {
  const file = path.join(runtimeDir(pluginRoot), "legacy-node-host.log");
  fs.appendFileSync(file, `[${Date.now()}] ${text}\n`, "utf8");
}

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, "utf8"));
}

function isObject(value) {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function resolvePackageJsonEntry(pluginRoot) {
  const pkgPath = path.join(pluginRoot, "package.json");
  if (!fs.existsSync(pkgPath)) {
    return "";
  }
  try {
    const pkg = readJson(pkgPath);
    const candidates = [
      pkg.metis?.channelPlugin,
      pkg.metis?.pluginEntry,
      pkg.module,
      pkg.main,
      typeof pkg.exports === "string" ? pkg.exports : "",
    ].filter((v) => typeof v === "string" && v.trim().length > 0);
    for (const candidate of candidates) {
      const resolved = path.isAbsolute(candidate) ? candidate : path.join(pluginRoot, candidate);
      if (fs.existsSync(resolved)) {
        return resolved;
      }
    }
  } catch {
    return "";
  }
  return "";
}

function resolvePluginEntry(pluginRoot, manifest) {
  const runtime = manifest.gatewayRuntime ?? {};
  const candidates = [
    runtime.pluginEntry,
    runtime.hostEntry,
    runtime.entry,
    runtime.script,
    "dist/gateway.js",
    "dist/index.js",
    "gateway.js",
    "index.js",
    resolvePackageJsonEntry(pluginRoot),
  ].filter((v) => typeof v === "string" && v.trim().length > 0);
  for (const candidate of candidates) {
    const resolved = path.isAbsolute(candidate) ? candidate : path.join(pluginRoot, candidate);
    if (fs.existsSync(resolved)) {
      return resolved;
    }
  }
  return "";
}

async function loadPluginModule(pluginEntry) {
  return import(pathToFileURL(pluginEntry).href);
}

function resolvePluginExport(mod) {
  const candidates = [mod.default, mod.plugin, mod.channelPlugin, mod.legacyPlugin, mod.metisPlugin];
  for (const candidate of candidates) {
    if (isObject(candidate)) {
      return candidate;
    }
  }
  return null;
}

function resolveHook(mod, plugin, op) {
  const topLevel = mod?.[op];
  if (typeof topLevel === "function") {
    return topLevel;
  }
  if (typeof plugin?.host?.[op] === "function") {
    return plugin.host[op];
  }
  if (op === "start" && typeof plugin?.gateway?.startAccount === "function") {
    return (ctx) => plugin.gateway.startAccount(ctx);
  }
  if (op === "stop" && typeof plugin?.gateway?.stopAccount === "function") {
    return (ctx) => plugin.gateway.stopAccount(ctx);
  }
  if (op === "send") {
    if (typeof plugin?.host?.send === "function") {
      return (ctx) => plugin.host.send(ctx);
    }
    if (typeof plugin?.outbound?.sendText === "function") {
      return (ctx) =>
        plugin.outbound.sendText({
          cfg: ctx.cfg,
          to: ctx.peerId,
          text: ctx.text,
          replyToId: ctx.replyTo || null,
          accountId: ctx.accountId,
        });
    }
  }
  if (op === "pull" && typeof plugin?.host?.pull === "function") {
    return (ctx) => plugin.host.pull(ctx);
  }
  return null;
}

function buildHostContext({
  manifest,
  pluginRoot,
  pluginId,
  channelId,
  configJson,
  manifestPath,
  peerId,
  text,
  replyTo,
  accountId,
  target,
  action,
  payloadJson,
  groupId,
}) {
  let cfg = {};
  try {
    cfg = configJson ? JSON.parse(configJson) : {};
  } catch {
    cfg = {};
  }
  return {
    manifest,
    manifestPath,
    pluginRoot,
    pluginId,
    channelId,
    accountId: accountId || "default",
    cfg,
    configJson,
    peerId,
    text,
    replyTo,
    target,
    action,
    groupId,
    payload: (() => {
      try {
        return payloadJson ? JSON.parse(payloadJson) : {};
      } catch {
        return {};
      }
    })(),
    runtime: {
      compatibilityMode: "legacy-node-plugin",
      hostRoot: pluginRoot,
    },
    log: {
      info: (msg) => log(pluginRoot, `info ${String(msg)}`),
      warn: (msg) => log(pluginRoot, `warn ${String(msg)}`),
      error: (msg) => log(pluginRoot, `error ${String(msg)}`),
    },
  };
}

function normalizePullItems(value) {
  if (!Array.isArray(value)) {
    return [];
  }
  return value.filter((item) => isObject(item));
}

function normalizeSendResult(value) {
  if (value == null) {
    return { ok: true };
  }
  if (typeof value === "boolean") {
    return { ok: value };
  }
  if (isObject(value)) {
    return value;
  }
  return { ok: true };
}

function resolveAccountIds(plugin, cfg) {
  try {
    if (typeof plugin?.config?.listAccountIds === "function") {
      const value = plugin.config.listAccountIds(cfg);
      if (Array.isArray(value) && value.length > 0) {
        return value.filter((entry) => typeof entry === "string" && entry.trim().length > 0);
      }
    }
  } catch {
    return ["default"];
  }
  return ["default"];
}

function resolveDefaultAccountId(plugin, cfg, accountIds) {
  try {
    if (typeof plugin?.config?.defaultAccountId === "function") {
      const value = plugin.config.defaultAccountId(cfg);
      if (typeof value === "string" && value.trim()) {
        return value.trim();
      }
    }
  } catch {
    return accountIds[0] ?? "default";
  }
  return accountIds[0] ?? "default";
}

function resolveAccount(plugin, cfg, accountId) {
  try {
    if (typeof plugin?.config?.resolveAccount === "function") {
      return plugin.config.resolveAccount(cfg, accountId);
    }
  } catch {
    return {};
  }
  return {};
}

async function resolveConfigured(plugin, cfg, account) {
  try {
    if (typeof plugin?.config?.isConfigured === "function") {
      return Boolean(await plugin.config.isConfigured(account, cfg));
    }
  } catch {
    return false;
  }
  return true;
}

function pluginSupports(plugin) {
  return {
    listAccountIds: typeof plugin?.config?.listAccountIds === "function",
    resolveAccount: typeof plugin?.config?.resolveAccount === "function",
    isConfigured: typeof plugin?.config?.isConfigured === "function",
    probeAccount: typeof plugin?.status?.probeAccount === "function",
    auditAccount: typeof plugin?.status?.auditAccount === "function",
    logoutAccount: typeof plugin?.gateway?.logoutAccount === "function",
    startAccount: typeof plugin?.gateway?.startAccount === "function",
    stopAccount: typeof plugin?.gateway?.stopAccount === "function",
    sendText: typeof plugin?.outbound?.sendText === "function",
    sendMedia: typeof plugin?.outbound?.sendMedia === "function",
    sendPoll: typeof plugin?.outbound?.sendPoll === "function",
    setup: isObject(plugin?.setup),
    setupApplyAccountConfig: typeof plugin?.setup?.applyAccountConfig === "function",
    setupValidateInput: typeof plugin?.setup?.validateInput === "function",
    setupResolveAccountId: typeof plugin?.setup?.resolveAccountId === "function",
    messageActions:
      typeof plugin?.actions?.discover === "function" ||
      typeof plugin?.messageActions?.discover === "function",
    dispatchAction:
      typeof plugin?.actions?.dispatch === "function" ||
      typeof plugin?.messageActions?.dispatch === "function",
    statusIssues:
      typeof plugin?.status?.issues === "function" ||
      typeof plugin?.status?.listIssues === "function" ||
      typeof plugin?.status?.getIssues === "function",
    directoryLive:
      typeof plugin?.directory?.listPeersLive === "function" ||
      typeof plugin?.directory?.listGroupsLive === "function" ||
      typeof plugin?.directory?.listGroupMembers === "function",
  };
}

async function resolveStatusIssues(plugin, ctx, account, probe, audit) {
  if (typeof plugin?.status?.issues === "function") {
    return await plugin.status.issues({
      account,
      cfg: ctx.cfg,
      timeoutMs: 10_000,
      probe,
      audit,
    });
  }
  if (typeof plugin?.status?.listIssues === "function") {
    return await plugin.status.listIssues({
      account,
      cfg: ctx.cfg,
      probe,
      audit,
    });
  }
  if (typeof plugin?.status?.getIssues === "function") {
    return await plugin.status.getIssues({
      account,
      cfg: ctx.cfg,
      probe,
      audit,
    });
  }
  return [];
}

async function resolveMessageActions(plugin, ctx, accountId) {
  if (typeof plugin?.actions?.discover === "function") {
    return await plugin.actions.discover({
      cfg: ctx.cfg,
      accountId,
      runtime: ctx.runtime,
    });
  }
  if (typeof plugin?.messageActions?.discover === "function") {
    return await plugin.messageActions.discover({
      cfg: ctx.cfg,
      accountId,
      runtime: ctx.runtime,
    });
  }
  return [];
}

async function dispatchMessageAction(plugin, ctx, accountId, action, payload) {
  if (typeof plugin?.actions?.dispatch === "function") {
    return await plugin.actions.dispatch({
      cfg: ctx.cfg,
      accountId,
      action,
      payload,
      runtime: ctx.runtime,
    });
  }
  if (typeof plugin?.messageActions?.dispatch === "function") {
    return await plugin.messageActions.dispatch({
      cfg: ctx.cfg,
      accountId,
      action,
      payload,
      runtime: ctx.runtime,
    });
  }
  return null;
}

async function resolveDirectorySnapshot(plugin, ctx, accountId, groupId) {
  const peers =
    typeof plugin?.directory?.listPeersLive === "function"
      ? await plugin.directory.listPeersLive({ cfg: ctx.cfg, accountId, runtime: ctx.runtime })
      : [];
  const groups =
    typeof plugin?.directory?.listGroupsLive === "function"
      ? await plugin.directory.listGroupsLive({ cfg: ctx.cfg, accountId, runtime: ctx.runtime })
      : [];
  const members =
    groupId && typeof plugin?.directory?.listGroupMembers === "function"
      ? await plugin.directory.listGroupMembers({ cfg: ctx.cfg, accountId, groupId, runtime: ctx.runtime })
      : [];
  return {
    peers: Array.isArray(peers) ? peers : [],
    groups: Array.isArray(groups) ? groups : [],
    members: Array.isArray(members) ? members : [],
  };
}

function resolveChannelIds(manifest, plugin) {
  const fromManifest = Array.isArray(manifest?.channelIds)
    ? manifest.channelIds
    : Array.isArray(manifest?.channels)
      ? manifest.channels
      : [];
  if (fromManifest.length > 0) {
    return fromManifest.filter((entry) => typeof entry === "string" && entry.trim().length > 0);
  }
  const fromMeta = Array.isArray(plugin?.meta?.channelIds)
    ? plugin.meta.channelIds
    : Array.isArray(plugin?.meta?.channels)
      ? plugin.meta.channels
      : [];
  return fromMeta.filter((entry) => typeof entry === "string" && entry.trim().length > 0);
}

async function loadPluginRuntime(params) {
  const manifest = readJson(params.manifestPath);
  const pluginEntry = resolvePluginEntry(params.pluginRoot, manifest);
  const packageJsonPath = path.join(params.pluginRoot, "package.json");
  const runtime = {
    manifest,
    manifestPath: params.manifestPath,
    pluginRoot: params.pluginRoot,
    pluginId: params.pluginId,
    channelId: params.channelId,
    packageJsonPath,
    packageJsonFound: fs.existsSync(packageJsonPath),
    pluginEntry,
    loaded: false,
    mod: null,
    plugin: null,
    ctx: null,
  };
  if (!pluginEntry) {
    return runtime;
  }
  const mod = await loadPluginModule(pluginEntry);
  const plugin = resolvePluginExport(mod);
  runtime.loaded = Boolean(plugin || mod);
  runtime.mod = mod;
  runtime.plugin = plugin;
  runtime.ctx = buildHostContext({
    manifest,
    pluginRoot: params.pluginRoot,
    pluginId: params.pluginId,
    channelId: params.channelId,
    configJson: params.configJson,
    manifestPath: params.manifestPath,
    peerId: params.peerId,
    text: params.text,
    replyTo: params.replyTo,
    accountId: params.accountId,
    target: params.target,
    action: params.action,
    payloadJson: params.payloadJson,
    groupId: params.groupId,
  });
  return runtime;
}

async function buildPluginInspect(params) {
  const runtime = await loadPluginRuntime(params);
  const out = {
    pluginId: params.pluginId,
    channelId: params.channelId,
    compatibilityMode: "legacy-node-plugin",
    manifestFound: true,
    packageJsonFound: runtime.packageJsonFound,
    pluginEntry: runtime.pluginEntry,
    loaded: runtime.loaded,
  };
  if (!runtime.plugin || !runtime.ctx) {
    return out;
  }
  const accountIds = resolveAccountIds(runtime.plugin, runtime.ctx.cfg);
  const defaultAccountId = resolveDefaultAccountId(runtime.plugin, runtime.ctx.cfg, accountIds);
  const account = resolveAccount(runtime.plugin, runtime.ctx.cfg, defaultAccountId);
  const configured = await resolveConfigured(runtime.plugin, runtime.ctx.cfg, account);
  const supports = pluginSupports(runtime.plugin);
  const setup = await buildSetupState(params);
  const packageState = await buildPackageState(params);
  const bindings = await buildBindingsState(params);
  const status = await buildStatusState(params);
  const actions = await buildActionsState(params);
  return {
    ...out,
    channelIds: resolveChannelIds(runtime.manifest, runtime.plugin),
    accountIds,
    defaultAccountId,
    configured,
    supports,
    setupRegistry: {
      supported: Boolean(supports.setup),
      validateInput: Boolean(supports.setupValidateInput),
      applyAccountConfig: Boolean(supports.setupApplyAccountConfig),
      resolveAccountId: Boolean(supports.setupResolveAccountId),
      state: setup.state ?? "unknown",
    },
    runtimeForwarders: {
      gatewayStart: Boolean(supports.startAccount),
      gatewayStop: Boolean(supports.stopAccount),
      gatewayLogout: Boolean(supports.logoutAccount),
      outboundText: Boolean(supports.sendText),
      outboundMedia: Boolean(supports.sendMedia),
      outboundPoll: Boolean(supports.sendPoll),
      directoryLive: Boolean(supports.directoryLive),
      messageActions: Boolean(supports.messageActions),
      dispatchAction: Boolean(supports.dispatchAction),
    },
    packageState,
    bindings,
    status,
    actions,
    meta: isObject(runtime.plugin.meta) ? runtime.plugin.meta : {},
  };
}

async function buildAccountsState(params) {
  const runtime = await loadPluginRuntime(params);
  if (!runtime.plugin || !runtime.ctx) {
    return {
      pluginId: params.pluginId,
      channelId: params.channelId,
      defaultAccountId: "default",
      configured: false,
      accountIds: [],
      accounts: [],
    };
  }
  const channelIds = resolveChannelIds(runtime.manifest, runtime.plugin);
  const accountIds = resolveAccountIds(runtime.plugin, runtime.ctx.cfg);
  const defaultAccountId = resolveDefaultAccountId(runtime.plugin, runtime.ctx.cfg, accountIds);
  const accounts = [];
  for (const accountId of accountIds) {
    const account = resolveAccount(runtime.plugin, runtime.ctx.cfg, accountId);
    const configured = await resolveConfigured(runtime.plugin, runtime.ctx.cfg, account);
    accounts.push({
      accountId,
      configured,
      defaultAccount: accountId === defaultAccountId,
      account: isObject(account) ? account : {},
      channelIds,
    });
  }
  return {
    pluginId: params.pluginId,
    channelId: params.channelId,
    channelIds,
    defaultAccountId,
    configured: accounts.some((entry) => entry.configured),
    accountIds,
    accounts,
  };
}

async function buildBindingsState(params) {
  const runtime = await loadPluginRuntime(params);
  if (!runtime.plugin || !runtime.ctx) {
    return {
      pluginId: params.pluginId,
      channelId: params.channelId,
      configured: false,
      configuredBinding: false,
      defaultAccountId: `${params.pluginId}:default`,
      accountIds: [],
      accounts: [],
      activeChannelIds: [params.channelId],
      supports: {},
      bindingState: "plugin-unavailable",
    };
  }
  const channelIds = resolveChannelIds(runtime.manifest, runtime.plugin);
  const accountIds = resolveAccountIds(runtime.plugin, runtime.ctx.cfg);
  const defaultAccountId = resolveDefaultAccountId(runtime.plugin, runtime.ctx.cfg, accountIds);
  const account = resolveAccount(runtime.plugin, runtime.ctx.cfg, defaultAccountId);
  const configured = await resolveConfigured(runtime.plugin, runtime.ctx.cfg, account);
  const supports = pluginSupports(runtime.plugin);
  const accounts = [];
  for (const accountId of accountIds) {
    const accountRow = resolveAccount(runtime.plugin, runtime.ctx.cfg, accountId);
    const accountConfigured = await resolveConfigured(runtime.plugin, runtime.ctx.cfg, accountRow);
    accounts.push({
      accountId,
      configured: accountConfigured,
      defaultAccount: accountId === defaultAccountId,
      account: isObject(accountRow) ? accountRow : {},
      channelIds: channelIds.length > 0 ? channelIds : [params.channelId],
    });
  }
  return {
    pluginId: params.pluginId,
    channelId: params.channelId,
    configured,
    configuredBinding: configured,
    defaultAccountId,
    accountIds,
    accounts,
    activeChannelIds: channelIds.length > 0 ? channelIds : [params.channelId],
    supports,
    bindingState: configured ? "configured" : "pending-config",
  };
}

async function buildConfiguredBindingsState(params) {
  const runtime = await loadPluginRuntime(params);
  if (!runtime.plugin || !runtime.ctx) {
    return {
      pluginId: params.pluginId,
      channelId: params.channelId,
      configured: false,
      defaultAccountId: `${params.pluginId}:default`,
      accountIds: [],
      activeChannelIds: [params.channelId],
      rows: [],
      state: "plugin-unavailable",
    };
  }
  const applied = await buildApplySetupState(params);
  const activeChannelIds = resolveChannelIds(runtime.manifest, runtime.plugin);
  const effectiveChannelIds = activeChannelIds.length > 0 ? activeChannelIds : [params.channelId];
  const effectiveAccountIds =
    Array.isArray(applied.accountIds) && applied.accountIds.length > 0
      ? applied.accountIds
      : [applied.defaultAccountId || `${params.pluginId}:default`];
  const defaultAccountId = applied.defaultAccountId || effectiveAccountIds[0] || `${params.pluginId}:default`;
  const rows = [];
  for (const channelId of effectiveChannelIds) {
    for (const accountId of effectiveAccountIds) {
      rows.push({
        channelId,
        pluginId: params.pluginId,
        accountId,
        defaultAccountId,
        enabled: true,
        configured: Boolean(applied.applied),
        autoEnabled: true,
        origin: "registered",
        bindingKind: "configured",
      });
    }
  }
  return {
    pluginId: params.pluginId,
    channelId: params.channelId,
    configured: Boolean(applied.applied),
    defaultAccountId,
    accountIds: effectiveAccountIds,
    activeChannelIds: effectiveChannelIds,
    rows,
    state: applied.state || "configured",
    setupSupported: Boolean(applied.setupSupported),
    supports: applied.supports ?? {},
  };
}

async function buildConfiguredBindingsSummaryState(params) {
  const manifest = readJson(params.manifestPath);
  const cfg = parseConfigObject(params.configJson);
  const configured = Object.keys(cfg).length > 0;
  const activeChannelIds = resolveChannelIds(manifest, null);
  const effectiveChannelIds = activeChannelIds.length > 0 ? activeChannelIds : [params.channelId];
  const declaredAccountIds =
    Array.isArray(cfg.accountIds) && cfg.accountIds.length > 0
      ? cfg.accountIds.filter((entry) => typeof entry === "string" && entry.trim().length > 0)
      : [];
  const defaultAccountId =
    typeof cfg.defaultAccountId === "string" && cfg.defaultAccountId.trim().length > 0
      ? cfg.defaultAccountId.trim()
      : `${params.pluginId}:default`;
  const effectiveAccountIds = declaredAccountIds.length > 0 ? declaredAccountIds : [defaultAccountId];
  return {
    pluginId: params.pluginId,
    channelId: params.channelId,
    configured,
    configuredBinding: configured,
    defaultAccountId,
    accountIds: effectiveAccountIds,
    activeChannelIds: effectiveChannelIds,
    rowCount: effectiveChannelIds.length * effectiveAccountIds.length,
    state: configured ? "configured" : "needs-config",
    setupSupported: false,
    supports: {},
  };
}

async function buildPackageState(params) {
  const runtime = await loadPluginRuntime(params);
  const supports = runtime.plugin ? pluginSupports(runtime.plugin) : {};
  return {
    pluginId: params.pluginId,
    packageProbe: runtime.loaded ? "ready" : runtime.pluginEntry ? "entry-unloadable" : "missing-entry",
    probeState: runtime.loaded ? "ready" : runtime.pluginEntry ? "entry-unloadable" : "missing-entry",
    packageJsonFound: runtime.packageJsonFound,
    pluginEntry: runtime.pluginEntry ?? "",
    loaded: Boolean(runtime.loaded),
    runtimeKind: "legacy-node-plugin",
    compatibilityMode: "legacy-node-plugin",
    runtimeForwarders: {
      gatewayStart: Boolean(supports.startAccount),
      gatewayStop: Boolean(supports.stopAccount),
      gatewayLogout: Boolean(supports.logoutAccount),
      outboundText: Boolean(supports.sendText),
      outboundMedia: Boolean(supports.sendMedia),
      outboundPoll: Boolean(supports.sendPoll),
      directoryLive: Boolean(supports.directoryLive),
      messageActions: Boolean(supports.messageActions),
      dispatchAction: Boolean(supports.dispatchAction),
    },
    setupRegistry: {
      supported: Boolean(supports.setup),
      validateInput: Boolean(supports.setupValidateInput),
      applyAccountConfig: Boolean(supports.setupApplyAccountConfig),
      resolveAccountId: Boolean(supports.setupResolveAccountId),
    },
  };
}

async function buildSetupState(params) {
  const runtime = await loadPluginRuntime(params);
  const supports = runtime.plugin ? pluginSupports(runtime.plugin) : {};
  let configured = false;
  if (runtime.plugin && runtime.ctx) {
    const accountIds = resolveAccountIds(runtime.plugin, runtime.ctx.cfg);
    const defaultAccountId = resolveDefaultAccountId(runtime.plugin, runtime.ctx.cfg, accountIds);
    const account = resolveAccount(runtime.plugin, runtime.ctx.cfg, defaultAccountId);
    configured = await resolveConfigured(runtime.plugin, runtime.ctx.cfg, account);
  }
  return {
    pluginId: params.pluginId,
    setupSupported: Boolean(supports.setup),
    configured,
    state: configured ? "configured" : supports.setup ? "needs-setup" : "manual-config",
    actionsNeeded: !configured,
    supports,
    setupRegistry: {
      supported: Boolean(supports.setup),
      validateInput: Boolean(supports.setupValidateInput),
      applyAccountConfig: Boolean(supports.setupApplyAccountConfig),
      resolveAccountId: Boolean(supports.setupResolveAccountId),
    },
  };
}

async function buildApplySetupState(params) {
  const runtime = await loadPluginRuntime(params);
  if (!runtime.plugin || !runtime.ctx) {
    return {
      pluginId: params.pluginId,
      applied: false,
      setupSupported: false,
      state: "plugin-unavailable",
    };
  }
  const supports = pluginSupports(runtime.plugin);
  if (!supports.setup) {
    return {
      pluginId: params.pluginId,
      applied: false,
      setupSupported: false,
      state: "setup-unsupported",
      supports,
    };
  }
  const input = isObject(runtime.ctx.cfg) ? runtime.ctx.cfg : {};
  let validation = {};
  if (typeof runtime.plugin?.setup?.validateInput === "function") {
    validation = await runtime.plugin.setup.validateInput(input);
    if (validation?.ok === false) {
      return {
        pluginId: params.pluginId,
        applied: false,
        setupSupported: true,
        state: "invalid-input",
        validation,
        supports,
      };
    }
  }
  let appliedConfig = input;
  if (typeof runtime.plugin?.setup?.applyAccountConfig === "function") {
    const value = await runtime.plugin.setup.applyAccountConfig({
      input,
      cfg: runtime.ctx.cfg,
      runtime: runtime.ctx.runtime,
    });
    if (isObject(value)) {
      appliedConfig = value;
    }
  }
  const accountIds = resolveAccountIds(runtime.plugin, appliedConfig);
  const defaultAccountId =
    typeof runtime.plugin?.setup?.resolveAccountId === "function"
      ? runtime.plugin.setup.resolveAccountId(appliedConfig) || resolveDefaultAccountId(runtime.plugin, appliedConfig, accountIds)
      : resolveDefaultAccountId(runtime.plugin, appliedConfig, accountIds);
  return {
    pluginId: params.pluginId,
    applied: true,
    setupSupported: true,
    state: "applied",
    config: appliedConfig,
    accountIds,
    defaultAccountId,
    validation,
    supports,
  };
}

async function buildSetupRegistryState(params) {
  const setup = await buildSetupState(params);
  return {
    pluginId: params.pluginId,
    setupRegistry: setup.setupRegistry ?? {
      supported: false,
      validateInput: false,
      applyAccountConfig: false,
      resolveAccountId: false,
    },
    supports: setup.supports ?? {},
    state: setup.state ?? "unknown",
    configured: Boolean(setup.configured),
    actionsNeeded: Boolean(setup.actionsNeeded),
  };
}

async function buildRuntimeForwardersState(params) {
  const packageState = await buildPackageState(params);
  return {
    pluginId: params.pluginId,
    runtimeKind: packageState.runtimeKind ?? "legacy-node-plugin",
    compatibilityMode: packageState.compatibilityMode ?? "legacy-node-plugin",
    runtimeForwarders: packageState.runtimeForwarders ?? {},
    setupRegistry: packageState.setupRegistry ?? {},
  };
}

async function buildResolveAccountState(params) {
  const runtime = await loadPluginRuntime(params);
  if (!runtime.plugin || !runtime.ctx) {
    return {
      pluginId: params.pluginId,
      accountId: params.accountId || "default",
      configured: false,
      supported: false,
      account: {},
    };
  }
  const accountIds = resolveAccountIds(runtime.plugin, runtime.ctx.cfg);
  const accountId =
    (params.accountId && params.accountId.trim()) ||
    resolveDefaultAccountId(runtime.plugin, runtime.ctx.cfg, accountIds);
  const account = resolveAccount(runtime.plugin, runtime.ctx.cfg, accountId);
  const configured = await resolveConfigured(runtime.plugin, runtime.ctx.cfg, account);
  return {
    pluginId: params.pluginId,
    accountId,
    configured,
    supported: typeof runtime.plugin?.config?.resolveAccount === "function",
    account: isObject(account) ? account : {},
  };
}

async function buildDirectoryState(params) {
  const runtime = await loadPluginRuntime(params);
  if (!runtime.plugin || !runtime.ctx) {
    return {
      pluginId: params.pluginId,
      accountId: params.accountId || "default",
      supported: false,
      peers: [],
      groups: [],
      members: [],
    };
  }
  const accountIds = resolveAccountIds(runtime.plugin, runtime.ctx.cfg);
  const accountId =
    (params.accountId && params.accountId.trim()) ||
    resolveDefaultAccountId(runtime.plugin, runtime.ctx.cfg, accountIds);
  const snapshot = await resolveDirectorySnapshot(runtime.plugin, runtime.ctx, accountId, params.groupId);
  return {
    pluginId: params.pluginId,
    accountId,
    supported: pluginSupports(runtime.plugin).directoryLive,
    ...snapshot,
  };
}

async function buildTargetsState(params) {
  const runtime = await loadPluginRuntime(params);
  if (!runtime.plugin || !runtime.ctx) {
    return {
      pluginId: params.pluginId,
      accountId: params.accountId || "default",
      target: params.target || "",
      resolved: false,
      candidates: [],
    };
  }
  const accountIds = resolveAccountIds(runtime.plugin, runtime.ctx.cfg);
  const accountId =
    (params.accountId && params.accountId.trim()) ||
    resolveDefaultAccountId(runtime.plugin, runtime.ctx.cfg, accountIds);
  const target = typeof params.target === "string" ? params.target.trim() : "";
  const snapshot = await resolveDirectorySnapshot(runtime.plugin, runtime.ctx, accountId, "");
  const peerMatches = snapshot.peers.filter((entry) => isObject(entry) && (entry.id === target || entry.name === target));
  const groupMatches = snapshot.groups.filter((entry) => isObject(entry) && (entry.id === target || entry.name === target));
  const candidates = [...peerMatches, ...groupMatches];
  return {
    pluginId: params.pluginId,
    accountId,
    target,
    resolved: candidates.length > 0,
    targetKind: peerMatches.length > 0 ? "peer" : groupMatches.length > 0 ? "group" : "unknown",
    candidates,
  };
}

async function buildDispatchActionState(params) {
  const runtime = await loadPluginRuntime(params);
  if (!runtime.plugin || !runtime.ctx) {
    return {
      pluginId: params.pluginId,
      accountId: params.accountId || "default",
      action: params.action || "",
      supported: false,
      dispatched: false,
      reason: "plugin-unavailable",
    };
  }
  const accountIds = resolveAccountIds(runtime.plugin, runtime.ctx.cfg);
  const accountId =
    (params.accountId && params.accountId.trim()) ||
    resolveDefaultAccountId(runtime.plugin, runtime.ctx.cfg, accountIds);
  const action = typeof params.action === "string" ? params.action.trim() : "";
  let payload = isObject(runtime.ctx.payload) ? runtime.ctx.payload : {};
  if (isObject(payload.payload)) {
    payload = payload.payload;
  }
  if (!isObject(payload)) {
    payload = {};
  }
  if (typeof payload.text !== "string" && typeof runtime.ctx.text === "string" && runtime.ctx.text.trim()) {
    payload = { ...payload, text: runtime.ctx.text };
  }
  if (typeof payload.peerId !== "string" && typeof runtime.ctx.peerId === "string" && runtime.ctx.peerId.trim()) {
    payload = { ...payload, peerId: runtime.ctx.peerId };
  }
  if (typeof payload.replyTo !== "string" && typeof runtime.ctx.replyTo === "string" && runtime.ctx.replyTo.trim()) {
    payload = { ...payload, replyTo: runtime.ctx.replyTo };
  }
  const dispatched = await dispatchMessageAction(runtime.plugin, runtime.ctx, accountId, action, payload);
  if (dispatched == null) {
    return {
      pluginId: params.pluginId,
      accountId,
      action,
      supported: false,
      dispatched: false,
      reason: "dispatch-unsupported",
    };
  }
  return {
    pluginId: params.pluginId,
    accountId,
    action,
    supported: true,
    dispatched: true,
    result: isObject(dispatched) ? dispatched : { value: dispatched },
  };
}

async function buildProbeState(params) {
  const runtime = await loadPluginRuntime(params);
  if (!runtime.plugin || !runtime.ctx) {
    return {
      pluginId: params.pluginId,
      accountId: "default",
      configured: false,
      supported: false,
      ok: false,
      status: "plugin-unavailable",
    };
  }
  const accountIds = resolveAccountIds(runtime.plugin, runtime.ctx.cfg);
  const accountId =
    (params.accountId && params.accountId.trim()) ||
    resolveDefaultAccountId(runtime.plugin, runtime.ctx.cfg, accountIds);
  const account = resolveAccount(runtime.plugin, runtime.ctx.cfg, accountId);
  const configured = await resolveConfigured(runtime.plugin, runtime.ctx.cfg, account);
  if (!configured) {
    return {
      pluginId: params.pluginId,
      accountId,
      configured,
      supported: typeof runtime.plugin?.status?.probeAccount === "function",
      ok: false,
      status: "pending-config",
    };
  }
  if (typeof runtime.plugin?.status?.probeAccount !== "function") {
    return {
      pluginId: params.pluginId,
      accountId,
      configured,
      supported: false,
      ok: true,
      status: "ready",
    };
  }
  const probe = await runtime.plugin.status.probeAccount({
    account,
    timeoutMs: params.timeoutMs,
    cfg: runtime.ctx.cfg,
  });
  return {
    pluginId: params.pluginId,
    accountId,
    configured,
    supported: true,
    probe,
  };
}

async function buildAuditState(params) {
  const runtime = await loadPluginRuntime(params);
  if (!runtime.plugin || !runtime.ctx) {
    return {
      pluginId: params.pluginId,
      accountId: "default",
      configured: false,
      supported: false,
      remediationState: "plugin-unavailable",
    };
  }
  const accountIds = resolveAccountIds(runtime.plugin, runtime.ctx.cfg);
  const accountId =
    (params.accountId && params.accountId.trim()) ||
    resolveDefaultAccountId(runtime.plugin, runtime.ctx.cfg, accountIds);
  const account = resolveAccount(runtime.plugin, runtime.ctx.cfg, accountId);
  const configured = await resolveConfigured(runtime.plugin, runtime.ctx.cfg, account);
  if (!configured) {
    return {
      pluginId: params.pluginId,
      accountId,
      configured,
      supported: typeof runtime.plugin?.status?.auditAccount === "function",
      remediationState: "binding-review",
    };
  }
  if (typeof runtime.plugin?.status?.auditAccount !== "function") {
    return {
      pluginId: params.pluginId,
      accountId,
      configured,
      supported: false,
      remediationState: "ready",
    };
  }
  const probe =
    typeof runtime.plugin?.status?.probeAccount === "function"
      ? await runtime.plugin.status.probeAccount({
          account,
          timeoutMs: params.timeoutMs,
          cfg: runtime.ctx.cfg,
        })
      : undefined;
  const audit = await runtime.plugin.status.auditAccount({
    account,
    timeoutMs: params.timeoutMs,
    cfg: runtime.ctx.cfg,
    probe,
  });
  return {
    pluginId: params.pluginId,
    accountId,
    configured,
    supported: true,
    audit,
  };
}

async function buildStatusState(params) {
  const runtime = await loadPluginRuntime(params);
  if (!runtime.plugin || !runtime.ctx) {
    return {
      pluginId: params.pluginId,
      channelId: params.channelId,
      state: "plugin-unavailable",
      configured: false,
      actionsNeeded: true,
      issues: [],
    };
  }
  const accountIds = resolveAccountIds(runtime.plugin, runtime.ctx.cfg);
  const defaultAccountId = resolveDefaultAccountId(runtime.plugin, runtime.ctx.cfg, accountIds);
  const account = resolveAccount(runtime.plugin, runtime.ctx.cfg, defaultAccountId);
  const configured = await resolveConfigured(runtime.plugin, runtime.ctx.cfg, account);
  const probe = await buildProbeState(params);
  const audit = await buildAuditState(params);
  const issues = await resolveStatusIssues(runtime.plugin, runtime.ctx, account, probe.probe, audit.audit);
  return {
    pluginId: params.pluginId,
    channelId: params.channelId,
    accountId: defaultAccountId,
    configured,
    supported: {
      probe: typeof runtime.plugin?.status?.probeAccount === "function",
      audit: typeof runtime.plugin?.status?.auditAccount === "function",
      issues: Array.isArray(issues) || typeof runtime.plugin?.status?.issues === "function",
    },
    state: configured ? "configured" : "pending-config",
    actionsNeeded: !configured || (Array.isArray(issues) && issues.length > 0),
    probe,
    audit,
    issues: Array.isArray(issues) ? issues : [],
  };
}

async function buildActionsState(params) {
  const runtime = await loadPluginRuntime(params);
  if (!runtime.plugin || !runtime.ctx) {
    return {
      pluginId: params.pluginId,
      accountId: "default",
      actions: [],
      actionNames: [],
      supported: false,
    };
  }
  const accountIds = resolveAccountIds(runtime.plugin, runtime.ctx.cfg);
  const accountId =
    (params.accountId && params.accountId.trim()) ||
    resolveDefaultAccountId(runtime.plugin, runtime.ctx.cfg, accountIds);
  const discovered = await resolveMessageActions(runtime.plugin, runtime.ctx, accountId);
  const actions = Array.isArray(discovered) ? discovered : [];
  const actionNames = actions
    .map((entry) => {
      if (!isObject(entry)) {
        return "";
      }
      return typeof entry.action === "string"
        ? entry.action
        : typeof entry.name === "string"
          ? entry.name
          : "";
    })
    .filter(Boolean);
  return {
    pluginId: params.pluginId,
    accountId,
    actions,
    actionNames,
    supported: true,
  };
}

async function buildStartState(params) {
  const runtime = await loadPluginRuntime(params);
  if (!runtime.plugin || !runtime.ctx) {
    return { pluginId: params.pluginId, accountId: "default", started: false, supported: false };
  }
  const accountIds = resolveAccountIds(runtime.plugin, runtime.ctx.cfg);
  const accountId =
    (params.accountId && params.accountId.trim()) ||
    resolveDefaultAccountId(runtime.plugin, runtime.ctx.cfg, accountIds);
  const account = resolveAccount(runtime.plugin, runtime.ctx.cfg, accountId);
  if (typeof runtime.plugin?.gateway?.startAccount !== "function") {
    return { pluginId: params.pluginId, accountId, started: false, supported: false };
  }
  const result = await runtime.plugin.gateway.startAccount({
    cfg: runtime.ctx.cfg,
    accountId,
    account,
    runtime: runtime.ctx.runtime,
  });
  return {
    pluginId: params.pluginId,
    accountId,
    supported: true,
    ...(isObject(result) ? result : {}),
    started: isObject(result) && typeof result.started === "boolean" ? result.started : true,
  };
}

async function buildStopState(params) {
  const runtime = await loadPluginRuntime(params);
  if (!runtime.plugin || !runtime.ctx) {
    return { pluginId: params.pluginId, accountId: "default", stopped: false, supported: false };
  }
  const accountIds = resolveAccountIds(runtime.plugin, runtime.ctx.cfg);
  const accountId =
    (params.accountId && params.accountId.trim()) ||
    resolveDefaultAccountId(runtime.plugin, runtime.ctx.cfg, accountIds);
  const account = resolveAccount(runtime.plugin, runtime.ctx.cfg, accountId);
  if (typeof runtime.plugin?.gateway?.stopAccount !== "function") {
    return { pluginId: params.pluginId, accountId, stopped: false, supported: false };
  }
  const result = await runtime.plugin.gateway.stopAccount({
    cfg: runtime.ctx.cfg,
    accountId,
    account,
    runtime: runtime.ctx.runtime,
  });
  return {
    pluginId: params.pluginId,
    accountId,
    supported: true,
    ...(isObject(result) ? result : {}),
    stopped: isObject(result) && typeof result.stopped === "boolean" ? result.stopped : true,
  };
}

async function buildSendState(params) {
  const runtime = await loadPluginRuntime(params);
  if (!runtime.plugin || !runtime.ctx) {
    return {
      pluginId: params.pluginId,
      accountId: "default",
      peerId: params.peerId,
      ok: false,
      supported: false,
      reason: "plugin-unavailable",
    };
  }
  const accountIds = resolveAccountIds(runtime.plugin, runtime.ctx.cfg);
  const accountId =
    (params.accountId && params.accountId.trim()) ||
    resolveDefaultAccountId(runtime.plugin, runtime.ctx.cfg, accountIds);
  const sendHook = resolveHook(runtime.mod, runtime.plugin, "send");
  if (typeof sendHook !== "function") {
    return {
      pluginId: params.pluginId,
      accountId,
      peerId: params.peerId,
      ok: false,
      supported: false,
      reason: "send-unsupported",
    };
  }
  const value = await sendHook({
    ...runtime.ctx,
    accountId,
    peerId: params.peerId,
    text: params.text,
    replyTo: params.replyTo,
  });
  const result = normalizeSendResult(value);
  return {
    pluginId: params.pluginId,
    accountId,
    peerId: params.peerId,
    supported: true,
    ...result,
    ok: result.ok !== false,
  };
}

async function buildLogoutState(params) {
  const runtime = await loadPluginRuntime(params);
  if (!runtime.plugin || !runtime.ctx) {
    return {
      pluginId: params.pluginId,
      accountId: "default",
      supported: false,
      cleared: false,
      reason: "plugin-unavailable",
    };
  }
  const accountIds = resolveAccountIds(runtime.plugin, runtime.ctx.cfg);
  const accountId =
    (params.accountId && params.accountId.trim()) ||
    resolveDefaultAccountId(runtime.plugin, runtime.ctx.cfg, accountIds);
  const account = resolveAccount(runtime.plugin, runtime.ctx.cfg, accountId);
  if (typeof runtime.plugin?.gateway?.logoutAccount !== "function") {
    return {
      pluginId: params.pluginId,
      accountId,
      supported: false,
      cleared: false,
      reason: "logout-unsupported",
    };
  }
  const result = await runtime.plugin.gateway.logoutAccount({
    cfg: runtime.ctx.cfg,
    accountId,
    account,
    runtime: runtime.ctx.runtime,
  });
  return {
    pluginId: params.pluginId,
    accountId,
    supported: true,
    ...(isObject(result) ? result : {}),
  };
}

function stringifyResult(value) {
  return `${JSON.stringify(value)}\n`;
}

function parseConfigObject(configJson) {
  try {
    const value = configJson ? JSON.parse(configJson) : {};
    return isObject(value) ? value : {};
  } catch {
    return {};
  }
}

async function invokePluginHook(params) {
  const manifest = readJson(params.manifestPath);
  if (params.op === "inspect") {
    return { code: 0, stdout: stringifyResult(await buildPluginInspect(params)) };
  }
  if (params.op === "package-state") {
    return { code: 0, stdout: stringifyResult(await buildPackageState(params)) };
  }
  if (params.op === "setup") {
    return { code: 0, stdout: stringifyResult(await buildSetupState(params)) };
  }
  if (params.op === "setup-registry") {
    return { code: 0, stdout: stringifyResult(await buildSetupRegistryState(params)) };
  }
  if (params.op === "apply-setup") {
    return { code: 0, stdout: stringifyResult(await buildApplySetupState(params)) };
  }
  if (params.op === "runtime-forwarders") {
    return { code: 0, stdout: stringifyResult(await buildRuntimeForwardersState(params)) };
  }
  if (params.op === "resolve-account") {
    return { code: 0, stdout: stringifyResult(await buildResolveAccountState(params)) };
  }
  if (params.op === "accounts") {
    return { code: 0, stdout: stringifyResult(await buildAccountsState(params)) };
  }
  if (params.op === "bindings") {
    return { code: 0, stdout: stringifyResult(await buildBindingsState(params)) };
  }
  if (params.op === "configured-bindings") {
    return { code: 0, stdout: stringifyResult(await buildConfiguredBindingsState(params)) };
  }
  if (params.op === "configured-bindings-summary") {
    return { code: 0, stdout: stringifyResult(await buildConfiguredBindingsSummaryState(params)) };
  }
  if (params.op === "directory") {
    return { code: 0, stdout: stringifyResult(await buildDirectoryState(params)) };
  }
  if (params.op === "targets") {
    return { code: 0, stdout: stringifyResult(await buildTargetsState(params)) };
  }
  if (params.op === "status") {
    return { code: 0, stdout: stringifyResult(await buildStatusState(params)) };
  }
  if (params.op === "actions") {
    return { code: 0, stdout: stringifyResult(await buildActionsState(params)) };
  }
  if (params.op === "dispatch-action") {
    return { code: 0, stdout: stringifyResult(await buildDispatchActionState(params)) };
  }
  if (params.op === "probe") {
    return { code: 0, stdout: stringifyResult(await buildProbeState(params)) };
  }
  if (params.op === "audit") {
    return { code: 0, stdout: stringifyResult(await buildAuditState(params)) };
  }
  if (params.op === "logout") {
    return { code: 0, stdout: stringifyResult(await buildLogoutState(params)) };
  }
  if (params.op === "start") {
    return { code: 0, stdout: stringifyResult(await buildStartState(params)) };
  }
  if (params.op === "stop") {
    return { code: 0, stdout: stringifyResult(await buildStopState(params)) };
  }
  if (params.op === "send") {
    const send = await buildSendState(params);
    return { code: send.ok === false ? 1 : 0, stdout: stringifyResult(send) };
  }

  const pluginEntry = resolvePluginEntry(params.pluginRoot, manifest);
  if (!pluginEntry) {
    log(params.pluginRoot, `host: no plugin entry resolved for ${params.pluginId}/${params.channelId}`);
    return { code: params.op === "send" ? 1 : 0, stdout: "" };
  }

  try {
    const mod = await loadPluginModule(pluginEntry);
    const plugin = resolvePluginExport(mod);
    const hook = resolveHook(mod, plugin, params.op);
    if (hook) {
      const ctx = buildHostContext({
        manifest,
        pluginRoot: params.pluginRoot,
        pluginId: params.pluginId,
        channelId: params.channelId,
        configJson: params.configJson,
        manifestPath: params.manifestPath,
        peerId: params.peerId,
        text: params.text,
        replyTo: params.replyTo,
        accountId: params.accountId,
        target: params.target,
        action: params.action,
        payloadJson: params.payloadJson,
        groupId: params.groupId,
      });
      log(params.pluginRoot, `host: invoke-hook op=${params.op} entry=${pluginEntry}`);
      const value = await hook(ctx);
      if (params.op === "pull") {
        const items = normalizePullItems(value);
        const stdout = items.map((item) => JSON.stringify(item)).join("\n");
        return { code: 0, stdout: stdout ? `${stdout}\n` : "" };
      }
      if (params.op === "send") {
        const result = normalizeSendResult(value);
        return { code: result.ok === false ? 1 : 0, stdout: "" };
      }
      return { code: 0, stdout: "" };
    }
  } catch (error) {
    log(params.pluginRoot, `host: hook import/invoke failed ${String(error)}`);
  }

  const runtime = manifest.gatewayRuntime ?? {};
  const command =
    typeof runtime.hostCommand === "string" && runtime.hostCommand.trim()
      ? runtime.hostCommand.trim()
      : "node";
  const args = [
    pluginEntry,
    params.op,
    "--plugin-id",
    params.pluginId,
    "--channel-id",
    params.channelId,
    "--plugin-root",
    params.pluginRoot,
    "--manifest-path",
    params.manifestPath,
    "--compat-mode",
    "legacy-node-plugin",
    "--config-json",
    params.configJson ?? "",
  ];
  if (params.peerId) args.push("--peer-id", params.peerId);
  if (params.text) args.push("--text", params.text);
  if (params.replyTo) args.push("--reply-to", params.replyTo);

  log(params.pluginRoot, `host: forward-process op=${params.op} command=${command} entry=${pluginEntry}`);
  const result = spawnSync(command, args, {
    cwd: params.pluginRoot,
    env: {
      ...process.env,
      LEGACY_PLUGIN_MANIFEST: params.manifestPath,
      LEGACY_PLUGIN_ROOT: params.pluginRoot,
      LEGACY_PLUGIN_ID: params.pluginId,
      LEGACY_CHANNEL_ID: params.channelId,
      LEGACY_COMPAT_MODE: "legacy-node-plugin",
      LEGACY_PLUGIN_CONFIG_JSON: params.configJson ?? "",
    },
    encoding: "utf8",
  });
  if (result.error) {
    log(params.pluginRoot, `host: spawn error ${String(result.error)}`);
    return { code: 1, stdout: "" };
  }
  if (result.stderr) {
    log(params.pluginRoot, `host stderr: ${result.stderr.trim()}`);
  }
  return {
    code: typeof result.status === "number" ? result.status : 1,
    stdout: result.stdout ?? "",
  };
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const op = args._[0] ?? "";
  const pluginRoot = path.resolve(args["plugin-root"] ?? ".");
  const manifestPath = path.resolve(args["manifest-path"] ?? path.join(pluginRoot, "metis.plugin.json"));
  const pluginId = String(args["plugin-id"] ?? "").trim();
  const channelId = String(args["channel-id"] ?? "").trim();
  const configJson = String(args["config-json"] ?? "");
  const peerId = String(args["peer-id"] ?? "");
  const text = String(args["text"] ?? "");
  const replyTo = String(args["reply-to"] ?? "");
  const accountId = String(args["account-id"] ?? "");
  const target = String(args["target"] ?? "");
  const action = String(args["action"] ?? "");
  const payloadJson = String(args["payload-json"] ?? "");
  const groupId = String(args["group-id"] ?? "");
  const timeoutMs = Number.parseInt(String(args["timeout-ms"] ?? "10000"), 10) || 10000;

  if (!op || !pluginId || !channelId) {
    process.exit(2);
  }

  if (!fs.existsSync(manifestPath)) {
    log(pluginRoot, `host: manifest not found at ${manifestPath}`);
    process.exit(op === "send" ? 1 : 0);
  }

  const result = await invokePluginHook({
    pluginRoot,
    manifestPath,
    pluginId,
    channelId,
    configJson,
    op,
    peerId,
    text,
    replyTo,
    accountId,
    target,
    action,
    payloadJson,
    groupId,
    timeoutMs,
  });

  if (
    (op === "pull" ||
      op === "inspect" ||
      op === "package-state" ||
      op === "setup" ||
      op === "setup-registry" ||
      op === "apply-setup" ||
      op === "runtime-forwarders" ||
      op === "resolve-account" ||
      op === "accounts" ||
      op === "bindings" ||
      op === "configured-bindings" ||
      op === "configured-bindings-summary" ||
      op === "directory" ||
      op === "targets" ||
      op === "status" ||
      op === "actions" ||
      op === "dispatch-action" ||
      op === "probe" ||
      op === "audit" ||
      op === "logout" ||
      op === "start" ||
      op === "stop" ||
      op === "send") &&
    result.stdout
  ) {
    process.stdout.write(result.stdout);
  }
  process.exit(result.code);
}

await main();
