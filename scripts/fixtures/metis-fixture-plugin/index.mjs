const plugin = {
  meta: {
    name: "Metis Fixture",
    channelIds: ["metis-fixture"],
  },
  config: {
    listAccountIds(cfg) {
      const ids = Array.isArray(cfg?.accountIds) && cfg.accountIds.length > 0 ? cfg.accountIds : ["fixture:default"];
      return ids;
    },
    defaultAccountId(cfg) {
      return typeof cfg?.defaultAccountId === "string" && cfg.defaultAccountId.trim()
        ? cfg.defaultAccountId.trim()
        : "fixture:default";
    },
    resolveAccount(cfg, accountId) {
      return {
        accountId,
        token: typeof cfg?.token === "string" ? cfg.token : "",
        channel: "metis-fixture",
      };
    },
    async isConfigured(account, cfg) {
      return Boolean((account?.token || cfg?.token || "").trim());
    },
  },
  status: {
    async probeAccount({ account, timeoutMs }) {
      const configured = Boolean((account?.token || "").trim());
      return {
        ok: configured,
        status: configured ? "ready" : "pending-config",
        timeoutMs,
      };
    },
    async auditAccount({ account, probe }) {
      const configured = Boolean((account?.token || "").trim());
      return {
        policyState: configured ? "routable" : "pending-config",
        remediationState: configured ? "ready" : "binding-review",
        actionsNeeded: !configured,
        constraints: [
          {
            name: "fixture-token",
            satisfied: configured,
            detail: configured ? "fixture token present" : "fixture token missing",
          },
        ],
        actions: configured
          ? []
          : [
              {
                action: "apply-fixture-setup",
                method: "plugins.setup.apply",
                params: {
                  pluginId: "metis-fixture",
                  config: {
                    token: "fixture-token",
                    accountIds: ["fixture:default"],
                    defaultAccountId: "fixture:default",
                  },
                },
              },
            ],
        probe,
      };
    },
    async issues({ account }) {
      const configured = Boolean((account?.token || "").trim());
      return configured
        ? []
        : [
            {
              code: "fixture-token-missing",
              severity: "error",
              detail: "fixture token missing",
            },
          ];
    },
  },
  actions: {
    async discover({ accountId }) {
      return [
        {
          action: "fixture-send-text",
          label: "Send Fixture Text",
          accountId,
          capability: "outbound.sendText",
        },
      ];
    },
    async dispatch({ accountId, action, payload }) {
      return {
        ok: action === "fixture-send-text",
        accountId,
        action,
        echoedText: typeof payload?.text === "string" ? payload.text : "",
      };
    },
  },
  directory: {
    async listPeersLive({ accountId }) {
      return [
        { id: "fixture-peer", name: "Fixture Peer", accountId },
        { id: "fixture-peer-2", name: "Fixture Peer 2", accountId },
      ];
    },
    async listGroupsLive({ accountId }) {
      return [{ id: "fixture-group", name: "Fixture Group", accountId }];
    },
    async listGroupMembers({ accountId, groupId }) {
      return [
        { id: "fixture-peer", groupId, accountId },
        { id: "fixture-peer-2", groupId, accountId },
      ];
    },
  },
  setup: {
    async validateInput(input) {
      return {
        ok: Boolean((input?.token || "").trim()),
        issues: Boolean((input?.token || "").trim()) ? [] : ["missing-token"],
      };
    },
    resolveAccountId(input) {
      return typeof input?.defaultAccountId === "string" && input.defaultAccountId.trim()
        ? input.defaultAccountId.trim()
        : "fixture:default";
    },
    async applyAccountConfig({ input }) {
      return {
        token: typeof input?.token === "string" ? input.token : "",
        accountIds:
          Array.isArray(input?.accountIds) && input.accountIds.length > 0
            ? input.accountIds
            : ["fixture:default"],
        defaultAccountId:
          typeof input?.defaultAccountId === "string" && input.defaultAccountId.trim()
            ? input.defaultAccountId.trim()
            : "fixture:default",
      };
    },
  },
  gateway: {
    async logoutAccount({ accountId }) {
      return {
        cleared: true,
        accountId,
        reason: "fixture-logout",
      };
    },
    async startAccount({ accountId }) {
      return { started: true, accountId };
    },
    async stopAccount({ accountId }) {
      return { stopped: true, accountId };
    },
  },
  outbound: {
    async sendText({ to, text, accountId }) {
      return {
        ok: Boolean(to && text && accountId),
        delivered: Boolean(to && text && accountId),
        targetId: to,
        accountId,
        textLength: typeof text === "string" ? text.length : 0,
      };
    },
  },
};

export default plugin;
