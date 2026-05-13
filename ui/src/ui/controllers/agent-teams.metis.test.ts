import { describe, expect, it, vi } from "vitest";
import {
  applyAgentTeamBinding,
  createAgentTeam,
  createEmptyAgentTeamBindingDraft,
  createEmptyAgentTeamDraft,
  createEmptyAgentTeamModelDraft,
  loadAgentTeamModel,
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
    });
    expect(state.agentTeamsSuccess).toBe("Team created.");
  });

  it("updates team members, aliases, and bindings through agents.teams.update", async () => {
    const { state, request } = createState();
    state.agentTeamDraft = {
      id: "content",
      displayName: "Content Team",
      template: "",
      defaultAgentId: "content-reviewer",
      membersJson: '[{"agentId":"content-reviewer","role":"reviewer"}]',
      aliasesJson: '[{"agentId":"content-reviewer","patterns":["review"]}]',
      bindingsJson: '[{"agentId":"content-reviewer","match":{"channel":"telegram"}}]',
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
      aliases: [{ agentId: "content-reviewer", patterns: ["review"] }],
      bindings: [{ agentId: "content-reviewer", match: { channel: "telegram" } }],
    });
  });
});

describe("team binding and models", () => {
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
