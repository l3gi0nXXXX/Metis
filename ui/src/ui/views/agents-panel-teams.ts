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
  AGENT_TEAM_TEMPLATE_GROUPS,
  applyAgentTeamTemplate,
  buildAgentTeamAcceptancePlan,
  buildAgentTeamBindingConflictPreview,
  buildAgentTeamCultivationSnapshot,
  buildAgentTeamBindingPreview,
  buildAgentTeamReadinessBoard,
  changeAgentTeamAlias,
  changeAgentTeamMember,
  exportAgentTeamTemplate,
  importAgentTeamTemplate,
  removeAgentTeamAlias,
  removeAgentTeamMember,
  setAgentTeamBroadcastEnabled,
  setAgentTeamBroadcastMember,
  setAgentTeamBroadcastMembers,
  type AgentTeamAcceptanceItem,
  type AgentTeamAliasDraft,
  type AgentTeamBindingDraft,
  type AgentTeamBindingPreview,
  type AgentTeamEditorDraft,
  type AgentTeamFeishuAuthAction,
  type AgentTeamFeishuAuthResult,
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
  feishuAuthLoading: boolean;
  feishuAuthError: string | null;
  feishuAuthResult: AgentTeamFeishuAuthResult | null;
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
  onStartFeishuOAuth: (accountId: string, action?: AgentTeamFeishuAuthAction) => void;
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
    ${renderAgentTeamManagementSummary(props, teams, activeMembers, activeAliases, activeBroadcast)}
    ${renderWorkflowStrip(props, activeMembers, activeBroadcast)}
    ${renderRouteReadinessPanels(props)}
    ${renderTeamWizardCard(props, activeMembers)}
    ${renderFeishuSetupRepairWizard(props)}
    ${renderAcceptanceReadinessPanels(props, teams, activeMembers)}

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

    <section class="grid grid-cols-2" style="margin-top: 16px;">
      ${renderMetisCapabilitiesPanel()}
      ${renderFeishuAuthDoctorPanel(props)}
    </section>

    <section style="margin-top: 16px;">
      ${renderCultivationPanel(props)}
    </section>

    <section style="margin-top: 16px;">
      ${renderDoctorPanel(props, teams, activeMembers)}
    </section>
  `;
}

function renderAcceptanceReadinessPanels(
  props: AgentTeamsPanelProps,
  teams: AgentTeam[],
  members: AgentTeamMember[],
) {
  const plan = buildAgentTeamAcceptancePlan({
    teamCount: teams.length,
    memberCount: members.length,
    bindingCount: safeJsonArrayLength(props.draft.bindingsJson),
    hasModelState: Boolean(props.modelResult?.models),
    hasWorkspaceProfile: Boolean(props.workspace.workspace || props.workspace.files.length > 0),
    channelsSnapshot: props.channelsSnapshot,
  });
  return html`
    <section class="grid grid-cols-2" style="margin-bottom: 16px;">
      <section class="card">
        <div class="row" style="justify-content: space-between; align-items: flex-start;">
          <div>
            <div class="card-title">Manual acceptance / evidence pack</div>
            <div class="card-sub">
              Local UI evidence can pass without real IM resources; live Telegram and Feishu rows stay explicit until operator evidence is attached.
            </div>
          </div>
          <span class="badge">${plan.summary.localPass} local-pass</span>
        </div>
        <div class="agents-overview-grid" style="margin-top: 14px;">
          <div class="agent-kv">
            <div class="label">Local rows</div>
            <div>${plan.summary.localPass} local-pass</div>
          </div>
          <div class="agent-kv">
            <div class="label">External rows</div>
            <div>${plan.summary.externalResourceRequired} external-resource-required</div>
          </div>
          <div class="agent-kv">
            <div class="label">Operator rows</div>
            <div>${plan.summary.operatorRecordRequired} operator-record-required</div>
          </div>
          <div class="agent-kv">
            <div class="label">Write boundary</div>
            <div>Gateway RPC only</div>
          </div>
        </div>
        <div class="agent-kv" style="margin-top: 12px;">
          <div class="label">Evidence command</div>
          <pre class="mono" style="white-space: pre-wrap; margin: 0;">${plan.evidenceCommand}</pre>
        </div>
        <div class="list" style="margin-top: 12px;">
          ${plan.evidenceItems.map((item) => renderAcceptanceItem(item))}
        </div>
      </section>
      <section class="card">
        <div class="row" style="justify-content: space-between; align-items: flex-start;">
          <div>
            <div class="card-title">External resource readiness</div>
            <div class="card-sub">
              Telegram and Feishu live acceptance needs real test resources; this panel separates setup signals from live proof.
            </div>
          </div>
          <span class="badge">${plan.summary.externalResourceRequired} external-resource-required</span>
        </div>
        <div class="callout info" style="margin-top: 12px;">
          Control UI provides guided setup and linking an existing Feishu bot; it does not create a Feishu app or bot. Secrets and real token files stay behind Gateway RPC or operator-managed backend configuration.
        </div>
        <div class="list" style="margin-top: 12px;">
          ${plan.externalItems.map((item) => renderAcceptanceItem(item))}
        </div>
      </section>
    </section>
  `;
}

function renderAcceptanceItem(item: AgentTeamAcceptanceItem) {
  return html`
    <div class="list-item">
      <div class="list-main">
        <div class="list-title">${item.title}</div>
        <div class="list-sub">${item.detail}</div>
        <div class="list-sub" style="margin-top: 6px;">Acceptance: ${item.acceptance}</div>
      </div>
      <div class="list-meta"><span class="badge">${item.status}</span></div>
    </div>
  `;
}

function renderAgentTeamManagementSummary(
  props: AgentTeamsPanelProps,
  teams: AgentTeam[],
  members: AgentTeamMember[],
  aliases: AgentTeamAliasDraft[],
  broadcast: Record<string, unknown>,
) {
  const selectedName = props.detail ? teamDisplayName(props.detail) : "Start with a template";
  const bindingCount = safeJsonArrayLength(props.draft.bindingsJson);
  const nextAction = resolveAgentTeamNextAction(props, teams, members, bindingCount);
  return html`
    <section class="card" style="margin-bottom: 16px;">
      <div class="row" style="justify-content: space-between; align-items: flex-start;">
        <div>
          <div class="card-title">Agent Team Management</div>
          <div class="card-sub">
            Create teams, review member state, repair channel setup, and then bind Feishu or Telegram routes from one place.
          </div>
        </div>
        <span class="badge">${props.saving ? "saving" : props.loading ? "loading" : "ready"}</span>
      </div>
      <div class="agents-overview-grid" style="margin-top: 14px;">
        <div class="agent-kv">
          <div class="label">Teams</div>
          <div>${formatCount(teams.length, "team")}</div>
        </div>
        <div class="agent-kv">
          <div class="label">Selected path</div>
          <div>${selectedName}</div>
        </div>
        <div class="agent-kv">
          <div class="label">Members and aliases</div>
          <div>${formatCount(members.length, "member")} · ${formatCount(aliases.length, "alias")}</div>
        </div>
        <div class="agent-kv">
          <div class="label">Bindings and broadcast</div>
          <div>${formatCount(bindingCount, "binding")} · ${broadcastEnabled(broadcast) ? "broadcast on" : "broadcast off"}</div>
        </div>
        <div class="agent-kv">
          <div class="label">Telegram</div>
          <div>${channelReadinessLabel(props, "telegram")}</div>
        </div>
        <div class="agent-kv">
          <div class="label">Feishu</div>
          <div>${channelReadinessLabel(props, "feishu")}</div>
        </div>
        <div class="agent-kv">
          <div class="label">Next action</div>
          <div>${nextAction}</div>
        </div>
      </div>
      ${props.error
        ? html`
            <div class="callout danger" style="margin-top: 12px;">
              <div class="list-title">Repair first</div>
              <div class="list-sub">
                ${redactSecretText(props.error)}. Refresh Gateway status or check the current Control UI token and agent-team RPC permission before editing.
              </div>
            </div>
          `
        : nothing}
      <div class="callout info" style="margin-top: 12px;">
        Control UI cannot automatically create a Feishu app or bot; it supports guided setup and linking an existing bot through Gateway status, OAuth, and repair steps. Create or install the bot in Feishu developer console first, then associate it here.
      </div>
    </section>
  `;
}

type FeishuWizardStep = {
  title: string;
  status: "ready" | "needed" | "repair" | "manual";
  message: string;
  details: string[];
  copyLabel: string;
  copyText: string;
};

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

function renderRouteReadinessPanels(props: AgentTeamsPanelProps) {
  const board = buildAgentTeamReadinessBoard({
    draft: props.draft,
    channelsSnapshot: props.channelsSnapshot,
  });
  const conflict = buildAgentTeamBindingConflictPreview(props.draft, props.binding);
  return html`
    <section class="grid grid-cols-2" style="margin-bottom: 16px;">
      <section class="card">
        <div class="row" style="justify-content: space-between; align-items: flex-start;">
          <div>
            <div class="card-title">Channel readiness board</div>
            <div class="card-sub">Telegram and Feishu setup state, route coverage, and live evidence path.</div>
          </div>
          <span class="badge">${board.summary}</span>
        </div>
        <div class="agent-kv" style="margin-top: 12px;">
          <div class="label">Evidence pack</div>
          <div>${board.evidencePackHint}</div>
        </div>
        <div class="list" style="margin-top: 12px;">
          ${board.channels.map(
            (channel) => html`
              <div class="list-item">
                <div class="list-main">
                  <div class="list-title">${channel.label}</div>
                  <div class="list-sub">
                    ${channel.runtimeStatus} · ${channel.accountStatus} · ${channel.routeStatus} · auth ${channel.authStatus}
                  </div>
                  <div class="list-sub" style="margin-top: 6px;">${channel.nextSteps.join(" ")}</div>
                </div>
                <div class="list-meta"><span class="badge">${channel.status}</span></div>
              </div>
            `,
          )}
        </div>
      </section>
      <section class="card">
        <div class="row" style="justify-content: space-between; align-items: flex-start;">
          <div>
            <div class="card-title">Binding conflict preview</div>
            <div class="card-sub">Compares the current Binding Builder route with saved team binding metadata before Apply.</div>
          </div>
          <span class="badge">${conflict.summary}</span>
        </div>
        <div class="list" style="margin-top: 12px;">
          ${conflict.items.map(
            (item) => html`
              <div class="list-item">
                <div class="list-main">
                  <div class="list-title">${item.title}</div>
                  <div class="list-sub">${item.detail}</div>
                  <div class="list-sub" style="margin-top: 6px;">${item.repair}</div>
                </div>
                <div class="list-meta"><span class="badge">${item.status}</span></div>
              </div>
            `,
          )}
        </div>
      </section>
    </section>
  `;
}

function renderFeishuSetupRepairWizard(props: AgentTeamsPanelProps) {
  const steps = buildFeishuSetupWizardSteps(props);
  const readyCount = steps.filter((step) => step.status === "ready").length;
  const defaultAccount =
    resolveFeishuSettings(props).defaultAccount ||
    props.channelsSnapshot?.channelDefaultAccountId?.feishu ||
    "default";
  return html`
    <section class="card" style="margin-bottom: 16px;">
      <div class="row" style="justify-content: space-between; align-items: flex-start;">
        <div>
          <div class="card-title">Feishu setup/repair wizard</div>
          <div class="card-sub">
            Read-only setup checklist for app credentials, event subscription, scopes, routing, OAuth, OAPI, and cards.
          </div>
        </div>
        <span class="badge">${readyCount}/${steps.length} ready</span>
      </div>
      <div class="callout info" style="margin-top: 12px;">
        Browser repair is limited to Gateway RPC actions and copyable repair steps. Token files, app credential files, and local Feishu config stay behind Gateway RPC or operator-managed backend configuration.
      </div>
      ${renderFeishuExistingAppBotFlow(props, defaultAccount)}
      <div class="agents-overview-grid" style="margin-top: 14px;">
        <div class="agent-kv">
          <div class="label">Account</div>
          <div class="mono">${defaultAccount}</div>
        </div>
        <div class="agent-kv">
          <div class="label">Checklist</div>
          <div>${readyCount} ready · ${steps.length - readyCount} need repair</div>
        </div>
        <div class="agent-kv">
          <div class="label">Profile files</div>
          <div>${AGENT_TEAM_PROFILE_FILES.length} supported</div>
        </div>
        <div class="agent-kv">
          <div class="label">Write boundary</div>
          <div>Gateway RPC only</div>
        </div>
      </div>
      <div class="list" style="margin-top: 14px;">
        ${steps.map(
          (step) => html`
            <div class="list-item">
              <div class="list-main">
                <div class="list-title">${step.title}</div>
                <div class="list-sub">${step.message}</div>
                <div class="list-sub" style="margin-top: 6px;">${step.details.join(" · ")}</div>
              </div>
              <div class="list-meta">
                <span class="badge">${step.status}</span>
                <button
                  type="button"
                  class="btn btn--sm"
                  title="Copy repair steps"
                  @click=${() => copyFeishuWizardSteps(step.copyText)}
                >
                  ${step.copyLabel}
                </button>
              </div>
            </div>
          `,
        )}
      </div>
    </section>
  `;
}

function renderFeishuExistingAppBotFlow(props: AgentTeamsPanelProps, defaultAccount: string) {
  return html`
    <div class="callout info" style="margin-top: 12px;">
      <div class="list-title">Link existing Feishu app/bot</div>
      <div class="list-sub">
        Associate existing app/bot by confirming developer-console credentials, event URL, scopes, bot installation, and a test message through Gateway status. Control UI cannot automatically create a Feishu app or bot; it only provides guided setup and linking an existing bot. Control UI never stores app secrets or token files.
      </div>
      <div class="row" style="gap: 8px; margin-top: 10px;">
        <button
          type="button"
          class="btn btn--sm"
          ?disabled=${props.feishuAuthLoading}
          @click=${() => props.onStartFeishuOAuth(defaultAccount, "status")}
        >
          Associate existing app/bot
        </button>
        <button type="button" class="btn btn--sm btn--ghost" ?disabled=${props.loading} @click=${props.onRefresh}>
          Refresh status
        </button>
      </div>
    </div>
  `;
}

function buildFeishuSetupWizardSteps(props: AgentTeamsPanelProps): FeishuWizardStep[] {
  const status = objectValue(props.channelsSnapshot?.channels?.feishu);
  const capabilities = stringArrayFromUnknown(status?.capabilities).map((item) => item.toLowerCase());
  const auth = objectValue(status?.auth) ?? objectValue(status?.oauth);
  const doctor = objectValue(status?.doctor) ?? objectValue(status?.diagnostics);
  const feishu = resolveFeishuSettings(props);
  const config = resolveFeishuConfigObject(props);
  const accountConfigs = resolveFeishuAccountConfigs(config);
  const configuredAccount = feishu.accounts.some((account) => account.configured === true);
  const appCredentialReady =
    status?.configured === true ||
    configuredAccount ||
    hasFeishuCredentialFields(config) ||
    accountConfigs.some((account) => hasFeishuCredentialFields(account));
  const eventReady =
    status?.running === true ||
    capabilities.some((item) => item.includes("event") || item.includes("webhook") || item.includes("long")) ||
    hasFeishuEventFields(config) ||
    accountConfigs.some((account) => hasFeishuEventFields(account));
  const appScopeGaps = missingScopes(auth, ["missingAppScopes", "missing_app_scopes", "appScopeMissing"]);
  const userScopeGaps = missingScopes(auth, ["missingUserScopes", "missing_user_scopes", "userScopeMissing"]);
  const authOk = isFeishuAuthAuthorized(auth);
  const scopeSummary = auth ? statusText(auth, ["scopeSummary", "scopes", "userScopes", "grantedUserScopes"], "") : "";
  const scopeReady = Boolean(auth && appScopeGaps.length === 0 && userScopeGaps.length === 0 && (scopeSummary || authOk));
  const groupReady = feishu.groupCount > 0;
  const threadReady = feishu.threadSession !== "not configured";
  const oapiReady =
    capabilities.some((item) => item.includes("oapi") || item.includes("openapi")) &&
    appScopeGaps.length === 0;
  const cardReady =
    capabilities.some(
      (item) =>
        item.includes("card") ||
        item.includes("interactive") ||
        item.includes("blockstreaming") ||
        item.includes("streaming-card"),
    ) && !doctorHasFinding(doctor, "card_unavailable");

  return [
    {
      title: "App credentials",
      status: appCredentialReady ? "ready" : "needed",
      message: appCredentialReady
        ? "Feishu app credential presence is visible through redacted Gateway status."
        : "Missing Feishu app credential signal. Configure app id, app secret, and domain behind Gateway.",
      details: [
        "Open Feishu developer console",
        "confirm app id/app secret/domain",
        "refresh channels.status",
      ],
      copyLabel: "Copy credential steps",
      copyText: feishuCopyBlock("Feishu app credential repair", [
        "Open Feishu developer console for the test app.",
        "Confirm app id, app secret, and tenant domain in operator-managed Gateway configuration.",
        "Restart or refresh Gateway and verify `channels.status` reports the Feishu account as configured.",
        "Do not paste app secret values into the browser, team metadata, profile files, or comments.",
      ]),
    },
    {
      title: "Event subscription",
      status: eventReady ? "ready" : "needed",
      message: eventReady
        ? "Gateway status/config shows Feishu event delivery or runtime activity."
        : "Missing event subscription signal. Configure webhook or long-connection receive mode in Feishu and Gateway.",
      details: [
        "subscribe message events",
        "include card/reaction/drive/bot events as needed",
        "verify Gateway inbound logs",
      ],
      copyLabel: "Copy event steps",
      copyText: feishuCopyBlock("Feishu event subscription repair", [
        "Open Feishu developer console > Events and callbacks.",
        "Configure the request URL or long-connection receive mode used by Gateway.",
        "Subscribe to message receive, reaction, card action, drive comment, and bot membership events required by the team.",
        "Refresh Control UI and verify `channels.status` plus Gateway logs show Feishu event readiness.",
      ]),
    },
    {
      title: "Scope repair",
      status: scopeReady ? "ready" : auth ? "repair" : "needed",
      message: scopeReady
        ? `Scopes visible: ${scopeSummary || "authorized"}`
        : `Missing app scopes: ${formatScopeList(appScopeGaps, "none reported")}; missing user scopes: ${formatScopeList(userScopeGaps, "offline_access or OAPI scopes")}.`,
      details: [
        "grant app scopes in Feishu console",
        "grant user scopes through OAuth",
        "rerun Gateway OAuth",
      ],
      copyLabel: "Copy scope repair steps",
      copyText: feishuCopyBlock(
        "Feishu scope repair",
        [
          `Grant missing app scopes in Feishu developer console: ${formatScopeList(appScopeGaps, "check OAPI capability requirements")}.`,
          `Grant missing user scopes through OAuth: ${formatScopeList(userScopeGaps, "offline_access and action-specific user scopes")}.`,
          "Run `channels.feishu.auth.start` from Gateway RPC or click Start OAuth via Gateway in Control UI.",
          "Poll or complete the OAuth flow through Gateway RPC, then refresh `channels.status`.",
        ],
        auth ? `Current redacted auth diagnostic:\n${redactedJsonText(auth)}` : "Current auth diagnostic: not visible in channels.status.",
      ),
    },
    {
      title: "Group/thread routing",
      status: groupReady && threadReady ? "ready" : "manual",
      message:
        groupReady && threadReady
          ? "Group policy and thread session settings are visible."
          : "Group allowlist or thread session policy is not fully visible. Repair belongs in non-secret Gateway configuration.",
      details: [
        `${groupReady ? "group policy visible" : "group policy missing"}`,
        `${threadReady ? "thread policy visible" : "thread policy missing"}`,
        "use Binding Builder for peer/thread routes",
      ],
      copyLabel: "Copy routing steps",
      copyText: feishuCopyBlock("Feishu group/thread routing repair", [
        "Confirm the Feishu account id matches the account used by the incoming group.",
        "Configure allowed groups and thread session policy in Gateway backend configuration.",
        "Use the Teams Binding Builder to preview a structured route with channel, account, peer, thread, team, and roles.",
        "Apply the route through `agents.bind` or `agents.teams.update`; do not edit route files from the browser.",
      ]),
    },
    {
      title: "OAuth device flow",
      status: authOk || props.feishuAuthResult ? "ready" : "repair",
      message:
        authOk || props.feishuAuthResult
          ? "OAuth status or lifecycle result is visible through Gateway RPC."
          : "Start OAuth through Gateway RPC after app credentials and scopes are configured.",
      details: ["Start OAuth via Gateway", "Status", "Poll", "Complete", "Revoke local auth"],
      copyLabel: "Copy OAuth steps",
      copyText: feishuCopyBlock("Feishu OAuth device-flow repair", [
        "Click Start OAuth via Gateway or call `channels.feishu.auth.start` with the account id.",
        "Open the verification URL and enter the user code returned by Gateway.",
        "Use Status, Poll, or Complete through Gateway RPC until tokenStatus is authorized.",
        "Use Revoke local auth only when intentionally clearing local Gateway auth state.",
      ]),
    },
    {
      title: "OAPI readiness",
      status: oapiReady ? "ready" : "manual",
      message: oapiReady
        ? "OAPI capability is advertised and no app scope gap is visible."
        : "OAPI capability or app-scope readiness is incomplete; tools should return structured auth_required or scope_missing diagnostics.",
      details: ["docs/wiki/drive/search/calendar/task/sheets/bitable", "Gateway tool calls only", "redacted diagnostics"],
      copyLabel: "Copy OAPI steps",
      copyText: feishuCopyBlock("Feishu OAPI readiness repair", [
        "Grant the action-specific app and user scopes required by the Feishu OAPI tool.",
        "Complete OAuth through Gateway so user access token scopes are refreshed.",
        "Run the OAPI tool through Gateway or the agent runtime and inspect structured `auth_required`, `scope_missing`, or `app_scope_missing` diagnostics.",
        "Do not call Feishu OAPI directly from Control UI browser code.",
      ]),
    },
    {
      title: "Card readiness",
      status: cardReady ? "ready" : "manual",
      message: cardReady
        ? "Interactive or streaming card capability is visible in Gateway status."
        : "Card readiness is not fully visible. Verify card events and live smoke through opt-in Gateway diagnostics.",
      details: ["interactive card events", "streaming card fallback", "live smoke opt-in"],
      copyLabel: "Copy card steps",
      copyText: feishuCopyBlock("Feishu card readiness repair", [
        "Enable interactive card callbacks or card action events in the Feishu developer console.",
        "Verify Gateway receives card action events and can map them to route/session context.",
        "Run card live smoke only with explicit opt-in test credentials.",
        "If card patch fails or a message is unavailable, expect Gateway fallback text or a clear diagnostic.",
      ]),
    },
  ];
}

function copyFeishuWizardSteps(text: string) {
  const safeText = redactSecretText(text);
  if (typeof navigator === "undefined" || !navigator.clipboard?.writeText) {
    return;
  }
  void navigator.clipboard.writeText(safeText);
}

function feishuCopyBlock(title: string, steps: string[], context = ""): string {
  const body = steps.map((step, index) => `${index + 1}. ${step}`).join("\n");
  return [
    title,
    "",
    body,
    "",
    "Safety: Control UI does not write token files, app credential files, or local Feishu config. Use Gateway RPC or operator-managed backend configuration for real changes.",
    context ? `\n${context}` : "",
  ]
    .filter(Boolean)
    .join("\n");
}

function resolveFeishuConfigObject(props: AgentTeamsPanelProps): Record<string, unknown> | null {
  const gateway = objectValue(props.configForm?.gateway);
  return objectValue(gateway?.feishu ?? props.configForm?.feishu);
}

function resolveFeishuAccountConfigs(config: Record<string, unknown> | null): Record<string, unknown>[] {
  const accounts = objectValue(config?.accounts);
  if (!accounts) {
    return [];
  }
  return Object.values(accounts)
    .map((value) => objectValue(value))
    .filter((value): value is Record<string, unknown> => Boolean(value));
}

function hasFeishuCredentialFields(config: Record<string, unknown> | null): boolean {
  if (!config) {
    return false;
  }
  return hasAnyStringField(config, ["appId", "app_id", "clientId", "client_id", "domain"]) &&
    hasAnyStringField(config, ["appSecret", "app_secret", "clientSecret", "client_secret"]);
}

function hasFeishuEventFields(config: Record<string, unknown> | null): boolean {
  if (!config) {
    return false;
  }
  return (
    hasAnyStringField(config, ["webhook", "webhookUrl", "eventUrl", "requestUrl", "connectionMode", "receiveMode"]) ||
    Array.isArray(config.events) ||
    Array.isArray(config.eventSubscriptions)
  );
}

function hasAnyStringField(config: Record<string, unknown>, keys: string[]): boolean {
  return keys.some((key) => Boolean(stringOrEmpty(config[key]).trim()));
}

function formatScopeList(scopes: string[], fallback: string): string {
  return scopes.length > 0 ? scopes.join(", ") : fallback;
}

function renderTeamWizardCard(props: AgentTeamsPanelProps, members: AgentTeamMember[]) {
  const feishu = resolveFeishuSettings(props);
  const teamId = props.draft.id.trim() || props.selectedId || "";
  const canExport = Boolean(props.draft.id.trim() || members.length > 0);
  return html`
    <section class="card" style="margin-bottom: 16px;">
      <div class="row" style="justify-content: space-between; align-items: flex-start;">
        <div>
          <div class="card-title">Team Wizard</div>
          <div class="card-sub">Template, members, default member, model, profile, binding, and Feishu readiness in one guided path.</div>
        </div>
        <span class="badge">Metis template schema</span>
      </div>
      <div style="margin-top: 14px;">
        <div class="list-title">Template library</div>
        <div class="card-sub">Grouped templates for content, engineering, support, data, and operations teams.</div>
        <div class="list" style="margin-top: 10px;">
          ${AGENT_TEAM_TEMPLATE_GROUPS.map(
            (group) => html`
              <div class="list-item">
                <div class="list-main">
                  <div class="row" style="justify-content: space-between; align-items: center; gap: 8px;">
                    <div class="list-title">${group.label}</div>
                    <span class="badge">${formatCount(group.templates.length, "template")}</span>
                  </div>
                  <div class="grid grid-cols-3" style="margin-top: 10px;">
                    ${group.templates.map(
                      (template) => html`
                        <div class="agent-kv">
                          <div class="row" style="justify-content: space-between; align-items: center; gap: 8px;">
                            <div class="label">${template.transport}</div>
                            <span class="badge">${props.draft.template === template.id ? "selected" : "template"}</span>
                          </div>
                          <div class="list-title" style="margin-top: 6px;">${template.label}</div>
                          <div class="list-sub">${template.description}</div>
                          <button
                            type="button"
                            class="btn btn--sm"
                            style="margin-top: 10px;"
                            @click=${() => props.onDraftChange(applyAgentTeamTemplate(props.draft, template.id))}
                          >
                            Use template
                          </button>
                        </div>
                      `,
                    )}
                  </div>
                </div>
              </div>
            `,
          )}
        </div>
      </div>
      <div class="agents-overview-grid" style="margin-top: 14px;">
        <div class="agent-kv">
          <div class="label">Members</div>
          <div>${formatCount(members.length, "member")}</div>
        </div>
        <div class="agent-kv">
          <div class="label">Default member</div>
          <div>${memberDisplayName(props.draft.defaultAgentId, members)}</div>
        </div>
        <div class="agent-kv">
          <div class="label">Model</div>
          <div>${props.modelResult?.models?.path ? "loaded" : "choose member below"}</div>
        </div>
        <div class="agent-kv">
          <div class="label">Profile</div>
          <div>${props.workspace.workspace ? "workspace loaded" : "choose profile below"}</div>
        </div>
      </div>
      <div class="callout info" style="margin-top: 12px;">
        <div class="list-title">IM team commands</div>
        <div class="list-sub">
          /agents team · /agents status · /agents switch @writer. Alias routing such as @writer or /agent writer remains handled by persisted team aliases and channel bindings.
        </div>
      </div>
      <div class="row" style="justify-content: space-between; align-items: flex-end; margin-top: 14px;">
        <div>
          <div class="list-title">Channel route presets</div>
          <div class="muted">Seed the Binding Builder with non-secret Telegram or Feishu route fields, then preview/apply through Gateway RPC.</div>
        </div>
        <div class="row" style="gap: 8px;">
          <button
            type="button"
            class="btn btn--sm"
            @click=${() =>
              props.onBindingChange({
                channel: "telegram",
                accountId: "default",
                peerKind: "group",
                useStructuredBinding: true,
                team: teamId,
              })}
          >
            Seed Telegram route
          </button>
          <button
            type="button"
            class="btn btn--sm"
            @click=${() =>
              props.onBindingChange({
                channel: "feishu",
                accountId: feishu.defaultAccount || "default",
                peerKind: "group",
                useStructuredBinding: true,
                team: teamId,
              })}
          >
            Seed Feishu route
          </button>
        </div>
      </div>
      <div class="row" style="justify-content: space-between; align-items: flex-end; margin-top: 14px;">
        <div>
          <div class="list-title">Template import/export</div>
          <div class="muted">Uses metis.agentTeamTemplate.v1. Tokens, secrets, and auth files are not included.</div>
        </div>
        <div class="row" style="gap: 8px;">
          <button
            type="button"
            class="btn btn--sm"
            ?disabled=${!canExport}
            @click=${() => downloadAgentTeamTemplate(props.draft)}
          >
            Export template JSON
          </button>
          <label class="btn btn--sm btn--ghost">
            Import template JSON
            <input
              type="file"
              accept="application/json,.json"
              style="display: none;"
              @change=${(event: Event) => importTemplateFile(event, props)}
            />
          </label>
        </div>
      </div>
      <div class="callout info" style="margin-top: 12px;">
        Feishu readiness is checked below from Gateway status. Browser-side repair never writes local token, secret, or auth files.
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
      ${props.error
        ? html`
            <div class="callout danger" style="margin-top: 12px;">
              <div class="list-title">Repair first</div>
              <div class="list-sub">${redactSecretText(props.error)}</div>
            </div>
          `
        : nothing}
      ${props.success ? html`<div class="callout success" style="margin-top: 12px;">${props.success}</div>` : nothing}
      ${teams.length === 0
        ? html`
            <div class="callout info" style="margin-top: 12px;">
              No teams are configured yet. Create from a template or import a Metis team template, then add members, bindings, profiles, models, and channel setup.
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
      ${renderTeamHealthSummary(props, activeMembers, activeAliases, activeBroadcast)}
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
            ${AGENT_TEAM_TEMPLATE_GROUPS.flatMap((group) =>
              group.templates.map(
                (template) => html`<option value=${template.id}>${group.label} · ${template.label}</option>`,
              ),
            )}
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
      ${renderMemberDetails(activeMembers, activeAliases, activeBroadcast, props.draft.defaultAgentId)}
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

function renderTeamHealthSummary(
  props: AgentTeamsPanelProps,
  members: AgentTeamMember[],
  aliases: AgentTeamAliasDraft[],
  broadcast: Record<string, unknown>,
) {
  const health = buildTeamHealthSummary(props, members, aliases, broadcast);
  return html`
    <div style="margin-top: 14px;">
      <div class="list-title">Team health summary</div>
      <div class="agents-overview-grid" style="margin-top: 8px;">
        ${health.map(
          (item) => html`
            <div class="agent-kv">
              <div class="label">${item.label}</div>
              <div>${item.value}</div>
            </div>
          `,
        )}
      </div>
    </div>
  `;
}

function renderMemberDetails(
  members: AgentTeamMember[],
  aliases: AgentTeamAliasDraft[],
  broadcast: Record<string, unknown>,
  defaultAgentId: string,
) {
  const selectedMembers = stringArrayFromUnknown(broadcast.members);
  return html`
    <div style="margin-top: 16px;">
      <div class="list-title">Member details</div>
      <div class="list" style="margin-top: 8px;">
        ${members.length === 0
          ? html`<div class="callout info">No member details are available yet.</div>`
          : members.map((member) => {
              const memberAliases = aliases
                .filter((alias) => alias.agentId === member.agentId)
                .map((alias) => alias.alias);
              const tags = [
                member.agentId === defaultAgentId ? "default" : "",
                selectedMembers.includes(member.agentId) ? "broadcast" : "",
                memberAliases.length ? memberAliases.join(", ") : "no aliases",
              ].filter(Boolean);
              return html`
                <div class="list-item">
                  <div class="list-main">
                    <div class="list-title">${memberDisplayName(member.agentId, members)}</div>
                    <div class="list-sub">
                      ${member.role || "role missing"} · ${member.name || "name missing"} · ${tags.join(" · ")}
                    </div>
                  </div>
                </div>
              `;
            })}
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
      ${renderModelProviderChips(model)}
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

function renderModelProviderChips(model: AgentModelsResult["models"] | null) {
  if (!model) {
    return nothing;
  }
  const chips = modelProviderChips(model);
  return html`
    <div style="margin-top: 14px;">
      <div class="list-title">Model provider chips</div>
      <div class="card-sub">Derived from agents.models.get/set and redacted before display.</div>
      <div class="list" style="margin-top: 8px;">
        ${chips.length === 0
          ? html`<div class="callout info">No provider entries are visible in this models.json response.</div>`
          : chips.map(
              (chip) => html`
                <div class="list-item">
                  <div class="list-main">
                    <div class="list-title">${chip.label}</div>
                    <div class="list-sub mono">
                      ${chip.modelRef || "no default model"}${chip.runtimeProvider
                        ? ` · runtime ${chip.runtimeProvider}`
                        : ""}
                    </div>
                  </div>
                  <div class="list-meta">
                    <span class="badge">${chip.status}</span>
                  </div>
                </div>
              `,
            )}
      </div>
      ${model.credentialSource
        ? html`
            <div class="agent-kv" style="margin-top: 12px;">
              <div class="label">Credential source</div>
              <pre class="mono" style="white-space: pre-wrap; margin: 0;">${redactedJsonText(model.credentialSource)}</pre>
            </div>
          `
        : nothing}
    </div>
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

const METIS_CAPABILITY_GROUPS = [
  {
    title: "AgentTeam Gateway RPC",
    badge: "Gateway",
    items: [
      "agents.teams.* team CRUD",
      "agents.bind route bindings",
      "agents.migration.dryRun read-only doctor preview",
    ],
  },
  {
    title: "Workspace profile files",
    badge: "profiles",
    items: [...AGENT_TEAM_PROFILE_FILES],
  },
  {
    title: "Model and provider state",
    badge: "models",
    items: ["agents.models.get", "agents.models.set", "per-agent models.json", "redacted credential source"],
  },
  {
    title: "Channel capabilities",
    badge: "channels",
    items: [
      "Telegram route/account/topic baseline",
      "Feishu route/account/group/thread status",
      "Feishu native commands: /feishu auth, /feishu doctor, /feishu info",
    ],
  },
  {
    title: "Built-in tools",
    badge: "tools",
    items: ["feishu_media_list", "feishu_im_user_fetch_resource", "gateway control tools", "memory tools"],
  },
  {
    title: "Built-in skills",
    badge: "skills",
    items: ["workspace skills", "bundled Metis skills", "per-agent skill allowlist"],
  },
];

function renderMetisCapabilitiesPanel() {
  return html`
    <section class="card">
      <div class="card-title">Metis capabilities</div>
      <div class="card-sub">Metis-owned built-in tools, skills, channel capabilities, and Gateway RPC surfaces.</div>
      <div class="callout info" style="margin-top: 12px;">
        This is a read-only capability inventory. It does not expose third-party plugin install toggles or copy public branding assets.
      </div>
      <div class="list" style="margin-top: 12px;">
        ${METIS_CAPABILITY_GROUPS.map(
          (group) => html`
            <div class="list-item">
              <div class="list-main">
                <div class="list-title">${group.title}</div>
                <div class="list-sub">${group.items.join(" · ")}</div>
              </div>
              <div class="list-meta"><span class="badge">${group.badge}</span></div>
            </div>
          `,
        )}
      </div>
    </section>
  `;
}

function renderFeishuAuthDoctorPanel(props: AgentTeamsPanelProps) {
  const status = objectValue(props.channelsSnapshot?.channels?.feishu);
  const capabilities = stringArrayFromUnknown(status?.capabilities);
  const auth = objectValue(status?.auth) ?? objectValue(status?.oauth);
  const doctor = objectValue(status?.doctor) ?? objectValue(status?.diagnostics);
  const oapiAvailable = capabilities.some((item) => {
    const normalized = item.toLowerCase();
    return normalized.includes("oapi") || normalized.includes("openapi");
  });
  const defaultAccount =
    resolveFeishuSettings(props).defaultAccount ||
    props.channelsSnapshot?.channelDefaultAccountId?.feishu ||
    "default";
  return html`
    <section class="card">
      <div class="card-title">Feishu Auth & Doctor</div>
      <div class="card-sub">Read-only Feishu status, auth, doctor, and OAPI signals from Gateway RPC.</div>
      <div class="callout info" style="margin-top: 12px;">
        UI will not write token files, app credentials, or local Feishu config. Auth start and token refresh must stay behind Gateway RPC or native Feishu commands.
      </div>
      ${props.feishuAuthError
        ? html`<div class="callout danger" style="margin-top: 12px;">${redactSecretText(props.feishuAuthError)}</div>`
        : nothing}
      <div class="agents-overview-grid" style="margin-top: 14px;">
        <div class="agent-kv">
          <div class="label">Account</div>
          <div class="mono">${defaultAccount}</div>
        </div>
        <div class="agent-kv">
          <div class="label">OAuth status</div>
          <div>${auth ? statusText(auth, ["status", "tokenStatus"], "status unknown") : "Auth status RPC missing"}</div>
        </div>
        <div class="agent-kv">
          <div class="label">Doctor</div>
          <div>${doctor ? statusText(doctor, ["status", "state"], "available") : "Doctor status RPC missing"}</div>
        </div>
        <div class="agent-kv">
          <div class="label">OAPI</div>
          <div>${oapiAvailable ? "OAPI capability advertised" : "OAPI status RPC missing"}</div>
        </div>
      </div>
      ${auth
        ? html`
            <div class="agent-kv" style="margin-top: 12px;">
              <div class="label">Auth summary</div>
              <div>
                ${statusText(auth, ["accountId"], defaultAccount)} ·
                ${statusText(auth, ["scopeSummary", "scopes"], "scope status missing")}
                ${stringOrEmpty(auth.error)
                  ? html`<div class="list-sub">Error: ${redactSecretText(stringOrEmpty(auth.error))}</div>`
                  : nothing}
              </div>
            </div>
          `
        : html`
            <div class="callout warning" style="margin-top: 12px;">
              Auth status RPC missing. Needed backend field: channels.status.channels.feishu.auth or oauth with redacted accountId, status, tokenStatus, and scopeSummary.
            </div>
          `}
      ${doctor
        ? html`
            <div class="agent-kv" style="margin-top: 12px;">
              <div class="label">Doctor summary</div>
              <div>${redactedJsonText(compactStatusObject(doctor, ["status", "state", "findings", "lastProbeAt", "message"]))}</div>
            </div>
          `
        : html`
            <div class="callout warning" style="margin-top: 12px;">
              Doctor status RPC missing. Use /feishu doctor until Gateway exposes a redacted Feishu doctor object to channels.status.
            </div>
          `}
      <div class="agent-model-actions">
        <button
          type="button"
          class="btn btn--sm primary"
          ?disabled=${props.feishuAuthLoading}
          @click=${() => props.onStartFeishuOAuth(defaultAccount)}
        >
          ${props.feishuAuthLoading ? "Starting OAuth..." : "Start OAuth via Gateway"}
        </button>
        <button
          type="button"
          class="btn btn--sm"
          ?disabled=${props.feishuAuthLoading}
          @click=${() => props.onStartFeishuOAuth(defaultAccount, "status")}
        >
          Status
        </button>
        <button
          type="button"
          class="btn btn--sm"
          ?disabled=${props.feishuAuthLoading}
          @click=${() => props.onStartFeishuOAuth(defaultAccount, "poll")}
        >
          Poll
        </button>
        <button
          type="button"
          class="btn btn--sm"
          ?disabled=${props.feishuAuthLoading}
          @click=${() => props.onStartFeishuOAuth(defaultAccount, "complete")}
        >
          Complete
        </button>
        <button
          type="button"
          class="btn btn--sm danger"
          ?disabled=${props.feishuAuthLoading}
          @click=${() => props.onStartFeishuOAuth(defaultAccount, "revoke")}
        >
          Revoke local auth
        </button>
      </div>
      ${props.feishuAuthResult
        ? html`
            <div class="agent-kv" style="margin-top: 12px;">
              <div class="label">OAuth lifecycle result</div>
              <pre class="mono" style="white-space: pre-wrap; margin: 0;">${redactedJsonText(props.feishuAuthResult)}</pre>
            </div>
          `
        : nothing}
      ${renderFeishuMissingSetupSteps(props, auth, doctor, oapiAvailable)}
    </section>
  `;
}

function renderFeishuMissingSetupSteps(
  props: AgentTeamsPanelProps,
  auth: Record<string, unknown> | null,
  doctor: Record<string, unknown> | null,
  oapiAvailable: boolean,
) {
  const feishu = resolveFeishuSettings(props);
  const steps = [
    {
      label: "Confirm Feishu app credentials",
      done: feishu.accounts.some((account) => account.configured === true),
    },
    {
      label: "Start OAuth through Gateway RPC",
      done: Boolean(auth) || Boolean(props.feishuAuthResult),
    },
    {
      label: "Grant offline_access and OAPI scopes",
      done: Boolean(auth && statusText(auth, ["scopeSummary", "scopes"], "").trim()),
    },
    {
      label: "Run Feishu doctor",
      done: Boolean(doctor),
    },
    {
      label: "Bind channel/account/peer/thread/team route",
      done: Boolean(props.bindingPreview?.applyPayload || safeJsonArrayLength(props.draft.bindingsJson) > 0),
    },
    {
      label: "Expose OAPI capability status",
      done: oapiAvailable,
    },
  ];
  return html`
    <div style="margin-top: 14px;">
      <div class="list-title">Missing setup steps</div>
      <div class="list" style="margin-top: 8px;">
        ${steps.map(
          (step) => html`
            <div class="list-item">
              <div class="list-main">
                <div class="list-title">${step.label}</div>
              </div>
              <div class="list-meta"><span class="badge">${step.done ? "done" : "needed"}</span></div>
            </div>
          `,
        )}
      </div>
    </div>
  `;
}

function renderCultivationPanel(props: AgentTeamsPanelProps) {
  const snapshot = buildAgentTeamCultivationSnapshot({
    workspace: props.workspace,
    channelsSnapshot: props.channelsSnapshot,
  });
  const files = [snapshot.memory, snapshot.heartbeat];
  return html`
    <section class="card">
      <div class="row" style="justify-content: space-between; align-items: flex-start;">
        <div>
          <div class="card-title">Cultivation, Memory & Heartbeat</div>
          <div class="card-sub">
            Baseline view of member training files and recent Gateway doctor findings. Values come from agents.files and channels.status only.
          </div>
        </div>
        <span class="badge">${snapshot.agentId || "choose member"}</span>
      </div>
      <div class="agents-overview-grid" style="margin-top: 14px;">
        ${files.map(
          (file) => html`
            <div class="agent-kv">
              <div class="label">${file.name}</div>
              <div>${file.name} ${file.status}</div>
              ${file.updatedAtMs ? html`<div class="agent-kv-sub">${file.updatedAtMs}</div>` : nothing}
            </div>
          `,
        )}
        <div class="agent-kv">
          <div class="label">Doctor status</div>
          <div>${snapshot.doctor.status}</div>
          ${snapshot.doctor.lastProbeAt
            ? html`<div class="agent-kv-sub">${snapshot.doctor.lastProbeAt}</div>`
            : nothing}
        </div>
        <div class="agent-kv">
          <div class="label">Findings</div>
          <div>${formatCount(snapshot.doctor.findings.length, "finding")}</div>
        </div>
      </div>
      <div class="grid grid-cols-2" style="margin-top: 14px;">
        ${renderCultivationPreview("Memory preview", snapshot.memory.preview)}
        ${renderCultivationPreview("Heartbeat preview", snapshot.heartbeat.preview)}
      </div>
      <div style="margin-top: 14px;">
        <div class="list-title">Recent doctor findings</div>
        <div class="list" style="margin-top: 8px;">
          ${snapshot.doctor.findings.length === 0
            ? html`<div class="callout success">No doctor findings are visible in the current Gateway status.</div>`
            : snapshot.doctor.findings.map(
                (finding) => html`
                  <div class="list-item">
                    <div class="list-main">
                      <div class="list-title">${finding.code}</div>
                      <div class="list-sub">${finding.message}</div>
                    </div>
                  </div>
                `,
              )}
        </div>
      </div>
      <div class="callout info" style="margin-top: 12px;">
        Use the Workspace Profiles editor for MEMORY.md and HEARTBEAT.md changes. This panel does not write secrets, tokens, or local files.
      </div>
    </section>
  `;
}

function renderCultivationPreview(title: string, preview: string) {
  return html`
    <div class="agent-kv">
      <div class="label">${title}</div>
      <div>${preview || "Load the file to show a redacted preview."}</div>
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
      <div class="callout info" style="margin-top: 12px;">
        Repair actions never write token, secret, or auth files from the browser. Secret and auth repair stays behind Gateway RPC or operator-managed backend configuration.
      </div>
      <div class="list" style="margin-top: 14px;">
        ${items.map(
          (item) => html`
            <div class="list-item">
              <div class="list-main">
                <div class="list-title">${item.title}</div>
                <div class="list-sub">${item.message}</div>
              </div>
              <div class="list-meta">
                <span class="badge">${item.status}</span>
                ${renderDoctorAction(props, item)}
              </div>
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

function downloadAgentTeamTemplate(draft: AgentTeamEditorDraft) {
  const text = exportAgentTeamTemplate(draft);
  if (typeof document === "undefined" || typeof URL === "undefined" || !URL.createObjectURL) {
    return;
  }
  const blob = new Blob([text], { type: "application/json" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = `${draft.id.trim() || "metis-agent-team-template"}.json`;
  link.click();
  URL.revokeObjectURL(url);
}

function importTemplateFile(event: Event, props: AgentTeamsPanelProps) {
  const input = event.target as HTMLInputElement;
  const file = input.files?.[0];
  if (!file) {
    return;
  }
  const reader = new FileReader();
  reader.onload = () => {
    try {
      props.onDraftChange(importAgentTeamTemplate(String(reader.result ?? "")));
    } catch (_err) {
      // Invalid template files are ignored here; Gateway mutations still validate drafts before saving.
    } finally {
      input.value = "";
    }
  };
  reader.readAsText(file);
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

function safeJsonArray(text: string): unknown[] {
  try {
    const parsed = JSON.parse(text || "[]") as unknown;
    return Array.isArray(parsed) ? parsed : [];
  } catch (_err) {
    return [];
  }
}

function buildTeamHealthSummary(
  props: AgentTeamsPanelProps,
  members: AgentTeamMember[],
  aliases: AgentTeamAliasDraft[],
  broadcast: Record<string, unknown>,
): { label: string; value: string }[] {
  const memberIds = new Set(members.map((member) => member.agentId).filter(Boolean));
  const bindings = safeJsonArray(props.draft.bindingsJson).map((entry) => objectValue(entry)).filter(Boolean);
  const bindingAgentIds = bindings.map((binding) => stringOrEmpty(binding?.agentId)).filter(Boolean);
  const missingRouteAgents = bindingAgentIds.filter((agentId) => !memberIds.has(agentId));
  const duplicateAliases = duplicateStrings(aliases.map((alias) => alias.alias.toLowerCase()).filter(Boolean));
  const missingProfileAgents = members
    .filter((member) => member.agentId && props.workspace.agentId !== member.agentId)
    .map((member) => member.agentId);
  const modelAgentId = props.modelResult?.models?.agentId || props.modelDraft.agentId;
  const missingModelAgents = members
    .filter((member) => member.agentId && modelAgentId !== member.agentId)
    .map((member) => member.agentId);
  const feishuStatus = objectValue(props.channelsSnapshot?.channels?.feishu);
  const feishuAuth = objectValue(feishuStatus?.auth) ?? objectValue(feishuStatus?.oauth);
  const missingAuth = isFeishuAuthAuthorized(feishuAuth) ? [] : ["Feishu OAuth"];
  const feishuReady = Boolean(
    feishuStatus?.configured === true &&
      feishuStatus?.running === true &&
      (props.channelsSnapshot?.channelAccounts?.feishu ?? []).length > 0 &&
      missingAuth.length === 0,
  );
  return [
    {
      label: "Routing conflicts",
      value: [...missingRouteAgents, ...duplicateAliases].join(", ") || "none",
    },
    {
      label: "Missing profiles",
      value: missingProfileAgents.join(", ") || "none",
    },
    {
      label: "Missing model",
      value: missingModelAgents.join(", ") || "none",
    },
    {
      label: "Missing auth",
      value: missingAuth.join(", ") || "none",
    },
    {
      label: "Feishu readiness",
      value: feishuReady ? "ready" : "needs repair",
    },
    {
      label: "Broadcast members",
      value: broadcastEnabled(broadcast)
        ? formatCount(stringArrayFromUnknown(broadcast.members).length, "member")
        : "disabled",
    },
  ];
}

function duplicateStrings(values: string[]): string[] {
  const seen = new Set<string>();
  const duplicates = new Set<string>();
  values.forEach((value) => {
    if (seen.has(value)) {
      duplicates.add(value);
    } else {
      seen.add(value);
    }
  });
  return Array.from(duplicates);
}

function formatCount(count: number, label: string): string {
  if (count === 1) {
    return `${count} ${label}`;
  }
  const plural = label === "alias" ? "aliases" : `${label}s`;
  return `${count} ${plural}`;
}

function resolveAgentTeamNextAction(
  props: AgentTeamsPanelProps,
  teams: AgentTeam[],
  members: AgentTeamMember[],
  bindingCount: number,
): string {
  if (props.error) {
    return "Repair Gateway RPC access";
  }
  if (teams.length === 0 && members.length === 0) {
    return "Start with a template";
  }
  if (members.length === 0) {
    return "Add team members";
  }
  if (bindingCount === 0 && !props.bindingPreview?.applyPayload) {
    return "Preview a channel binding";
  }
  if (!props.workspace.workspace) {
    return "Load member profile files";
  }
  if (!props.modelResult?.models) {
    return "Load member model state";
  }
  if (channelIsReady(props, "feishu") || channelIsReady(props, "telegram")) {
    return "Review and save team changes";
  }
  return "Repair channel setup";
}

function channelReadinessLabel(props: AgentTeamsPanelProps, channel: "feishu" | "telegram"): string {
  const label = channel === "feishu" ? "Feishu" : "Telegram";
  return `${label} ${channelIsReady(props, channel) ? "ready" : "needs setup"}`;
}

function channelIsReady(props: AgentTeamsPanelProps, channel: "feishu" | "telegram"): boolean {
  const status = objectValue(props.channelsSnapshot?.channels?.[channel]);
  const accounts = props.channelsSnapshot?.channelAccounts?.[channel] ?? [];
  return (
    status?.configured === true ||
    status?.running === true ||
    accounts.some((account) => account.configured === true || account.running === true || account.connected === true)
  );
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

type DoctorAction = "start-feishu-oauth" | "refresh" | "preview-binding" | "apply-binding";

type DoctorItem = {
  title: string;
  message: string;
  status: string;
  action?: DoctorAction;
};

function buildDoctorItems(
  props: AgentTeamsPanelProps,
  teams: AgentTeam[],
  members: AgentTeamMember[],
): DoctorItem[] {
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
    ...buildFeishuReadinessItems(props),
  ];
}

function buildFeishuReadinessItems(props: AgentTeamsPanelProps): DoctorItem[] {
  const feishu = resolveFeishuSettings(props);
  const status = objectValue(props.channelsSnapshot?.channels?.feishu);
  const capabilities = stringArrayFromUnknown(status?.capabilities).map((item) => item.toLowerCase());
  const auth = objectValue(status?.auth) ?? objectValue(status?.oauth);
  const doctor = objectValue(status?.doctor) ?? objectValue(status?.diagnostics);
  const oapiAvailable = capabilities.some((item) => item.includes("oapi") || item.includes("openapi"));
  const appScopeGaps = missingScopes(auth, ["missingAppScopes", "missing_app_scopes", "appScopeMissing"]);
  const userScopeGaps = missingScopes(auth, ["missingUserScopes", "missing_user_scopes", "userScopeMissing"]);
  const authOk = isFeishuAuthAuthorized(auth);
  const userScopesOk = authOk && userScopeGaps.length === 0 && authHasOfflineAccess(auth);
  const groupPolicyDisabled = feishu.groupCount === 0 || doctorHasFinding(doctor, "disabled_group_policy");
  const hasBinding = safeJsonArrayLength(props.draft.bindingsJson) > 0 || Boolean(props.bindingPreview?.applyPayload);
  const hasAccount = feishu.accounts.length > 0;
  const appScopesOk = appScopeGaps.length === 0 && oapiAvailable;
  return [
    {
      title: authOk ? "OAuth authorized" : "Missing OAuth",
      message: authOk
        ? `Feishu account ${feishu.defaultAccount || "default"} has an authorized OAuth status.`
        : "Start OAuth through Gateway RPC; the browser will not write token files.",
      status: authOk ? "ok" : "repair",
      action: authOk ? undefined : "start-feishu-oauth",
    },
    {
      title: appScopesOk ? "App scope ready" : "Missing app scope",
      message: appScopesOk
        ? "Feishu OAPI/app scope capability is advertised by Gateway status."
        : `Missing app scopes: ${appScopeGaps.length ? appScopeGaps.join(", ") : "OAPI capability not advertised"}. Update the Feishu app in backend/admin config, then refresh.`,
      status: appScopesOk ? "ok" : "manual",
      action: appScopesOk ? undefined : "refresh",
    },
    {
      title: userScopesOk ? "User scope ready" : "Missing user scope",
      message: userScopesOk
        ? "User OAuth scopes include offline access."
        : `Missing user scopes: ${userScopeGaps.length ? userScopeGaps.join(", ") : "offline_access"}. Re-run Gateway OAuth after app scopes are granted.`,
      status: userScopesOk ? "ok" : "repair",
      action: userScopesOk ? undefined : "start-feishu-oauth",
    },
    {
      title: hasAccount ? "Channel account ready" : "Missing channel account",
      message: hasAccount
        ? "channels.status exposes a redacted Feishu channel account."
        : "No redacted Feishu channel account is visible. Configure the account behind Gateway, then refresh.",
      status: hasAccount ? "ok" : "manual",
      action: hasAccount ? undefined : "refresh",
    },
    {
      title: groupPolicyDisabled ? "Disabled group policy" : "Group policy ready",
      message: groupPolicyDisabled
        ? "No Feishu group policy is visible or doctor reports disabled_group_policy. Repair belongs in non-secret Gateway configuration."
        : "Feishu group policy is visible in Control UI status/config.",
      status: groupPolicyDisabled ? "manual" : "ok",
      action: groupPolicyDisabled ? "refresh" : undefined,
    },
    {
      title: hasBinding ? "Binding ready" : "Missing binding",
      message: hasBinding
        ? "Team binding metadata or a Binding Builder preview is ready."
        : "Seed a Telegram or Feishu route, preview it, then apply it through agents.bind.",
      status: hasBinding ? "ok" : "repair",
      action: hasBinding ? (props.bindingPreview?.applyPayload ? "apply-binding" : undefined) : "preview-binding",
    },
  ];
}

function renderDoctorAction(props: AgentTeamsPanelProps, item: DoctorItem) {
  if (!item.action) {
    return nothing;
  }
  if (item.action === "start-feishu-oauth") {
    const accountId = resolveFeishuSettings(props).defaultAccount || props.channelsSnapshot?.channelDefaultAccountId?.feishu || "default";
    return html`
      <button
        type="button"
        class="btn btn--sm"
        ?disabled=${props.feishuAuthLoading}
        @click=${() => props.onStartFeishuOAuth(accountId)}
      >
        Start OAuth
      </button>
    `;
  }
  if (item.action === "refresh") {
    return html`<button type="button" class="btn btn--sm" ?disabled=${props.loading} @click=${props.onRefresh}>Refresh status</button>`;
  }
  if (item.action === "apply-binding") {
    return html`
      <button
        type="button"
        class="btn btn--sm"
        ?disabled=${props.saving || !props.bindingPreview?.applyPayload}
        @click=${props.onApplyBinding}
      >
        Apply binding
      </button>
    `;
  }
  return html`<button type="button" class="btn btn--sm" @click=${props.onPreviewBinding}>Preview binding</button>`;
}

function isFeishuAuthAuthorized(auth: Record<string, unknown> | null): boolean {
  if (!auth) {
    return false;
  }
  const values = ["status", "tokenStatus", "state"]
    .map((key) => stringOrEmpty(auth[key]).toLowerCase())
    .filter(Boolean);
  if (values.some((value) => value.includes("missing") || value.includes("expired"))) {
    return false;
  }
  return values.some((value) => ["authorized", "ok", "active", "valid"].includes(value));
}

function authHasOfflineAccess(auth: Record<string, unknown> | null): boolean {
  if (!auth) {
    return false;
  }
  const scopes = [
    ...missingScopes(auth, ["scopeSummary", "scopes", "userScopes", "grantedUserScopes"]),
  ].map((scope) => scope.toLowerCase());
  return scopes.some((scope) => scope === "offline_access" || scope.includes("offline_access"));
}

function missingScopes(obj: Record<string, unknown> | null, keys: string[]): string[] {
  if (!obj) {
    return [];
  }
  for (const key of keys) {
    const value = obj[key];
    if (Array.isArray(value)) {
      return stringArrayFromUnknown(value);
    }
    if (typeof value === "string" && value.trim()) {
      return value
        .split(/[\s,]+/)
        .map((part) => part.trim())
        .filter(Boolean);
    }
  }
  return [];
}

function doctorHasFinding(doctor: Record<string, unknown> | null, code: string): boolean {
  if (!doctor) {
    return false;
  }
  const normalizedCode = code.toLowerCase();
  return Object.values(doctor).some((value) => hasFindingValue(value, normalizedCode));
}

function hasFindingValue(value: unknown, normalizedCode: string): boolean {
  if (typeof value === "string") {
    return value.toLowerCase().includes(normalizedCode);
  }
  if (Array.isArray(value)) {
    return value.some((entry) => hasFindingValue(entry, normalizedCode));
  }
  const obj = objectValue(value);
  if (!obj) {
    return false;
  }
  return Object.values(obj).some((entry) => hasFindingValue(entry, normalizedCode));
}

function objectValue(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null;
}

type ModelProviderChip = {
  label: string;
  provider: string;
  runtimeProvider: string;
  modelRef: string;
  status: string;
};

function modelProviderChips(model: AgentModelsResult["models"]): ModelProviderChip[] {
  const state = objectValue(model.state);
  const providers = state?.providers;
  const chips: ModelProviderChip[] = [];
  if (Array.isArray(providers)) {
    providers.forEach((provider) => {
      const chip = modelProviderChipFromObject(objectValue(provider));
      if (chip) {
        chips.push(chip);
      }
    });
  } else {
    const providerObject = objectValue(providers);
    if (providerObject) {
      Object.entries(providerObject).forEach(([providerId, value]) => {
        const item = objectValue(value) ?? { provider: providerId };
        const chip = modelProviderChipFromObject({ ...item, provider: item.provider ?? providerId });
        if (chip) {
          chips.push(chip);
        }
      });
    }
  }
  if (chips.length === 0 && model.primaryModelRef) {
    const provider = model.primaryModelRef.includes(":") ? model.primaryModelRef.split(":")[0] : "";
    chips.push({
      label: provider || "Primary model",
      provider,
      runtimeProvider: provider,
      modelRef: model.primaryModelRef,
      status: "primary",
    });
  }
  return chips;
}

function modelProviderChipFromObject(item: Record<string, unknown> | null): ModelProviderChip | null {
  if (!item) {
    return null;
  }
  const provider = stringOrEmpty(item.provider) || stringOrEmpty(item.id);
  const runtimeProvider = stringOrEmpty(item.runtimeProvider) || stringOrEmpty(item.runtime_provider);
  const modelRef =
    stringOrEmpty(item.defaultModelRef) ||
    stringOrEmpty(item.modelRef) ||
    stringOrEmpty(item.model) ||
    stringOrEmpty(item.runtimeModelRef);
  const label = stringOrEmpty(item.displayName) || stringOrEmpty(item.name) || provider || runtimeProvider || modelRef;
  if (!label) {
    return null;
  }
  return {
    label,
    provider,
    runtimeProvider,
    modelRef,
    status: providerConfiguredStatus(item.configured),
  };
}

function providerConfiguredStatus(value: unknown): string {
  if (value === true) {
    return "configured";
  }
  if (value === false) {
    return "needs credentials";
  }
  return "status unknown";
}

function statusText(
  obj: Record<string, unknown>,
  keys: string[],
  fallback: string,
): string {
  for (const key of keys) {
    const value = obj[key];
    if (typeof value === "string" && value.trim()) {
      return redactSecretText(value.trim());
    }
    if (typeof value === "number" || typeof value === "boolean") {
      return String(value);
    }
    if (Array.isArray(value)) {
      const joined = value.map((item) => String(item).trim()).filter(Boolean).join(", ");
      if (joined) {
        return redactSecretText(joined);
      }
    }
  }
  return fallback;
}

function compactStatusObject(
  obj: Record<string, unknown>,
  keys: string[],
): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  keys.forEach((key) => {
    if (obj[key] !== undefined) {
      out[key] = obj[key];
    }
  });
  return out;
}

function redactedJsonText(value: unknown): string {
  try {
    return redactSecretText(JSON.stringify(value ?? {}, null, 2));
  } catch (_err) {
    return redactSecretText(String(value ?? ""));
  }
}

function stringOrEmpty(value: unknown): string {
  return typeof value === "string" ? value : "";
}

function redactSecretText(value: string): string {
  return value
    .replace(/\bBearer\s+[^\s"',;]+/gi, "Bearer [redacted]")
    .replace(/authorization:\s*bearer\s+[^\s,;]+/gi, "Authorization: Bearer [redacted]")
    .replace(/\b(access|refresh|bot|app)[_-]?token\s*[:=]\s*[^\s,;]+/gi, "$1_token=[redacted]")
    .replace(/(["']?(?:access|refresh|bot|app)[_-]?token["']?\s*[:=]\s*)["']?[^"',;\s]+["']?/gi, "$1[redacted]")
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
