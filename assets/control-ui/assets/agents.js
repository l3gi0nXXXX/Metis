import{f as e,o as t,r as n,u as r}from"./i18n.js";import{l as i}from"./format.js";import{A as a,B as o,C as s,D as c,F as l,H as u,I as d,L as f,N as p,O as m,P as h,R as g,S as ee,T as _,U as v,V as y,_ as b,a as x,b as S,d as C,f as te,g as ne,h as w,k as T,m as E,n as D,p as O,r as re,t as ie,u as ae,v as k,w as oe,x as A,y as j,z as se}from"./index.js";import{r as ce}from"./channel-config-extras.js";import{i as le,n as ue,r as de,t as fe}from"./skills-shared.js";function pe(t){let{agent:i,configForm:a,agentFilesList:o,configLoading:s,configSaving:c,configDirty:l,onConfigReload:u,onConfigSave:d,onModelChange:f,onModelFallbacksChange:p,onSelectPanel:m}=t,h=k(a,i.id),g=i.model,ee=(o&&o.agentId===i.id?o.workspace:null)||h.entry?.workspace||h.defaults?.workspace||i.workspace||`default`,_=h.entry?.model?S(h.entry?.model):h.defaults?.model?S(h.defaults?.model):S(g),v=S(h.defaults?.model??g),y=A(h.entry?.model),x=A(h.defaults?.model)||(v===`-`?null:ne(v))||(a?null:A(g)),C=y??x??null,w=j(h.entry?.model)??j(h.defaults?.model)??(a?null:j(g))??[],T=Array.isArray(h.entry?.skills)?h.entry?.skills:null,E=T?.length??null,D=!!(t.defaultId&&i.id===t.defaultId),O=!a||s||c,re=e=>{let t=w.filter((t,n)=>n!==e);p(i.id,t)};return e`
    <section class="card">
      <div class="card-title">Overview</div>
      <div class="card-sub">Workspace paths and identity metadata.</div>

      <div class="agents-overview-grid" style="margin-top: 16px;">
        <div class="agent-kv">
          <div class="label">Workspace</div>
          <div>
            <button
              type="button"
              class="workspace-link mono"
              @click=${()=>m(`files`)}
              title="Open Files tab"
            >
              ${ee}
            </button>
          </div>
        </div>
        <div class="agent-kv">
          <div class="label">Primary Model</div>
          <div class="mono">${_}</div>
        </div>
        <div class="agent-kv">
          <div class="label">Skills Filter</div>
          <div>${T?`${E} selected`:`all skills`}</div>
        </div>
      </div>

      ${l?e`
            <div class="callout warn" style="margin-top: 16px">
              You have unsaved config changes.
            </div>
          `:r}

      <div class="agent-model-select" style="margin-top: 20px;">
        <div class="label">Model Selection</div>
        <div class="agent-model-fields">
          <label class="field">
            <span>Primary model${D?` (default)`:``}</span>
            <select
              .value=${D?C??``:y??``}
              ?disabled=${O}
              @change=${e=>f(i.id,e.target.value||null)}
            >
              ${D?e` <option value="">Not set</option> `:e`
                    <option value="">
                      ${x?`Inherit default (${x})`:`Inherit default`}
                    </option>
                  `}
              ${te(a,C??void 0,t.modelCatalog)}
            </select>
          </label>
          <div class="field">
            <span>Fallbacks</span>
            <div
              class="agent-chip-input"
              @click=${e=>{let t=e.currentTarget.querySelector(`input`);t&&t.focus()}}
            >
              ${w.map((t,n)=>e`
                  <span class="chip">
                    ${t}
                    <button
                      type="button"
                      class="chip-remove"
                      ?disabled=${O}
                      @click=${()=>re(n)}
                    >
                      &times;
                    </button>
                  </span>
                `)}
              <input
                ?disabled=${O}
                placeholder=${w.length===0?`provider/model`:``}
                @keydown=${e=>{let t=e.target;if(e.key===`Enter`||e.key===`,`){e.preventDefault();let n=b(t.value);n.length>0&&(p(i.id,[...w,...n]),t.value=``)}}}
                @blur=${e=>{let t=e.target,n=b(t.value);n.length>0&&(p(i.id,[...w,...n]),t.value=``)}}
              />
            </div>
          </div>
        </div>
        <div class="agent-model-actions">
          <button
            type="button"
            class="btn btn--sm"
            ?disabled=${s}
            @click=${u}
          >
            ${n(`common.reloadConfig`)}
          </button>
          <button
            type="button"
            class="btn btn--sm primary"
            ?disabled=${c||!l}
            @click=${d}
          >
            ${c?`Saving…`:`Save`}
          </button>
        </div>
      </div>
    </section>
  `}var me=Object.defineProperty,he=(e,t,n)=>t in e?me(e,t,{enumerable:!0,configurable:!0,writable:!0,value:n}):e[t]=n,M=(e,t,n)=>he(e,typeof t==`symbol`?t:t+``,n),ge={classPrefix:`cm-`,theme:`github`,linkTarget:`_blank`,sanitize:!1,plugins:[],customRenderers:{}};function N(e){return{...ge,...e,plugins:e?.plugins??[],customRenderers:e?.customRenderers??{}}}function _e(e,t){return typeof t==`function`?t(e):e}function P(e,t){let n=N(t),r=n.classPrefix,i=e;for(let e of n.plugins)e.transformBlock&&(i=i.map(e.transformBlock));let a=`<div class="${r}preview">${i.map(e=>{for(let t of n.plugins)if(t.renderBlock){let r=t.renderBlock(e,()=>F(e,n));if(r!==null)return r}let t=n.customRenderers[e.type];return t?t(e):F(e,n)}).join(`
`)}</div>`;return a=_e(a,n.sanitize),a}async function ve(e,t){let n=N(t);for(let e of n.plugins)e.init&&await e.init();let r=P(e,t);for(let e of n.plugins)e.postProcess&&(r=await e.postProcess(r));return r}function F(e,t){let n=t.classPrefix;switch(e.type){case`paragraph`:return`<p class="${n}paragraph">${I(e.content,t)}</p>`;case`heading`:return ye(e,t);case`bulletList`:return be(e,t);case`numberedList`:return xe(e,t);case`checkList`:return Se(e,t);case`codeBlock`:return Ce(e,t);case`blockquote`:return`<blockquote class="${n}blockquote">${I(e.content,t)}</blockquote>`;case`table`:return we(e,t);case`image`:return Te(e,t);case`divider`:return`<hr class="${n}divider" />`;case`callout`:return Ee(e,t);default:return`<div class="${n}unknown">${I(e.content,t)}</div>`}}function ye(e,t){let n=t.classPrefix,r=e.props.level,i=`h${r}`;return`<${i} class="${n}heading ${n}h${r}">${I(e.content,t)}</${i}>`}function be(e,t){return`<ul class="${t.classPrefix}bullet-list">
${e.children.map(e=>`<li>${I(e.content,t)}</li>`).join(`
`)}
</ul>`}function xe(e,t){return`<ol class="${t.classPrefix}numbered-list">
${e.children.map(e=>`<li>${I(e.content,t)}</li>`).join(`
`)}
</ol>`}function Se(e,t){let n=t.classPrefix,r=e.props.checked;return`
<div class="${n}checklist-item">
  <input type="checkbox" ${r?`checked disabled`:`disabled`} />
  <span class="${r?`${n}checked`:``}">${I(e.content,t)}</span>
</div>`.trim()}function Ce(e,t){let n=t.classPrefix,r=e.content.map(e=>e.text).join(``),i=e.props.language||``,a=L(r),o=i?` language-${i}`:``;return`<pre class="${n}code-block"${i?` data-language="${i}"`:``}><code class="${n}code${o}">${a}</code></pre>`}function we(e,t){let n=t.classPrefix,{headers:r,rows:i,alignments:a}=e.props,o=e=>{let t=a?.[e];return t?` style="text-align: ${t}"`:``};return`<table class="${n}table">
${r.length>0?`<thead><tr>${r.map((e,t)=>`<th${o(t)}>${L(e)}</th>`).join(``)}</tr></thead>`:``}
<tbody>
${i.map(e=>`<tr>${e.map((e,t)=>`<td${o(t)}>${L(e)}</td>`).join(``)}</tr>`).join(`
`)}
</tbody>
</table>`}function Te(e,t){let n=t.classPrefix,{url:r,alt:i,title:a,width:o,height:s}=e.props,c=i?` alt="${L(i)}"`:` alt=""`,l=a?` title="${L(a)}"`:``,u=o?` width="${o}"`:``,d=s?` height="${s}"`:``;return`<figure class="${n}image">${`<img src="${L(r)}"${c}${l}${u}${d} />`}${i?`<figcaption>${L(i)}</figcaption>`:``}</figure>`}function Ee(e,t){let n=t.classPrefix,r=e.props.type;return`
<div class="${n}callout ${n}callout-${r}" role="alert">
  <strong class="${n}callout-title">${r}</strong>
  <div class="${n}callout-content">${I(e.content,t)}</div>
</div>`.trim()}function I(e,t){return e.map(e=>De(e,t)).join(``)}function De(e,t){let n=L(e.text),r=e.styles;if(r.code&&(n=`<code>${n}</code>`),r.highlight&&(n=`<mark>${n}</mark>`),r.strikethrough&&(n=`<del>${n}</del>`),r.underline&&(n=`<u>${n}</u>`),r.italic&&(n=`<em>${n}</em>`),r.bold&&(n=`<strong>${n}</strong>`),r.link){let e=t.linkTarget===`_blank`?` target="_blank" rel="noopener noreferrer"`:``,i=r.link.title?` title="${L(r.link.title)}"`:``;n=`<a href="${L(r.link.url)}"${i}${e}>${n}</a>`}return n}function L(e){return e.replace(/&/g,`&amp;`).replace(/</g,`&lt;`).replace(/>/g,`&gt;`).replace(/"/g,`&quot;`).replace(/'/g,`&#039;`)}function Oe(e){return[...[1,2,3,4,5,6].map(t=>({tag:`h${t}`,classes:[`${e}heading`,`${e}h${t}`]})),{tag:`p`,classes:[`${e}paragraph`]},{tag:`ul`,classes:[`${e}bullet-list`]},{tag:`ol`,classes:[`${e}numbered-list`]},{tag:`pre`,classes:[`${e}code-block`]},{tag:`blockquote`,classes:[`${e}blockquote`]},{tag:`hr`,classes:[`${e}divider`]},{tag:`table`,classes:[`${e}table`]},{tag:`figure`,classes:[`${e}image`]}]}function ke(e,t){let n=t.join(` `),r=/\bclass\s*=\s*"([^"]*)"/i,i=e.match(r);return i?e.replace(r,`class="${n} ${i[1]}"`):e.endsWith(`/>`)?e.slice(0,-2)+` class="${n}" />`:e.slice(0,-1)+` class="${n}">`}function Ae(e,t){return e.replace(/(?<!<figure[^>]*>\s*)(<img\s[^>]*\/?>)(?!\s*<\/figure>)/gi,`<figure class="${t}image">$1</figure>`)}function je(e,t){let n=t?.classPrefix??`cm-`,r=t?.wrapperClass??`${n}preview`,i=Oe(n),a=e;for(let{tag:e,classes:t}of i){let n=RegExp(`<${e}(\\s[^>]*)?>|<${e}\\s*\\/?>`,`gi`);a=a.replace(n,e=>ke(e,t))}return a=Ae(a,n),a=`<div class="${r}">${a}</div>`,typeof t?.sanitize==`function`&&(a=t.sanitize(a)),a}async function Me(e){try{return(await t(()=>import(`./preview.js`),[],import.meta.url)).parse(e)}catch{throw Error(`@create-markdown/core is required to parse markdown in <markdown-preview>. Install it, or provide pre-parsed blocks via the blocks attribute / setBlocks().`)}}M(class extends HTMLElement{constructor(){super(),M(this,`_shadow`,null),M(this,`plugins`,[]),M(this,`defaultTheme`,`github`),M(this,`styleElement`),M(this,`contentElement`);let e=this.constructor._shadowMode;e!==`none`&&(this._shadow=this.attachShadow({mode:e})),this.styleElement=document.createElement(`style`),this.renderRoot.appendChild(this.styleElement),this.contentElement=document.createElement(`div`),this.contentElement.className=`markdown-preview-content`,this.renderRoot.appendChild(this.contentElement),this.updateStyles()}static get observedAttributes(){return[`theme`,`link-target`,`async`]}get renderRoot(){return this._shadow??this}connectedCallback(){this.render()}attributeChangedCallback(e,t,n){this.render()}setPlugins(e){this.plugins=e,this.render()}setDefaultTheme(e){this.defaultTheme=e,this.render()}getMarkdown(){let e=this.getAttribute(`blocks`);if(e)try{return JSON.parse(e).map(e=>e.content.map(e=>e.text).join(``)).join(`

`)}catch{return``}return this.textContent||``}setMarkdown(e){this.textContent=e,this.render()}setBlocks(e){this.setAttribute(`blocks`,JSON.stringify(e)),this.render()}getOptions(){return{theme:this.getAttribute(`theme`)||this.defaultTheme,linkTarget:this.getAttribute(`link-target`)||`_blank`,plugins:this.plugins}}async getBlocks(){let e=this.getAttribute(`blocks`);if(e)try{return JSON.parse(e)}catch{return console.warn(`Invalid blocks JSON in markdown-preview element`),[]}return Me(this.textContent||``)}async render(){let e=await this.getBlocks(),t=this.getOptions(),n=this.hasAttribute(`async`)||this.plugins.length>0;try{let r;r=n?await ve(e,t):P(e,t),this.contentElement.innerHTML=r}catch(e){console.error(`Error rendering markdown preview:`,e),this.contentElement.innerHTML=`<div class="error">Error rendering content</div>`}}updateStyles(){let e=this.plugins.filter(e=>e.getCSS).map(e=>e.getCSS()).join(`

`),t=this._shadow?`:host { display: block; }`:`markdown-preview { display: block; }`;this.styleElement.textContent=`
${t}

.markdown-preview-content {
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Noto Sans', Helvetica, Arial, sans-serif;
  font-size: 16px;
  line-height: 1.6;
}

.error {
  color: #cf222e;
  padding: 1rem;
  background: #ffebe9;
  border-radius: 6px;
}

${e}
    `.trim()}},`_shadowMode`,`open`);function Ne(t,n,r){return e`
    <section class="card">
      <div class="card-title">Agent Context</div>
      <div class="card-sub">${n}</div>
      <div class="agents-overview-grid" style="margin-top: 16px;">
        <div class="agent-kv">
          <div class="label">Workspace</div>
          <div>
            <button
              type="button"
              class="workspace-link mono"
              @click=${()=>r(`files`)}
              title="Open Files tab"
            >
              ${t.workspace}
            </button>
          </div>
        </div>
        <div class="agent-kv">
          <div class="label">Primary Model</div>
          <div class="mono">${t.model}</div>
        </div>
        <div class="agent-kv">
          <div class="label">Identity Name</div>
          <div>${t.identityName}</div>
        </div>
        <div class="agent-kv">
          <div class="label">Identity Avatar</div>
          <div>${t.identityAvatar}</div>
        </div>
        <div class="agent-kv">
          <div class="label">Skills Filter</div>
          <div>${t.skillsLabel}</div>
        </div>
        <div class="agent-kv">
          <div class="label">Default</div>
          <div>${t.isDefault?`yes`:`no`}</div>
        </div>
      </div>
    </section>
  `}function Pe(e,t){let n=e.channelMeta?.find(e=>e.id===t);return n?.label?n.label:e.channelLabels?.[t]??t}function Fe(e){if(!e)return[];let t=new Set;for(let n of e.channelOrder??[])t.add(n);for(let n of e.channelMeta??[])t.add(n.id);for(let n of Object.keys(e.channelAccounts??{}))t.add(n);let n=[],r=e.channelOrder?.length?e.channelOrder:Array.from(t);for(let e of r)t.has(e)&&(n.push(e),t.delete(e));for(let e of t)n.push(e);return n.map(t=>({id:t,label:Pe(e,t),accounts:e.channelAccounts?.[t]??[]}))}var Ie=[`groupPolicy`,`streamMode`,`dmPolicy`];function Le(e){let t=0,n=0,r=0;for(let i of e){let e=i.probe&&typeof i.probe==`object`&&`ok`in i.probe?!!i.probe.ok:!1;(i.connected===!0||i.running===!0||e)&&(t+=1),i.configured&&(n+=1),i.enabled&&(r+=1)}return{total:e.length,connected:t,configured:n,enabled:r}}function Re(t){let a=Fe(t.snapshot),o=t.lastSuccess?i(t.lastSuccess):`never`;return e`
    <section class="grid grid-cols-2">
      ${Ne(t.context,`Workspace, identity, and model configuration.`,t.onSelectPanel)}
      <section class="card">
        <div class="row" style="justify-content: space-between;">
          <div>
            <div class="card-title">Channels</div>
            <div class="card-sub">Gateway-wide channel status snapshot.</div>
          </div>
          <button class="btn btn--sm" ?disabled=${t.loading} @click=${t.onRefresh}>
            ${t.loading?n(`common.refreshing`):n(`common.refresh`)}
          </button>
        </div>
        <div class="muted" style="margin-top: 8px;">Last refresh: ${o}</div>
        ${t.error?e`<div class="callout danger" style="margin-top: 12px;">${t.error}</div>`:r}
        ${t.snapshot?r:e`
              <div class="callout info" style="margin-top: 12px">
                Load channels to see live status.
              </div>
            `}
        ${a.length===0?e` <div class="muted" style="margin-top: 16px">No channels found.</div> `:e`
              <div class="list" style="margin-top: 16px;">
                ${a.map(n=>{let i=Le(n.accounts),a=i.total?`${i.connected}/${i.total} connected`:`no accounts`,o=i.configured?`${i.configured} configured`:`not configured`,s=i.total?`${i.enabled} enabled`:`disabled`,c=ce({configForm:t.configForm,channelId:n.id,fields:Ie});return e`
                    <div class="list-item">
                      <div class="list-main">
                        <div class="list-title">${n.label}</div>
                        <div class="list-sub mono">${n.id}</div>
                      </div>
                      <div class="list-meta">
                        <div>${a}</div>
                        <div>${o}</div>
                        <div>${s}</div>
                        ${i.configured===0?e`
                              <div>
                                <a
                                  href="https://docs.metis.ai/channels"
                                  target="_blank"
                                  rel="noopener"
                                  style="color: var(--accent); font-size: 12px"
                                  >Setup guide</a
                                >
                              </div>
                            `:r}
                        ${c.length>0?c.map(t=>e`<div>${t.label}: ${t.value}</div>`):r}
                      </div>
                    </div>
                  `})}
              </div>
            `}
      </section>
    </section>
  `}function ze(t){let i=t.jobs.filter(e=>e.agentId===t.agentId);return e`
    <section class="grid grid-cols-2">
      ${Ne(t.context,`Workspace and scheduling targets.`,t.onSelectPanel)}
      <section class="card">
        <div class="row" style="justify-content: space-between;">
          <div>
            <div class="card-title">Scheduler</div>
            <div class="card-sub">Gateway cron status.</div>
          </div>
          <button class="btn btn--sm" ?disabled=${t.loading} @click=${t.onRefresh}>
            ${t.loading?n(`common.refreshing`):n(`common.refresh`)}
          </button>
        </div>
        <div class="stat-grid" style="margin-top: 16px;">
          <div class="stat">
            <div class="stat-label">${n(`common.enabled`)}</div>
            <div class="stat-value">
              ${t.status?t.status.enabled?n(`common.yes`):n(`common.no`):n(`common.na`)}
            </div>
          </div>
          <div class="stat">
            <div class="stat-label">Jobs</div>
            <div class="stat-value">${t.status?.jobs??n(`common.na`)}</div>
          </div>
          <div class="stat">
            <div class="stat-label">Next wake</div>
            <div class="stat-value">${x(t.status?.nextWakeAtMs??null)}</div>
          </div>
        </div>
        ${t.error?e`<div class="callout danger" style="margin-top: 12px;">${t.error}</div>`:r}
      </section>
    </section>
    <section class="card">
      <div class="card-title">Agent Cron Jobs</div>
      <div class="card-sub">Scheduled jobs targeting this agent.</div>
      ${i.length===0?e` <div class="muted" style="margin-top: 16px">No jobs assigned.</div> `:e`
            <div class="list" style="margin-top: 16px;">
              ${i.map(n=>e`
                  <div class="list-item">
                    <div class="list-main">
                      <div class="list-title">${n.name}</div>
                      ${n.description?e`<div class="list-sub">${n.description}</div>`:r}
                      <div class="chip-row" style="margin-top: 6px;">
                        <span class="chip">${D(n)}</span>
                        <span class="chip ${n.enabled?`chip-ok`:`chip-warn`}">
                          ${n.enabled?`enabled`:`disabled`}
                        </span>
                        <span class="chip">${n.sessionTarget}</span>
                      </div>
                    </div>
                    <div class="list-meta">
                      <div class="mono">${re(n)}</div>
                      <div class="muted">${ie(n)}</div>
                      <button
                        class="btn btn--sm"
                        style="margin-top: 6px;"
                        ?disabled=${!n.enabled}
                        @click=${()=>t.onRunNow(n.id)}
                      >
                        Run Now
                      </button>
                    </div>
                  </div>
                `)}
            </div>
          `}
    </section>
  `}function Be(t){let i=t.agentFilesList?.agentId===t.agentId?t.agentFilesList:null,o=i?.files??[],s=t.agentFileActive??null,l=s?o.find(e=>e.name===s)??null:null,u=s?t.agentFileContents[s]??``:``,d=s?t.agentFileDrafts[s]??u:``,f=s?d!==u:!1;return e`
    <section class="card">
      <div class="row" style="justify-content: space-between;">
        <div>
          <div class="card-title">Core Files</div>
          <div class="card-sub">Bootstrap persona, identity, and tool guidance.</div>
        </div>
        <button
          class="btn btn--sm"
          ?disabled=${t.agentFilesLoading}
          @click=${()=>t.onLoadFiles(t.agentId)}
        >
          ${t.agentFilesLoading?n(`common.loading`):n(`common.refresh`)}
        </button>
      </div>
      ${i?e`<div class="muted mono" style="margin-top: 8px;">
            Workspace: <span>${i.workspace}</span>
          </div>`:r}
      ${t.agentFilesError?e`<div class="callout danger" style="margin-top: 12px;">
            ${t.agentFilesError}
          </div>`:r}
      ${i?o.length===0?e` <div class="muted" style="margin-top: 16px">No files found.</div> `:e`
              <div class="agent-tabs" style="margin-top: 14px;">
                ${o.map(n=>{let i=s===n.name,a=n.name.replace(/\.md$/i,``);return e`
                    <button
                      class="agent-tab ${i?`active`:``} ${n.missing?`agent-tab--missing`:``}"
                      @click=${()=>t.onSelectFile(n.name)}
                    >
                      ${a}${n.missing?e` <span class="agent-tab-badge">missing</span> `:r}
                    </button>
                  `})}
              </div>
              ${l?e`
                    <div class="agent-file-header" style="margin-top: 14px;">
                      <div>
                        <div class="agent-file-sub mono">${l.path}</div>
                      </div>
                      <div class="agent-file-actions">
                        <button
                          class="btn btn--sm"
                          title="Preview rendered markdown"
                          @click=${e=>{let t=e.currentTarget.closest(`.card`)?.querySelector(`dialog`);t&&t.showModal()}}
                        >
                          ${T.eye} Preview
                        </button>
                        <button
                          class="btn btn--sm"
                          ?disabled=${!f}
                          @click=${()=>t.onFileReset(l.name)}
                        >
                          Reset
                        </button>
                        <button
                          class="btn btn--sm primary"
                          ?disabled=${t.agentFileSaving||!f}
                          @click=${()=>t.onFileSave(l.name)}
                        >
                          ${t.agentFileSaving?`Saving…`:`Save`}
                        </button>
                      </div>
                    </div>
                    ${l.missing?e`
                          <div class="callout info" style="margin-top: 10px">
                            This file is missing. Saving will create it in the agent workspace.
                          </div>
                        `:r}
                    <label class="field agent-file-field" style="margin-top: 12px;">
                      <span>Content</span>
                      <textarea
                        class="agent-file-textarea"
                        .value=${d}
                        @input=${e=>t.onFileDraftChange(l.name,e.target.value)}
                      ></textarea>
                    </label>
                    <dialog
                      class="md-preview-dialog"
                      @click=${e=>{let t=e.currentTarget;e.target===t&&t.close()}}
                      @close=${e=>{e.currentTarget.querySelector(`.md-preview-dialog__panel`)?.classList.remove(`fullscreen`)}}
                    >
                      <div class="md-preview-dialog__panel">
                        <div class="md-preview-dialog__header">
                          <div class="md-preview-dialog__title mono">${l.name}</div>
                          <div class="md-preview-dialog__actions">
                            <button
                              class="btn btn--sm md-preview-expand-btn"
                              title="Toggle fullscreen"
                              @click=${e=>{let t=e.currentTarget,n=t.closest(`.md-preview-dialog__panel`);if(!n)return;let r=n.classList.toggle(`fullscreen`);t.classList.toggle(`is-fullscreen`,r)}}
                            >
                              <span class="when-normal">${T.maximize} Expand</span
                              ><span class="when-fullscreen">${T.minimize} Collapse</span>
                            </button>
                            <button
                              class="btn btn--sm"
                              title="Edit file"
                              @click=${e=>{e.currentTarget.closest(`dialog`)?.close(),document.querySelector(`.agent-file-textarea`)?.focus()}}
                            >
                              ${T.edit} Editor
                            </button>
                            <button
                              class="btn btn--sm"
                              @click=${e=>{e.currentTarget.closest(`dialog`)?.close()}}
                            >
                              ${T.x} Close
                            </button>
                          </div>
                        </div>
                        <div class="md-preview-dialog__body">
                          ${a(je(c.parse(d,{gfm:!0,breaks:!0}),{sanitize:e=>m.sanitize(e)}))}
                        </div>
                      </div>
                    </dialog>
                  `:e` <div class="muted" style="margin-top: 16px">Select a file to edit.</div> `}
            `:e`
            <div class="callout info" style="margin-top: 12px">
              Load the agent workspace files to edit core instructions.
            </div>
          `}
    </section>
  `}function Ve(t,n){let i=n.source??t.source,a=n.pluginId??t.pluginId,o=[];return i===`plugin`&&a?o.push(`plugin:${a}`):i===`core`&&o.push(`core`),n.optional&&o.push(`optional`),o.length===0?r:e`
    <div style="display: flex; gap: 6px; flex-wrap: wrap; margin-top: 6px;">
      ${o.map(t=>e`<span class="agent-pill">${t}</span>`)}
    </div>
  `}function He(e){return e.source===`plugin`?e.pluginId?n(`agentTools.connectedSource`,{id:e.pluginId}):n(`agentTools.connected`):e.source===`channel`?e.channelId?n(`agentTools.channelSource`,{id:e.channelId}):n(`agentTools.channel`):n(`agentTools.builtIn`)}function Ue(t){let i=k(t.configForm,t.agentId),a=i.entry?.tools??{},o=i.globalTools??{},c=a.profile??o.profile??`full`,l=s(t.toolsCatalogResult),u=oe(t.toolsCatalogResult),d=a.profile?`agent override`:o.profile?`global default`:`default`,f=Array.isArray(a.allow)&&a.allow.length>0,p=Array.isArray(o.allow)&&o.allow.length>0,m=!!t.configForm&&!t.configLoading&&!t.configSaving&&!f&&!(t.toolsCatalogLoading&&!t.toolsCatalogResult&&!t.toolsCatalogError),h=f?[]:Array.isArray(a.alsoAllow)?a.alsoAllow:[],g=f?[]:Array.isArray(a.deny)?a.deny:[],v=f?{allow:a.allow??[],deny:a.deny??[]}:ee(c)??void 0,y=u.flatMap(e=>e.tools.map(e=>e.id)),b=e=>{let t=O(e,v),n=E(e,h),r=E(e,g);return{allowed:(t||n)&&!r,baseAllowed:t,denied:r}},x=y.filter(e=>b(e).allowed).length,S=(e,n)=>{let r=new Set(h.map(e=>_(e)).filter(e=>e.length>0)),i=new Set(g.map(e=>_(e)).filter(e=>e.length>0)),a=b(e).baseAllowed,o=_(e);n?(i.delete(o),a||r.add(o)):(r.delete(o),i.add(o)),t.onOverridesChange(t.agentId,[...r],[...i])},C=e=>{let n=new Set(h.map(e=>_(e)).filter(e=>e.length>0)),r=new Set(g.map(e=>_(e)).filter(e=>e.length>0));for(let t of y){let i=b(t).baseAllowed,a=_(t);e?(r.delete(a),i||n.add(a)):(n.delete(a),r.add(a))}t.onOverridesChange(t.agentId,[...n],[...r])};return e`
    <section class="card">
      <div class="row" style="justify-content: space-between; flex-wrap: wrap;">
        <div style="min-width: 0;">
          <div class="card-title">Tool Access</div>
          <div class="card-sub">
            Profile + per-tool overrides for this agent.
            <span class="mono">${x}/${y.length}</span> enabled.
          </div>
        </div>
        <div class="row" style="gap: 8px; flex-wrap: wrap;">
          <button class="btn btn--sm" ?disabled=${!m} @click=${()=>C(!0)}>
            Enable All
          </button>
          <button class="btn btn--sm" ?disabled=${!m} @click=${()=>C(!1)}>
            Disable All
          </button>
          <button
            class="btn btn--sm"
            ?disabled=${t.configLoading}
            @click=${t.onConfigReload}
          >
            ${n(`common.reloadConfig`)}
          </button>
          <button
            class="btn btn--sm primary"
            ?disabled=${t.configSaving||!t.configDirty}
            @click=${t.onConfigSave}
          >
            ${t.configSaving?`Saving…`:`Save`}
          </button>
        </div>
      </div>

      ${t.configForm?r:e`
            <div class="callout info" style="margin-top: 12px">
              Load the gateway config to adjust tool profiles.
            </div>
          `}
      ${f?e`
            <div class="callout info" style="margin-top: 12px">
              This agent is using an explicit allowlist in config. Tool overrides are managed in the
              Config tab.
            </div>
          `:r}
      ${p?e`
            <div class="callout info" style="margin-top: 12px">
              Global tools.allow is set. Agent overrides cannot enable tools that are globally
              blocked.
            </div>
          `:r}
      ${t.toolsCatalogLoading&&!t.toolsCatalogResult&&!t.toolsCatalogError?e`
            <div class="callout info" style="margin-top: 12px">Loading runtime tool catalog…</div>
          `:r}
      ${t.toolsCatalogError?e`
            <div class="callout info" style="margin-top: 12px">
              Could not load runtime tool catalog. Showing built-in fallback list instead.
            </div>
          `:r}

      <div class="agent-tools-meta" style="margin-top: 16px;">
        <div class="agent-kv">
          <div class="label">Profile</div>
          <div class="mono">${c}</div>
        </div>
        <div class="agent-kv">
          <div class="label">Source</div>
          <div>${d}</div>
        </div>
        ${t.configDirty?e`
              <div class="agent-kv">
                <div class="label">Status</div>
                <div class="mono">unsaved</div>
              </div>
            `:r}
      </div>

      <div style="margin-top: 18px;">
        <div class="label">Available Right Now</div>
        <div class="card-sub">
          What this agent can use in the current chat session.
          <span class="mono">${t.runtimeSessionKey||`no session`}</span>
        </div>
        ${t.runtimeSessionMatchesSelectedAgent?t.toolsEffectiveLoading&&!t.toolsEffectiveResult&&!t.toolsEffectiveError?e`
                <div class="callout info" style="margin-top: 12px">Loading available tools…</div>
              `:t.toolsEffectiveError?e`
                  <div class="callout info" style="margin-top: 12px">
                    Could not load available tools for this session.
                  </div>
                `:(t.toolsEffectiveResult?.groups?.length??0)===0?e`
                    <div class="callout info" style="margin-top: 12px">
                      No tools are available for this session right now.
                    </div>
                  `:e`
                    <div class="agent-tools-grid" style="margin-top: 16px;">
                      ${t.toolsEffectiveResult?.groups.map(t=>e`
                          <div class="agent-tools-section">
                            <div class="agent-tools-header">${t.label}</div>
                            <div class="agent-tools-list">
                              ${t.tools.map(t=>e`
                                  <div class="agent-tool-row">
                                    <div>
                                      <div class="agent-tool-title">${t.label}</div>
                                      <div class="agent-tool-sub">${t.description}</div>
                                      <div
                                        style="display: flex; gap: 6px; flex-wrap: wrap; margin-top: 6px;"
                                      >
                                        <span class="agent-pill"
                                          >${He(t)}</span
                                        >
                                      </div>
                                    </div>
                                  </div>
                                `)}
                            </div>
                          </div>
                        `)}
                    </div>
                  `:e`
              <div class="callout info" style="margin-top: 12px">
                Switch chat to this agent to view its live runtime tools.
              </div>
            `}
      </div>

      <div class="agent-tools-presets" style="margin-top: 16px;">
        <div class="label">Quick Presets</div>
        <div class="agent-tools-buttons">
          ${l.map(n=>e`
              <button
                class="btn btn--sm ${c===n.id?`active`:``}"
                ?disabled=${!m}
                @click=${()=>t.onProfileChange(t.agentId,n.id,!0)}
              >
                ${n.label}
              </button>
            `)}
          <button
            class="btn btn--sm"
            ?disabled=${!m}
            @click=${()=>t.onProfileChange(t.agentId,null,!1)}
          >
            Inherit
          </button>
        </div>
      </div>

      <div class="agent-tools-grid" style="margin-top: 20px;">
        ${u.map(t=>e`
            <div class="agent-tools-section">
              <div class="agent-tools-header">
                ${t.label}
                ${t.source===`plugin`&&t.pluginId?e`<span class="agent-pill" style="margin-left: 8px;"
                      >plugin:${t.pluginId}</span
                    >`:r}
              </div>
              <div class="agent-tools-list">
                ${t.tools.map(n=>{let{allowed:r}=b(n.id);return e`
                    <div class="agent-tool-row">
                      <div>
                        <div class="agent-tool-title mono">${n.label}</div>
                        <div class="agent-tool-sub">${n.description}</div>
                        ${Ve(t,n)}
                      </div>
                      <label class="cfg-toggle">
                        <input
                          type="checkbox"
                          .checked=${r}
                          ?disabled=${!m}
                          @change=${e=>S(n.id,e.target.checked)}
                        />
                        <span class="cfg-toggle__track"></span>
                      </label>
                    </div>
                  `})}
              </div>
            </div>
          `)}
      </div>
    </section>
  `}function We(t){let i=!!t.configForm&&!t.configLoading&&!t.configSaving,a=k(t.configForm,t.agentId),o=Array.isArray(a.entry?.skills)?a.entry?.skills:void 0,s=new Set((o??[]).map(e=>e.trim()).filter(Boolean)),c=o!==void 0,l=!!(t.report&&t.activeAgentId===t.agentId),u=l?t.report?.skills??[]:[],d=t.filter.trim().toLowerCase(),f=d?u.filter(e=>[e.name,e.description,e.source].join(` `).toLowerCase().includes(d)):u,p=le(f),m=c?u.filter(e=>s.has(e.name)).length:u.length,h=u.length;return e`
    <section class="card">
      <div class="row" style="justify-content: space-between; flex-wrap: wrap;">
        <div style="min-width: 0;">
          <div class="card-title">Skills</div>
          <div class="card-sub">
            Per-agent skill allowlist and workspace skills.
            ${h>0?e`<span class="mono">${m}/${h}</span>`:r}
          </div>
        </div>
        <div class="row" style="gap: 8px; flex-wrap: wrap;">
          <div
            class="row"
            style="gap: 4px; border: 1px solid var(--border); border-radius: var(--radius-md); padding: 2px;"
          >
            <button
              class="btn btn--sm"
              ?disabled=${!i}
              @click=${()=>t.onClear(t.agentId)}
            >
              Enable All
            </button>
            <button
              class="btn btn--sm"
              ?disabled=${!i}
              @click=${()=>t.onDisableAll(t.agentId)}
            >
              Disable All
            </button>
            <button
              class="btn btn--sm"
              ?disabled=${!i||!c}
              @click=${()=>t.onClear(t.agentId)}
              title="Remove per-agent allowlist and use all skills"
            >
              Reset
            </button>
          </div>
          <button
            class="btn btn--sm"
            ?disabled=${t.configLoading}
            @click=${t.onConfigReload}
          >
            ${n(`common.reloadConfig`)}
          </button>
          <button class="btn btn--sm" ?disabled=${t.loading} @click=${t.onRefresh}>
            ${t.loading?n(`common.loading`):n(`common.refresh`)}
          </button>
          <button
            class="btn btn--sm primary"
            ?disabled=${t.configSaving||!t.configDirty}
            @click=${t.onConfigSave}
          >
            ${t.configSaving?`Saving…`:`Save`}
          </button>
        </div>
      </div>

      ${t.configForm?r:e`
            <div class="callout info" style="margin-top: 12px">
              Load the gateway config to set per-agent skills.
            </div>
          `}
      ${c?e`
            <div class="callout info" style="margin-top: 12px">
              This agent uses a custom skill allowlist.
            </div>
          `:e`
            <div class="callout info" style="margin-top: 12px">
              All skills are enabled. Disabling any skill will create a per-agent allowlist.
            </div>
          `}
      ${!l&&!t.loading?e`
            <div class="callout info" style="margin-top: 12px">
              Load skills for this agent to view workspace-specific entries.
            </div>
          `:r}
      ${t.error?e`<div class="callout danger" style="margin-top: 12px;">${t.error}</div>`:r}

      <div class="filters" style="margin-top: 14px;">
        <label class="field" style="flex: 1;">
          <span>Filter</span>
          <input
            .value=${t.filter}
            @input=${e=>t.onFilterChange(e.target.value)}
            placeholder="Search skills"
            autocomplete="off"
            name="agent-skills-filter"
          />
        </label>
        <div class="muted">${f.length} shown</div>
      </div>

      ${f.length===0?e` <div class="muted" style="margin-top: 16px">No skills found.</div> `:e`
            <div class="agent-skills-groups" style="margin-top: 16px;">
              ${p.map(e=>Ge(e,{agentId:t.agentId,allowSet:s,usingAllowlist:c,editable:i,onToggle:t.onToggle}))}
            </div>
          `}
    </section>
  `}function Ge(t,n){return e`
    <details class="agent-skills-group" ?open=${!(t.id===`workspace`||t.id===`built-in`)}>
      <summary class="agent-skills-header">
        <span>${t.label}</span>
        <span class="muted">${t.skills.length}</span>
      </summary>
      <div class="list skills-grid">
        ${t.skills.map(e=>Ke(e,{agentId:n.agentId,allowSet:n.allowSet,usingAllowlist:n.usingAllowlist,editable:n.editable,onToggle:n.onToggle}))}
      </div>
    </details>
  `}function Ke(t,n){let i=n.usingAllowlist?n.allowSet.has(t.name):!0,a=fe(t),o=ue(t);return e`
    <div class="list-item agent-skill-row">
      <div class="list-main">
        <div class="list-title">${t.emoji?`${t.emoji} `:``}${t.name}</div>
        <div class="list-sub">${t.description}</div>
        ${de({skill:t})}
        ${a.length>0?e`<div class="muted" style="margin-top: 6px;">Missing: ${a.join(`, `)}</div>`:r}
        ${o.length>0?e`<div class="muted" style="margin-top: 6px;">Reason: ${o.join(`, `)}</div>`:r}
      </div>
      <div class="list-meta">
        <label class="cfg-toggle">
          <input
            type="checkbox"
            .checked=${i}
            ?disabled=${!n.editable}
            @change=${e=>n.onToggle(n.agentId,t.name,e.target.checked)}
          />
          <span class="cfg-toggle__track"></span>
        </label>
      </div>
    </div>
  `}function qe(t){let n=t.list?.teams??[],r=ht(t.draft.membersJson),i=r.length>0?r:t.detail?.members??[],a=gt(t.draft.aliasesJson),o=a.length>0?a:_t(t.detail),s=vt(t.draft.broadcastJson,t.detail?.broadcast),c=t.detail?pt(t.detail):t.selectedId?t.selectedId:`New team`;return e`
    ${Je(t,i,s)}

    <section class="grid grid-cols-2">
      ${Ye(t,n)}
      ${Xe(t,c,r,i,o,s)}
    </section>

    <section class="grid grid-cols-2" style="margin-top: 16px;">
      ${nt(t,i)}
      ${rt(t,i)}
    </section>

    <section class="grid grid-cols-2" style="margin-top: 16px;">
      ${it(t,i)}
      ${ot(t)}
    </section>

    <section class="grid grid-cols-2" style="margin-top: 16px;">
      ${lt()}
      ${ut(t)}
    </section>

    <section style="margin-top: 16px;">
      ${ft(t,n,i)}
    </section>
  `}function Je(t,n,r){return e`
    <section class="card" style="margin-bottom: 16px;">
      <div class="row" style="justify-content: space-between; align-items: flex-start;">
        <div>
          <div class="card-title">Guided workflow</div>
          <div class="card-sub">Create or edit a team, then walk through members, routing, profiles, model state, and Feishu status.</div>
        </div>
        <span class="badge">Gateway RPC only</span>
      </div>
      <div class="agents-overview-grid" style="margin-top: 14px;">
        ${[{label:t.detail?`Edit team`:`Create team`,status:t.draft.id?`ready`:`needs key`},{label:`Members`,status:U(n.length,`member`)},{label:`Default`,status:B(t.draft.defaultAgentId,n)},{label:`Bindings`,status:U(H(t.draft.bindingsJson),`binding`)},{label:`Profiles`,status:t.workspace.workspace?`workspace loaded`:`choose member`},{label:`Models`,status:t.modelResult?.models?.path?`models.json loaded`:`load model`},{label:`Feishu`,status:(t.channelsSnapshot?.channelAccounts?.feishu??[]).length?`status visible`:`status missing`},{label:`Broadcast`,status:V(r)?`${W(r.members).length} selected`:`disabled`}].map(t=>e`
            <div class="agent-kv">
              <div class="label">${t.label}</div>
              <div>${t.status}</div>
            </div>
          `)}
      </div>
    </section>
  `}function Ye(t,i){return e`
    <section class="card">
      <div class="row" style="justify-content: space-between; align-items: flex-start;">
        <div>
          <div class="card-title">Agent Teams</div>
          <div class="card-sub">Manage team definitions through Gateway AgentTeam RPC.</div>
        </div>
        <div class="row" style="gap: 8px;">
          <button type="button" class="btn btn--sm" ?disabled=${t.loading} @click=${t.onRefresh}>
            ${t.loading?n(`common.refreshing`):n(`common.refresh`)}
          </button>
          <button type="button" class="btn btn--sm btn--ghost" @click=${t.onNewTeam}>
            New
          </button>
        </div>
      </div>
      ${t.error?e`<div class="callout danger" style="margin-top: 12px;">${t.error}</div>`:r}
      ${t.success?e`<div class="callout success" style="margin-top: 12px;">${t.success}</div>`:r}
      ${i.length===0?e`<div class="callout info" style="margin-top: 12px;">No teams are configured yet.</div>`:e`
            <div class="list" style="margin-top: 16px;">
              ${i.map(n=>e`
                  <button
                    type="button"
                    class="list-item"
                    style="width: 100%; text-align: left;"
                    @click=${()=>t.onSelectTeam(n.id)}
                    aria-pressed=${n.id===t.selectedId?`true`:`false`}
                  >
                    <div class="list-main">
                      <div class="list-title">${pt(n)}</div>
                      <div class="list-sub">
                        ${U(n.members?.length??0,`member`)} ·
                        ${U(n.aliases?.length??0,`alias`)} · default
                        ${B(n.defaultAgentId,n.members??[])}
                      </div>
                    </div>
                    <div class="list-meta">
                      <span class="badge">${U(n.bindings?.length??0,`binding`)}</span>
                      <span class="badge">${V(n.broadcast)?`broadcast on`:`broadcast off`}</span>
                    </div>
                  </button>
                `)}
            </div>
          `}
    </section>
  `}function Xe(t,n,r,i,a,o){return e`
    <section class="card">
      <div class="card-title">${n}</div>
      <div class="card-sub">Create teams, edit members, and keep JSON metadata available for compatibility.</div>
      ${Qe(i,a,t.draft.bindingsJson,o)}
      <div class="grid grid-cols-2" style="margin-top: 14px;">
        <label class="field">
          <span>Team key</span>
          <input
            .value=${t.draft.id}
            ?disabled=${!!t.detail}
            placeholder="content"
            @input=${e=>t.onDraftChange({id:Z(e)})}
          />
        </label>
        <label class="field">
          <span>Display name</span>
          <input
            .value=${t.draft.displayName}
            placeholder="Content Team"
            @input=${e=>t.onDraftChange({displayName:Z(e)})}
          />
        </label>
        <label class="field">
          <span>Template</span>
          <select
            .value=${t.draft.template}
            ?disabled=${!!t.detail||r.length>0}
            @change=${e=>t.onDraftChange({template:Q(e)})}
          >
            <option value="pm-writer-reviewer">PM / Writer / Reviewer</option>
            <option value="">Custom members</option>
          </select>
        </label>
        <label class="field">
          <span>Default member</span>
          <select
            .value=${t.draft.defaultAgentId}
            @change=${e=>t.onDraftChange({defaultAgentId:Q(e)})}
          >
            <option value="">First member</option>
            ${i.map(t=>e`
                <option value=${t.agentId}>${B(t.agentId,i)}</option>
              `)}
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
          @click=${()=>t.onDraftChange(l(t.draft))}
        >
          Add Member
        </button>
      </div>
      ${r.length===0?e`<div class="callout info" style="margin-top: 12px;">Use a template, or add members for a custom team.</div>`:e`
            <div class="list" style="margin-top: 12px;">
              ${r.map((e,n)=>Ze(t,e,n))}
            </div>
          `}

      ${$e(t,i)}
      ${tt(t,i,o)}

      <details style="margin-top: 14px;">
        <summary class="muted">Advanced metadata JSON</summary>
        ${z(`Aliases JSON`,t.draft.aliasesJson,e=>t.onDraftChange({aliasesJson:e}))}
        ${z(`Team bindings JSON`,t.draft.bindingsJson,e=>t.onDraftChange({bindingsJson:e}))}
        ${z(`Broadcast JSON`,t.draft.broadcastJson,e=>t.onDraftChange({broadcastJson:e}))}
      </details>

      <div class="agent-model-actions">
        <button
          type="button"
          class="btn btn--sm primary"
          ?disabled=${t.saving||!!t.detail}
          @click=${t.onCreateTeam}
        >
          ${t.saving&&!t.detail?`Creating...`:`Create Team`}
        </button>
        <button
          type="button"
          class="btn btn--sm"
          ?disabled=${t.saving||!t.detail}
          @click=${t.onUpdateTeam}
        >
          ${t.saving&&t.detail?`Saving...`:`Save Team`}
        </button>
        <button
          type="button"
          class="btn btn--sm btn--ghost"
          ?disabled=${t.saving||!t.detail}
          @click=${t.onDeleteTeam}
        >
          Delete
        </button>
      </div>
    </section>
  `}function Ze(t,n,r){return e`
    <div class="list-item">
      <div class="list-main">
        <div class="grid grid-cols-3">
          <label class="field">
            <span>Agent id</span>
            <input
              .value=${n.agentId??``}
              placeholder="content-writer"
              @input=${e=>t.onDraftChange(g(t.draft,r,{agentId:Z(e)}))}
            />
          </label>
          <label class="field">
            <span>Role</span>
            <input
              .value=${n.role??``}
              placeholder="writer"
              @input=${e=>t.onDraftChange(g(t.draft,r,{role:Z(e)}))}
            />
          </label>
          <label class="field">
            <span>Name</span>
            <input
              .value=${n.name??``}
              placeholder="Writer"
              @input=${e=>t.onDraftChange(g(t.draft,r,{name:Z(e)}))}
            />
          </label>
        </div>
      </div>
      <div class="list-meta">
        <button
          type="button"
          class="btn btn--sm btn--ghost"
          @click=${()=>t.onDraftChange(o(t.draft,r))}
        >
          Remove
        </button>
      </div>
    </div>
  `}function Qe(t,n,r,i){return e`
    <div class="agents-overview-grid" style="margin-top: 14px;">
      <div class="agent-kv">
        <div class="label">Members</div>
        <div>${U(t.length,`member`)}</div>
      </div>
      <div class="agent-kv">
        <div class="label">Aliases</div>
        <div>${U(n.length,`alias`)}</div>
      </div>
      <div class="agent-kv">
        <div class="label">Bindings</div>
        <div>${U(H(r),`binding`)}</div>
      </div>
      <div class="agent-kv">
        <div class="label">Broadcast</div>
        <div>${V(i)?`Broadcast enabled`:`Broadcast disabled`}</div>
      </div>
    </div>
  `}function $e(t,n){let r=gt(t.draft.aliasesJson);return e`
    <div class="row" style="justify-content: space-between; margin-top: 16px;">
      <div>
        <div class="list-title">Aliases</div>
        <div class="muted">Map mention text such as @writer or /agent writer to a member.</div>
      </div>
      <button
        type="button"
        class="btn btn--sm"
        @click=${()=>t.onDraftChange(h(t.draft))}
      >
        Add Alias
      </button>
    </div>
    ${r.length===0?e`<div class="callout info" style="margin-top: 12px;">No aliases are configured.</div>`:e`
          <div class="list" style="margin-top: 12px;">
            ${r.map((e,r)=>et(t,n,e,r))}
          </div>
        `}
  `}function et(t,n,r,i){return e`
    <div class="list-item">
      <div class="list-main">
        <div class="grid grid-cols-2">
          <label class="field">
            <span>Alias</span>
            <input
              .value=${r.alias??``}
              placeholder="@writer"
              @input=${e=>t.onDraftChange(f(t.draft,i,{alias:Z(e)}))}
            />
          </label>
          <label class="field">
            <span>Member</span>
            <select
              .value=${r.agentId??``}
              @change=${e=>t.onDraftChange(f(t.draft,i,{agentId:Q(e)}))}
            >
              <option value="">Choose member</option>
              ${n.map(t=>e`<option value=${t.agentId}>${B(t.agentId,n)}</option>`)}
            </select>
          </label>
        </div>
      </div>
      <div class="list-meta">
        <button
          type="button"
          class="btn btn--sm btn--ghost"
          @click=${()=>t.onDraftChange(se(t.draft,i))}
        >
          Remove
        </button>
      </div>
    </div>
  `}function tt(t,n,r){let i=V(r),a=W(r.members);return e`
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
            ?disabled=${!i||n.length===0}
            @click=${()=>t.onDraftChange(v(t.draft,n,!0))}
          >
            Select all members
          </button>
          <button
            type="button"
            class="btn btn--sm btn--ghost"
            ?disabled=${!i}
            @click=${()=>t.onDraftChange(v(t.draft,n,!1))}
          >
            Clear selected
          </button>
          <label class="row" style="gap: 8px;">
            <input
              type="checkbox"
              ?checked=${i}
              @change=${e=>t.onDraftChange(y(t.draft,$(e)))}
            />
            <span>${i?`Broadcast enabled`:`Broadcast disabled`}</span>
          </label>
        </div>
      </div>
      <div class="list" style="margin-top: 12px;">
        ${n.map(r=>{let o=a.includes(r.agentId);return e`
            <label class="list-item" style="cursor: pointer;">
              <div class="list-main">
                <div class="list-title">${B(r.agentId,n)}</div>
                <div class="list-sub">${o?`Included in broadcast`:`Not included`}</div>
              </div>
              <div class="list-meta">
                <input
                  type="checkbox"
                  ?checked=${o}
                  ?disabled=${!i}
                  @change=${e=>t.onDraftChange(u(t.draft,r.agentId,$(e)))}
                />
              </div>
            </label>
          `})}
      </div>
    </div>
  `}function nt(t,n){let i=t.bindingPreview??d(t.binding);return e`
    <section class="card">
      <div class="card-title">Binding Builder</div>
      <div class="card-sub">Build channel/account/peer/thread/group/team/role routes before applying them.</div>
      <div class="grid grid-cols-2" style="margin-top: 14px;">
        <label class="field">
          <span>Member</span>
          <select .value=${t.binding.agentId} @change=${e=>t.onBindingChange({agentId:Q(e)})}>
            <option value="">Choose member</option>
            ${n.map(t=>e`<option value=${t.agentId}>${B(t.agentId,n)}</option>`)}
          </select>
        </label>
        <label class="field">
          <span>Action</span>
          <select
            .value=${t.binding.mode}
            @change=${e=>t.onBindingChange({mode:Q(e)===`unbind`?`unbind`:`bind`})}
          >
            <option value="bind">Apply</option>
            <option value="unbind">Remove</option>
          </select>
        </label>
        <label class="field">
          <span>Payload type</span>
          <select
            .value=${t.binding.useStructuredBinding?`structured`:`simple`}
            @change=${e=>t.onBindingChange({useStructuredBinding:Q(e)===`structured`})}
          >
            <option value="simple">Simple binding</option>
            <option value="structured">JSON route binding</option>
          </select>
        </label>
        <label class="field">
          <span>Simple binding</span>
          <input
            .value=${t.binding.spec}
            placeholder="feishu:tenant-a"
            @input=${e=>t.onBindingChange({spec:Z(e)})}
          />
        </label>
        ${R(t,`Channel`,`channel`,`feishu`)}
        ${R(t,`Account`,`accountId`,`tenant-a`)}
        ${R(t,`Peer kind`,`peerKind`,`group`)}
        ${R(t,`Peer id`,`peer`,`chat:oc_123`)}
        ${R(t,`Thread`,`thread`,`thread:om_456`)}
        ${R(t,`Group`,`group`,`chat:oc_123`)}
        ${R(t,`Team`,`team`,`content`)}
        ${R(t,`Roles`,`roles`,`writer,reviewer`)}
      </div>
      <label class="field" style="margin-top: 12px;">
        <span>Comment</span>
        <input
          .value=${t.binding.comment}
          placeholder="content team route"
          @input=${e=>t.onBindingChange({comment:Z(e)})}
        />
      </label>
      <div class="agent-model-actions">
        <button type="button" class="btn btn--sm" @click=${t.onPreviewBinding}>Preview</button>
        <button
          type="button"
          class="btn btn--sm primary"
          ?disabled=${t.saving||!t.binding.agentId||!i.applyPayload}
          @click=${t.onApplyBinding}
        >
          ${t.binding.mode===`unbind`?`Remove Binding`:`Apply Binding`}
        </button>
      </div>
      <div class="callout info" style="margin-top: 12px;">
        <pre style="white-space: pre-wrap; margin: 0;">${i.lines.join(`
`)}</pre>
      </div>
      ${t.bindingResult?e`<div class="callout success" style="margin-top: 12px;">${mt(t.bindingResult)}</div>`:r}
    </section>
  `}function R(t,n,r,i){return e`
    <label class="field">
      <span>${n}</span>
      <input
        .value=${String(t.binding[r]??``)}
        placeholder=${i}
        @input=${e=>t.onBindingChange({[r]:Z(e)})}
      />
    </label>
  `}function rt(t,n){return e`
    <section class="card">
      <div class="card-title">Workspace Profiles</div>
      <div class="card-sub">Edit Gateway-supported workspace files via agents.files RPC.</div>
      ${t.workspaceError?e`<div class="callout danger" style="margin-top: 12px;">${t.workspaceError}</div>`:r}
      <div class="grid grid-cols-2" style="margin-top: 14px;">
        <label class="field">
          <span>Member</span>
          <select
            .value=${t.workspace.agentId}
            @change=${e=>t.onWorkspaceChange({agentId:Q(e)})}
          >
            <option value="">Choose member</option>
            ${n.map(t=>e`<option value=${t.agentId}>${B(t.agentId,n)}</option>`)}
          </select>
        </label>
        <label class="field">
          <span>Profile file</span>
          <select
            .value=${t.workspace.fileName}
            @change=${e=>{let n=Q(e);t.onWorkspaceChange({fileName:n}),t.onLoadWorkspaceFile(n)}}
          >
            ${p.map(t=>e`<option value=${t}>${t}</option>`)}
          </select>
        </label>
      </div>
      ${t.workspace.workspace?e`
            <div class="agent-kv" style="margin-top: 12px;">
              <div class="label">Workspace</div>
              <div class="mono">${t.workspace.workspace}</div>
            </div>
          `:r}
      ${t.workspace.path?e`
            <div class="agent-kv" style="margin-top: 12px;">
              <div class="label">File path</div>
              <div class="mono">${t.workspace.path}</div>
            </div>
          `:r}
      <label class="field agent-file-field" style="margin-top: 12px;">
        <span>${t.workspace.fileName}</span>
        <textarea
          class="agent-file-textarea"
          rows="12"
          .value=${t.workspace.draft}
          @input=${e=>t.onWorkspaceChange({draft:wt(e)})}
        ></textarea>
      </label>
      <div class="agent-model-actions">
        <button
          type="button"
          class="btn btn--sm"
          ?disabled=${t.workspaceLoading||!t.workspace.agentId}
          @click=${t.onLoadWorkspaceFiles}
        >
          ${t.workspaceLoading?`Loading...`:`List Files`}
        </button>
        <button
          type="button"
          class="btn btn--sm"
          ?disabled=${t.workspaceLoading||!t.workspace.agentId||!t.workspace.fileName}
          @click=${()=>t.onLoadWorkspaceFile(t.workspace.fileName)}
        >
          Load
        </button>
        <button
          type="button"
          class="btn btn--sm primary"
          ?disabled=${t.workspaceSaving||!t.workspace.agentId||!t.workspace.fileName}
          @click=${t.onSaveWorkspaceFile}
        >
          ${t.workspaceSaving?`Saving...`:`Save`}
        </button>
      </div>
    </section>
  `}function it(t,n){let i=t.modelResult?.models??null;return e`
    <section class="card">
      <div class="card-title">Model Editor</div>
      <div class="card-sub">Read and write per-agent models.json through Gateway.</div>
      ${t.modelError?e`<div class="callout danger" style="margin-top: 12px;">${t.modelError}</div>`:r}
      <div class="grid grid-cols-2" style="margin-top: 14px;">
        <label class="field">
          <span>Member</span>
          <select
            .value=${t.modelDraft.agentId}
            @change=${e=>t.onModelDraftChange({agentId:Q(e)})}
          >
            <option value="">Choose member</option>
            ${n.map(t=>e`<option value=${t.agentId}>${B(t.agentId,n)}</option>`)}
          </select>
        </label>
        <div class="field">
          <span>Provider status</span>
          <input
            readonly
            .value=${i?`${i.providerCount??0} providers · ${i.present?`models.json present`:`new file`}`:`Load member model`}
          />
        </div>
      </div>
      <div class="grid grid-cols-2" style="margin-top: 12px;">
        <label class="field">
          <span>Primary model ref</span>
          <input
            .value=${t.modelDraft.primaryModelRef}
            placeholder="openai:gpt-5-mini"
            @input=${e=>t.onModelDraftChange({primaryModelRef:Z(e)})}
          />
        </label>
        <label class="field">
          <span>Runtime primary model ref</span>
          <input
            .value=${t.modelDraft.runtimePrimaryModelRef}
            placeholder="openai:gpt-5-mini"
            @input=${e=>t.onModelDraftChange({runtimePrimaryModelRef:Z(e)})}
          />
        </label>
      </div>
      ${i?.path?e`
            <div class="agent-kv" style="margin-top: 12px;">
              <div class="label">models.json path</div>
              <div class="mono">${i.path}</div>
            </div>
          `:r}
      ${at(i)}
      ${z(`models.json state`,t.modelDraft.stateJson,e=>t.onModelDraftChange({stateJson:e}))}
      <div class="agent-model-actions">
        <button
          type="button"
          class="btn btn--sm"
          ?disabled=${t.modelLoading||!t.modelDraft.agentId}
          @click=${t.onLoadModel}
        >
          ${t.modelLoading?`Loading...`:`Load Model`}
        </button>
        <button
          type="button"
          class="btn btn--sm primary"
          ?disabled=${t.saving||!t.modelDraft.agentId}
          @click=${t.onSaveModel}
        >
          ${t.saving?`Saving...`:`Save Model`}
        </button>
      </div>
    </section>
  `}function at(t){if(!t)return r;let n=bt(t);return e`
    <div style="margin-top: 14px;">
      <div class="list-title">Model provider chips</div>
      <div class="card-sub">Derived from agents.models.get/set and redacted before display.</div>
      <div class="list" style="margin-top: 8px;">
        ${n.length===0?e`<div class="callout info">No provider entries are visible in this models.json response.</div>`:n.map(t=>e`
                <div class="list-item">
                  <div class="list-main">
                    <div class="list-title">${t.label}</div>
                    <div class="list-sub mono">
                      ${t.modelRef||`no default model`}${t.runtimeProvider?` · runtime ${t.runtimeProvider}`:``}
                    </div>
                  </div>
                  <div class="list-meta">
                    <span class="badge">${t.status}</span>
                  </div>
                </div>
              `)}
      </div>
      ${t.credentialSource?e`
            <div class="agent-kv" style="margin-top: 12px;">
              <div class="label">Credential source</div>
              <pre class="mono" style="white-space: pre-wrap; margin: 0;">${J(t.credentialSource)}</pre>
            </div>
          `:r}
    </div>
  `}function ot(t){let n=G(t);return e`
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
          <div class="mono">${n.defaultAccount||`not configured`}</div>
        </div>
        <div class="agent-kv">
          <div class="label">Thread Session</div>
          <div>${n.threadSession}</div>
        </div>
        <div class="agent-kv">
          <div class="label">Groups</div>
          <div>${n.groupCount}</div>
        </div>
        <div class="agent-kv">
          <div class="label">Accounts</div>
          <div>${n.accounts.length}</div>
        </div>
      </div>
      ${n.accounts.length===0?e`<div class="callout info" style="margin-top: 12px;">No Feishu accounts are visible in channels.status yet.</div>`:e`
            <div class="list" style="margin-top: 12px;">
              ${n.accounts.map(t=>e`
                  <div class="list-item">
                    <div class="list-main">
                      <div class="list-title">${t.name||t.accountId}</div>
                      <div class="list-sub mono">${t.accountId}</div>
                    </div>
                    <div class="list-meta">
                      <div>${t.configured?`configured`:`not configured`}</div>
                      <div>${t.running||t.connected?`active`:`stopped`}</div>
                    </div>
                    ${t.lastError?e`
                          <div class="list-sub" style="margin-top: 8px;">
                            Last error: ${X(t.lastError)}
                          </div>
                        `:r}
                  </div>
                `)}
            </div>
          `}
      <div class="callout info" style="margin-top: 12px;">
        Feishu commands: /feishu start, /feishu doctor, /feishu auth, /feishu info --all.
        Status shown here is read-only and redacted; secrets stay behind Gateway configuration and auth storage.
      </div>
      ${st(t)}
    </section>
  `}function st(t){let n=K(t.channelsSnapshot?.channels?.feishu),r=W(n?.capabilities),i=K(n?.auth)??K(n?.oauth),a=K(n?.doctor)??K(n?.diagnostics),o=!!i||r.some(e=>e.includes(`oauth`)),s=r.some(e=>e.includes(`oapi`)||e.includes(`openapi`)),c=!!a||r.some(e=>e.includes(`doctor`));return e`
    <div style="margin-top: 14px;">
      <div class="list-title">Capability gaps</div>
      <div class="list" style="margin-top: 8px;">
        ${[{title:`Account status`,message:(t.channelsSnapshot?.channelAccounts?.feishu??[]).length?`channels.status exposes redacted Feishu account state.`:`No Feishu accounts are visible in channels.status.`,status:(t.channelsSnapshot?.channelAccounts?.feishu??[]).length?`available`:`missing`},{title:`OAuth`,message:o?`Gateway exposes Feishu auth status.`:`OAuth missing from the current status contract.`,status:o?`available`:`missing`},{title:`OAPI tools`,message:s?`Gateway advertises Feishu OAPI tool capability.`:`Docs/wiki/calendar/task/bitable OAPI tools are not advertised here.`,status:s?`available`:`missing`},{title:`Doctor`,message:c?`Gateway exposes Feishu doctor diagnostics.`:`Doctor status is not exposed to this panel; use Gateway or /feishu doctor when available.`,status:c?`available`:`missing`}].map(t=>e`
            <div class="list-item">
              <div class="list-main">
                <div class="list-title">${t.title} ${t.status}</div>
                <div class="list-sub">${t.message}</div>
              </div>
              <div class="list-meta"><span class="badge">${t.status}</span></div>
            </div>
          `)}
      </div>
    </div>
  `}var ct=[{title:`AgentTeam Gateway RPC`,badge:`Gateway`,items:[`agents.teams.* team CRUD`,`agents.bind route bindings`,`agents.migration.dryRun read-only doctor preview`]},{title:`Workspace profile files`,badge:`profiles`,items:[...p]},{title:`Model and provider state`,badge:`models`,items:[`agents.models.get`,`agents.models.set`,`per-agent models.json`,`redacted credential source`]},{title:`Channel capabilities`,badge:`channels`,items:[`Telegram route/account/topic baseline`,`Feishu route/account/group/thread status`,`Feishu native commands: /feishu auth, /feishu doctor, /feishu info`]},{title:`Built-in tools`,badge:`tools`,items:[`feishu_media_list`,`feishu_im_user_fetch_resource`,`gateway control tools`,`memory tools`]},{title:`Built-in skills`,badge:`skills`,items:[`workspace skills`,`bundled Metis skills`,`per-agent skill allowlist`]}];function lt(){return e`
    <section class="card">
      <div class="card-title">Metis capabilities</div>
      <div class="card-sub">Metis-owned built-in tools, skills, channel capabilities, and Gateway RPC surfaces.</div>
      <div class="callout info" style="margin-top: 12px;">
        This is a read-only capability inventory. It does not expose third-party plugin install toggles or copy public branding assets.
      </div>
      <div class="list" style="margin-top: 12px;">
        ${ct.map(t=>e`
            <div class="list-item">
              <div class="list-main">
                <div class="list-title">${t.title}</div>
                <div class="list-sub">${t.items.join(` · `)}</div>
              </div>
              <div class="list-meta"><span class="badge">${t.badge}</span></div>
            </div>
          `)}
      </div>
    </section>
  `}function ut(t){let n=K(t.channelsSnapshot?.channels?.feishu),i=W(n?.capabilities),a=K(n?.auth)??K(n?.oauth),o=K(n?.doctor)??K(n?.diagnostics),s=i.some(e=>{let t=e.toLowerCase();return t.includes(`oapi`)||t.includes(`openapi`)}),c=G(t).defaultAccount||t.channelsSnapshot?.channelDefaultAccountId?.feishu||`default`;return e`
    <section class="card">
      <div class="card-title">Feishu Auth & Doctor</div>
      <div class="card-sub">Read-only Feishu status, auth, doctor, and OAPI signals from Gateway RPC.</div>
      <div class="callout info" style="margin-top: 12px;">
        UI will not write token files, app credentials, or local Feishu config. Auth start and token refresh must stay behind Gateway RPC or native Feishu commands.
      </div>
      ${t.feishuAuthError?e`<div class="callout danger" style="margin-top: 12px;">${X(t.feishuAuthError)}</div>`:r}
      <div class="agents-overview-grid" style="margin-top: 14px;">
        <div class="agent-kv">
          <div class="label">Account</div>
          <div class="mono">${c}</div>
        </div>
        <div class="agent-kv">
          <div class="label">OAuth status</div>
          <div>${a?q(a,[`status`,`tokenStatus`],`status unknown`):`Auth status RPC missing`}</div>
        </div>
        <div class="agent-kv">
          <div class="label">Doctor</div>
          <div>${o?q(o,[`status`,`state`],`available`):`Doctor status RPC missing`}</div>
        </div>
        <div class="agent-kv">
          <div class="label">OAPI</div>
          <div>${s?`OAPI capability advertised`:`OAPI status RPC missing`}</div>
        </div>
      </div>
      ${a?e`
            <div class="agent-kv" style="margin-top: 12px;">
              <div class="label">Auth summary</div>
              <div>
                ${q(a,[`accountId`],c)} ·
                ${q(a,[`scopeSummary`,`scopes`],`scope status missing`)}
                ${Y(a.error)?e`<div class="list-sub">Error: ${X(Y(a.error))}</div>`:r}
              </div>
            </div>
          `:e`
            <div class="callout warning" style="margin-top: 12px;">
              Auth status RPC missing. Needed backend field: channels.status.channels.feishu.auth or oauth with redacted accountId, status, tokenStatus, and scopeSummary.
            </div>
          `}
      ${o?e`
            <div class="agent-kv" style="margin-top: 12px;">
              <div class="label">Doctor summary</div>
              <div>${J(Ct(o,[`status`,`state`,`findings`,`lastProbeAt`,`message`]))}</div>
            </div>
          `:e`
            <div class="callout warning" style="margin-top: 12px;">
              Doctor status RPC missing. Use /feishu doctor until Gateway exposes a redacted Feishu doctor object to channels.status.
            </div>
          `}
      <div class="agent-model-actions">
        <button
          type="button"
          class="btn btn--sm primary"
          ?disabled=${t.feishuAuthLoading}
          @click=${()=>t.onStartFeishuOAuth(c)}
        >
          ${t.feishuAuthLoading?`Starting OAuth...`:`Start OAuth via Gateway`}
        </button>
      </div>
      ${t.feishuAuthResult?e`
            <div class="agent-kv" style="margin-top: 12px;">
              <div class="label">OAuth start result</div>
              <pre class="mono" style="white-space: pre-wrap; margin: 0;">${J(t.feishuAuthResult)}</pre>
            </div>
          `:r}
      ${dt(t,a,o,s)}
    </section>
  `}function dt(t,n,r,i){return e`
    <div style="margin-top: 14px;">
      <div class="list-title">Missing setup steps</div>
      <div class="list" style="margin-top: 8px;">
        ${[{label:`Confirm Feishu app credentials`,done:G(t).accounts.some(e=>e.configured===!0)},{label:`Start OAuth through Gateway RPC`,done:!!n||!!t.feishuAuthResult},{label:`Grant offline_access and OAPI scopes`,done:!!(n&&q(n,[`scopeSummary`,`scopes`],``).trim())},{label:`Run Feishu doctor`,done:!!r},{label:`Bind channel/account/peer/thread/team route`,done:!!(t.bindingPreview?.applyPayload||H(t.draft.bindingsJson)>0)},{label:`Expose OAPI capability status`,done:i}].map(t=>e`
            <div class="list-item">
              <div class="list-main">
                <div class="list-title">${t.label}</div>
              </div>
              <div class="list-meta"><span class="badge">${t.done?`done`:`needed`}</span></div>
            </div>
          `)}
      </div>
    </div>
  `}function ft(t,r,i){let a=yt(t,r,i);return e`
    <section class="card">
      <div class="row" style="justify-content: space-between;">
        <div>
          <div class="card-title">Doctor</div>
          <div class="card-sub">Local UI checks for team, binding, model, profile, and Feishu readiness.</div>
        </div>
        <button type="button" class="btn btn--sm" ?disabled=${t.loading} @click=${t.onRefresh}>
          ${t.loading?n(`common.refreshing`):n(`common.refresh`)}
        </button>
      </div>
      <div class="list" style="margin-top: 14px;">
        ${a.map(t=>e`
            <div class="list-item">
              <div class="list-main">
                <div class="list-title">${t.title}</div>
                <div class="list-sub">${t.message}</div>
              </div>
              <div class="list-meta"><span class="badge">${t.status}</span></div>
            </div>
          `)}
      </div>
    </section>
  `}function z(t,n,r){return e`
    <label class="field agent-file-field" style="margin-top: 12px;">
      <span>${t}</span>
      <textarea
        class="agent-file-textarea"
        rows="6"
        .value=${n}
        @input=${e=>r(wt(e))}
      ></textarea>
    </label>
  `}function pt(e){return e.displayName?.trim()||e.id}function B(e,t){if(!e)return`first configured member`;let n=t.find(t=>t.agentId===e);return n?`${n.name?.trim()||n.role?.trim()||n.agentId} (${n.agentId})`:e}function mt(e){let t=[e.added?.length?`${e.added.length} added`:``,e.removed?.length?`${e.removed.length} removed`:``,e.skipped?.length?`${e.skipped.length} skipped`:``,e.missing?.length?`${e.missing.length} missing`:``,e.conflicts?.length?`${e.conflicts.length} conflicts`:``].filter(Boolean);return t.length?t.join(`, `):`Gateway accepted the binding request.`}function ht(e){try{let t=JSON.parse(e||`[]`);return Array.isArray(t)?t:[]}catch{return[]}}function gt(e){try{let t=JSON.parse(e||`[]`);return Array.isArray(t)?t.map(e=>K(e)).filter(e=>!!e).map(e=>({alias:Y(e.alias),agentId:Y(e.agentId)})).filter(e=>e.alias||e.agentId):[]}catch{return[]}}function _t(e){return Array.isArray(e?.aliases)?e.aliases.map(e=>K(e)).filter(e=>!!e).map(e=>({alias:Y(e.alias),agentId:Y(e.agentId)})).filter(e=>e.alias||e.agentId):[]}function vt(e,t){try{return K(JSON.parse(e||`{}`))??t??{enabled:!1}}catch{return t??{enabled:!1}}}function V(e){return K(e)?.enabled===!0}function H(e){try{let t=JSON.parse(e||`[]`);return Array.isArray(t)?t.length:0}catch{return 0}}function U(e,t){return`${e} ${t}${e===1?``:`s`}`}function W(e){return Array.isArray(e)?e.filter(e=>typeof e==`string`).map(e=>e.trim()).filter(Boolean):[]}function G(e){let t=K(K(e.configForm?.gateway)?.feishu??e.configForm?.feishu),n=K(t?.accounts),r=K(t?.groups),i=e.channelsSnapshot?.channelAccounts?.feishu??[],a=n?Object.keys(n):[],o=Y(t?.defaultAccount)||e.channelsSnapshot?.channelDefaultAccountId?.feishu||i[0]?.accountId||a[0]||``,s=i.length>0?i:a.map(e=>({accountId:e,configured:!0}));return{defaultAccount:o,threadSession:Y(t?.threadSession)||Y(t?.groupSessionScope)||`not configured`,groupCount:r?Object.keys(r).length:0,accounts:s}}function yt(e,t,n){return[{title:`Teams list`,message:t.length>0?`${t.length} team definitions loaded.`:`No team definitions loaded.`,status:t.length>0?`ok`:`info`},{title:`Members`,message:n.length>0?`${n.length} members available for edit.`:`No members selected.`,status:n.length>0?`ok`:`warn`},{title:`Binding preview`,message:e.bindingPreview?.applyPayload?`Apply payload is ready.`:`Preview a binding before applying.`,status:e.bindingPreview?.applyPayload?`ok`:`info`},{title:`Workspace profiles`,message:e.workspace.workspace?`Workspace loaded: ${e.workspace.workspace}`:`Choose a member and list files.`,status:e.workspace.workspace?`ok`:`info`},{title:`Model profile`,message:e.modelResult?.models?.path?`models.json: ${e.modelResult.models.path}`:`Load a member model.`,status:e.modelResult?.models?.path?`ok`:`info`},{title:`Feishu accounts`,message:(e.channelsSnapshot?.channelAccounts?.feishu??[]).length>0?`Feishu account status is visible.`:`No Feishu account status in channels.status.`,status:(e.channelsSnapshot?.channelAccounts?.feishu??[]).length>0?`ok`:`info`}]}function K(e){return e&&typeof e==`object`&&!Array.isArray(e)?e:null}function bt(e){let t=K(e.state)?.providers,n=[];if(Array.isArray(t))t.forEach(e=>{let t=xt(K(e));t&&n.push(t)});else{let e=K(t);e&&Object.entries(e).forEach(([e,t])=>{let r=K(t)??{provider:e},i=xt({...r,provider:r.provider??e});i&&n.push(i)})}if(n.length===0&&e.primaryModelRef){let t=e.primaryModelRef.includes(`:`)?e.primaryModelRef.split(`:`)[0]:``;n.push({label:t||`Primary model`,provider:t,runtimeProvider:t,modelRef:e.primaryModelRef,status:`primary`})}return n}function xt(e){if(!e)return null;let t=Y(e.provider)||Y(e.id),n=Y(e.runtimeProvider)||Y(e.runtime_provider),r=Y(e.defaultModelRef)||Y(e.modelRef)||Y(e.model)||Y(e.runtimeModelRef),i=Y(e.displayName)||Y(e.name)||t||n||r;return i?{label:i,provider:t,runtimeProvider:n,modelRef:r,status:St(e.configured)}:null}function St(e){return e===!0?`configured`:e===!1?`needs credentials`:`status unknown`}function q(e,t,n){for(let n of t){let t=e[n];if(typeof t==`string`&&t.trim())return X(t.trim());if(typeof t==`number`||typeof t==`boolean`)return String(t);if(Array.isArray(t)){let e=t.map(e=>String(e).trim()).filter(Boolean).join(`, `);if(e)return X(e)}}return n}function Ct(e,t){let n={};return t.forEach(t=>{e[t]!==void 0&&(n[t]=e[t])}),n}function J(e){try{return X(JSON.stringify(e??{},null,2))}catch{return X(String(e??``))}}function Y(e){return typeof e==`string`?e:``}function X(e){return e.replace(/authorization:\s*bearer\s+[^\s,;]+/gi,`Authorization: Bearer [redacted]`).replace(/\b(access|refresh|bot|app)[_-]?token\s*[:=]\s*[^\s,;]+/gi,`$1_token=[redacted]`).replace(/(["']?(?:access|refresh|bot|app)[_-]?token["']?\s*[:=]\s*)["']?[^"',;\s]+["']?/gi,`$1[redacted]`).replace(/\b(app[_-]?secret|authorization)\s*[:=]\s*[^\s,;]+/gi,`$1=[redacted]`)}function Z(e){return e.target.value}function Q(e){return e.target.value}function wt(e){return e.target.value}function $(e){return e.target.checked}function Tt(t){let i=t.agentsList?.agents??[],a=t.agentsList?.defaultId??null,o=t.selectedAgentId??a??i[0]?.id??null,s=o?i.find(e=>e.id===o)??null:null,c=o&&t.agentSkills.agentId===o?t.agentSkills.report?.skills?.length??null:null,l=t.channels.snapshot?Object.keys(t.channels.snapshot.channelAccounts??{}).length:null,u=o?t.cron.jobs.filter(e=>e.agentId===o).length:null,d={files:t.agentFiles.list?.files?.length??null,skills:c,channels:l,cron:u||null,teams:t.agentTeams.list?.count??null};return e`
    <div class="agents-layout">
      <section class="agents-toolbar">
        <div class="agents-toolbar-row">
          <div class="agents-control-select">
            <select
              class="agents-select"
              .value=${o??``}
              ?disabled=${t.loading||i.length===0}
              @change=${e=>t.onSelectAgent(e.target.value)}
            >
              ${i.length===0?e` <option value="">No agents</option> `:i.map(t=>e`
                      <option value=${t.id} ?selected=${t.id===o}>
                        ${w(t)}${ae(t.id,a)?` (${ae(t.id,a)})`:``}
                      </option>
                    `)}
            </select>
          </div>
          <div class="agents-toolbar-actions">
            ${s?e`
                  <button
                    type="button"
                    class="btn btn--sm btn--ghost"
                    @click=${()=>void navigator.clipboard.writeText(s.id)}
                    title="Copy agent ID to clipboard"
                  >
                    Copy ID
                  </button>
                  <button
                    type="button"
                    class="btn btn--sm btn--ghost"
                    ?disabled=${!!(a&&s.id===a)}
                    @click=${()=>t.onSetDefault(s.id)}
                    title=${a&&s.id===a?`Already the default agent`:`Set as the default agent`}
                  >
                    ${a&&s.id===a?`Default`:`Set Default`}
                  </button>
                `:r}
            <button
              class="btn btn--sm agents-refresh-btn"
              ?disabled=${t.loading}
              @click=${t.onRefresh}
            >
              ${t.loading?n(`common.loading`):n(`common.refresh`)}
            </button>
          </div>
        </div>
        ${t.error?e`<div class="callout danger" style="margin-top: 8px;">${t.error}</div>`:r}
      </section>
      <section class="agents-main">
        ${Et(t.activePanel,e=>t.onSelectPanel(e),d)}
        ${!s&&t.activePanel!==`teams`?e`
              <div class="card">
                <div class="card-title">Select an agent</div>
                <div class="card-sub">Pick an agent to inspect its workspace and tools.</div>
              </div>
            `:e`
              ${t.activePanel===`overview`?pe({agent:s,basePath:t.basePath,defaultId:a,configForm:t.config.form,agentFilesList:t.agentFiles.list,agentIdentity:t.agentIdentityById[s.id]??null,agentIdentityError:t.agentIdentityError,agentIdentityLoading:t.agentIdentityLoading,configLoading:t.config.loading,configSaving:t.config.saving,configDirty:t.config.dirty,modelCatalog:t.modelCatalog,onConfigReload:t.onConfigReload,onConfigSave:t.onConfigSave,onModelChange:t.onModelChange,onModelFallbacksChange:t.onModelFallbacksChange,onSelectPanel:t.onSelectPanel}):r}
              ${t.activePanel===`files`?Be({agentId:s.id,agentFilesList:t.agentFiles.list,agentFilesLoading:t.agentFiles.loading,agentFilesError:t.agentFiles.error,agentFileActive:t.agentFiles.active,agentFileContents:t.agentFiles.contents,agentFileDrafts:t.agentFiles.drafts,agentFileSaving:t.agentFiles.saving,onLoadFiles:t.onLoadFiles,onSelectFile:t.onSelectFile,onFileDraftChange:t.onFileDraftChange,onFileReset:t.onFileReset,onFileSave:t.onFileSave}):r}
              ${t.activePanel===`tools`?Ue({agentId:s.id,configForm:t.config.form,configLoading:t.config.loading,configSaving:t.config.saving,configDirty:t.config.dirty,toolsCatalogLoading:t.toolsCatalog.loading,toolsCatalogError:t.toolsCatalog.error,toolsCatalogResult:t.toolsCatalog.result,toolsEffectiveLoading:t.toolsEffective.loading,toolsEffectiveError:t.toolsEffective.error,toolsEffectiveResult:t.toolsEffective.result,runtimeSessionKey:t.runtimeSessionKey,runtimeSessionMatchesSelectedAgent:t.runtimeSessionMatchesSelectedAgent,onProfileChange:t.onToolsProfileChange,onOverridesChange:t.onToolsOverridesChange,onConfigReload:t.onConfigReload,onConfigSave:t.onConfigSave}):r}
              ${t.activePanel===`skills`?We({agentId:s.id,report:t.agentSkills.report,loading:t.agentSkills.loading,error:t.agentSkills.error,activeAgentId:t.agentSkills.agentId,configForm:t.config.form,configLoading:t.config.loading,configSaving:t.config.saving,configDirty:t.config.dirty,filter:t.agentSkills.filter,onFilterChange:t.onSkillsFilterChange,onRefresh:t.onSkillsRefresh,onToggle:t.onAgentSkillToggle,onClear:t.onAgentSkillsClear,onDisableAll:t.onAgentSkillsDisableAll,onConfigReload:t.onConfigReload,onConfigSave:t.onConfigSave}):r}
              ${t.activePanel===`channels`?Re({context:C(s,t.config.form,t.agentFiles.list,a,t.agentIdentityById[s.id]??null),configForm:t.config.form,snapshot:t.channels.snapshot,loading:t.channels.loading,error:t.channels.error,lastSuccess:t.channels.lastSuccess,onRefresh:t.onChannelsRefresh,onSelectPanel:t.onSelectPanel}):r}
              ${t.activePanel===`cron`?ze({context:C(s,t.config.form,t.agentFiles.list,a,t.agentIdentityById[s.id]??null),agentId:s.id,jobs:t.cron.jobs,status:t.cron.status,loading:t.cron.loading,error:t.cron.error,onRefresh:t.onCronRefresh,onRunNow:t.onCronRunNow,onSelectPanel:t.onSelectPanel}):r}
              ${t.activePanel===`teams`?qe({...t.agentTeams,onRefresh:t.onTeamsRefresh,onSelectTeam:t.onSelectTeam,onNewTeam:t.onNewTeam,onDraftChange:t.onTeamDraftChange,onCreateTeam:t.onCreateTeam,onUpdateTeam:t.onUpdateTeam,onDeleteTeam:t.onDeleteTeam,onBindingChange:t.onTeamBindingChange,onPreviewBinding:t.onPreviewTeamBinding,onApplyBinding:t.onApplyTeamBinding,onModelDraftChange:t.onTeamModelDraftChange,onLoadModel:t.onLoadTeamModel,onSaveModel:t.onSaveTeamModel,onWorkspaceChange:t.onWorkspaceChange,onLoadWorkspaceFiles:t.onLoadWorkspaceFiles,onLoadWorkspaceFile:t.onLoadWorkspaceFile,onSaveWorkspaceFile:t.onSaveWorkspaceFile,onStartFeishuOAuth:t.onStartFeishuOAuth}):r}
            `}
      </section>
    </div>
  `}function Et(t,n,i){return e`
    <div class="agent-tabs">
      ${[{id:`overview`,label:`Overview`},{id:`files`,label:`Files`},{id:`tools`,label:`Tools`},{id:`skills`,label:`Skills`},{id:`channels`,label:`Channels`},{id:`cron`,label:`Cron Jobs`},{id:`teams`,label:`Teams`}].map(a=>e`
          <button
            class="agent-tab ${t===a.id?`active`:``}"
            type="button"
            @click=${()=>n(a.id)}
          >
            ${a.label}${i[a.id]==null?r:e`<span class="agent-tab-count">${i[a.id]}</span>`}
          </button>
        `)}
    </div>
  `}export{Tt as renderAgents};
//# sourceMappingURL=agents.js.map