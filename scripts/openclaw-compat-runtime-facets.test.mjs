import assert from "node:assert/strict";
import test from "node:test";

import { createRuntimeFacets, createRuntimeState } from "./openclaw-compat-runtime-facets.mjs";

test("runtime config is a redacted immutable snapshot and secrets resolve with redacted diagnostics", async () => {
  const state = createRuntimeState({
    config: {
      publicFlag: true,
      nested: { mode: "test" },
      OPENCLAW_TOKEN: "config-secret-value",
    },
    secrets: { OPENCLAW_TOKEN: "super-secret-token" },
  });
  const runtime = createRuntimeFacets(state, "fixture-plugin");

  assert.equal(runtime.config.publicFlag, true);
  assert.equal(runtime.config.nested.mode, "test");
  assert.equal(runtime.config.OPENCLAW_TOKEN, "[REDACTED]");
  assert.throws(() => {
    runtime.config.publicFlag = false;
  }, TypeError);

  const value = await runtime.secrets.get("OPENCLAW_TOKEN");
  assert.equal(value, "super-secret-token");

  const serialized = JSON.stringify(state.diagnostics);
  assert.equal(serialized.includes("super-secret-token"), false);
  assert.equal(serialized.includes("config-secret-value"), false);
  assert.ok(state.diagnostics.some((diagnostic) => diagnostic.code === "secret_resolved" && diagnostic.found === true));
});

test("runtime fetch enforces allowlist and records deterministic diagnostics", async () => {
  const deniedState = createRuntimeState({ fetchPolicy: { allow: ["https://allowed.example"] } });
  const deniedRuntime = createRuntimeFacets(deniedState, "fixture-plugin");

  const denied = await deniedRuntime.fetch("https://blocked.example/data");
  assert.equal(denied.ok, false);
  assert.equal(denied.status, "blocked");
  assert.ok(deniedState.diagnostics.some((diagnostic) => diagnostic.code === "fetch_denied"));

  const allowedState = createRuntimeState({
    fetchPolicy: { allow: ["https://allowed.example"] },
    fetchImpl: async (url, init) => ({
      ok: true,
      status: 202,
      headers: new Map([["content-type", "application/json"]]),
      text: async () => JSON.stringify({ url: String(url), method: init.method }),
    }),
  });
  const allowedRuntime = createRuntimeFacets(allowedState, "fixture-plugin");

  const allowed = await allowedRuntime.fetch("https://allowed.example/data", { method: "POST" });
  assert.equal(allowed.ok, true);
  assert.equal(allowed.status, 202);
  assert.deepEqual(JSON.parse(allowed.body), { url: "https://allowed.example/data", method: "POST" });
});

test("runtime media creates file refs and resolves stored content", async () => {
  const state = createRuntimeState({ permissions: { media: true } });
  const runtime = createRuntimeFacets(state, "fixture-plugin");

  const uploaded = await runtime.media.upload({
    name: "note.txt",
    mimeType: "text/plain",
    content: "hello media",
  });

  assert.equal(uploaded.ok, true);
  assert.equal(uploaded.ref.name, "note.txt");
  assert.equal(uploaded.ref.mimeType, "text/plain");
  assert.equal(uploaded.ref.uri.startsWith("metis://media/"), true);

  const resolved = await runtime.media.resolve(uploaded.ref.id);
  assert.deepEqual(resolved.ref, uploaded.ref);

  const downloaded = await runtime.media.download(uploaded.ref.id);
  assert.equal(downloaded.ok, true);
  assert.equal(downloaded.content, "hello media");
});

test("reply conversation thread and process facets use permission gates", async () => {
  const deniedState = createRuntimeState();
  const deniedRuntime = createRuntimeFacets(deniedState, "fixture-plugin");

  assert.equal((await deniedRuntime.reply.send({ text: "hi" })).status, "permission_denied");
  assert.equal((await deniedRuntime.conversation.get("conversation-1")).status, "permission_denied");
  assert.equal((await deniedRuntime.thread.get("thread-1")).status, "permission_denied");
  assert.equal((await deniedRuntime.process.spawn({ command: "node" })).status, "permission_denied");

  const allowedState = createRuntimeState({
    permissions: { reply: true, conversation: true, thread: true, process: true },
    adapters: {
      reply: { send: async (message) => ({ ok: true, id: "reply-1", text: message.text }) },
      conversation: { get: async (id) => ({ ok: true, id, title: "Conversation" }) },
      thread: { get: async (id) => ({ ok: true, id, title: "Thread" }) },
      process: { spawn: async (request) => ({ ok: true, pid: 123, command: request.command }) },
    },
  });
  const allowedRuntime = createRuntimeFacets(allowedState, "fixture-plugin");

  assert.deepEqual(await allowedRuntime.reply.send({ text: "hi" }), { ok: true, id: "reply-1", text: "hi" });
  assert.deepEqual(await allowedRuntime.conversation.get("conversation-1"), {
    ok: true,
    id: "conversation-1",
    title: "Conversation",
  });
  assert.deepEqual(await allowedRuntime.thread.get("thread-1"), { ok: true, id: "thread-1", title: "Thread" });
  assert.deepEqual(await allowedRuntime.process.spawn({ command: "node" }), { ok: true, pid: 123, command: "node" });
});

test("allowed but unwired runtime facets return not_applicable diagnostics instead of fake success", async () => {
  const state = createRuntimeState({
    permissions: { reply: true, conversation: true, thread: true, process: true },
  });
  const runtime = createRuntimeFacets(state, "fixture-plugin");

  assert.equal((await runtime.reply.send({ text: "hi" })).status, "not_applicable");
  assert.equal((await runtime.conversation.get("conversation-1")).status, "not_applicable");
  assert.equal((await runtime.thread.get("thread-1")).status, "not_applicable");
  assert.equal((await runtime.process.spawn({ command: "node" })).status, "not_applicable");

  assert.ok(state.diagnostics.some((diagnostic) => diagnostic.code === "runtime_facet_not_applicable" && diagnostic.facet === "reply"));
  assert.ok(state.diagnostics.some((diagnostic) => diagnostic.code === "runtime_facet_not_applicable" && diagnostic.facet === "process"));
});
