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
    expect(text).toContain("Feishu content handoff");
    expect(text).toContain("Telegram support triage");
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
});
