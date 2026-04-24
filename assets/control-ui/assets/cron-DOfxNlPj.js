import{f as e,r as t,u as n}from"./i18n-CV7rUnW0.js";import{i as r,l as i}from"./format-EHph2kGh.js";import{M as a,a as o,n as s}from"./index-DWX0XMYb.js";var c=e=>e??n;function l(){return[{value:`ok`,label:t(`cron.runs.runStatusOk`)},{value:`error`,label:t(`cron.runs.runStatusError`)},{value:`skipped`,label:t(`cron.runs.runStatusSkipped`)}]}function u(){return[{value:`delivered`,label:t(`cron.runs.deliveryDelivered`)},{value:`not-delivered`,label:t(`cron.runs.deliveryNotDelivered`)},{value:`unknown`,label:t(`cron.runs.deliveryUnknown`)},{value:`not-requested`,label:t(`cron.runs.deliveryNotRequested`)}]}function d(e,t,n){let r=new Set(e);return n?r.add(t):r.delete(t),Array.from(r)}function f(e,t){return e.length===0?t:e.length<=2?e.join(`, `):`${e[0]} +${e.length-1}`}function p(e){let t=[`last`,...e.channels.filter(Boolean)],n=e.form.deliveryChannel?.trim();n&&!t.includes(n)&&t.push(n);let r=new Set;return t.filter(e=>r.has(e)?!1:(r.add(e),!0))}function m(e,t){if(t===`last`)return`last`;let n=e.channelMeta?.find(e=>e.id===t);return n?.label?n.label:e.channelLabels?.[t]??t}function h(n){return e`
    <div class="field cron-filter-dropdown" data-filter=${n.id}>
      <span>${n.title}</span>
      <details class="cron-filter-dropdown__details">
        <summary class="btn cron-filter-dropdown__trigger">
          <span>${n.summary}</span>
        </summary>
        <div class="cron-filter-dropdown__panel">
          <div class="cron-filter-dropdown__list">
            ${n.options.map(t=>e`
                <label class="cron-filter-dropdown__option">
                  <input
                    type="checkbox"
                    value=${t.value}
                    .checked=${n.selected.includes(t.value)}
                    @change=${e=>{let r=e.target;n.onToggle(t.value,r.checked)}}
                  />
                  <span>${t.label}</span>
                </label>
              `)}
          </div>
          <div class="row">
            <button class="btn" type="button" @click=${n.onClear}>
              ${t(`cron.runs.clear`)}
            </button>
          </div>
        </div>
      </details>
    </div>
  `}function g(t,r){let i=Array.from(new Set(r.map(e=>e.trim()).filter(Boolean)));return i.length===0?n:e`<datalist id=${t}>
    ${i.map(t=>e`<option value=${t}></option> `)}
  </datalist>`}function _(e){return`cron-error-${e}`}function v(e){return e===`name`?`cron-name`:e===`scheduleAt`?`cron-schedule-at`:e===`everyAmount`?`cron-every-amount`:e===`cronExpr`?`cron-cron-expr`:e===`staggerAmount`?`cron-stagger-amount`:e===`payloadText`?`cron-payload-text`:e===`payloadModel`?`cron-payload-model`:e===`payloadThinking`?`cron-payload-thinking`:e===`timeoutSeconds`?`cron-timeout-seconds`:e===`failureAlertAfter`?`cron-failure-alert-after`:e===`failureAlertCooldownSeconds`?`cron-failure-alert-cooldown-seconds`:`cron-delivery-to`}function y(e,n,r){return e===`payloadText`?n.payloadKind===`systemEvent`?t(`cron.form.mainTimelineMessage`):t(`cron.form.assistantTaskPrompt`):e===`deliveryTo`?t(r===`webhook`?`cron.form.webhookUrl`:`cron.form.to`):{name:t(`cron.form.fieldName`),scheduleAt:t(`cron.form.runAt`),everyAmount:t(`cron.form.every`),cronExpr:t(`cron.form.expression`),staggerAmount:t(`cron.form.staggerWindow`),payloadText:t(`cron.form.assistantTaskPrompt`),payloadModel:t(`cron.form.model`),payloadThinking:t(`cron.form.thinking`),timeoutSeconds:t(`cron.form.timeoutSeconds`),deliveryTo:t(`cron.form.to`),failureAlertAfter:`Failure alert after`,failureAlertCooldownSeconds:`Failure alert cooldown`}[e]}function b(e,t,n){let r=[`name`,`scheduleAt`,`everyAmount`,`cronExpr`,`staggerAmount`,`payloadText`,`payloadModel`,`payloadThinking`,`timeoutSeconds`,`deliveryTo`,`failureAlertAfter`,`failureAlertCooldownSeconds`],i=[];for(let a of r){let r=e[a];r&&i.push({key:a,label:y(a,t,n),message:r,inputId:v(a)})}return i}function x(e){let t=document.getElementById(e);t instanceof HTMLElement&&(typeof t.scrollIntoView==`function`&&t.scrollIntoView({block:`center`,behavior:`smooth`}),t.focus())}function S(r,i=!1){return e`<span>
    ${r}
    ${i?e`
          <span class="cron-required-marker" aria-hidden="true">*</span>
          <span class="cron-required-sr">${t(`cron.form.requiredSr`)}</span>
        `:n}
  </span>`}function C(r){let i=!!r.editingJobId,a=r.form.payloadKind===`agentTurn`,s=r.form.scheduleKind===`cron`,v=p(r),y=r.runsJobId==null?void 0:r.jobs.find(e=>e.id===r.runsJobId),C=r.runsScope===`all`?t(`cron.jobList.allJobs`):y?.name??r.runsJobId??t(`cron.jobList.selectJob`),D=r.runs.toSorted((e,t)=>r.runsSortDir===`asc`?e.ts-t.ts:t.ts-e.ts),O=l(),k=u(),A=O.filter(e=>r.runsStatuses.includes(e.value)).map(e=>e.label),j=k.filter(e=>r.runsDeliveryStatuses.includes(e.value)).map(e=>e.label),M=f(A,t(`cron.runs.allStatuses`)),P=f(j,t(`cron.runs.allDelivery`)),F=r.form.sessionTarget!==`main`&&r.form.payloadKind===`agentTurn`,I=r.form.deliveryMode===`announce`&&!F?`none`:r.form.deliveryMode,L=b(r.fieldErrors,r.form,I),R=!r.busy&&L.length>0,z=r.jobsQuery.trim().length>0||r.jobsEnabledFilter!==`all`||r.jobsScheduleKindFilter!==`all`||r.jobsLastStatusFilter!==`all`||r.jobsSortBy!==`nextRunAtMs`||r.jobsSortDir!==`asc`,B=R&&!r.canSubmit?L.length===1?t(`cron.form.fixFields`,{count:String(L.length)}):t(`cron.form.fixFieldsPlural`,{count:String(L.length)}):``;return e`
    <section class="card cron-summary-strip">
      <div class="cron-summary-strip__left">
        <div class="cron-summary-item">
          <div class="cron-summary-label">${t(`cron.summary.enabled`)}</div>
          <div class="cron-summary-value">
            <span class=${`chip ${r.status?.enabled?`chip-ok`:`chip-danger`}`}>
              ${r.status?r.status.enabled?t(`cron.summary.yes`):t(`cron.summary.no`):t(`common.na`)}
            </span>
          </div>
        </div>
        <div class="cron-summary-item">
          <div class="cron-summary-label">${t(`cron.summary.jobs`)}</div>
          <div class="cron-summary-value">${r.status?.jobs??t(`common.na`)}</div>
        </div>
        <div class="cron-summary-item cron-summary-item--wide">
          <div class="cron-summary-label">${t(`cron.summary.nextWake`)}</div>
          <div class="cron-summary-value">${o(r.status?.nextWakeAtMs??null)}</div>
        </div>
      </div>
      <div class="cron-summary-strip__actions">
        <button
          class=${r.loading?`btn cron-refresh-btn--loading`:`btn`}
          ?disabled=${r.loading}
          @click=${r.onRefresh}
        >
          ${r.loading?t(`cron.summary.refreshing`):t(`cron.summary.refresh`)}
        </button>
        ${r.error?e`<span class="muted">${r.error}</span>`:n}
      </div>
    </section>

    <section class="cron-workspace">
      <div class="cron-workspace-main">
        <section class="card">
          <div
            class="row"
            style="justify-content: space-between; align-items: flex-start; gap: 12px;"
          >
            <div>
              <div class="card-title">${t(`cron.jobs.title`)}</div>
              <div class="card-sub">${t(`cron.jobs.subtitle`)}</div>
            </div>
            <div class="muted">
              ${t(`cron.jobs.shownOf`,{shown:String(r.jobs.length),total:String(r.jobsTotal)})}
            </div>
          </div>
          <div class="filters" style="margin-top: 12px;">
            <label class="field cron-filter-search">
              <span>${t(`cron.jobs.searchJobs`)}</span>
              <input
                .value=${r.jobsQuery}
                placeholder=${t(`cron.jobs.searchPlaceholder`)}
                @input=${e=>r.onJobsFiltersChange({cronJobsQuery:e.target.value})}
              />
            </label>
            <label class="field">
              <span>${t(`cron.jobs.enabled`)}</span>
              <select
                .value=${r.jobsEnabledFilter}
                @change=${e=>r.onJobsFiltersChange({cronJobsEnabledFilter:e.target.value})}
              >
                <option value="all">${t(`cron.jobs.all`)}</option>
                <option value="enabled">${t(`common.enabled`)}</option>
                <option value="disabled">${t(`common.disabled`)}</option>
              </select>
            </label>
            <label class="field">
              <span>${t(`cron.jobs.schedule`)}</span>
              <select
                data-test-id="cron-jobs-schedule-filter"
                .value=${r.jobsScheduleKindFilter}
                @change=${e=>r.onJobsFiltersChange({cronJobsScheduleKindFilter:e.target.value})}
              >
                <option value="all">${t(`cron.jobs.all`)}</option>
                <option value="at">${t(`cron.form.at`)}</option>
                <option value="every">${t(`cron.form.every`)}</option>
                <option value="cron">${t(`cron.form.cronOption`)}</option>
              </select>
            </label>
            <label class="field">
              <span>${t(`cron.jobs.lastRun`)}</span>
              <select
                data-test-id="cron-jobs-last-status-filter"
                .value=${r.jobsLastStatusFilter}
                @change=${e=>r.onJobsFiltersChange({cronJobsLastStatusFilter:e.target.value})}
              >
                <option value="all">${t(`cron.jobs.all`)}</option>
                <option value="ok">${t(`cron.runs.runStatusOk`)}</option>
                <option value="error">${t(`cron.runs.runStatusError`)}</option>
                <option value="skipped">${t(`cron.runs.runStatusSkipped`)}</option>
              </select>
            </label>
            <label class="field">
              <span>${t(`cron.jobs.sort`)}</span>
              <select
                .value=${r.jobsSortBy}
                @change=${e=>r.onJobsFiltersChange({cronJobsSortBy:e.target.value})}
              >
                <option value="nextRunAtMs">${t(`cron.jobs.nextRun`)}</option>
                <option value="updatedAtMs">${t(`cron.jobs.recentlyUpdated`)}</option>
                <option value="name">${t(`cron.jobs.name`)}</option>
              </select>
            </label>
            <label class="field">
              <span>${t(`cron.jobs.direction`)}</span>
              <select
                .value=${r.jobsSortDir}
                @change=${e=>r.onJobsFiltersChange({cronJobsSortDir:e.target.value})}
              >
                <option value="asc">${t(`cron.jobs.ascending`)}</option>
                <option value="desc">${t(`cron.jobs.descending`)}</option>
              </select>
            </label>
            <label class="field">
              <span>${t(`cron.jobs.reset`)}</span>
              <button
                class="btn"
                data-test-id="cron-jobs-filters-reset"
                ?disabled=${!z}
                @click=${r.onJobsFiltersReset}
              >
                ${t(`cron.jobs.reset`)}
              </button>
            </label>
          </div>
          ${r.jobs.length===0?e` <div class="muted" style="margin-top: 12px">${t(`cron.jobs.noMatching`)}</div> `:e`
                <div class="list" style="margin-top: 12px;">
                  ${r.jobs.map(e=>E(e,r))}
                </div>
              `}
          ${r.jobsHasMore?e`
                <div class="row" style="margin-top: 12px">
                  <button
                    class="btn"
                    ?disabled=${r.loading||r.jobsLoadingMore}
                    @click=${r.onLoadMoreJobs}
                  >
                    ${r.jobsLoadingMore?t(`cron.jobs.loading`):t(`cron.jobs.loadMore`)}
                  </button>
                </div>
              `:n}
        </section>

        <section class="card">
          <div
            class="row"
            style="justify-content: space-between; align-items: flex-start; gap: 12px;"
          >
            <div>
              <div class="card-title">${t(`cron.runs.title`)}</div>
              <div class="card-sub">
                ${r.runsScope===`all`?t(`cron.runs.subtitleAll`):t(`cron.runs.subtitleJob`,{title:C})}
              </div>
            </div>
            <div class="muted">
              ${t(`cron.jobs.shownOf`,{shown:String(D.length),total:String(r.runsTotal)})}
            </div>
          </div>
          <div class="cron-run-filters">
            <div class="cron-run-filters__row cron-run-filters__row--primary">
              <label class="field">
                <span>${t(`cron.runs.scope`)}</span>
                <select
                  .value=${r.runsScope}
                  @change=${e=>r.onRunsFiltersChange({cronRunsScope:e.target.value})}
                >
                  <option value="all">${t(`cron.runs.allJobs`)}</option>
                  <option value="job" ?disabled=${r.runsJobId==null}>
                    ${t(`cron.runs.selectedJob`)}
                  </option>
                </select>
              </label>
              <label class="field cron-run-filter-search">
                <span>${t(`cron.runs.searchRuns`)}</span>
                <input
                  .value=${r.runsQuery}
                  placeholder=${t(`cron.runs.searchPlaceholder`)}
                  @input=${e=>r.onRunsFiltersChange({cronRunsQuery:e.target.value})}
                />
              </label>
              <label class="field">
                <span>${t(`cron.jobs.sort`)}</span>
                <select
                  .value=${r.runsSortDir}
                  @change=${e=>r.onRunsFiltersChange({cronRunsSortDir:e.target.value})}
                >
                  <option value="desc">${t(`cron.runs.newestFirst`)}</option>
                  <option value="asc">${t(`cron.runs.oldestFirst`)}</option>
                </select>
              </label>
            </div>
            <div class="cron-run-filters__row cron-run-filters__row--secondary">
              ${h({id:`status`,title:t(`cron.runs.status`),summary:M,options:O,selected:r.runsStatuses,onToggle:(e,t)=>{let n=d(r.runsStatuses,e,t);r.onRunsFiltersChange({cronRunsStatuses:n})},onClear:()=>{r.onRunsFiltersChange({cronRunsStatuses:[]})}})}
              ${h({id:`delivery`,title:t(`cron.runs.delivery`),summary:P,options:k,selected:r.runsDeliveryStatuses,onToggle:(e,t)=>{let n=d(r.runsDeliveryStatuses,e,t);r.onRunsFiltersChange({cronRunsDeliveryStatuses:n})},onClear:()=>{r.onRunsFiltersChange({cronRunsDeliveryStatuses:[]})}})}
            </div>
          </div>
          ${r.runsScope===`job`&&r.runsJobId==null?e`
                <div class="muted" style="margin-top: 12px">${t(`cron.runs.selectJobHint`)}</div>
              `:D.length===0?e`
                  <div class="muted" style="margin-top: 12px">${t(`cron.runs.noMatching`)}</div>
                `:e`
                  <div class="list" style="margin-top: 12px;">
                    ${D.map(e=>N(e,r.basePath,r.onNavigateToChat))}
                  </div>
                `}
          ${(r.runsScope===`all`||r.runsJobId!=null)&&r.runsHasMore?e`
                <div class="row" style="margin-top: 12px">
                  <button
                    class="btn"
                    ?disabled=${r.runsLoadingMore}
                    @click=${r.onLoadMoreRuns}
                  >
                    ${r.runsLoadingMore?t(`cron.jobs.loading`):t(`cron.runs.loadMore`)}
                  </button>
                </div>
              `:n}
        </section>
      </div>

      <section class="card cron-workspace-form">
        <div class="card-title">${t(i?`cron.form.editJob`:`cron.form.newJob`)}</div>
        <div class="card-sub">
          ${t(i?`cron.form.updateSubtitle`:`cron.form.createSubtitle`)}
        </div>
        <div class="cron-form">
          <div class="cron-required-legend">
            <span class="cron-required-marker" aria-hidden="true">*</span> ${t(`cron.form.required`)}
          </div>
          <section class="cron-form-section">
            <div class="cron-form-section__title">${t(`cron.form.basics`)}</div>
            <div class="cron-form-section__sub">${t(`cron.form.basicsSub`)}</div>
            <div class="form-grid cron-form-grid">
              <label class="field">
                ${S(t(`cron.form.fieldName`),!0)}
                <input
                  id="cron-name"
                  .value=${r.form.name}
                  placeholder=${t(`cron.form.namePlaceholder`)}
                  aria-invalid=${r.fieldErrors.name?`true`:`false`}
                  aria-describedby=${c(r.fieldErrors.name?_(`name`):void 0)}
                  @input=${e=>r.onFormChange({name:e.target.value})}
                />
                ${T(r.fieldErrors.name,_(`name`))}
              </label>
              <label class="field">
                <span>${t(`cron.form.description`)}</span>
                <input
                  .value=${r.form.description}
                  placeholder=${t(`cron.form.descriptionPlaceholder`)}
                  @input=${e=>r.onFormChange({description:e.target.value})}
                />
              </label>
              <label class="field">
                ${S(t(`cron.form.agentId`))}
                <input
                  id="cron-agent-id"
                  .value=${r.form.agentId}
                  list="cron-agent-suggestions"
                  ?disabled=${r.form.clearAgent}
                  @input=${e=>r.onFormChange({agentId:e.target.value})}
                  placeholder=${t(`cron.form.agentPlaceholder`)}
                />
                <div class="cron-help">${t(`cron.form.agentHelp`)}</div>
              </label>
              <label class="field checkbox cron-checkbox cron-checkbox-inline">
                <input
                  type="checkbox"
                  .checked=${r.form.enabled}
                  @change=${e=>r.onFormChange({enabled:e.target.checked})}
                />
                <span class="field-checkbox__label">${t(`cron.summary.enabled`)}</span>
              </label>
            </div>
          </section>

          <section class="cron-form-section">
            <div class="cron-form-section__title">${t(`cron.form.schedule`)}</div>
            <div class="cron-form-section__sub">${t(`cron.form.scheduleSub`)}</div>
            <div class="form-grid cron-form-grid">
              <label class="field cron-span-2">
                ${S(t(`cron.form.schedule`))}
                <select
                  id="cron-schedule-kind"
                  .value=${r.form.scheduleKind}
                  @change=${e=>r.onFormChange({scheduleKind:e.target.value})}
                >
                  <option value="every">${t(`cron.form.every`)}</option>
                  <option value="at">${t(`cron.form.at`)}</option>
                  <option value="cron">${t(`cron.form.cronOption`)}</option>
                </select>
              </label>
            </div>
            ${w(r)}
          </section>

          <section class="cron-form-section">
            <div class="cron-form-section__title">${t(`cron.form.execution`)}</div>
            <div class="cron-form-section__sub">${t(`cron.form.executionSub`)}</div>
            <div class="form-grid cron-form-grid">
              <label class="field">
                ${S(t(`cron.form.session`))}
                <select
                  id="cron-session-target"
                  .value=${r.form.sessionTarget}
                  @change=${e=>r.onFormChange({sessionTarget:e.target.value})}
                >
                  <option value="main">${t(`cron.form.main`)}</option>
                  <option value="isolated">${t(`cron.form.isolated`)}</option>
                </select>
                <div class="cron-help">${t(`cron.form.sessionHelp`)}</div>
              </label>
              <label class="field">
                ${S(t(`cron.form.wakeMode`))}
                <select
                  id="cron-wake-mode"
                  .value=${r.form.wakeMode}
                  @change=${e=>r.onFormChange({wakeMode:e.target.value})}
                >
                  <option value="now">${t(`cron.form.now`)}</option>
                  <option value="next-heartbeat">${t(`cron.form.nextHeartbeat`)}</option>
                </select>
                <div class="cron-help">${t(`cron.form.wakeModeHelp`)}</div>
              </label>
              <label class="field ${a?``:`cron-span-2`}">
                ${S(t(`cron.form.payloadKind`))}
                <select
                  id="cron-payload-kind"
                  .value=${r.form.payloadKind}
                  @change=${e=>r.onFormChange({payloadKind:e.target.value})}
                >
                  <option value="systemEvent">${t(`cron.form.systemEvent`)}</option>
                  <option value="agentTurn">${t(`cron.form.agentTurn`)}</option>
                </select>
                <div class="cron-help">
                  ${r.form.payloadKind===`systemEvent`?t(`cron.form.systemEventHelp`):t(`cron.form.agentTurnHelp`)}
                </div>
              </label>
              ${a?e`
                    <label class="field">
                      ${S(t(`cron.form.timeoutSeconds`))}
                      <input
                        id="cron-timeout-seconds"
                        .value=${r.form.timeoutSeconds}
                        placeholder=${t(`cron.form.timeoutPlaceholder`)}
                        aria-invalid=${r.fieldErrors.timeoutSeconds?`true`:`false`}
                        aria-describedby=${c(r.fieldErrors.timeoutSeconds?_(`timeoutSeconds`):void 0)}
                        @input=${e=>r.onFormChange({timeoutSeconds:e.target.value})}
                      />
                      <div class="cron-help">${t(`cron.form.timeoutHelp`)}</div>
                      ${T(r.fieldErrors.timeoutSeconds,_(`timeoutSeconds`))}
                    </label>
                  `:n}
            </div>
            <label class="field cron-span-2">
              ${S(r.form.payloadKind===`systemEvent`?t(`cron.form.mainTimelineMessage`):t(`cron.form.assistantTaskPrompt`),!0)}
              <textarea
                id="cron-payload-text"
                .value=${r.form.payloadText}
                aria-invalid=${r.fieldErrors.payloadText?`true`:`false`}
                aria-describedby=${c(r.fieldErrors.payloadText?_(`payloadText`):void 0)}
                @input=${e=>r.onFormChange({payloadText:e.target.value})}
                rows="4"
              ></textarea>
              ${T(r.fieldErrors.payloadText,_(`payloadText`))}
            </label>
          </section>

          <section class="cron-form-section">
            <div class="cron-form-section__title">${t(`cron.form.deliverySection`)}</div>
            <div class="cron-form-section__sub">${t(`cron.form.deliverySub`)}</div>
            <div class="form-grid cron-form-grid">
              <label class="field ${I===`none`?`cron-span-2`:``}">
                ${S(t(`cron.form.resultDelivery`))}
                <select
                  id="cron-delivery-mode"
                  .value=${I}
                  @change=${e=>r.onFormChange({deliveryMode:e.target.value})}
                >
                  ${F?e` <option value="announce">${t(`cron.form.announceDefault`)}</option> `:n}
                  <option value="webhook">${t(`cron.form.webhookPost`)}</option>
                  <option value="none">${t(`cron.form.noneInternal`)}</option>
                </select>
                <div class="cron-help">${t(`cron.form.deliveryHelp`)}</div>
              </label>
              ${I===`none`?n:e`
                    <label class="field ${I===`webhook`?`cron-span-2`:``}">
                      ${S(t(I===`webhook`?`cron.form.webhookUrl`:`cron.form.channel`),I===`webhook`)}
                      ${I===`webhook`?e`
                            <input
                              id="cron-delivery-to"
                              .value=${r.form.deliveryTo}
                              list="cron-delivery-to-suggestions"
                              aria-invalid=${r.fieldErrors.deliveryTo?`true`:`false`}
                              aria-describedby=${c(r.fieldErrors.deliveryTo?_(`deliveryTo`):void 0)}
                              @input=${e=>r.onFormChange({deliveryTo:e.target.value})}
                              placeholder=${t(`cron.form.webhookPlaceholder`)}
                            />
                          `:e`
                            <select
                              id="cron-delivery-channel"
                              .value=${r.form.deliveryChannel||`last`}
                              @change=${e=>r.onFormChange({deliveryChannel:e.target.value})}
                            >
                              ${v.map(t=>e`<option value=${t}>
                                    ${m(r,t)}
                                  </option>`)}
                            </select>
                          `}
                      ${I===`announce`?e` <div class="cron-help">${t(`cron.form.channelHelp`)}</div> `:e` <div class="cron-help">${t(`cron.form.webhookHelp`)}</div> `}
                    </label>
                    ${I===`announce`?e`
                          <label class="field cron-span-2">
                            ${S(t(`cron.form.to`))}
                            <input
                              id="cron-delivery-to"
                              .value=${r.form.deliveryTo}
                              list="cron-delivery-to-suggestions"
                              @input=${e=>r.onFormChange({deliveryTo:e.target.value})}
                              placeholder=${t(`cron.form.toPlaceholder`)}
                            />
                            <div class="cron-help">${t(`cron.form.toHelp`)}</div>
                          </label>
                        `:n}
                    ${I===`webhook`?T(r.fieldErrors.deliveryTo,_(`deliveryTo`)):n}
                  `}
            </div>
          </section>

          <details class="cron-advanced">
            <summary class="cron-advanced__summary">${t(`cron.form.advanced`)}</summary>
            <div class="cron-help">${t(`cron.form.advancedHelp`)}</div>
            <div class="form-grid cron-form-grid">
              <label class="field checkbox cron-checkbox">
                <input
                  type="checkbox"
                  .checked=${r.form.deleteAfterRun}
                  @change=${e=>r.onFormChange({deleteAfterRun:e.target.checked})}
                />
                <span class="field-checkbox__label">${t(`cron.form.deleteAfterRun`)}</span>
                <div class="cron-help">${t(`cron.form.deleteAfterRunHelp`)}</div>
              </label>
              <label class="field checkbox cron-checkbox">
                <input
                  type="checkbox"
                  .checked=${r.form.clearAgent}
                  @change=${e=>r.onFormChange({clearAgent:e.target.checked})}
                />
                <span class="field-checkbox__label">${t(`cron.form.clearAgentOverride`)}</span>
                <div class="cron-help">${t(`cron.form.clearAgentHelp`)}</div>
              </label>
              <label class="field cron-span-2">
                ${S(`Session key`)}
                <input
                  id="cron-session-key"
                  .value=${r.form.sessionKey}
                  @input=${e=>r.onFormChange({sessionKey:e.target.value})}
                  placeholder="agent:main:main"
                />
                <div class="cron-help">Optional routing key for job delivery and wake routing.</div>
              </label>
              ${s?e`
                    <label class="field checkbox cron-checkbox cron-span-2">
                      <input
                        type="checkbox"
                        .checked=${r.form.scheduleExact}
                        @change=${e=>r.onFormChange({scheduleExact:e.target.checked})}
                      />
                      <span class="field-checkbox__label">${t(`cron.form.exactTiming`)}</span>
                      <div class="cron-help">${t(`cron.form.exactTimingHelp`)}</div>
                    </label>
                    <div class="cron-stagger-group cron-span-2">
                      <label class="field">
                        ${S(t(`cron.form.staggerWindow`))}
                        <input
                          id="cron-stagger-amount"
                          .value=${r.form.staggerAmount}
                          ?disabled=${r.form.scheduleExact}
                          aria-invalid=${r.fieldErrors.staggerAmount?`true`:`false`}
                          aria-describedby=${c(r.fieldErrors.staggerAmount?_(`staggerAmount`):void 0)}
                          @input=${e=>r.onFormChange({staggerAmount:e.target.value})}
                          placeholder=${t(`cron.form.staggerPlaceholder`)}
                        />
                        ${T(r.fieldErrors.staggerAmount,_(`staggerAmount`))}
                      </label>
                      <label class="field">
                        <span>${t(`cron.form.staggerUnit`)}</span>
                        <select
                          .value=${r.form.staggerUnit}
                          ?disabled=${r.form.scheduleExact}
                          @change=${e=>r.onFormChange({staggerUnit:e.target.value})}
                        >
                          <option value="seconds">${t(`cron.form.seconds`)}</option>
                          <option value="minutes">${t(`cron.form.minutes`)}</option>
                        </select>
                      </label>
                    </div>
                  `:n}
              ${a?e`
                    <label class="field cron-span-2">
                      ${S(`Account ID`)}
                      <input
                        id="cron-delivery-account-id"
                        .value=${r.form.deliveryAccountId}
                        list="cron-delivery-account-suggestions"
                        ?disabled=${I!==`announce`}
                        @input=${e=>r.onFormChange({deliveryAccountId:e.target.value})}
                        placeholder="default"
                      />
                      <div class="cron-help">
                        Optional channel account ID for multi-account setups.
                      </div>
                    </label>
                    <label class="field checkbox cron-checkbox cron-span-2">
                      <input
                        type="checkbox"
                        .checked=${r.form.payloadLightContext}
                        @change=${e=>r.onFormChange({payloadLightContext:e.target.checked})}
                      />
                      <span class="field-checkbox__label">Light context</span>
                      <div class="cron-help">
                        Use lightweight bootstrap context for this agent job.
                      </div>
                    </label>
                    <label class="field">
                      ${S(t(`cron.form.model`))}
                      <input
                        id="cron-payload-model"
                        .value=${r.form.payloadModel}
                        list="cron-model-suggestions"
                        @input=${e=>r.onFormChange({payloadModel:e.target.value})}
                        placeholder=${t(`cron.form.modelPlaceholder`)}
                      />
                      <div class="cron-help">${t(`cron.form.modelHelp`)}</div>
                    </label>
                    <label class="field">
                      ${S(t(`cron.form.thinking`))}
                      <input
                        id="cron-payload-thinking"
                        .value=${r.form.payloadThinking}
                        list="cron-thinking-suggestions"
                        @input=${e=>r.onFormChange({payloadThinking:e.target.value})}
                        placeholder=${t(`cron.form.thinkingPlaceholder`)}
                      />
                      <div class="cron-help">${t(`cron.form.thinkingHelp`)}</div>
                    </label>
                  `:n}
              ${a?e`
                    <label class="field cron-span-2">
                      ${S(`Failure alerts`)}
                      <select
                        .value=${r.form.failureAlertMode}
                        @change=${e=>r.onFormChange({failureAlertMode:e.target.value})}
                      >
                        <option value="inherit">Inherit global setting</option>
                        <option value="disabled">Disable for this job</option>
                        <option value="custom">Custom per-job settings</option>
                      </select>
                      <div class="cron-help">
                        Control when this job sends repeated-failure alerts.
                      </div>
                    </label>
                    ${r.form.failureAlertMode===`custom`?e`
                          <label class="field">
                            ${S(`Alert after`)}
                            <input
                              id="cron-failure-alert-after"
                              .value=${r.form.failureAlertAfter}
                              aria-invalid=${r.fieldErrors.failureAlertAfter?`true`:`false`}
                              aria-describedby=${c(r.fieldErrors.failureAlertAfter?_(`failureAlertAfter`):void 0)}
                              @input=${e=>r.onFormChange({failureAlertAfter:e.target.value})}
                              placeholder="2"
                            />
                            <div class="cron-help">Consecutive errors before alerting.</div>
                            ${T(r.fieldErrors.failureAlertAfter,_(`failureAlertAfter`))}
                          </label>
                          <label class="field">
                            ${S(`Cooldown (seconds)`)}
                            <input
                              id="cron-failure-alert-cooldown-seconds"
                              .value=${r.form.failureAlertCooldownSeconds}
                              aria-invalid=${r.fieldErrors.failureAlertCooldownSeconds?`true`:`false`}
                              aria-describedby=${c(r.fieldErrors.failureAlertCooldownSeconds?_(`failureAlertCooldownSeconds`):void 0)}
                              @input=${e=>r.onFormChange({failureAlertCooldownSeconds:e.target.value})}
                              placeholder="3600"
                            />
                            <div class="cron-help">Minimum seconds between alerts.</div>
                            ${T(r.fieldErrors.failureAlertCooldownSeconds,_(`failureAlertCooldownSeconds`))}
                          </label>
                          <label class="field">
                            ${S(`Alert channel`)}
                            <select
                              .value=${r.form.failureAlertChannel||`last`}
                              @change=${e=>r.onFormChange({failureAlertChannel:e.target.value})}
                            >
                              ${v.map(t=>e`<option value=${t}>
                                    ${m(r,t)}
                                  </option>`)}
                            </select>
                          </label>
                          <label class="field">
                            ${S(`Alert to`)}
                            <input
                              .value=${r.form.failureAlertTo}
                              list="cron-delivery-to-suggestions"
                              @input=${e=>r.onFormChange({failureAlertTo:e.target.value})}
                              placeholder="+1555... or chat id"
                            />
                            <div class="cron-help">
                              Optional recipient override for failure alerts.
                            </div>
                          </label>
                          <label class="field">
                            ${S(`Alert mode`)}
                            <select
                              .value=${r.form.failureAlertDeliveryMode||`announce`}
                              @change=${e=>r.onFormChange({failureAlertDeliveryMode:e.target.value})}
                            >
                              <option value="announce">Announce (via channel)</option>
                              <option value="webhook">Webhook (HTTP POST)</option>
                            </select>
                          </label>
                          <label class="field">
                            ${S(`Alert account ID`)}
                            <input
                              .value=${r.form.failureAlertAccountId}
                              @input=${e=>r.onFormChange({failureAlertAccountId:e.target.value})}
                              placeholder="Account ID for multi-account setups"
                            />
                          </label>
                        `:n}
                  `:n}
              ${I===`none`?n:e`
                    <label class="field checkbox cron-checkbox cron-span-2">
                      <input
                        type="checkbox"
                        .checked=${r.form.deliveryBestEffort}
                        @change=${e=>r.onFormChange({deliveryBestEffort:e.target.checked})}
                      />
                      <span class="field-checkbox__label"
                        >${t(`cron.form.bestEffortDelivery`)}</span
                      >
                      <div class="cron-help">${t(`cron.form.bestEffortHelp`)}</div>
                    </label>
                  `}
            </div>
          </details>
        </div>
        ${R?e`
              <div class="cron-form-status" role="status" aria-live="polite">
                <div class="cron-form-status__title">${t(`cron.form.cantAddYet`)}</div>
                <div class="cron-help">${t(`cron.form.fillRequired`)}</div>
                <ul class="cron-form-status__list">
                  ${L.map(n=>e`
                      <li>
                        <button
                          type="button"
                          class="cron-form-status__link"
                          @click=${()=>x(n.inputId)}
                        >
                          ${n.label}: ${t(n.message)}
                        </button>
                      </li>
                    `)}
                </ul>
              </div>
            `:n}
        <div class="row cron-form-actions">
          <button
            class="btn primary"
            ?disabled=${r.busy||!r.canSubmit}
            @click=${r.onAdd}
          >
            ${r.busy?t(`cron.form.saving`):t(i?`cron.form.saveChanges`:`cron.form.addJob`)}
          </button>
          ${B?e`<div class="cron-submit-reason" aria-live="polite">${B}</div>`:n}
          ${i?e`
                <button class="btn" ?disabled=${r.busy} @click=${r.onCancelEdit}>
                  ${t(`cron.form.cancel`)}
                </button>
              `:n}
        </div>
      </section>
    </section>

    ${g(`cron-agent-suggestions`,r.agentSuggestions)}
    ${g(`cron-model-suggestions`,r.modelSuggestions)}
    ${g(`cron-thinking-suggestions`,r.thinkingSuggestions)}
    ${g(`cron-tz-suggestions`,r.timezoneSuggestions)}
    ${g(`cron-delivery-to-suggestions`,r.deliveryToSuggestions)}
    ${g(`cron-delivery-account-suggestions`,r.accountSuggestions)}
  `}function w(n){let r=n.form;return r.scheduleKind===`at`?e`
      <label class="field cron-span-2" style="margin-top: 12px;">
        ${S(t(`cron.form.runAt`),!0)}
        <input
          id="cron-schedule-at"
          type="datetime-local"
          .value=${r.scheduleAt}
          aria-invalid=${n.fieldErrors.scheduleAt?`true`:`false`}
          aria-describedby=${c(n.fieldErrors.scheduleAt?_(`scheduleAt`):void 0)}
          @input=${e=>n.onFormChange({scheduleAt:e.target.value})}
        />
        ${T(n.fieldErrors.scheduleAt,_(`scheduleAt`))}
      </label>
    `:r.scheduleKind===`every`?e`
      <div class="form-grid cron-form-grid" style="margin-top: 12px;">
        <label class="field">
          ${S(t(`cron.form.every`),!0)}
          <input
            id="cron-every-amount"
            .value=${r.everyAmount}
            aria-invalid=${n.fieldErrors.everyAmount?`true`:`false`}
            aria-describedby=${c(n.fieldErrors.everyAmount?_(`everyAmount`):void 0)}
            @input=${e=>n.onFormChange({everyAmount:e.target.value})}
            placeholder=${t(`cron.form.everyAmountPlaceholder`)}
          />
          ${T(n.fieldErrors.everyAmount,_(`everyAmount`))}
        </label>
        <label class="field">
          <span>${t(`cron.form.unit`)}</span>
          <select
            .value=${r.everyUnit}
            @change=${e=>n.onFormChange({everyUnit:e.target.value})}
          >
            <option value="minutes">${t(`cron.form.minutes`)}</option>
            <option value="hours">${t(`cron.form.hours`)}</option>
            <option value="days">${t(`cron.form.days`)}</option>
          </select>
        </label>
      </div>
    `:e`
    <div class="form-grid cron-form-grid" style="margin-top: 12px;">
      <label class="field">
        ${S(t(`cron.form.expression`),!0)}
        <input
          id="cron-cron-expr"
          .value=${r.cronExpr}
          aria-invalid=${n.fieldErrors.cronExpr?`true`:`false`}
          aria-describedby=${c(n.fieldErrors.cronExpr?_(`cronExpr`):void 0)}
          @input=${e=>n.onFormChange({cronExpr:e.target.value})}
          placeholder=${t(`cron.form.expressionPlaceholder`)}
        />
        ${T(n.fieldErrors.cronExpr,_(`cronExpr`))}
      </label>
      <label class="field">
        <span>${t(`cron.form.timezoneOptional`)}</span>
        <input
          .value=${r.cronTz}
          list="cron-tz-suggestions"
          @input=${e=>n.onFormChange({cronTz:e.target.value})}
          placeholder=${t(`cron.form.timezonePlaceholder`)}
        />
        <div class="cron-help">${t(`cron.form.timezoneHelp`)}</div>
      </label>
      <div class="cron-help cron-span-2">${t(`cron.form.jitterHelp`)}</div>
    </div>
  `}function T(r,i){return r?e`<div id=${c(i)} class="cron-help cron-error">${t(r)}</div>`:n}function E(r,i){let a=`list-item list-item-clickable cron-job${i.runsJobId===r.id?` list-item-selected`:``}`,o=e=>{i.onLoadRuns(r.id),e()};return e`
    <div class=${a} @click=${()=>i.onLoadRuns(r.id)}>
      <div class="list-main">
        <div class="list-title">${r.name}</div>
        <div class="list-sub">${s(r)}</div>
        ${D(r)}
        ${r.agentId?e`<div class="muted cron-job-agent">
              ${t(`cron.jobDetail.agent`)}: ${r.agentId}
            </div>`:n}
      </div>
      <div class="list-meta">${A(r)}</div>
      <div class="cron-job-footer">
        <div class="chip-row cron-job-chips">
          <span class=${`chip ${r.enabled?`chip-ok`:`chip-danger`}`}>
            ${r.enabled?t(`cron.jobList.enabled`):t(`cron.jobList.disabled`)}
          </span>
          <span class="chip">${r.sessionTarget}</span>
          <span class="chip">${r.wakeMode}</span>
        </div>
        <div class="row cron-job-actions">
          <button
            class="btn"
            ?disabled=${i.busy}
            @click=${e=>{e.stopPropagation(),o(()=>i.onEdit(r))}}
          >
            ${t(`cron.jobList.edit`)}
          </button>
          <button
            class="btn"
            ?disabled=${i.busy}
            @click=${e=>{e.stopPropagation(),o(()=>i.onClone(r))}}
          >
            ${t(`cron.jobList.clone`)}
          </button>
          <button
            class="btn"
            ?disabled=${i.busy}
            @click=${e=>{e.stopPropagation(),o(()=>i.onToggle(r,!r.enabled))}}
          >
            ${r.enabled?t(`cron.jobList.disable`):t(`cron.jobList.enable`)}
          </button>
          <button
            class="btn"
            ?disabled=${i.busy}
            @click=${e=>{e.stopPropagation(),o(()=>i.onRun(r,`force`))}}
          >
            ${t(`cron.jobList.run`)}
          </button>
          <button
            class="btn"
            ?disabled=${i.busy}
            @click=${e=>{e.stopPropagation(),o(()=>i.onRun(r,`due`))}}
          >
            Run if due
          </button>
          <button
            class="btn"
            ?disabled=${i.busy}
            @click=${e=>{e.stopPropagation(),i.onLoadRuns(r.id)}}
          >
            ${t(`cron.jobList.history`)}
          </button>
          <button
            class="btn danger"
            ?disabled=${i.busy}
            @click=${e=>{e.stopPropagation(),o(()=>i.onRemove(r))}}
          >
            ${t(`cron.jobList.remove`)}
          </button>
        </div>
      </div>
    </div>
  `}function D(r){if(r.payload.kind===`systemEvent`)return e`<div class="cron-job-detail">
      <span class="cron-job-detail-label">${t(`cron.jobDetail.system`)}</span>
      <span class="muted cron-job-detail-value">${r.payload.text}</span>
    </div>`;let i=r.delivery,a=i?.mode===`webhook`?i.to?` (${i.to})`:``:i?.channel||i?.to?` (${i.channel??`last`}${i.to?` -> ${i.to}`:``})`:``;return e`
    <div class="cron-job-detail">
      <span class="cron-job-detail-label">${t(`cron.jobDetail.prompt`)}</span>
      <span class="muted cron-job-detail-value">${r.payload.message}</span>
    </div>
    ${i?e`<div class="cron-job-detail">
          <span class="cron-job-detail-label">${t(`cron.jobDetail.delivery`)}</span>
          <span class="muted cron-job-detail-value">${i.mode}${a}</span>
        </div>`:n}
  `}function O(e){return typeof e!=`number`||!Number.isFinite(e)?t(`common.na`):i(e)}function k(e,n=Date.now()){let r=i(e);return t(e>n?`cron.runEntry.next`:`cron.runEntry.due`,{rel:r})}function A(n){let i=n.state?.lastStatus,a=i===`ok`?`cron-job-status-ok`:i===`error`?`cron-job-status-error`:i===`skipped`?`cron-job-status-skipped`:`cron-job-status-na`,o=t(i===`ok`?`cron.runs.runStatusOk`:i===`error`?`cron.runs.runStatusError`:i===`skipped`?`cron.runs.runStatusSkipped`:`common.na`),s=n.state?.nextRunAtMs,c=n.state?.lastRunAtMs;return e`
    <div class="cron-job-state">
      <div class="cron-job-state-row">
        <span class="cron-job-state-key">${t(`cron.jobState.status`)}</span>
        <span class=${`cron-job-status-pill ${a}`}>${o}</span>
      </div>
      <div class="cron-job-state-row">
        <span class="cron-job-state-key">${t(`cron.jobState.next`)}</span>
        <span class="cron-job-state-value" title=${r(s)}>
          ${O(s)}
        </span>
      </div>
      <div class="cron-job-state-row">
        <span class="cron-job-state-key">${t(`cron.jobState.last`)}</span>
        <span class="cron-job-state-value" title=${r(c)}>
          ${O(c)}
        </span>
      </div>
    </div>
  `}function j(e){switch(e){case`ok`:return t(`cron.runs.runStatusOk`);case`error`:return t(`cron.runs.runStatusError`);case`skipped`:return t(`cron.runs.runStatusSkipped`);default:return t(`cron.runs.runStatusUnknown`)}}function M(e){switch(e){case`delivered`:return t(`cron.runs.deliveryDelivered`);case`not-delivered`:return t(`cron.runs.deliveryNotDelivered`);case`not-requested`:return t(`cron.runs.deliveryNotRequested`);case`unknown`:return t(`cron.runs.deliveryUnknown`);default:return t(`cron.runs.deliveryUnknown`)}}function N(i,o,s){let c=typeof i.sessionKey==`string`&&i.sessionKey.trim().length>0?`${a(`chat`,o)}?session=${encodeURIComponent(i.sessionKey)}`:null,l=j(i.status??`unknown`),u=M(i.deliveryStatus??`not-requested`),d=i.usage,f=d&&typeof d.total_tokens==`number`?`${d.total_tokens} tokens`:d&&typeof d.input_tokens==`number`&&typeof d.output_tokens==`number`?`${d.input_tokens} in / ${d.output_tokens} out`:null;return e`
    <div class="list-item cron-run-entry">
      <div class="list-main cron-run-entry__main">
        <div class="list-title cron-run-entry__title">
          ${i.jobName??i.jobId}
          <span class="muted"> · ${l}</span>
        </div>
        <div class="list-sub cron-run-entry__summary">
          ${i.summary??i.error??t(`cron.runEntry.noSummary`)}
        </div>
        <div class="chip-row" style="margin-top: 6px;">
          <span class="chip">${u}</span>
          ${i.model?e`<span class="chip">${i.model}</span>`:n}
          ${i.provider?e`<span class="chip">${i.provider}</span>`:n}
          ${f?e`<span class="chip">${f}</span>`:n}
        </div>
      </div>
      <div class="list-meta cron-run-entry__meta">
        <div>${r(i.ts)}</div>
        ${typeof i.runAtMs==`number`?e`<div class="muted">${t(`cron.runEntry.runAt`)} ${r(i.runAtMs)}</div>`:n}
        <div class="muted">${i.durationMs??0}ms</div>
        ${typeof i.nextRunAtMs==`number`?e`<div class="muted">${k(i.nextRunAtMs)}</div>`:n}
        ${c?e`<div>
              <a
                class="session-link"
                href=${c}
                @click=${e=>{e.defaultPrevented||e.button!==0||e.metaKey||e.ctrlKey||e.shiftKey||e.altKey||s&&i.sessionKey&&(e.preventDefault(),s(i.sessionKey))}}
                >${t(`cron.runEntry.openRunChat`)}</a
              >
            </div>`:n}
        ${i.error?e`<div class="muted">${i.error}</div>`:n}
        ${i.deliveryError?e`<div class="muted">${i.deliveryError}</div>`:n}
      </div>
    </div>
  `}export{C as renderCron};
//# sourceMappingURL=cron-DOfxNlPj.js.map