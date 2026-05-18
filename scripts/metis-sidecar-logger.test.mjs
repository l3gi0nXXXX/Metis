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
