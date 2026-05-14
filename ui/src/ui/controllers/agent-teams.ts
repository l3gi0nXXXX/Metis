import type { GatewayBrowserClient } from "../gateway.ts";
import type {
  AgentBindingsResult,
  AgentFileEntry,
  AgentModelsResult,
  AgentTeam,
  AgentTeamGetResult,
  AgentTeamMember,
  AgentTeamMutationResult,
  AgentTeamsListResult,
  AgentsFilesGetResult,
  AgentsFilesListResult,
  AgentsFilesSetResult,
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
  broadcastJson: string;
};

export type AgentTeamAliasDraft = {
  alias: string;
  agentId: string;
};

export type AgentTeamBindingDraft = {
  agentId: string;
  spec: string;
  mode: "bind" | "unbind";
  useStructuredBinding: boolean;
  channel: string;
  accountId: string;
  peerKind: string;
  peer: string;
  thread: string;
  group: string;
  team: string;
  roles: string;
  comment: string;
};

export type AgentTeamBindingPreview = {
  simpleBinding: string;
  routeBinding: Record<string, unknown> | null;
  applyPayload: Record<string, unknown> | null;
  lines: string[];
};

export type AgentTeamModelDraft = {
  agentId: string;
  primaryModelRef: string;
  runtimePrimaryModelRef: string;
  stateJson: string;
};

export type AgentTeamWorkspaceDraft = {
  agentId: string;
  workspace: string;
  files: AgentFileEntry[];
  fileName: string;
  path: string;
  content: string;
  draft: string;
};

export type AgentTeamFeishuAuthResult = Record<string, unknown>;

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
  agentTeamBindingPreview?: AgentTeamBindingPreview | null;
  agentTeamBindingResult: AgentBindingsResult | null;
  agentTeamModelLoading: boolean;
  agentTeamModelError: string | null;
  agentTeamModelResult: AgentModelsResult | null;
  agentTeamModelDraft: AgentTeamModelDraft;
  agentTeamWorkspaceLoading: boolean;
  agentTeamWorkspaceSaving: boolean;
  agentTeamWorkspaceError: string | null;
  agentTeamWorkspace: AgentTeamWorkspaceDraft;
  agentTeamFeishuAuthLoading: boolean;
  agentTeamFeishuAuthError: string | null;
  agentTeamFeishuAuthResult: AgentTeamFeishuAuthResult | null;
};

export const AGENT_TEAM_PROFILE_FILES = [
  "SOUL.md",
  "TOOLS.md",
  "IDENTITY.md",
  "USER.md",
] as const;

export function createEmptyAgentTeamDraft(): AgentTeamEditorDraft {
  return {
    id: "",
    displayName: "",
    template: "pm-writer-reviewer",
    defaultAgentId: "",
    membersJson: "[]",
    aliasesJson: "[]",
    bindingsJson: "[]",
    broadcastJson: "{\n  \"enabled\": false\n}",
  };
}

export function createEmptyAgentTeamBindingDraft(): AgentTeamBindingDraft {
  return {
    agentId: "",
    spec: "",
    mode: "bind",
    useStructuredBinding: false,
    channel: "feishu",
    accountId: "",
    peerKind: "group",
    peer: "",
    thread: "",
    group: "",
    team: "",
    roles: "",
    comment: "",
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

export function createEmptyAgentTeamWorkspaceDraft(): AgentTeamWorkspaceDraft {
  return {
    agentId: "",
    workspace: "",
    files: [],
    fileName: "SOUL.md",
    path: "",
    content: "",
    draft: "",
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
    broadcastJson: stringifyPretty(team.broadcast ?? { enabled: false }),
  };
}

export function membersFromDraft(draft: AgentTeamEditorDraft): AgentTeamMember[] {
  return parseJsonArray<AgentTeamMember>(draft.membersJson, "members");
}

export function changeAgentTeamMember(
  draft: AgentTeamEditorDraft,
  index: number,
  patch: Partial<AgentTeamMember>,
): AgentTeamEditorDraft {
  const members = membersFromDraft(draft);
  if (index < 0 || index >= members.length) {
    return draft;
  }
  const current = members[index] ?? { agentId: "" };
  const next = {
    ...current,
    ...patch,
  };
  const compact: AgentTeamMember = { agentId: next.agentId?.trim() ?? "" };
  if (next.role?.trim()) {
    compact.role = next.role.trim();
  }
  if (next.name?.trim()) {
    compact.name = next.name.trim();
  }
  members[index] = compact;
  return { ...draft, membersJson: stringifyPretty(members) };
}

export function addAgentTeamMember(draft: AgentTeamEditorDraft): AgentTeamEditorDraft {
  const members = membersFromDraft(draft);
  members.push({ agentId: "", role: "", name: "" });
  return { ...draft, membersJson: stringifyPretty(members) };
}

export function removeAgentTeamMember(
  draft: AgentTeamEditorDraft,
  index: number,
): AgentTeamEditorDraft {
  const members = membersFromDraft(draft);
  if (index < 0 || index >= members.length) {
    return draft;
  }
  members.splice(index, 1);
  return { ...draft, membersJson: stringifyPretty(members) };
}

export function aliasesFromDraft(draft: AgentTeamEditorDraft): AgentTeamAliasDraft[] {
  return parseJsonArray<AgentTeamAliasDraft>(draft.aliasesJson, "aliases");
}

export function changeAgentTeamAlias(
  draft: AgentTeamEditorDraft,
  index: number,
  patch: Partial<AgentTeamAliasDraft>,
): AgentTeamEditorDraft {
  const aliases = aliasesFromDraft(draft);
  if (index < 0 || index >= aliases.length) {
    return draft;
  }
  const current = aliases[index] ?? { alias: "", agentId: "" };
  const next = {
    ...current,
    ...patch,
  };
  aliases[index] = {
    alias: next.alias?.trim() ?? "",
    agentId: next.agentId?.trim() ?? "",
  };
  return { ...draft, aliasesJson: stringifyPretty(aliases) };
}

export function addAgentTeamAlias(draft: AgentTeamEditorDraft): AgentTeamEditorDraft {
  const aliases = aliasesFromDraft(draft);
  aliases.push({ alias: "", agentId: "" });
  return { ...draft, aliasesJson: stringifyPretty(aliases) };
}

export function removeAgentTeamAlias(
  draft: AgentTeamEditorDraft,
  index: number,
): AgentTeamEditorDraft {
  const aliases = aliasesFromDraft(draft);
  if (index < 0 || index >= aliases.length) {
    return draft;
  }
  aliases.splice(index, 1);
  return { ...draft, aliasesJson: stringifyPretty(aliases) };
}

export function broadcastFromDraft(draft: AgentTeamEditorDraft): Record<string, unknown> {
  return parseJsonObject(draft.broadcastJson, "broadcast");
}

export function setAgentTeamBroadcastEnabled(
  draft: AgentTeamEditorDraft,
  enabled: boolean,
): AgentTeamEditorDraft {
  const broadcast = broadcastFromDraft(draft);
  broadcast.enabled = enabled;
  return { ...draft, broadcastJson: stringifyPretty(broadcast) };
}

export function setAgentTeamBroadcastMember(
  draft: AgentTeamEditorDraft,
  agentId: string,
  selected: boolean,
): AgentTeamEditorDraft {
  const normalized = agentId.trim();
  if (!normalized) {
    return draft;
  }
  const broadcast = broadcastFromDraft(draft);
  const members = stringArrayValue(broadcast.members);
  const hasMember = members.includes(normalized);
  if (selected && !hasMember) {
    members.push(normalized);
  }
  if (!selected && hasMember) {
    members.splice(members.indexOf(normalized), 1);
  }
  broadcast.members = members;
  return { ...draft, broadcastJson: stringifyPretty(broadcast) };
}

export function setAgentTeamBroadcastMembers(
  draft: AgentTeamEditorDraft,
  members: AgentTeamMember[],
  selected: boolean,
): AgentTeamEditorDraft {
  const broadcast = broadcastFromDraft(draft);
  broadcast.members = selected ? uniqueStrings(members.map((member) => member.agentId)) : [];
  return { ...draft, broadcastJson: stringifyPretty(broadcast) };
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
    state.agentTeamWorkspace = {
      ...state.agentTeamWorkspace,
      agentId: state.agentTeamWorkspace.agentId || defaultAgentId,
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
  const preview = buildAgentTeamBindingPreview(draft);
  if (!agentId || !preview.applyPayload) {
    state.agentTeamsError = "Choose a team member and enter a channel binding.";
    return;
  }
  state.agentTeamsSaving = true;
  state.agentTeamsError = null;
  state.agentTeamsSuccess = null;
  state.agentTeamBindingPreview = preview;
  try {
    const method = draft.mode === "unbind" ? "agents.unbind" : "agents.bind";
    const res = await state.client.request<AgentBindingsResult>(method, preview.applyPayload);
    state.agentTeamBindingResult = res ?? null;
    state.agentTeamsSuccess = draft.mode === "unbind" ? "Binding removed." : "Binding applied.";
  } catch (err) {
    state.agentTeamsError = String(err);
  } finally {
    state.agentTeamsSaving = false;
  }
}

export function previewAgentTeamBinding(
  state: AgentTeamsState,
  draft = state.agentTeamBinding,
): AgentTeamBindingPreview {
  const preview = buildAgentTeamBindingPreview(draft);
  state.agentTeamBindingPreview = preview;
  return preview;
}

export function buildAgentTeamBindingPreview(
  draft: AgentTeamBindingDraft,
): AgentTeamBindingPreview {
  const agentId = stringValue(draft.agentId).trim();
  const channel = stringValue(draft.channel).trim();
  const accountId = stringValue(draft.accountId).trim();
  const explicitSpec = stringValue(draft.spec).trim();
  const simpleBinding = explicitSpec || (channel ? `${channel}${accountId ? `:${accountId}` : ""}` : "");
  const match: Record<string, unknown> = {};
  if (channel) {
    match.channel = channel;
  }
  if (accountId) {
    match.accountId = accountId;
  }
  const threadId = stringValue(draft.thread).trim();
  const peerId = threadId || stringValue(draft.peer).trim();
  if (peerId) {
    match.peer = {
      kind: threadId ? "thread" : stringValue(draft.peerKind).trim() || "group",
      id: peerId,
    };
  }
  if (stringValue(draft.group).trim()) {
    match.guildId = stringValue(draft.group).trim();
  }
  if (stringValue(draft.team).trim()) {
    match.teamId = stringValue(draft.team).trim();
  }
  const roles = splitCsv(stringValue(draft.roles));
  if (roles.length > 0) {
    match.roles = roles;
  }
  const routeBinding =
    agentId && Object.keys(match).length > 0
      ? ({
          type: "route",
          agentId,
          match,
        } as Record<string, unknown>)
      : null;
  if (routeBinding && stringValue(draft.comment).trim()) {
    routeBinding.comment = stringValue(draft.comment).trim();
  }
  const applyPayload = buildBindingApplyPayload(draft, agentId, simpleBinding, routeBinding);
  const lines = [
    "Gateway has no dedicated binding preview RPC in the current contract; this is a read-only preview of the apply payload.",
  ];
  if (simpleBinding) {
    lines.push(`Simple binding: ${simpleBinding}`);
  }
  if (routeBinding) {
    lines.push(`JSON binding: ${stringifyPretty(routeBinding)}`);
  }
  if (applyPayload) {
    lines.push(`Apply call: ${draft.mode === "unbind" ? "agents.unbind" : "agents.bind"} ${stringifyPretty(applyPayload)}`);
  }
  return {
    simpleBinding,
    routeBinding,
    applyPayload,
    lines,
  };
}

function buildBindingApplyPayload(
  draft: AgentTeamBindingDraft,
  agentId: string,
  simpleBinding: string,
  routeBinding: Record<string, unknown> | null,
): Record<string, unknown> | null {
  if (!agentId) {
    return null;
  }
  if (draft.useStructuredBinding) {
    if (!routeBinding) {
      return null;
    }
    return {
      agentId,
      bindings: [routeBinding],
    };
  }
  if (!simpleBinding) {
    return null;
  }
  return {
    agentId,
    bind: simpleBinding,
  };
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

export async function loadAgentTeamWorkspaceFiles(
  state: AgentTeamsState,
  agentId = state.agentTeamWorkspace.agentId,
) {
  const id = agentId.trim();
  if (!state.client || !state.connected || !id || state.agentTeamWorkspaceLoading) {
    return;
  }
  state.agentTeamWorkspaceLoading = true;
  state.agentTeamWorkspaceError = null;
  try {
    const res = await state.client.request<AgentsFilesListResult | null>("agents.files.list", {
      agentId: id,
    });
    if (res) {
      const files = filterProfileFiles(res.files ?? []);
      const current = state.agentTeamWorkspace.fileName;
      const fileName = files.some((file) => file.name === current) ? current : (files[0]?.name ?? "SOUL.md");
      state.agentTeamWorkspace = {
        ...state.agentTeamWorkspace,
        agentId: id,
        workspace: res.workspace ?? "",
        files,
        fileName,
      };
    }
  } catch (err) {
    state.agentTeamWorkspaceError = String(err);
  } finally {
    state.agentTeamWorkspaceLoading = false;
  }
}

export async function loadAgentTeamWorkspaceFile(
  state: AgentTeamsState,
  fileName = state.agentTeamWorkspace.fileName,
) {
  const agentId = state.agentTeamWorkspace.agentId.trim();
  const name = normalizeProfileFileName(fileName);
  if (!state.client || !state.connected || !agentId || !name || state.agentTeamWorkspaceLoading) {
    return;
  }
  state.agentTeamWorkspaceLoading = true;
  state.agentTeamWorkspaceError = null;
  try {
    const res = await state.client.request<AgentsFilesGetResult | null>("agents.files.get", {
      agentId,
      name,
    });
    if (res?.file) {
      const content = res.file.content ?? "";
      state.agentTeamWorkspace = {
        ...state.agentTeamWorkspace,
        workspace: res.workspace ?? state.agentTeamWorkspace.workspace,
        fileName: res.file.name,
        path: res.file.path,
        content,
        draft: content,
        files: mergeProfileFile(state.agentTeamWorkspace.files, res.file),
      };
    }
  } catch (err) {
    state.agentTeamWorkspaceError = String(err);
  } finally {
    state.agentTeamWorkspaceLoading = false;
  }
}

export async function saveAgentTeamWorkspaceFile(state: AgentTeamsState) {
  const agentId = state.agentTeamWorkspace.agentId.trim();
  const name = normalizeProfileFileName(state.agentTeamWorkspace.fileName);
  if (!state.client || !state.connected || !agentId || !name || state.agentTeamWorkspaceSaving) {
    return;
  }
  state.agentTeamWorkspaceSaving = true;
  state.agentTeamWorkspaceError = null;
  try {
    const content = state.agentTeamWorkspace.draft;
    const res = await state.client.request<AgentsFilesSetResult | null>("agents.files.set", {
      agentId,
      name,
      content,
    });
    if (res?.file) {
      state.agentTeamWorkspace = {
        ...state.agentTeamWorkspace,
        workspace: res.workspace ?? state.agentTeamWorkspace.workspace,
        fileName: res.file.name,
        path: res.file.path,
        content,
        draft: content,
        files: mergeProfileFile(state.agentTeamWorkspace.files, res.file),
      };
      state.agentTeamsSuccess = `${res.file.name} saved.`;
    }
  } catch (err) {
    state.agentTeamWorkspaceError = String(err);
  } finally {
    state.agentTeamWorkspaceSaving = false;
  }
}

export async function startAgentTeamFeishuOAuth(
  state: AgentTeamsState,
  accountId = "",
) {
  if (!state.client || !state.connected || state.agentTeamFeishuAuthLoading) {
    return;
  }
  state.agentTeamFeishuAuthLoading = true;
  state.agentTeamFeishuAuthError = null;
  state.agentTeamsSuccess = null;
  try {
    const params: Record<string, unknown> = {};
    const normalizedAccountId = accountId.trim();
    if (normalizedAccountId) {
      params.accountId = normalizedAccountId;
    }
    const res = await state.client.request<AgentTeamFeishuAuthResult>(
      "channels.feishu.auth.start",
      params,
    );
    state.agentTeamFeishuAuthResult = sanitizeFeishuAuthResult(res ?? {});
    state.agentTeamsSuccess = "Feishu OAuth started through Gateway RPC.";
  } catch (err) {
    state.agentTeamFeishuAuthError = String(err);
  } finally {
    state.agentTeamFeishuAuthLoading = false;
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
  const members = compactTeamMembers(parseJsonArray<AgentTeamMember>(draft.membersJson, "members"));
  if (members.length > 0) {
    payload.members = members;
  } else if (options.create && draft.template.trim()) {
    payload.template = draft.template.trim();
  }
  const defaultAgentId = normalizeDefaultAgentId(draft.defaultAgentId, members);
  if (defaultAgentId) {
    payload.defaultAgentId = defaultAgentId;
  }
  payload.aliases = compactTeamAliases(parseJsonArray<AgentTeamAliasDraft>(draft.aliasesJson, "aliases"));
  payload.bindings = parseJsonArray(draft.bindingsJson, "bindings");
  payload.broadcast = compactBroadcast(parseJsonObject(draft.broadcastJson, "broadcast"), members);
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

function splitCsv(text: string): string[] {
  return text
    .split(",")
    .map((part) => part.trim())
    .filter(Boolean);
}

function stringArrayValue(value: unknown): string[] {
  return Array.isArray(value)
    ? uniqueStrings(value.filter((item): item is string => typeof item === "string"))
    : [];
}

function uniqueStrings(values: string[]): string[] {
  const seen = new Set<string>();
  const result: string[] = [];
  for (const value of values) {
    const normalized = value.trim();
    if (!normalized || seen.has(normalized)) {
      continue;
    }
    seen.add(normalized);
    result.push(normalized);
  }
  return result;
}

function stringValue(value: string | undefined): string {
  return value ?? "";
}

function normalizeProfileFileName(name: string): string {
  const normalized = name.trim();
  return AGENT_TEAM_PROFILE_FILES.includes(normalized as (typeof AGENT_TEAM_PROFILE_FILES)[number])
    ? normalized
    : "";
}

function filterProfileFiles(files: AgentFileEntry[]): AgentFileEntry[] {
  const byName = new Map(files.map((file) => [file.name, file]));
  return AGENT_TEAM_PROFILE_FILES.map(
    (name) => byName.get(name) ?? { name, path: "", missing: true },
  );
}

function mergeProfileFile(files: AgentFileEntry[], entry: AgentFileEntry): AgentFileEntry[] {
  const next = filterProfileFiles(files);
  const index = next.findIndex((file) => file.name === entry.name);
  if (index >= 0) {
    next[index] = entry;
  }
  return next;
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

function compactTeamMembers(members: AgentTeamMember[]): AgentTeamMember[] {
  return members
    .map((member) => {
      const agentId = member.agentId?.trim() ?? "";
      const compact: AgentTeamMember = { agentId };
      if (member.role?.trim()) {
        compact.role = member.role.trim();
      }
      if (member.name?.trim()) {
        compact.name = member.name.trim();
      }
      return compact;
    })
    .filter((member) => Boolean(member.agentId));
}

function compactTeamAliases(aliases: AgentTeamAliasDraft[]): AgentTeamAliasDraft[] {
  return aliases
    .map((alias) => ({
      alias: alias.alias?.trim() ?? "",
      agentId: alias.agentId?.trim() ?? "",
    }))
    .filter((alias) => Boolean(alias.alias && alias.agentId));
}

function normalizeDefaultAgentId(defaultAgentId: string, members: AgentTeamMember[]): string {
  const normalized = defaultAgentId.trim();
  if (!normalized) {
    return "";
  }
  if (members.length === 0 || members.some((member) => member.agentId === normalized)) {
    return normalized;
  }
  return members[0]?.agentId ?? "";
}

function compactBroadcast(
  broadcast: Record<string, unknown>,
  members: AgentTeamMember[],
): Record<string, unknown> {
  if (!Array.isArray(broadcast.members)) {
    return broadcast;
  }
  const memberIds = new Set(members.map((member) => member.agentId));
  const selected = stringArrayValue(broadcast.members).filter(
    (agentId) => memberIds.size === 0 || memberIds.has(agentId),
  );
  return {
    ...broadcast,
    members: selected,
  };
}

function stringifyPretty(value: unknown): string {
  return JSON.stringify(value ?? null, null, 2);
}

function sanitizeFeishuAuthResult(value: AgentTeamFeishuAuthResult): AgentTeamFeishuAuthResult {
  const sanitized = deepRedact(value) as AgentTeamFeishuAuthResult;
  sanitized.redacted = true;
  return sanitized;
}

function deepRedact(value: unknown): unknown {
  if (Array.isArray(value)) {
    return value.map((item) => deepRedact(item));
  }
  if (value && typeof value === "object") {
    const out: Record<string, unknown> = {};
    Object.entries(value as Record<string, unknown>).forEach(([key, entry]) => {
      if (isSecretKey(key)) {
        out[key] = "[redacted]";
      } else {
        out[key] = deepRedact(entry);
      }
    });
    return out;
  }
  if (typeof value === "string") {
    return value.replace(/bearer\s+[^\s,;]+/gi, "Bearer [redacted]");
  }
  return value;
}

function isSecretKey(key: string): boolean {
  const normalized = key.toLowerCase().replace(/[-_]/g, "");
  return (
    normalized.includes("token") ||
    normalized.includes("secret") ||
    normalized === "authorization" ||
    normalized === "authheader"
  );
}
