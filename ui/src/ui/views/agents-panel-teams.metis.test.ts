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
    modelResult: null,
    modelDraft: createEmptyAgentTeamModelDraft(),
    workspaceLoading: false,
    workspaceSaving: false,
    workspaceError: null,
    workspace: {
      ...createEmptyAgentTeamWorkspaceDraft(),
      agentId: "content-writer",
      fileName: "SOUL.md",
    },
    channelsSnapshot: {
      ts: 1,
      channelOrder: ["feishu"],
      channelLabels: { feishu: "Feishu" },
      channels: { feishu: { configured: true, running: true } },
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
    expect(text).toContain("OAuth missing");
    expect(text).toContain("/feishu doctor");
    expect(text).toContain("Team-agent parity is partial");
    expect(text).toContain("[redacted]");
    expect(text).not.toContain("secret-access-token");

    const options = Array.from(container.querySelectorAll("option")).map(
      (option) => option.textContent ?? "",
    );
    expect(options).toContain("HEARTBEAT.md");
    expect(options).toContain("BOOTSTRAP.md");
  });
});
