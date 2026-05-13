import type { GatewayBrowserClient } from "../gateway.ts";
import type {
  AgentBindingsResult,
  AgentModelsResult,
  AgentTeam,
  AgentTeamGetResult,
  AgentTeamMember,
  AgentTeamMutationResult,
  AgentTeamsListResult,
} from "../types.ts";
import {
  formatMissingOperatorReadScopeMessage,
  isMissingOperatorReadScopeError,
} from "./scope-errors.ts";

export type AgentTeamEditorDraft = {
  id: string;
  displayName: string;
  template: string;
  defaultAgentId: string;
  membersJson: string;
  aliasesJson: string;
  bindingsJson: string;
};

export type AgentTeamBindingDraft = {
  agentId: string;
  spec: string;
  mode: "bind" | "unbind";
};

export type AgentTeamModelDraft = {
  agentId: string;
  primaryModelRef: string;
  runtimePrimaryModelRef: string;
  stateJson: string;
};

export type AgentTeamsState = {
  client: GatewayBrowserClient | null;
  connected: boolean;
  agentTeamsLoading: boolean;
  agentTeamsSaving: boolean;
  agentTeamsError: string | null;
  agentTeamsSuccess: string | null;
  agentTeamsList: AgentTeamsListResult | null;
  agentTeamsSelectedId: string | null;
  agentTeamsDetail: AgentTeam | null;
  agentTeamDraft: AgentTeamEditorDraft;
  agentTeamBinding: AgentTeamBindingDraft;
  agentTeamBindingResult: AgentBindingsResult | null;
  agentTeamModelLoading: boolean;
  agentTeamModelError: string | null;
  agentTeamModelResult: AgentModelsResult | null;
  agentTeamModelDraft: AgentTeamModelDraft;
};

export function createEmptyAgentTeamDraft(): AgentTeamEditorDraft {
  return {
    id: "",
    displayName: "",
    template: "pm-writer-reviewer",
    defaultAgentId: "",
    membersJson: "[]",
    aliasesJson: "[]",
    bindingsJson: "[]",
  };
}

export function createEmptyAgentTeamBindingDraft(): AgentTeamBindingDraft {
  return {
    agentId: "",
    spec: "",
    mode: "bind",
  };
}

export function createEmptyAgentTeamModelDraft(): AgentTeamModelDraft {
  return {
    agentId: "",
    primaryModelRef: "",
    runtimePrimaryModelRef: "",
    stateJson: "{\n  \"providers\": []\n}",
  };
}

export function draftFromTeam(team: AgentTeam | null): AgentTeamEditorDraft {
  if (!team) {
    return createEmptyAgentTeamDraft();
  }
  return {
    id: team.id ?? "",
    displayName: team.displayName ?? team.id ?? "",
    template: "",
    defaultAgentId: team.defaultAgentId ?? "",
    membersJson: stringifyPretty(team.members ?? []),
    aliasesJson: stringifyPretty(team.aliases ?? []),
    bindingsJson: stringifyPretty(team.bindings ?? []),
  };
}

export async function loadAgentTeams(state: AgentTeamsState) {
  if (!state.client || !state.connected || state.agentTeamsLoading) {
    return;
  }
  state.agentTeamsLoading = true;
  state.agentTeamsError = null;
  try {
    const res = await state.client.request<AgentTeamsListResult>("agents.teams.list", {});
    if (!res) {
      return;
    }
    state.agentTeamsList = {
      teams: Array.isArray(res.teams) ? res.teams : [],
      count: typeof res.count === "number" ? res.count : (res.teams?.length ?? 0),
    };
    const selected = state.agentTeamsSelectedId;
    const known = state.agentTeamsList.teams.some((team) => team.id === selected);
    if (!selected || !known) {
      state.agentTeamsSelectedId = state.agentTeamsList.teams[0]?.id ?? null;
    }
    if (state.agentTeamsSelectedId) {
      await loadAgentTeamDetail(state, state.agentTeamsSelectedId);
    } else {
      state.agentTeamsDetail = null;
      state.agentTeamDraft = createEmptyAgentTeamDraft();
    }
  } catch (err) {
    state.agentTeamsError = isMissingOperatorReadScopeError(err)
      ? formatMissingOperatorReadScopeMessage("agent teams")
      : String(err);
  } finally {
    state.agentTeamsLoading = false;
  }
}

export async function loadAgentTeamDetail(state: AgentTeamsState, teamId: string) {
  const id = teamId.trim();
  if (!state.client || !state.connected || !id) {
    return;
  }
  try {
    const res = await state.client.request<AgentTeamGetResult>("agents.teams.get", { id });
    state.agentTeamsSelectedId = id;
    state.agentTeamsDetail = res?.team ?? null;
    state.agentTeamDraft = draftFromTeam(state.agentTeamsDetail);
    const defaultAgentId = state.agentTeamsDetail?.defaultAgentId ?? "";
    state.agentTeamBinding = {
      ...state.agentTeamBinding,
      agentId: state.agentTeamBinding.agentId || defaultAgentId,
    };
    state.agentTeamModelDraft = {
      ...state.agentTeamModelDraft,
      agentId: state.agentTeamModelDraft.agentId || defaultAgentId,
    };
  } catch (err) {
    state.agentTeamsError = String(err);
  }
}

export async function createAgentTeam(state: AgentTeamsState, draft = state.agentTeamDraft) {
  try {
    const payload = teamPayloadFromDraft(draft, { create: true });
    await mutateAgentTeam(state, "agents.teams.create", payload, "Team created.");
  } catch (err) {
    state.agentTeamsError = String(err);
  }
}

export async function updateAgentTeam(state: AgentTeamsState, draft = state.agentTeamDraft) {
  try {
    const payload = teamPayloadFromDraft(draft, { create: false });
    await mutateAgentTeam(state, "agents.teams.update", payload, "Team updated.");
  } catch (err) {
    state.agentTeamsError = String(err);
  }
}

export async function deleteAgentTeam(state: AgentTeamsState, teamId = state.agentTeamsSelectedId) {
  const id = teamId?.trim() ?? "";
  if (!id) {
    state.agentTeamsError = "Select a team before deleting.";
    return;
  }
  await mutateAgentTeam(state, "agents.teams.delete", { id }, "Team deleted.");
}

export async function applyAgentTeamBinding(
  state: AgentTeamsState,
  draft = state.agentTeamBinding,
) {
  if (!state.client || !state.connected) {
    return;
  }
  const agentId = draft.agentId.trim();
  const spec = draft.spec.trim();
  if (!agentId || !spec) {
    state.agentTeamsError = "Choose a team member and enter a channel binding.";
    return;
  }
  state.agentTeamsSaving = true;
  state.agentTeamsError = null;
  state.agentTeamsSuccess = null;
  try {
    const method = draft.mode === "unbind" ? "agents.unbind" : "agents.bind";
    const res = await state.client.request<AgentBindingsResult>(method, {
      agentId,
      bind: spec,
    });
    state.agentTeamBindingResult = res ?? null;
    state.agentTeamsSuccess = draft.mode === "unbind" ? "Binding removed." : "Binding applied.";
  } catch (err) {
    state.agentTeamsError = String(err);
  } finally {
    state.agentTeamsSaving = false;
  }
}

export async function loadAgentTeamModel(
  state: AgentTeamsState,
  agentId = state.agentTeamModelDraft.agentId,
) {
  const id = agentId.trim();
  if (!state.client || !state.connected || !id) {
    return;
  }
  state.agentTeamModelLoading = true;
  state.agentTeamModelError = null;
  try {
    const res = await state.client.request<AgentModelsResult>("agents.models.get", { agentId: id });
    state.agentTeamModelResult = res ?? null;
    const model = res?.models;
    const nextState = model?.state ?? {};
    state.agentTeamModelDraft = {
      agentId: id,
      primaryModelRef: model?.primaryModelRef ?? "",
      runtimePrimaryModelRef: model?.runtimePrimaryModelRef ?? "",
      stateJson: stringifyPretty(nextState),
    };
  } catch (err) {
    state.agentTeamModelError = String(err);
  } finally {
    state.agentTeamModelLoading = false;
  }
}

export async function saveAgentTeamModel(
  state: AgentTeamsState,
  draft = state.agentTeamModelDraft,
) {
  const agentId = draft.agentId.trim();
  if (!state.client || !state.connected || !agentId) {
    return;
  }
  state.agentTeamsSaving = true;
  state.agentTeamModelError = null;
  state.agentTeamsSuccess = null;
  try {
    const parsed = parseJsonObject(draft.stateJson, "models.json state");
    if (draft.primaryModelRef.trim()) {
      parsed.primaryModelRef = draft.primaryModelRef.trim();
    }
    if (draft.runtimePrimaryModelRef.trim()) {
      parsed.runtimePrimaryModelRef = draft.runtimePrimaryModelRef.trim();
    }
    const res = await state.client.request<AgentModelsResult>("agents.models.set", {
      agentId,
      state: parsed,
    });
    state.agentTeamModelResult = res ?? null;
    state.agentTeamsSuccess = "Model settings saved.";
    await loadAgentTeamModel(state, agentId);
  } catch (err) {
    state.agentTeamModelError = String(err);
  } finally {
    state.agentTeamsSaving = false;
  }
}

function teamPayloadFromDraft(
  draft: AgentTeamEditorDraft,
  options: { create: boolean },
): Record<string, unknown> {
  const id = draft.id.trim();
  if (!id) {
    throw new Error("Team id is required.");
  }
  const payload: Record<string, unknown> = {
    id,
    displayName: draft.displayName.trim() || id,
  };
  const members = parseJsonArray<AgentTeamMember>(draft.membersJson, "members");
  if (members.length > 0) {
    payload.members = members;
  } else if (options.create && draft.template.trim()) {
    payload.template = draft.template.trim();
  }
  if (draft.defaultAgentId.trim()) {
    payload.defaultAgentId = draft.defaultAgentId.trim();
  }
  payload.aliases = parseJsonArray(draft.aliasesJson, "aliases");
  payload.bindings = parseJsonArray(draft.bindingsJson, "bindings");
  return payload;
}

async function mutateAgentTeam(
  state: AgentTeamsState,
  method: "agents.teams.create" | "agents.teams.update" | "agents.teams.delete",
  payload: Record<string, unknown>,
  success: string,
) {
  if (!state.client || !state.connected) {
    return;
  }
  state.agentTeamsSaving = true;
  state.agentTeamsError = null;
  state.agentTeamsSuccess = null;
  try {
    const res = await state.client.request<AgentTeamMutationResult>(method, payload);
    state.agentTeamsSuccess = success;
    const selected = res?.team?.id ?? (payload.id as string | undefined) ?? null;
    await loadAgentTeams(state);
    if (method === "agents.teams.delete") {
      return;
    }
    if (selected) {
      await loadAgentTeamDetail(state, selected);
    }
  } catch (err) {
    state.agentTeamsError = String(err);
  } finally {
    state.agentTeamsSaving = false;
  }
}

function parseJsonArray<T = unknown>(text: string, label: string): T[] {
  const trimmed = text.trim();
  if (!trimmed) {
    return [];
  }
  const parsed = JSON.parse(trimmed) as unknown;
  if (!Array.isArray(parsed)) {
    throw new Error(`${label} must be a JSON array.`);
  }
  return parsed as T[];
}

function parseJsonObject(text: string, label: string): Record<string, unknown> {
  const trimmed = text.trim();
  if (!trimmed) {
    return {};
  }
  const parsed = JSON.parse(trimmed) as unknown;
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error(`${label} must be a JSON object.`);
  }
  return parsed as Record<string, unknown>;
}

function stringifyPretty(value: unknown): string {
  return JSON.stringify(value ?? null, null, 2);
}
