import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import { validateOpenClawCompatGate } from "./openclaw-compat-ci-gate.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const fixtureRoot = path.join(__dirname, "fixtures", "openclaw-compat-ci");
const artifactRoot = path.join("scripts", "fixtures", "openclaw-compat-ci", "artifacts");
const passedSecurityEvidence = {
  install_security_status: "passed",
  install_security_artifact: path.join(artifactRoot, "chat-install-security.json"),
  start_security_status: "passed",
  start_security_artifact: path.join(artifactRoot, "chat-start-security.json"),
  handler_security_status: "passed",
  handler_security_artifact: path.join(artifactRoot, "chat-handler-security.json"),
};

function readFixture(name) {
  return JSON.parse(fs.readFileSync(path.join(fixtureRoot, name), "utf8"));
}

function alignedRecord(id, overrides = {}) {
  return {
    id,
    pluginId: id,
    source_repo: "openclaw",
    sourceRef: `OpenClaw/plugins/${id}/src/index.ts:1`,
    entry: "dist/index.mjs",
    registerApis: ["registerCommand"],
    sdkSubpaths: ["@openclaw/plugin-sdk"],
    status: "aligned",
    real_plugin_smoke_status: "passed",
    real_plugin_smoke_artifact: path.join(artifactRoot, "chat-smoke.json"),
    behavior_test_status: "passed",
    behavior_test_artifact: path.join(artifactRoot, "chat-behavior.json"),
    ...passedSecurityEvidence,
    runtime_facets_required: ["command"],
    release_blockers: [],
    ...overrides,
  };
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
        real_plugin_smoke_artifact: path.join(artifactRoot, "chat-smoke.json"),
        behavior_test_status: "passed",
        behavior_test_artifact: path.join(artifactRoot, "chat-behavior.json"),
        ...passedSecurityEvidence,
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
          real_plugin_smoke_artifact: path.join(artifactRoot, "chat-smoke.json"),
          behavior_test_status: "passed",
          behavior_test_artifact: path.join(artifactRoot, "chat-behavior.json"),
          ...passedSecurityEvidence,
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
          real_plugin_smoke_artifact: path.join(artifactRoot, "chat-smoke.json"),
          behavior_test_status: "passed",
          behavior_test_artifact: path.join(artifactRoot, "chat-behavior.json"),
          ...passedSecurityEvidence,
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
      "missing_install_security_status",
      "missing_start_security_status",
      "missing_handler_security_status",
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
          real_plugin_smoke_artifact: path.join(artifactRoot, "chat-smoke.json"),
          behavior_test_status: "passed",
          behavior_test_artifact: path.join(artifactRoot, "chat-behavior.json"),
          ...passedSecurityEvidence,
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
          ...passedSecurityEvidence,
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

test("fails release gate when passed smoke or behavior evidence lacks artifact paths", () => {
  const result = validateOpenClawCompatGate({
    inventory: { plugins: [] },
    matrix: {
      matrix: [
        alignedRecord("no-artifacts", {
          real_plugin_smoke_artifact: undefined,
          behavior_test_artifact: undefined,
        }),
      ],
    },
  });

  assert.equal(result.ok, false);
  assert.ok(result.errors.some((error) => error.code === "missing_real_plugin_smoke_artifact" && error.recordId === "no-artifacts"));
  assert.ok(result.errors.some((error) => error.code === "missing_behavior_test_artifact" && error.recordId === "no-artifacts"));
});

test("fails aligned promotion when install, start, or handler security evidence is missing", () => {
  const result = validateOpenClawCompatGate({
    inventory: { plugins: [] },
    matrix: {
      matrix: [
        alignedRecord("missing-security-evidence", {
          install_security_status: undefined,
          install_security_artifact: undefined,
          start_security_status: undefined,
          start_security_artifact: undefined,
          handler_security_status: undefined,
          handler_security_artifact: undefined,
        }),
      ],
    },
  });

  assert.equal(result.ok, false);
  assert.ok(result.errors.some((error) => error.code === "missing_install_security_status" && error.recordId === "missing-security-evidence"));
  assert.ok(result.errors.some((error) => error.code === "missing_start_security_status" && error.recordId === "missing-security-evidence"));
  assert.ok(result.errors.some((error) => error.code === "missing_handler_security_status" && error.recordId === "missing-security-evidence"));
});

test("fails aligned promotion unless every security gate status is passed", () => {
  const result = validateOpenClawCompatGate({
    inventory: { plugins: [] },
    matrix: {
      matrix: [
        alignedRecord("not-run-security", {
          install_security_status: "not-run",
        }),
        alignedRecord("not-applicable-security", {
          start_security_status: "not-applicable",
        }),
      ],
    },
  });

  assert.equal(result.ok, false);
  assert.ok(result.errors.some((error) => error.code === "install_security_not_ready" && error.recordId === "not-run-security"));
  assert.ok(result.errors.some((error) => error.code === "aligned_security_evidence_not_passed" && error.recordId === "not-applicable-security"));
});

test("fails aligned promotion unless smoke and behavior evidence are passed artifacts", () => {
  const result = validateOpenClawCompatGate({
    inventory: { plugins: [] },
    matrix: {
      matrix: [
        alignedRecord("not-applicable-smoke", {
          real_plugin_smoke_status: "not-applicable",
          real_plugin_smoke_artifact: undefined,
        }),
        alignedRecord("not-applicable-behavior", {
          behavior_test_status: "not-applicable",
          behavior_test_artifact: undefined,
        }),
      ],
    },
  });

  assert.equal(result.ok, false);
  assert.ok(result.errors.some((error) => error.code === "aligned_evidence_not_passed" && error.recordId === "not-applicable-smoke"));
  assert.ok(result.errors.some((error) => error.code === "aligned_evidence_not_passed" && error.recordId === "not-applicable-behavior"));
});

test("fails release gate when security artifacts are missing or do not match the schema", () => {
  const result = validateOpenClawCompatGate({
    inventory: { plugins: [] },
    matrix: {
      matrix: [
        alignedRecord("missing-security-artifact", {
          install_security_artifact: path.join(artifactRoot, "missing-install-security.json"),
        }),
        alignedRecord("wrong-security-artifact", {
          handler_security_artifact: path.join(artifactRoot, "chat-behavior.json"),
        }),
      ],
    },
  });

  assert.equal(result.ok, false);
  assert.ok(result.errors.some((error) => error.code === "install_security_artifact_missing" && error.recordId === "missing-security-artifact"));
  assert.ok(result.errors.some((error) => error.code === "invalid_handler_security_artifact" && error.recordId === "wrong-security-artifact"));
});

test("fails release gate when referenced smoke or behavior artifacts do not exist", () => {
  const result = validateOpenClawCompatGate({
    inventory: { plugins: [] },
    matrix: {
      matrix: [
        alignedRecord("missing-artifacts", {
          real_plugin_smoke_artifact: path.join(artifactRoot, "missing-smoke.json"),
          behavior_test_artifact: path.join(artifactRoot, "missing-behavior.json"),
        }),
      ],
    },
  });

  assert.equal(result.ok, false);
  assert.ok(result.errors.some((error) => error.code === "real_plugin_smoke_artifact_missing" && error.recordId === "missing-artifacts"));
  assert.ok(result.errors.some((error) => error.code === "behavior_test_artifact_missing" && error.recordId === "missing-artifacts"));
});

test("fails source boundary metadata for dirty openclaw source and omitted qmd source", () => {
  const result = validateOpenClawCompatGate({
    inventory: {
      sources: [
        { name: "openclaw", exists: true, ref: "3e72c0352d", dirty: true, dirty_paths: ["pnpm-lock.yaml"] },
        { name: "openclaw-china", exists: true, ref: "a36d023" },
        { name: "openclaw-weixin", exists: true, ref: "archive-sha256:abc" },
        { name: "clawmate", exists: true, ref: "580e011" },
      ],
      plugins: [alignedRecord("dirty-source")],
    },
    matrix: { plugins: [] },
  });

  assert.equal(result.ok, false);
  assert.ok(result.errors.some((error) => error.code === "source_dirty" && error.recordId === "openclaw"));
  assert.ok(result.errors.some((error) => error.code === "source_missing" && error.recordId === "qmd"));
});

test("fails source boundary when a pinned git source root is dirty", () => {
  const sourceRoot = fs.mkdtempSync(path.join(os.tmpdir(), "metis-openclaw-source-"));
  execFileSync("git", ["-C", sourceRoot, "init"], { stdio: "ignore" });
  execFileSync("git", ["-C", sourceRoot, "config", "user.email", "metis-test@example.invalid"], { stdio: "ignore" });
  execFileSync("git", ["-C", sourceRoot, "config", "user.name", "Metis Test"], { stdio: "ignore" });
  fs.writeFileSync(path.join(sourceRoot, "pnpm-lock.yaml"), "lockfileVersion: 9\n");
  execFileSync("git", ["-C", sourceRoot, "add", "pnpm-lock.yaml"], { stdio: "ignore" });
  execFileSync("git", ["-C", sourceRoot, "commit", "-m", "seed"], { stdio: "ignore" });
  fs.appendFileSync(path.join(sourceRoot, "pnpm-lock.yaml"), "dirty: true\n");

  const result = validateOpenClawCompatGate({
    inventory: {
      sources: [
        { name: "openclaw", root: sourceRoot, exists: true, ref: "3e72c0352d" },
        { name: "openclaw-china", exists: true, ref: "a36d023" },
        { name: "openclaw-weixin", exists: true, ref: "archive-sha256:abc" },
        { name: "clawmate", exists: true, ref: "580e011" },
        { name: "qmd", exists: true, ref: "9a8b7c6" },
      ],
      plugins: [alignedRecord("dirty-source")],
    },
    matrix: { plugins: [] },
  });

  assert.equal(result.ok, false);
  assert.ok(result.errors.some((error) => error.code === "source_dirty" && error.recordId === "openclaw"));
});

test("fails release gate when representative plugin evidence is absent", () => {
  const result = validateOpenClawCompatGate({
    inventory: {
      sources: [
        { name: "openclaw", exists: true, ref: "3e72c0352d" },
        { name: "openclaw-china", exists: true, ref: "a36d023" },
        { name: "openclaw-weixin", exists: true, ref: "archive-sha256:abc" },
        { name: "clawmate", exists: true, ref: "580e011" },
        { name: "qmd", exists: true, ref: "9a8b7c6" },
      ],
      plugins: [
        alignedRecord("china-channel", { source_repo: "openclaw-china" }),
        alignedRecord("plain-openclaw"),
      ],
    },
    matrix: { plugins: [] },
  });

  assert.equal(result.ok, false);
  assert.ok(result.errors.some((error) => error.code === "missing_representative_plugin_evidence" && error.recordId === "openclaw-weixin"));
  assert.ok(result.errors.some((error) => error.code === "missing_representative_plugin_evidence" && error.recordId === "clawmate"));
  assert.ok(!result.errors.some((error) => error.code === "missing_representative_plugin_evidence" && error.recordId === "openclaw-china"));
});

test("fails release gate when source boundary plugin counts do not match records", () => {
  const matrix = {
    sources: [
      { name: "openclaw", exists: true, ref: "3e72c0352d", plugin_count: 2 },
      { name: "openclaw-china", exists: true, ref: "a36d023", plugin_count: 0 },
      { name: "openclaw-weixin", exists: true, ref: "archive-sha256:abc", plugin_count: 0 },
      { name: "clawmate", exists: true, ref: "580e011", plugin_count: 0 },
      { name: "qmd", exists: true, ref: "9a8b7c6", plugin_count: 0 },
    ],
    summary: {
      plugin_count: 1,
      by_source: { openclaw: 2 },
      source_boundary: {
        total_from_sources: 2,
        plugin_count_matches_sources: false,
      },
    },
    plugins: [alignedRecord("one-openclaw")],
  };

  const result = validateOpenClawCompatGate({
    inventory: { plugins: [] },
    matrix,
  });

  assert.equal(result.ok, false);
  assert.ok(result.errors.some((error) => error.code === "source_plugin_count_mismatch" && error.recordId === "openclaw"));
  assert.ok(result.errors.some((error) => error.code === "summary_plugin_count_mismatch" && error.recordId === "plugin_count"));
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
          real_plugin_smoke_artifact: path.join(artifactRoot, "chat-smoke.json"),
          behavior_test_status: "passed",
          behavior_test_artifact: path.join(artifactRoot, "chat-behavior.json"),
          ...passedSecurityEvidence,
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
          install_security_status: "not-run",
          start_security_status: "not-run",
          handler_security_status: "not-run",
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
