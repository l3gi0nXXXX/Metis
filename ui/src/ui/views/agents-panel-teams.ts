import { html, nothing } from "lit";
import { t } from "../../i18n/index.ts";
import type {
  AgentBindingsResult,
  AgentModelsResult,
  AgentTeam,
  AgentTeamMember,
  AgentTeamsListResult,
  ChannelAccountSnapshot,
  ChannelsStatusSnapshot,
} from "../types.ts";
import {
  addAgentTeamAlias,
  addAgentTeamMember,
  AGENT_TEAM_PROFILE_FILES,
  buildAgentTeamBindingPreview,
  changeAgentTeamAlias,
  changeAgentTeamMember,
  removeAgentTeamAlias,
  removeAgentTeamMember,
  setAgentTeamBroadcastEnabled,
  setAgentTeamBroadcastMember,
  setAgentTeamBroadcastMembers,
  type AgentTeamAliasDraft,
  type AgentTeamBindingDraft,
  type AgentTeamBindingPreview,
  type AgentTeamEditorDraft,
  type AgentTeamModelDraft,
  type AgentTeamWorkspaceDraft,
} from "../controllers/agent-teams.ts";

export type AgentTeamsPanelState = {
  loading: boolean;
  saving: boolean;
  error: string | null;
  success: string | null;
  list: AgentTeamsListResult | null;
  selectedId: string | null;
  detail: AgentTeam | null;
  draft: AgentTeamEditorDraft;
  binding: AgentTeamBindingDraft;
  bindingPreview: AgentTeamBindingPreview | null;
  bindingResult: AgentBindingsResult | null;
  modelLoading: boolean;
  modelError: string | null;
  modelResult: AgentModelsResult | null;
  modelDraft: AgentTeamModelDraft;
  workspaceLoading: boolean;
  workspaceSaving: boolean;
  workspaceError: string | null;
  workspace: AgentTeamWorkspaceDraft;
  channelsSnapshot: ChannelsStatusSnapshot | null;
  configForm: Record<string, unknown> | null;
};

export type AgentTeamsPanelProps = AgentTeamsPanelState & {
  onRefresh: () => void;
  onSelectTeam: (teamId: string) => void;
  onNewTeam: () => void;
  onDraftChange: (patch: Partial<AgentTeamEditorDraft>) => void;
  onCreateTeam: () => void;
  onUpdateTeam: () => void;
  onDeleteTeam: () => void;
  onBindingChange: (patch: Partial<AgentTeamBindingDraft>) => void;
  onPreviewBinding: () => void;
  onApplyBinding: () => void;
  onModelDraftChange: (patch: Partial<AgentTeamModelDraft>) => void;
  onLoadModel: () => void;
  onSaveModel: () => void;
  onWorkspaceChange: (patch: Partial<AgentTeamWorkspaceDraft>) => void;
  onLoadWorkspaceFiles: () => void;
  onLoadWorkspaceFile: (name: string) => void;
  onSaveWorkspaceFile: () => void;
};

export function renderAgentTeamsPanel(props: AgentTeamsPanelProps) {
  const teams = props.list?.teams ?? [];
  const draftMembers = safeMembersFromJson(props.draft.membersJson);
  const activeMembers = draftMembers.length > 0 ? draftMembers : (props.detail?.members ?? []);
  const draftAliases = safeAliasesFromJson(props.draft.aliasesJson);
  const activeAliases = draftAliases.length > 0 ? draftAliases : teamAliases(props.detail);
  const activeBroadcast = safeBroadcastFromJson(props.draft.broadcastJson, props.detail?.broadcast);
  const selectedTeamLabel = props.detail
    ? teamDisplayName(props.detail)
    : props.selectedId
      ? props.selectedId
      : "New team";
  return html`
    ${renderWorkflowStrip(props, activeMembers, activeBroadcast)}

    <section class="grid grid-cols-2">
      ${renderTeamsList(props, teams)}
      ${renderTeamEditor(
        props,
        selectedTeamLabel,
        draftMembers,
        activeMembers,
        activeAliases,
        activeBroadcast,
      )}
    </section>

    <section class="grid grid-cols-2" style="margin-top: 16px;">
      ${renderBindingCard(props, activeMembers)}
      ${renderWorkspaceProfileCard(props, activeMembers)}
    </section>

    <section class="grid grid-cols-2" style="margin-top: 16px;">
      ${renderModelCard(props, activeMembers)}
      ${renderFeishuSettingsCard(props)}
    </section>

    <section style="margin-top: 16px;">
      ${renderDoctorPanel(props, teams, activeMembers)}
    </section>
  `;
}

function renderWorkflowStrip(
  props: AgentTeamsPanelProps,
  members: AgentTeamMember[],
  broadcast: Record<string, unknown>,
) {
  const steps = [
    {
      label: props.detail ? "Edit team" : "Create team",
      status: props.draft.id ? "ready" : "needs key",
    },
    { label: "Members", status: formatCount(members.length, "member") },
    { label: "Default", status: memberDisplayName(props.draft.defaultAgentId, members) },
    {
      label: "Bindings",
      status: formatCount(safeJsonArrayLength(props.draft.bindingsJson), "binding"),
    },
    { label: "Profiles", status: props.workspace.workspace ? "workspace loaded" : "choose member" },
    { label: "Models", status: props.modelResult?.models?.path ? "models.json loaded" : "load model" },
    {
      label: "Feishu",
      status: (props.channelsSnapshot?.channelAccounts?.feishu ?? []).length
        ? "status visible"
        : "status missing",
    },
    {
      label: "Broadcast",
      status: broadcastEnabled(broadcast)
        ? `${stringArrayFromUnknown(broadcast.members).length} selected`
        : "disabled",
    },
  ];
  return html`
    <section class="card" style="margin-bottom: 16px;">
      <div class="row" style="justify-content: space-between; align-items: flex-start;">
        <div>
          <div class="card-title">Guided workflow</div>
          <div class="card-sub">Create or edit a team, then walk through members, routing, profiles, model state, and Feishu status.</div>
        </div>
        <span class="badge">Gateway RPC only</span>
      </div>
      <div class="agents-overview-grid" style="margin-top: 14px;">
        ${steps.map(
          (step) => html`
            <div class="agent-kv">
              <div class="label">${step.label}</div>
              <div>${step.status}</div>
            </div>
          `,
        )}
      </div>
    </section>
  `;
}

function renderTeamsList(props: AgentTeamsPanelProps, teams: AgentTeam[]) {
  return html`
    <section class="card">
      <div class="row" style="justify-content: space-between; align-items: flex-start;">
        <div>
          <div class="card-title">Agent Teams</div>
          <div class="card-sub">Manage team definitions through Gateway AgentTeam RPC.</div>
        </div>
        <div class="row" style="gap: 8px;">
          <button type="button" class="btn btn--sm" ?disabled=${props.loading} @click=${props.onRefresh}>
            ${props.loading ? t("common.refreshing") : t("common.refresh")}
          </button>
          <button type="button" class="btn btn--sm btn--ghost" @click=${props.onNewTeam}>
            New
          </button>
        </div>
      </div>
      ${props.error ? html`<div class="callout danger" style="margin-top: 12px;">${props.error}</div>` : nothing}
      ${props.success ? html`<div class="callout success" style="margin-top: 12px;">${props.success}</div>` : nothing}
      ${teams.length === 0
        ? html`<div class="callout info" style="margin-top: 12px;">No teams are configured yet.</div>`
        : html`
            <div class="list" style="margin-top: 16px;">
              ${teams.map(
                (team) => html`
                  <button
                    type="button"
                    class="list-item"
                    style="width: 100%; text-align: left;"
                    @click=${() => props.onSelectTeam(team.id)}
                    aria-pressed=${team.id === props.selectedId ? "true" : "false"}
                  >
                    <div class="list-main">
                      <div class="list-title">${teamDisplayName(team)}</div>
                      <div class="list-sub">
                        ${formatCount(team.members?.length ?? 0, "member")} ·
                        ${formatCount(team.aliases?.length ?? 0, "alias")} · default
                        ${memberDisplayName(team.defaultAgentId, team.members ?? [])}
                      </div>
                    </div>
                    <div class="list-meta">
                      <span class="badge">${formatCount(team.bindings?.length ?? 0, "binding")}</span>
                      <span class="badge">${broadcastEnabled(team.broadcast) ? "broadcast on" : "broadcast off"}</span>
                    </div>
                  </button>
                `,
              )}
            </div>
          `}
    </section>
  `;
}

function renderTeamEditor(
  props: AgentTeamsPanelProps,
  selectedTeamLabel: string,
  draftMembers: AgentTeamMember[],
  activeMembers: AgentTeamMember[],
  activeAliases: AgentTeamAliasDraft[],
  activeBroadcast: Record<string, unknown>,
) {
  return html`
    <section class="card">
      <div class="card-title">${selectedTeamLabel}</div>
      <div class="card-sub">Create teams, edit members, and keep JSON metadata available for compatibility.</div>
      ${renderTeamSummary(activeMembers, activeAliases, props.draft.bindingsJson, activeBroadcast)}
      <div class="grid grid-cols-2" style="margin-top: 14px;">
        <label class="field">
          <span>Team key</span>
          <input
            .value=${props.draft.id}
            ?disabled=${Boolean(props.detail)}
            placeholder="content"
            @input=${(e: Event) => props.onDraftChange({ id: inputValue(e) })}
          />
        </label>
        <label class="field">
          <span>Display name</span>
          <input
            .value=${props.draft.displayName}
            placeholder="Content Team"
            @input=${(e: Event) => props.onDraftChange({ displayName: inputValue(e) })}
          />
        </label>
        <label class="field">
          <span>Template</span>
          <select
            .value=${props.draft.template}
            ?disabled=${Boolean(props.detail) || draftMembers.length > 0}
            @change=${(e: Event) => props.onDraftChange({ template: selectValue(e) })}
          >
            <option value="pm-writer-reviewer">PM / Writer / Reviewer</option>
            <option value="">Custom members</option>
          </select>
        </label>
        <label class="field">
          <span>Default member</span>
          <select
            .value=${props.draft.defaultAgentId}
            @change=${(e: Event) => props.onDraftChange({ defaultAgentId: selectValue(e) })}
          >
            <option value="">First member</option>
            ${activeMembers.map(
              (member) => html`
                <option value=${member.agentId}>${memberDisplayName(member.agentId, activeMembers)}</option>
              `,
            )}
          </select>
        </label>
      </div>

      <div class="row" style="justify-content: space-between; margin-top: 16px;">
        <div>
          <div class="list-title">Members</div>
          <div class="muted">Each member becomes an agent-scoped workspace and model profile.</div>
        </div>
        <button
          type="button"
          class="btn btn--sm"
          @click=${() => props.onDraftChange(addAgentTeamMember(props.draft))}
        >
          Add Member
        </button>
      </div>
      ${draftMembers.length === 0
        ? html`<div class="callout info" style="margin-top: 12px;">Use a template, or add members for a custom team.</div>`
        : html`
            <div class="list" style="margin-top: 12px;">
              ${draftMembers.map((member, index) => renderMemberRow(props, member, index))}
            </div>
          `}

      ${renderAliasEditor(props, activeMembers)}
      ${renderBroadcastEditor(props, activeMembers, activeBroadcast)}

      <details style="margin-top: 14px;">
        <summary class="muted">Advanced metadata JSON</summary>
        ${renderJsonField("Aliases JSON", props.draft.aliasesJson, (aliasesJson) =>
          props.onDraftChange({ aliasesJson }),
        )}
        ${renderJsonField("Team bindings JSON", props.draft.bindingsJson, (bindingsJson) =>
          props.onDraftChange({ bindingsJson }),
        )}
        ${renderJsonField("Broadcast JSON", props.draft.broadcastJson, (broadcastJson) =>
          props.onDraftChange({ broadcastJson }),
        )}
      </details>

      <div class="agent-model-actions">
        <button
          type="button"
          class="btn btn--sm primary"
          ?disabled=${props.saving || Boolean(props.detail)}
          @click=${props.onCreateTeam}
        >
          ${props.saving && !props.detail ? "Creating..." : "Create Team"}
        </button>
        <button
          type="button"
          class="btn btn--sm"
          ?disabled=${props.saving || !props.detail}
          @click=${props.onUpdateTeam}
        >
          ${props.saving && props.detail ? "Saving..." : "Save Team"}
        </button>
        <button
          type="button"
          class="btn btn--sm btn--ghost"
          ?disabled=${props.saving || !props.detail}
          @click=${props.onDeleteTeam}
        >
          Delete
        </button>
      </div>
    </section>
  `;
}

function renderMemberRow(props: AgentTeamsPanelProps, member: AgentTeamMember, index: number) {
  return html`
    <div class="list-item">
      <div class="list-main">
        <div class="grid grid-cols-3">
          <label class="field">
            <span>Agent id</span>
            <input
              .value=${member.agentId ?? ""}
              placeholder="content-writer"
              @input=${(e: Event) =>
                props.onDraftChange(changeAgentTeamMember(props.draft, index, { agentId: inputValue(e) }))}
            />
          </label>
          <label class="field">
            <span>Role</span>
            <input
              .value=${member.role ?? ""}
              placeholder="writer"
              @input=${(e: Event) =>
                props.onDraftChange(changeAgentTeamMember(props.draft, index, { role: inputValue(e) }))}
            />
          </label>
          <label class="field">
            <span>Name</span>
            <input
              .value=${member.name ?? ""}
              placeholder="Writer"
              @input=${(e: Event) =>
                props.onDraftChange(changeAgentTeamMember(props.draft, index, { name: inputValue(e) }))}
            />
          </label>
        </div>
      </div>
      <div class="list-meta">
        <button
          type="button"
          class="btn btn--sm btn--ghost"
          @click=${() => props.onDraftChange(removeAgentTeamMember(props.draft, index))}
        >
          Remove
        </button>
      </div>
    </div>
  `;
}

function renderTeamSummary(
  members: AgentTeamMember[],
  aliases: AgentTeamAliasDraft[],
  bindingsJson: string,
  broadcast: Record<string, unknown>,
) {
  return html`
    <div class="agents-overview-grid" style="margin-top: 14px;">
      <div class="agent-kv">
        <div class="label">Members</div>
        <div>${formatCount(members.length, "member")}</div>
      </div>
      <div class="agent-kv">
        <div class="label">Aliases</div>
        <div>${formatCount(aliases.length, "alias")}</div>
      </div>
      <div class="agent-kv">
        <div class="label">Bindings</div>
        <div>${formatCount(safeJsonArrayLength(bindingsJson), "binding")}</div>
      </div>
      <div class="agent-kv">
        <div class="label">Broadcast</div>
        <div>${broadcastEnabled(broadcast) ? "Broadcast enabled" : "Broadcast disabled"}</div>
      </div>
    </div>
  `;
}

function renderAliasEditor(props: AgentTeamsPanelProps, members: AgentTeamMember[]) {
  const aliases = safeAliasesFromJson(props.draft.aliasesJson);
  return html`
    <div class="row" style="justify-content: space-between; margin-top: 16px;">
      <div>
        <div class="list-title">Aliases</div>
        <div class="muted">Map mention text such as @writer or /agent writer to a member.</div>
      </div>
      <button
        type="button"
        class="btn btn--sm"
        @click=${() => props.onDraftChange(addAgentTeamAlias(props.draft))}
      >
        Add Alias
      </button>
    </div>
    ${aliases.length === 0
      ? html`<div class="callout info" style="margin-top: 12px;">No aliases are configured.</div>`
      : html`
          <div class="list" style="margin-top: 12px;">
            ${aliases.map((alias, index) => renderAliasRow(props, members, alias, index))}
          </div>
        `}
  `;
}

function renderAliasRow(
  props: AgentTeamsPanelProps,
  members: AgentTeamMember[],
  alias: AgentTeamAliasDraft,
  index: number,
) {
  return html`
    <div class="list-item">
      <div class="list-main">
        <div class="grid grid-cols-2">
          <label class="field">
            <span>Alias</span>
            <input
              .value=${alias.alias ?? ""}
              placeholder="@writer"
              @input=${(e: Event) =>
                props.onDraftChange(changeAgentTeamAlias(props.draft, index, { alias: inputValue(e) }))}
            />
          </label>
          <label class="field">
            <span>Member</span>
            <select
              .value=${alias.agentId ?? ""}
              @change=${(e: Event) =>
                props.onDraftChange(changeAgentTeamAlias(props.draft, index, { agentId: selectValue(e) }))}
            >
              <option value="">Choose member</option>
              ${members.map(
                (member) =>
                  html`<option value=${member.agentId}>${memberDisplayName(member.agentId, members)}</option>`,
              )}
            </select>
          </label>
        </div>
      </div>
      <div class="list-meta">
        <button
          type="button"
          class="btn btn--sm btn--ghost"
          @click=${() => props.onDraftChange(removeAgentTeamAlias(props.draft, index))}
        >
          Remove
        </button>
      </div>
    </div>
  `;
}

function renderBroadcastEditor(
  props: AgentTeamsPanelProps,
  members: AgentTeamMember[],
  broadcast: Record<string, unknown>,
) {
  const enabled = broadcastEnabled(broadcast);
  const selectedMembers = stringArrayFromUnknown(broadcast.members);
  return html`
    <div style="margin-top: 16px;">
      <div class="row" style="justify-content: space-between; align-items: flex-start;">
        <div>
          <div class="list-title">Broadcast</div>
          <div class="muted">Gateway persists this team fan-out plan; runtime fan-out remains a partial capability.</div>
        </div>
        <div class="row" style="gap: 8px; align-items: center;">
          <button
            type="button"
            class="btn btn--sm btn--ghost"
            ?disabled=${!enabled || members.length === 0}
            @click=${() => props.onDraftChange(setAgentTeamBroadcastMembers(props.draft, members, true))}
          >
            Select all members
          </button>
          <button
            type="button"
            class="btn btn--sm btn--ghost"
            ?disabled=${!enabled}
            @click=${() => props.onDraftChange(setAgentTeamBroadcastMembers(props.draft, members, false))}
          >
            Clear selected
          </button>
          <label class="row" style="gap: 8px;">
            <input
              type="checkbox"
              ?checked=${enabled}
              @change=${(e: Event) =>
                props.onDraftChange(setAgentTeamBroadcastEnabled(props.draft, checkedValue(e)))}
            />
            <span>${enabled ? "Broadcast enabled" : "Broadcast disabled"}</span>
          </label>
        </div>
      </div>
      <div class="list" style="margin-top: 12px;">
        ${members.map((member) => {
          const selected = selectedMembers.includes(member.agentId);
          return html`
            <label class="list-item" style="cursor: pointer;">
              <div class="list-main">
                <div class="list-title">${memberDisplayName(member.agentId, members)}</div>
                <div class="list-sub">${selected ? "Included in broadcast" : "Not included"}</div>
              </div>
              <div class="list-meta">
                <input
                  type="checkbox"
                  ?checked=${selected}
                  ?disabled=${!enabled}
                  @change=${(e: Event) =>
                    props.onDraftChange(
                      setAgentTeamBroadcastMember(props.draft, member.agentId, checkedValue(e)),
                    )}
                />
              </div>
            </label>
          `;
        })}
      </div>
    </div>
  `;
}

function renderBindingCard(props: AgentTeamsPanelProps, members: AgentTeamMember[]) {
  const preview = props.bindingPreview ?? buildAgentTeamBindingPreview(props.binding);
  return html`
    <section class="card">
      <div class="card-title">Binding Builder</div>
      <div class="card-sub">Build channel/account/peer/thread/group/team/role routes before applying them.</div>
      <div class="grid grid-cols-2" style="margin-top: 14px;">
        <label class="field">
          <span>Member</span>
          <select .value=${props.binding.agentId} @change=${(e: Event) => props.onBindingChange({ agentId: selectValue(e) })}>
            <option value="">Choose member</option>
            ${members.map((member) => html`<option value=${member.agentId}>${memberDisplayName(member.agentId, members)}</option>`)}
          </select>
        </label>
        <label class="field">
          <span>Action</span>
          <select
            .value=${props.binding.mode}
            @change=${(e: Event) =>
              props.onBindingChange({ mode: selectValue(e) === "unbind" ? "unbind" : "bind" })}
          >
            <option value="bind">Apply</option>
            <option value="unbind">Remove</option>
          </select>
        </label>
        <label class="field">
          <span>Payload type</span>
          <select
            .value=${props.binding.useStructuredBinding ? "structured" : "simple"}
            @change=${(e: Event) =>
              props.onBindingChange({ useStructuredBinding: selectValue(e) === "structured" })}
          >
            <option value="simple">Simple binding</option>
            <option value="structured">JSON route binding</option>
          </select>
        </label>
        <label class="field">
          <span>Simple binding</span>
          <input
            .value=${props.binding.spec}
            placeholder="feishu:tenant-a"
            @input=${(e: Event) => props.onBindingChange({ spec: inputValue(e) })}
          />
        </label>
        ${renderBindingTextInput(props, "Channel", "channel", "feishu")}
        ${renderBindingTextInput(props, "Account", "accountId", "tenant-a")}
        ${renderBindingTextInput(props, "Peer kind", "peerKind", "group")}
        ${renderBindingTextInput(props, "Peer id", "peer", "chat:oc_123")}
        ${renderBindingTextInput(props, "Thread", "thread", "thread:om_456")}
        ${renderBindingTextInput(props, "Group", "group", "chat:oc_123")}
        ${renderBindingTextInput(props, "Team", "team", "content")}
        ${renderBindingTextInput(props, "Roles", "roles", "writer,reviewer")}
      </div>
      <label class="field" style="margin-top: 12px;">
        <span>Comment</span>
        <input
          .value=${props.binding.comment}
          placeholder="content team route"
          @input=${(e: Event) => props.onBindingChange({ comment: inputValue(e) })}
        />
      </label>
      <div class="agent-model-actions">
        <button type="button" class="btn btn--sm" @click=${props.onPreviewBinding}>Preview</button>
        <button
          type="button"
          class="btn btn--sm primary"
          ?disabled=${props.saving || !props.binding.agentId || !preview.applyPayload}
          @click=${props.onApplyBinding}
        >
          ${props.binding.mode === "unbind" ? "Remove Binding" : "Apply Binding"}
        </button>
      </div>
      <div class="callout info" style="margin-top: 12px;">
        <pre style="white-space: pre-wrap; margin: 0;">${preview.lines.join("\n")}</pre>
      </div>
      ${props.bindingResult
        ? html`<div class="callout success" style="margin-top: 12px;">${bindingSummary(props.bindingResult)}</div>`
        : nothing}
    </section>
  `;
}

function renderBindingTextInput(
  props: AgentTeamsPanelProps,
  label: string,
  key: keyof AgentTeamBindingDraft,
  placeholder: string,
) {
  return html`
    <label class="field">
      <span>${label}</span>
      <input
        .value=${String(props.binding[key] ?? "")}
        placeholder=${placeholder}
        @input=${(e: Event) => props.onBindingChange({ [key]: inputValue(e) } as Partial<AgentTeamBindingDraft>)}
      />
    </label>
  `;
}

function renderWorkspaceProfileCard(props: AgentTeamsPanelProps, members: AgentTeamMember[]) {
  return html`
    <section class="card">
      <div class="card-title">Workspace Profiles</div>
      <div class="card-sub">Edit Gateway-supported workspace files via agents.files RPC.</div>
      ${props.workspaceError
        ? html`<div class="callout danger" style="margin-top: 12px;">${props.workspaceError}</div>`
        : nothing}
      <div class="grid grid-cols-2" style="margin-top: 14px;">
        <label class="field">
          <span>Member</span>
          <select
            .value=${props.workspace.agentId}
            @change=${(e: Event) => props.onWorkspaceChange({ agentId: selectValue(e) })}
          >
            <option value="">Choose member</option>
            ${members.map((member) => html`<option value=${member.agentId}>${memberDisplayName(member.agentId, members)}</option>`)}
          </select>
        </label>
        <label class="field">
          <span>Profile file</span>
          <select
            .value=${props.workspace.fileName}
            @change=${(e: Event) => {
              const name = selectValue(e);
              props.onWorkspaceChange({ fileName: name });
              props.onLoadWorkspaceFile(name);
            }}
          >
            ${AGENT_TEAM_PROFILE_FILES.map((name) => html`<option value=${name}>${name}</option>`)}
          </select>
        </label>
      </div>
      ${props.workspace.workspace
        ? html`
            <div class="agent-kv" style="margin-top: 12px;">
              <div class="label">Workspace</div>
              <div class="mono">${props.workspace.workspace}</div>
            </div>
          `
        : nothing}
      ${props.workspace.path
        ? html`
            <div class="agent-kv" style="margin-top: 12px;">
              <div class="label">File path</div>
              <div class="mono">${props.workspace.path}</div>
            </div>
          `
        : nothing}
      <label class="field agent-file-field" style="margin-top: 12px;">
        <span>${props.workspace.fileName}</span>
        <textarea
          class="agent-file-textarea"
          rows="12"
          .value=${props.workspace.draft}
          @input=${(e: Event) => props.onWorkspaceChange({ draft: textareaValue(e) })}
        ></textarea>
      </label>
      <div class="agent-model-actions">
        <button
          type="button"
          class="btn btn--sm"
          ?disabled=${props.workspaceLoading || !props.workspace.agentId}
          @click=${props.onLoadWorkspaceFiles}
        >
          ${props.workspaceLoading ? "Loading..." : "List Files"}
        </button>
        <button
          type="button"
          class="btn btn--sm"
          ?disabled=${props.workspaceLoading || !props.workspace.agentId || !props.workspace.fileName}
          @click=${() => props.onLoadWorkspaceFile(props.workspace.fileName)}
        >
          Load
        </button>
        <button
          type="button"
          class="btn btn--sm primary"
          ?disabled=${props.workspaceSaving || !props.workspace.agentId || !props.workspace.fileName}
          @click=${props.onSaveWorkspaceFile}
        >
          ${props.workspaceSaving ? "Saving..." : "Save"}
        </button>
      </div>
    </section>
  `;
}

function renderModelCard(props: AgentTeamsPanelProps, members: AgentTeamMember[]) {
  const model = props.modelResult?.models ?? null;
  return html`
    <section class="card">
      <div class="card-title">Model Editor</div>
      <div class="card-sub">Read and write per-agent models.json through Gateway.</div>
      ${props.modelError ? html`<div class="callout danger" style="margin-top: 12px;">${props.modelError}</div>` : nothing}
      <div class="grid grid-cols-2" style="margin-top: 14px;">
        <label class="field">
          <span>Member</span>
          <select
            .value=${props.modelDraft.agentId}
            @change=${(e: Event) => props.onModelDraftChange({ agentId: selectValue(e) })}
          >
            <option value="">Choose member</option>
            ${members.map((member) => html`<option value=${member.agentId}>${memberDisplayName(member.agentId, members)}</option>`)}
          </select>
        </label>
        <div class="field">
          <span>Provider status</span>
          <input
            readonly
            .value=${model
              ? `${model.providerCount ?? 0} providers · ${model.present ? "models.json present" : "new file"}`
              : "Load member model"}
          />
        </div>
      </div>
      <div class="grid grid-cols-2" style="margin-top: 12px;">
        <label class="field">
          <span>Primary model ref</span>
          <input
            .value=${props.modelDraft.primaryModelRef}
            placeholder="openai:gpt-5-mini"
            @input=${(e: Event) => props.onModelDraftChange({ primaryModelRef: inputValue(e) })}
          />
        </label>
        <label class="field">
          <span>Runtime primary model ref</span>
          <input
            .value=${props.modelDraft.runtimePrimaryModelRef}
            placeholder="openai:gpt-5-mini"
            @input=${(e: Event) => props.onModelDraftChange({ runtimePrimaryModelRef: inputValue(e) })}
          />
        </label>
      </div>
      ${model?.path
        ? html`
            <div class="agent-kv" style="margin-top: 12px;">
              <div class="label">models.json path</div>
              <div class="mono">${model.path}</div>
            </div>
          `
        : nothing}
      ${renderJsonField("models.json state", props.modelDraft.stateJson, (stateJson) =>
        props.onModelDraftChange({ stateJson }),
      )}
      <div class="agent-model-actions">
        <button
          type="button"
          class="btn btn--sm"
          ?disabled=${props.modelLoading || !props.modelDraft.agentId}
          @click=${props.onLoadModel}
        >
          ${props.modelLoading ? "Loading..." : "Load Model"}
        </button>
        <button
          type="button"
          class="btn btn--sm primary"
          ?disabled=${props.saving || !props.modelDraft.agentId}
          @click=${props.onSaveModel}
        >
          ${props.saving ? "Saving..." : "Save Model"}
        </button>
      </div>
    </section>
  `;
}

function renderFeishuSettingsCard(props: AgentTeamsPanelProps) {
  const feishu = resolveFeishuSettings(props);
  return html`
    <section class="card">
      <div class="card-title">Feishu Settings</div>
      <div class="card-sub">Non-secret channel settings and account runtime snapshot.</div>
      <div class="callout info" style="margin-top: 12px;">
        Team-agent parity is partial. This panel reports Gateway status and explicit missing
        capabilities without implying OAuth, OAPI tools, or interactive cards are complete.
      </div>
      <div class="agents-overview-grid" style="margin-top: 14px;">
        <div class="agent-kv">
          <div class="label">Default Account</div>
          <div class="mono">${feishu.defaultAccount || "not configured"}</div>
        </div>
        <div class="agent-kv">
          <div class="label">Thread Session</div>
          <div>${feishu.threadSession}</div>
        </div>
        <div class="agent-kv">
          <div class="label">Groups</div>
          <div>${feishu.groupCount}</div>
        </div>
        <div class="agent-kv">
          <div class="label">Accounts</div>
          <div>${feishu.accounts.length}</div>
        </div>
      </div>
      ${feishu.accounts.length === 0
        ? html`<div class="callout info" style="margin-top: 12px;">No Feishu accounts are visible in channels.status yet.</div>`
        : html`
            <div class="list" style="margin-top: 12px;">
              ${feishu.accounts.map(
                (account) => html`
                  <div class="list-item">
                    <div class="list-main">
                      <div class="list-title">${account.name || account.accountId}</div>
                      <div class="list-sub mono">${account.accountId}</div>
                    </div>
                    <div class="list-meta">
                      <div>${account.configured ? "configured" : "not configured"}</div>
                      <div>${account.running || account.connected ? "active" : "stopped"}</div>
                    </div>
                    ${account.lastError
                      ? html`
                          <div class="list-sub" style="margin-top: 8px;">
                            Last error: ${redactSecretText(account.lastError)}
                          </div>
                        `
                      : nothing}
                  </div>
                `,
              )}
            </div>
          `}
      <div class="callout info" style="margin-top: 12px;">
        Feishu commands: /feishu start, /feishu doctor, /feishu auth, /feishu info --all.
        Status shown here is read-only and redacted; secrets stay behind Gateway configuration and auth storage.
      </div>
      ${renderFeishuCapabilityGaps(props)}
    </section>
  `;
}

function renderFeishuCapabilityGaps(props: AgentTeamsPanelProps) {
  const status = objectValue(props.channelsSnapshot?.channels?.feishu);
  const capabilities = stringArrayFromUnknown(status?.capabilities);
  const authState = objectValue(status?.auth) ?? objectValue(status?.oauth);
  const doctorState = objectValue(status?.doctor) ?? objectValue(status?.diagnostics);
  const hasOauth = Boolean(authState) || capabilities.some((item) => item.includes("oauth"));
  const hasOapi = capabilities.some((item) => item.includes("oapi") || item.includes("openapi"));
  const hasDoctor = Boolean(doctorState) || capabilities.some((item) => item.includes("doctor"));
  const rows = [
    {
      title: "Account status",
      message: (props.channelsSnapshot?.channelAccounts?.feishu ?? []).length
        ? "channels.status exposes redacted Feishu account state."
        : "No Feishu accounts are visible in channels.status.",
      status: (props.channelsSnapshot?.channelAccounts?.feishu ?? []).length ? "available" : "missing",
    },
    {
      title: "OAuth",
      message: hasOauth
        ? "Gateway exposes Feishu auth status."
        : "OAuth missing from the current status contract.",
      status: hasOauth ? "available" : "missing",
    },
    {
      title: "OAPI tools",
      message: hasOapi
        ? "Gateway advertises Feishu OAPI tool capability."
        : "Docs/wiki/calendar/task/bitable OAPI tools are not advertised here.",
      status: hasOapi ? "available" : "missing",
    },
    {
      title: "Doctor",
      message: hasDoctor
        ? "Gateway exposes Feishu doctor diagnostics."
        : "Doctor status is not exposed to this panel; use Gateway or /feishu doctor when available.",
      status: hasDoctor ? "available" : "missing",
    },
  ];
  return html`
    <div style="margin-top: 14px;">
      <div class="list-title">Capability gaps</div>
      <div class="list" style="margin-top: 8px;">
        ${rows.map(
          (row) => html`
            <div class="list-item">
              <div class="list-main">
                <div class="list-title">${row.title} ${row.status}</div>
                <div class="list-sub">${row.message}</div>
              </div>
              <div class="list-meta"><span class="badge">${row.status}</span></div>
            </div>
          `,
        )}
      </div>
    </div>
  `;
}

function renderDoctorPanel(
  props: AgentTeamsPanelProps,
  teams: AgentTeam[],
  members: AgentTeamMember[],
) {
  const items = buildDoctorItems(props, teams, members);
  return html`
    <section class="card">
      <div class="row" style="justify-content: space-between;">
        <div>
          <div class="card-title">Doctor</div>
          <div class="card-sub">Local UI checks for team, binding, model, profile, and Feishu readiness.</div>
        </div>
        <button type="button" class="btn btn--sm" ?disabled=${props.loading} @click=${props.onRefresh}>
          ${props.loading ? t("common.refreshing") : t("common.refresh")}
        </button>
      </div>
      <div class="list" style="margin-top: 14px;">
        ${items.map(
          (item) => html`
            <div class="list-item">
              <div class="list-main">
                <div class="list-title">${item.title}</div>
                <div class="list-sub">${item.message}</div>
              </div>
              <div class="list-meta"><span class="badge">${item.status}</span></div>
            </div>
          `,
        )}
      </div>
    </section>
  `;
}

function renderJsonField(label: string, value: string, onChange: (value: string) => void) {
  return html`
    <label class="field agent-file-field" style="margin-top: 12px;">
      <span>${label}</span>
      <textarea
        class="agent-file-textarea"
        rows="6"
        .value=${value}
        @input=${(e: Event) => onChange(textareaValue(e))}
      ></textarea>
    </label>
  `;
}

function teamDisplayName(team: AgentTeam) {
  return team.displayName?.trim() || team.id;
}

function memberDisplayName(agentId: string | undefined, members: AgentTeamMember[]) {
  if (!agentId) {
    return "first configured member";
  }
  const member = members.find((entry) => entry.agentId === agentId);
  if (!member) {
    return agentId;
  }
  const label = member.name?.trim() || member.role?.trim() || member.agentId;
  return `${label} (${member.agentId})`;
}

function bindingSummary(result: AgentBindingsResult) {
  const parts = [
    result.added?.length ? `${result.added.length} added` : "",
    result.removed?.length ? `${result.removed.length} removed` : "",
    result.skipped?.length ? `${result.skipped.length} skipped` : "",
    result.missing?.length ? `${result.missing.length} missing` : "",
    result.conflicts?.length ? `${result.conflicts.length} conflicts` : "",
  ].filter(Boolean);
  return parts.length ? parts.join(", ") : "Gateway accepted the binding request.";
}

function safeMembersFromJson(text: string): AgentTeamMember[] {
  try {
    const parsed = JSON.parse(text || "[]") as unknown;
    return Array.isArray(parsed) ? (parsed as AgentTeamMember[]) : [];
  } catch (_err) {
    return [];
  }
}

function safeAliasesFromJson(text: string): AgentTeamAliasDraft[] {
  try {
    const parsed = JSON.parse(text || "[]") as unknown;
    if (!Array.isArray(parsed)) {
      return [];
    }
    return parsed
      .map((item) => objectValue(item))
      .filter((item): item is Record<string, unknown> => Boolean(item))
      .map((item) => ({
        alias: stringOrEmpty(item.alias),
        agentId: stringOrEmpty(item.agentId),
      }))
      .filter((item) => item.alias || item.agentId);
  } catch (_err) {
    return [];
  }
}

function teamAliases(team: AgentTeam | null): AgentTeamAliasDraft[] {
  if (!Array.isArray(team?.aliases)) {
    return [];
  }
  return team.aliases
    .map((item) => objectValue(item))
    .filter((item): item is Record<string, unknown> => Boolean(item))
    .map((item) => ({
      alias: stringOrEmpty(item.alias),
      agentId: stringOrEmpty(item.agentId),
    }))
    .filter((item) => item.alias || item.agentId);
}

function safeBroadcastFromJson(
  text: string,
  fallback?: Record<string, unknown>,
): Record<string, unknown> {
  try {
    const parsed = JSON.parse(text || "{}") as unknown;
    return objectValue(parsed) ?? fallback ?? { enabled: false };
  } catch (_err) {
    return fallback ?? { enabled: false };
  }
}

function broadcastEnabled(value: unknown): boolean {
  return objectValue(value)?.enabled === true;
}

function safeJsonArrayLength(text: string): number {
  try {
    const parsed = JSON.parse(text || "[]") as unknown;
    return Array.isArray(parsed) ? parsed.length : 0;
  } catch (_err) {
    return 0;
  }
}

function formatCount(count: number, label: string): string {
  return `${count} ${label}${count === 1 ? "" : "s"}`;
}

function stringArrayFromUnknown(value: unknown): string[] {
  return Array.isArray(value)
    ? value.filter((item): item is string => typeof item === "string").map((item) => item.trim()).filter(Boolean)
    : [];
}

function resolveFeishuSettings(props: AgentTeamsPanelProps): {
  defaultAccount: string;
  threadSession: string;
  groupCount: number;
  accounts: ChannelAccountSnapshot[];
} {
  const gateway = objectValue(props.configForm?.gateway);
  const feishu = objectValue(gateway?.feishu ?? props.configForm?.feishu);
  const accountsObject = objectValue(feishu?.accounts);
  const groupsObject = objectValue(feishu?.groups);
  const runtimeAccounts = props.channelsSnapshot?.channelAccounts?.feishu ?? [];
  const configuredAccounts = accountsObject ? Object.keys(accountsObject) : [];
  const defaultAccount =
    stringOrEmpty(feishu?.defaultAccount) ||
    props.channelsSnapshot?.channelDefaultAccountId?.feishu ||
    runtimeAccounts[0]?.accountId ||
    configuredAccounts[0] ||
    "";
  const accounts =
    runtimeAccounts.length > 0
      ? runtimeAccounts
      : configuredAccounts.map((accountId) => ({ accountId, configured: true }));
  return {
    defaultAccount,
    threadSession: stringOrEmpty(feishu?.threadSession) || stringOrEmpty(feishu?.groupSessionScope) || "not configured",
    groupCount: groupsObject ? Object.keys(groupsObject).length : 0,
    accounts,
  };
}

function buildDoctorItems(
  props: AgentTeamsPanelProps,
  teams: AgentTeam[],
  members: AgentTeamMember[],
): Array<{ title: string; message: string; status: string }> {
  return [
    {
      title: "Teams list",
      message: teams.length > 0 ? `${teams.length} team definitions loaded.` : "No team definitions loaded.",
      status: teams.length > 0 ? "ok" : "info",
    },
    {
      title: "Members",
      message: members.length > 0 ? `${members.length} members available for edit.` : "No members selected.",
      status: members.length > 0 ? "ok" : "warn",
    },
    {
      title: "Binding preview",
      message: props.bindingPreview?.applyPayload ? "Apply payload is ready." : "Preview a binding before applying.",
      status: props.bindingPreview?.applyPayload ? "ok" : "info",
    },
    {
      title: "Workspace profiles",
      message: props.workspace.workspace
        ? `Workspace loaded: ${props.workspace.workspace}`
        : "Choose a member and list files.",
      status: props.workspace.workspace ? "ok" : "info",
    },
    {
      title: "Model profile",
      message: props.modelResult?.models?.path ? `models.json: ${props.modelResult.models.path}` : "Load a member model.",
      status: props.modelResult?.models?.path ? "ok" : "info",
    },
    {
      title: "Feishu accounts",
      message:
        (props.channelsSnapshot?.channelAccounts?.feishu ?? []).length > 0
          ? "Feishu account status is visible."
          : "No Feishu account status in channels.status.",
      status: (props.channelsSnapshot?.channelAccounts?.feishu ?? []).length > 0 ? "ok" : "info",
    },
  ];
}

function objectValue(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null;
}

function stringOrEmpty(value: unknown): string {
  return typeof value === "string" ? value : "";
}

function redactSecretText(value: string): string {
  return value
    .replace(/authorization:\s*bearer\s+[^\s,;]+/gi, "Authorization: Bearer [redacted]")
    .replace(/\b(access|refresh|bot|app)[_-]?token\s*[:=]\s*[^\s,;]+/gi, "$1_token=[redacted]")
    .replace(/\b(app[_-]?secret|authorization)\s*[:=]\s*[^\s,;]+/gi, "$1=[redacted]");
}

function inputValue(event: Event): string {
  return (event.target as HTMLInputElement).value;
}

function selectValue(event: Event): string {
  return (event.target as HTMLSelectElement).value;
}

function textareaValue(event: Event): string {
  return (event.target as HTMLTextAreaElement).value;
}

function checkedValue(event: Event): boolean {
  return (event.target as HTMLInputElement).checked;
}
