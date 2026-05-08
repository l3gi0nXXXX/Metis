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

  assert.ok(
    registered.result.diagnostics.some((diagnostic) => diagnostic.code === "unknown_capability" && diagnostic.capability === "registerWidget"),
  );
  assert.ok(
    registered.result.diagnostics.some((diagnostic) => diagnostic.code === "runtime_placeholder" && diagnostic.facade === "media.upload"),
  );

  const health = await host.request("runtime.health");
  assert.equal(health.result.status, "ok");
  assert.equal(health.result.loadedPluginCount, 1);

  const stop = await host.request("runtime.stop");
  assert.equal(stop.result.ok, true);
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
