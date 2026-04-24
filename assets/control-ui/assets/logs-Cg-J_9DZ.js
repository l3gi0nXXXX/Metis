import{f as e,r as t,u as n}from"./i18n-CV7rUnW0.js";var r=[`trace`,`debug`,`info`,`warn`,`error`,`fatal`];function i(e){if(!e)return``;let t=new Date(e);return Number.isNaN(t.getTime())?e:t.toLocaleTimeString()}function a(e,t){return t?[e.message,e.subsystem,e.raw].filter(Boolean).join(` `).toLowerCase().includes(t):!0}function o(o){let s=o.filterText.trim().toLowerCase(),c=r.some(e=>!o.levelFilters[e]),l=o.entries.filter(e=>e.level&&!o.levelFilters[e.level]?!1:a(e,s)),u=s||c?`filtered`:`visible`;return e`
    <section class="card">
      <div class="row" style="justify-content: space-between;">
        <div>
          <div class="card-title">Logs</div>
          <div class="card-sub">Gateway file logs (JSONL).</div>
        </div>
        <div class="row" style="gap: 8px;">
          <button class="btn" ?disabled=${o.loading} @click=${o.onRefresh}>
            ${o.loading?t(`common.loading`):t(`common.refresh`)}
          </button>
          <button
            class="btn"
            ?disabled=${l.length===0}
            @click=${()=>o.onExport(l.map(e=>e.raw),u)}
          >
            Export ${u}
          </button>
        </div>
      </div>

      <div class="filters" style="margin-top: 14px;">
        <label class="field" style="min-width: 220px;">
          <span>Filter</span>
          <input
            .value=${o.filterText}
            @input=${e=>o.onFilterTextChange(e.target.value)}
            placeholder="Search logs"
          />
        </label>
        <label class="field checkbox">
          <span>Auto-follow</span>
          <input
            type="checkbox"
            .checked=${o.autoFollow}
            @change=${e=>o.onToggleAutoFollow(e.target.checked)}
          />
        </label>
      </div>

      <div class="chip-row" style="margin-top: 12px;">
        ${r.map(t=>e`
            <label class="chip log-chip ${t}">
              <input
                type="checkbox"
                .checked=${o.levelFilters[t]}
                @change=${e=>o.onLevelToggle(t,e.target.checked)}
              />
              <span>${t}</span>
            </label>
          `)}
      </div>

      ${o.file?e`<div class="muted" style="margin-top: 10px;">File: ${o.file}</div>`:n}
      ${o.truncated?e`
            <div class="callout" style="margin-top: 10px">
              Log output truncated; showing latest chunk.
            </div>
          `:n}
      ${o.error?e`<div class="callout danger" style="margin-top: 10px;">${o.error}</div>`:n}

      <div class="log-stream" style="margin-top: 12px;" @scroll=${o.onScroll}>
        ${l.length===0?e` <div class="muted" style="padding: 12px">No log entries.</div> `:l.map(t=>e`
                <div class="log-row">
                  <div class="log-time mono">${i(t.time)}</div>
                  <div class="log-level ${t.level??``}">${t.level??``}</div>
                  <div class="log-subsystem mono">${t.subsystem??``}</div>
                  <div class="log-message mono">${t.message??t.raw}</div>
                </div>
              `)}
      </div>
    </section>
  `}export{o as renderLogs};
//# sourceMappingURL=logs-Cg-J_9DZ.js.map