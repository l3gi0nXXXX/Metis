import{f as e,o as t,r as n,u as r}from"./i18n.js";import{l as i}from"./format.js";import{A as a,C as o,D as s,O as c,S as l,T as u,_ as d,a as f,b as p,d as m,f as h,g,h as _,k as v,m as y,n as b,p as x,r as S,t as C,u as w,v as T,w as E,x as D,y as O}from"./index.js";import{r as k}from"./channel-config-extras.js";import{i as A,n as j,r as M,t as N}from"./skills-shared.js";function P(t){let{agent:i,configForm:a,agentFilesList:o,configLoading:s,configSaving:c,configDirty:l,onConfigReload:u,onConfigSave:f,onModelChange:m,onModelFallbacksChange:_,onSelectPanel:v}=t,y=T(a,i.id),b=i.model,x=(o&&o.agentId===i.id?o.workspace:null)||y.entry?.workspace||y.defaults?.workspace||i.workspace||`default`,S=y.entry?.model?p(y.entry?.model):y.defaults?.model?p(y.defaults?.model):p(b),C=p(y.defaults?.model??b),w=D(y.entry?.model),E=D(y.defaults?.model)||(C===`-`?null:g(C))||(a?null:D(b)),k=w??E??null,A=O(y.entry?.model)??O(y.defaults?.model)??(a?null:O(b))??[],j=Array.isArray(y.entry?.skills)?y.entry?.skills:null,M=j?.length??null,N=!!(t.defaultId&&i.id===t.defaultId),P=!a||s||c,F=e=>{let t=A.filter((t,n)=>n!==e);_(i.id,t)};return e`
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
              @click=${()=>v(`files`)}
              title="Open Files tab"
            >
              ${x}
            </button>
          </div>
        </div>
        <div class="agent-kv">
          <div class="label">Primary Model</div>
          <div class="mono">${S}</div>
        </div>
        <div class="agent-kv">
          <div class="label">Skills Filter</div>
          <div>${j?`${M} selected`:`all skills`}</div>
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
            <span>Primary model${N?` (default)`:``}</span>
            <select
              .value=${N?k??``:w??``}
              ?disabled=${P}
              @change=${e=>m(i.id,e.target.value||null)}
            >
              ${N?e` <option value="">Not set</option> `:e`
                    <option value="">
                      ${E?`Inherit default (${E})`:`Inherit default`}
                    </option>
                  `}
              ${h(a,k??void 0,t.modelCatalog)}
            </select>
          </label>
          <div class="field">
            <span>Fallbacks</span>
            <div
              class="agent-chip-input"
              @click=${e=>{let t=e.currentTarget.querySelector(`input`);t&&t.focus()}}
            >
              ${A.map((t,n)=>e`
                  <span class="chip">
                    ${t}
                    <button
                      type="button"
                      class="chip-remove"
                      ?disabled=${P}
                      @click=${()=>F(n)}
                    >
                      &times;
                    </button>
                  </span>
                `)}
              <input
                ?disabled=${P}
                placeholder=${A.length===0?`provider/model`:``}
                @keydown=${e=>{let t=e.target;if(e.key===`Enter`||e.key===`,`){e.preventDefault();let n=d(t.value);n.length>0&&(_(i.id,[...A,...n]),t.value=``)}}}
                @blur=${e=>{let t=e.target,n=d(t.value);n.length>0&&(_(i.id,[...A,...n]),t.value=``)}}
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
            @click=${f}
          >
            ${c?`Saving…`:`Save`}
          </button>
        </div>
      </div>
    </section>
  `}var F=Object.defineProperty,ee=(e,t,n)=>t in e?F(e,t,{enumerable:!0,configurable:!0,writable:!0,value:n}):e[t]=n,I=(e,t,n)=>ee(e,typeof t==`symbol`?t:t+``,n),L={classPrefix:`cm-`,theme:`github`,linkTarget:`_blank`,sanitize:!1,plugins:[],customRenderers:{}};function R(e){return{...L,...e,plugins:e?.plugins??[],customRenderers:e?.customRenderers??{}}}function z(e,t){return typeof t==`function`?t(e):e}function B(e,t){let n=R(t),r=n.classPrefix,i=e;for(let e of n.plugins)e.transformBlock&&(i=i.map(e.transformBlock));let a=`<div class="${r}preview">${i.map(e=>{for(let t of n.plugins)if(t.renderBlock){let r=t.renderBlock(e,()=>V(e,n));if(r!==null)return r}let t=n.customRenderers[e.type];return t?t(e):V(e,n)}).join(`
`)}</div>`;return a=z(a,n.sanitize),a}async function te(e,t){let n=R(t);for(let e of n.plugins)e.init&&await e.init();let r=B(e,t);for(let e of n.plugins)e.postProcess&&(r=await e.postProcess(r));return r}function V(e,t){let n=t.classPrefix;switch(e.type){case`paragraph`:return`<p class="${n}paragraph">${K(e.content,t)}</p>`;case`heading`:return ne(e,t);case`bulletList`:return re(e,t);case`numberedList`:return ie(e,t);case`checkList`:return ae(e,t);case`codeBlock`:return H(e,t);case`blockquote`:return`<blockquote class="${n}blockquote">${K(e.content,t)}</blockquote>`;case`table`:return U(e,t);case`image`:return W(e,t);case`divider`:return`<hr class="${n}divider" />`;case`callout`:return G(e,t);default:return`<div class="${n}unknown">${K(e.content,t)}</div>`}}function ne(e,t){let n=t.classPrefix,r=e.props.level,i=`h${r}`;return`<${i} class="${n}heading ${n}h${r}">${K(e.content,t)}</${i}>`}function re(e,t){return`<ul class="${t.classPrefix}bullet-list">
${e.children.map(e=>`<li>${K(e.content,t)}</li>`).join(`
`)}
</ul>`}function ie(e,t){return`<ol class="${t.classPrefix}numbered-list">
${e.children.map(e=>`<li>${K(e.content,t)}</li>`).join(`
`)}
</ol>`}function ae(e,t){let n=t.classPrefix,r=e.props.checked;return`
<div class="${n}checklist-item">
  <input type="checkbox" ${r?`checked disabled`:`disabled`} />
  <span class="${r?`${n}checked`:``}">${K(e.content,t)}</span>
</div>`.trim()}function H(e,t){let n=t.classPrefix,r=e.content.map(e=>e.text).join(``),i=e.props.language||``,a=J(r),o=i?` language-${i}`:``;return`<pre class="${n}code-block"${i?` data-language="${i}"`:``}><code class="${n}code${o}">${a}</code></pre>`}function U(e,t){let n=t.classPrefix,{headers:r,rows:i,alignments:a}=e.props,o=e=>{let t=a?.[e];return t?` style="text-align: ${t}"`:``};return`<table class="${n}table">
${r.length>0?`<thead><tr>${r.map((e,t)=>`<th${o(t)}>${J(e)}</th>`).join(``)}</tr></thead>`:``}
<tbody>
${i.map(e=>`<tr>${e.map((e,t)=>`<td${o(t)}>${J(e)}</td>`).join(``)}</tr>`).join(`
`)}
</tbody>
</table>`}function W(e,t){let n=t.classPrefix,{url:r,alt:i,title:a,width:o,height:s}=e.props,c=i?` alt="${J(i)}"`:` alt=""`,l=a?` title="${J(a)}"`:``,u=o?` width="${o}"`:``,d=s?` height="${s}"`:``;return`<figure class="${n}image">${`<img src="${J(r)}"${c}${l}${u}${d} />`}${i?`<figcaption>${J(i)}</figcaption>`:``}</figure>`}function G(e,t){let n=t.classPrefix,r=e.props.type;return`
<div class="${n}callout ${n}callout-${r}" role="alert">
  <strong class="${n}callout-title">${r}</strong>
  <div class="${n}callout-content">${K(e.content,t)}</div>
</div>`.trim()}function K(e,t){return e.map(e=>q(e,t)).join(``)}function q(e,t){let n=J(e.text),r=e.styles;if(r.code&&(n=`<code>${n}</code>`),r.highlight&&(n=`<mark>${n}</mark>`),r.strikethrough&&(n=`<del>${n}</del>`),r.underline&&(n=`<u>${n}</u>`),r.italic&&(n=`<em>${n}</em>`),r.bold&&(n=`<strong>${n}</strong>`),r.link){let e=t.linkTarget===`_blank`?` target="_blank" rel="noopener noreferrer"`:``,i=r.link.title?` title="${J(r.link.title)}"`:``;n=`<a href="${J(r.link.url)}"${i}${e}>${n}</a>`}return n}function J(e){return e.replace(/&/g,`&amp;`).replace(/</g,`&lt;`).replace(/>/g,`&gt;`).replace(/"/g,`&quot;`).replace(/'/g,`&#039;`)}function oe(e){return[...[1,2,3,4,5,6].map(t=>({tag:`h${t}`,classes:[`${e}heading`,`${e}h${t}`]})),{tag:`p`,classes:[`${e}paragraph`]},{tag:`ul`,classes:[`${e}bullet-list`]},{tag:`ol`,classes:[`${e}numbered-list`]},{tag:`pre`,classes:[`${e}code-block`]},{tag:`blockquote`,classes:[`${e}blockquote`]},{tag:`hr`,classes:[`${e}divider`]},{tag:`table`,classes:[`${e}table`]},{tag:`figure`,classes:[`${e}image`]}]}function se(e,t){let n=t.join(` `),r=/\bclass\s*=\s*"([^"]*)"/i,i=e.match(r);return i?e.replace(r,`class="${n} ${i[1]}"`):e.endsWith(`/>`)?e.slice(0,-2)+` class="${n}" />`:e.slice(0,-1)+` class="${n}">`}function ce(e,t){return e.replace(/(?<!<figure[^>]*>\s*)(<img\s[^>]*\/?>)(?!\s*<\/figure>)/gi,`<figure class="${t}image">$1</figure>`)}function le(e,t){let n=t?.classPrefix??`cm-`,r=t?.wrapperClass??`${n}preview`,i=oe(n),a=e;for(let{tag:e,classes:t}of i){let n=RegExp(`<${e}(\\s[^>]*)?>|<${e}\\s*\\/?>`,`gi`);a=a.replace(n,e=>se(e,t))}return a=ce(a,n),a=`<div class="${r}">${a}</div>`,typeof t?.sanitize==`function`&&(a=t.sanitize(a)),a}async function ue(e){try{return(await t(()=>import(`./preview.js`),[],import.meta.url)).parse(e)}catch{throw Error(`@create-markdown/core is required to parse markdown in <markdown-preview>. Install it, or provide pre-parsed blocks via the blocks attribute / setBlocks().`)}}I(class extends HTMLElement{constructor(){super(),I(this,`_shadow`,null),I(this,`plugins`,[]),I(this,`defaultTheme`,`github`),I(this,`styleElement`),I(this,`contentElement`);let e=this.constructor._shadowMode;e!==`none`&&(this._shadow=this.attachShadow({mode:e})),this.styleElement=document.createElement(`style`),this.renderRoot.appendChild(this.styleElement),this.contentElement=document.createElement(`div`),this.contentElement.className=`markdown-preview-content`,this.renderRoot.appendChild(this.contentElement),this.updateStyles()}static get observedAttributes(){return[`theme`,`link-target`,`async`]}get renderRoot(){return this._shadow??this}connectedCallback(){this.render()}attributeChangedCallback(e,t,n){this.render()}setPlugins(e){this.plugins=e,this.render()}setDefaultTheme(e){this.defaultTheme=e,this.render()}getMarkdown(){let e=this.getAttribute(`blocks`);if(e)try{return JSON.parse(e).map(e=>e.content.map(e=>e.text).join(``)).join(`

`)}catch{return``}return this.textContent||``}setMarkdown(e){this.textContent=e,this.render()}setBlocks(e){this.setAttribute(`blocks`,JSON.stringify(e)),this.render()}getOptions(){return{theme:this.getAttribute(`theme`)||this.defaultTheme,linkTarget:this.getAttribute(`link-target`)||`_blank`,plugins:this.plugins}}async getBlocks(){let e=this.getAttribute(`blocks`);if(e)try{return JSON.parse(e)}catch{return console.warn(`Invalid blocks JSON in markdown-preview element`),[]}return ue(this.textContent||``)}async render(){let e=await this.getBlocks(),t=this.getOptions(),n=this.hasAttribute(`async`)||this.plugins.length>0;try{let r;r=n?await te(e,t):B(e,t),this.contentElement.innerHTML=r}catch(e){console.error(`Error rendering markdown preview:`,e),this.contentElement.innerHTML=`<div class="error">Error rendering content</div>`}}updateStyles(){let e=this.plugins.filter(e=>e.getCSS).map(e=>e.getCSS()).join(`

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
    `.trim()}},`_shadowMode`,`open`);function Y(t,n,r){return e`
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
  `}function de(e,t){let n=e.channelMeta?.find(e=>e.id===t);return n?.label?n.label:e.channelLabels?.[t]??t}function fe(e){if(!e)return[];let t=new Set;for(let n of e.channelOrder??[])t.add(n);for(let n of e.channelMeta??[])t.add(n.id);for(let n of Object.keys(e.channelAccounts??{}))t.add(n);let n=[],r=e.channelOrder?.length?e.channelOrder:Array.from(t);for(let e of r)t.has(e)&&(n.push(e),t.delete(e));for(let e of t)n.push(e);return n.map(t=>({id:t,label:de(e,t),accounts:e.channelAccounts?.[t]??[]}))}var pe=[`groupPolicy`,`streamMode`,`dmPolicy`];function me(e){let t=0,n=0,r=0;for(let i of e){let e=i.probe&&typeof i.probe==`object`&&`ok`in i.probe?!!i.probe.ok:!1;(i.connected===!0||i.running===!0||e)&&(t+=1),i.configured&&(n+=1),i.enabled&&(r+=1)}return{total:e.length,connected:t,configured:n,enabled:r}}function he(t){let a=fe(t.snapshot),o=t.lastSuccess?i(t.lastSuccess):`never`;return e`
    <section class="grid grid-cols-2">
      ${Y(t.context,`Workspace, identity, and model configuration.`,t.onSelectPanel)}
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
                ${a.map(n=>{let i=me(n.accounts),a=i.total?`${i.connected}/${i.total} connected`:`no accounts`,o=i.configured?`${i.configured} configured`:`not configured`,s=i.total?`${i.enabled} enabled`:`disabled`,c=k({configForm:t.configForm,channelId:n.id,fields:pe});return e`
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
  `}function ge(t){let i=t.jobs.filter(e=>e.agentId===t.agentId);return e`
    <section class="grid grid-cols-2">
      ${Y(t.context,`Workspace and scheduling targets.`,t.onSelectPanel)}
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
            <div class="stat-value">${f(t.status?.nextWakeAtMs??null)}</div>
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
                        <span class="chip">${b(n)}</span>
                        <span class="chip ${n.enabled?`chip-ok`:`chip-warn`}">
                          ${n.enabled?`enabled`:`disabled`}
                        </span>
                        <span class="chip">${n.sessionTarget}</span>
                      </div>
                    </div>
                    <div class="list-meta">
                      <div class="mono">${S(n)}</div>
                      <div class="muted">${C(n)}</div>
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
  `}function _e(t){let i=t.agentFilesList?.agentId===t.agentId?t.agentFilesList:null,o=i?.files??[],l=t.agentFileActive??null,u=l?o.find(e=>e.name===l)??null:null,d=l?t.agentFileContents[l]??``:``,f=l?t.agentFileDrafts[l]??d:``,p=l?f!==d:!1;return e`
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
                ${o.map(n=>{let i=l===n.name,a=n.name.replace(/\.md$/i,``);return e`
                    <button
                      class="agent-tab ${i?`active`:``} ${n.missing?`agent-tab--missing`:``}"
                      @click=${()=>t.onSelectFile(n.name)}
                    >
                      ${a}${n.missing?e` <span class="agent-tab-badge">missing</span> `:r}
                    </button>
                  `})}
              </div>
              ${u?e`
                    <div class="agent-file-header" style="margin-top: 14px;">
                      <div>
                        <div class="agent-file-sub mono">${u.path}</div>
                      </div>
                      <div class="agent-file-actions">
                        <button
                          class="btn btn--sm"
                          title="Preview rendered markdown"
                          @click=${e=>{let t=e.currentTarget.closest(`.card`)?.querySelector(`dialog`);t&&t.showModal()}}
                        >
                          ${v.eye} Preview
                        </button>
                        <button
                          class="btn btn--sm"
                          ?disabled=${!p}
                          @click=${()=>t.onFileReset(u.name)}
                        >
                          Reset
                        </button>
                        <button
                          class="btn btn--sm primary"
                          ?disabled=${t.agentFileSaving||!p}
                          @click=${()=>t.onFileSave(u.name)}
                        >
                          ${t.agentFileSaving?`Saving…`:`Save`}
                        </button>
                      </div>
                    </div>
                    ${u.missing?e`
                          <div class="callout info" style="margin-top: 10px">
                            This file is missing. Saving will create it in the agent workspace.
                          </div>
                        `:r}
                    <label class="field agent-file-field" style="margin-top: 12px;">
                      <span>Content</span>
                      <textarea
                        class="agent-file-textarea"
                        .value=${f}
                        @input=${e=>t.onFileDraftChange(u.name,e.target.value)}
                      ></textarea>
                    </label>
                    <dialog
                      class="md-preview-dialog"
                      @click=${e=>{let t=e.currentTarget;e.target===t&&t.close()}}
                      @close=${e=>{e.currentTarget.querySelector(`.md-preview-dialog__panel`)?.classList.remove(`fullscreen`)}}
                    >
                      <div class="md-preview-dialog__panel">
                        <div class="md-preview-dialog__header">
                          <div class="md-preview-dialog__title mono">${u.name}</div>
                          <div class="md-preview-dialog__actions">
                            <button
                              class="btn btn--sm md-preview-expand-btn"
                              title="Toggle fullscreen"
                              @click=${e=>{let t=e.currentTarget,n=t.closest(`.md-preview-dialog__panel`);if(!n)return;let r=n.classList.toggle(`fullscreen`);t.classList.toggle(`is-fullscreen`,r)}}
                            >
                              <span class="when-normal">${v.maximize} Expand</span
                              ><span class="when-fullscreen">${v.minimize} Collapse</span>
                            </button>
                            <button
                              class="btn btn--sm"
                              title="Edit file"
                              @click=${e=>{e.currentTarget.closest(`dialog`)?.close(),document.querySelector(`.agent-file-textarea`)?.focus()}}
                            >
                              ${v.edit} Editor
                            </button>
                            <button
                              class="btn btn--sm"
                              @click=${e=>{e.currentTarget.closest(`dialog`)?.close()}}
                            >
                              ${v.x} Close
                            </button>
                          </div>
                        </div>
                        <div class="md-preview-dialog__body">
                          ${a(le(s.parse(f,{gfm:!0,breaks:!0}),{sanitize:e=>c.sanitize(e)}))}
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
  `}function ve(t,n){let i=n.source??t.source,a=n.pluginId??t.pluginId,o=[];return i===`plugin`&&a?o.push(`plugin:${a}`):i===`core`&&o.push(`core`),n.optional&&o.push(`optional`),o.length===0?r:e`
    <div style="display: flex; gap: 6px; flex-wrap: wrap; margin-top: 6px;">
      ${o.map(t=>e`<span class="agent-pill">${t}</span>`)}
    </div>
  `}function ye(e){return e.source===`plugin`?e.pluginId?n(`agentTools.connectedSource`,{id:e.pluginId}):n(`agentTools.connected`):e.source===`channel`?e.channelId?n(`agentTools.channelSource`,{id:e.channelId}):n(`agentTools.channel`):n(`agentTools.builtIn`)}function be(t){let i=T(t.configForm,t.agentId),a=i.entry?.tools??{},s=i.globalTools??{},c=a.profile??s.profile??`full`,d=o(t.toolsCatalogResult),f=E(t.toolsCatalogResult),p=a.profile?`agent override`:s.profile?`global default`:`default`,m=Array.isArray(a.allow)&&a.allow.length>0,h=Array.isArray(s.allow)&&s.allow.length>0,g=!!t.configForm&&!t.configLoading&&!t.configSaving&&!m&&!(t.toolsCatalogLoading&&!t.toolsCatalogResult&&!t.toolsCatalogError),_=m?[]:Array.isArray(a.alsoAllow)?a.alsoAllow:[],v=m?[]:Array.isArray(a.deny)?a.deny:[],b=m?{allow:a.allow??[],deny:a.deny??[]}:l(c)??void 0,S=f.flatMap(e=>e.tools.map(e=>e.id)),C=e=>{let t=x(e,b),n=y(e,_),r=y(e,v);return{allowed:(t||n)&&!r,baseAllowed:t,denied:r}},w=S.filter(e=>C(e).allowed).length,D=(e,n)=>{let r=new Set(_.map(e=>u(e)).filter(e=>e.length>0)),i=new Set(v.map(e=>u(e)).filter(e=>e.length>0)),a=C(e).baseAllowed,o=u(e);n?(i.delete(o),a||r.add(o)):(r.delete(o),i.add(o)),t.onOverridesChange(t.agentId,[...r],[...i])},O=e=>{let n=new Set(_.map(e=>u(e)).filter(e=>e.length>0)),r=new Set(v.map(e=>u(e)).filter(e=>e.length>0));for(let t of S){let i=C(t).baseAllowed,a=u(t);e?(r.delete(a),i||n.add(a)):(n.delete(a),r.add(a))}t.onOverridesChange(t.agentId,[...n],[...r])};return e`
    <section class="card">
      <div class="row" style="justify-content: space-between; flex-wrap: wrap;">
        <div style="min-width: 0;">
          <div class="card-title">Tool Access</div>
          <div class="card-sub">
            Profile + per-tool overrides for this agent.
            <span class="mono">${w}/${S.length}</span> enabled.
          </div>
        </div>
        <div class="row" style="gap: 8px; flex-wrap: wrap;">
          <button class="btn btn--sm" ?disabled=${!g} @click=${()=>O(!0)}>
            Enable All
          </button>
          <button class="btn btn--sm" ?disabled=${!g} @click=${()=>O(!1)}>
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
      ${m?e`
            <div class="callout info" style="margin-top: 12px">
              This agent is using an explicit allowlist in config. Tool overrides are managed in the
              Config tab.
            </div>
          `:r}
      ${h?e`
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
          <div>${p}</div>
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
                                          >${ye(t)}</span
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
          ${d.map(n=>e`
              <button
                class="btn btn--sm ${c===n.id?`active`:``}"
                ?disabled=${!g}
                @click=${()=>t.onProfileChange(t.agentId,n.id,!0)}
              >
                ${n.label}
              </button>
            `)}
          <button
            class="btn btn--sm"
            ?disabled=${!g}
            @click=${()=>t.onProfileChange(t.agentId,null,!1)}
          >
            Inherit
          </button>
        </div>
      </div>

      <div class="agent-tools-grid" style="margin-top: 20px;">
        ${f.map(t=>e`
            <div class="agent-tools-section">
              <div class="agent-tools-header">
                ${t.label}
                ${t.source===`plugin`&&t.pluginId?e`<span class="agent-pill" style="margin-left: 8px;"
                      >plugin:${t.pluginId}</span
                    >`:r}
              </div>
              <div class="agent-tools-list">
                ${t.tools.map(n=>{let{allowed:r}=C(n.id);return e`
                    <div class="agent-tool-row">
                      <div>
                        <div class="agent-tool-title mono">${n.label}</div>
                        <div class="agent-tool-sub">${n.description}</div>
                        ${ve(t,n)}
                      </div>
                      <label class="cfg-toggle">
                        <input
                          type="checkbox"
                          .checked=${r}
                          ?disabled=${!g}
                          @change=${e=>D(n.id,e.target.checked)}
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
  `}function xe(t){let i=!!t.configForm&&!t.configLoading&&!t.configSaving,a=T(t.configForm,t.agentId),o=Array.isArray(a.entry?.skills)?a.entry?.skills:void 0,s=new Set((o??[]).map(e=>e.trim()).filter(Boolean)),c=o!==void 0,l=!!(t.report&&t.activeAgentId===t.agentId),u=l?t.report?.skills??[]:[],d=t.filter.trim().toLowerCase(),f=d?u.filter(e=>[e.name,e.description,e.source].join(` `).toLowerCase().includes(d)):u,p=A(f),m=c?u.filter(e=>s.has(e.name)).length:u.length,h=u.length;return e`
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
              ${p.map(e=>Se(e,{agentId:t.agentId,allowSet:s,usingAllowlist:c,editable:i,onToggle:t.onToggle}))}
            </div>
          `}
    </section>
  `}function Se(t,n){return e`
    <details class="agent-skills-group" ?open=${!(t.id===`workspace`||t.id===`built-in`)}>
      <summary class="agent-skills-header">
        <span>${t.label}</span>
        <span class="muted">${t.skills.length}</span>
      </summary>
      <div class="list skills-grid">
        ${t.skills.map(e=>Ce(e,{agentId:n.agentId,allowSet:n.allowSet,usingAllowlist:n.usingAllowlist,editable:n.editable,onToggle:n.onToggle}))}
      </div>
    </details>
  `}function Ce(t,n){let i=n.usingAllowlist?n.allowSet.has(t.name):!0,a=N(t),o=j(t);return e`
    <div class="list-item agent-skill-row">
      <div class="list-main">
        <div class="list-title">${t.emoji?`${t.emoji} `:``}${t.name}</div>
        <div class="list-sub">${t.description}</div>
        ${M({skill:t})}
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
  `}function X(t){let i=t.list?.teams??[],a=t.detail?.members??[],o=t.detail?Q(t.detail):t.selectedId?t.selectedId:`New team`;return e`
    <section class="grid grid-cols-2">
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
        ${i.length===0?e`
              <div class="callout info" style="margin-top: 12px;">
                No teams are configured yet.
              </div>
            `:e`
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
                        <div class="list-title">${Q(n)}</div>
                        <div class="list-sub">
                          ${n.members?.length??0} members · default
                          ${$(n.defaultAgentId,n.members??[])}
                        </div>
                      </div>
                      <div class="list-meta">
                        <span class="badge">${n.bindings?.length??0} bindings</span>
                      </div>
                    </button>
                  `)}
              </div>
            `}
      </section>

      <section class="card">
        <div class="card-title">${o}</div>
        <div class="card-sub">Create or update team metadata, members, aliases, and draft bindings.</div>
        <div class="grid grid-cols-2" style="margin-top: 14px;">
          <label class="field">
            <span>Team key</span>
            <input
              .value=${t.draft.id}
              ?disabled=${!!t.detail}
              placeholder="content"
              @input=${e=>t.onDraftChange({id:e.target.value})}
            />
          </label>
          <label class="field">
            <span>Display name</span>
            <input
              .value=${t.draft.displayName}
              placeholder="Content Team"
              @input=${e=>t.onDraftChange({displayName:e.target.value})}
            />
          </label>
          <label class="field">
            <span>Template for new team</span>
            <select
              .value=${t.draft.template}
              ?disabled=${!!t.detail}
              @change=${e=>t.onDraftChange({template:e.target.value})}
            >
              <option value="pm-writer-reviewer">PM / Writer / Reviewer</option>
              <option value="">Custom members JSON</option>
            </select>
          </label>
          <label class="field">
            <span>Default member</span>
            <select
              .value=${t.draft.defaultAgentId}
              @change=${e=>t.onDraftChange({defaultAgentId:e.target.value})}
            >
              <option value="">First member</option>
              ${a.map(t=>e`
                  <option value=${t.agentId}>${$(t.agentId,a)}</option>
                `)}
            </select>
          </label>
        </div>
        ${Z(`Members JSON`,t.draft.membersJson,e=>t.onDraftChange({membersJson:e}))}
        ${Z(`Aliases JSON`,t.draft.aliasesJson,e=>t.onDraftChange({aliasesJson:e}))}
        ${Z(`Team bindings JSON`,t.draft.bindingsJson,e=>t.onDraftChange({bindingsJson:e}))}
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
    </section>

    <section class="grid grid-cols-2" style="margin-top: 16px;">
      ${we(t,a)}
      ${Te(t,a)}
    </section>
  `}function we(t,n){return e`
    <section class="card">
      <div class="card-title">Member Binding</div>
      <div class="card-sub">Apply or remove a channel/account route through Gateway binding RPC.</div>
      <div class="grid grid-cols-2" style="margin-top: 14px;">
        <label class="field">
          <span>Member</span>
          <select
            .value=${t.binding.agentId}
            @change=${e=>t.onBindingChange({agentId:e.target.value})}
          >
            <option value="">Choose member</option>
            ${n.map(t=>e`
                <option value=${t.agentId}>${$(t.agentId,n)}</option>
              `)}
          </select>
        </label>
        <label class="field">
          <span>Action</span>
          <select
            .value=${t.binding.mode}
            @change=${e=>t.onBindingChange({mode:e.target.value===`unbind`?`unbind`:`bind`})}
          >
            <option value="bind">Apply</option>
            <option value="unbind">Remove</option>
          </select>
        </label>
      </div>
      <label class="field" style="margin-top: 12px;">
        <span>Channel binding</span>
        <input
          .value=${t.binding.spec}
          placeholder="telegram:bot-a"
          @input=${e=>t.onBindingChange({spec:e.target.value})}
        />
      </label>
      <div class="agent-model-actions">
        <button
          type="button"
          class="btn btn--sm primary"
          ?disabled=${t.saving||!t.binding.agentId||!t.binding.spec.trim()}
          @click=${t.onApplyBinding}
        >
          ${t.binding.mode===`unbind`?`Remove Binding`:`Apply Binding`}
        </button>
      </div>
      ${t.bindingResult?e`
            <div class="callout info" style="margin-top: 12px;">
              ${Ee(t.bindingResult)}
            </div>
          `:r}
    </section>
  `}function Te(t,n){let i=t.modelResult?.models??null;return e`
    <section class="card">
      <div class="card-title">Member Model</div>
      <div class="card-sub">Read and write per-agent models.json through Gateway.</div>
      ${t.modelError?e`<div class="callout danger" style="margin-top: 12px;">${t.modelError}</div>`:r}
      <div class="grid grid-cols-2" style="margin-top: 14px;">
        <label class="field">
          <span>Member</span>
          <select
            .value=${t.modelDraft.agentId}
            @change=${e=>t.onModelDraftChange({agentId:e.target.value})}
          >
            <option value="">Choose member</option>
            ${n.map(t=>e`
                <option value=${t.agentId}>${$(t.agentId,n)}</option>
              `)}
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
            @input=${e=>t.onModelDraftChange({primaryModelRef:e.target.value})}
          />
        </label>
        <label class="field">
          <span>Runtime primary model ref</span>
          <input
            .value=${t.modelDraft.runtimePrimaryModelRef}
            placeholder="openai:gpt-5-mini"
            @input=${e=>t.onModelDraftChange({runtimePrimaryModelRef:e.target.value})}
          />
        </label>
      </div>
      ${i?.path?e`
            <div class="agent-kv" style="margin-top: 12px;">
              <div class="label">models.json path</div>
              <div class="mono">${i.path}</div>
            </div>
          `:r}
      ${Z(`models.json state`,t.modelDraft.stateJson,e=>t.onModelDraftChange({stateJson:e}))}
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
  `}function Z(t,n,r){return e`
    <label class="field agent-file-field" style="margin-top: 12px;">
      <span>${t}</span>
      <textarea
        class="agent-file-textarea"
        rows="6"
        .value=${n}
        @input=${e=>r(e.target.value)}
      ></textarea>
    </label>
  `}function Q(e){return e.displayName?.trim()||e.id}function $(e,t){if(!e)return`first configured member`;let n=t.find(t=>t.agentId===e);return n?`${n.name?.trim()||n.role?.trim()||n.agentId} (${n.agentId})`:e}function Ee(e){let t=[e.added?.length?`${e.added.length} added`:``,e.removed?.length?`${e.removed.length} removed`:``,e.skipped?.length?`${e.skipped.length} skipped`:``,e.missing?.length?`${e.missing.length} missing`:``,e.conflicts?.length?`${e.conflicts.length} conflicts`:``].filter(Boolean);return t.length?t.join(`, `):`Gateway accepted the binding request.`}function De(t){let i=t.agentsList?.agents??[],a=t.agentsList?.defaultId??null,o=t.selectedAgentId??a??i[0]?.id??null,s=o?i.find(e=>e.id===o)??null:null,c=o&&t.agentSkills.agentId===o?t.agentSkills.report?.skills?.length??null:null,l=t.channels.snapshot?Object.keys(t.channels.snapshot.channelAccounts??{}).length:null,u=o?t.cron.jobs.filter(e=>e.agentId===o).length:null,d={files:t.agentFiles.list?.files?.length??null,skills:c,channels:l,cron:u||null,teams:t.agentTeams.list?.count??null};return e`
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
                        ${_(t)}${w(t.id,a)?` (${w(t.id,a)})`:``}
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
        ${Oe(t.activePanel,e=>t.onSelectPanel(e),d)}
        ${!s&&t.activePanel!==`teams`?e`
              <div class="card">
                <div class="card-title">Select an agent</div>
                <div class="card-sub">Pick an agent to inspect its workspace and tools.</div>
              </div>
            `:e`
              ${t.activePanel===`overview`?P({agent:s,basePath:t.basePath,defaultId:a,configForm:t.config.form,agentFilesList:t.agentFiles.list,agentIdentity:t.agentIdentityById[s.id]??null,agentIdentityError:t.agentIdentityError,agentIdentityLoading:t.agentIdentityLoading,configLoading:t.config.loading,configSaving:t.config.saving,configDirty:t.config.dirty,modelCatalog:t.modelCatalog,onConfigReload:t.onConfigReload,onConfigSave:t.onConfigSave,onModelChange:t.onModelChange,onModelFallbacksChange:t.onModelFallbacksChange,onSelectPanel:t.onSelectPanel}):r}
              ${t.activePanel===`files`?_e({agentId:s.id,agentFilesList:t.agentFiles.list,agentFilesLoading:t.agentFiles.loading,agentFilesError:t.agentFiles.error,agentFileActive:t.agentFiles.active,agentFileContents:t.agentFiles.contents,agentFileDrafts:t.agentFiles.drafts,agentFileSaving:t.agentFiles.saving,onLoadFiles:t.onLoadFiles,onSelectFile:t.onSelectFile,onFileDraftChange:t.onFileDraftChange,onFileReset:t.onFileReset,onFileSave:t.onFileSave}):r}
              ${t.activePanel===`tools`?be({agentId:s.id,configForm:t.config.form,configLoading:t.config.loading,configSaving:t.config.saving,configDirty:t.config.dirty,toolsCatalogLoading:t.toolsCatalog.loading,toolsCatalogError:t.toolsCatalog.error,toolsCatalogResult:t.toolsCatalog.result,toolsEffectiveLoading:t.toolsEffective.loading,toolsEffectiveError:t.toolsEffective.error,toolsEffectiveResult:t.toolsEffective.result,runtimeSessionKey:t.runtimeSessionKey,runtimeSessionMatchesSelectedAgent:t.runtimeSessionMatchesSelectedAgent,onProfileChange:t.onToolsProfileChange,onOverridesChange:t.onToolsOverridesChange,onConfigReload:t.onConfigReload,onConfigSave:t.onConfigSave}):r}
              ${t.activePanel===`skills`?xe({agentId:s.id,report:t.agentSkills.report,loading:t.agentSkills.loading,error:t.agentSkills.error,activeAgentId:t.agentSkills.agentId,configForm:t.config.form,configLoading:t.config.loading,configSaving:t.config.saving,configDirty:t.config.dirty,filter:t.agentSkills.filter,onFilterChange:t.onSkillsFilterChange,onRefresh:t.onSkillsRefresh,onToggle:t.onAgentSkillToggle,onClear:t.onAgentSkillsClear,onDisableAll:t.onAgentSkillsDisableAll,onConfigReload:t.onConfigReload,onConfigSave:t.onConfigSave}):r}
              ${t.activePanel===`channels`?he({context:m(s,t.config.form,t.agentFiles.list,a,t.agentIdentityById[s.id]??null),configForm:t.config.form,snapshot:t.channels.snapshot,loading:t.channels.loading,error:t.channels.error,lastSuccess:t.channels.lastSuccess,onRefresh:t.onChannelsRefresh,onSelectPanel:t.onSelectPanel}):r}
              ${t.activePanel===`cron`?ge({context:m(s,t.config.form,t.agentFiles.list,a,t.agentIdentityById[s.id]??null),agentId:s.id,jobs:t.cron.jobs,status:t.cron.status,loading:t.cron.loading,error:t.cron.error,onRefresh:t.onCronRefresh,onRunNow:t.onCronRunNow,onSelectPanel:t.onSelectPanel}):r}
              ${t.activePanel===`teams`?X({...t.agentTeams,onRefresh:t.onTeamsRefresh,onSelectTeam:t.onSelectTeam,onNewTeam:t.onNewTeam,onDraftChange:t.onTeamDraftChange,onCreateTeam:t.onCreateTeam,onUpdateTeam:t.onUpdateTeam,onDeleteTeam:t.onDeleteTeam,onBindingChange:t.onTeamBindingChange,onApplyBinding:t.onApplyTeamBinding,onModelDraftChange:t.onTeamModelDraftChange,onLoadModel:t.onLoadTeamModel,onSaveModel:t.onSaveTeamModel}):r}
            `}
      </section>
    </div>
  `}function Oe(t,n,i){return e`
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
  `}export{De as renderAgents};
//# sourceMappingURL=agents.js.map