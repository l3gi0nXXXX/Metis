#!/usr/bin/env node

import fs from "node:fs";
import { createHash } from "node:crypto";
import { createRequire } from "node:module";
import os from "node:os";
import path from "node:path";
import readline from "node:readline";
import { pathToFileURL } from "node:url";

import { createRuntimeFacets, createRuntimeState } from "./openclaw-compat-runtime-facets.mjs";
import { OpenClawSecurityEnforcer, derivePermissionRequirements } from "./openclaw-compat-security-policy.mjs";

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
    security: defaultSecurityOptions(),
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
    setupSurfaces: [],
    doctorDiagnostics: [],
  };
}

function defaultSecurityOptions() {
  return {
    enabled: false,
    grants: {},
    source: {},
    sources: {},
    sourceAllowlist: [],
    approvalCategories: undefined,
    handlerTimeoutMs: 30000,
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
    configSchemas: [],
    setupSurfaces: [],
    doctorDiagnostics: [],
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
  state.security = securityOptionsFromParams(params);
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

function securityOptionsFromParams(params) {
  const security = isObject(params.security) ? params.security : {};
  const handlerTimeoutMs = Number(security.handlerTimeoutMs ?? params.handlerTimeoutMs ?? 30000);
  return {
    enabled: security.enabled === true,
    grants: isObject(security.grants) ? security.grants : isObject(params.securityGrants) ? params.securityGrants : {},
    source: isObject(security.source) ? security.source : isObject(params.source) ? params.source : {},
    sources: isObject(security.sources) ? security.sources : isObject(params.sources) ? params.sources : {},
    sourceAllowlist: security.sourceAllowlist ?? params.sourceAllowlist ?? [],
    approvalCategories: Array.isArray(security.approvalCategories) ? security.approvalCategories : undefined,
    handlerTimeoutMs: Number.isFinite(handlerTimeoutMs) && handlerTimeoutMs > 0 ? handlerTimeoutMs : 30000,
  };
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

function isSensitiveSchemaField(name, field = {}) {
  return (
    SENSITIVE_KEY.test(String(name ?? "")) ||
    String(field.format ?? "").toLowerCase() === "password" ||
    field.secret === true ||
    field["x-secret"] === true
  );
}

function redactConfigSchemaDefaults(value, parentKey = "") {
  if (Array.isArray(value)) {
    return value.map((item) => redactConfigSchemaDefaults(item, parentKey));
  }
  if (!isObject(value)) {
    return value;
  }

  const sensitiveSelf = isSensitiveSchemaField(parentKey, value);
  const out = {};
  for (const [key, childValue] of Object.entries(value)) {
    if (key === "default" && sensitiveSelf) {
      continue;
    }
    if (key === "properties" && isObject(childValue)) {
      out[key] = Object.fromEntries(
        Object.entries(childValue).map(([fieldName, fieldValue]) => [fieldName, redactConfigSchemaDefaults(fieldValue, fieldName)]),
      );
      continue;
    }
    out[key] = redactConfigSchemaDefaults(childValue, key);
  }
  return out;
}

function addCapability(state, collection, pluginId, spec, extra = {}) {
  const sanitizedSpec = state.redactor.sanitize(redactConfigSchemaDefaults(spec));
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
  state.diagnostics.push(state.redactor.sanitize(redactConfigSchemaDefaults(diagnostic)));
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
  collectConfigurationFacets(state, pluginId, spec, "capability");
}

function pluginManifest(plugin) {
  return plugin.manifestPath.endsWith("openclaw.plugin.json") ? readJsonFile(plugin.manifestPath) : {};
}

function pluginPackageJson(plugin) {
  return plugin.packagePath ? readJsonFile(plugin.packagePath) : {};
}

function collectManifestConfigurationFacets(state, plugin, manifest) {
  if (!isObject(manifest)) {
    return;
  }
  if (isObject(manifest.configSchema)) {
    addCapability(state, "configSchemas", plugin.id, {
      name: plugin.id,
      id: plugin.id,
      source: "manifest.configSchema",
      schema: manifest.configSchema,
      setupHints: Array.isArray(manifest.setupHints) ? manifest.setupHints : [],
      installHints: Array.isArray(manifest.installHints) ? manifest.installHints : [],
    });
  }
  if (Array.isArray(manifest.setupHints) || Array.isArray(manifest.installHints) || isObject(manifest.setup)) {
    addCapability(state, "setupSurfaces", plugin.id, {
      name: plugin.id,
      id: plugin.id,
      source: "manifest.setup",
      setup: isObject(manifest.setup) ? manifest.setup : {},
      setupHints: Array.isArray(manifest.setupHints) ? manifest.setupHints : [],
      installHints: Array.isArray(manifest.installHints) ? manifest.installHints : [],
    });
  }
  if (isObject(manifest.doctor)) {
    addCapability(state, "doctorDiagnostics", plugin.id, {
      name: plugin.id,
      id: plugin.id,
      source: "manifest.doctor",
      doctor: manifest.doctor,
    });
  }
}

function collectConfigurationFacets(state, pluginId, spec, source) {
  if (!isObject(spec)) {
    return;
  }
  const name = capabilityName(spec, pluginId);
  if (isObject(spec.configSchema)) {
    addCapability(state, "configSchemas", pluginId, {
      name,
      id: firstString(spec.id, spec.name, name),
      source: `${source}.configSchema`,
      schema: spec.configSchema,
      ownerCapability: name,
    });
  }
  if (isObject(spec.setup) || isObject(spec.setupWizard)) {
    addCapability(state, "setupSurfaces", pluginId, {
      name,
      id: firstString(spec.id, spec.name, name),
      source: `${source}.setup`,
      setup: spec.setup ?? {},
      setupWizard: spec.setupWizard ?? {},
      ownerCapability: name,
    });
  }
  if (isObject(spec.doctor)) {
    addCapability(state, "doctorDiagnostics", pluginId, {
      name,
      id: firstString(spec.id, spec.name, name),
      source: `${source}.doctor`,
      doctor: spec.doctor,
      ownerCapability: name,
    });
  }
}

function sourceForPlugin(state, plugin) {
  const sources = state.security.sources;
  if (isObject(sources)) {
    if (isObject(sources[plugin.id])) {
      return sources[plugin.id];
    }
    if (isObject(sources[plugin.root])) {
      return sources[plugin.root];
    }
    if (isObject(sources.default)) {
      return sources.default;
    }
  }
  return state.security.source;
}

function capabilityRecordsForPlugin(state, pluginId) {
  const records = [];
  for (const collection of Object.values(state.capabilities)) {
    for (const record of collection) {
      if (record.pluginId === pluginId) {
        records.push(record.spec ?? record);
      }
    }
  }
  return records;
}

function prunePluginRegistrations(state, pluginId) {
  for (const [key, collection] of Object.entries(state.capabilities)) {
    state.capabilities[key] = collection.filter((record) => record.pluginId !== pluginId);
  }
  for (const [key, collection] of Object.entries(state.handlers)) {
    state.handlers[key] = collection.filter((entry) => entry.record.pluginId !== pluginId);
  }
}

function createSecurityEnforcer(state, plugin, capabilityRecords = []) {
  const options = {
    pluginId: plugin.id,
    manifest: pluginManifest(plugin),
    packageJson: pluginPackageJson(plugin),
    capabilityRecords,
    source: sourceForPlugin(state, plugin),
    sourceAllowlist: state.security.sourceAllowlist,
    grants: state.security.grants,
  };
  if (state.security.approvalCategories) {
    options.approvalCategories = state.security.approvalCategories;
  }
  return new OpenClawSecurityEnforcer(options);
}

function enforceStartGate(state, plugin, capabilityRecords, phase) {
  if (!state.security.enabled) {
    return true;
  }
  const decision = createSecurityEnforcer(state, plugin, capabilityRecords).enforceStart();
  if (decision.allowed) {
    return true;
  }
  addDiagnostic(state, {
    code: "security_start_denied",
    pluginId: plugin.id,
    phase,
    decision,
  });
  return false;
}

async function dispatchThroughSecurity(state, entry, stage, handler) {
  const plugin = state.plugins.find((candidate) => candidate.id === entry.record.pluginId) ?? {
    id: entry.record.pluginId,
    root: "",
    manifestPath: "",
    packagePath: "",
  };
  if (!state.security.enabled) {
    const decision = await createSecurityEnforcer(state, plugin, []).runGuardedHandler(stage, handler, {
      timeoutMs: state.security.handlerTimeoutMs,
    });
    if (!decision.allowed) {
      return decision;
    }
    return decision.diagnostics?.result ?? { ok: true };
  }
  const permissionRequests = derivePermissionRequirements({ capabilityRecords: [entry.record.spec ?? entry.record] });
  const decision = await createSecurityEnforcer(state, plugin, []).dispatchHandler(stage, permissionRequests, handler, {
    timeoutMs: state.security.handlerTimeoutMs,
  });
  if (!decision.allowed) {
    return decision;
  }
  return decision.diagnostics?.result ?? { ok: true };
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
    registerWebSearchProvider: (spec, handler) => registerCapabilityWithHandler(state, "providers", pluginId, spec, handler, {
      kind: "web-search",
    }),
    registerChannel: (spec, handler) => registerCapabilityWithHandler(state, "channels", pluginId, spec, handler),
    registerHook: (kindOrSpec, handler) => {
      const spec = typeof kindOrSpec === "string" ? { name: kindOrSpec } : kindOrSpec;
      registerCapabilityWithHandler(state, "hooks", pluginId, spec, handler);
    },
    registerMessageHook: (kindOrSpec, handler) => {
      const spec = typeof kindOrSpec === "string" ? { name: kindOrSpec } : kindOrSpec;
      registerCapabilityWithHandler(state, "hooks", pluginId, spec, handler, { kind: "message" });
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
    registerConfigSchema: (spec) => addCapability(state, "configSchemas", pluginId, spec),
    registerSetup: (spec, handler) => registerCapabilityWithHandler(state, "setupSurfaces", pluginId, spec, handler),
    registerDoctor: (spec, handler) => registerCapabilityWithHandler(state, "doctorDiagnostics", pluginId, spec, handler),
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
            releaseBlocker: true,
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
  if (!enforceStartGate(state, plugin, [], "preload")) {
    return;
  }

  try {
    collectManifestConfigurationFacets(state, plugin, pluginManifest(plugin));
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
    const capabilityRecords = capabilityRecordsForPlugin(state, plugin.id);
    if (!enforceStartGate(state, plugin, capabilityRecords, "capabilities")) {
      prunePluginRegistrations(state, plugin.id);
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
    configSchemas: state.capabilities.configSchemas.map((record) =>
      registryRecord(record, "config.schema", { pluginId: record.pluginId, name: record.name || record.id }),
    ),
    setupSurfaces: state.capabilities.setupSurfaces.map((record) =>
      registryRecord(record, "setup.status", { pluginId: record.pluginId, name: record.name || record.id }),
    ),
    doctorDiagnostics: state.capabilities.doctorDiagnostics.map((record) =>
      registryRecord(record, "doctor.run", { pluginId: record.pluginId, name: record.name || record.id }),
    ),
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
    return dispatchThroughSecurity(state, entry, "channel.start", () => callHandler(entry.handler, [params.context ?? params], ["start"]));
  }
  if (action === "stop") {
    return dispatchThroughSecurity(state, entry, "channel.stop", () => callHandler(entry.handler, [params.context ?? params], ["stop"]));
  }
  if (action === "health") {
    return dispatchThroughSecurity(state, entry, "channel.health", () =>
      callHandler(entry.handler, [params.context ?? params], ["health"]),
    );
  }
  if (action === "pullInbound") {
    return dispatchThroughSecurity(state, entry, "channel.pullInbound", () =>
      callHandler(entry.handler, [params], ["pullInbound", "pull", "poll"]),
    );
  }
  if (action === "send") {
    return dispatchThroughSecurity(state, entry, "channel.send", () =>
      callHandler(entry.handler, [params.message ?? params, params.context ?? {}], ["send", "sendMessage"]),
    );
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
  return dispatchThroughSecurity(state, entry, "http.dispatch", () =>
    callHandler(entry.handler, [{ ...params, method, path: pathValue }], ["dispatch", "handle", "request"]),
  );
}

async function dispatchTool(state, params) {
  const entry = findHandlerEntry(state, "tools", params, ["name", "id", "tool"]);
  if (!entry) {
    return handlerNotFound("tools", params);
  }
  return dispatchThroughSecurity(state, entry, "tool.execute", () =>
    callHandler(entry.handler, [params.input ?? {}, params.context ?? {}], ["execute", "run"]),
  );
}

async function dispatchProvider(state, params) {
  const entry = findHandlerEntry(state, "providers", params, ["id", "name", "provider"]);
  if (!entry) {
    return handlerNotFound("providers", params);
  }
  return dispatchThroughSecurity(state, entry, "provider.invoke", () =>
    callHandler(entry.handler, [params.request ?? {}, params.context ?? {}], ["invoke", "generate", "complete"]),
  );
}

async function dispatchHook(state, params) {
  const entry = findHandlerEntry(state, "hooks", params, ["name", "id", "hook", "kind"]);
  if (!entry) {
    return handlerNotFound("hooks", params);
  }
  return dispatchThroughSecurity(state, entry, "hook.dispatch", () =>
    callHandler(entry.handler, [params.payload ?? {}, params.context ?? {}], ["dispatch", "handle"]),
  );
}

async function dispatchCommand(state, params) {
  const entry = findHandlerEntry(state, "commands", params, ["name", "id", "command"]);
  if (!entry) {
    return handlerNotFound("commands", params);
  }
  return dispatchThroughSecurity(state, entry, "command.execute", () =>
    callHandler(entry.handler, [params.args ?? [], params.context ?? {}], ["execute", "run", "handle"]),
  );
}

async function dispatchCli(state, params) {
  const entry = findHandlerEntry(state, "clis", params, ["name", "id", "command"]);
  if (!entry) {
    return handlerNotFound("clis", params);
  }
  return dispatchThroughSecurity(state, entry, "cli.execute", () =>
    callHandler(entry.handler, [params.args ?? [], params.context ?? {}], ["execute", "run", "handle"]),
  );
}

async function dispatchGatewayMethod(state, params) {
  const entry = findHandlerEntry(state, "gatewayMethods", params, ["name", "id", "method"]);
  if (!entry) {
    return handlerNotFound("gatewayMethods", params);
  }
  return dispatchThroughSecurity(state, entry, "gateway.invoke", () =>
    callHandler(entry.handler, [params.request ?? params.payload ?? {}, params.context ?? {}], ["invoke", "execute", "handle"]),
  );
}

async function dispatchInteractive(state, params) {
  const entry = findHandlerEntry(state, "interactiveHandlers", params, ["id", "name", "namespace"]);
  if (!entry) {
    return handlerNotFound("interactiveHandlers", params);
  }
  return dispatchThroughSecurity(state, entry, "interactive.dispatch", () =>
    callHandler(entry.handler, [params.payload ?? {}, params.scope ?? {}, params.context ?? {}], ["dispatch", "handle"]),
  );
}

async function dispatchApproval(state, params) {
  const entry = findHandlerEntry(state, "approvalHandlers", params, ["id", "name", "namespace"]);
  if (!entry) {
    return handlerNotFound("approvalHandlers", params);
  }
  return dispatchThroughSecurity(state, entry, "approval.dispatch", () =>
    callHandler(entry.handler, [params.payload ?? {}, params.scope ?? {}, params.context ?? {}], ["dispatch", "handle"]),
  );
}

function configSchemas(state, params) {
  const pluginId = typeof params.pluginId === "string" ? params.pluginId.trim() : "";
  const name = typeof params.name === "string" ? params.name.trim() : "";
  const schemas = state.capabilities.configSchemas.filter((record) => {
    if (pluginId && record.pluginId !== pluginId) {
      return false;
    }
    if (name && record.name !== name && record.id !== name) {
      return false;
    }
    return true;
  });
  return {
    ok: true,
    schemas: state.redactor.sanitize(schemas),
  };
}

async function dispatchSetup(state, params) {
  const entry = findHandlerEntry(state, "setupSurfaces", params, ["id", "name", "setup"]);
  if (!entry) {
    return handlerNotFound("setupSurfaces", params);
  }
  return dispatchThroughSecurity(state, entry, "setup.status", () =>
    callHandler(
      entry.handler,
      [{ config: params.config ?? state.configSnapshot, secrets: params.secrets ?? state.secrets, context: params.context ?? {} }],
      ["status", "getStatus", "handle", "run"],
    ),
  );
}

async function dispatchDoctor(state, params) {
  const entry = findHandlerEntry(state, "doctorDiagnostics", params, ["id", "name", "doctor"]);
  if (!entry) {
    return handlerNotFound("doctorDiagnostics", params);
  }
  return dispatchThroughSecurity(state, entry, "doctor.run", () =>
    callHandler(
      entry.handler,
      [{ config: params.config ?? state.configSnapshot, secrets: params.secrets ?? state.secrets, context: params.context ?? {} }],
      ["run", "check", "diagnose", "handle"],
    ),
  );
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
    if (method === "command.execute") {
      return response(id, await dispatchCommand(state, params));
    }
    if (method === "cli.execute") {
      return response(id, await dispatchCli(state, params));
    }
    if (method === "gateway.invoke") {
      return response(id, await dispatchGatewayMethod(state, params));
    }
    if (method === "interactive.dispatch") {
      return response(id, await dispatchInteractive(state, params));
    }
    if (method === "approval.dispatch") {
      return response(id, await dispatchApproval(state, params));
    }
    if (method === "config.schema") {
      return response(id, configSchemas(state, params));
    }
    if (method === "setup.status") {
      return response(id, await dispatchSetup(state, params));
    }
    if (method === "doctor.run") {
      return response(id, await dispatchDoctor(state, params));
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
