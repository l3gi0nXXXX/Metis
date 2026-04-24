#!/usr/bin/env node

import process from "node:process";
import path from "node:path";
import readline from "node:readline";
import { createRequire } from "node:module";

function parseArgs(argv) {
  const out = { _: [] };
  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    if (!token.startsWith("--")) {
      out._.push(token);
      continue;
    }
    const key = token.slice(2);
    const next = argv[i + 1];
    if (next == null || next.startsWith("--")) {
      out[key] = "true";
      continue;
    }
    out[key] = next;
    i += 1;
  }
  return out;
}

function readTrimmed(value) {
  return typeof value === "string" ? value.trim() : "";
}

function writeProtocol(frame) {
  process.stdout.write(`${JSON.stringify(frame)}\n`);
}

function writeStderr(text) {
  process.stderr.write(`[feishu-monitor] ${text}\n`);
}

function resolveDomain(Lark, raw) {
  const value = readTrimmed(raw).toLowerCase();
  if (!value || value === "feishu" || value === "https://open.feishu.cn") {
    return Lark.Domain.Feishu;
  }
  if (value === "lark" || value === "https://open.larksuite.com") {
    return Lark.Domain.Lark;
  }
  return readTrimmed(raw).replace(/\/+$/, "");
}

const args = parseArgs(process.argv.slice(2));
const sdkRoot = path.resolve(
  readTrimmed(args["sdk-root"]) ||
    path.resolve(path.dirname(new URL(import.meta.url).pathname), "..", "tools", "feishu-official-sdk"),
);

const requireFromSdkRoot = createRequire(path.join(sdkRoot, "package.json"));
const Lark = requireFromSdkRoot("@larksuiteoapi/node-sdk");

const originalConsole = {
  log: console.log.bind(console),
  info: console.info.bind(console),
  warn: console.warn.bind(console),
  error: console.error.bind(console),
};

console.log = (...items) => writeStderr(items.map(String).join(" "));
console.info = (...items) => writeStderr(items.map(String).join(" "));
console.warn = (...items) => writeStderr(items.map(String).join(" "));
console.error = (...items) => writeStderr(items.map(String).join(" "));

async function main() {
  const appId = readTrimmed(args["app-id"]);
  const appSecret = readTrimmed(args["app-secret"]);
  const verificationToken = readTrimmed(args["verification-token"]);
  const encryptKey = readTrimmed(args["encrypt-key"]);
  if (!appId || !appSecret) {
    throw new Error("missing --app-id / --app-secret");
  }

  const wsClient = new Lark.WSClient({
    appId,
    appSecret,
    domain: resolveDomain(Lark, args["domain"]),
    loggerLevel: Lark.LoggerLevel.error,
  });
  const eventDispatcher = new Lark.EventDispatcher({
    verificationToken,
    encryptKey,
  });

  let shuttingDown = false;

  const cleanup = (reason) => {
    if (shuttingDown) {
      return;
    }
    shuttingDown = true;
    try {
      wsClient.close();
    } catch (_err) {
      // best effort
    }
    writeProtocol({ type: "closed", reason });
  };

  process.on("SIGTERM", () => {
    cleanup("sigterm");
    process.exit(0);
  });
  process.on("SIGINT", () => {
    cleanup("sigint");
    process.exit(0);
  });
  process.on("uncaughtException", (err) => {
    writeProtocol({ type: "error", message: `uncaughtException: ${String(err)}` });
    cleanup("uncaught-exception");
    process.exit(1);
  });
  process.on("unhandledRejection", (err) => {
    writeProtocol({ type: "error", message: `unhandledRejection: ${String(err)}` });
  });

  const rl = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
  rl.on("line", (line) => {
    const trimmed = String(line ?? "").trim();
    if (!trimmed) return;
    try {
      const msg = JSON.parse(trimmed);
      if (msg?.type === "stop") {
        cleanup("stop");
        process.exit(0);
      }
    } catch (err) {
      writeProtocol({ type: "error", message: `invalid-control-frame: ${String(err)}` });
    }
  });

  eventDispatcher.register({
    "im.message.receive_v1": async (data) => {
      writeProtocol({
        type: "event",
        payload: {
          header: { event_type: "im.message.receive_v1" },
          event: data,
        },
      });
    },
    "im.chat.member.bot.added_v1": async (data) => {
      writeProtocol({ type: "log", level: "info", message: "bot-added", payload: data });
    },
    "im.chat.member.bot.deleted_v1": async (data) => {
      writeProtocol({ type: "log", level: "info", message: "bot-deleted", payload: data });
    },
  });

  originalConsole.error(
    `[feishu-monitor] starting sdkRoot=${sdkRoot} pid=${process.pid}`,
  );
  wsClient.start({ eventDispatcher });
  writeProtocol({ type: "ready" });
  await new Promise(() => {});
}

await main();
