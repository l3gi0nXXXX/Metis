import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import { createInstallPlan, preparePluginStage } from "./openclaw-compat-installer.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const hostScript = path.join(__dirname, "openclaw-compat-host.mjs");
const fixtureRoot = path.join(__dirname, "fixtures", "openclaw-compat-host");
const realPluginRoot = path.join(fixtureRoot, "real-plugin-smoke");
const workspacePluginRoot = path.join(fixtureRoot, "workspace-root", "packages", "plugin");

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

test("real-package smoke loads raw OpenClaw package entry without Metis manifest or wrapper", () => {
  assert.equal(fs.existsSync(path.join(realPluginRoot, "metis.plugin.json")), false);

  const response = once({
    jsonrpc: "2.0",
    id: 20,
    method: "plugin.load",
    params: { roots: [realPluginRoot], runtime: { version: "2026.3.23" } },
  });

  assert.equal(response.result.ok, true);
  assert.equal(response.result.loadedPluginCount, 1);
  assert.equal(response.result.plugins[0].entry.endsWith(path.join("dist", "index.js")), true);
  assert.ok(response.result.capabilities.tools.some((tool) => tool.name === "real.fixture.tool"));
  assert.equal(response.result.diagnostics.some((diagnostic) => diagnostic.code === "runtime_placeholder"), false);
});

test("installer exposes deterministic staging plan for raw workspace package dependencies", () => {
  const plan = createInstallPlan(workspacePluginRoot, {
    stageRoot: path.join(fixtureRoot, ".tmp-stage"),
    openclawPackageRoot: path.join(fixtureRoot, "fake-openclaw-sdk"),
  });

  assert.equal(plan.ok, true);
  assert.equal(plan.packageName, "@fixture/workspace-plugin");
  assert.equal(plan.requiresInstall, false);
  assert.ok(plan.workspaceLinks.some((link) => link.name === "@fixture/shared" && link.target.endsWith(path.join("packages", "shared"))));
  assert.ok(plan.workspaceLinks.some((link) => link.name === "openclaw" && link.target.endsWith("fake-openclaw-sdk")));
});

test("installer stages workspace links without writing node_modules into plugin source", () => {
  const stageRoot = path.join(fixtureRoot, ".tmp-stage");
  fs.rmSync(stageRoot, { recursive: true, force: true });

  const staged = preparePluginStage(workspacePluginRoot, {
    stageRoot,
    openclawPackageRoot: path.join(fixtureRoot, "fake-openclaw-sdk"),
  });

  assert.equal(staged.ok, true);
  assert.equal(fs.existsSync(path.join(workspacePluginRoot, "node_modules")), false);
  assert.equal(fs.existsSync(path.join(staged.stageRoot, "node_modules", "@fixture", "shared")), true);
  assert.equal(fs.lstatSync(path.join(staged.stageRoot, "node_modules", "@fixture", "shared")).isSymbolicLink(), true);
  assert.equal(fs.existsSync(path.join(staged.stageRoot, "node_modules", "openclaw")), true);

  fs.rmSync(stageRoot, { recursive: true, force: true });
});
