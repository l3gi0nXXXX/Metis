export default async function register(api) {
  const token = await api.secrets.get("OPENCLAW_TOKEN");
  if (token !== "super-secret-token") {
    throw new Error("secret resolver did not return fixture token");
  }

  api.logger.info("fixture loaded", { token });

  await api.runtime.media.upload({ name: "capture.txt" });
  await api.runtime.fetch("https://example.invalid/openclaw");
  await api.runtime.reply.send({ text: "hello" });
  await api.runtime.conversation.get("conversation-1");
  await api.runtime.thread.get("thread-1");
  await api.runtime.process.spawn({ command: "noop" });

  api.registerTool({ name: "fixture.tool", description: "Fixture tool" }, async (input) => ({
    ok: true,
    tool: "fixture.tool",
    input,
  }));
  api.registerProvider({ id: "fixture-provider", kind: "model" }, {
    invoke: async (request) => ({ ok: true, provider: "fixture-provider", prompt: request.prompt }),
  });
  api.registerChannel({ id: "fixture-channel", type: "chat" }, {
    start: async (context) => ({ ok: true, status: "started", channelId: "fixture-channel", accountId: context.accountId }),
    stop: async () => ({ ok: true, status: "stopped", channelId: "fixture-channel" }),
    health: async () => ({ ok: true, status: "healthy", channelId: "fixture-channel" }),
    pullInbound: async () => ({ ok: true, messages: [{ id: "inbound-1", text: "fixture inbound", channelId: "fixture-channel" }] }),
    send: async (message) => ({ ok: true, sent: true, text: message.text }),
  });
  api.registerHook("message.received", async (payload) => ({ ok: true, hook: "message.received", text: payload.text }));
  api.registerCommand({ name: "fixture-command", description: "Fixture command" }, async () => ({ ok: true }));
  api.registerCli({ name: "fixture-cli" }, async () => 0);
  api.registerHttpRoute({ method: "GET", path: "/fixture" }, async (request) => ({ status: 200, body: `${request.method} ${request.path} ${request.body}` }));
  api.registerHttpHandler({ name: "fixture-http-handler" }, async () => ({ status: 200 }));
  api.registerInteractiveHandler({ id: "fixture-interactive" }, async () => ({ ok: true }));
  api.registerApprovalHandler({ id: "fixture-approval" }, async () => ({ ok: true }));
  api.registerMemoryEmbeddingProvider({ id: "fixture-memory" }, {});
  api.registerGatewayMethod({ name: "fixture.gateway" }, async () => ({ ok: true }));
  api.registerService({ id: "fixture-service", secretResolved: true }, {});
  api.registerWidget({ id: "fixture-widget" });
}
