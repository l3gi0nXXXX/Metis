import { describe, expect, it, vi } from "vitest";
import {
  addAgentTeamAlias,
  AGENT_TEAM_TEMPLATE_GROUPS,
  AGENT_TEAM_PROFILE_FILES,
  applyAgentTeamTemplate,
  applyAgentTeamBinding,
  buildAgentTeamAcceptancePlan,
  buildAgentTeamBindingConflictPreview,
  buildAgentTeamCultivationSnapshot,
  buildAgentTeamBindingPreview,
  buildAgentTeamReadinessBoard,
  exportAgentTeamTemplate,
  changeAgentTeamMember,
  changeAgentTeamAlias,
  createAgentTeam,
  createEmptyAgentTeamBindingDraft,
  createEmptyAgentTeamDraft,
  createEmptyAgentTeamModelDraft,
  createEmptyAgentTeamWorkspaceDraft,
  importAgentTeamTemplate,
  loadAgentTeamWorkspaceFile,
  loadAgentTeamWorkspaceFiles,
  loadAgentTeamModel,
  previewAgentTeamBinding,
  removeAgentTeamAlias,
  saveAgentTeamWorkspaceFile,
  startAgentTeamFeishuOAuth,
  setAgentTeamBroadcastEnabled,
  setAgentTeamBroadcastMember,
  setAgentTeamBroadcastMembers,
  loadAgentTeams,
  saveAgentTeamModel,
  updateAgentTeam,
} from "./agent-teams.ts";
import type { AgentTeamsState } from "./agent-teams.ts";

function createState(): { state: AgentTeamsState; request: ReturnType<typeof vi.fn> } {
  const request = vi.fn();
  const state: AgentTeamsState = {
    client: { request } as unknown as AgentTeamsState["client"],
    connected: true,
    agentTeamsLoading: false,
    agentTeamsSaving: false,
    agentTeamsError: null,
    agentTeamsSuccess: null,
    agentTeamsList: null,
    agentTeamsSelectedId: null,
    agentTeamsDetail: null,
    agentTeamDraft: createEmptyAgentTeamDraft(),
    agentTeamBinding: createEmptyAgentTeamBindingDraft(),
    agentTeamBindingResult: null,
    agentTeamModelLoading: false,
    agentTeamModelError: null,
    agentTeamModelResult: null,
    agentTeamModelDraft: createEmptyAgentTeamModelDraft(),
    agentTeamWorkspaceLoading: false,
    agentTeamWorkspaceSaving: false,
    agentTeamWorkspaceError: null,
    agentTeamWorkspace: createEmptyAgentTeamWorkspaceDraft(),
    agentTeamFeishuAuthLoading: false,
    agentTeamFeishuAuthError: null,
    agentTeamFeishuAuthResult: null,
  };
  return { state, request };
}

describe("loadAgentTeams", () => {
  it("loads the list and selects the first team detail", async () => {
    const { state, request } = createState();
    request
      .mockResolvedValueOnce({
        teams: [{ id: "content", displayName: "Content", defaultAgentId: "content-writer" }],
        count: 1,
      })
      .mockResolvedValueOnce({
        team: {
          id: "content",
          displayName: "Content",
          defaultAgentId: "content-writer",
          members: [{ agentId: "content-writer", role: "writer" }],
        },
      });

    await loadAgentTeams(state);

    expect(request).toHaveBeenNthCalledWith(1, "agents.teams.list", {});
    expect(request).toHaveBeenNthCalledWith(2, "agents.teams.get", { id: "content" });
    expect(state.agentTeamsSelectedId).toBe("content");
    expect(state.agentTeamDraft.displayName).toBe("Content");
    expect(state.agentTeamBinding.agentId).toBe("content-writer");
  });
});

describe("team mutations", () => {
  it("exposes Miaoda-like template groups for content, engineering, support, data, and ops", () => {
    const groupLabels = AGENT_TEAM_TEMPLATE_GROUPS.map((group) => group.label);
    const groupedTemplateIds = AGENT_TEAM_TEMPLATE_GROUPS.flatMap((group) =>
      group.templates.map((template) => template.id),
    );

    expect(groupLabels).toEqual(["内容", "研发", "客服", "数据", "运营"]);
    expect(groupedTemplateIds).toContain("pm-writer-reviewer");
    expect(groupedTemplateIds).toContain("engineering-sprint");
    expect(groupedTemplateIds).toContain("telegram-support-triage");
    expect(groupedTemplateIds).toContain("data-insight-report");
    expect(groupedTemplateIds).toContain("ops-campaign-launch");
  });

  it("applies a Metis-owned Feishu team template without raw JSON editing", () => {
    const draft = applyAgentTeamTemplate(createEmptyAgentTeamDraft(), "feishu-content-handoff");

    expect(draft.template).toBe("feishu-content-handoff");
    expect(draft.displayName).toBe("Feishu Content Team");
    expect(draft.defaultAgentId).toBe("feishu-manager");
    expect(JSON.parse(draft.membersJson)).toEqual([
      { agentId: "feishu-manager", role: "manager", name: "Manager" },
      { agentId: "feishu-writer", role: "writer", name: "Writer" },
      { agentId: "feishu-reviewer", role: "reviewer", name: "Reviewer" },
    ]);
    expect(JSON.parse(draft.aliasesJson)).toEqual([
      { alias: "@manager", agentId: "feishu-manager" },
      { alias: "@writer", agentId: "feishu-writer" },
      { alias: "@reviewer", agentId: "feishu-reviewer" },
    ]);
    expect(JSON.parse(draft.broadcastJson)).toEqual({
      enabled: true,
      members: ["feishu-manager", "feishu-writer", "feishu-reviewer"],
      mode: "manager-delegation",
    });
  });

  it("exports and imports a Metis-owned team template schema", () => {
    const draft = {
      ...applyAgentTeamTemplate(createEmptyAgentTeamDraft(), "telegram-support-triage"),
      id: "support",
      displayName: "Support Team",
      defaultAgentId: "telegram-triage",
    };

    const exported = JSON.parse(exportAgentTeamTemplate(draft));
    const imported = importAgentTeamTemplate(JSON.stringify(exported));

    expect(exported.schema).toBe("metis.agentTeamTemplate.v1");
    expect(exported.team.id).toBe("support");
    expect(exported.team.template).toBe("telegram-support-triage");
    expect(imported.id).toBe("support");
    expect(imported.displayName).toBe("Support Team");
    expect(imported.defaultAgentId).toBe("telegram-triage");
    expect(JSON.parse(imported.membersJson)).toEqual(JSON.parse(draft.membersJson));
    expect(JSON.parse(imported.aliasesJson)).toEqual(JSON.parse(draft.aliasesJson));
    expect(JSON.parse(imported.bindingsJson)).toEqual([]);
  });

  it("summarizes local evidence rows separately from Telegram and Feishu live resource requirements", () => {
    const plan = buildAgentTeamAcceptancePlan({
      teamCount: 1,
      memberCount: 2,
      bindingCount: 1,
      hasModelState: true,
      hasWorkspaceProfile: true,
      channelsSnapshot: {
        ts: 1,
        channelOrder: ["telegram", "feishu"],
        channelLabels: { telegram: "Telegram", feishu: "Feishu" },
        channels: {
          telegram: { configured: true, running: true },
          feishu: {
            configured: true,
            running: true,
            capabilities: ["oauth:device-flow", "oapi:docs", "doctor"],
            auth: {
              status: "scope_missing",
              missingAppScopes: ["im:message"],
              missingUserScopes: ["offline_access"],
            },
          },
        },
        channelAccounts: {
          telegram: [{ accountId: "bot-a", configured: true, running: true }],
          feishu: [{ accountId: "tenant-a", configured: true, running: true }],
        },
        channelDefaultAccountId: { telegram: "bot-a", feishu: "tenant-a" },
      },
    });

    expect(plan.summary).toEqual({
      localPass: 3,
      externalResourceRequired: 4,
      operatorRecordRequired: 1,
    });
    expect(plan.evidenceItems.map((item) => item.status)).toEqual([
      "local-pass",
      "local-pass",
      "local-pass",
      "operator-record-required",
    ]);
    expect(plan.externalItems.map((item) => item.title)).toEqual([
      "Telegram bot, DM, group, topic, and broadcast",
      "Feishu existing app/bot and two accountIds",
      "Feishu OAuth, OAPI scopes, and low-risk resources",
      "Feishu CardKit and rich event live smoke",
    ]);
    expect(plan.externalItems.every((item) => item.status === "external-resource-required")).toBe(true);
    expect(plan.externalItems[1]?.detail).toContain("guided setup and linking an existing Feishu bot");
    expect(plan.externalItems[1]?.detail).toContain("does not create a Feishu app or bot");
  });

  it("builds a user-facing Telegram and Feishu readiness board with repair paths", () => {
    const board = buildAgentTeamReadinessBoard({
      draft: {
        ...createEmptyAgentTeamDraft(),
        id: "content",
        bindingsJson: '[{"agentId":"content-writer","match":{"channel":"telegram","accountId":"bot-a"}}]',
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
    });

    expect(board.summary).toBe("1 ready · 1 needs repair");
    expect(board.channels).toHaveLength(2);
    expect(board.channels[0]).toMatchObject({
      channel: "telegram",
      label: "Telegram",
      status: "ready",
      routeStatus: "1 route",
    });
    expect(board.channels[0]?.nextSteps).toContain("Collect live Telegram DM, group, topic, and broadcast evidence.");
    expect(board.channels[1]).toMatchObject({
      channel: "feishu",
      label: "Feishu",
      status: "needs-repair",
      routeStatus: "no route",
    });
    expect(board.channels[1]?.nextSteps).toContain("Configure an existing Feishu app/bot behind Gateway.");
    expect(board.channels[1]?.nextSteps).toContain("Grant app scopes: im:message.");
    expect(board.channels[1]?.nextSteps).toContain("Grant user scopes through OAuth: offline_access.");
    expect(board.channels[1]?.nextSteps.join(" ")).not.toContain("automatically create");
    expect(board.evidencePackHint).toContain("scripts/agentteam-manual-acceptance-gate.sh");
  });

  it("edits team members without requiring raw JSON textarea changes", () => {
    const draft = {
      ...createEmptyAgentTeamDraft(),
      membersJson: '[{"agentId":"content-writer","role":"writer","name":"Writer"}]',
    };

    const changed = changeAgentTeamMember(draft, 0, {
      role: "reviewer",
      name: "Reviewer",
    });

    expect(JSON.parse(changed.membersJson)).toEqual([
      { agentId: "content-writer", role: "reviewer", name: "Reviewer" },
    ]);
  });

  it("edits aliases and broadcast without requiring raw JSON textarea changes", () => {
    const draft = {
      ...createEmptyAgentTeamDraft(),
      aliasesJson: '[{"alias":"@writer","agentId":"content-writer"}]',
      broadcastJson: '{\n  "enabled": false\n}',
    };

    const withAlias = changeAgentTeamAlias(addAgentTeamAlias(draft), 1, {
      alias: "/agent review",
      agentId: "content-reviewer",
    });
    const withRemovedAlias = removeAgentTeamAlias(withAlias, 0);
    const withBroadcast = setAgentTeamBroadcastMember(
      setAgentTeamBroadcastEnabled(withRemovedAlias, true),
      "content-reviewer",
      true,
    );

    expect(JSON.parse(withBroadcast.aliasesJson)).toEqual([
      { alias: "/agent review", agentId: "content-reviewer" },
    ]);
    expect(JSON.parse(withBroadcast.broadcastJson)).toEqual({
      enabled: true,
      members: ["content-reviewer"],
    });
  });

  it("bulk-selects and clears broadcast members from the visible team members", () => {
    const draft = {
      ...createEmptyAgentTeamDraft(),
      broadcastJson: '{"enabled":true,"members":["content-reviewer"]}',
    };

    const selected = setAgentTeamBroadcastMembers(
      draft,
      [
        { agentId: "content-writer", role: "writer" },
        { agentId: "content-reviewer", role: "reviewer" },
      ],
      true,
    );
    const cleared = setAgentTeamBroadcastMembers(selected, [{ agentId: "content-writer" }], false);

    expect(JSON.parse(selected.broadcastJson)).toEqual({
      enabled: true,
      members: ["content-writer", "content-reviewer"],
    });
    expect(JSON.parse(cleared.broadcastJson)).toEqual({
      enabled: true,
      members: [],
    });
  });

  it("creates a template-backed team when members are empty", async () => {
    const { state, request } = createState();
    state.agentTeamDraft = {
      ...createEmptyAgentTeamDraft(),
      id: "content",
      displayName: "Content Team",
      template: "pm-writer-reviewer",
    };
    request
      .mockResolvedValueOnce({ team: { id: "content", displayName: "Content Team" } })
      .mockResolvedValueOnce({ teams: [{ id: "content", displayName: "Content Team" }], count: 1 })
      .mockResolvedValueOnce({ team: { id: "content", displayName: "Content Team" } });

    await createAgentTeam(state);

    expect(request).toHaveBeenNthCalledWith(1, "agents.teams.create", {
      id: "content",
      displayName: "Content Team",
      template: "pm-writer-reviewer",
      aliases: [],
      bindings: [],
      broadcast: { enabled: false },
    });
    expect(state.agentTeamsSuccess).toBe("Team created.");
  });

  it("ignores incomplete member rows when creating a custom team", async () => {
    const { state, request } = createState();
    state.agentTeamDraft = {
      ...createEmptyAgentTeamDraft(),
      id: "content",
      displayName: "Content Team",
      template: "",
      membersJson:
        '[{"agentId":"","role":"writer","name":"Draft"},{"agentId":"content-reviewer","role":"reviewer"}]',
    };
    request
      .mockResolvedValueOnce({ team: { id: "content", displayName: "Content Team" } })
      .mockResolvedValueOnce({ teams: [{ id: "content", displayName: "Content Team" }], count: 1 })
      .mockResolvedValueOnce({ team: { id: "content", displayName: "Content Team" } });

    await createAgentTeam(state);

    expect(request).toHaveBeenNthCalledWith(1, "agents.teams.create", {
      id: "content",
      displayName: "Content Team",
      members: [{ agentId: "content-reviewer", role: "reviewer" }],
      aliases: [],
      bindings: [],
      broadcast: { enabled: false },
    });
  });

  it("updates team members, aliases, bindings, and broadcast through agents.teams.update", async () => {
    const { state, request } = createState();
    state.agentTeamDraft = {
      id: "content",
      displayName: "Content Team",
      template: "",
      defaultAgentId: "content-reviewer",
      membersJson: '[{"agentId":"content-reviewer","role":"reviewer"}]',
      aliasesJson: '[{"agentId":"content-reviewer","alias":"@review"}]',
      bindingsJson: '[{"agentId":"content-reviewer","match":{"channel":"telegram"}}]',
      broadcastJson: '{"enabled":true,"members":["content-reviewer"]}',
    };
    request
      .mockResolvedValueOnce({ team: { id: "content" } })
      .mockResolvedValueOnce({ teams: [{ id: "content" }], count: 1 })
      .mockResolvedValueOnce({ team: { id: "content" } });

    await updateAgentTeam(state);

    expect(request).toHaveBeenNthCalledWith(1, "agents.teams.update", {
      id: "content",
      displayName: "Content Team",
      defaultAgentId: "content-reviewer",
      members: [{ agentId: "content-reviewer", role: "reviewer" }],
      aliases: [{ agentId: "content-reviewer", alias: "@review" }],
      bindings: [{ agentId: "content-reviewer", match: { channel: "telegram" } }],
      broadcast: { enabled: true, members: ["content-reviewer"] },
    });
  });

  it("normalizes raw team JSON before calling Gateway mutations", async () => {
    const { state, request } = createState();
    state.agentTeamDraft = {
      id: "content",
      displayName: " Content Team ",
      template: "",
      defaultAgentId: "missing-member",
      membersJson:
        '[{"agentId":" content-writer ","role":" writer ","name":" Writer "},{"agentId":"","role":"ignored"}]',
      aliasesJson:
        '[{"alias":" @writer ","agentId":" content-writer "},{"alias":"@missing","agentId":""}]',
      bindingsJson: '[{"agentId":"content-writer","match":{"channel":"feishu"}}]',
      broadcastJson: '{"enabled":true,"members":["content-writer","missing-member","content-writer"]}',
    };
    request
      .mockResolvedValueOnce({ team: { id: "content" } })
      .mockResolvedValueOnce({ teams: [{ id: "content" }], count: 1 })
      .mockResolvedValueOnce({ team: { id: "content" } });

    await updateAgentTeam(state);

    expect(request).toHaveBeenNthCalledWith(1, "agents.teams.update", {
      id: "content",
      displayName: "Content Team",
      defaultAgentId: "content-writer",
      members: [{ agentId: "content-writer", role: "writer", name: "Writer" }],
      aliases: [{ alias: "@writer", agentId: "content-writer" }],
      bindings: [{ agentId: "content-writer", match: { channel: "feishu" } }],
      broadcast: { enabled: true, members: ["content-writer"] },
    });
  });
});

describe("team binding and models", () => {
  it("builds a structured binding preview before applying", () => {
    const draft = {
      ...createEmptyAgentTeamBindingDraft(),
      agentId: "content-writer",
      useStructuredBinding: true,
      channel: "feishu",
      accountId: "tenant-a",
      peer: "chat:oc_123",
      thread: "thread:om_456",
      group: "chat:oc_123",
      team: "content",
      roles: "writer, reviewer",
      comment: "content team route",
    };

    const preview = buildAgentTeamBindingPreview(draft);

    expect(preview.simpleBinding).toBe("feishu:tenant-a");
    expect(preview.routeBinding).toEqual({
      type: "route",
      agentId: "content-writer",
      match: {
        channel: "feishu",
        accountId: "tenant-a",
        peer: { kind: "thread", id: "thread:om_456" },
        guildId: "chat:oc_123",
        teamId: "content",
        roles: ["writer", "reviewer"],
      },
      comment: "content team route",
    });
    expect(preview.applyPayload).toEqual({
      agentId: "content-writer",
      bindings: [preview.routeBinding],
    });
    expect(preview.lines.join("\n")).toContain("read-only preview");
  });

  it("detects binding conflicts between the draft team routes and the current apply preview", () => {
    const teamDraft = {
      ...createEmptyAgentTeamDraft(),
      id: "content",
      bindingsJson: JSON.stringify([
        {
          agentId: "content-writer",
          match: {
            channel: "feishu",
            accountId: "tenant-a",
            peer: { kind: "group", id: "chat:oc_123" },
            teamId: "content",
          },
        },
      ]),
    };
    const bindingDraft = {
      ...createEmptyAgentTeamBindingDraft(),
      agentId: "content-reviewer",
      useStructuredBinding: true,
      channel: "feishu",
      accountId: "tenant-a",
      peer: "chat:oc_123",
      team: "content",
    };

    const conflict = buildAgentTeamBindingConflictPreview(teamDraft, bindingDraft);

    expect(conflict.summary).toBe("1 conflict");
    expect(conflict.items).toEqual([
      {
        status: "conflict",
        title: "Route already targets another member",
        detail: "feishu tenant-a group:chat:oc_123 team:content is already assigned to content-writer.",
        repair: "Change the member, account, peer, thread, or team before applying this binding.",
      },
    ]);
  });

  it("applies a team member binding through agents.bind", async () => {
    const { state, request } = createState();
    state.agentTeamBinding = {
      agentId: "content-writer",
      spec: "telegram:bot-a",
      mode: "bind",
    };
    request.mockResolvedValue({ agentId: "content-writer", added: ["telegram accountId=bot-a"] });

    await applyAgentTeamBinding(state);

    expect(request).toHaveBeenCalledWith("agents.bind", {
      agentId: "content-writer",
      bind: "telegram:bot-a",
    });
    expect(state.agentTeamsSuccess).toBe("Binding applied.");
  });

  it("applies a structured binding through agents.bind after preview", async () => {
    const { state, request } = createState();
    state.agentTeamBinding = {
      ...createEmptyAgentTeamBindingDraft(),
      agentId: "content-writer",
      channel: "feishu",
      accountId: "tenant-a",
      peer: "chat:oc_123",
      useStructuredBinding: true,
    };
    request.mockResolvedValue({ agentId: "content-writer", added: ["feishu accountId=tenant-a"] });

    previewAgentTeamBinding(state);
    await applyAgentTeamBinding(state);

    expect(state.agentTeamBindingPreview?.routeBinding).toMatchObject({
      agentId: "content-writer",
      match: {
        channel: "feishu",
        accountId: "tenant-a",
        peer: { kind: "group", id: "chat:oc_123" },
      },
    });
    expect(request).toHaveBeenCalledWith("agents.bind", {
      agentId: "content-writer",
      bindings: [
        {
          type: "route",
          agentId: "content-writer",
          match: {
            channel: "feishu",
            accountId: "tenant-a",
            peer: { kind: "group", id: "chat:oc_123" },
          },
        },
      ],
    });
  });

  it("loads and saves per-agent model state through agents.models.get/set", async () => {
    const { state, request } = createState();
    request
      .mockResolvedValueOnce({
        models: {
          agentId: "content-writer",
          primaryModelRef: "openai:gpt-5-mini",
          runtimePrimaryModelRef: "openai:gpt-5-mini",
          providerCount: 0,
          state: { providers: [] },
        },
      })
      .mockResolvedValueOnce({
        models: {
          agentId: "content-writer",
          primaryModelRef: "openai:gpt-5.1",
          runtimePrimaryModelRef: "openai:gpt-5.1",
          state: { providers: [] },
        },
      })
      .mockResolvedValueOnce({
        models: {
          agentId: "content-writer",
          primaryModelRef: "openai:gpt-5.1",
          runtimePrimaryModelRef: "openai:gpt-5.1",
          state: { providers: [] },
        },
      });

    await loadAgentTeamModel(state, "content-writer");
    state.agentTeamModelDraft.primaryModelRef = "openai:gpt-5.1";
    state.agentTeamModelDraft.runtimePrimaryModelRef = "openai:gpt-5.1";
    await saveAgentTeamModel(state);

    expect(request).toHaveBeenNthCalledWith(1, "agents.models.get", {
      agentId: "content-writer",
    });
    expect(request).toHaveBeenNthCalledWith(2, "agents.models.set", {
      agentId: "content-writer",
      state: {
        providers: [],
        primaryModelRef: "openai:gpt-5.1",
        runtimePrimaryModelRef: "openai:gpt-5.1",
      },
    });
  });
});

describe("Feishu OAuth start", () => {
  it("starts Feishu OAuth through Gateway RPC and redacts accidental secret fields", async () => {
    const { state, request } = createState();
    request.mockResolvedValueOnce({
      status: "pending",
      accountId: "tenant-a",
      verificationUri: "https://verify.example/activate",
      userCode: "ABCD-EFGH",
      accessToken: "secret-access-token",
      refresh_token: "secret-refresh-token",
      authorization: "Bearer secret-authorization-token",
    });

    await startAgentTeamFeishuOAuth(state, "tenant-a");

    expect(request).toHaveBeenCalledWith("channels.feishu.auth.start", {
      accountId: "tenant-a",
    });
    expect(state.agentTeamFeishuAuthResult).toMatchObject({
      status: "pending",
      accountId: "tenant-a",
      verificationUri: "https://verify.example/activate",
      userCode: "ABCD-EFGH",
      redacted: true,
    });
    const rendered = JSON.stringify(state.agentTeamFeishuAuthResult);
    expect(rendered).toContain("[redacted]");
    expect(rendered).not.toContain("secret-access-token");
    expect(rendered).not.toContain("secret-refresh-token");
    expect(rendered).not.toContain("secret-authorization-token");
  });

  it("routes explicit Feishu OAuth lifecycle actions through Gateway RPC", async () => {
    const { state, request } = createState();
    request.mockResolvedValueOnce({
      status: "authorized",
      accountId: "tenant-a",
      tokenStatus: "authorized",
      scopeSummary: "offline_access",
    });

    await startAgentTeamFeishuOAuth(state, "tenant-a", "status");

    expect(request).toHaveBeenCalledWith("channels.feishu.auth.status", {
      accountId: "tenant-a",
    });
    expect(state.agentTeamsSuccess).toBe("Feishu OAuth status loaded through Gateway RPC.");
  });

  it("never asks the browser to server-revoke Feishu OAuth by default", async () => {
    const { state, request } = createState();
    request.mockResolvedValueOnce({
      status: "revoked",
      accountId: "tenant-a",
      redacted: true,
    });

    await startAgentTeamFeishuOAuth(state, "tenant-a", "revoke");

    expect(request).toHaveBeenCalledWith("channels.feishu.auth.revoke", {
      accountId: "tenant-a",
      serverRevoke: false,
    });
  });
});

describe("team workspace profiles", () => {
  it("matches the Gateway Control UI supported profile file contract", () => {
    expect([...AGENT_TEAM_PROFILE_FILES]).toEqual([
      "AGENTS.md",
      "SOUL.md",
      "TOOLS.md",
      "IDENTITY.md",
      "USER.md",
      "HEARTBEAT.md",
      "BOOTSTRAP.md",
      "MEMORY.md",
    ]);
  });

  it("lists, loads, and saves supported workspace profile files through agents.files RPC", async () => {
    const { state, request } = createState();
    request
      .mockResolvedValueOnce({
        agentId: "content-writer",
        workspace: "/tmp/metis/content-writer",
        files: [
          { name: "SOUL.md", path: "/tmp/metis/content-writer/SOUL.md", missing: false },
          { name: "scratch.txt", path: "/tmp/metis/content-writer/scratch.txt", missing: false },
        ],
      })
      .mockResolvedValueOnce({
        agentId: "content-writer",
        workspace: "/tmp/metis/content-writer",
        file: {
          name: "SOUL.md",
          path: "/tmp/metis/content-writer/SOUL.md",
          missing: false,
          content: "Be concise.",
        },
      })
      .mockResolvedValueOnce({
        ok: true,
        agentId: "content-writer",
        workspace: "/tmp/metis/content-writer",
        file: {
          name: "SOUL.md",
          path: "/tmp/metis/content-writer/SOUL.md",
          missing: false,
          content: "Be direct.",
        },
      });

    await loadAgentTeamWorkspaceFiles(state, "content-writer");
    await loadAgentTeamWorkspaceFile(state, "SOUL.md");
    state.agentTeamWorkspace.draft = "Be direct.";
    await saveAgentTeamWorkspaceFile(state);

    expect(request).toHaveBeenNthCalledWith(1, "agents.files.list", {
      agentId: "content-writer",
    });
    expect(request).toHaveBeenNthCalledWith(2, "agents.files.get", {
      agentId: "content-writer",
      name: "SOUL.md",
    });
    expect(request).toHaveBeenNthCalledWith(3, "agents.files.set", {
      agentId: "content-writer",
      name: "SOUL.md",
      content: "Be direct.",
    });
    expect(state.agentTeamWorkspace.files.map((file) => file.name)).toEqual([
      "AGENTS.md",
      "SOUL.md",
      "TOOLS.md",
      "IDENTITY.md",
      "USER.md",
      "HEARTBEAT.md",
      "BOOTSTRAP.md",
      "MEMORY.md",
    ]);
    expect(state.agentTeamWorkspace.content).toBe("Be direct.");
  });

  it("builds a redacted cultivation snapshot from memory, heartbeat, and doctor status", () => {
    const snapshot = buildAgentTeamCultivationSnapshot({
      workspace: {
        ...createEmptyAgentTeamWorkspaceDraft(),
        agentId: "content-writer",
        fileName: "MEMORY.md",
        draft: "Remember launch positioning. Authorization: Bearer secret-memory-token",
        files: [
          { name: "MEMORY.md", path: "/tmp/metis/MEMORY.md", missing: false, updatedAtMs: 1710000000000 },
          { name: "HEARTBEAT.md", path: "/tmp/metis/HEARTBEAT.md", missing: true },
        ],
      },
      channelsSnapshot: {
        ts: 1,
        channelOrder: ["feishu"],
        channelLabels: { feishu: "Feishu" },
        channels: {
          feishu: {
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
        channelAccounts: {},
        channelDefaultAccountId: {},
      },
    });

    expect(snapshot.agentId).toBe("content-writer");
    expect(snapshot.memory.status).toBe("loaded");
    expect(snapshot.heartbeat.status).toBe("missing");
    expect(snapshot.memory.preview).toContain("Remember launch positioning");
    expect(snapshot.memory.preview).toContain("Bearer [redacted]");
    expect(snapshot.doctor.status).toBe("warning");
    expect(snapshot.doctor.findings).toEqual([
      {
        code: "app_scope_missing",
        message: "Authorization: Bearer [redacted] missing im:message",
      },
    ]);
    expect(JSON.stringify(snapshot)).not.toContain("secret-doctor-token");
    expect(JSON.stringify(snapshot)).not.toContain("secret-memory-token");
  });
});
