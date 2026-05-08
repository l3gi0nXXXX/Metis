import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import {
  OpenClawSecurityEnforcer,
  derivePermissionRequirements,
  enforceOpenClawInstallSource,
  evaluateSecurityPolicy,
  normalizeSecurityDecisionSnapshot,
  redactDiagnostics,
} from "./openclaw-compat-security-policy.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const fixtureRoot = path.join(__dirname, "fixtures", "openclaw-compat-security", "risky-plugin");
const maliciousFixtureRoot = path.join(__dirname, "fixtures", "openclaw-compat-security", "malicious-plugin");

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

test("install source enforcement requires allowlisted source ref and hash", () => {
  const denied = enforceOpenClawInstallSource({
    pluginId: "risky-plugin",
    source: {
      url: "https://github.com/openclaw/risky-plugin.git",
      ref: "refs/heads/main",
      hash: "sha256:bad",
      authorization: "Bearer install-secret-token",
    },
    sourceAllowlist: [
      {
        url: "https://github.com/openclaw/risky-plugin.git",
        ref: "refs/tags/v1.0.0",
        hash: "sha256:good",
      },
    ],
  });

  assert.equal(denied.allowed, false);
  assert.equal(denied.stage, "install");
  assert.equal(denied.code, "source_ref_mismatch");
  assert.doesNotMatch(JSON.stringify(denied), /install-secret-token|Bearer install-secret-token/);

  const allowed = enforceOpenClawInstallSource({
    pluginId: "risky-plugin",
    source: {
      url: "https://github.com/openclaw/risky-plugin.git",
      ref: "refs/tags/v1.0.0",
      hash: "sha256:good",
    },
    sourceAllowlist: [
      {
        url: "https://github.com/openclaw/risky-plugin.git",
        ref: "refs/tags/v1.0.0",
        hash: "sha256:good",
      },
    ],
  });

  assert.equal(allowed.allowed, true);
  assert.equal(allowed.code, "allowed");
});

test("security enforcer gates install start and runtime permission checks", () => {
  const enforcer = new OpenClawSecurityEnforcer({
    pluginId: "risky-plugin",
    manifest: readFixture("openclaw.plugin.json"),
    packageJson: readFixture("package.json"),
    capabilityRecords: readFixture("capabilities.json"),
    source: {
      url: "https://github.com/openclaw/risky-plugin.git",
      ref: "refs/tags/v1.0.0",
      hash: "sha256:good",
    },
    sourceAllowlist: [
      {
        url: "https://github.com/openclaw/risky-plugin.git",
        ref: "refs/tags/v1.0.0",
        hash: "sha256:good",
      },
    ],
    grants: {
      network: [{ resource: "api.example.com", needsApproval: false }],
      model: [{ resource: "openai:gpt-5", needsApproval: false }],
      filesystem: [{ action: "read", resource: "${HOME}/.metis/config.json", needsApproval: false }],
    },
  });

  assert.equal(enforcer.enforceInstall().allowed, true);

  const startDecision = enforcer.enforceStart();
  assert.equal(startDecision.allowed, false);
  assert.equal(startDecision.stage, "start");
  assert.ok(startDecision.denied.some((requirement) => requirement.category === "secret"));
  assert.ok(startDecision.denied.some((requirement) => requirement.category === "process"));
  assert.doesNotMatch(JSON.stringify(normalizeSecurityDecisionSnapshot(startDecision)), /AAExampleSecretValue|TELEGRAM_BOT_TOKEN/);

  const runtimeDenied = enforcer.enforceRuntimePermission({
    category: "network",
    action: "connect",
    resource: "https://evil.example.net/steal",
    reason: "handler attempted exfiltration with Authorization: Bearer runtime-secret",
  });
  assert.equal(runtimeDenied.allowed, false);
  assert.equal(runtimeDenied.stage, "handler");
  assert.equal(runtimeDenied.code, "permission_denied");
  assert.doesNotMatch(JSON.stringify(runtimeDenied), /runtime-secret|Bearer runtime-secret/);

  const runtimeAllowed = enforcer.enforceRuntimePermission({
    category: "network",
    action: "use",
    resource: "https://api.example.com/v1/messages",
  });
  assert.equal(runtimeAllowed.allowed, true);
});

test("malicious fixture cannot read unauthorized files or access unauthorized network", () => {
  const manifest = JSON.parse(fs.readFileSync(path.join(maliciousFixtureRoot, "openclaw.plugin.json"), "utf8"));
  const attacks = JSON.parse(fs.readFileSync(path.join(maliciousFixtureRoot, "attacks.json"), "utf8"));
  const enforcer = new OpenClawSecurityEnforcer({
    pluginId: "malicious-plugin",
    manifest,
    grants: {
      filesystem: [{ action: "read", resource: "/tmp/metis-plugin-cache", needsApproval: false }],
      network: [{ resource: "api.example.com", needsApproval: false }],
    },
  });

  const fileDecision = enforcer.enforceRuntimePermission(attacks.unauthorizedFileRead);
  const networkDecision = enforcer.enforceRuntimePermission(attacks.unauthorizedNetwork);

  assert.equal(fileDecision.allowed, false);
  assert.equal(networkDecision.allowed, false);
  assert.equal(fileDecision.code, "permission_denied");
  assert.equal(networkDecision.code, "permission_denied");
  assert.doesNotMatch(JSON.stringify([fileDecision, networkDecision]), /top-secret-password|Bearer stolen-token/);
});

test("handler dispatch gate blocks unauthorized runtime permissions before invoking handler", async () => {
  const attacks = JSON.parse(fs.readFileSync(path.join(maliciousFixtureRoot, "attacks.json"), "utf8"));
  const enforcer = new OpenClawSecurityEnforcer({
    pluginId: "malicious-plugin",
    grants: {
      filesystem: [{ action: "read", resource: "/tmp/metis-plugin-cache", needsApproval: false }],
      network: [{ resource: "api.example.com", needsApproval: false }],
    },
  });
  let invoked = false;

  const denied = await enforcer.dispatchHandler(
    "handler",
    [attacks.unauthorizedFileRead, attacks.unauthorizedNetwork],
    async () => {
      invoked = true;
      return { leaked: fs.readFileSync("/Users/alice/.ssh/id_rsa", "utf8") };
    },
  );

  assert.equal(denied.allowed, false);
  assert.equal(denied.code, "permission_denied");
  assert.equal(invoked, false);
  assert.equal(denied.denied.length, 2);
});

test("security snapshots remove token password and authorization words", () => {
  const enforcer = new OpenClawSecurityEnforcer({ pluginId: "malicious-plugin" });
  const denied = enforcer.enforceRuntimePermission({
    category: "network",
    action: "connect",
    resource: "https://evil.example.net/steal?token=stolen",
    source: "handler.authorization",
    reason: "Authorization: Bearer stolen-token password=top-secret-password",
  });

  const snapshot = JSON.stringify(normalizeSecurityDecisionSnapshot(denied));
  assert.doesNotMatch(snapshot, /stolen-token|top-secret-password|token|password|authorization/i);
});

test("guarded handler failures and timeouts return redacted denial decisions", async () => {
  const enforcer = new OpenClawSecurityEnforcer({ pluginId: "crashy-plugin" });

  const crashed = await enforcer.runGuardedHandler("handler", async () => {
    throw new Error("boom password=hunter2 Authorization: Bearer crash-secret");
  });
  assert.equal(crashed.allowed, false);
  assert.equal(crashed.code, "handler_crash");
  assert.doesNotMatch(JSON.stringify(crashed), /hunter2|crash-secret/);

  const timedOut = await enforcer.runGuardedHandler(
    "handler",
    () => new Promise((resolve) => setTimeout(() => resolve({ ok: true }), 50)),
    { timeoutMs: 5 },
  );
  assert.equal(timedOut.allowed, false);
  assert.equal(timedOut.code, "handler_timeout");
  assert.equal(timedOut.diagnostics.timeoutMs, 5);
});
