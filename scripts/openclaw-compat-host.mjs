#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import readline from "node:readline";
import { pathToFileURL } from "node:url";

const HOST_VERSION = "0.1.0";
const ENTRY_FALLBACKS = ["index.js", "index.mjs", "dist/index.js"];
const SENSITIVE_KEY = /(?:secret|token|password|passwd|authorization|api[_-]?key|credential)/i;

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
    configSnapshot: {},
    secrets: {},
    redactor: createRedactor(),
    runtimeVersion: HOST_VERSION,
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
  state.configSnapshot = isObject(params.config) ? params.config : {};
  state.secrets = isObject(params.secrets) ? params.secrets : {};
  state.redactor = createRedactor(state.configSnapshot, state.secrets);
  state.runtimeVersion = String(params.runtime?.version ?? params.version ?? HOST_VERSION);
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

function entryCandidates(openclawManifest, packageJson) {
  const runtime = isObject(openclawManifest.runtime) ? openclawManifest.runtime : {};
  const gatewayRuntime = isObject(openclawManifest.gatewayRuntime) ? openclawManifest.gatewayRuntime : {};
  const plugin = isObject(openclawManifest.plugin) ? openclawManifest.plugin : {};
  const pkgOpenClaw = isObject(packageJson.openclaw) ? packageJson.openclaw : {};
  const pkgPlugin = isObject(pkgOpenClaw.plugin) ? pkgOpenClaw.plugin : {};
  const pkgMetis = isObject(packageJson.metis) ? packageJson.metis : {};

  return [
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
    pkgOpenClaw.entry,
    pkgOpenClaw.pluginEntry,
    pkgPlugin.entry,
    pkgMetis.pluginEntry,
    typeof packageJson.exports === "string" ? packageJson.exports : "",
    packageJson.module,
    packageJson.main,
    ...ENTRY_FALLBACKS,
  ];
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
  return firstString(spec.name, spec.id, spec.command, spec.path, spec.method, fallback);
}

function addCapability(state, collection, pluginId, spec, extra = {}) {
  const sanitizedSpec = state.redactor.sanitize(spec);
  state.capabilities[collection].push({
    pluginId,
    name: capabilityName(spec, extra.name),
    id: isObject(spec) ? firstString(spec.id, spec.name) : "",
    path: isObject(spec) ? firstString(spec.path) : "",
    command: isObject(spec) ? firstString(spec.command, spec.name) : "",
    method: isObject(spec) ? firstString(spec.method) : "",
    kind: isObject(spec) ? firstString(spec.kind, spec.type) : "",
    spec: sanitizedSpec,
    ...extra,
  });
}

function addDiagnostic(state, diagnostic) {
  state.diagnostics.push(state.redactor.sanitize(diagnostic));
}

function placeholder(state, pluginId, facade) {
  return async (...args) => {
    addDiagnostic(state, {
      code: "runtime_placeholder",
      pluginId,
      facade,
      args,
      message: `${facade} is not implemented in compatibility host`,
    });
    return { ok: false, status: "not_implemented", facade };
  };
}

function buildRuntimeFacade(state, pluginId) {
  return {
    version: state.runtimeVersion,
    config: state.redactor.sanitize(state.configSnapshot),
    secrets: {
      get: async (name) => resolveSecret(state, pluginId, name),
      resolve: async (name) => resolveSecret(state, pluginId, name),
    },
    logger: buildLogger(state, pluginId),
    media: {
      upload: placeholder(state, pluginId, "media.upload"),
      download: placeholder(state, pluginId, "media.download"),
      resolve: placeholder(state, pluginId, "media.resolve"),
    },
    fetch: placeholder(state, pluginId, "fetch"),
    reply: {
      send: placeholder(state, pluginId, "reply.send"),
    },
    conversation: {
      get: placeholder(state, pluginId, "conversation.get"),
      list: placeholder(state, pluginId, "conversation.list"),
    },
    thread: {
      get: placeholder(state, pluginId, "thread.get"),
      list: placeholder(state, pluginId, "thread.list"),
    },
    process: {
      spawn: placeholder(state, pluginId, "process.spawn"),
      env: placeholder(state, pluginId, "process.env"),
    },
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

async function resolveSecret(state, pluginId, name) {
  const key = String(name ?? "");
  const value = state.secrets[key] ?? "";
  addDiagnostic(state, {
    code: "secret_resolved",
    pluginId,
    name: key,
    value: value ? "[REDACTED]" : "",
    found: Boolean(value),
  });
  return value;
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
    registerTool: (spec, handler) => addCapability(state, "tools", pluginId, spec, { handlerRegistered: typeof handler === "function" }),
    registerProvider: (spec) => addCapability(state, "providers", pluginId, spec),
    registerChannel: (spec) => addCapability(state, "channels", pluginId, spec),
    registerHook: (kindOrSpec, handler) => {
      const spec = typeof kindOrSpec === "string" ? { name: kindOrSpec } : kindOrSpec;
      addCapability(state, "hooks", pluginId, spec, { handlerRegistered: typeof handler === "function" });
    },
    registerCommand: (spec, handler) => addCapability(state, "commands", pluginId, spec, { handlerRegistered: typeof handler === "function" }),
    registerCli: (spec, handler) => addCapability(state, "clis", pluginId, spec, { handlerRegistered: typeof handler === "function" }),
    registerHttpRoute: (spec, handler) => addCapability(state, "httpRoutes", pluginId, spec, { handlerRegistered: typeof handler === "function" }),
    registerHttpHandler: (spec, handler) => addCapability(state, "httpHandlers", pluginId, spec, { handlerRegistered: typeof handler === "function" }),
    registerInteractiveHandler: (spec, handler) =>
      addCapability(state, "interactiveHandlers", pluginId, spec, { handlerRegistered: typeof handler === "function" }),
    registerApprovalHandler: (spec, handler) =>
      addCapability(state, "approvalHandlers", pluginId, spec, { handlerRegistered: typeof handler === "function" }),
    registerMemoryEmbeddingProvider: (spec) => addCapability(state, "memoryEmbeddingProviders", pluginId, spec),
    registerGatewayMethod: (spec, handler) => addCapability(state, "gatewayMethods", pluginId, spec, { handlerRegistered: typeof handler === "function" }),
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
    const module = await import(pathToFileURL(plugin.entry).href);
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
    config: state.redactor.sanitize(state.configSnapshot),
    diagnostics: state.redactor.sanitize(state.diagnostics),
    ...extra,
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
