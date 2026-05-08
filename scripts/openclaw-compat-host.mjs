#!/usr/bin/env node

import fs from "node:fs";
import { createHash } from "node:crypto";
import { createRequire } from "node:module";
import os from "node:os";
import path from "node:path";
import readline from "node:readline";
import { pathToFileURL } from "node:url";

import { createRuntimeFacets, createRuntimeState } from "./openclaw-compat-runtime-facets.mjs";

const HOST_VERSION = "0.1.0";
const ENTRY_FALLBACKS = ["dist/index.js", "dist/index.mjs", "index.js", "index.mjs", "src/index.ts", "index.ts"];
const SENSITIVE_KEY = /(?:secret|token|password|passwd|authorization|api[_-]?key|credential)/i;
const requireFromHost = createRequire(import.meta.url);

function isObject(value) {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function parseArgs(argv) {
  const args = { once: false, oncePayload: "" };
  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    if (token === "--once") {
      args.once = true;
      const next = argv[i + 1];
      if (next && !next.startsWith("--")) {
        args.oncePayload = next;
        i += 1;
      }
    }
  }
  return args;
}

function readJson(raw, fallback = {}) {
  try {
    return raw ? JSON.parse(raw) : fallback;
  } catch {
    return fallback;
  }
}

function readJsonFile(file) {
  try {
    return readJson(fs.readFileSync(file, "utf8"), {});
  } catch {
    return {};
  }
}

function createRedactor(config = {}, secrets = {}) {
  const secretValues = new Set();

  function collect(value, key = "") {
    if (value == null) {
      return;
    }
    if (typeof value === "string") {
      if ((SENSITIVE_KEY.test(key) || key === "") && value) {
        secretValues.add(value);
      }
      return;
    }
    if (Array.isArray(value)) {
      for (const item of value) {
        collect(item, key);
      }
      return;
    }
    if (isObject(value)) {
      for (const [childKey, childValue] of Object.entries(value)) {
        collect(childValue, childKey);
      }
    }
  }

  collect(secrets);
  collect(config);

  function redactString(value) {
    let out = value;
    for (const secret of secretValues) {
      if (secret) {
        out = out.split(secret).join("[REDACTED]");
      }
    }
    return out;
  }

  function sanitize(value, key = "") {
    if (typeof value === "string") {
      if (SENSITIVE_KEY.test(key)) {
        return "[REDACTED]";
      }
      return redactString(value);
    }
    if (typeof value === "function") {
      return "[Function]";
    }
    if (Array.isArray(value)) {
      return value.map((item) => sanitize(item, key));
    }
    if (isObject(value)) {
      const out = {};
      for (const [childKey, childValue] of Object.entries(value)) {
        out[childKey] = sanitize(childValue, childKey);
      }
      return out;
    }
    return value;
  }

  return { sanitize, redactString };
}

function createState() {
  return {
    plugins: [],
    diagnostics: [],
    capabilities: emptyCapabilities(),
    handlers: emptyHandlers(),
    configSnapshot: {},
    secrets: {},
    redactor: createRedactor(),
    runtimeState: createRuntimeState(),
    runtimeVersion: HOST_VERSION,
  };
}

function emptyHandlers() {
  return {
    tools: [],
    providers: [],
    channels: [],
    hooks: [],
    commands: [],
    clis: [],
    httpRoutes: [],
    httpHandlers: [],
    interactiveHandlers: [],
    approvalHandlers: [],
    gatewayMethods: [],
  };
}

function emptyCapabilities() {
  return {
    tools: [],
    providers: [],
    channels: [],
    hooks: [],
    commands: [],
    clis: [],
    httpRoutes: [],
    httpHandlers: [],
    interactiveHandlers: [],
    approvalHandlers: [],
    memoryEmbeddingProviders: [],
    gatewayMethods: [],
    services: [],
  };
}

function resetStateForLoad(state, params) {
  state.plugins = [];
  state.diagnostics = [];
  state.capabilities = emptyCapabilities();
  state.handlers = emptyHandlers();
  state.configSnapshot = isObject(params.config) ? params.config : {};
  state.secrets = isObject(params.secrets) ? params.secrets : {};
  state.redactor = createRedactor(state.configSnapshot, state.secrets);
  state.runtimeVersion = String(params.runtime?.version ?? params.version ?? HOST_VERSION);
  state.runtimeState = createRuntimeState({
    ...params.runtime,
    version: state.runtimeVersion,
    config: state.configSnapshot,
    secrets: state.secrets,
    permissions: params.permissions,
    fetchPolicy: params.fetchPolicy,
    diagnostics: state.diagnostics,
    redactor: state.redactor,
  });
}

function rootsFromParams(params = {}) {
  const configured = params.roots ?? params.pluginRoots ?? params.plugins ?? [];
  const roots = Array.isArray(configured) ? configured : [configured];
  return roots
    .map((entry) => {
      if (typeof entry === "string") {
        return entry;
      }
      if (isObject(entry) && typeof entry.root === "string") {
        return entry.root;
      }
      return "";
    })
    .map((entry) => entry.trim())
    .filter(Boolean)
    .map((entry) => path.resolve(entry));
}

function firstString(...values) {
  for (const value of values) {
    if (typeof value === "string" && value.trim()) {
      return value.trim();
    }
  }
  return "";
}

function pluginIdFor(root, openclawManifest, packageJson) {
  return (
    firstString(
      openclawManifest.id,
      openclawManifest.name,
      openclawManifest.plugin?.id,
      packageJson.openclaw?.id,
      packageJson.name,
      path.basename(root),
    ) || path.basename(root)
  );
}

function addEntryCandidate(out, candidate) {
  if (Array.isArray(candidate)) {
    for (const item of candidate) {
      addEntryCandidate(out, item);
    }
    return;
  }
  if (isObject(candidate)) {
    addEntryCandidate(out, candidate.default);
    addEntryCandidate(out, candidate.import);
    addEntryCandidate(out, candidate.entry);
    return;
  }
  if (typeof candidate !== "string" || !candidate.trim()) {
    return;
  }
  const value = candidate.trim();
  if (value.endsWith("/src/index.ts") || value === "src/index.ts" || value === "./src/index.ts") {
    out.push(value.replace(/(?:^\.\/)?src\/index\.ts$/, "dist/index.js"));
  } else if (value.endsWith("/index.ts") || value === "index.ts" || value === "./index.ts") {
    out.push(value.replace(/(?:^\.\/)?index\.ts$/, "dist/index.js"));
  }
  out.push(value);
}

function packageExportCandidates(exportsField) {
  if (typeof exportsField === "string") {
    return [exportsField];
  }
  if (!isObject(exportsField)) {
    return [];
  }
  const dot = exportsField["."];
  if (typeof dot === "string") {
    return [dot];
  }
  if (isObject(dot)) {
    return [dot.default, dot.import].filter((value) => typeof value === "string" && value.trim());
  }
  return [];
}

function entryCandidates(openclawManifest, packageJson) {
  const runtime = isObject(openclawManifest.runtime) ? openclawManifest.runtime : {};
  const gatewayRuntime = isObject(openclawManifest.gatewayRuntime) ? openclawManifest.gatewayRuntime : {};
  const plugin = isObject(openclawManifest.plugin) ? openclawManifest.plugin : {};
  const pkgOpenClaw = isObject(packageJson.openclaw) ? packageJson.openclaw : {};
  const pkgPlugin = isObject(pkgOpenClaw.plugin) ? pkgOpenClaw.plugin : {};
  const pkgMetis = isObject(packageJson.metis) ? packageJson.metis : {};

  const out = [];
  for (const candidate of [
    openclawManifest.entry,
    openclawManifest.main,
    openclawManifest.module,
    plugin.entry,
    runtime.entry,
    runtime.pluginEntry,
    runtime.openclawEntry,
    gatewayRuntime.entry,
    gatewayRuntime.pluginEntry,
    gatewayRuntime.openclawEntry,
    pkgOpenClaw.extensions,
    pkgOpenClaw.entry,
    pkgOpenClaw.pluginEntry,
    pkgPlugin.entry,
    pkgMetis.pluginEntry,
    packageExportCandidates(packageJson.exports),
    packageJson.module,
    packageJson.main,
    ...ENTRY_FALLBACKS,
  ]) {
    addEntryCandidate(out, candidate);
  }
  return [...new Set(out)];
}

function discoverPlugin(root) {
  const packagePath = path.join(root, "package.json");
  const openclawManifestPath = path.join(root, "openclaw.plugin.json");
  const packageJson = fs.existsSync(packagePath) ? readJsonFile(packagePath) : {};
  const openclawManifest = fs.existsSync(openclawManifestPath) ? readJsonFile(openclawManifestPath) : {};
  const id = pluginIdFor(root, openclawManifest, packageJson);
  const manifestPath = fs.existsSync(openclawManifestPath) ? openclawManifestPath : fs.existsSync(packagePath) ? packagePath : "";

  let entry = "";
  for (const candidate of entryCandidates(openclawManifest, packageJson)) {
    if (typeof candidate !== "string" || !candidate.trim()) {
      continue;
    }
    const resolved = path.isAbsolute(candidate) ? candidate : path.join(root, candidate);
    if (fs.existsSync(resolved) && fs.statSync(resolved).isFile()) {
      entry = resolved;
      break;
    }
  }

  const diagnostics = [];
  if (!entry) {
    diagnostics.push({ code: "entry_not_found", pluginId: id, root });
  }

  return {
    plugin: {
      id,
      root,
      entry,
      manifestPath,
      packagePath: fs.existsSync(packagePath) ? packagePath : "",
    },
    diagnostics,
  };
}

function discoverPlugins(roots) {
  const plugins = [];
  const diagnostics = [];
  for (const root of roots) {
    const discovered = discoverPlugin(root);
    plugins.push(discovered.plugin);
    diagnostics.push(...discovered.diagnostics);
  }
  return { plugins, diagnostics };
}

function capabilityName(spec, fallback = "") {
  if (typeof spec === "string") {
    return spec;
  }
  if (!isObject(spec)) {
    return fallback;
  }
  const plugin = isObject(spec.plugin) ? spec.plugin : {};
  return firstString(spec.name, spec.id, spec.command, spec.path, spec.method, plugin.id, plugin.name, fallback);
}

function addCapability(state, collection, pluginId, spec, extra = {}) {
  const sanitizedSpec = state.redactor.sanitize(spec);
  const plugin = isObject(spec) && isObject(spec.plugin) ? spec.plugin : {};
  const record = {
    pluginId,
    name: capabilityName(spec, extra.name),
    id: isObject(spec) ? firstString(spec.id, spec.name, plugin.id, plugin.name) : "",
    path: isObject(spec) ? firstString(spec.path) : "",
    command: isObject(spec) ? firstString(spec.command, spec.name) : "",
    method: isObject(spec) ? firstString(spec.method) : "",
    kind: isObject(spec) ? firstString(spec.kind, spec.type) : "",
    spec: sanitizedSpec,
    ...extra,
  };
  state.capabilities[collection].push(record);
  return record;
}

function addDiagnostic(state, diagnostic) {
  state.diagnostics.push(state.redactor.sanitize(diagnostic));
}

function buildRuntimeFacade(state, pluginId) {
  const runtime = createRuntimeFacets(state.runtimeState, pluginId);
  return {
    ...runtime,
    logger: buildLogger(state, pluginId),
  };
}

function buildLogger(state, pluginId) {
  const logger = {};
  for (const level of ["debug", "info", "warn", "error"]) {
    logger[level] = (message, meta = {}) => {
      addDiagnostic(state, {
        code: "plugin_log",
        pluginId,
        level,
        message: String(message ?? ""),
        meta,
      });
    };
  }
  return logger;
}

function storeHandler(state, collection, record, handler) {
  if (typeof handler === "function" || isObject(handler)) {
    state.handlers[collection].push({ record, handler });
  }
}

function handlerFromSpec(spec, handler) {
  if (typeof handler === "function" || isObject(handler)) {
    return handler;
  }
  if (isObject(spec) && (typeof spec.handler === "function" || isObject(spec.handler))) {
    return spec.handler;
  }
  if (isObject(spec) && isObject(spec.plugin)) {
    return spec.plugin;
  }
  return null;
}

function registerCapabilityWithHandler(state, collection, pluginId, spec, handler, extra = {}) {
  const resolvedHandler = handlerFromSpec(spec, handler);
  const record = addCapability(state, collection, pluginId, spec, {
    handlerRegistered: Boolean(resolvedHandler),
    ...extra,
  });
  storeHandler(state, collection, record, resolvedHandler);
}

function buildApi(state, plugin) {
  const pluginId = plugin.id;
  const runtime = buildRuntimeFacade(state, pluginId);
  const api = {
    pluginId,
    pluginRoot: plugin.root,
    version: runtime.version,
    runtime,
    config: runtime.config,
    secrets: runtime.secrets,
    logger: runtime.logger,
    registerTool: (spec, handler) => registerCapabilityWithHandler(state, "tools", pluginId, spec, handler),
    registerProvider: (spec, handler) => registerCapabilityWithHandler(state, "providers", pluginId, spec, handler),
    registerChannel: (spec, handler) => registerCapabilityWithHandler(state, "channels", pluginId, spec, handler),
    registerHook: (kindOrSpec, handler) => {
      const spec = typeof kindOrSpec === "string" ? { name: kindOrSpec } : kindOrSpec;
      registerCapabilityWithHandler(state, "hooks", pluginId, spec, handler);
    },
    registerCommand: (spec, handler) => registerCapabilityWithHandler(state, "commands", pluginId, spec, handler),
    registerCli: (spec, handler) => registerCapabilityWithHandler(state, "clis", pluginId, spec, handler),
    registerHttpRoute: (spec, handler) => registerCapabilityWithHandler(state, "httpRoutes", pluginId, spec, handler),
    registerHttpHandler: (spec, handler) => registerCapabilityWithHandler(state, "httpHandlers", pluginId, spec, handler),
    registerInteractiveHandler: (spec, handler) =>
      registerCapabilityWithHandler(state, "interactiveHandlers", pluginId, spec, handler),
    registerApprovalHandler: (spec, handler) =>
      registerCapabilityWithHandler(state, "approvalHandlers", pluginId, spec, handler),
    registerMemoryEmbeddingProvider: (spec) => addCapability(state, "memoryEmbeddingProviders", pluginId, spec),
    registerGatewayMethod: (spec, handler) => registerCapabilityWithHandler(state, "gatewayMethods", pluginId, spec, handler),
    registerService: (spec) => addCapability(state, "services", pluginId, spec),
  };

  return new Proxy(api, {
    get(target, property) {
      if (property in target) {
        return target[property];
      }
      if (typeof property === "string" && property.startsWith("register")) {
        return (...args) => {
          addDiagnostic(state, {
            code: "unknown_capability",
            pluginId,
            capability: property,
            args,
          });
        };
      }
      return undefined;
    },
  });
}

async function loadPlugin(state, plugin) {
  if (!plugin.entry) {
    addDiagnostic(state, { code: "entry_not_found", pluginId: plugin.id, root: plugin.root });
    return;
  }

  try {
    const module = await importPluginModule(state, plugin);
    if (!module) {
      return;
    }
    const exported = module.default ?? module.plugin ?? module.openclawPlugin ?? module;
    const api = buildApi(state, plugin);
    if (typeof exported === "function") {
      await exported(api);
    } else if (isObject(exported) && typeof exported.register === "function") {
      await exported.register(api);
    } else if (typeof module.register === "function") {
      await module.register(api);
    } else {
      addDiagnostic(state, { code: "register_not_found", pluginId: plugin.id, entry: plugin.entry });
      return;
    }
    state.plugins.push(plugin);
  } catch (error) {
    addDiagnostic(state, {
      code: "plugin_load_error",
      pluginId: plugin.id,
      entry: plugin.entry,
      message: error?.message ?? String(error),
      stack: error?.stack ?? "",
    });
  }
}

function isTsEntry(file) {
  return file.endsWith(".ts") || file.endsWith(".tsx");
}

function resolvePackageFrom(root, packageName) {
  try {
    return createRequire(path.join(root, "package.json")).resolve(packageName);
  } catch {
    try {
      return requireFromHost.resolve(packageName);
    } catch {
      return "";
    }
  }
}

async function loadTsEntry(state, plugin) {
  const esbuildPath = resolvePackageFrom(plugin.root, "esbuild");
  if (!esbuildPath) {
    addDiagnostic(state, {
      code: "ts_entry_loader_unavailable",
      pluginId: plugin.id,
      entry: plugin.entry,
      message: "TypeScript entry requires a built dist entry or an available esbuild/tsx-compatible loader.",
      loaders: { esbuild: false, tsx: Boolean(resolvePackageFrom(plugin.root, "tsx")) },
    });
    return null;
  }

  const esbuild = await import(pathToFileURL(esbuildPath).href);
  const source = fs.readFileSync(plugin.entry, "utf8");
  const result = await esbuild.transform(source, {
    loader: plugin.entry.endsWith(".tsx") ? "tsx" : "ts",
    format: "esm",
    target: "node22",
    sourcemap: "inline",
  });
  const hash = createHash("sha256").update(plugin.entry).update(source).digest("hex").slice(0, 16);
  const cacheDir = path.join(os.tmpdir(), "metis-openclaw-ts-cache");
  fs.mkdirSync(cacheDir, { recursive: true });
  const cacheFile = path.join(cacheDir, `${hash}.mjs`);
  fs.writeFileSync(cacheFile, result.code, "utf8");
  addDiagnostic(state, { code: "ts_entry_transpiled", pluginId: plugin.id, entry: plugin.entry, cacheFile });
  return import(pathToFileURL(cacheFile).href);
}

async function importPluginModule(state, plugin) {
  if (isTsEntry(plugin.entry)) {
    return loadTsEntry(state, plugin);
  }
  return import(pathToFileURL(plugin.entry).href);
}

async function loadPlugins(state, params) {
  resetStateForLoad(state, params);
  const discovered = discoverPlugins(rootsFromParams(params));
  state.diagnostics.push(...discovered.diagnostics.map((diagnostic) => state.redactor.sanitize(diagnostic)));
  for (const plugin of discovered.plugins) {
    await loadPlugin(state, plugin);
  }
  return registeredResult(state, { loadedPluginCount: state.plugins.length });
}

function registeredResult(state, extra = {}) {
  return {
    ok: true,
    runtime: "openclaw-compat-host",
    version: HOST_VERSION,
    loadedPluginCount: state.plugins.length,
    plugins: state.redactor.sanitize(state.plugins),
    capabilities: state.redactor.sanitize(state.capabilities),
    gatewayRegistries: state.redactor.sanitize(buildGatewayRegistries(state)),
    config: state.redactor.sanitize(state.configSnapshot),
    diagnostics: state.redactor.sanitize(state.diagnostics),
    ...extra,
  };
}

function registryRecord(record, method, params = {}) {
  return {
    pluginId: record.pluginId,
    name: record.name,
    id: record.id,
    path: record.path,
    command: record.command,
    method: record.method,
    kind: record.kind,
    spec: record.spec,
    handlerRegistered: Boolean(record.handlerRegistered),
    dispatch: { method, params },
  };
}

function buildGatewayRegistries(state) {
  return {
    channels: state.capabilities.channels.map((record) =>
      registryRecord(record, "channel.start", { id: record.id || record.name }),
    ),
    httpRoutes: state.capabilities.httpRoutes.map((record) =>
      registryRecord(record, "http.dispatch", { method: record.method || "GET", path: record.path }),
    ),
    httpHandlers: state.capabilities.httpHandlers.map((record) =>
      registryRecord(record, "http.dispatch", { name: record.name || record.id }),
    ),
    tools: state.capabilities.tools.map((record) => registryRecord(record, "tool.execute", { name: record.name || record.id })),
    providers: state.capabilities.providers.map((record) =>
      registryRecord(record, "provider.invoke", { id: record.id || record.name }),
    ),
    hooks: state.capabilities.hooks.map((record) => registryRecord(record, "hook.dispatch", { name: record.name || record.id })),
  };
}

function healthResult(state) {
  return {
    ok: true,
    status: "ok",
    runtime: "openclaw-compat-host",
    version: HOST_VERSION,
    runtimeVersion: state.runtimeVersion,
    loadedPluginCount: state.plugins.length,
    capabilityCounts: Object.fromEntries(Object.entries(state.capabilities).map(([key, value]) => [key, value.length])),
    diagnostics: state.redactor.sanitize(state.diagnostics),
  };
}

function matchesCapability(record, params, keys) {
  for (const key of keys) {
    const expected = params[key];
    if (typeof expected !== "string" || !expected.trim()) {
      continue;
    }
    const value = expected.trim();
    if (record.name === value || record.id === value || record.path === value || record.command === value || record.method === value) {
      return true;
    }
  }
  return false;
}

function findHandlerEntry(state, collection, params, keys) {
  const entries = state.handlers[collection] ?? [];
  return entries.find((entry) => matchesCapability(entry.record, params, keys));
}

async function callHandler(target, args, methodNames = []) {
  if (typeof target === "function") {
    return target(...args);
  }
  if (isObject(target)) {
    for (const method of methodNames) {
      if (typeof target[method] === "function") {
        return target[method](...args);
      }
    }
  }
  return { ok: false, status: "handler_not_found" };
}

function handlerNotFound(collection, params) {
  return { ok: false, status: "handler_not_found", collection, params };
}

async function dispatchChannel(state, action, params) {
  const entry = findHandlerEntry(state, "channels", params, ["id", "name", "channelId"]);
  if (!entry) {
    return handlerNotFound("channels", params);
  }
  if (action === "start") {
    return callHandler(entry.handler, [params.context ?? params], ["start"]);
  }
  if (action === "stop") {
    return callHandler(entry.handler, [params.context ?? params], ["stop"]);
  }
  if (action === "health") {
    return callHandler(entry.handler, [params.context ?? params], ["health"]);
  }
  if (action === "pullInbound") {
    return callHandler(entry.handler, [params], ["pullInbound", "pull", "poll"]);
  }
  if (action === "send") {
    return callHandler(entry.handler, [params.message ?? params, params.context ?? {}], ["send", "sendMessage"]);
  }
  return { ok: false, status: "unknown_channel_action", action };
}

async function dispatchHttp(state, params) {
  const method = String(params.method ?? "GET").toUpperCase();
  const pathValue = String(params.path ?? "");
  const route = state.handlers.httpRoutes.find(
    (entry) =>
      entry.record.path === pathValue &&
      (!entry.record.method || entry.record.method.toUpperCase() === method || entry.record.method === "*"),
  );
  const entry = route ?? findHandlerEntry(state, "httpHandlers", params, ["name", "id", "path"]);
  if (!entry) {
    return handlerNotFound("http", params);
  }
  return callHandler(entry.handler, [{ ...params, method, path: pathValue }], ["dispatch", "handle", "request"]);
}

async function dispatchTool(state, params) {
  const entry = findHandlerEntry(state, "tools", params, ["name", "id", "tool"]);
  if (!entry) {
    return handlerNotFound("tools", params);
  }
  return callHandler(entry.handler, [params.input ?? {}, params.context ?? {}], ["execute", "run"]);
}

async function dispatchProvider(state, params) {
  const entry = findHandlerEntry(state, "providers", params, ["id", "name", "provider"]);
  if (!entry) {
    return handlerNotFound("providers", params);
  }
  return callHandler(entry.handler, [params.request ?? {}, params.context ?? {}], ["invoke", "generate", "complete"]);
}

async function dispatchHook(state, params) {
  const entry = findHandlerEntry(state, "hooks", params, ["name", "id", "hook", "kind"]);
  if (!entry) {
    return handlerNotFound("hooks", params);
  }
  return callHandler(entry.handler, [params.payload ?? {}, params.context ?? {}], ["dispatch", "handle"]);
}

async function handleRequest(state, request) {
  const id = request?.id ?? null;
  try {
    if (!isObject(request)) {
      throw new Error("request must be a JSON object");
    }
    const method = String(request.method ?? "");
    const params = isObject(request.params) ? request.params : {};
    if (method === "plugin.discover") {
      const discovered = discoverPlugins(rootsFromParams(params));
      return response(id, {
        ok: true,
        plugins: discovered.plugins,
        diagnostics: discovered.diagnostics,
      });
    }
    if (method === "plugin.load") {
      return response(id, await loadPlugins(state, params));
    }
    if (method === "plugin.registeredCapabilities") {
      return response(id, registeredResult(state));
    }
    if (method === "runtime.health") {
      return response(id, healthResult(state));
    }
    if (method === "runtime.stop") {
      return response(id, { ok: true, status: "stopping" });
    }
    if (method === "channel.start") {
      return response(id, await dispatchChannel(state, "start", params));
    }
    if (method === "channel.stop") {
      return response(id, await dispatchChannel(state, "stop", params));
    }
    if (method === "channel.health") {
      return response(id, await dispatchChannel(state, "health", params));
    }
    if (method === "channel.pullInbound") {
      return response(id, await dispatchChannel(state, "pullInbound", params));
    }
    if (method === "channel.send") {
      return response(id, await dispatchChannel(state, "send", params));
    }
    if (method === "http.dispatch") {
      return response(id, await dispatchHttp(state, params));
    }
    if (method === "tool.execute") {
      return response(id, await dispatchTool(state, params));
    }
    if (method === "provider.invoke") {
      return response(id, await dispatchProvider(state, params));
    }
    if (method === "hook.dispatch") {
      return response(id, await dispatchHook(state, params));
    }
    return response(id, null, { code: -32601, message: `unknown method: ${method}` });
  } catch (error) {
    return response(id, null, {
      code: -32000,
      message: state.redactor.redactString(error?.message ?? String(error)),
    });
  }
}

function response(id, result, error = null) {
  if (error) {
    return { jsonrpc: "2.0", id, error };
  }
  return { jsonrpc: "2.0", id, result };
}

function parseRequestLine(line) {
  try {
    return JSON.parse(line);
  } catch (error) {
    return { jsonrpc: "2.0", id: null, method: "", params: {}, parseError: error.message };
  }
}

function readStdin() {
  return new Promise((resolve) => {
    let data = "";
    process.stdin.setEncoding("utf8");
    process.stdin.on("data", (chunk) => {
      data += chunk;
    });
    process.stdin.on("end", () => resolve(data));
  });
}

async function runOnce(payload) {
  const state = createState();
  const raw = payload || (await readStdin());
  const firstLine = raw.split(/\n/).find((line) => line.trim()) ?? "";
  const request = parseRequestLine(firstLine);
  const out = request.parseError
    ? response(null, null, { code: -32700, message: request.parseError })
    : await handleRequest(state, request);
  process.stdout.write(`${JSON.stringify(state.redactor.sanitize(out))}\n`);
}

async function runPersistent() {
  const state = createState();
  const input = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
  for await (const line of input) {
    if (!line.trim()) {
      continue;
    }
    const request = parseRequestLine(line);
    const out = request.parseError
      ? response(null, null, { code: -32700, message: request.parseError })
      : await handleRequest(state, request);
    process.stdout.write(`${JSON.stringify(state.redactor.sanitize(out))}\n`);
    if (!request.parseError && request.method === "runtime.stop") {
      input.close();
      break;
    }
  }
}

const args = parseArgs(process.argv.slice(2));
if (args.once) {
  await runOnce(args.oncePayload);
} else {
  await runPersistent();
}
