import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import { validateOpenClawCompatGate } from "./openclaw-compat-ci-gate.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, "..");
const artifactRoot = path.join("scripts", "fixtures", "openclaw-compat-ci", "artifacts");
const currentMatrixPath = path.join(repoRoot, "develop_steps", "openclaw-plugin-compatibility-matrix-2026-05-08.json");

function alignedRecord(id, overrides = {}) {
  return {
    plugin_id: id,
    source_repo: "openclaw",
    source_ref: "3e72c0352d",
    entry_path: `plugins/${id}/src/index.ts`,
    register_apis: ["registerCommand"],
    sdk_subpaths: ["@openclaw/plugin-sdk"],
    metis_status: "aligned",
    real_plugin_smoke_status: "passed",
    real_plugin_smoke_artifact: path.join(artifactRoot, "chat-smoke.json"),
    behavior_test_status: "passed",
    behavior_test_artifact: path.join(artifactRoot, "chat-behavior.json"),
    install_security_status: "passed",
    install_security_artifact: path.join(artifactRoot, "chat-install-security.json"),
    start_security_status: "passed",
    start_security_artifact: path.join(artifactRoot, "chat-start-security.json"),
    handler_security_status: "passed",
    handler_security_artifact: path.join(artifactRoot, "chat-handler-security.json"),
    runtime_facets_required: ["command"],
    release_blockers: [],
    requires_metis_manifest: false,
    requires_wrapper: false,
    source_patched: false,
    ...overrides,
  };
}

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, "utf8"));
}

function syntheticFullMatrix(records) {
  return {
    schema_version: 1,
    sources: [
      { name: "openclaw", exists: true, ref: "3e72c0352d" },
      { name: "openclaw-china", exists: true, ref: "a36d023" },
      { name: "openclaw-weixin", exists: true, ref: "f3e1d2c" },
      { name: "clawmate", exists: true, ref: "580e011" },
      { name: "qmd", exists: true, ref: "9a8b7c6" },
    ],
    summary: {
      plugin_count: records.length,
      by_status: records.reduce((counts, record) => {
        const status = record.metis_status ?? record.status;
        counts[status] = (counts[status] ?? 0) + 1;
        return counts;
      }, {}),
      release_ready: true,
    },
    plugins: records,
    diagnostics: [],
  };
}

test("fails the current all-plugin matrix shape with 104 missing plugins, qmd missing, openclaw-weixin unpinned, and missing behavior tests", () => {
  const missingRecords = Array.from({ length: 104 }, (_, index) =>
    alignedRecord(`gap-${String(index + 1).padStart(3, "0")}`, {
      metis_status: "missing",
      behavior_test_status: undefined,
      release_blockers: ["release_status_not_ready"],
    }),
  );

  const matrix = syntheticFullMatrix(missingRecords);
  matrix.sources = [
    { name: "openclaw", exists: true, ref: "3e72c0352d" },
    { name: "openclaw-china", exists: true, ref: "a36d023" },
    { name: "openclaw-weixin", exists: true, ref: "" },
    { name: "clawmate", exists: true, ref: "580e011" },
    { name: "qmd", exists: false, ref: "" },
  ];
  matrix.summary = {
    plugin_count: 104,
    by_status: { missing: 104 },
    release_ready: false,
  };
  matrix.diagnostics = [
    {
      source: "qmd",
      code: "source_missing",
      message: "Source root not found: /Users/l3gi0n/work/workspace_cangjie/qmd",
    },
  ];

  const result = validateOpenClawCompatGate({
    inventory: { plugins: [] },
    matrix,
  });

  assert.equal(result.ok, false);
  assert.equal(
    result.errors.filter((error) => error.code === "release_status_not_ready").length,
    104,
  );
  assert.ok(result.errors.some((error) => error.code === "source_missing" && error.recordId === "qmd"));
  assert.ok(result.errors.some((error) => error.code === "missing_source_ref" && error.recordId === "openclaw-weixin"));
  assert.ok(result.errors.some((error) => error.code === "missing_behavior_test_status"));
  assert.ok(result.errors.some((error) => error.code === "summary_release_not_ready"));
});

test("passes a synthetic full matrix only when every plugin is aligned or not-applicable with release evidence", () => {
  const matrix = syntheticFullMatrix([
    alignedRecord("chat-commands"),
    alignedRecord("china-channel", { source_repo: "openclaw-china" }),
    alignedRecord("weixin-channel", { source_repo: "openclaw-weixin" }),
    alignedRecord("clawmate-companion", { source_repo: "clawmate" }),
    alignedRecord("setup-only", {
      metis_status: "not-applicable",
      real_plugin_smoke_status: "not-applicable",
      behavior_test_status: "not-applicable",
      install_security_status: "not-applicable",
      start_security_status: "not-applicable",
      handler_security_status: "not-applicable",
      runtime_facets_required: [],
    }),
  ]);

  const result = validateOpenClawCompatGate({
    inventory: { plugins: [] },
    matrix,
  });

  assert.equal(result.ok, true);
  assert.equal(result.releaseReady, true);
  assert.deepEqual(result.errors, []);
});

test("fails the checked-in real matrix until all current blockers are resolved with real evidence", () => {
  const matrix = readJson(currentMatrixPath);
  const result = validateOpenClawCompatGate({
    inventory: { plugins: [] },
    matrix,
  });

  assert.equal(result.ok, false);
  assert.equal(matrix.summary.plugin_count, 104);
  assert.equal(matrix.summary.by_status.missing, 104);
  assert.equal(
    result.errors.filter((error) => error.code === "release_status_not_ready").length,
    104,
  );
  assert.ok(result.errors.some((error) => error.code === "source_missing" && error.recordId === "qmd"));
  assert.ok(result.errors.some((error) => error.code === "real_plugin_smoke_not_ready"));
  assert.ok(result.errors.some((error) => error.code === "behavior_test_not_ready"));
});
