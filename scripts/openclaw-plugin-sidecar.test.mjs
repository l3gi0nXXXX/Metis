#!/usr/bin/env node

import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";

const sidecarPath = path.join(import.meta.dirname, "openclaw-plugin-sidecar.mjs");

function writePlugin(source) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "metis-openclaw-sidecar-test-"));
  const pluginRoot = path.join(root, "plugin");
  fs.mkdirSync(pluginRoot, { recursive: true });
  fs.writeFileSync(
    path.join(pluginRoot, "package.json"),
    JSON.stringify({ name: "fixture", type: "module", main: "index.mjs" }),
  );
  fs.writeFileSync(path.join(pluginRoot, "index.mjs"), source);
  return { root, pluginRoot };
}

function invoke(method, payload, pluginRoot) {
  const config = { enabled: true, plugins: [pluginRoot] };
  const request = { method, payload, config };
  const result = spawnSync(
    process.execPath,
    [
      sidecarPath,
      method,
      "--config-json",
      JSON.stringify(config),
      "--request-json",
      JSON.stringify(request),
    ],
    {
      encoding: "utf8",
      env: {
        ...process.env,
        HOME: fs.mkdtempSync(path.join(os.tmpdir(), "metis-openclaw-sidecar-home-")),
        METIS_HOME: fs.mkdtempSync(path.join(os.tmpdir(), "metis-openclaw-sidecar-metis-home-")),
      },
    },
  );
  assert.equal(result.status, 0, result.stderr);
  return JSON.parse(result.stdout);
}

test("OpenClaw-style command and two-argument hooks are normalized", () => {
  const { root, pluginRoot } = writePlugin(`
    export default function(api) {
      api.registerCommand({
        name: "demo",
        description: "Demo",
        handler: async (ctx) => ({ text: "cmd:" + ctx.args + ":" + ctx.isAuthorizedSender + ":" + ctx.messageThreadId }),
      });
      api.registerHook("message_sending", async (event, ctx) => ({ content: event.content + ":" + ctx.accountId }));
    }
  `);
  try {
    const command = invoke(
      "command.dispatch",
      {
        command: "demo",
        args: "alpha beta",
        commandBody: "/demo alpha beta",
        channel: "telegram",
        accountId: "default",
        isAuthorizedSender: true,
        messageThreadId: "42",
      },
      pluginRoot,
    );
    assert.equal(command.matched, true);
    assert.equal(command.intents[0].text, "cmd:alpha beta:true:42");

    const hook = invoke(
      "hook.message_sending",
      { channel: "telegram", accountId: "default", peerId: "group:-100", text: "hello", content: "hello" },
      pluginRoot,
    );
    assert.equal(hook.text, "hello:default");
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test("interactive respond contract and unsupported capabilities are structured", () => {
  const { root, pluginRoot } = writePlugin(`
    export default function(api) {
      api.registerTool({ name: "not_in_sidecar" });
      api.registerProvider({ name: "not_in_sidecar" });
      api.registerChannel({ name: "not_in_sidecar" });
      api.interactive.register({ namespace: "demo", channel: "telegram" }, async (ctx) => {
        const ack = await ctx.respond.answerCallbackQuery({ text: "ok" });
        await ctx.respond.reply({ text: "reply" });
        await ctx.respond.editMessage({ text: ack.status });
        await ctx.respond.editButtons({ buttons: [[{ text: "Next", callback_data: "plugin:demo:next" }]] });
        await ctx.respond.clearButtons();
        await ctx.respond.deleteMessage();
      });
    }
  `);
  try {
    const result = invoke(
      "interactive.dispatch",
      {
        data: "plugin:demo:run",
        callbackId: "cb-1",
        callbackMessage: { messageId: "77", chatId: "8734062810", messageText: "Choose" },
        senderId: "8734062810",
        auth: { isAuthorizedSender: true },
      },
      pluginRoot,
    );
    assert.equal(result.matched, true);
    assert.deepEqual(
      result.intents.map((intent) => intent.type),
      ["answer-callback-query", "reply", "edit", "edit-buttons", "clear-buttons", "delete"],
    );
    assert.equal(result.intents[0].callbackId, "cb-1");
    assert.deepEqual(
      result.diagnostics.map((diagnostic) => diagnostic.unsupportedCapability.capability),
      ["api.registerTool", "api.registerProvider", "api.registerChannel"],
    );

    const unsupported = invoke("sdk.missing", {}, pluginRoot);
    assert.equal(unsupported.status, "unsupported");
    assert.equal(unsupported.unsupportedCapability.capability, "sdk.missing");
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test("approval callback handlers use respond intents and parse decision before approval id", () => {
  const { root, pluginRoot } = writePlugin(`
    export default function(api) {
      api.approvals.register({ namespace: "demo", channel: "telegram" }, async (ctx) => {
        await ctx.respond.answerCallbackQuery({ text: "approval " + ctx.decision });
        await ctx.respond.editMessage({ text: "approval:" + ctx.decision + ":" + ctx.approvalId });
        await ctx.respond.clearButtons();
        return { type: "reply", text: "done" };
      });
    }
  `);
  try {
    const result = invoke(
      "approval.dispatch",
      {
        data: "plugin-approval:demo:allow:approval-1",
        callbackId: "cb-approval",
        callbackMessage: { messageId: "77", chatId: "8734062810", messageText: "Approve?" },
        senderId: "8734062810",
      },
      pluginRoot,
    );
    assert.equal(result.matched, true);
    assert.deepEqual(
      result.intents.map((intent) => intent.type),
      ["answer-callback-query", "edit", "clear-buttons", "reply"],
    );
    assert.equal(result.intents[1].text, "approval:allow:approval-1");
    assert.equal(result.intents[1].targetMessageId, "77");
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});
