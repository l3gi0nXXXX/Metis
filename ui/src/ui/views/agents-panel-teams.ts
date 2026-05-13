import { html, nothing } from "lit";
import { t } from "../../i18n/index.ts";
import type {
  AgentBindingsResult,
  AgentModelsResult,
  AgentTeam,
  AgentTeamMember,
  AgentTeamsListResult,
} from "../types.ts";
import type {
  AgentTeamBindingDraft,
  AgentTeamEditorDraft,
  AgentTeamModelDraft,
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
  bindingResult: AgentBindingsResult | null;
  modelLoading: boolean;
  modelError: string | null;
  modelResult: AgentModelsResult | null;
  modelDraft: AgentTeamModelDraft;
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
  onApplyBinding: () => void;
  onModelDraftChange: (patch: Partial<AgentTeamModelDraft>) => void;
  onLoadModel: () => void;
  onSaveModel: () => void;
};

export function renderAgentTeamsPanel(props: AgentTeamsPanelProps) {
  const teams = props.list?.teams ?? [];
  const members = props.detail?.members ?? [];
  const selectedTeamLabel = props.detail
    ? teamDisplayName(props.detail)
    : props.selectedId
      ? props.selectedId
      : "New team";
  return html`
    <section class="grid grid-cols-2">
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
        ${props.error
          ? html`<div class="callout danger" style="margin-top: 12px;">${props.error}</div>`
          : nothing}
        ${props.success
          ? html`<div class="callout success" style="margin-top: 12px;">${props.success}</div>`
          : nothing}
        ${teams.length === 0
          ? html`
              <div class="callout info" style="margin-top: 12px;">
                No teams are configured yet.
              </div>
            `
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
                          ${team.members?.length ?? 0} members · default
                          ${memberDisplayName(team.defaultAgentId, team.members ?? [])}
                        </div>
                      </div>
                      <div class="list-meta">
                        <span class="badge">${team.bindings?.length ?? 0} bindings</span>
                      </div>
                    </button>
                  `,
                )}
              </div>
            `}
      </section>

      <section class="card">
        <div class="card-title">${selectedTeamLabel}</div>
        <div class="card-sub">Create or update team metadata, members, aliases, and draft bindings.</div>
        <div class="grid grid-cols-2" style="margin-top: 14px;">
          <label class="field">
            <span>Team key</span>
            <input
              .value=${props.draft.id}
              ?disabled=${Boolean(props.detail)}
              placeholder="content"
              @input=${(e: Event) =>
                props.onDraftChange({ id: (e.target as HTMLInputElement).value })}
            />
          </label>
          <label class="field">
            <span>Display name</span>
            <input
              .value=${props.draft.displayName}
              placeholder="Content Team"
              @input=${(e: Event) =>
                props.onDraftChange({ displayName: (e.target as HTMLInputElement).value })}
            />
          </label>
          <label class="field">
            <span>Template for new team</span>
            <select
              .value=${props.draft.template}
              ?disabled=${Boolean(props.detail)}
              @change=${(e: Event) =>
                props.onDraftChange({ template: (e.target as HTMLSelectElement).value })}
            >
              <option value="pm-writer-reviewer">PM / Writer / Reviewer</option>
              <option value="">Custom members JSON</option>
            </select>
          </label>
          <label class="field">
            <span>Default member</span>
            <select
              .value=${props.draft.defaultAgentId}
              @change=${(e: Event) =>
                props.onDraftChange({ defaultAgentId: (e.target as HTMLSelectElement).value })}
            >
              <option value="">First member</option>
              ${members.map(
                (member) => html`
                  <option value=${member.agentId}>${memberDisplayName(member.agentId, members)}</option>
                `,
              )}
            </select>
          </label>
        </div>
        ${renderJsonField("Members JSON", props.draft.membersJson, (membersJson) =>
          props.onDraftChange({ membersJson }),
        )}
        ${renderJsonField("Aliases JSON", props.draft.aliasesJson, (aliasesJson) =>
          props.onDraftChange({ aliasesJson }),
        )}
        ${renderJsonField("Team bindings JSON", props.draft.bindingsJson, (bindingsJson) =>
          props.onDraftChange({ bindingsJson }),
        )}
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
    </section>

    <section class="grid grid-cols-2" style="margin-top: 16px;">
      ${renderBindingCard(props, members)}
      ${renderModelCard(props, members)}
    </section>
  `;
}

function renderBindingCard(props: AgentTeamsPanelProps, members: AgentTeamMember[]) {
  return html`
    <section class="card">
      <div class="card-title">Member Binding</div>
      <div class="card-sub">Apply or remove a channel/account route through Gateway binding RPC.</div>
      <div class="grid grid-cols-2" style="margin-top: 14px;">
        <label class="field">
          <span>Member</span>
          <select
            .value=${props.binding.agentId}
            @change=${(e: Event) =>
              props.onBindingChange({ agentId: (e.target as HTMLSelectElement).value })}
          >
            <option value="">Choose member</option>
            ${members.map(
              (member) => html`
                <option value=${member.agentId}>${memberDisplayName(member.agentId, members)}</option>
              `,
            )}
          </select>
        </label>
        <label class="field">
          <span>Action</span>
          <select
            .value=${props.binding.mode}
            @change=${(e: Event) =>
              props.onBindingChange({
                mode: (e.target as HTMLSelectElement).value === "unbind" ? "unbind" : "bind",
              })}
          >
            <option value="bind">Apply</option>
            <option value="unbind">Remove</option>
          </select>
        </label>
      </div>
      <label class="field" style="margin-top: 12px;">
        <span>Channel binding</span>
        <input
          .value=${props.binding.spec}
          placeholder="telegram:bot-a"
          @input=${(e: Event) =>
            props.onBindingChange({ spec: (e.target as HTMLInputElement).value })}
        />
      </label>
      <div class="agent-model-actions">
        <button
          type="button"
          class="btn btn--sm primary"
          ?disabled=${props.saving || !props.binding.agentId || !props.binding.spec.trim()}
          @click=${props.onApplyBinding}
        >
          ${props.binding.mode === "unbind" ? "Remove Binding" : "Apply Binding"}
        </button>
      </div>
      ${props.bindingResult
        ? html`
            <div class="callout info" style="margin-top: 12px;">
              ${bindingSummary(props.bindingResult)}
            </div>
          `
        : nothing}
    </section>
  `;
}

function renderModelCard(props: AgentTeamsPanelProps, members: AgentTeamMember[]) {
  const model = props.modelResult?.models ?? null;
  return html`
    <section class="card">
      <div class="card-title">Member Model</div>
      <div class="card-sub">Read and write per-agent models.json through Gateway.</div>
      ${props.modelError
        ? html`<div class="callout danger" style="margin-top: 12px;">${props.modelError}</div>`
        : nothing}
      <div class="grid grid-cols-2" style="margin-top: 14px;">
        <label class="field">
          <span>Member</span>
          <select
            .value=${props.modelDraft.agentId}
            @change=${(e: Event) =>
              props.onModelDraftChange({ agentId: (e.target as HTMLSelectElement).value })}
          >
            <option value="">Choose member</option>
            ${members.map(
              (member) => html`
                <option value=${member.agentId}>${memberDisplayName(member.agentId, members)}</option>
              `,
            )}
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
            @input=${(e: Event) =>
              props.onModelDraftChange({
                primaryModelRef: (e.target as HTMLInputElement).value,
              })}
          />
        </label>
        <label class="field">
          <span>Runtime primary model ref</span>
          <input
            .value=${props.modelDraft.runtimePrimaryModelRef}
            placeholder="openai:gpt-5-mini"
            @input=${(e: Event) =>
              props.onModelDraftChange({
                runtimePrimaryModelRef: (e.target as HTMLInputElement).value,
              })}
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

function renderJsonField(label: string, value: string, onChange: (value: string) => void) {
  return html`
    <label class="field agent-file-field" style="margin-top: 12px;">
      <span>${label}</span>
      <textarea
        class="agent-file-textarea"
        rows="6"
        .value=${value}
        @input=${(e: Event) => onChange((e.target as HTMLTextAreaElement).value)}
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
