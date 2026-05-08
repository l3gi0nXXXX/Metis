#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

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

function readJson(raw, fallback = {}) {
  try {
    return raw ? JSON.parse(raw) : fallback;
  } catch {
    return fallback;
  }
}

function isObject(value) {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function resolvePluginRoots(config) {
  const roots = [];
  const configured = Array.isArray(config.plugins) ? config.plugins : [];
  for (const entry of configured) {
    if (typeof entry === "string" && entry.trim()) {
      roots.push(path.resolve(entry.trim()));
      continue;
    }
    if (isObject(entry) && typeof entry.root === "string" && entry.root.trim()) {
      roots.push(path.resolve(entry.root.trim()));
    }
  }
  return roots;
}

function resolveManifest(pluginRoot) {
  for (const name of ["openclaw.plugin.json", "metis.plugin.json", "package.json"]) {
    const file = path.join(pluginRoot, name);
    if (fs.existsSync(file)) {
      return { path: file, value: readJson(fs.readFileSync(file, "utf8"), {}) };
    }
  }
  return { path: "", value: {} };
}

function resolveEntry(pluginRoot, manifest) {
  const runtime = isObject(manifest.gatewayRuntime) ? manifest.gatewayRuntime : {};
  const candidates = [
    runtime.openclawEntry,
    runtime.pluginEntry,
    runtime.entry,
    manifest.entry,
    manifest.main,
    manifest.module,
  ];
  const packagePath = path.join(pluginRoot, "package.json");
  if (fs.existsSync(packagePath)) {
    const pkg = readJson(fs.readFileSync(packagePath, "utf8"), {});
    candidates.push(pkg.openclaw?.entry, pkg.metis?.pluginEntry, pkg.module, pkg.main);
  }
  candidates.push("dist/index.js", "index.js", "index.mjs");
  for (const candidate of candidates) {
    if (typeof candidate !== "string" || !candidate.trim()) {
      continue;
    }
    const resolved = path.isAbsolute(candidate) ? candidate : path.join(pluginRoot, candidate);
    if (fs.existsSync(resolved)) {
      return resolved;
    }
  }
  return "";
}

async function loadModule(file) {
  return import(pathToFileURL(file).href);
}

async function registerPlugin(pluginRoot, registry) {
  const manifest = resolveManifest(pluginRoot);
  const entry = resolveEntry(pluginRoot, manifest.value);
  const pluginId =
    String(manifest.value.id ?? manifest.value.name ?? path.basename(pluginRoot)).trim() || path.basename(pluginRoot);
  if (!entry) {
    registry.diagnostics.push({ pluginId, status: "skipped", reason: "entry_not_found", pluginRoot });
    return;
  }
  const api = buildApi(pluginId, pluginRoot, registry);
  try {
    const mod = await loadModule(entry);
    const exported = mod.default ?? mod.plugin ?? mod.openclawPlugin ?? mod;
    if (typeof exported === "function") {
      await exported(api);
    } else if (typeof exported?.register === "function") {
      await exported.register(api);
    } else if (typeof mod.register === "function") {
      await mod.register(api);
    } else if (isObject(exported)) {
      captureDeclarativePlugin(pluginId, exported, registry);
    }
    registry.plugins.push({ pluginId, pluginRoot, entry, manifestPath: manifest.path });
  } catch (error) {
    registry.diagnostics.push({ pluginId, status: "error", reason: String(error), pluginRoot, entry });
  }
}

function buildApi(pluginId, pluginRoot, registry) {
  const unsupportedRegistration = (capability) => (..._args) => {
    const result = unsupportedCapability(capability, {
      pluginId,
      reason: "not implemented by the Metis OpenClaw plugin compatibility sidecar",
    });
    registry.diagnostics.push({
      pluginId,
      status: "unsupported",
      reason: "unsupportedCapability",
      unsupportedCapability: result.unsupportedCapability,
    });
    return result;
  };
  const api = {
    pluginId,
    pluginRoot,
    registerInteractiveHandler(registration, handler) {
      const namespace = normalizeNamespace(registration?.namespace ?? registration?.id ?? registration?.name);
      const channel = String(registration?.channel ?? "telegram").trim().toLowerCase() || "telegram";
      if (!namespace || typeof handler !== "function") {
        registry.diagnostics.push({ pluginId, status: "error", reason: "invalid_interactive_handler" });
        return;
      }
      registry.interactive.push({ pluginId, channel, namespace, handler });
    },
    registerCommand(spec, handler) {
      const command = normalizeCommand(spec?.command ?? spec?.name);
      const description = String(spec?.description ?? spec?.summary ?? "Plugin command").trim() || "Plugin command";
      const effectiveHandler = typeof handler === "function" ? handler : spec?.handler;
      if (!command || typeof effectiveHandler !== "function") {
        registry.diagnostics.push({ pluginId, status: "error", reason: "invalid_command_handler" });
        return;
      }
      registry.commands.push({ pluginId, command, description, handler: effectiveHandler, requireAuth: spec?.requireAuth !== false });
    },
    registerMessageHook(kind, handler) {
      if (typeof handler === "function") {
        registry.hooks.push({ pluginId, kind: String(kind ?? "").trim(), handler });
      }
    },
    registerHook(events, handler) {
      const names = Array.isArray(events) ? events : [events];
      for (const event of names) {
        api.registerMessageHook(event, handler);
      }
    },
    registerApprovalHandler(registration, handler) {
      const namespace = normalizeNamespace(registration?.namespace ?? registration?.id ?? registration?.name);
      const channel = String(registration?.channel ?? "telegram").trim().toLowerCase() || "telegram";
      if (!namespace || typeof handler !== "function") {
        registry.diagnostics.push({ pluginId, status: "error", reason: "invalid_approval_handler" });
        return;
      }
      registry.approvals.push({ pluginId, channel, namespace, handler });
    },
    hooks: {
      message_sending(handler) {
        if (typeof handler === "function") {
          registry.hooks.push({ pluginId, kind: "message_sending", handler });
        }
      },
      message_sent(handler) {
        if (typeof handler === "function") {
          registry.hooks.push({ pluginId, kind: "message_sent", handler });
        }
      },
      message_received(handler) {
        if (typeof handler === "function") {
          registry.hooks.push({ pluginId, kind: "message_received", handler });
        }
      },
    },
    on(kind, handler) {
      api.registerMessageHook(kind, handler);
    },
    unsupportedCapability(capability, details = {}) {
      return unsupportedCapability(capability, { pluginId, ...details });
    },
    logger: {
      debug() {},
      info() {},
      warn() {},
      error() {},
    },
    runtime: {
      kind: "metis-openclaw-plugin-compat-sidecar",
      unsupportedCapability(capability, details = {}) {
        return unsupportedCapability(capability, { pluginId, ...details });
      },
    },
    registerTool: unsupportedRegistration("api.registerTool"),
    registerHttpRoute: unsupportedRegistration("api.registerHttpRoute"),
    registerChannel: unsupportedRegistration("api.registerChannel"),
    registerGatewayMethod: unsupportedRegistration("api.registerGatewayMethod"),
    registerCli: unsupportedRegistration("api.registerCli"),
    registerReload: unsupportedRegistration("api.registerReload"),
    registerNodeHostCommand: unsupportedRegistration("api.registerNodeHostCommand"),
    registerSecurityAuditCollector: unsupportedRegistration("api.registerSecurityAuditCollector"),
    registerService: unsupportedRegistration("api.registerService"),
    registerConfigMigration: unsupportedRegistration("api.registerConfigMigration"),
    registerAutoEnableProbe: unsupportedRegistration("api.registerAutoEnableProbe"),
    registerProvider: unsupportedRegistration("api.registerProvider"),
    registerSpeechProvider: unsupportedRegistration("api.registerSpeechProvider"),
    registerRealtimeTranscriptionProvider: unsupportedRegistration("api.registerRealtimeTranscriptionProvider"),
    registerRealtimeVoiceProvider: unsupportedRegistration("api.registerRealtimeVoiceProvider"),
    registerMediaUnderstandingProvider: unsupportedRegistration("api.registerMediaUnderstandingProvider"),
    registerImageGenerationProvider: unsupportedRegistration("api.registerImageGenerationProvider"),
    registerVideoGenerationProvider: unsupportedRegistration("api.registerVideoGenerationProvider"),
    registerMusicGenerationProvider: unsupportedRegistration("api.registerMusicGenerationProvider"),
    registerWebFetchProvider: unsupportedRegistration("api.registerWebFetchProvider"),
    registerWebSearchProvider: unsupportedRegistration("api.registerWebSearchProvider"),
    registerContextEngine: unsupportedRegistration("api.registerContextEngine"),
    registerMemoryPromptSection: unsupportedRegistration("api.registerMemoryPromptSection"),
    registerMemoryFlushPlan: unsupportedRegistration("api.registerMemoryFlushPlan"),
    registerMemoryRuntime: unsupportedRegistration("api.registerMemoryRuntime"),
    registerMemoryEmbeddingProvider: unsupportedRegistration("api.registerMemoryEmbeddingProvider"),
    onConversationBindingResolved: unsupportedRegistration("api.onConversationBindingResolved"),
    resolvePath(input) {
      return path.resolve(pluginRoot, String(input ?? ""));
    },
  };
  api.interactive = { register: api.registerInteractiveHandler };
  api.commands = { register: api.registerCommand };
  api.approvals = { register: api.registerApprovalHandler };
  return api;
}

function captureDeclarativePlugin(pluginId, exported, registry) {
  const commands = Array.isArray(exported.commands) ? exported.commands : [];
  for (const spec of commands) {
    if (!isObject(spec)) continue;
    const command = normalizeCommand(spec.command ?? spec.name);
    if (!command) continue;
    registry.commands.push({
      pluginId,
      command,
      description: String(spec.description ?? "Plugin command"),
      handler: async (ctx) => ({ intents: [{ type: "reply", text: `Plugin command ${command} accepted.` }], ctx }),
    });
  }
}

function normalizeNamespace(raw) {
  const value = String(raw ?? "").trim().toLowerCase();
  return /^[a-z0-9_.-]{1,48}$/.test(value) ? value : "";
}

function normalizeCommand(raw) {
  const value = String(raw ?? "").trim().replace(/^\/+/, "").toLowerCase();
  return /^[a-z0-9_]{1,32}$/.test(value) ? value : "";
}

function unsupportedCapability(capability, details = {}) {
  const name = String(capability ?? "").trim() || "unknown";
  return {
    ok: false,
    status: "unsupported",
    unsupportedCapability: {
      capability: name,
      runtime: "metis-openclaw-plugin-compat-sidecar",
      reason: String(details.reason ?? "not implemented by the Metis OpenClaw plugin compatibility sidecar"),
      pluginId: String(details.pluginId ?? ""),
    },
  };
}

function callbackNamespace(data) {
  const value = String(data ?? "").trim();
  if (value.startsWith("plugin:")) {
    return normalizeNamespace(value.split(":")[1] ?? "");
  }
  return normalizeNamespace(value.split(":")[0] ?? "");
}

function approvalNamespace(data) {
  const value = String(data ?? "").trim();
  if (value.startsWith("plugin-approval:")) {
    return normalizeNamespace(value.split(":")[1] ?? "");
  }
  if (value.startsWith("approval:")) {
    return normalizeNamespace(value.split(":")[1] ?? "");
  }
  return normalizeNamespace(value.split(":")[0] ?? "");
}

function approvalDecision(data) {
  const parts = String(data ?? "").trim().split(":");
  const last = parts[parts.length - 1] ?? "";
  const normalized = String(last).trim().toLowerCase();
  if (["allow", "approve", "approved", "allow-once", "allow-always"].includes(normalized)) {
    return normalized;
  }
  if (["deny", "denied", "reject", "rejected"].includes(normalized)) {
    return normalized;
  }
  return "";
}

async function buildRegistry(config) {
  const registry = { plugins: [], diagnostics: [], interactive: [], commands: [], hooks: [], approvals: [] };
  for (const root of resolvePluginRoots(config)) {
    await registerPlugin(root, registry);
  }
  return registry;
}

function normalizeIntent(value) {
  if (!isObject(value)) return null;
  const type = String(value.type ?? value.kind ?? "").trim();
  if (!type) return null;
  const out = {
    type,
    text: String(value.text ?? value.message ?? ""),
    targetMessageId: String(value.targetMessageId ?? value.messageId ?? ""),
    reason: String(value.reason ?? ""),
  };
  if (Array.isArray(value.buttons)) out.buttons = value.buttons;
  if (value.op != null) out.op = String(value.op);
  if (value.channel != null) out.channel = String(value.channel);
  if (value.sessionKey != null) out.sessionKey = String(value.sessionKey);
  if (value.conversationId != null) out.conversationId = String(value.conversationId);
  if (value.parentConversationId != null) out.parentConversationId = String(value.parentConversationId);
  if (value.threadId != null) out.threadId = String(value.threadId);
  if (value.ownerId != null) out.ownerId = String(value.ownerId);
  if (value.ttlMs != null) out.ttlMs = Number(value.ttlMs) || 0;
  if (isObject(value.binding)) out.binding = value.binding;
  return out;
}

function normalizeHandlerResult(value, collectedIntents = [], collectedBindingIntents = []) {
  if (typeof value === "string") {
    return {
      ok: true,
      matched: true,
      intents: [...collectedIntents, { type: "reply", text: value }],
      bindingIntents: collectedBindingIntents,
    };
  }
  if (!isObject(value)) {
    return { ok: true, matched: true, intents: collectedIntents, bindingIntents: collectedBindingIntents };
  }
  if (isObject(value.unsupportedCapability)) {
    return {
      ok: false,
      matched: true,
      status: "unsupported",
      unsupportedCapability: value.unsupportedCapability,
      reason: value.unsupportedCapability.reason ?? "unsupported OpenClaw plugin capability",
      intents: collectedIntents,
      bindingIntents: collectedBindingIntents,
    };
  }
  const intents = Array.isArray(value.intents)
    ? value.intents.map(normalizeIntent).filter(Boolean)
    : normalizeIntent(value)
      ? [normalizeIntent(value)]
      : typeof value.text === "string" || typeof value.content === "string"
        ? [{ type: "reply", text: String(value.text ?? value.content ?? "") }]
      : [];
  const bindingIntents = Array.isArray(value.bindingIntents)
    ? value.bindingIntents.map(normalizeIntent).filter(Boolean)
    : [];
  return {
    ok: value.ok !== false,
    matched: value.matched !== false,
    intents: [...collectedIntents, ...intents],
    bindingIntents: [...collectedBindingIntents, ...bindingIntents],
    message: value.message ?? "",
  };
}

function callbackPayload(data, namespace) {
  const value = String(data ?? "").trim();
  const prefix = value.startsWith("plugin:") ? `plugin:${namespace}:` : `${namespace}:`;
  return value.startsWith(prefix) ? value.slice(prefix.length) : "";
}

function callbackMessageId(payload) {
  return String(payload.callbackMessage?.messageId ?? payload.messageId ?? "").trim();
}

function conversationSnapshot(payload, overrides = {}) {
  return {
    channel: "telegram",
    accountId: String(overrides.accountId ?? payload.accountId ?? "").trim(),
    conversationId: String(overrides.conversationId ?? payload.conversationId ?? payload.peerId ?? "").trim(),
    parentConversationId: String(overrides.parentConversationId ?? payload.parentConversationId ?? "").trim(),
    threadId: String(overrides.threadId ?? payload.threadId ?? "").trim(),
    sessionKey: String(overrides.sessionKey ?? payload.sessionKey ?? "").trim(),
    ownerId: String(overrides.ownerId ?? payload.senderId ?? "").trim(),
  };
}

function buildInteractiveContext(payload, namespace, intents, bindingIntents) {
  const targetMessageId = callbackMessageId(payload);
  const pushIntent = (intent) => {
    const normalized = normalizeIntent({ targetMessageId, ...intent });
    if (normalized) intents.push(normalized);
  };
  const currentBinding = conversationSnapshot(payload, isObject(payload.currentConversationBinding) ? payload.currentConversationBinding : {});
  const ctx = {
    ...payload,
    channel: "telegram",
    accountId: String(payload.accountId ?? "").trim(),
    callbackId: String(payload.callbackId ?? "").trim(),
    conversationId: currentBinding.conversationId,
    parentConversationId: currentBinding.parentConversationId,
    senderId: String(payload.senderId ?? payload.callbackSenderId ?? "").trim(),
    senderUsername: String(payload.senderUsername ?? "").trim(),
    threadId: currentBinding.threadId,
    messageThreadId: String(payload.messageThreadId ?? currentBinding.threadId ?? "").trim(),
    isGroup: payload.isGroup === true,
    isForum: payload.isForum === true,
    auth: isObject(payload.auth) ? payload.auth : { isAuthorizedSender: false },
    callback: {
      data: String(payload.data ?? "").trim(),
      namespace,
      payload: callbackPayload(payload.data, namespace),
      messageId: targetMessageId,
      chatId: String(payload.callbackMessage?.chatId ?? "").trim(),
      messageText: String(payload.callbackMessage?.messageText ?? "").trim(),
    },
    respond: {
      async reply(params = {}) {
        pushIntent({ type: "reply", text: String(params.text ?? ""), buttons: params.buttons });
      },
      async editMessage(params = {}) {
        pushIntent({ type: "edit", text: String(params.text ?? ""), buttons: undefined });
        if (Array.isArray(params.buttons)) {
          pushIntent({ type: "edit-buttons", buttons: params.buttons });
        }
      },
      async editButtons(params = {}) {
        pushIntent({ type: "edit-buttons", buttons: params.buttons });
      },
      async clearButtons() {
        pushIntent({ type: "clear-buttons" });
      },
      async deleteMessage() {
        pushIntent({ type: "delete" });
      },
      async answerCallbackQuery(params = {}) {
        ctx.callbackAnswer = {
          ok: true,
          status: "already_acknowledged_by_gateway",
          callbackId: String(payload.callbackId ?? "").trim(),
          text: String(params.text ?? ""),
          showAlert: params.showAlert === true || params.show_alert === true,
        };
        return ctx.callbackAnswer;
      },
    },
    async requestConversationBinding(params = {}) {
      const binding = conversationSnapshot(payload, {
        ...params,
        sessionKey: params.sessionKey ?? payload.sessionKey,
        ownerId: params.ownerId ?? payload.senderId,
      });
      const intent = normalizeIntent({ type: "binding", op: "bind", ...binding, ttlMs: params.ttlMs ?? 0 });
      if (intent) bindingIntents.push(intent);
      return { ok: true, status: "queued", binding };
    },
    async detachConversationBinding() {
      const binding = conversationSnapshot(payload);
      const intent = normalizeIntent({ type: "binding", op: "detach", ...binding });
      if (intent) bindingIntents.push(intent);
      return { removed: true };
    },
    async getCurrentConversationBinding() {
      if (!currentBinding.conversationId || !currentBinding.sessionKey) return null;
      return currentBinding;
    },
    async touchConversationBinding() {
      const binding = conversationSnapshot(payload);
      const intent = normalizeIntent({ type: "binding", op: "touch", ...binding });
      if (intent) bindingIntents.push(intent);
      return { ok: true, status: "queued", binding };
    },
  };
  return ctx;
}

function commandArgs(payload) {
  if (typeof payload.args === "string") return payload.args.trim();
  if (Array.isArray(payload.args)) return payload.args.map((v) => String(v ?? "")).join(" ").trim();
  const body = String(payload.commandBody ?? payload.text ?? "").trim();
  return body.split(/\s+/).slice(1).join(" ").trim();
}

function commandArgv(payload) {
  if (Array.isArray(payload.argv)) return payload.argv.map((v) => String(v ?? ""));
  const args = commandArgs(payload);
  return args ? args.split(/\s+/) : [];
}

function buildCommandContext(payload, intents, bindingIntents) {
  const binding = conversationSnapshot(payload);
  const pushBindingIntent = (op, params = {}) => {
    const intent = normalizeIntent({ type: "binding", op, ...binding, ...params });
    if (intent) bindingIntents.push(intent);
    return intent;
  };
  return {
    ...payload,
    channel: String(payload.channel ?? "telegram").trim() || "telegram",
    accountId: String(payload.accountId ?? "").trim(),
    command: String(payload.command ?? "").trim(),
    args: commandArgs(payload),
    argv: commandArgv(payload),
    text: String(payload.text ?? payload.commandBody ?? "").trim(),
    commandBody: String(payload.commandBody ?? payload.text ?? "").trim(),
    from: String(payload.from ?? payload.senderId ?? "").trim(),
    to: String(payload.to ?? payload.peerId ?? payload.conversationId ?? "").trim(),
    senderId: String(payload.senderId ?? "").trim(),
    isAuthorizedSender: payload.isAuthorizedSender === true || payload.auth?.isAuthorizedSender === true,
    sessionKey: String(payload.sessionKey ?? "").trim(),
    messageThreadId: String(payload.messageThreadId ?? payload.threadId ?? "").trim(),
    respond: {
      async reply(params = {}) {
        const normalized = normalizeIntent({ type: "reply", text: String(params.text ?? ""), buttons: params.buttons });
        if (normalized) intents.push(normalized);
      },
      async editMessage(params = {}) {
        const normalized = normalizeIntent({ type: "edit", text: String(params.text ?? ""), targetMessageId: params.targetMessageId });
        if (normalized) intents.push(normalized);
      },
    },
    async requestConversationBinding(params = {}) {
      const intent = pushBindingIntent("bind", {
        sessionKey: params.sessionKey ?? payload.sessionKey,
        ownerId: params.ownerId ?? payload.senderId,
        ttlMs: params.ttlMs ?? 0,
      });
      return { ok: true, status: "queued", binding: intent?.binding ?? binding };
    },
    async detachConversationBinding() {
      pushBindingIntent("detach");
      return { removed: true };
    },
    async getCurrentConversationBinding() {
      if (!binding.conversationId || !binding.sessionKey) return null;
      return binding;
    },
  };
}

function hookMetadata(payload) {
  return {
    channel: String(payload.channel ?? "telegram"),
    accountId: String(payload.accountId ?? ""),
    peerId: String(payload.peerId ?? ""),
    conversationId: String(payload.conversationId ?? payload.peerId ?? ""),
    parentConversationId: String(payload.parentConversationId ?? ""),
    threadId: String(payload.threadId ?? payload.messageThreadId ?? ""),
    reply: isObject(payload.reply) ? payload.reply : undefined,
    mediaKinds: Array.isArray(payload.mediaKinds) ? payload.mediaKinds : undefined,
    mediaSummary: isObject(payload.mediaSummary) ? payload.mediaSummary : undefined,
    messageId: String(payload.messageId ?? payload.sentMessageId ?? ""),
    senderId: String(payload.senderId ?? ""),
  };
}

function hookContext(payload) {
  const metadata = hookMetadata(payload);
  return {
    channelId: metadata.channel,
    accountId: metadata.accountId,
    conversationId: metadata.conversationId,
    parentConversationId: metadata.parentConversationId,
    threadId: metadata.threadId,
    messageThreadId: metadata.threadId,
    peerId: metadata.peerId,
    senderId: metadata.senderId,
    metadata,
  };
}

function messageSendingEvent(payload) {
  return {
    to: String(payload.to ?? payload.peerId ?? payload.conversationId ?? ""),
    content: String(payload.content ?? payload.text ?? ""),
    metadata: hookMetadata(payload),
  };
}

function messageSentEvent(payload) {
  return {
    to: String(payload.to ?? payload.peerId ?? payload.conversationId ?? ""),
    content: String(payload.content ?? payload.text ?? ""),
    success: payload.success === true || payload.delivered === true,
    error: String(payload.error ?? payload.reason ?? ""),
    metadata: hookMetadata(payload),
  };
}

function messageReceivedEvent(payload) {
  return {
    from: String(payload.from ?? payload.senderId ?? payload.peerId ?? ""),
    content: String(payload.content ?? payload.text ?? ""),
    timestamp: Number(payload.timestamp ?? payload.receivedAtMs ?? 0) || undefined,
    metadata: hookMetadata(payload),
  };
}

async function runSidecarHook(hook, payload, event, ctx) {
  if (hook.handler.length >= 2) {
    return await hook.handler(event, ctx);
  }
  return await hook.handler({ ...payload, event, ctx, content: event.content, metadata: event.metadata });
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const method = String(args._[0] ?? "").trim();
  const config = readJson(String(args["config-json"] ?? ""), {});
  const request = readJson(String(args["request-json"] ?? ""), {});
  const payload = isObject(request.payload) ? request.payload : {};
  const registry = await buildRegistry(config);

  if (method === "lifecycle.start" || method === "lifecycle.stop" || method === "lifecycle.health") {
    process.stdout.write(
      JSON.stringify({
        ok: true,
        status: "ok",
        method,
        runtime: "node-sidecar",
        pluginCount: registry.plugins.length,
        diagnostics: registry.diagnostics,
      }),
    );
    return;
  }

  if (method === "handlers.list") {
    process.stdout.write(
      JSON.stringify({
        ok: true,
        handlers: registry.interactive.map((h) => ({
          pluginId: h.pluginId,
          channel: h.channel,
          namespace: h.namespace,
        })),
        approvals: registry.approvals.map((h) => ({
          pluginId: h.pluginId,
          channel: h.channel,
          namespace: h.namespace,
        })),
        diagnostics: registry.diagnostics,
      }),
    );
    return;
  }

  if (method === "commands.list") {
    process.stdout.write(
      JSON.stringify({
        ok: true,
        commands: registry.commands.map((c) => ({
          pluginId: c.pluginId,
          command: c.command,
          description: c.description,
        })),
        diagnostics: registry.diagnostics,
      }),
    );
    return;
  }

  if (method === "interactive.dispatch") {
    const namespace = callbackNamespace(payload.data);
    const telegramHandlers = registry.interactive.filter((h) => h.channel === "telegram");
    const handler = telegramHandlers.find((h) => h.namespace === namespace) ?? (telegramHandlers.length === 1 ? telegramHandlers[0] : null);
    if (!handler) {
      process.stdout.write(
        JSON.stringify({
          ok: true,
          matched: false,
          reason: "handler_not_found",
          namespace,
          handlers: telegramHandlers.map((h) => ({ pluginId: h.pluginId, namespace: h.namespace })),
          diagnostics: registry.diagnostics,
        }),
      );
      return;
    }
    const intents = [];
    const bindingIntents = [];
    const ctx = buildInteractiveContext(payload, namespace, intents, bindingIntents);
    const result = normalizeHandlerResult(await handler.handler(ctx), intents, bindingIntents);
    process.stdout.write(JSON.stringify({ ...result, pluginId: handler.pluginId, namespace, diagnostics: registry.diagnostics }));
    return;
  }

  if (method === "command.dispatch") {
    const command = normalizeCommand(payload.command);
    const handler = registry.commands.find((c) => c.command === command);
    if (!handler) {
      process.stdout.write(JSON.stringify({ ok: true, matched: false, reason: "command_not_found", diagnostics: registry.diagnostics }));
      return;
    }
    const intents = [];
    const bindingIntents = [];
    const result = normalizeHandlerResult(await handler.handler(buildCommandContext(payload, intents, bindingIntents)), intents, bindingIntents);
    process.stdout.write(JSON.stringify({ ...result, pluginId: handler.pluginId, command, diagnostics: registry.diagnostics }));
    return;
  }

  if (method === "approval.dispatch") {
    const namespace = approvalNamespace(payload.data);
    const telegramHandlers = registry.approvals.filter((h) => h.channel === "telegram");
    const handler = telegramHandlers.find((h) => h.namespace === namespace) ?? (telegramHandlers.length === 1 ? telegramHandlers[0] : null);
    if (!handler) {
      process.stdout.write(
        JSON.stringify({
          ok: true,
          matched: false,
          reason: "approval_handler_not_found",
          namespace,
          handlers: telegramHandlers.map((h) => ({ pluginId: h.pluginId, namespace: h.namespace })),
          diagnostics: registry.diagnostics,
        }),
      );
      return;
    }
    const result = normalizeHandlerResult(
      await handler.handler({
        ...payload,
        namespace,
        decision: payload.decision ?? approvalDecision(payload.data),
      }),
    );
    process.stdout.write(JSON.stringify({ ...result, pluginId: handler.pluginId, namespace, diagnostics: registry.diagnostics }));
    return;
  }

  if (method === "hook.message_sending") {
    let current = { ...payload };
    const hookErrors = [];
    for (const hook of registry.hooks.filter((h) => h.kind === "message_sending")) {
      const result = await runSidecarHook(hook, current, messageSendingEvent(current), hookContext(current)).catch((error) => {
        hookErrors.push({ pluginId: hook.pluginId, kind: hook.kind, reason: String(error) });
        return null;
      });
      if (isObject(result)) {
        if (result.cancelled === true || result.cancel === true) {
          process.stdout.write(
            JSON.stringify({
              ok: true,
              status: "cancelled",
              cancelled: true,
              reason: String(result.reason ?? "cancelled by plugin hook"),
              pluginId: hook.pluginId,
            }),
          );
          return;
        }
        if (typeof result.text === "string") {
          current.text = result.text;
        }
        if (typeof result.content === "string") {
          current.text = result.content;
          current.content = result.content;
        }
      }
    }
    process.stdout.write(JSON.stringify({ ok: true, status: "ok", cancelled: false, text: current.text, diagnostics: [...registry.diagnostics, ...hookErrors] }));
    return;
  }

  if (method === "hook.message_sent") {
    const hookErrors = [];
    for (const hook of registry.hooks.filter((h) => h.kind === "message_sent")) {
      try {
        await runSidecarHook(hook, payload, messageSentEvent(payload), hookContext(payload));
      } catch (error) {
        hookErrors.push({ pluginId: hook.pluginId, kind: hook.kind, reason: String(error) });
      }
    }
    process.stdout.write(JSON.stringify({ ok: true, status: "ok", diagnostics: [...registry.diagnostics, ...hookErrors] }));
    return;
  }

  if (method === "hook.message_received") {
    const hookErrors = [];
    for (const hook of registry.hooks.filter((h) => h.kind === "message_received" || h.kind === "message:received")) {
      try {
        await runSidecarHook(hook, payload, messageReceivedEvent(payload), hookContext(payload));
      } catch (error) {
        hookErrors.push({ pluginId: hook.pluginId, kind: hook.kind, reason: String(error) });
      }
    }
    process.stdout.write(JSON.stringify({ ok: true, status: "ok", diagnostics: [...registry.diagnostics, ...hookErrors] }));
    return;
  }

  process.stdout.write(JSON.stringify(unsupportedCapability(method, { reason: `unknown sidecar method: ${method}` })));
}

await main();
