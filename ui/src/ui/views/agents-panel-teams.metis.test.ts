/* @vitest-environment jsdom */

import { render } from "lit";
import { describe, expect, it, vi } from "vitest";
import {
  createEmptyAgentTeamBindingDraft,
  createEmptyAgentTeamDraft,
  createEmptyAgentTeamModelDraft,
  createEmptyAgentTeamWorkspaceDraft,
} from "../controllers/agent-teams.ts";
import { renderAgentTeamsPanel, type AgentTeamsPanelProps } from "./agents-panel-teams.ts";

function createProps(overrides: Partial<AgentTeamsPanelProps> = {}): AgentTeamsPanelProps {
  const members = [
    { agentId: "content-writer", role: "writer", name: "Writer" },
    { agentId: "content-reviewer", role: "reviewer", name: "Reviewer" },
  ];
  return {
    loading: false,
    saving: false,
    error: null,
    success: null,
    list: {
      count: 1,
      teams: [
        {
          id: "content",
          displayName: "Content Team",
          defaultAgentId: "content-writer",
          members,
          aliases: [{ alias: "@review", agentId: "content-reviewer" }],
          bindings: [{ agentId: "content-reviewer", match: { channel: "feishu" } }],
          broadcast: { enabled: true, members: ["content-writer", "content-reviewer"] },
        },
      ],
    },
    selectedId: "content",
    detail: {
      id: "content",
      displayName: "Content Team",
      defaultAgentId: "content-writer",
      members,
      aliases: [{ alias: "@review", agentId: "content-reviewer" }],
      bindings: [{ agentId: "content-reviewer", match: { channel: "feishu" } }],
      broadcast: { enabled: true, members: ["content-writer", "content-reviewer"] },
    },
    draft: {
      ...createEmptyAgentTeamDraft(),
      id: "content",
      displayName: "Content Team",
      defaultAgentId: "content-writer",
      membersJson: JSON.stringify(members),
      aliasesJson: '[{"alias":"@review","agentId":"content-reviewer"}]',
      bindingsJson: '[{"agentId":"content-reviewer","match":{"channel":"feishu"}}]',
      broadcastJson: '{"enabled":true,"members":["content-writer","content-reviewer"]}',
    },
    binding: createEmptyAgentTeamBindingDraft(),
    bindingPreview: null,
    bindingResult: null,
    modelLoading: false,
    modelError: null,
    modelResult: {
      models: {
        agentId: "content-writer",
        path: "/tmp/metis/agents/content-writer/agent/models.json",
        present: true,
        primaryModelRef: "openai:gpt-5-mini",
        runtimePrimaryModelRef: "openai:gpt-5-mini",
        providerCount: 2,
        credentialSource: {
          status: "configured",
          source: "agent auth-profiles.json",
          authorization: "Authorization: Bearer model-secret-token",
        },
        state: {
          providers: [
            {
              provider: "openai",
              displayName: "OpenAI",
              runtimeProvider: "openai",
              defaultModelRef: "openai:gpt-5-mini",
              configured: true,
            },
            {
              provider: "qwen",
              displayName: "Qwen",
              runtimeProvider: "modelstudio",
              defaultModelRef: "qwen:qwen-plus",
              configured: false,
            },
          ],
        },
      },
    },
    modelDraft: createEmptyAgentTeamModelDraft(),
    workspaceLoading: false,
    workspaceSaving: false,
    workspaceError: null,
    workspace: {
      ...createEmptyAgentTeamWorkspaceDraft(),
      agentId: "content-writer",
      fileName: "SOUL.md",
    },
    feishuAuthLoading: false,
    feishuAuthError: null,
    feishuAuthResult: null,
    channelsSnapshot: {
      ts: 1,
      channelOrder: ["feishu"],
      channelLabels: { feishu: "Feishu" },
      channels: {
        feishu: {
          configured: true,
          running: true,
          capabilities: ["oauth:device-flow", "oapi:docs", "doctor"],
          auth: {
            accountId: "tenant-a",
            status: "authorized",
            tokenStatus: "authorized",
            scopeSummary: "docs:read im:message",
            accessToken: "secret-feishu-access-token",
          },
          doctor: {
            status: "ok",
            findings: 0,
            lastProbeAt: 123,
          },
        },
      },
      channelAccounts: {
        feishu: [
          {
            accountId: "tenant-a",
            name: "Tenant A",
            configured: true,
            running: true,
            lastError: "Authorization: Bearer secret-access-token failed",
          },
        ],
      },
      channelDefaultAccountId: { feishu: "tenant-a" },
    },
    configForm: {
      gateway: {
        feishu: {
          defaultAccountId: "tenant-a",
          threadSession: "enabled",
          groups: { "chat:oc_123": {} },
        },
      },
    },
    onRefresh: vi.fn(),
    onSelectTeam: vi.fn(),
    onNewTeam: vi.fn(),
    onDraftChange: vi.fn(),
    onCreateTeam: vi.fn(),
    onUpdateTeam: vi.fn(),
    onDeleteTeam: vi.fn(),
    onBindingChange: vi.fn(),
    onPreviewBinding: vi.fn(),
    onApplyBinding: vi.fn(),
    onModelDraftChange: vi.fn(),
    onLoadModel: vi.fn(),
    onSaveModel: vi.fn(),
    onWorkspaceChange: vi.fn(),
    onLoadWorkspaceFiles: vi.fn(),
    onLoadWorkspaceFile: vi.fn(),
    onSaveWorkspaceFile: vi.fn(),
    onStartFeishuOAuth: vi.fn(),
    ...overrides,
  };
}

describe("renderAgentTeamsPanel", () => {
  it("renders dashboard counts, broadcast controls, profile files, and Feishu gap state", () => {
    const container = document.createElement("div");
    render(renderAgentTeamsPanel(createProps()), container);

    const text = container.textContent ?? "";
    expect(text).toContain("2 members");
    expect(text).toContain("1 alias");
    expect(text).toContain("1 binding");
    expect(text).toContain("Broadcast enabled");
    expect(text).toContain("Guided workflow");
    expect(text).toContain("Select all members");
    expect(text).toContain("Clear selected");
    expect(text).toContain("Capability gaps");
    expect(text).toContain("OAuth available");
    expect(text).toContain("/feishu doctor");
    expect(text).toContain("Team-agent parity is partial");
    expect(text).toContain("Model provider chips");
    expect(text).toContain("OpenAI");
    expect(text).toContain("Qwen");
    expect(text).toContain("openai:gpt-5-mini");
    expect(text).toContain("agent auth-profiles.json");
    expect(text).toContain("Metis capabilities");
    expect(text).toContain("feishu_im_user_fetch_resource");
    expect(text).toContain("Workspace profile files");
    expect(text).toContain("Feishu Auth & Doctor");
    expect(text).toContain("Start OAuth via Gateway");
    expect(text).toContain("Missing setup steps");
    expect(text).toContain("Confirm Feishu app credentials");
    expect(text).toContain("Grant offline_access and OAPI scopes");
    expect(text).toContain("authorized");
    expect(text).toContain("docs:read im:message");
    expect(text).toContain("[redacted]");
    expect(text).not.toContain("secret-access-token");
    expect(text).not.toContain("model-secret-token");
    expect(text).not.toContain("secret-feishu-access-token");

    const options = Array.from(container.querySelectorAll("option")).map(
      (option) => option.textContent ?? "",
    );
    expect(options).toContain("SOUL.md");
    expect(options).toContain("IDENTITY.md");
    expect(options).toContain("USER.md");
    expect(options).toContain("TOOLS.md");
    expect(options).toContain("AGENTS.md");
    expect(options).toContain("HEARTBEAT.md");
    expect(options).toContain("BOOTSTRAP.md");
    expect(options).toContain("MEMORY.md");
  });

  it("renders Team Wizard templates and wires channel route presets", () => {
    const onBindingChange = vi.fn();
    const onDraftChange = vi.fn();
    const container = document.createElement("div");
    render(renderAgentTeamsPanel(createProps({ onBindingChange, onDraftChange })), container);

    const text = container.textContent ?? "";
    expect(text).toContain("Team Wizard");
    expect(text).toContain("Template library");
    expect(text).toContain("内容");
    expect(text).toContain("研发");
    expect(text).toContain("客服");
    expect(text).toContain("数据");
    expect(text).toContain("运营");
    expect(text).toContain("Feishu content handoff");
    expect(text).toContain("Engineering sprint");
    expect(text).toContain("Data insight report");
    expect(text).toContain("Ops campaign launch");
    expect(text).toContain("Telegram support triage");
    expect(text).toContain("IM team commands");
    expect(text).toContain("/agents team");
    expect(text).toContain("/agents status");
    expect(text).toContain("/agents switch @writer");
    expect(text).toContain("Export template JSON");
    expect(text).toContain("Import template JSON");

    const feishuButton = Array.from(container.querySelectorAll("button")).find((entry) =>
      (entry.textContent ?? "").includes("Seed Feishu route"),
    );
    expect(feishuButton).toBeTruthy();
    feishuButton?.click();
    expect(onBindingChange).toHaveBeenCalledWith({
      channel: "feishu",
      accountId: "tenant-a",
      peerKind: "group",
      useStructuredBinding: true,
      team: "content",
    });

    const telegramButton = Array.from(container.querySelectorAll("button")).find((entry) =>
      (entry.textContent ?? "").includes("Seed Telegram route"),
    );
    expect(telegramButton).toBeTruthy();
    telegramButton?.click();
    expect(onBindingChange).toHaveBeenCalledWith({
      channel: "telegram",
      accountId: "default",
      peerKind: "group",
      useStructuredBinding: true,
      team: "content",
    });
  });

  it("renders manual evidence and external resource readiness panels", () => {
    const container = document.createElement("div");
    render(renderAgentTeamsPanel(createProps()), container);

    const text = container.textContent ?? "";
    expect(text).toContain("Manual acceptance / evidence pack");
    expect(text).toContain("local-pass");
    expect(text).toContain("operator-record-required");
    expect(text).toContain("scripts/agentteam-manual-acceptance-gate.sh");
    expect(text).toContain("External resource readiness");
    expect(text).toContain("Telegram bot, DM, group, topic, and broadcast");
    expect(text).toContain("Feishu existing app/bot and two accountIds");
    expect(text).toContain("Feishu OAuth, OAPI scopes, and low-risk resources");
    expect(text).toContain("Feishu CardKit and rich event live smoke");
    expect(text).toContain("external-resource-required");
    expect(text).toContain("Control UI provides guided setup and linking an existing Feishu bot");
    expect(text).toContain("does not create a Feishu app or bot");
    expect(text).toContain("Gateway RPC only");
    expect(text).not.toContain("secret-feishu-access-token");
  });

  it("renders a channel readiness board and binding conflict preview", () => {
    const container = document.createElement("div");
    render(
      renderAgentTeamsPanel(
        createProps({
          draft: {
            ...createEmptyAgentTeamDraft(),
            id: "content",
            displayName: "Content Team",
            defaultAgentId: "content-writer",
            membersJson:
              '[{"agentId":"content-writer","role":"writer","name":"Writer"},{"agentId":"content-reviewer","role":"reviewer","name":"Reviewer"}]',
            aliasesJson: '[{"alias":"@writer","agentId":"content-writer"}]',
            bindingsJson:
              '[{"agentId":"content-writer","match":{"channel":"feishu","accountId":"tenant-a","peer":{"kind":"group","id":"chat:oc_123"},"teamId":"content"}}]',
            broadcastJson: '{"enabled":true,"members":["content-writer","content-reviewer"]}',
          },
          binding: {
            ...createEmptyAgentTeamBindingDraft(),
            agentId: "content-reviewer",
            useStructuredBinding: true,
            channel: "feishu",
            accountId: "tenant-a",
            peer: "chat:oc_123",
            team: "content",
          },
          channelsSnapshot: {
            ts: 1,
            channelOrder: ["telegram", "feishu"],
            channelLabels: { telegram: "Telegram", feishu: "Feishu" },
            channels: {
              telegram: { configured: true, running: true },
              feishu: {
                configured: false,
                running: false,
                auth: {
                  status: "scope_missing",
                  missingAppScopes: ["im:message"],
                  missingUserScopes: ["offline_access"],
                },
              },
            },
            channelAccounts: {
              telegram: [{ accountId: "bot-a", configured: true, running: true }],
              feishu: [],
            },
            channelDefaultAccountId: { telegram: "bot-a" },
          },
        }),
      ),
      container,
    );

    const text = container.textContent ?? "";
    expect(text).toContain("Channel readiness board");
    expect(text).toContain("1 ready · 1 needs repair");
    expect(text).toContain("Telegram");
    expect(text).toContain("Collect live Telegram DM, group, topic, and broadcast evidence.");
    expect(text).toContain("Feishu");
    expect(text).toContain("Configure an existing Feishu app/bot behind Gateway.");
    expect(text).toContain("Grant app scopes: im:message.");
    expect(text).toContain("Binding conflict preview");
    expect(text).toContain("1 conflict");
    expect(text).toContain("Route already targets another member");
    expect(text).toContain("assigned to content-writer");
    expect(text).toContain("Change the member, account, peer, thread, or team before applying this binding.");
    expect(text).not.toContain("Create Feishu app/bot automatically");
  });

  it("renders member detail and health summary without leaking secrets", () => {
    const container = document.createElement("div");
    render(
      renderAgentTeamsPanel(
        createProps({
          draft: {
            ...createEmptyAgentTeamDraft(),
            id: "content",
            displayName: "Content Team",
            defaultAgentId: "content-writer",
            membersJson:
              '[{"agentId":"content-writer","role":"writer","name":"Writer"},{"agentId":"content-reviewer","role":"reviewer","name":"Reviewer"},{"agentId":"missing-model","role":"analyst","name":"Analyst"}]',
            aliasesJson: '[{"alias":"@writer","agentId":"content-writer"},{"alias":"/agent review","agentId":"content-reviewer"}]',
            bindingsJson:
              '[{"agentId":"content-writer","match":{"channel":"feishu"}},{"agentId":"missing-route","match":{"channel":"telegram"}}]',
            broadcastJson: '{"enabled":true,"members":["content-writer"]}',
          },
        }),
      ),
      container,
    );

    const text = container.textContent ?? "";
    expect(text).toContain("Team health summary");
    expect(text).toContain("Routing conflicts");
    expect(text).toContain("missing-route");
    expect(text).toContain("Missing profiles");
    expect(text).toContain("missing-model");
    expect(text).toContain("Missing model");
    expect(text).toContain("Missing auth");
    expect(text).toContain("Feishu readiness");
    expect(text).toContain("Member details");
    expect(text).toContain("@writer");
    expect(text).toContain("/agent review");
    expect(text).toContain("default");
    expect(text).toContain("broadcast");
    expect(text).not.toContain("secret-feishu-access-token");
  });

  it("renders explicit Doctor repair rows for Feishu and team readiness gaps", () => {
    const onStartFeishuOAuth = vi.fn();
    const container = document.createElement("div");
    render(
      renderAgentTeamsPanel(
        createProps({
          onStartFeishuOAuth,
          draft: {
            ...createEmptyAgentTeamDraft(),
            id: "content",
            displayName: "Content Team",
            membersJson: '[{"agentId":"content-writer","role":"writer"}]',
            bindingsJson: "[]",
          },
          channelsSnapshot: {
            ts: 1,
            channelOrder: ["feishu"],
            channelLabels: { feishu: "Feishu" },
            channels: {
              feishu: {
                configured: true,
                running: true,
                auth: {
                  accountId: "tenant-a",
                  status: "missing_oauth",
                  missingAppScopes: ["im:message"],
                  missingUserScopes: ["offline_access"],
                },
                doctor: {
                  status: "warning",
                  findings: [
                    { code: "disabled_group_policy", message: "group policy disabled" },
                  ],
                },
              },
            },
            channelAccounts: { feishu: [] },
            channelDefaultAccountId: { feishu: "tenant-a" },
          },
          configForm: {
            gateway: {
              feishu: {
                defaultAccountId: "tenant-a",
                groups: {},
              },
            },
          },
        }),
      ),
      container,
    );

    const text = container.textContent ?? "";
    expect(text).toContain("Missing OAuth");
    expect(text).toContain("Missing app scope");
    expect(text).toContain("Missing user scope");
    expect(text).toContain("Missing channel account");
    expect(text).toContain("Disabled group policy");
    expect(text).toContain("Missing binding");
    expect(text).toContain("Repair actions never write token, secret, or auth files from the browser.");

    const startOAuth = Array.from(container.querySelectorAll("button")).find((entry) =>
      (entry.textContent ?? "").includes("Start OAuth"),
    );
    expect(startOAuth).toBeTruthy();
    startOAuth?.click();
    expect(onStartFeishuOAuth).toHaveBeenCalledWith("tenant-a");
  });

  it("renders cultivation memory, heartbeat, and recent doctor findings baseline", () => {
    const container = document.createElement("div");
    render(
      renderAgentTeamsPanel(
        createProps({
          workspace: {
            ...createEmptyAgentTeamWorkspaceDraft(),
            agentId: "content-writer",
            workspace: "/tmp/metis/content-writer",
            fileName: "MEMORY.md",
            draft: "Remember launch positioning. Authorization: Bearer secret-memory-token",
            files: [
              { name: "MEMORY.md", path: "/tmp/metis/content-writer/MEMORY.md", missing: false },
              { name: "HEARTBEAT.md", path: "/tmp/metis/content-writer/HEARTBEAT.md", missing: false },
            ],
          },
          channelsSnapshot: {
            ts: 1,
            channelOrder: ["feishu"],
            channelLabels: { feishu: "Feishu" },
            channels: {
              feishu: {
                configured: true,
                running: true,
                doctor: {
                  status: "warning",
                  lastProbeAt: 1710000100000,
                  findings: [
                    {
                      code: "app_scope_missing",
                      message: "Authorization: Bearer secret-doctor-token missing im:message",
                    },
                  ],
                },
              },
            },
            channelAccounts: {
              feishu: [{ accountId: "tenant-a", configured: true, running: true }],
            },
            channelDefaultAccountId: { feishu: "tenant-a" },
          },
        }),
      ),
      container,
    );

    const text = container.textContent ?? "";
    expect(text).toContain("Cultivation, Memory & Heartbeat");
    expect(text).toContain("MEMORY.md loaded");
    expect(text).toContain("HEARTBEAT.md present");
    expect(text).toContain("Memory preview");
    expect(text).toContain("Remember launch positioning");
    expect(text).toContain("Recent doctor findings");
    expect(text).toContain("app_scope_missing");
    expect(text).toContain("Bearer [redacted]");
    expect(text).not.toContain("secret-memory-token");
    expect(text).not.toContain("secret-doctor-token");
  });

  it("wires Feishu OAuth start to a Gateway RPC callback", () => {
    const onStartFeishuOAuth = vi.fn();
    const container = document.createElement("div");
    render(renderAgentTeamsPanel(createProps({ onStartFeishuOAuth })), container);

    const button = Array.from(container.querySelectorAll("button")).find((entry) =>
      (entry.textContent ?? "").includes("Start OAuth via Gateway"),
    );
    expect(button).toBeTruthy();
    button?.click();

    expect(onStartFeishuOAuth).toHaveBeenCalledWith("tenant-a");
  });

  it("wires Feishu OAuth lifecycle buttons to explicit Gateway RPC actions", () => {
    const onStartFeishuOAuth = vi.fn();
    const container = document.createElement("div");
    render(renderAgentTeamsPanel(createProps({ onStartFeishuOAuth })), container);

    const buttons = Array.from(container.querySelectorAll("button"));
    for (const [label, action] of [
      ["Status", "status"],
      ["Poll", "poll"],
      ["Complete", "complete"],
      ["Revoke local auth", "revoke"],
    ] as const) {
      const button = buttons.find((entry) => (entry.textContent ?? "").includes(label));
      expect(button).toBeTruthy();
      button?.click();
      expect(onStartFeishuOAuth).toHaveBeenLastCalledWith("tenant-a", action);
    }
  });

  it("shows explicit fallback rows when Feishu auth status RPC fields are absent", () => {
    const container = document.createElement("div");
    render(
      renderAgentTeamsPanel(
        createProps({
          channelsSnapshot: {
            ts: 1,
            channelOrder: ["feishu"],
            channelLabels: { feishu: "Feishu" },
            channels: { feishu: { configured: true, running: true } },
            channelAccounts: { feishu: [] },
            channelDefaultAccountId: { feishu: "tenant-a" },
          },
        }),
      ),
      container,
    );

    const text = container.textContent ?? "";
    expect(text).toContain("Feishu Auth & Doctor");
    expect(text).toContain("Auth status RPC missing");
    expect(text).toContain("Doctor status RPC missing");
    expect(text).toContain("UI will not write token files");
  });

  it("renders the Feishu setup wizard with missing configuration guidance", () => {
    const container = document.createElement("div");
    render(
      renderAgentTeamsPanel(
        createProps({
          channelsSnapshot: {
            ts: 1,
            channelOrder: ["feishu"],
            channelLabels: { feishu: "Feishu" },
            channels: { feishu: { configured: false, running: false } },
            channelAccounts: { feishu: [] },
            channelDefaultAccountId: {},
          },
          configForm: { gateway: { feishu: {} } },
        }),
      ),
      container,
    );

    const text = container.textContent ?? "";
    expect(text).toContain("Feishu setup/repair wizard");
    expect(text).toContain("Link existing Feishu app/bot");
    expect(text).toContain("Associate existing app/bot");
    expect(text).toContain("App credentials");
    expect(text).toContain("Event subscription");
    expect(text).toContain("Scope repair");
    expect(text).toContain("Group/thread routing");
    expect(text).toContain("OAuth device flow");
    expect(text).toContain("OAPI readiness");
    expect(text).toContain("Card readiness");
    expect(text).toContain("Open Feishu developer console");
    expect(text).toContain("copyable repair steps");
    expect(text).toContain("Gateway RPC or operator-managed backend configuration");
    expect(text).toContain("AGENTS.md");
    expect(text).toContain("BOOTSTRAP.md");
    expect(text).not.toContain("secret-feishu-access-token");
    expect(text).not.toContain("Authorization: Bearer secret");
  });

  it("renders a management-console empty state with honest Feishu setup boundaries", () => {
    const container = document.createElement("div");
    render(
      renderAgentTeamsPanel(
        createProps({
          error: "Gateway RPC failed",
          list: { count: 0, teams: [] },
          selectedId: null,
          detail: null,
          draft: createEmptyAgentTeamDraft(),
          channelsSnapshot: {
            ts: 1,
            channelOrder: ["feishu", "telegram"],
            channelLabels: { feishu: "Feishu", telegram: "Telegram" },
            channels: {
              feishu: { configured: false, running: false },
              telegram: { configured: true, running: true },
            },
            channelAccounts: { feishu: [], telegram: [{ accountId: "bot-a", running: true }] },
            channelDefaultAccountId: { telegram: "bot-a" },
          },
        }),
      ),
      container,
    );

    const text = container.textContent ?? "";
    expect(text).toContain("Agent Team Management");
    expect(text).toContain("Start with a template");
    expect(text).toContain("No teams are configured yet");
    expect(text).toContain("Create from a template or import a Metis team template");
    expect(text).toContain("Gateway RPC failed");
    expect(text).toContain("Repair first");
    expect(text).toContain("Control UI cannot automatically create a Feishu app or bot");
    expect(text).toContain("guided setup and linking an existing bot");
    expect(text).toContain("Telegram ready");
    expect(text).toContain("Feishu needs setup");
  });

  it("copies redacted Feishu repair steps without mutating configuration", async () => {
    const writeText = vi.fn().mockResolvedValue(undefined);
    Object.defineProperty(navigator, "clipboard", {
      configurable: true,
      value: { writeText },
    });
    const container = document.createElement("div");
    render(
      renderAgentTeamsPanel(
        createProps({
          channelsSnapshot: {
            ts: 1,
            channelOrder: ["feishu"],
            channelLabels: { feishu: "Feishu" },
            channels: {
              feishu: {
                configured: true,
                running: true,
                capabilities: ["doctor"],
                auth: {
                  accountId: "tenant-a",
                  status: "scope_missing",
                  missingAppScopes: ["im:message"],
                  missingUserScopes: ["offline_access"],
                  authorization: "Bearer secret-scope-token",
                },
              },
            },
            channelAccounts: {
              feishu: [{ accountId: "tenant-a", configured: true, running: true }],
            },
            channelDefaultAccountId: { feishu: "tenant-a" },
          },
        }),
      ),
      container,
    );

    const button = Array.from(container.querySelectorAll("button")).find((entry) =>
      (entry.textContent ?? "").includes("Copy scope repair steps"),
    );
    expect(button).toBeTruthy();
    button?.click();
    await Promise.resolve();

    expect(writeText).toHaveBeenCalledTimes(1);
    const copied = String(writeText.mock.calls[0]?.[0] ?? "");
    expect(copied).toContain("offline_access");
    expect(copied).toContain("im:message");
    expect(copied).toContain("channels.feishu.auth.start");
    expect(copied).toContain("[redacted]");
    expect(copied).not.toContain("secret-scope-token");
  });
});
