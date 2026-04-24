import{f as e,r as t,u as n}from"./i18n-CV7rUnW0.js";import{i as r}from"./index-DWX0XMYb.js";function i(i){let a=(i.status&&typeof i.status==`object`?i.status.securityAudit:null)?.summary??null,o=a?.critical??0,s=a?.warn??0,c=a?.info??0,l=o>0?`danger`:s>0?`warn`:`success`,u=o>0?`${o} critical`:s>0?`${s} warnings`:`No critical issues`;return e`
    <section class="grid">
      <div class="card">
        <div class="row" style="justify-content: space-between;">
          <div>
            <div class="card-title">Snapshots</div>
            <div class="card-sub">Status, health, and heartbeat data.</div>
          </div>
          <button class="btn" ?disabled=${i.loading} @click=${i.onRefresh}>
            ${i.loading?t(`common.refreshing`):t(`common.refresh`)}
          </button>
        </div>
        <div class="stack" style="margin-top: 12px;">
          <div>
            <div class="muted">Status</div>
            ${a?e`<div class="callout ${l}" style="margin-top: 8px;">
                  Security audit: ${u}${c>0?` · ${c} info`:``}. Run
                  <span class="mono">Metis security audit --deep</span> for details.
                </div>`:n}
            <pre class="code-block">${JSON.stringify(i.status??{},null,2)}</pre>
          </div>
          <div>
            <div class="muted">Health</div>
            <pre class="code-block">${JSON.stringify(i.health??{},null,2)}</pre>
          </div>
          <div>
            <div class="muted">Last heartbeat</div>
            <pre class="code-block">${JSON.stringify(i.heartbeat??{},null,2)}</pre>
          </div>
        </div>
      </div>

      <div class="card">
        <div class="card-title">Manual RPC</div>
        <div class="card-sub">Send a raw gateway method with JSON params.</div>
        <div class="stack" style="margin-top: 16px;">
          <label class="field">
            <span>Method</span>
            <select
              .value=${i.callMethod}
              @change=${e=>i.onCallMethodChange(e.target.value)}
            >
              ${i.callMethod?n:e` <option value="" disabled>Select a method…</option> `}
              ${i.methods.map(t=>e`<option value=${t}>${t}</option>`)}
            </select>
          </label>
          <label class="field">
            <span>Params (JSON)</span>
            <textarea
              .value=${i.callParams}
              @input=${e=>i.onCallParamsChange(e.target.value)}
              rows="6"
            ></textarea>
          </label>
        </div>
        <div class="row" style="margin-top: 12px;">
          <button class="btn primary" @click=${i.onCall}>${t(`common.call`)}</button>
        </div>
        ${i.callError?e`<div class="callout danger" style="margin-top: 12px;">${i.callError}</div>`:n}
        ${i.callResult?e`<pre class="code-block" style="margin-top: 12px;">${i.callResult}</pre>`:n}
      </div>
    </section>

    <section class="card" style="margin-top: 18px;">
      <div class="card-title">Models</div>
      <div class="card-sub">Catalog from models.list.</div>
      <pre class="code-block" style="margin-top: 12px;">
${JSON.stringify(i.models??[],null,2)}</pre
      >
    </section>

    <section class="card" style="margin-top: 18px;">
      <div class="card-title">Event Log</div>
      <div class="card-sub">Latest gateway events.</div>
      ${i.eventLog.length===0?e` <div class="muted" style="margin-top: 12px">No events yet.</div> `:e`
            <div class="list debug-event-log" style="margin-top: 12px;">
              ${i.eventLog.map(t=>e`
                  <div class="list-item debug-event-log__item">
                    <div class="list-main">
                      <div class="list-title">${t.event}</div>
                      <div class="list-sub">${new Date(t.ts).toLocaleTimeString()}</div>
                    </div>
                    <div class="list-meta debug-event-log__meta">
                      <pre class="code-block debug-event-log__payload">
${r(t.payload)}</pre
                      >
                    </div>
                  </div>
                `)}
            </div>
          `}
    </section>
  `}export{i as renderDebug};
//# sourceMappingURL=debug-COrc_dLA.js.map