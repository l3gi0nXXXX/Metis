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
  const deniedState = createRuntimeState({ permissions: { fetch: true }, fetchPolicy: { allow: ["https://allowed.example"] } });
  const deniedRuntime = createRuntimeFacets(deniedState, "fixture-plugin");

  const denied = await deniedRuntime.fetch("https://blocked.example/data");
  assert.equal(denied.ok, false);
  assert.equal(denied.status, "blocked");
  assert.ok(deniedState.diagnostics.some((diagnostic) => diagnostic.code === "fetch_denied"));

  const allowedState = createRuntimeState({
    permissions: { fetch: true },
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

test("runtime fetch requires an explicit network grant before policy evaluation", async () => {
  const state = createRuntimeState({
    permissions: { fetch: false },
    fetchPolicy: { allow: ["https://allowed.example"] },
    fetchImpl: async () => {
      throw new Error("fetchImpl must not run without a grant");
    },
  });
  const runtime = createRuntimeFacets(state, "fixture-plugin");

  const denied = await runtime.fetch("https://allowed.example/data");

  assert.equal(denied.ok, false);
  assert.equal(denied.status, "permission_denied");
  assert.equal(denied.facet, "fetch");
  assert.ok(state.diagnostics.some((diagnostic) => diagnostic.code === "permission_denied" && diagnostic.facet === "fetch"));
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
  assert.equal((await runtime.process.spawn({ command: "node" })).status, "authorized");

  assert.ok(state.diagnostics.some((diagnostic) => diagnostic.code === "runtime_facet_not_applicable" && diagnostic.facet === "reply"));
  assert.ok(state.diagnostics.some((diagnostic) => diagnostic.code === "process_sandbox_decision" && diagnostic.facet === "process"));
});

test("provider memory browser and realtime facets expose production bridge contracts", async () => {
  const deniedState = createRuntimeState();
  const deniedRuntime = createRuntimeFacets(deniedState, "fixture-plugin");

  assert.equal((await deniedRuntime.provider.listModels({ providerId: "openai" })).status, "permission_denied");
  assert.equal((await deniedRuntime.memory.search({ query: "metis" })).status, "permission_denied");
  assert.equal((await deniedRuntime.browser.open({ url: "https://example.com" })).status, "permission_denied");
  assert.equal((await deniedRuntime.realtime.connect({ url: "wss://example.com" })).status, "permission_denied");

  const allowedState = createRuntimeState({
    permissions: { provider: true, memory: true, browser: true, realtime: true },
    adapters: {
      provider: {
        listModels: async (request) => ({
          ok: true,
          contract: "metis.model-provider-registry.v1",
          providerId: request.providerId,
          models: ["openai:gpt-4o-mini"],
        }),
        stream: async (request) => ({
          ok: true,
          contract: "metis.model-provider-stream.v1",
          model: request.model,
          chunks: [{ kind: "delta", text: "hello" }],
        }),
        toolCall: async (request) => ({
          ok: true,
          contract: "metis.model-provider-tool-call.v1",
          name: request.name,
        }),
      },
      memory: {
        search: async (request) => ({
          ok: true,
          contract: "metis.memory-context-backend.v1",
          backendId: "memory-core",
          hits: [{ text: request.query, score: 1 }],
        }),
      },
    },
  });
  const allowedRuntime = createRuntimeFacets(allowedState, "fixture-plugin");

  assert.deepEqual(await allowedRuntime.provider.listModels({ providerId: "openai" }), {
    ok: true,
    contract: "metis.model-provider-registry.v1",
    providerId: "openai",
    models: ["openai:gpt-4o-mini"],
  });
  assert.equal((await allowedRuntime.provider.stream({ model: "openai:gpt-4o-mini" })).contract, "metis.model-provider-stream.v1");
  assert.equal((await allowedRuntime.provider.toolCall({ name: "search" })).contract, "metis.model-provider-tool-call.v1");
  assert.equal((await allowedRuntime.memory.search({ query: "metis" })).contract, "metis.memory-context-backend.v1");
  assert.equal((await allowedRuntime.browser.open({ url: "https://example.com" })).status, "not_applicable");
  assert.equal((await allowedRuntime.realtime.connect({ url: "wss://example.com" })).status, "not_applicable");
});

test("runtime adapters return redacted error evidence instead of leaking secrets", async () => {
  const state = createRuntimeState({
    secrets: { OPENCLAW_TOKEN: "super-secret-token" },
    permissions: { reply: true },
    adapters: {
      reply: {
        send: async () => {
          throw new Error("backend failed with super-secret-token");
        },
      },
    },
  });
  const runtime = createRuntimeFacets(state, "fixture-plugin");

  const result = await runtime.reply.send({ text: "hi" });

  assert.equal(result.ok, false);
  assert.equal(result.status, "runtime_error");
  assert.equal(result.facet, "reply");
  assert.equal(JSON.stringify(result).includes("super-secret-token"), false);
  assert.ok(state.diagnostics.some((diagnostic) => diagnostic.code === "runtime_adapter_error" && diagnostic.facet === "reply"));
  assert.equal(JSON.stringify(state.diagnostics).includes("super-secret-token"), false);
});

test("memory embedding facet exposes Metis embedding contract through grants", async () => {
  const deniedState = createRuntimeState();
  const deniedRuntime = createRuntimeFacets(deniedState, "fixture-plugin");
  assert.equal((await deniedRuntime.memory.embed({ text: "metis" })).status, "permission_denied");

  const allowedState = createRuntimeState({
    permissions: { memory: true },
    adapters: {
      memory: {
        embed: async (request) => ({
          ok: true,
          contract: "metis.memory-embedding-provider.v1",
          model: "fixture-embedding",
          input: request.text,
          embedding: [0.1, 0.2],
        }),
      },
    },
  });
  const allowedRuntime = createRuntimeFacets(allowedState, "fixture-plugin");

  assert.deepEqual(await allowedRuntime.memory.embed({ text: "metis" }), {
    ok: true,
    contract: "metis.memory-embedding-provider.v1",
    model: "fixture-embedding",
    input: "metis",
    embedding: [0.1, 0.2],
  });
});

test("process facet has sandbox evidence for granted but invalid spawn requests", async () => {
  const state = createRuntimeState({ permissions: { process: true } });
  const runtime = createRuntimeFacets(state, "fixture-plugin");

  const result = await runtime.process.spawn({ command: "" });

  assert.equal(result.ok, false);
  assert.equal(result.status, "invalid_request");
  assert.equal(result.contract, "metis.openclaw-sandbox.v1");
  assert.equal(result.facet, "process");
  assert.ok(state.diagnostics.some((diagnostic) => diagnostic.code === "process_sandbox_decision"));
});
