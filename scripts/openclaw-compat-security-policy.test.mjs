import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import {
  derivePermissionRequirements,
  evaluateSecurityPolicy,
  redactDiagnostics,
} from "./openclaw-compat-security-policy.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const fixtureRoot = path.join(__dirname, "fixtures", "openclaw-compat-security", "risky-plugin");

function readFixture(name) {
  return JSON.parse(fs.readFileSync(path.join(fixtureRoot, name), "utf8"));
}

test("derives all supported permission categories from manifest, package, and capability records", () => {
  const requirements = derivePermissionRequirements({
    manifest: readFixture("openclaw.plugin.json"),
    packageJson: readFixture("package.json"),
    capabilityRecords: readFixture("capabilities.json"),
  });

  const categories = new Set(requirements.map((requirement) => requirement.category));
  assert.deepEqual([...categories].sort(), [
    "browser",
    "env",
    "filesystem",
    "media",
    "model",
    "network",
    "process",
    "secret",
    "webhook",
  ]);
  assert.ok(requirements.some((requirement) => requirement.category === "process" && requirement.resource === "postinstall"));
  assert.ok(requirements.some((requirement) => requirement.category === "filesystem" && requirement.action === "write"));
});

test("denies every derived requirement by default", () => {
  const result = evaluateSecurityPolicy({
    pluginId: "risky-plugin",
    manifest: readFixture("openclaw.plugin.json"),
    packageJson: readFixture("package.json"),
    capabilityRecords: readFixture("capabilities.json"),
  });

  assert.equal(result.pluginId, "risky-plugin");
  assert.equal(result.allowed.length, 0);
  assert.equal(result.needsApproval.length, 0);
  assert.ok(result.denied.length >= 9);
  assert.equal(result.releaseReady, false);
});

test("allowlist grants low-risk permissions and still marks high-risk permissions for approval", () => {
  const result = evaluateSecurityPolicy({
    pluginId: "risky-plugin",
    manifest: readFixture("openclaw.plugin.json"),
    packageJson: readFixture("package.json"),
    capabilityRecords: readFixture("capabilities.json"),
    allowlist: {
      network: ["api.example.com", "api.package.example", "docs.example.com"],
      model: ["openai:gpt-5"],
      process: ["git"],
      filesystem: ["${HOME}/.metis/config.json"],
    },
  });

  assert.ok(result.allowed.some((requirement) => requirement.category === "network"));
  assert.ok(result.allowed.some((requirement) => requirement.category === "model"));
  assert.ok(result.needsApproval.some((requirement) => requirement.category === "process" && requirement.resource === "git"));
  assert.ok(result.needsApproval.some((requirement) => requirement.category === "filesystem"));
  assert.ok(result.denied.some((requirement) => requirement.category === "secret"));
});

test("redacts secrets from diagnostics recursively", () => {
  const diagnostics = redactDiagnostics({
    token: "123456789:AAExampleSecretValue",
    authorization: "Bearer abc.def.ghi",
    nested: {
      url: "https://user:password@example.com/hook?token=secret",
      env: "OPENAI_API_KEY=sk-secret-value",
    },
    plain: "network access denied",
  });

  assert.equal(diagnostics.token, "[REDACTED]");
  assert.equal(diagnostics.authorization, "[REDACTED]");
  assert.equal(diagnostics.nested.url, "https://[REDACTED]@example.com/hook?token=[REDACTED]");
  assert.equal(diagnostics.nested.env, "OPENAI_API_KEY=[REDACTED]");
  assert.equal(diagnostics.plain, "network access denied");
});
