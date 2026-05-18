import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import test from "node:test";

test("sidecar logger keeps stdout protocol JSON and routes diagnostics to stderr", () => {
  const child = spawnSync(
    process.execPath,
    [
      "--input-type=module",
      "--eval",
      `
        import {
          configureKnownSecrets,
          installConsoleStderrPatch,
          writeDiagnostic,
          writeProtocol,
        } from "./lib/metis-sidecar-logger.mjs";

        configureKnownSecrets(["fake-secret-token"]);
        installConsoleStderrPatch({ prefix: "fixture-sidecar" });
        console.log("console fake-secret-token");
        console.error("console-error fake-secret-token");
        writeDiagnostic("warn", "diagnostic fake-secret-token", { authorization: "Bearer fake-secret-token" }, { prefix: "fixture-sidecar" });
        writeProtocol({ type: "event", payload: { text: "hello fake-secret-token", nested: { token: "fake-secret-token" } } });
      `,
    ],
    {
      cwd: import.meta.dirname,
      encoding: "utf8",
    },
  );

  assert.equal(child.status, 0, child.stderr);
  const stdoutLines = child.stdout.trim().split(/\n+/).filter(Boolean);
  assert.equal(stdoutLines.length, 1, child.stdout);
  const frame = JSON.parse(stdoutLines[0]);
  assert.equal(frame.type, "event");
  assert.equal(frame.payload.text.includes("fake-secret-token"), false);
  assert.equal(frame.payload.nested.token, "[REDACTED]");
  for (const line of stdoutLines) {
    assert.doesNotThrow(() => JSON.parse(line));
  }
  const stderrLines = child.stderr.trim().split(/\n+/).filter(Boolean);
  assert.ok(stderrLines.length >= 3, child.stderr);
  for (const line of stderrLines) {
    assert.match(line, /^\[fixture-sidecar\] /);
    assert.throws(() => JSON.parse(line));
  }
  assert.match(child.stderr, /\[fixture-sidecar\] info: console \[REDACTED\]/);
  assert.match(child.stderr, /\[fixture-sidecar\] error: console-error \[REDACTED\]/);
  assert.match(child.stderr, /\[fixture-sidecar\] warn: diagnostic \[REDACTED\]/);
  assert.equal(`${child.stdout}${child.stderr}`.includes("fake-secret-token"), false);
});

test("sidecar logger redacts nested protocol secrets and patches all console levels", () => {
  const child = spawnSync(
    process.execPath,
    [
      "--input-type=module",
      "--eval",
      `
        import {
          configureKnownSecrets,
          installConsoleStderrPatch,
          writeDiagnostic,
          writeProtocol,
        } from "./lib/metis-sidecar-logger.mjs";

        configureKnownSecrets(["phase9-known-secret"]);
        installConsoleStderrPatch({ prefix: "phase9-sidecar" });
        console.info("info phase9-known-secret");
        console.warn("warn token=phase9-query-secret");
        console.error("error https://example.test/?token=phase9-url-secret");
        console.debug("debug ok");
        console.trace("trace ok");
        writeDiagnostic("error", "diagnostic phase9-known-secret", {
          token: "phase9-field-secret",
          nested: {
            authorization: "Bearer phase9-field-bearer",
            url: "https://example.test/?key=phase9-field-key",
          },
        }, { prefix: "phase9-sidecar" });
        writeProtocol({
          type: "event",
          payload: {
            url: "https://example.test/path?secret=phase9-protocol-secret",
            token: "phase9-protocol-token",
            nested: { api_key: "phase9-protocol-api-key" },
          },
        });
      `,
    ],
    {
      cwd: import.meta.dirname,
      encoding: "utf8",
    },
  );

  assert.equal(child.status, 0, child.stderr);
  const stdoutLines = child.stdout.trim().split(/\n+/).filter(Boolean);
  assert.equal(stdoutLines.length, 1, child.stdout);
  const frame = JSON.parse(stdoutLines[0]);
  assert.equal(frame.type, "event");
  assert.equal(frame.payload.token, "[REDACTED]");
  assert.equal(frame.payload.nested.api_key, "[REDACTED]");
  assert.equal(frame.payload.url.includes("phase9-protocol-secret"), false);
  assert.match(child.stderr, /\[phase9-sidecar\] info:/);
  assert.match(child.stderr, /\[phase9-sidecar\] warn:/);
  assert.match(child.stderr, /\[phase9-sidecar\] error:/);
  assert.match(child.stderr, /\[phase9-sidecar\] debug:/);
  assert.match(child.stderr, /\[phase9-sidecar\] trace:/);
  assert.doesNotMatch(child.stderr, /^\{"type":"event"/m);
  assert.equal(`${child.stdout}${child.stderr}`.includes("phase9-known-secret"), false);
  assert.equal(`${child.stdout}${child.stderr}`.includes("phase9-query-secret"), false);
  assert.equal(`${child.stdout}${child.stderr}`.includes("phase9-url-secret"), false);
  assert.equal(`${child.stdout}${child.stderr}`.includes("phase9-field-secret"), false);
  assert.equal(`${child.stdout}${child.stderr}`.includes("phase9-field-bearer"), false);
  assert.equal(`${child.stdout}${child.stderr}`.includes("phase9-field-key"), false);
  assert.equal(`${child.stdout}${child.stderr}`.includes("phase9-protocol-secret"), false);
  assert.equal(`${child.stdout}${child.stderr}`.includes("phase9-protocol-token"), false);
  assert.equal(`${child.stdout}${child.stderr}`.includes("phase9-protocol-api-key"), false);
});

test("sidecar logger redacts common provider tokens without explicit secret registration", () => {
  const child = spawnSync(
    process.execPath,
    [
      "--input-type=module",
      "--eval",
      `
        import {
          installConsoleStderrPatch,
          writeDiagnostic,
          writeProtocol,
        } from "./lib/metis-sidecar-logger.mjs";

        installConsoleStderrPatch({ prefix: "pattern-sidecar" });
        console.warn("openai sk-proj-1234567890abcdef github ghp_1234567890abcdef1234567890abcdef1234");
        writeDiagnostic("error", "telegram bot123456:abcdefghijklmnopqrstuvwxyz_123456789 bearer Bearer abcdefghijklmnopqrstuvwxyz123456", {
          pem: "-----BEGIN PRIVATE KEY-----\\nabc123\\n-----END PRIVATE KEY-----",
          google: "AIza1234567890abcdefghijklmnop",
          npm: "npm_1234567890abcdef",
        }, { prefix: "pattern-sidecar" });
        writeProtocol({
          type: "event",
          payload: {
            tokenLike: "pplx-1234567890abcdef",
            groq: "gsk_1234567890abcdef",
            slack: "xoxb-1234567890-abcdef",
          },
        });
      `,
    ],
    {
      cwd: import.meta.dirname,
      encoding: "utf8",
    },
  );

  assert.equal(child.status, 0, child.stderr);
  const combined = `${child.stdout}${child.stderr}`;
  assert.equal(combined.includes("sk-proj-1234567890abcdef"), false);
  assert.equal(combined.includes("ghp_1234567890abcdef1234567890abcdef1234"), false);
  assert.equal(combined.includes("bot123456:abcdefghijklmnopqrstuvwxyz_123456789"), false);
  assert.equal(combined.includes("Bearer abcdefghijklmnopqrstuvwxyz123456"), false);
  assert.equal(combined.includes("-----BEGIN PRIVATE KEY-----"), false);
  assert.equal(combined.includes("AIza1234567890abcdefghijklmnop"), false);
  assert.equal(combined.includes("npm_1234567890abcdef"), false);
  assert.equal(combined.includes("pplx-1234567890abcdef"), false);
  assert.equal(combined.includes("gsk_1234567890abcdef"), false);
  assert.equal(combined.includes("xoxb-1234567890-abcdef"), false);
});
