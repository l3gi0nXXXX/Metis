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
  ChannelsStatusSnapshot,
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

export type AgentTeamTemplateId =
  | "pm-writer-reviewer"
  | "feishu-content-handoff"
  | "engineering-sprint"
  | "telegram-support-triage"
  | "data-insight-report"
  | "ops-campaign-launch";

export type AgentTeamTemplate = {
  id: AgentTeamTemplateId;
  label: string;
  description: string;
  category: "content" | "engineering" | "support" | "data" | "ops";
  transport: "feishu" | "telegram" | "generic";
  displayName: string;
  defaultAgentId: string;
  members: AgentTeamMember[];
  aliases: AgentTeamAliasDraft[];
  broadcast: Record<string, unknown>;
};

export type AgentTeamAliasDraft = {
  alias: string;
  agentId: string;
};

export type AgentTeamTemplateGroup = {
  id: AgentTeamTemplate["category"];
  label: string;
  templates: AgentTeamTemplate[];
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

export type AgentTeamCultivationFileSnapshot = {
  name: "MEMORY.md" | "HEARTBEAT.md";
  status: "loaded" | "present" | "missing";
  updatedAtMs?: number;
  preview: string;
};

export type AgentTeamDoctorFindingSnapshot = {
  code: string;
  message: string;
};

export type AgentTeamCultivationSnapshot = {
  agentId: string;
  memory: AgentTeamCultivationFileSnapshot;
  heartbeat: AgentTeamCultivationFileSnapshot;
  doctor: {
    status: string;
    lastProbeAt?: number;
    findings: AgentTeamDoctorFindingSnapshot[];
  };
};

export type AgentTeamAcceptanceStatus =
  | "local-pass"
  | "external-resource-required"
  | "operator-record-required";

export type AgentTeamAcceptanceItem = {
  title: string;
  status: AgentTeamAcceptanceStatus;
  detail: string;
  acceptance: string;
};

export type AgentTeamAcceptancePlan = {
  evidenceCommand: string;
  summary: {
    localPass: number;
    externalResourceRequired: number;
    operatorRecordRequired: number;
  };
  evidenceItems: AgentTeamAcceptanceItem[];
  externalItems: AgentTeamAcceptanceItem[];
};

export type AgentTeamReadinessStatus = "ready" | "needs-repair";

export type AgentTeamChannelReadiness = {
  channel: "telegram" | "feishu";
  label: string;
  status: AgentTeamReadinessStatus;
  routeStatus: string;
  accountStatus: string;
  runtimeStatus: string;
  authStatus: string;
  nextSteps: string[];
};

export type AgentTeamReadinessBoard = {
  summary: string;
  evidencePackHint: string;
  channels: AgentTeamChannelReadiness[];
};

export type AgentTeamBindingConflictStatus = "clear" | "warning" | "conflict";

export type AgentTeamBindingConflictItem = {
  status: AgentTeamBindingConflictStatus;
  title: string;
  detail: string;
  repair: string;
};

export type AgentTeamBindingConflictPreview = {
  summary: string;
  items: AgentTeamBindingConflictItem[];
};

export type AgentTeamFeishuAuthResult = Record<string, unknown>;
export type AgentTeamFeishuAuthAction = "start" | "status" | "poll" | "complete" | "revoke";

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
  "AGENTS.md",
  "SOUL.md",
  "TOOLS.md",
  "IDENTITY.md",
  "USER.md",
  "HEARTBEAT.md",
  "BOOTSTRAP.md",
  "MEMORY.md",
] as const;

export const AGENT_TEAM_TEMPLATES: AgentTeamTemplate[] = [
  {
    id: "pm-writer-reviewer",
    label: "PM / Writer / Reviewer",
    description: "Generic content team with deterministic fan-out.",
    category: "content",
    transport: "generic",
    displayName: "Content Team",
    defaultAgentId: "content-pm",
    members: [
      { agentId: "content-pm", role: "pm", name: "PM" },
      { agentId: "content-writer", role: "writer", name: "Writer" },
      { agentId: "content-reviewer", role: "reviewer", name: "Reviewer" },
    ],
    aliases: [
      { alias: "@pm", agentId: "content-pm" },
      { alias: "@writer", agentId: "content-writer" },
      { alias: "@reviewer", agentId: "content-reviewer" },
    ],
    broadcast: {
      enabled: true,
      members: ["content-pm", "content-writer", "content-reviewer"],
      mode: "fan-out",
    },
  },
  {
    id: "feishu-content-handoff",
    label: "Feishu content handoff",
    description: "Manager delegation pattern for Feishu group workflows.",
    category: "content",
    transport: "feishu",
    displayName: "Feishu Content Team",
    defaultAgentId: "feishu-manager",
    members: [
      { agentId: "feishu-manager", role: "manager", name: "Manager" },
      { agentId: "feishu-writer", role: "writer", name: "Writer" },
      { agentId: "feishu-reviewer", role: "reviewer", name: "Reviewer" },
    ],
    aliases: [
      { alias: "@manager", agentId: "feishu-manager" },
      { alias: "@writer", agentId: "feishu-writer" },
      { alias: "@reviewer", agentId: "feishu-reviewer" },
    ],
    broadcast: {
      enabled: true,
      members: ["feishu-manager", "feishu-writer", "feishu-reviewer"],
      mode: "manager-delegation",
    },
  },
  {
    id: "engineering-sprint",
    label: "Engineering sprint",
    description: "Planner, implementer, reviewer, and release notes roles for development loops.",
    category: "engineering",
    transport: "generic",
    displayName: "Engineering Sprint Team",
    defaultAgentId: "eng-planner",
    members: [
      { agentId: "eng-planner", role: "planner", name: "Planner" },
      { agentId: "eng-implementer", role: "implementer", name: "Implementer" },
      { agentId: "eng-reviewer", role: "reviewer", name: "Reviewer" },
      { agentId: "eng-release", role: "release", name: "Release" },
    ],
    aliases: [
      { alias: "@planner", agentId: "eng-planner" },
      { alias: "@dev", agentId: "eng-implementer" },
      { alias: "@review", agentId: "eng-reviewer" },
      { alias: "/agent release", agentId: "eng-release" },
    ],
    broadcast: {
      enabled: true,
      members: ["eng-planner", "eng-implementer", "eng-reviewer"],
      mode: "review-loop",
    },
  },
  {
    id: "telegram-support-triage",
    label: "Telegram support triage",
    description: "Triage, answer, and escalation team for Telegram chats.",
    category: "support",
    transport: "telegram",
    displayName: "Telegram Support Team",
    defaultAgentId: "telegram-triage",
    members: [
      { agentId: "telegram-triage", role: "triage", name: "Triage" },
      { agentId: "telegram-answer", role: "answer", name: "Answer" },
      { agentId: "telegram-escalation", role: "escalation", name: "Escalation" },
    ],
    aliases: [
      { alias: "@triage", agentId: "telegram-triage" },
      { alias: "@answer", agentId: "telegram-answer" },
      { alias: "@escalate", agentId: "telegram-escalation" },
    ],
    broadcast: {
      enabled: true,
      members: ["telegram-triage", "telegram-answer", "telegram-escalation"],
      mode: "fan-out",
    },
  },
  {
    id: "data-insight-report",
    label: "Data insight report",
    description: "Analyst, charting, and narrative roles for structured reporting.",
    category: "data",
    transport: "generic",
    displayName: "Data Insight Team",
    defaultAgentId: "data-analyst",
    members: [
      { agentId: "data-analyst", role: "analyst", name: "Analyst" },
      { agentId: "data-viz", role: "visualization", name: "Visualization" },
      { agentId: "data-narrator", role: "narrative", name: "Narrator" },
    ],
    aliases: [
      { alias: "@analyst", agentId: "data-analyst" },
      { alias: "@chart", agentId: "data-viz" },
      { alias: "@report", agentId: "data-narrator" },
    ],
    broadcast: {
      enabled: true,
      members: ["data-analyst", "data-viz", "data-narrator"],
      mode: "report-chain",
    },
  },
  {
    id: "ops-campaign-launch",
    label: "Ops campaign launch",
    description: "Operations owner, copy, QA, and customer response roles for campaign launches.",
    category: "ops",
    transport: "feishu",
    displayName: "Ops Campaign Team",
    defaultAgentId: "ops-owner",
    members: [
      { agentId: "ops-owner", role: "owner", name: "Owner" },
      { agentId: "ops-copy", role: "copy", name: "Copy" },
      { agentId: "ops-qa", role: "qa", name: "QA" },
      { agentId: "ops-support", role: "support", name: "Support" },
    ],
    aliases: [
      { alias: "@owner", agentId: "ops-owner" },
      { alias: "@copy", agentId: "ops-copy" },
      { alias: "@qa", agentId: "ops-qa" },
      { alias: "@support", agentId: "ops-support" },
    ],
    broadcast: {
      enabled: true,
      members: ["ops-owner", "ops-copy", "ops-qa", "ops-support"],
      mode: "launch-readiness",
    },
  },
];

export const AGENT_TEAM_TEMPLATE_GROUPS: AgentTeamTemplateGroup[] = [
  { id: "content", label: "内容", templates: AGENT_TEAM_TEMPLATES.filter((template) => template.category === "content") },
  { id: "engineering", label: "研发", templates: AGENT_TEAM_TEMPLATES.filter((template) => template.category === "engineering") },
  { id: "support", label: "客服", templates: AGENT_TEAM_TEMPLATES.filter((template) => template.category === "support") },
  { id: "data", label: "数据", templates: AGENT_TEAM_TEMPLATES.filter((template) => template.category === "data") },
  { id: "ops", label: "运营", templates: AGENT_TEAM_TEMPLATES.filter((template) => template.category === "ops") },
];

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

export function buildAgentTeamCultivationSnapshot(params: {
  workspace: AgentTeamWorkspaceDraft;
  channelsSnapshot: ChannelsStatusSnapshot | null;
}): AgentTeamCultivationSnapshot {
  const doctor = resolveFeishuDoctor(params.channelsSnapshot);
  return {
    agentId: params.workspace.agentId.trim(),
    memory: buildCultivationFileSnapshot(params.workspace, "MEMORY.md"),
    heartbeat: buildCultivationFileSnapshot(params.workspace, "HEARTBEAT.md"),
    doctor: {
      status: stringValue(doctor?.status) || stringValue(doctor?.state) || (doctor ? "available" : "missing"),
      lastProbeAt: numberValue(doctor?.lastProbeAt),
      findings: extractDoctorFindings(doctor),
    },
  };
}

export function buildAgentTeamAcceptancePlan(params: {
  teamCount: number;
  memberCount: number;
  bindingCount: number;
  hasModelState: boolean;
  hasWorkspaceProfile: boolean;
  channelsSnapshot: ChannelsStatusSnapshot | null;
}): AgentTeamAcceptancePlan {
  const telegramStatus = channelStatus(params.channelsSnapshot, "telegram");
  const feishuStatus = channelStatus(params.channelsSnapshot, "feishu");
  const feishuAuth = objectValue(feishuStatus.raw?.auth) ?? objectValue(feishuStatus.raw?.oauth);
  const feishuCapabilities = stringArrayValue(feishuStatus.raw?.capabilities).map((capability) =>
    capability.toLowerCase(),
  );
  const appScopeGaps = scopeList(feishuAuth, ["missingAppScopes", "missing_app_scopes", "appScopeMissing"]);
  const userScopeGaps = scopeList(feishuAuth, ["missingUserScopes", "missing_user_scopes", "userScopeMissing"]);
  const oapiVisible = feishuCapabilities.some(
    (capability) => capability.includes("oapi") || capability.includes("openapi"),
  );
  const evidenceItems: AgentTeamAcceptanceItem[] = [
    {
      title: "Team CRUD, members, aliases, bindings, and broadcast",
      status: "local-pass",
      detail: [
        countText(params.teamCount, "team"),
        countText(params.memberCount, "member"),
        `${countText(params.bindingCount, "binding")} visible from Gateway RPC`,
      ].join(" · "),
      acceptance: "Create, edit, delete, and refresh a team without using IM commands or local config files.",
    },
    {
      title: "Profile, model, and binding editors",
      status: "local-pass",
      detail: [
        params.hasWorkspaceProfile ? "workspace/profile loaded" : "workspace/profile editor available",
        params.hasModelState ? "model state loaded" : "model editor available",
        "route preview is browser-local until Apply",
      ].join(" · "),
      acceptance: "Profile and model changes go through agents.files and agents.models Gateway RPC.",
    },
    {
      title: "Template import/export and route preview",
      status: "local-pass",
      detail: "metis.agentTeamTemplate.v1 excludes tokens, secrets, and local auth files.",
      acceptance: "Export/import template JSON and preview Telegram or Feishu routes before applying.",
    },
    {
      title: "Manual gate evidence pack",
      status: "operator-record-required",
      detail: "Run the manual acceptance gate from an operator shell and attach its redacted report.",
      acceptance: "Report records local-pass, external-resource-required, skipped, and operator notes without real tokens.",
    },
  ];
  const externalItems: AgentTeamAcceptanceItem[] = [
    {
      title: "Telegram bot, DM, group, topic, and broadcast",
      status: "external-resource-required",
      detail: telegramStatus.accountCount > 0
        ? `Gateway status sees ${telegramStatus.accountCount} Telegram account(s); live acceptance still needs test bot, private chat, group, topic, and broadcast evidence.`
        : "Requires a test Telegram bot, private chat, group, topic, and broadcast run; local UI can only prepare route bindings.",
      acceptance: "Collect redacted inbound, route, broadcast fan-out, and reply evidence from real Telegram chats.",
    },
    {
      title: "Feishu existing app/bot and two accountIds",
      status: "external-resource-required",
      detail: `${feishuStatus.accountCount} Feishu account(s) visible. ` +
        "Control UI provides guided setup and linking an existing Feishu bot; " +
        "it does not create a Feishu app or bot.",
      acceptance: "Use real test apps/bots, two accountIds, a test tenant, test user, group, and thread.",
    },
    {
      title: "Feishu OAuth, OAPI scopes, and low-risk resources",
      status: "external-resource-required",
      detail: [
        `OAuth ${statusLabel(feishuAuth, "not visible")}`,
        `OAPI ${oapiVisible ? "visible" : "not advertised"}`,
        `app scopes ${scopeSummary(appScopeGaps)}`,
        `user scopes ${scopeSummary(userScopeGaps)}`,
      ].join(" · "),
      acceptance: "Complete offline_access OAuth and low-risk doc/wiki/calendar/task/bitable/sheet/im smoke against test resources.",
    },
    {
      title: "Feishu CardKit and rich event live smoke",
      status: "external-resource-required",
      detail: "Needs real card create/patch/finalize/abort plus image, file, audio, video, reaction, quote, and forward events.",
      acceptance: "Collect redacted card fallback/success and rich-event resource evidence from a real Feishu test group.",
    },
  ];
  return {
    evidenceCommand: "scripts/agentteam-manual-acceptance-gate.sh",
    summary: countAcceptanceStatuses([...evidenceItems, ...externalItems]),
    evidenceItems,
    externalItems,
  };
}

export function buildAgentTeamReadinessBoard(params: {
  draft: AgentTeamEditorDraft;
  channelsSnapshot: ChannelsStatusSnapshot | null;
}): AgentTeamReadinessBoard {
  const bindings = parseDraftBindings(params.draft);
  const channels: AgentTeamChannelReadiness[] = [
    buildChannelReadiness("telegram", "Telegram", params.channelsSnapshot, bindings),
    buildChannelReadiness("feishu", "Feishu", params.channelsSnapshot, bindings),
  ];
  const readyCount = channels.filter((channel) => channel.status === "ready").length;
  const repairCount = channels.length - readyCount;
  return {
    summary: `${readyCount} ready · ${repairCount} needs repair`,
    evidencePackHint: "Run scripts/agentteam-manual-acceptance-gate.sh after browser smoke and attach the redacted report.",
    channels,
  };
}

export function buildAgentTeamBindingConflictPreview(
  draft: AgentTeamEditorDraft,
  binding: AgentTeamBindingDraft,
): AgentTeamBindingConflictPreview {
  const preview = buildAgentTeamBindingPreview(binding);
  const current = routeDescriptorFromBinding(preview.routeBinding);
  if (!current) {
    return {
      summary: "No structured route preview",
      items: [
        {
          status: "warning",
          title: "Preview structured route first",
          detail: "Conflict detection needs a JSON route binding preview with channel, account, peer, thread, or team fields.",
          repair: "Switch Payload type to JSON route binding or fill channel route fields before applying.",
        },
      ],
    };
  }

  const conflicts = parseDraftBindings(draft)
    .map((entry) => routeDescriptorFromBinding(entry))
    .filter((entry): entry is RouteDescriptor => Boolean(entry))
    .filter((entry) => routeDescriptorsConflict(entry, current));
  if (conflicts.length === 0) {
    return {
      summary: "No conflicts",
      items: [
        {
          status: "clear",
          title: "No matching route conflict",
          detail: `${formatRouteDescriptor(current)} is not already assigned in this team draft.`,
          repair: "Preview the apply payload, then apply through Gateway RPC when ready.",
        },
      ],
    };
  }

  const items = conflicts.map((conflict) => {
    const sameAgent = conflict.agentId === current.agentId;
    return {
      status: sameAgent ? "warning" : "conflict",
      title: sameAgent ? "Route already exists for this member" : "Route already targets another member",
      detail: `${formatRouteDescriptor(current)} is already assigned to ${conflict.agentId}.`,
      repair: sameAgent
        ? "Review whether this duplicate route should be removed from team bindings before applying."
        : "Change the member, account, peer, thread, or team before applying this binding.",
    } satisfies AgentTeamBindingConflictItem;
  });
  const hardConflicts = items.filter((item) => item.status === "conflict").length;
  const warnings = items.length - hardConflicts;
  return {
    summary: hardConflicts > 0
      ? `${hardConflicts} conflict${hardConflicts === 1 ? "" : "s"}`
      : `${warnings} warning${warnings === 1 ? "" : "s"}`,
    items,
  };
}

export function applyAgentTeamTemplate(
  draft: AgentTeamEditorDraft,
  templateId: string,
): AgentTeamEditorDraft {
  const template = AGENT_TEAM_TEMPLATES.find((entry) => entry.id === templateId);
  if (!template) {
    return { ...draft, template: templateId };
  }
  return {
    ...draft,
    displayName: draft.displayName.trim() ? draft.displayName : template.displayName,
    template: template.id,
    defaultAgentId: template.defaultAgentId,
    membersJson: stringifyPretty(template.members),
    aliasesJson: stringifyPretty(template.aliases),
    broadcastJson: stringifyPretty(template.broadcast),
  };
}

export function exportAgentTeamTemplate(draft: AgentTeamEditorDraft): string {
  const members = compactTeamMembers(parseJsonArray<AgentTeamMember>(draft.membersJson, "members"));
  return stringifyPretty({
    schema: "metis.agentTeamTemplate.v1",
    team: {
      id: draft.id.trim(),
      displayName: draft.displayName.trim(),
      template: draft.template.trim(),
      defaultAgentId: normalizeDefaultAgentId(draft.defaultAgentId, members),
      members,
      aliases: compactTeamAliases(parseJsonArray<AgentTeamAliasDraft>(draft.aliasesJson, "aliases")),
      bindings: parseJsonArray(draft.bindingsJson, "bindings"),
      broadcast: compactBroadcast(parseJsonObject(draft.broadcastJson, "broadcast"), members),
    },
  });
}

export function importAgentTeamTemplate(text: string): AgentTeamEditorDraft {
  const root = parseJsonObject(text, "team template");
  if (root.schema !== "metis.agentTeamTemplate.v1") {
    throw new Error("team template schema must be metis.agentTeamTemplate.v1.");
  }
  const team = objectValue(root.team);
  if (!team) {
    throw new Error("team template must include a team object.");
  }
  return {
    id: stringValue(team.id),
    displayName: stringValue(team.displayName),
    template: stringValue(team.template),
    defaultAgentId: stringValue(team.defaultAgentId),
    membersJson: stringifyPretty(Array.isArray(team.members) ? team.members : []),
    aliasesJson: stringifyPretty(Array.isArray(team.aliases) ? team.aliases : []),
    bindingsJson: stringifyPretty(Array.isArray(team.bindings) ? team.bindings : []),
    broadcastJson: stringifyPretty(objectValue(team.broadcast) ?? { enabled: false }),
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
  action: AgentTeamFeishuAuthAction = "start",
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
    if (action === "revoke") {
      params.serverRevoke = false;
    }
    const res = await state.client.request<AgentTeamFeishuAuthResult>(
      `channels.feishu.auth.${action}`,
      params,
    );
    state.agentTeamFeishuAuthResult = sanitizeFeishuAuthResult(res ?? {});
    state.agentTeamsSuccess = feishuAuthActionSuccessMessage(action);
  } catch (err) {
    state.agentTeamFeishuAuthError = String(err);
  } finally {
    state.agentTeamFeishuAuthLoading = false;
  }
}

function feishuAuthActionSuccessMessage(action: AgentTeamFeishuAuthAction): string {
  switch (action) {
    case "status":
      return "Feishu OAuth status loaded through Gateway RPC.";
    case "poll":
      return "Feishu OAuth poll completed through Gateway RPC.";
    case "complete":
      return "Feishu OAuth completion checked through Gateway RPC.";
    case "revoke":
      return "Local Feishu OAuth authorization revoked through Gateway RPC.";
    default:
      return "Feishu OAuth started through Gateway RPC.";
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

function stringValue(value: unknown): string {
  return typeof value === "string" ? value : "";
}

function channelStatus(snapshot: ChannelsStatusSnapshot | null, channel: string): {
  raw: Record<string, unknown> | null;
  accountCount: number;
} {
  const raw = objectValue(snapshot?.channels?.[channel]);
  const accounts = snapshot?.channelAccounts?.[channel] ?? [];
  return {
    raw,
    accountCount: accounts.length,
  };
}

type RouteDescriptor = {
  agentId: string;
  channel: string;
  accountId: string;
  peer: string;
  teamId: string;
};

function buildChannelReadiness(
  channel: "telegram" | "feishu",
  label: string,
  snapshot: ChannelsStatusSnapshot | null,
  bindings: Record<string, unknown>[],
): AgentTeamChannelReadiness {
  const status = objectValue(snapshot?.channels?.[channel]);
  const accounts = snapshot?.channelAccounts?.[channel] ?? [];
  const configured = status?.configured === true ||
    status?.running === true ||
    accounts.some((account) => account.configured === true || account.running === true || account.connected === true);
  const routeCount = bindings.filter((binding) => routeBindingChannel(binding) === channel).length;
  const nextSteps = channel === "telegram"
    ? telegramReadinessSteps(configured, routeCount)
    : feishuReadinessSteps(status, accounts.length, routeCount);
  return {
    channel,
    label,
    status: configured ? "ready" : "needs-repair",
    routeStatus: routeCount === 0 ? "no route" : countText(routeCount, "route"),
    accountStatus: countText(accounts.length, "account"),
    runtimeStatus: status?.running === true ? "running" : status?.configured === true ? "configured" : "not configured",
    authStatus: channel === "feishu"
      ? statusLabel(objectValue(status?.auth) ?? objectValue(status?.oauth), "not visible")
      : "managed by bot token behind Gateway",
    nextSteps,
  };
}

function telegramReadinessSteps(configured: boolean, routeCount: number): string[] {
  const steps: string[] = [];
  if (!configured) {
    steps.push("Configure the test Telegram bot/proxy behind Gateway.");
  }
  if (routeCount === 0) {
    steps.push("Preview and apply a Telegram route binding for the team.");
  }
  steps.push("Collect live Telegram DM, group, topic, and broadcast evidence.");
  return steps;
}

function feishuReadinessSteps(
  status: Record<string, unknown> | null,
  accountCount: number,
  routeCount: number,
): string[] {
  const auth = objectValue(status?.auth) ?? objectValue(status?.oauth);
  const appScopes = scopeList(auth, ["missingAppScopes", "missing_app_scopes", "appScopeMissing"]);
  const userScopes = scopeList(auth, ["missingUserScopes", "missing_user_scopes", "userScopeMissing"]);
  const steps: string[] = [];
  if (status?.configured !== true || accountCount === 0) {
    steps.push("Configure an existing Feishu app/bot behind Gateway.");
  }
  if (routeCount === 0) {
    steps.push("Preview and apply a Feishu route binding for the team.");
  }
  if (!isAuthorizedStatus(auth)) {
    steps.push("Start or repair Feishu OAuth through Gateway RPC.");
  }
  if (appScopes.length > 0) {
    steps.push(`Grant app scopes: ${appScopes.join(", ")}.`);
  }
  if (userScopes.length > 0) {
    steps.push(`Grant user scopes through OAuth: ${userScopes.join(", ")}.`);
  }
  steps.push("Run /feishu doctor or refresh channels.status after repair.");
  return steps;
}

function isAuthorizedStatus(auth: Record<string, unknown> | null): boolean {
  const status = statusLabel(auth, "").toLowerCase();
  return status === "authorized" || status === "ok" || status === "ready";
}

function parseDraftBindings(draft: AgentTeamEditorDraft): Record<string, unknown>[] {
  try {
    return parseJsonArray(draft.bindingsJson, "bindings")
      .map((entry) => objectValue(entry))
      .filter((entry): entry is Record<string, unknown> => Boolean(entry));
  } catch (_err) {
    return [];
  }
}

function routeBindingChannel(binding: Record<string, unknown>): string {
  return routeDescriptorFromBinding(binding)?.channel || "";
}

function routeDescriptorFromBinding(binding: Record<string, unknown> | null): RouteDescriptor | null {
  if (!binding) {
    return null;
  }
  const match = objectValue(binding.match);
  const channel = stringValue(match?.channel ?? binding.channel).trim();
  if (!channel) {
    return null;
  }
  return {
    agentId: stringValue(binding.agentId).trim(),
    channel,
    accountId: stringValue(match?.accountId ?? binding.accountId).trim(),
    peer: routePeerKey(match?.peer),
    teamId: stringValue(match?.teamId ?? binding.teamId).trim(),
  };
}

function routePeerKey(peer: unknown): string {
  if (typeof peer === "string") {
    return peer.trim();
  }
  const obj = objectValue(peer);
  if (!obj) {
    return "";
  }
  const kind = stringValue(obj.kind).trim();
  const id = stringValue(obj.id).trim();
  if (!id) {
    return "";
  }
  return kind ? `${kind}:${id}` : id;
}

function routeDescriptorsConflict(left: RouteDescriptor, right: RouteDescriptor): boolean {
  return left.channel === right.channel &&
    left.accountId === right.accountId &&
    left.peer === right.peer &&
    left.teamId === right.teamId;
}

function formatRouteDescriptor(route: RouteDescriptor): string {
  return [
    route.channel,
    route.accountId,
    route.peer,
    route.teamId ? `team:${route.teamId}` : "",
  ]
    .filter(Boolean)
    .join(" ");
}

function countAcceptanceStatuses(items: AgentTeamAcceptanceItem[]): AgentTeamAcceptancePlan["summary"] {
  return {
    localPass: items.filter((item) => item.status === "local-pass").length,
    externalResourceRequired: items.filter((item) => item.status === "external-resource-required").length,
    operatorRecordRequired: items.filter((item) => item.status === "operator-record-required").length,
  };
}

function scopeList(auth: Record<string, unknown> | null, keys: string[]): string[] {
  if (!auth) {
    return [];
  }
  for (const key of keys) {
    const value = auth[key];
    if (Array.isArray(value)) {
      return value.map((item) => stringValue(item).trim()).filter(Boolean);
    }
    if (typeof value === "string" && value.trim()) {
      return value.split(",").map((item) => item.trim()).filter(Boolean);
    }
  }
  return [];
}

function statusLabel(value: Record<string, unknown> | null, fallback: string): string {
  if (!value) {
    return fallback;
  }
  return stringValue(value.status) || stringValue(value.tokenStatus) || fallback;
}

function scopeSummary(scopes: string[]): string {
  return scopes.length > 0 ? scopes.join(", ") : "none reported";
}

function countText(count: number, noun: string): string {
  return `${count} ${noun}${count === 1 ? "" : "s"}`;
}

function numberValue(value: unknown): number | undefined {
  return typeof value === "number" && Number.isFinite(value) ? value : undefined;
}

function objectValue(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null;
}

function buildCultivationFileSnapshot(
  workspace: AgentTeamWorkspaceDraft,
  name: "MEMORY.md" | "HEARTBEAT.md",
): AgentTeamCultivationFileSnapshot {
  const file = workspace.files.find((entry) => entry.name === name);
  const loaded = workspace.fileName === name;
  return {
    name,
    status: loaded ? "loaded" : file && !file.missing ? "present" : "missing",
    updatedAtMs: file?.updatedAtMs,
    preview: loaded ? summarizeProfileText(workspace.draft) : "",
  };
}

function summarizeProfileText(text: string): string {
  const redacted = String(deepRedact(text) ?? "").trim();
  if (!redacted) {
    return "";
  }
  return redacted.length > 220 ? `${redacted.slice(0, 220)}...` : redacted;
}

function resolveFeishuDoctor(snapshot: ChannelsStatusSnapshot | null): Record<string, unknown> | null {
  const feishu = objectValue(snapshot?.channels?.feishu);
  return objectValue(feishu?.doctor) ?? objectValue(feishu?.diagnostics);
}

function extractDoctorFindings(doctor: Record<string, unknown> | null): AgentTeamDoctorFindingSnapshot[] {
  if (!doctor) {
    return [];
  }
  const findings = doctor.findings;
  if (Array.isArray(findings)) {
    return findings
      .map((entry) => doctorFindingFromUnknown(entry))
      .filter((entry): entry is AgentTeamDoctorFindingSnapshot => Boolean(entry));
  }
  const message = stringValue(doctor.message) || stringValue(doctor.error);
  if (!message) {
    return [];
  }
  return [{ code: stringValue(doctor.code) || "doctor_message", message: redactDiagnosticText(message) }];
}

function doctorFindingFromUnknown(value: unknown): AgentTeamDoctorFindingSnapshot | null {
  if (typeof value === "string") {
    return { code: "finding", message: redactDiagnosticText(value) };
  }
  const obj = objectValue(value);
  if (!obj) {
    return null;
  }
  const code = stringValue(obj.code) || stringValue(obj.id) || stringValue(obj.kind) || "finding";
  const message = stringValue(obj.message) || stringValue(obj.detail) || stringValue(obj.reason) || code;
  return {
    code: redactDiagnosticText(code),
    message: redactDiagnosticText(message),
  };
}

function redactDiagnosticText(text: string): string {
  return String(deepRedact(text) ?? "");
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
