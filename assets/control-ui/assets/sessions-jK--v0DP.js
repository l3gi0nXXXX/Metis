import{f as e,r as t,u as n}from"./i18n-CV7rUnW0.js";import{l as r}from"./format-EHph2kGh.js";import{M as i,k as a,s as o}from"./index-DWX0XMYb.js";var s=[``,`off`,`minimal`,`low`,`medium`,`high`,`xhigh`],c=[``,`off`,`on`],l=[{value:``,label:`inherit`},{value:`off`,label:`off (explicit)`},{value:`on`,label:`on`},{value:`full`,label:`full`}],u=[{value:``,label:`inherit`},{value:`on`,label:`on`},{value:`off`,label:`off`}],d=[``,`off`,`on`,`stream`],f=[10,25,50,100];function p(e){if(!e)return``;let t=e.trim().toLowerCase();return t===`z.ai`||t===`z-ai`?`zai`:t}function m(e){return p(e)===`zai`}function h(e){return m(e)?c:s}function g(e,t){return!t||e.includes(t)?[...e]:[...e,t]}function _(e,t){return!t||e.some(e=>e.value===t)?[...e]:[...e,{value:t,label:`${t} (custom)`}]}function v(e,t){return!t||!e||e===`off`?e:`on`}function y(e,t){return e?t&&e===`on`?`low`:e:null}function b(e,t){let n=t.trim().toLowerCase();return n?e.filter(e=>{let t=(e.key??``).toLowerCase(),r=(e.label??``).toLowerCase(),i=(e.kind??``).toLowerCase(),a=(e.displayName??``).toLowerCase();return t.includes(n)||r.includes(n)||i.includes(n)||a.includes(n)}):e}function x(e,t,n){let r=n===`asc`?1:-1;return[...e].toSorted((e,n)=>{let i=0;switch(t){case`key`:i=(e.key??``).localeCompare(n.key??``);break;case`kind`:i=(e.kind??``).localeCompare(n.kind??``);break;case`updated`:i=(e.updatedAt??0)-(n.updatedAt??0);break;case`tokens`:i=(e.totalTokens??e.inputTokens??e.outputTokens??0)-(n.totalTokens??n.inputTokens??n.outputTokens??0);break}return i*r})}function S(e,t,n){let r=t*n;return e.slice(r,r+n)}function C(r){let i=x(b(r.result?.sessions??[],r.searchQuery),r.sortColumn,r.sortDir),o=i.length,s=Math.max(1,Math.ceil(o/r.pageSize)),c=Math.min(r.page,s-1),l=S(i,c,r.pageSize),u=(t,n,i=``)=>{let o=r.sortColumn===t,s=o&&r.sortDir===`asc`?`desc`:`asc`;return e`
      <th
        class=${i}
        data-sortable
        data-sort-dir=${o?r.sortDir:``}
        @click=${()=>r.onSortChange(t,o?s:`desc`)}
      >
        ${n}
        <span class="data-table-sort-icon">${a.arrowUpDown}</span>
      </th>
    `};return e`
    <section class="card">
      <div class="row" style="justify-content: space-between; margin-bottom: 12px;">
        <div>
          <div class="card-title">Sessions</div>
          <div class="card-sub">
            ${r.result?`Store: ${r.result.path}`:`Active session keys and per-session overrides.`}
          </div>
        </div>
        <button class="btn" ?disabled=${r.loading} @click=${r.onRefresh}>
          ${r.loading?t(`common.loading`):t(`common.refresh`)}
        </button>
      </div>

      <div class="filters" style="margin-bottom: 12px;">
        <label class="field-inline">
          <span>Active</span>
          <input
            style="width: 72px;"
            placeholder="min"
            .value=${r.activeMinutes}
            @input=${e=>r.onFiltersChange({activeMinutes:e.target.value,limit:r.limit,includeGlobal:r.includeGlobal,includeUnknown:r.includeUnknown})}
          />
        </label>
        <label class="field-inline">
          <span>Limit</span>
          <input
            style="width: 64px;"
            .value=${r.limit}
            @input=${e=>r.onFiltersChange({activeMinutes:r.activeMinutes,limit:e.target.value,includeGlobal:r.includeGlobal,includeUnknown:r.includeUnknown})}
          />
        </label>
        <label class="field-inline checkbox">
          <input
            type="checkbox"
            .checked=${r.includeGlobal}
            @change=${e=>r.onFiltersChange({activeMinutes:r.activeMinutes,limit:r.limit,includeGlobal:e.target.checked,includeUnknown:r.includeUnknown})}
          />
          <span>Global</span>
        </label>
        <label class="field-inline checkbox">
          <input
            type="checkbox"
            .checked=${r.includeUnknown}
            @change=${e=>r.onFiltersChange({activeMinutes:r.activeMinutes,limit:r.limit,includeGlobal:r.includeGlobal,includeUnknown:e.target.checked})}
          />
          <span>Unknown</span>
        </label>
      </div>

      ${r.error?e`<div class="callout danger" style="margin-bottom: 12px;">${r.error}</div>`:n}

      <div class="data-table-wrapper">
        <div class="data-table-toolbar">
          <div class="data-table-search">
            <input
              type="text"
              placeholder="Filter by key, label, kind…"
              .value=${r.searchQuery}
              @input=${e=>r.onSearchChange(e.target.value)}
            />
          </div>
        </div>

        ${r.selectedKeys.size>0?e`
              <div class="data-table-bulk-bar">
                <span>${r.selectedKeys.size} selected</span>
                <button class="btn btn--sm" @click=${r.onDeselectAll}>
                  ${t(`common.unselect`)}
                </button>
                <button
                  class="btn btn--sm danger"
                  ?disabled=${r.loading}
                  @click=${r.onDeleteSelected}
                >
                  ${a.trash} Delete
                </button>
              </div>
            `:n}

        <div class="data-table-container">
          <table class="data-table">
            <thead>
              <tr>
                <th class="data-table-checkbox-col">
                  ${l.length>0?e`<input
                        type="checkbox"
                        .checked=${l.length>0&&l.every(e=>r.selectedKeys.has(e.key))}
                        .indeterminate=${l.some(e=>r.selectedKeys.has(e.key))&&!l.every(e=>r.selectedKeys.has(e.key))}
                        @change=${()=>{l.every(e=>r.selectedKeys.has(e.key))?r.onDeselectPage(l.map(e=>e.key)):r.onSelectPage(l.map(e=>e.key))}}
                        aria-label="Select all on page"
                      />`:n}
                </th>
                ${u(`key`,`Key`,`data-table-key-col`)}
                <th>Label</th>
                ${u(`kind`,`Kind`)} ${u(`updated`,`Updated`)}
                ${u(`tokens`,`Tokens`)}
                <th>Thinking</th>
                <th>Fast</th>
                <th>Verbose</th>
                <th>Reasoning</th>
              </tr>
            </thead>
            <tbody>
              ${l.length===0?e`
                    <tr>
                      <td
                        colspan="10"
                        style="text-align: center; padding: 48px 16px; color: var(--muted)"
                      >
                        No sessions found.
                      </td>
                    </tr>
                  `:l.map(e=>w(e,r.basePath,r.onPatch,r.selectedKeys.has(e.key),r.onToggleSelect,r.loading,r.onNavigateToChat))}
            </tbody>
          </table>
        </div>

        ${o>0?e`
              <div class="data-table-pagination">
                <div class="data-table-pagination__info">
                  ${c*r.pageSize+1}-${Math.min((c+1)*r.pageSize,o)}
                  of ${o} row${o===1?``:`s`}
                </div>
                <div class="data-table-pagination__controls">
                  <select
                    style="height: 32px; padding: 0 8px; font-size: 13px; border-radius: var(--radius-md); border: 1px solid var(--border); background: var(--card);"
                    .value=${String(r.pageSize)}
                    @change=${e=>r.onPageSizeChange(Number(e.target.value))}
                  >
                    ${f.map(t=>e`<option value=${t}>${t} per page</option>`)}
                  </select>
                  <button ?disabled=${c<=0} @click=${()=>r.onPageChange(c-1)}>
                    Previous
                  </button>
                  <button
                    ?disabled=${c>=s-1}
                    @click=${()=>r.onPageChange(c+1)}
                  >
                    Next
                  </button>
                </div>
              </div>
            `:n}
      </div>
    </section>
  `}function w(a,s,c,f,p,b,x){let S=a.updatedAt?r(a.updatedAt):t(`common.na`),C=a.thinkingLevel??``,w=m(a.modelProvider),T=v(C,w),E=g(h(a.modelProvider),T),D=a.fastMode===!0?`on`:a.fastMode===!1?`off`:``,O=_(u,D),k=a.verboseLevel??``,A=_(l,k),j=a.reasoningLevel??``,M=g(d,j),N=typeof a.displayName==`string`&&a.displayName.trim().length>0?a.displayName.trim():null,P=!!(N&&N!==a.key&&N!==(typeof a.label==`string`?a.label.trim():``)),F=a.kind!==`global`,I=F?`${i(`chat`,s)}?session=${encodeURIComponent(a.key)}`:null,L=a.kind===`direct`?`data-table-badge--direct`:a.kind===`group`?`data-table-badge--group`:a.kind===`global`?`data-table-badge--global`:`data-table-badge--unknown`;return e`
    <tr>
      <td class="data-table-checkbox-col">
        <input
          type="checkbox"
          .checked=${f}
          @change=${()=>p(a.key)}
          aria-label="Select session"
        />
      </td>
      <td class="data-table-key-col">
        <div class="mono session-key-cell">
          ${F?e`<a
                href=${I}
                class="session-link"
                @click=${e=>{e.defaultPrevented||e.button!==0||e.metaKey||e.ctrlKey||e.shiftKey||e.altKey||x&&(e.preventDefault(),x(a.key))}}
                >${a.key}</a
              >`:a.key}
          ${P?e`<span class="muted session-key-display-name">${N}</span>`:n}
        </div>
      </td>
      <td>
        <input
          .value=${a.label??``}
          ?disabled=${b}
          placeholder="(optional)"
          style="width: 100%; max-width: 140px; padding: 6px 10px; font-size: 13px; border: 1px solid var(--border); border-radius: var(--radius-sm);"
          @change=${e=>{let t=e.target.value.trim();c(a.key,{label:t||null})}}
        />
      </td>
      <td>
        <span class="data-table-badge ${L}">${a.kind}</span>
      </td>
      <td>${S}</td>
      <td>${o(a)}</td>
      <td>
        <select
          ?disabled=${b}
          style="padding: 6px 10px; font-size: 13px; border: 1px solid var(--border); border-radius: var(--radius-sm); min-width: 90px;"
          @change=${e=>{let t=e.target.value;c(a.key,{thinkingLevel:y(t,w)})}}
        >
          ${E.map(t=>e`<option value=${t} ?selected=${T===t}>
                ${t||`inherit`}
              </option>`)}
        </select>
      </td>
      <td>
        <select
          ?disabled=${b}
          style="padding: 6px 10px; font-size: 13px; border: 1px solid var(--border); border-radius: var(--radius-sm); min-width: 90px;"
          @change=${e=>{let t=e.target.value;c(a.key,{fastMode:t===``?null:t===`on`})}}
        >
          ${O.map(t=>e`<option value=${t.value} ?selected=${D===t.value}>
                ${t.label}
              </option>`)}
        </select>
      </td>
      <td>
        <select
          ?disabled=${b}
          style="padding: 6px 10px; font-size: 13px; border: 1px solid var(--border); border-radius: var(--radius-sm); min-width: 90px;"
          @change=${e=>{let t=e.target.value;c(a.key,{verboseLevel:t||null})}}
        >
          ${A.map(t=>e`<option value=${t.value} ?selected=${k===t.value}>
                ${t.label}
              </option>`)}
        </select>
      </td>
      <td>
        <select
          ?disabled=${b}
          style="padding: 6px 10px; font-size: 13px; border: 1px solid var(--border); border-radius: var(--radius-sm); min-width: 90px;"
          @change=${e=>{let t=e.target.value;c(a.key,{reasoningLevel:t||null})}}
        >
          ${M.map(t=>e`<option value=${t} ?selected=${j===t}>
                ${t||`inherit`}
              </option>`)}
        </select>
      </td>
    </tr>
  `}export{C as renderSessions};
//# sourceMappingURL=sessions-jK--v0DP.js.map