import assert from "node:assert/strict";
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
    registered.result.diagnostics.some((diagnostic) => diagnostic.code === "unknown_capability" && diagnostic.capability === "registerWidget"),
  );
  assert.equal(registered.result.diagnostics.some((diagnostic) => diagnostic.code === "runtime_placeholder"), false);

  const health = await host.request("runtime.health");
  assert.equal(health.result.status, "ok");
  assert.equal(health.result.loadedPluginCount, 1);

  const stop = await host.request("runtime.stop");
  assert.equal(stop.result.ok, true);
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

  const stopChannel = await host.request("channel.stop", { id: "fixture-channel" });
  assert.deepEqual(stopChannel.result, { ok: true, status: "stopped", channelId: "fixture-channel" });
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
