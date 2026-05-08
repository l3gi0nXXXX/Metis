import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import { createInstallPlan, preparePluginStage } from "./openclaw-compat-installer.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const hostScript = path.join(__dirname, "openclaw-compat-host.mjs");
const smokeScript = path.join(__dirname, "openclaw-compat-real-plugin-smoke.mjs");
const fixtureRoot = path.join(__dirname, "fixtures", "openclaw-compat-host");
const realPluginRoot = path.join(fixtureRoot, "real-plugin-smoke");
const workspacePluginRoot = path.join(fixtureRoot, "workspace-root", "packages", "plugin");
const tsEntryOnlyRoot = path.join(fixtureRoot, "ts-entry-only");
const sdkRequiredRoot = path.join(fixtureRoot, "sdk-required");

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

function runSmoke(args) {
  const child = spawnSync(process.execPath, [smokeScript, ...args], {
    encoding: "utf8",
  });
  assert.equal(child.status, 0, child.stderr);
  return JSON.parse(child.stdout);
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

test("installer detects package manager from lockfiles without writing plugin source", () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "metis-openclaw-pm-"));
  try {
    fs.writeFileSync(path.join(tmp, "package.json"), JSON.stringify({ name: "pm-fixture", version: "1.0.0" }), "utf8");
    fs.writeFileSync(path.join(tmp, "pnpm-lock.yaml"), "lockfileVersion: '9.0'\n", "utf8");

    const plan = createInstallPlan(tmp, { stageRoot: path.join(tmp, "stage") });

    assert.deepEqual(plan.packageManager, { name: "pnpm", reason: "pnpm-lock.yaml" });
    assert.deepEqual(plan.installCommand, ["pnpm", "install", "--frozen-lockfile", "--ignore-scripts"]);
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
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

test("installer source gate blocks unallowlisted plugin staging before copying files", () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "metis-openclaw-install-gate-"));
  try {
    fs.writeFileSync(path.join(tmp, "package.json"), JSON.stringify({ name: "install-gate", version: "1.0.0" }), "utf8");
    const stageRoot = path.join(tmp, "stage");
    const source = {
      url: "https://github.com/openclaw/install-gate.git",
      ref: "refs/heads/main",
      hash: "sha256:bad",
    };
    const sourceAllowlist = [
      {
        url: "https://github.com/openclaw/install-gate.git",
        ref: "refs/tags/v1.0.0",
        hash: "sha256:good",
      },
    ];

    const plan = createInstallPlan(tmp, { stageRoot, source, sourceAllowlist });

    assert.equal(plan.ok, false);
    assert.equal(plan.security.stage, "install");
    assert.equal(plan.security.code, "source_ref_mismatch");
    assert.throws(() => preparePluginStage(tmp, { stageRoot, source, sourceAllowlist }), /source_ref_mismatch/);
    assert.equal(fs.existsSync(path.join(stageRoot, "package", "package.json")), false);
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

test("real smoke runner stages raw package, loads register(api), and maps matrix smoke status", () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "metis-openclaw-smoke-"));
  try {
    const matrixIn = path.join(tmp, "matrix-in.json");
    const matrixOut = path.join(tmp, "matrix-out.json");
    fs.writeFileSync(
      matrixIn,
      JSON.stringify({
        plugins: [
          {
            plugin_id: "real-fixture",
            source_root: realPluginRoot,
            real_plugin_smoke_status: "not-run",
          },
        ],
      }),
      "utf8",
    );

    const result = runSmoke([
      "--plugin",
      `real-fixture:${realPluginRoot}`,
      "--stage-root",
      tmp,
      "--matrix-in",
      matrixIn,
      "--matrix-out",
      matrixOut,
    ]);

    assert.equal(result.status, "DONE");
    assert.equal(result.results[0].pluginId, "real-fixture");
    assert.equal(result.results[0].real_plugin_smoke_status, "passed");
    assert.equal(result.results[0].loadedPluginCount, 1);
    assert.equal(result.results[0].stagedPluginRoot.startsWith(tmp), true);
    assert.notEqual(result.results[0].stagedPluginRoot, realPluginRoot);
    assert.equal(fs.existsSync(path.join(realPluginRoot, "metis.plugin.json")), false);
    assert.equal(fs.existsSync(path.join(realPluginRoot, "node_modules")), false);

    const mapped = JSON.parse(fs.readFileSync(matrixOut, "utf8"));
    assert.equal(mapped.plugins[0].real_plugin_smoke_status, "passed");
    assert.equal(mapped.plugins[0].real_plugin_smoke_diagnostic.pluginId, "real-fixture");
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

test("real smoke runner returns deterministic TS-only blocker without marking passed", () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "metis-openclaw-smoke-"));
  try {
    const result = runSmoke(["--plugin", `ts-only:${tsEntryOnlyRoot}`, "--stage-root", tmp]);

    assert.equal(result.status, "BLOCKED");
    assert.equal(result.results[0].real_plugin_smoke_status, "blocked");
    assert.equal(result.results[0].blockers.some((blocker) => blocker.code === "ts_entry_loader_unavailable"), true);
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

test("real smoke runner returns deterministic SDK incompatibility blocker", () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "metis-openclaw-smoke-"));
  try {
    const result = runSmoke(["--plugin", `sdk-required:${sdkRequiredRoot}`, "--stage-root", tmp]);

    assert.equal(result.status, "BLOCKED");
    assert.equal(result.results[0].real_plugin_smoke_status, "blocked");
    assert.equal(result.results[0].blockers.some((blocker) => blocker.code === "openclaw_sdk_incompatible"), true);
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

test("real smoke runner resolves staged OpenClaw SDK link when provided", () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "metis-openclaw-smoke-"));
  try {
    const result = runSmoke([
      "--plugin",
      `sdk-required:${sdkRequiredRoot}`,
      "--stage-root",
      tmp,
      "--openclaw-package-root",
      path.join(fixtureRoot, "fake-openclaw-sdk"),
    ]);

    assert.equal(result.status, "DONE");
    assert.equal(result.results[0].real_plugin_smoke_status, "passed");
    assert.equal(result.results[0].capabilities.tools.some((tool) => tool.name === "sdk.required.tool"), true);
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});
