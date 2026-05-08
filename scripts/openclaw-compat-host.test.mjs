import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import { spawn, spawnSync } from "node:child_process";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const hostScript = path.join(__dirname, "openclaw-compat-host.mjs");
const fixtureRoot = path.join(__dirname, "fixtures", "openclaw-compat-host");
const rawRegisterRoot = path.join(fixtureRoot, "raw-register");
const missingEntryRoot = path.join(fixtureRoot, "missing-entry");
const extensionsArrayRoot = path.join(fixtureRoot, "openclaw-extensions-array");
const exportsDefaultRoot = path.join(fixtureRoot, "exports-dot-default");
const exportsImportRoot = path.join(fixtureRoot, "exports-dot-import");
const tsDistPriorityRoot = path.join(fixtureRoot, "ts-dist-priority");
const tsEntryOnlyRoot = path.join(fixtureRoot, "ts-entry-only");

function once(request) {
  const child = spawnSync(process.execPath, [hostScript, "--once"], {
    input: `${JSON.stringify(request)}\n`,
    encoding: "utf8",
  });
  assert.equal(child.status, 0, child.stderr);
  const lines = child.stdout.trim().split(/\n+/).filter(Boolean);
  assert.equal(lines.length, 1, child.stdout);
  return JSON.parse(lines[0]);
}

function startHost(t) {
  const child = spawn(process.execPath, [hostScript], {
    stdio: ["pipe", "pipe", "pipe"],
  });
  child.stdin.setDefaultEncoding("utf8");
  child.stdout.setEncoding("utf8");
  child.stderr.setEncoding("utf8");

  let nextId = 1;
  let stdoutBuffer = "";
  let stderr = "";
  const pending = new Map();

  child.stderr.on("data", (chunk) => {
    stderr += chunk;
  });

  child.stdout.on("data", (chunk) => {
    stdoutBuffer += chunk;
    while (stdoutBuffer.includes("\n")) {
      const index = stdoutBuffer.indexOf("\n");
      const line = stdoutBuffer.slice(0, index).trim();
      stdoutBuffer = stdoutBuffer.slice(index + 1);
      if (!line) {
        continue;
      }
      const response = JSON.parse(line);
      const waiter = pending.get(response.id);
      if (waiter) {
        pending.delete(response.id);
        waiter.resolve(response);
      }
    }
  });

  t.after(() => {
    for (const waiter of pending.values()) {
      waiter.reject(new Error(`host stopped before response; stderr=${stderr}`));
    }
    pending.clear();
    if (!child.killed) {
      child.kill();
    }
  });

  return {
    request(method, params = {}) {
      const id = nextId;
      nextId += 1;
      const payload = { jsonrpc: "2.0", id, method, params };
      const promise = new Promise((resolve, reject) => {
        const timeout = setTimeout(() => {
          pending.delete(id);
          reject(new Error(`timeout waiting for ${method}; stderr=${stderr}`));
        }, 5000);
        pending.set(id, {
          resolve: (response) => {
            clearTimeout(timeout);
            resolve(response);
          },
          reject,
        });
      });
      child.stdin.write(`${JSON.stringify(payload)}\n`);
      return promise;
    },
    child,
  };
}

function byName(items, name) {
  return items.find((item) => item.name === name || item.id === name || item.path === name || item.command === name);
}

function makeToolFixture(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "metis-openclaw-gap08-tools-"));
  fs.writeFileSync(
    path.join(root, "package.json"),
    JSON.stringify({ name: "gap08-tool-fixture", type: "module", main: "index.mjs" }),
  );
  fs.writeFileSync(
    path.join(root, "index.mjs"),
    `
export default async function register(api) {
  for (const name of ["firecrawl.search", "tavily.search", "exa.search", "clawmate.plan"]) {
    api.registerTool(
      {
        name,
        inputSchema: { type: "object", required: ["query"], properties: { query: { type: "string" } } },
        timeoutMs: 9000,
        permissions: ["network:https://api.example.invalid"],
        resultShape: { ok: "ok", content: "content", error: "error" },
      },
      async (input, context) => ({ ok: true, content: name + ":" + input.query, context })
    );
  }
}
`,
  );
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  return root;
}

function makeGap03Fixture(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "metis-openclaw-gap03-host-"));
  fs.writeFileSync(
    path.join(root, "package.json"),
    JSON.stringify({ name: "gap03-host-fixture", type: "module", main: "index.mjs" }),
    "utf8",
  );
  fs.writeFileSync(
    path.join(root, "index.mjs"),
    `
export default async function register(api) {
  api.registerWebSearchProvider({ id: "fixture-web-search", kind: "web-search" }, {
    invoke: async (request) => ({ ok: true, provider: "fixture-web-search", query: request.query })
  });
  api.registerMessageHook("message.created", async (payload) => ({ ok: true, hook: "message.created", text: payload.text }));
  api.registerCli({ name: "fixture-cli-dispatch" }, async (args) => ({ ok: true, args }));
  api.registerGatewayMethod({ name: "fixture.gateway.dispatch" }, async (request) => ({ ok: true, request }));
  api.registerTool({ name: "fixture.crash" }, async () => {
    throw new Error("boom GAP03_SECRET_TOKEN");
  });
  api.registerTool({ name: "fixture.timeout" }, async () => {
    await new Promise((resolve) => setTimeout(resolve, 100));
    return { ok: true };
  });
  api.registerMystery({ id: "fixture-mystery", token: "GAP03_SECRET_TOKEN" });
}
`,
    "utf8",
  );
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  return root;
}

function makeConfigDoctorFixture(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "metis-openclaw-config-doctor-"));
  fs.writeFileSync(
    path.join(root, "package.json"),
    JSON.stringify({ name: "gap08-config-doctor", type: "module", main: "index.mjs" }),
    "utf8",
  );
  fs.writeFileSync(
    path.join(root, "openclaw.plugin.json"),
    JSON.stringify({
      id: "gap08-config-doctor",
      configSchema: {
        type: "object",
        required: ["botToken", "endpoint"],
        properties: {
          botToken: { type: "string", title: "Bot token", format: "password", default: "manifest-secret-token" },
          endpoint: { type: "string", title: "Endpoint", default: "https://api.example.invalid" },
        },
      },
      setupHints: ["Create the upstream OpenClaw bot token."],
      installHints: ["Restart the plugin after saving config."],
    }),
    "utf8",
  );
  fs.writeFileSync(
    path.join(root, "index.mjs"),
    `
export default async function register(api) {
  api.registerConfigSchema({
    name: "runtime-config",
    schema: {
      type: "object",
      properties: {
        runtimePassword: { type: "string", format: "password", default: "runtime-secret-password" }
      }
    }
  });
  api.registerSetup(
    {
      name: "primary-setup",
      title: "Primary setup",
      hints: ["Paste the token from OpenClaw setup."]
    },
    async ({ config }) => ({
      ok: true,
      configured: Boolean(config?.botToken),
      hints: ["Paste the token from OpenClaw setup."]
    })
  );
  api.registerDoctor(
    {
      name: "primary-doctor",
      title: "Primary doctor"
    },
    async ({ config }) => ({
      ok: false,
      status: config?.botToken ? "ready" : "setup-required",
      diagnostics: {
        authorization: "Bearer doctor-secret-token",
        message: "missing bot token"
      }
    })
  );
}
`,
    "utf8",
  );
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  return root;
}

test("persistent host loads raw register(api) plugin and captures OpenClaw capabilities", async (t) => {
  const host = startHost(t);
  const load = await host.request("plugin.load", {
    roots: [rawRegisterRoot],
    runtime: { version: "test-runtime" },
    config: { publicFlag: true },
    secrets: { OPENCLAW_TOKEN: "super-secret-token" },
  });

  assert.equal(load.result.ok, true);
  assert.equal(load.result.loadedPluginCount, 1);

  const registered = await host.request("plugin.registeredCapabilities");
  assert.equal(registered.result.ok, true);

  const capabilities = registered.result.capabilities;
  assert.ok(byName(capabilities.tools, "fixture.tool"));
  assert.ok(byName(capabilities.providers, "fixture-provider"));
  assert.ok(byName(capabilities.channels, "fixture-channel"));
  assert.ok(byName(capabilities.hooks, "message.received"));
  assert.ok(byName(capabilities.commands, "fixture-command"));
  assert.ok(byName(capabilities.clis, "fixture-cli"));
  assert.ok(byName(capabilities.httpRoutes, "/fixture"));
  assert.ok(byName(capabilities.httpHandlers, "fixture-http-handler"));
  assert.ok(byName(capabilities.interactiveHandlers, "fixture-interactive"));
  assert.ok(byName(capabilities.approvalHandlers, "fixture-approval"));
  assert.ok(byName(capabilities.memoryEmbeddingProviders, "fixture-memory"));
  assert.ok(byName(capabilities.gatewayMethods, "fixture.gateway"));
  assert.ok(byName(capabilities.services, "fixture-service"));

  const registries = registered.result.gatewayRegistries;
  assert.ok(byName(registries.tools, "fixture.tool"));
  assert.ok(byName(registries.providers, "fixture-provider"));
  assert.ok(byName(registries.channels, "fixture-channel"));
  assert.ok(byName(registries.hooks, "message.received"));
  assert.ok(byName(registries.httpRoutes, "/fixture"));
  assert.equal(byName(registries.tools, "fixture.tool").dispatch.method, "tool.execute");
  assert.equal(byName(registries.channels, "fixture-channel").dispatch.method, "channel.start");
  assert.equal(byName(registries.httpRoutes, "/fixture").dispatch.method, "http.dispatch");

  assert.ok(
    registered.result.diagnostics.some(
      (diagnostic) =>
        diagnostic.code === "unknown_capability" &&
        diagnostic.capability === "registerWidget" &&
        diagnostic.releaseBlocker === true,
    ),
  );
  assert.equal(registered.result.diagnostics.some((diagnostic) => diagnostic.code === "runtime_placeholder"), false);

  const health = await host.request("runtime.health");
  assert.equal(health.result.status, "ok");
  assert.equal(health.result.loadedPluginCount, 1);

  const stop = await host.request("runtime.stop");
  assert.equal(stop.result.ok, true);
});

test("persistent host captures OpenClaw SDK register aliases without converting plugin manifests", async (t) => {
  const host = startHost(t);
  const root = makeGap03Fixture(t);
  const load = await host.request("plugin.load", {
    roots: [root],
    runtime: { version: "test-runtime" },
    secrets: { GAP03_SECRET_TOKEN: "GAP03_SECRET_TOKEN" },
  });

  assert.equal(load.result.ok, true);
  assert.equal(load.result.loadedPluginCount, 1);

  const registered = await host.request("plugin.registeredCapabilities");
  assert.ok(byName(registered.result.capabilities.providers, "fixture-web-search"));
  assert.ok(byName(registered.result.capabilities.hooks, "message.created"));
  assert.equal(
    registered.result.diagnostics.some((diagnostic) => diagnostic.capability === "registerWebSearchProvider"),
    false,
  );
  assert.equal(
    registered.result.diagnostics.some((diagnostic) => diagnostic.capability === "registerMessageHook"),
    false,
  );

  const serialized = JSON.stringify(registered);
  assert.equal(serialized.includes("GAP03_SECRET_TOKEN"), false);
});

test("persistent host exposes raw OpenClaw config schema, setup, and doctor surfaces without Metis manifest", async (t) => {
  const host = startHost(t);
  const root = makeConfigDoctorFixture(t);
  assert.equal(fs.existsSync(path.join(root, "metis.plugin.json")), false);

  const load = await host.request("plugin.load", {
    roots: [root],
    config: { botToken: "config-secret-token", endpoint: "https://api.example.invalid" },
    secrets: { botToken: "store-secret-token" },
  });

  assert.equal(load.result.ok, true);
  assert.equal(load.result.loadedPluginCount, 1);
  assert.equal(JSON.stringify(load.result).includes("manifest-secret-token"), false);
  assert.equal(JSON.stringify(load.result).includes("runtime-secret-password"), false);
  assert.equal(JSON.stringify(load.result).includes("config-secret-token"), false);
  assert.equal(JSON.stringify(load.result).includes("store-secret-token"), false);

  const registered = await host.request("plugin.registeredCapabilities");
  assert.ok(byName(registered.result.capabilities.configSchemas, "gap08-config-doctor"));
  assert.ok(byName(registered.result.capabilities.configSchemas, "runtime-config"));
  assert.ok(byName(registered.result.capabilities.setupSurfaces, "primary-setup"));
  assert.ok(byName(registered.result.capabilities.doctorDiagnostics, "primary-doctor"));

  const configSchemas = await host.request("config.schema", { pluginId: "gap08-config-doctor" });
  assert.equal(configSchemas.result.ok, true);
  assert.equal(configSchemas.result.schemas.length, 2);
  assert.equal(JSON.stringify(configSchemas.result).includes("manifest-secret-token"), false);
  assert.equal(JSON.stringify(configSchemas.result).includes("runtime-secret-password"), false);

  const setup = await host.request("setup.status", { name: "primary-setup", config: { botToken: "configured-token" } });
  assert.deepEqual(setup.result, {
    ok: true,
    configured: true,
    hints: ["Paste the token from OpenClaw setup."],
  });

  const doctor = await host.request("doctor.run", { name: "primary-doctor", config: {} });
  assert.equal(doctor.result.ok, false);
  assert.equal(doctor.result.status, "setup-required");
  assert.equal(JSON.stringify(doctor.result).includes("doctor-secret-token"), false);
  assert.equal(doctor.result.diagnostics.authorization, "[REDACTED]");
});

test("discovers OpenClaw package entries from extensions, exports, dist, and TS source fallbacks", () => {
  const response = once({
    jsonrpc: "2.0",
    id: 10,
    method: "plugin.discover",
    params: { roots: [extensionsArrayRoot, exportsDefaultRoot, exportsImportRoot, tsDistPriorityRoot, tsEntryOnlyRoot] },
  });

  assert.equal(response.result.ok, true);
  const byRoot = new Map(response.result.plugins.map((plugin) => [plugin.root, plugin]));
  assert.equal(byRoot.get(extensionsArrayRoot).entry.endsWith("extension.mjs"), true);
  assert.equal(byRoot.get(exportsDefaultRoot).entry.endsWith("default-entry.mjs"), true);
  assert.equal(byRoot.get(exportsImportRoot).entry.endsWith("import-entry.mjs"), true);
  assert.equal(byRoot.get(tsDistPriorityRoot).entry.endsWith(path.join("dist", "index.js")), true);
  assert.equal(byRoot.get(tsEntryOnlyRoot).entry.endsWith(path.join("src", "index.ts")), true);
});

test("TS-only entries fail with deterministic loader diagnostic when no controlled loader is available", () => {
  const response = once({
    jsonrpc: "2.0",
    id: 11,
    method: "plugin.load",
    params: { roots: [tsEntryOnlyRoot], runtime: { version: "test-runtime" } },
  });

  assert.equal(response.result.ok, true);
  assert.equal(response.result.loadedPluginCount, 0);
  assert.ok(
    response.result.diagnostics.some(
      (diagnostic) => diagnostic.code === "ts_entry_loader_unavailable" && diagnostic.entry.endsWith(path.join("src", "index.ts")),
    ),
  );
  assert.equal(response.result.diagnostics.some((diagnostic) => diagnostic.code === "plugin_load_error"), false);
});

test("persistent host dispatches registered channel, HTTP, tool, provider, and hook handlers", async (t) => {
  const host = startHost(t);
  const load = await host.request("plugin.load", {
    roots: [rawRegisterRoot],
    runtime: { version: "test-runtime" },
    secrets: { OPENCLAW_TOKEN: "super-secret-token" },
    permissions: {
      media: true,
      reply: true,
      conversation: true,
      thread: true,
      process: false,
    },
  });

  assert.equal(load.result.ok, true);
  assert.equal(load.result.loadedPluginCount, 1);

  const start = await host.request("channel.start", { id: "fixture-channel", context: { accountId: "acct-1" } });
  assert.deepEqual(start.result, { ok: true, status: "started", channelId: "fixture-channel", accountId: "acct-1" });

  const health = await host.request("channel.health", { id: "fixture-channel" });
  assert.deepEqual(health.result, { ok: true, status: "healthy", channelId: "fixture-channel" });

  const inbound = await host.request("channel.pullInbound", { id: "fixture-channel", limit: 1 });
  assert.deepEqual(inbound.result, {
    ok: true,
    messages: [{ id: "inbound-1", text: "fixture inbound", channelId: "fixture-channel" }],
  });

  const sent = await host.request("channel.send", { id: "fixture-channel", message: { text: "hello dispatch" } });
  assert.deepEqual(sent.result, { ok: true, sent: true, text: "hello dispatch" });

  const http = await host.request("http.dispatch", { method: "GET", path: "/fixture", body: "ping" });
  assert.deepEqual(http.result, { status: 200, body: "GET /fixture ping" });

  const tool = await host.request("tool.execute", { name: "fixture.tool", input: { value: 7 } });
  assert.deepEqual(tool.result, { ok: true, tool: "fixture.tool", input: { value: 7 } });

  const provider = await host.request("provider.invoke", { id: "fixture-provider", request: { prompt: "hi" } });
  assert.deepEqual(provider.result, { ok: true, provider: "fixture-provider", prompt: "hi" });

  const hook = await host.request("hook.dispatch", { name: "message.received", payload: { text: "hook me" } });
  assert.deepEqual(hook.result, { ok: true, hook: "message.received", text: "hook me" });

  const command = await host.request("command.execute", { name: "fixture-command", args: ["doctor"], context: { channel: "generic" } });
  assert.deepEqual(command.result, { ok: true });

  const cli = await host.request("cli.execute", { name: "fixture-cli", args: ["doctor"], context: { channel: "generic" } });
  assert.deepEqual(cli.result, 0);

  const gateway = await host.request("gateway.invoke", { name: "fixture.gateway", request: { value: 7 } });
  assert.deepEqual(gateway.result, { ok: true });

  const interactive = await host.request("interactive.dispatch", {
    id: "fixture-interactive",
    payload: { data: "clicked" },
    scope: { channelId: "generic", accountId: "acct-1", peerId: "peer-1", threadId: "thread-1" },
  });
  assert.deepEqual(interactive.result, { ok: true });

  const approval = await host.request("approval.dispatch", {
    id: "fixture-approval",
    payload: { decision: "allow-once" },
    scope: { channelId: "generic", accountId: "acct-1", peerId: "peer-1", threadId: "thread-1" },
  });
  assert.deepEqual(approval.result, { ok: true });

  const stopChannel = await host.request("channel.stop", { id: "fixture-channel" });
  assert.deepEqual(stopChannel.result, { ok: true, status: "stopped", channelId: "fixture-channel" });
});

test("persistent host dispatches alias handlers and preserves OpenClaw result shapes", async (t) => {
  const host = startHost(t);
  const root = makeGap03Fixture(t);
  const load = await host.request("plugin.load", { roots: [root], runtime: { version: "test-runtime" } });
  assert.equal(load.result.loadedPluginCount, 1);

  const provider = await host.request("provider.invoke", { id: "fixture-web-search", request: { query: "metis" } });
  assert.deepEqual(provider.result, { ok: true, provider: "fixture-web-search", query: "metis" });

  const hook = await host.request("hook.dispatch", { name: "message.created", payload: { text: "hello" } });
  assert.deepEqual(hook.result, { ok: true, hook: "message.created", text: "hello" });

  const cli = await host.request("cli.execute", { name: "fixture-cli-dispatch", args: ["doctor"] });
  assert.deepEqual(cli.result, { ok: true, args: ["doctor"] });

  const gateway = await host.request("gateway.invoke", { name: "fixture.gateway.dispatch", request: { value: 11 } });
  assert.deepEqual(gateway.result, { ok: true, request: { value: 11 } });
});

test("persistent host returns redacted JS error evidence for crashed and timed-out handlers", async (t) => {
  const host = startHost(t);
  const root = makeGap03Fixture(t);
  const load = await host.request("plugin.load", {
    roots: [root],
    runtime: { version: "test-runtime" },
    secrets: { GAP03_SECRET_TOKEN: "GAP03_SECRET_TOKEN" },
    handlerTimeoutMs: 10,
  });
  assert.equal(load.result.loadedPluginCount, 1);

  const crashed = await host.request("tool.execute", { name: "fixture.crash" });
  assert.equal(crashed.result.allowed, false);
  assert.equal(crashed.result.code, "handler_crash");
  assert.equal(JSON.stringify(crashed).includes("GAP03_SECRET_TOKEN"), false);
  assert.equal(JSON.stringify(crashed).includes("[REDACTED]"), true);

  const timedOut = await host.request("tool.execute", { name: "fixture.timeout" });
  assert.equal(timedOut.result.allowed, false);
  assert.equal(timedOut.result.code, "handler_timeout");
  assert.equal(timedOut.result.diagnostics.timeoutMs, 10);
});

test("persistent host dispatches OpenClaw search tool fixtures through tool bridge shape", async (t) => {
  const host = startHost(t);
  const root = makeToolFixture(t);
  const load = await host.request("plugin.load", {
    roots: [root],
    runtime: { version: "test-runtime" },
    permissions: { fetch: true },
  });

  assert.equal(load.result.ok, true);
  assert.equal(load.result.loadedPluginCount, 1);

  for (const name of ["firecrawl.search", "tavily.search", "exa.search", "clawmate.plan"]) {
    const dispatched = await host.request("tool.execute", {
      name,
      input: { query: "metis" },
      context: { channelId: "generic", accountId: "acct-1", peerId: "peer-1", threadId: "thread-1" },
    });
    assert.deepEqual(dispatched.result, {
      ok: true,
      content: `${name}:metis`,
      context: { channelId: "generic", accountId: "acct-1", peerId: "peer-1", threadId: "thread-1" },
    });
  }
});

test("persistent host start gate blocks denied manifest permissions before plugin code runs", async (t) => {
  const host = startHost(t);
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "metis-openclaw-start-gate-"));
  const marker = path.join(root, "invoked.txt");
  fs.writeFileSync(
    path.join(root, "package.json"),
    JSON.stringify({ name: "start-gate-fixture", type: "module", main: "index.mjs" }),
    "utf8",
  );
  fs.writeFileSync(
    path.join(root, "openclaw.plugin.json"),
    JSON.stringify({
      id: "start-gate-fixture",
      permissions: { network: ["https://denied.example"] },
    }),
    "utf8",
  );
  fs.writeFileSync(
    path.join(root, "index.mjs"),
    `
import fs from "node:fs";
export default async function register(api) {
  fs.writeFileSync(${JSON.stringify(marker)}, "invoked");
  api.registerTool({ name: "should.not.load" }, async () => ({ ok: true }));
}
`,
    "utf8",
  );
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));

  const load = await host.request("plugin.load", {
    roots: [root],
    security: {
      enabled: true,
      grants: { network: [] },
    },
  });

  assert.equal(load.result.loadedPluginCount, 0);
  assert.equal(fs.existsSync(marker), false);
  assert.ok(load.result.diagnostics.some((diagnostic) => diagnostic.code === "security_start_denied"));
});

test("persistent host handler dispatch gate blocks denied capability permissions before invoking handler", async (t) => {
  const host = startHost(t);
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "metis-openclaw-handler-gate-"));
  const marker = path.join(root, "handler-invoked.txt");
  fs.writeFileSync(
    path.join(root, "package.json"),
    JSON.stringify({ name: "handler-gate-fixture", type: "module", main: "index.mjs" }),
    "utf8",
  );
  fs.writeFileSync(
    path.join(root, "index.mjs"),
    `
import fs from "node:fs";
export default async function register(api) {
  api.registerTool(
    {
      name: "network.denied.tool",
      permissions: ["network:https://evil.example"],
    },
    async () => {
      fs.writeFileSync(${JSON.stringify(marker)}, "invoked");
      return { ok: true };
    }
  );
}
`,
    "utf8",
  );
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));

  const load = await host.request("plugin.load", {
    roots: [root],
    security: {
      enabled: true,
      grants: {
        network: [{ resource: "api.example.com", needsApproval: false }],
      },
    },
  });

  assert.equal(load.result.loadedPluginCount, 0);
  assert.ok(load.result.diagnostics.some((diagnostic) => diagnostic.code === "security_start_denied"));

  const dispatched = await host.request("tool.execute", { name: "network.denied.tool", input: { query: "metis" } });
  assert.equal(dispatched.result.status, "handler_not_found");
  assert.equal(fs.existsSync(marker), false);
});

test("--once plugin.discover reports missing entry diagnostics without executing plugins", () => {
  const response = once({
    jsonrpc: "2.0",
    id: 1,
    method: "plugin.discover",
    params: { roots: [rawRegisterRoot, missingEntryRoot] },
  });

  assert.equal(response.result.ok, true);
  assert.equal(response.result.plugins.length, 2);
  assert.equal(response.result.plugins.find((plugin) => plugin.root === rawRegisterRoot).entry.endsWith("index.mjs"), true);
  assert.equal(response.result.plugins.find((plugin) => plugin.root === missingEntryRoot).entry, "");
  assert.ok(response.result.diagnostics.some((diagnostic) => diagnostic.code === "entry_not_found"));
});

test("secret values are redacted from load responses and diagnostics", () => {
  const response = once({
    jsonrpc: "2.0",
    id: 2,
    method: "plugin.load",
    params: {
      roots: [rawRegisterRoot],
      runtime: { version: "test-runtime" },
      config: { OPENCLAW_TOKEN: "config-secret-value" },
      secrets: { OPENCLAW_TOKEN: "super-secret-token" },
    },
  });

  const serialized = JSON.stringify(response);
  assert.equal(response.result.ok, true);
  assert.equal(serialized.includes("super-secret-token"), false);
  assert.equal(serialized.includes("config-secret-value"), false);
  assert.ok(serialized.includes("[REDACTED]"));
});
