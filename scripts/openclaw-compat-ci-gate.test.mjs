import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import { validateOpenClawCompatGate } from "./openclaw-compat-ci-gate.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const fixtureRoot = path.join(__dirname, "fixtures", "openclaw-compat-ci");

function readFixture(name) {
  return JSON.parse(fs.readFileSync(path.join(fixtureRoot, name), "utf8"));
}

test("passes release gate when inventory and matrix records are complete and release-ready", () => {
  const result = validateOpenClawCompatGate({
    inventory: readFixture("release-ready-inventory.json"),
    matrix: readFixture("release-ready-matrix.json"),
  });

  assert.equal(result.ok, true);
  assert.equal(result.releaseReady, true);
  assert.deepEqual(result.errors, []);
});

test("accepts object-map matrix records from generated inventory artifacts", () => {
  const result = validateOpenClawCompatGate({
    inventory: { plugins: [] },
    matrix: {
      "chat.commands": {
        pluginId: "chat",
        sourceRef: "OpenClaw/plugins/chat/src/index.ts:42",
        entry: "dist/index.mjs",
        registerApis: ["registerCommand"],
        sdkSubpaths: ["@openclaw/plugin-sdk"],
        status: "aligned",
        real_plugin_smoke_status: "passed",
        behavior_test_status: "passed",
        runtime_facets_required: ["command"],
        release_blockers: [],
      },
    },
  });

  assert.equal(result.ok, true);
  assert.equal(result.records[0].recordId, "chat.commands");
});

test("accepts generated Phase 0 snake_case inventory records", () => {
  const result = validateOpenClawCompatGate({
    inventory: {
      plugins: [
        {
          plugin_id: "openclaw-weixin",
          source_ref: "Tencent/openclaw-weixin@abc123",
          entry_path: "index.ts",
          register_apis: ["registerChannel"],
          sdk_subpaths: [],
          metis_status: "missing",
          real_plugin_smoke_status: "passed",
          behavior_test_status: "passed",
          runtime_facets_required: ["channel"],
          release_blockers: [],
          requires_metis_manifest: false,
          requires_wrapper: false,
          source_patched: false,
        },
      ],
    },
    matrix: { plugins: [] },
  });

  assert.equal(result.ok, false);
  assert.equal(result.records[0].recordId, "openclaw-weixin");
  assert.ok(result.errors.some((error) => error.code === "release_status_not_ready" && error.recordId === "openclaw-weixin"));
  assert.ok(!result.errors.some((error) => error.code === "missing_register_apis"));
  assert.ok(!result.errors.some((error) => error.code === "missing_sdk_subpaths"));
});

test("fails generated inventory records that require source patching or wrappers", () => {
  const result = validateOpenClawCompatGate({
    inventory: {
      plugins: [
        {
          plugin_id: "patched",
          source_ref: "patched@1",
          entry_path: "index.js",
          register_apis: [],
          sdk_subpaths: [],
          metis_status: "aligned",
          real_plugin_smoke_status: "passed",
          behavior_test_status: "passed",
          runtime_facets_required: [],
          release_blockers: [],
          requires_metis_manifest: true,
          requires_wrapper: "true",
          source_patched: true,
        },
      ],
    },
    matrix: { plugins: [] },
  });

  assert.equal(result.ok, false);
  assert.ok(result.errors.some((error) => error.code === "requires_metis_manifest"));
  assert.ok(result.errors.some((error) => error.code === "requires_wrapper"));
  assert.ok(result.errors.some((error) => error.code === "source_patched"));
});

test("fails release gate for partial or missing compatibility status", () => {
  const result = validateOpenClawCompatGate({
    inventory: readFixture("release-ready-inventory.json"),
    matrix: readFixture("failing-matrix.json"),
  });

  assert.equal(result.ok, false);
  assert.equal(result.releaseReady, false);
  assert.ok(result.errors.some((error) => error.code === "release_status_not_ready" && error.recordId === "chat.commands"));
});

test("fails gate when compatibility requires Metis manifests, wrappers, or source patches", () => {
  const result = validateOpenClawCompatGate({
    inventory: readFixture("release-ready-inventory.json"),
    matrix: readFixture("failing-matrix.json"),
  });

  assert.ok(result.errors.some((error) => error.code === "requires_metis_manifest" && error.recordId === "wrapper-only"));
  assert.ok(result.errors.some((error) => error.code === "requires_wrapper" && error.recordId === "wrapper-only"));
  assert.ok(result.errors.some((error) => error.code === "source_patched" && error.recordId === "wrapper-only"));
});

test("reports missing sourceRef, entry, registerApis, sdkSubpaths, and status fields", () => {
  const result = validateOpenClawCompatGate({
    inventory: { plugins: [] },
    matrix: {
      matrix: [
        {
          id: "missing-everything",
          pluginId: "broken"
        }
      ]
    },
  });

  assert.equal(result.ok, false);
  assert.deepEqual(
    result.errors.map((error) => error.code).sort(),
    [
      "missing_entry",
      "missing_register_apis",
      "missing_behavior_test_status",
      "missing_real_plugin_smoke_status",
      "missing_release_blockers",
      "missing_sdk_subpaths",
      "missing_source_ref",
      "missing_status",
      "missing_runtime_facets_required",
    ].sort(),
  );
});

test("treats string compatibility escape-hatch markers as failing markers", () => {
  const result = validateOpenClawCompatGate({
    inventory: { plugins: [] },
    matrix: {
      matrix: [
        {
          id: "string-flags",
          sourceRef: "OpenClaw/plugins/string/src/index.ts:1",
          entry: "index.mjs",
          registerApis: ["registerCommand"],
          sdkSubpaths: ["@openclaw/plugin-sdk"],
          status: "aligned",
          real_plugin_smoke_status: "passed",
          behavior_test_status: "passed",
          runtime_facets_required: ["command"],
          release_blockers: [],
          requiresWrapper: "true",
        },
      ],
    },
  });

  assert.equal(result.ok, false);
  assert.ok(result.errors.some((error) => error.code === "requires_wrapper" && error.recordId === "string-flags"));
});

test("fails release gate when smoke or behavior evidence is missing or not ready", () => {
  const result = validateOpenClawCompatGate({
    inventory: { plugins: [] },
    matrix: {
      matrix: [
        {
          id: "not-smoked",
          pluginId: "not-smoked",
          sourceRef: "OpenClaw/plugins/not-smoked/src/index.ts:1",
          entry: "index.mjs",
          registerApis: ["registerCommand"],
          sdkSubpaths: ["@openclaw/plugin-sdk"],
          status: "aligned",
          real_plugin_smoke_status: "pending",
          behavior_test_status: "missing",
          runtime_facets_required: ["command"],
          release_blockers: [],
        },
      ],
    },
  });

  assert.equal(result.ok, false);
  assert.ok(result.errors.some((error) => error.code === "real_plugin_smoke_not_ready" && error.recordId === "not-smoked"));
  assert.ok(result.errors.some((error) => error.code === "behavior_test_not_ready" && error.recordId === "not-smoked"));
});

test("fails release gate when release blockers are present", () => {
  const result = validateOpenClawCompatGate({
    inventory: { plugins: [] },
    matrix: {
      matrix: [
        {
          id: "blocked",
          pluginId: "blocked",
          sourceRef: "OpenClaw/plugins/blocked/src/index.ts:1",
          entry: "index.mjs",
          registerApis: ["registerCommand"],
          sdkSubpaths: ["@openclaw/plugin-sdk"],
          status: "aligned",
          real_plugin_smoke_status: "passed",
          behavior_test_status: "passed",
          runtime_facets_required: ["command"],
          release_blockers: ["requires channel runtime"],
        },
      ],
    },
  });

  assert.equal(result.ok, false);
  assert.ok(result.errors.some((error) => error.code === "release_blocker" && error.recordId === "blocked"));
});

test("does not treat metadata arrays as plugin records", () => {
  const result = validateOpenClawCompatGate({
    inventory: {
      summary: { release_ready: false },
      release_blockers: [
        { plugin_id: "blocked", code: "release_status_not_ready" },
      ],
      diagnostics: [
        { source: "qmd", code: "source_missing" },
      ],
      plugins: [
        {
          plugin_id: "blocked",
          source_ref: "repo@abc123",
          entry_path: "index.mjs",
          register_apis: ["registerCommand"],
          sdk_subpaths: ["@openclaw/plugin-sdk"],
          metis_status: "missing",
          real_plugin_smoke_status: "not-run",
          behavior_test_status: "not-run",
          runtime_facets_required: ["command"],
          release_blockers: [],
        },
      ],
    },
    matrix: { plugins: [] },
  });

  assert.equal(result.records.length, 1);
  assert.deepEqual(result.records.map((record) => record.recordId), ["blocked"]);
  assert.ok(!result.errors.some((error) => error.code === "missing_entry"));
  assert.ok(!result.errors.some((error) => error.code === "missing_source_ref"));
});
