import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import {
  canClaimZeroCostCompatibility,
  normalizeCapabilityRegistry,
  redactSecrets,
} from "./openclaw-compat-capabilities.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const fixtureDir = path.join(__dirname, "fixtures", "openclaw-compat-capabilities");

function readFixture(name) {
  return JSON.parse(fs.readFileSync(path.join(fixtureDir, name), "utf8"));
}

test("normalizes every OpenClaw capability group into Metis capability records", () => {
  const report = normalizeCapabilityRegistry(readFixture("full-capture.json"));
  const expectedGroups = [
    "channel",
    "httpRoute",
    "httpHandler",
    "tool",
    "provider",
    "hook",
    "command",
    "cli",
    "approval",
    "interactive",
    "memory",
    "media",
    "process",
    "browser",
    "realtime",
    "acp",
  ];

  assert.deepEqual(Object.keys(report.groups), expectedGroups);
  assert.equal(report.records.length, expectedGroups.length);
  assert.equal(report.releaseGate.zeroCostCompatible, true);
  assert.equal(report.releaseGate.blockingRecords.length, 0);

  for (const group of expectedGroups) {
    assert.equal(report.groups[group].status, "aligned", group);
    assert.equal(report.groups[group].records.length, 1, group);
    assert.equal(report.groups[group].gap, "");
    assert.equal(report.groups[group].implementationTask, "");
    assert.ok(report.groups[group].acceptanceTests.length > 0, group);
    assert.equal(report.groups[group].records[0].status, "aligned", group);
    assert.equal(report.groups[group].records[0].source, "openclaw-host-capture");
  }

  assert.deepEqual(report.diagnostics, []);
  assert.equal(canClaimZeroCostCompatibility(report), true);
});

test("blocks zero cost compatibility when any capability is partial or missing", () => {
  const capture = {
    source: "openclaw-host-capture",
    capabilities: [
      {
        kind: "tool",
        name: "web_search",
        metisStatus: "partial",
        gap: "Metis has no direct OpenClaw web_search parity gate",
        implementationTask: "Map web_search to Gateway tool registry with policy checks",
        acceptanceTests: ["web_search capture emits Gateway tool fixture"],
      },
      {
        kind: "memory",
        id: "project-memory",
        status: "missing",
        gap: "No project-scoped memory compatibility record exists",
        implementationTask: "Add memory capability bridge contract",
        acceptanceTests: ["project memory fixture can be imported without loss"],
      },
    ],
  };

  const report = normalizeCapabilityRegistry(capture);

  assert.equal(report.releaseGate.zeroCostCompatible, false);
  assert.deepEqual(
    report.releaseGate.blockingRecords.map((record) => `${record.group}:${record.id}:${record.status}`),
    ["tool:web_search:partial", "memory:project-memory:missing"],
  );
  assert.match(report.releaseGate.reason, /partial\/missing/);
  assert.equal(canClaimZeroCostCompatibility(report), false);
});

test("emits diagnostics for unknown capability groups and schema problems", () => {
  const report = normalizeCapabilityRegistry({
    source: "openclaw-host-capture",
    capabilities: [
      { kind: "workflow", id: "custom-flow", metisStatus: "aligned" },
      { kind: "tool", metisStatus: "aligned", acceptanceTests: ["missing id should be diagnosed"] },
      {
        kind: "provider",
        id: "bad-status",
        metisStatus: "done",
        gap: "Invalid status blocks automated compatibility claims",
        implementationTask: "Use an accepted status value",
        acceptanceTests: ["provider status validation fixture fails closed"],
      },
      { kind: "approval", id: "approval-without-tests", metisStatus: "aligned" },
      { kind: "memory", id: "memory-without-gap", metisStatus: "missing", acceptanceTests: ["memory fixture is captured"] },
    ],
  });

  assert.deepEqual(
    report.diagnostics.map((diagnostic) => diagnostic.code),
    [
      "unknown_capability_group",
      "missing_capability_id",
      "invalid_status",
      "missing_acceptance_tests",
      "missing_gap",
      "missing_implementation_task",
    ],
  );
  assert.equal(report.records.length, 3);
  assert.equal(report.records.find((record) => record.id === "bad-status").status, "partial");
  assert.equal(report.records.find((record) => record.id === "approval-without-tests").status, "partial");
  assert.equal(report.records.find((record) => record.id === "memory-without-gap").status, "missing");
  assert.equal(report.releaseGate.zeroCostCompatible, false);
});

test("redacts secret and token fields without destroying normalized capability shape", () => {
  const capture = readFixture("full-capture.json");
  const sanitized = redactSecrets(capture);
  const serialized = JSON.stringify(sanitized);

  assert.equal(sanitized.authToken, "[REDACTED]");
  assert.equal(sanitized.registry.channels[0].botToken, "[REDACTED]");
  assert.equal(sanitized.registry.providers[0].apiKey, "[REDACTED]");
  assert.doesNotMatch(serialized, /ocp_live_super_secret|telegram-secret|sk-proj-secret/);

  const report = normalizeCapabilityRegistry(capture);
  assert.equal(report.sanitizedCapture.authToken, "[REDACTED]");
  assert.equal(report.groups.provider.records[0].raw.apiKey, "[REDACTED]");
  assert.equal(report.groups.channel.records[0].raw.botToken, "[REDACTED]");
});
