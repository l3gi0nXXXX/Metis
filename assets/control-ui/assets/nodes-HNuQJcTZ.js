import{f as e,r as t,u as n}from"./i18n-CV7rUnW0.js";import{l as r,r as i,t as a}from"./format-EHph2kGh.js";function o(e){let t=e?.agents??{},n=Array.isArray(t.list)?t.list:[],r=[];return n.forEach((e,t)=>{if(!e||typeof e!=`object`)return;let n=e,i=typeof n.id==`string`?n.id.trim():``;if(!i)return;let a=typeof n.name==`string`?n.name.trim():void 0,o=n.default===!0;r.push({id:i,name:a||void 0,isDefault:o,index:t,record:n})}),r}function s(e,t){let n=new Set(t),r=[];for(let t of e){if(!(Array.isArray(t.commands)?t.commands:[]).some(e=>n.has(String(e))))continue;let e=typeof t.nodeId==`string`?t.nodeId.trim():``;if(!e)continue;let i=typeof t.displayName==`string`&&t.displayName.trim()?t.displayName.trim():e;r.push({id:e,label:i===e?e:`${i} · ${e}`})}return r.sort((e,t)=>e.label.localeCompare(t.label)),r}var c=`__defaults__`,l=[{value:`deny`,label:`Deny`},{value:`allowlist`,label:`Allowlist`},{value:`full`,label:`Full`}],u=[{value:`off`,label:`Off`},{value:`on-miss`,label:`On miss`},{value:`always`,label:`Always`}];function d(e){return e===`allowlist`||e===`full`||e===`deny`?e:`deny`}function f(e){return e===`always`||e===`off`||e===`on-miss`?e:`on-miss`}function p(e){let t=e?.defaults??{};return{security:d(t.security),ask:f(t.ask),askFallback:d(t.askFallback??`deny`),autoAllowSkills:!!(t.autoAllowSkills??!1)}}function m(e){return o(e).map(e=>({id:e.id,name:e.name,isDefault:e.isDefault}))}function h(e,t){let n=m(e),r=Object.keys(t?.agents??{}),i=new Map;n.forEach(e=>i.set(e.id,e)),r.forEach(e=>{i.has(e)||i.set(e,{id:e})});let a=Array.from(i.values());return a.length===0&&a.push({id:`main`,isDefault:!0}),a.sort((e,t)=>{if(e.isDefault&&!t.isDefault)return-1;if(!e.isDefault&&t.isDefault)return 1;let n=e.name?.trim()?e.name:e.id,r=t.name?.trim()?t.name:t.id;return n.localeCompare(r)}),a}function g(e,t){return e===c?c:e&&t.some(t=>t.id===e)?e:c}function _(e){let t=e.execApprovalsForm??e.execApprovalsSnapshot?.file??null,n=!!t,r=p(t),i=h(e.configForm,t),a=w(e.nodes),o=e.execApprovalsTarget,s=o===`node`&&e.execApprovalsTargetNodeId?e.execApprovalsTargetNodeId:null;o===`node`&&s&&!a.some(e=>e.id===s)&&(s=null);let l=g(e.execApprovalsSelectedAgent,i),u=l===c?null:(t?.agents??{})[l]??null,d=Array.isArray(u?.allowlist)?u.allowlist??[]:[];return{ready:n,disabled:e.execApprovalsSaving||e.execApprovalsLoading,dirty:e.execApprovalsDirty,loading:e.execApprovalsLoading,saving:e.execApprovalsSaving,form:t,defaults:r,selectedScope:l,selectedAgent:u,agents:i,allowlist:d,target:o,targetNodeId:s,targetNodes:a,onSelectScope:e.onExecApprovalsSelectAgent,onSelectTarget:e.onExecApprovalsTargetChange,onPatch:e.onExecApprovalsPatch,onRemove:e.onExecApprovalsRemove,onLoad:e.onLoadExecApprovals,onSave:e.onSaveExecApprovals}}function v(r){let i=r.ready,a=r.target!==`node`||!!r.targetNodeId;return e`
    <section class="card">
      <div class="row" style="justify-content: space-between; align-items: center;">
        <div>
          <div class="card-title">Exec approvals</div>
          <div class="card-sub">
            Allowlist and approval policy for <span class="mono">exec host=gateway/node</span>.
          </div>
        </div>
        <button
          class="btn"
          ?disabled=${r.disabled||!r.dirty||!a}
          @click=${r.onSave}
        >
          ${r.saving?`Saving…`:`Save`}
        </button>
      </div>

      ${y(r)}
      ${i?e`
            ${b(r)} ${x(r)}
            ${r.selectedScope===c?n:S(r)}
          `:e`<div class="row" style="margin-top: 12px; gap: 12px;">
            <div class="muted">Load exec approvals to edit allowlists.</div>
            <button class="btn" ?disabled=${r.loading||!a} @click=${r.onLoad}>
              ${r.loading?t(`common.loading`):t(`common.loadApprovals`)}
            </button>
          </div>`}
    </section>
  `}function y(t){let r=t.targetNodes.length>0,i=t.targetNodeId??``;return e`
    <div class="list" style="margin-top: 12px;">
      <div class="list-item">
        <div class="list-main">
          <div class="list-title">Target</div>
          <div class="list-sub">Gateway edits local approvals; node edits the selected node.</div>
        </div>
        <div class="list-meta">
          <label class="field">
            <span>Host</span>
            <select
              ?disabled=${t.disabled}
              @change=${e=>{if(e.target.value===`node`){let e=t.targetNodes[0]?.id??null;t.onSelectTarget(`node`,i||e)}else t.onSelectTarget(`gateway`,null)}}
            >
              <option value="gateway" ?selected=${t.target===`gateway`}>Gateway</option>
              <option value="node" ?selected=${t.target===`node`}>Node</option>
            </select>
          </label>
          ${t.target===`node`?e`
                <label class="field">
                  <span>Node</span>
                  <select
                    ?disabled=${t.disabled||!r}
                    @change=${e=>{let n=e.target.value.trim();t.onSelectTarget(`node`,n||null)}}
                  >
                    <option value="" ?selected=${i===``}>Select node</option>
                    ${t.targetNodes.map(t=>e`<option value=${t.id} ?selected=${i===t.id}>
                          ${t.label}
                        </option>`)}
                  </select>
                </label>
              `:n}
        </div>
      </div>
      ${t.target===`node`&&!r?e` <div class="muted">No nodes advertise exec approvals yet.</div> `:n}
    </div>
  `}function b(t){return e`
    <div class="row" style="margin-top: 12px; gap: 8px; flex-wrap: wrap;">
      <span class="label">Scope</span>
      <div class="row" style="gap: 8px; flex-wrap: wrap;">
        <button
          class="btn btn--sm ${t.selectedScope===c?`active`:``}"
          @click=${()=>t.onSelectScope(c)}
        >
          Defaults
        </button>
        ${t.agents.map(n=>{let r=n.name?.trim()?`${n.name} (${n.id})`:n.id;return e`
            <button
              class="btn btn--sm ${t.selectedScope===n.id?`active`:``}"
              @click=${()=>t.onSelectScope(n.id)}
            >
              ${r}
            </button>
          `})}
      </div>
    </div>
  `}function x(t){let r=t.selectedScope===c,i=t.defaults,a=t.selectedAgent??{},o=r?[`defaults`]:[`agents`,t.selectedScope],s=typeof a.security==`string`?a.security:void 0,d=typeof a.ask==`string`?a.ask:void 0,f=typeof a.askFallback==`string`?a.askFallback:void 0,p=r?i.security:s??`__default__`,m=r?i.ask:d??`__default__`,h=r?i.askFallback:f??`__default__`,g=typeof a.autoAllowSkills==`boolean`?a.autoAllowSkills:void 0,_=g??i.autoAllowSkills,v=g==null;return e`
    <div class="list" style="margin-top: 16px;">
      <div class="list-item">
        <div class="list-main">
          <div class="list-title">Security</div>
          <div class="list-sub">
            ${r?`Default security mode.`:`Default: ${i.security}.`}
          </div>
        </div>
        <div class="list-meta">
          <label class="field">
            <span>Mode</span>
            <select
              ?disabled=${t.disabled}
              @change=${e=>{let n=e.target.value;!r&&n===`__default__`?t.onRemove([...o,`security`]):t.onPatch([...o,`security`],n)}}
            >
              ${r?n:e`<option value="__default__" ?selected=${p===`__default__`}>
                    Use default (${i.security})
                  </option>`}
              ${l.map(t=>e`<option value=${t.value} ?selected=${p===t.value}>
                    ${t.label}
                  </option>`)}
            </select>
          </label>
        </div>
      </div>

      <div class="list-item">
        <div class="list-main">
          <div class="list-title">Ask</div>
          <div class="list-sub">
            ${r?`Default prompt policy.`:`Default: ${i.ask}.`}
          </div>
        </div>
        <div class="list-meta">
          <label class="field">
            <span>Mode</span>
            <select
              ?disabled=${t.disabled}
              @change=${e=>{let n=e.target.value;!r&&n===`__default__`?t.onRemove([...o,`ask`]):t.onPatch([...o,`ask`],n)}}
            >
              ${r?n:e`<option value="__default__" ?selected=${m===`__default__`}>
                    Use default (${i.ask})
                  </option>`}
              ${u.map(t=>e`<option value=${t.value} ?selected=${m===t.value}>
                    ${t.label}
                  </option>`)}
            </select>
          </label>
        </div>
      </div>

      <div class="list-item">
        <div class="list-main">
          <div class="list-title">Ask fallback</div>
          <div class="list-sub">
            ${r?`Applied when the UI prompt is unavailable.`:`Default: ${i.askFallback}.`}
          </div>
        </div>
        <div class="list-meta">
          <label class="field">
            <span>Fallback</span>
            <select
              ?disabled=${t.disabled}
              @change=${e=>{let n=e.target.value;!r&&n===`__default__`?t.onRemove([...o,`askFallback`]):t.onPatch([...o,`askFallback`],n)}}
            >
              ${r?n:e`<option value="__default__" ?selected=${h===`__default__`}>
                    Use default (${i.askFallback})
                  </option>`}
              ${l.map(t=>e`<option value=${t.value} ?selected=${h===t.value}>
                    ${t.label}
                  </option>`)}
            </select>
          </label>
        </div>
      </div>

      <div class="list-item">
        <div class="list-main">
          <div class="list-title">Auto-allow skill CLIs</div>
          <div class="list-sub">
            ${r?`Allow skill executables listed by the Gateway.`:v?`Using default (${i.autoAllowSkills?`on`:`off`}).`:`Override (${_?`on`:`off`}).`}
          </div>
        </div>
        <div class="list-meta">
          <label class="field">
            <span>Enabled</span>
            <input
              type="checkbox"
              ?disabled=${t.disabled}
              .checked=${_}
              @change=${e=>{let n=e.target;t.onPatch([...o,`autoAllowSkills`],n.checked)}}
            />
          </label>
          ${!r&&!v?e`<button
                class="btn btn--sm"
                ?disabled=${t.disabled}
                @click=${()=>t.onRemove([...o,`autoAllowSkills`])}
              >
                Use default
              </button>`:n}
        </div>
      </div>
    </div>
  `}function S(t){let n=[`agents`,t.selectedScope,`allowlist`],r=t.allowlist;return e`
    <div class="row" style="margin-top: 18px; justify-content: space-between;">
      <div>
        <div class="card-title">Allowlist</div>
        <div class="card-sub">Case-insensitive glob patterns.</div>
      </div>
      <button
        class="btn btn--sm"
        ?disabled=${t.disabled}
        @click=${()=>{let e=[...r,{pattern:``}];t.onPatch(n,e)}}
      >
        Add pattern
      </button>
    </div>
    <div class="list" style="margin-top: 12px;">
      ${r.length===0?e` <div class="muted">No allowlist entries yet.</div> `:r.map((e,n)=>C(t,e,n))}
    </div>
  `}function C(t,i,o){let s=i.lastUsedAt?r(i.lastUsedAt):`never`,c=i.lastUsedCommand?a(i.lastUsedCommand,120):null,l=i.lastResolvedPath?a(i.lastResolvedPath,120):null;return e`
    <div class="list-item">
      <div class="list-main">
        <div class="list-title">${i.pattern?.trim()?i.pattern:`New pattern`}</div>
        <div class="list-sub">Last used: ${s}</div>
        ${c?e`<div class="list-sub mono">${c}</div>`:n}
        ${l?e`<div class="list-sub mono">${l}</div>`:n}
      </div>
      <div class="list-meta">
        <label class="field">
          <span>Pattern</span>
          <input
            type="text"
            .value=${i.pattern??``}
            ?disabled=${t.disabled}
            @input=${e=>{let n=e.target;t.onPatch([`agents`,t.selectedScope,`allowlist`,o,`pattern`],n.value)}}
          />
        </label>
        <button
          class="btn btn--sm danger"
          ?disabled=${t.disabled}
          @click=${()=>{if(t.allowlist.length<=1){t.onRemove([`agents`,t.selectedScope,`allowlist`]);return}t.onRemove([`agents`,t.selectedScope,`allowlist`,o])}}
        >
          Remove
        </button>
      </div>
    </div>
  `}function w(e){return s(e,[`system.execApprovals.get`,`system.execApprovals.set`])}function T(n){let r=A(n);return e`
    ${v(_(n))} ${j(r)} ${E(n)}
    <section class="card">
      <div class="row" style="justify-content: space-between;">
        <div>
          <div class="card-title">Nodes</div>
          <div class="card-sub">Paired devices and live links.</div>
        </div>
        <button class="btn" ?disabled=${n.loading} @click=${n.onRefresh}>
          ${n.loading?t(`common.loading`):t(`common.refresh`)}
        </button>
      </div>
      <div class="list" style="margin-top: 16px;">
        ${n.nodes.length===0?e` <div class="muted">No nodes found.</div> `:n.nodes.map(e=>F(e))}
      </div>
    </section>
  `}function E(r){let i=r.devicesList??{pending:[],paired:[]},a=Array.isArray(i.pending)?i.pending:[],o=Array.isArray(i.paired)?i.paired:[];return e`
    <section class="card">
      <div class="row" style="justify-content: space-between;">
        <div>
          <div class="card-title">Devices</div>
          <div class="card-sub">Pairing requests + role tokens.</div>
        </div>
        <button class="btn" ?disabled=${r.devicesLoading} @click=${r.onDevicesRefresh}>
          ${r.devicesLoading?t(`common.loading`):t(`common.refresh`)}
        </button>
      </div>
      ${r.devicesError?e`<div class="callout danger" style="margin-top: 12px;">${r.devicesError}</div>`:n}
      <div class="list" style="margin-top: 16px;">
        ${a.length>0?e`
              <div class="muted" style="margin-bottom: 8px;">Pending</div>
              ${a.map(e=>D(e,r))}
            `:n}
        ${o.length>0?e`
              <div class="muted" style="margin-top: 12px; margin-bottom: 8px;">Paired</div>
              ${o.map(e=>O(e,r))}
            `:n}
        ${a.length===0&&o.length===0?e` <div class="muted">No paired devices.</div> `:n}
      </div>
    </section>
  `}function D(n,a){let o=n.displayName?.trim()||n.deviceId,s=typeof n.ts==`number`?r(n.ts):t(`common.na`),c=n.role?.trim()||i(n.roles),l=i(n.scopes),u=n.isRepair?` · repair`:``,d=n.remoteIp?` · ${n.remoteIp}`:``;return e`
    <div class="list-item">
      <div class="list-main">
        <div class="list-title">${o}</div>
        <div class="list-sub">${n.deviceId}${d}</div>
        <div class="muted" style="margin-top: 6px;">
          role: ${c} · scopes: ${l} · requested ${s}${u}
        </div>
      </div>
      <div class="list-meta">
        <div class="row" style="justify-content: flex-end; gap: 8px; flex-wrap: wrap;">
          <button class="btn btn--sm primary" @click=${()=>a.onDeviceApprove(n.requestId)}>
            Approve
          </button>
          <button class="btn btn--sm" @click=${()=>a.onDeviceReject(n.requestId)}>
            Reject
          </button>
        </div>
      </div>
    </div>
  `}function O(t,n){let r=t.displayName?.trim()||t.deviceId,a=t.remoteIp?` · ${t.remoteIp}`:``,o=`roles: ${i(t.roles)}`,s=`scopes: ${i(t.scopes)}`,c=Array.isArray(t.tokens)?t.tokens:[];return e`
    <div class="list-item">
      <div class="list-main">
        <div class="list-title">${r}</div>
        <div class="list-sub">${t.deviceId}${a}</div>
        <div class="muted" style="margin-top: 6px;">${o} · ${s}</div>
        ${c.length===0?e` <div class="muted" style="margin-top: 6px">Tokens: none</div> `:e`
              <div class="muted" style="margin-top: 10px;">Tokens</div>
              <div style="display: flex; flex-direction: column; gap: 8px; margin-top: 6px;">
                ${c.map(e=>k(t.deviceId,e,n))}
              </div>
            `}
      </div>
    </div>
  `}function k(t,a,o){let s=a.revokedAtMs?`revoked`:`active`,c=`scopes: ${i(a.scopes)}`,l=r(a.rotatedAtMs??a.createdAtMs??a.lastUsedAtMs??null);return e`
    <div class="row" style="justify-content: space-between; gap: 8px;">
      <div class="list-sub">${a.role} · ${s} · ${c} · ${l}</div>
      <div class="row" style="justify-content: flex-end; gap: 6px; flex-wrap: wrap;">
        <button
          class="btn btn--sm"
          @click=${()=>o.onDeviceRotate(t,a.role,a.scopes)}
        >
          Rotate
        </button>
        ${a.revokedAtMs?n:e`
              <button
                class="btn btn--sm danger"
                @click=${()=>o.onDeviceRevoke(t,a.role)}
              >
                Revoke
              </button>
            `}
      </div>
    </div>
  `}function A(e){let t=e.configForm,n=N(e.nodes),{defaultBinding:r,agents:i}=P(t);return{ready:!!t,disabled:e.configSaving||e.configFormMode===`raw`,configDirty:e.configDirty,configLoading:e.configLoading,configSaving:e.configSaving,defaultBinding:r,agents:i,nodes:n,onBindDefault:e.onBindDefault,onBindAgent:e.onBindAgent,onSave:e.onSaveBindings,onLoadConfig:e.onLoadConfig,formMode:e.configFormMode}}function j(r){let i=r.nodes.length>0,a=r.defaultBinding??``;return e`
    <section class="card">
      <div class="row" style="justify-content: space-between; align-items: center;">
        <div>
          <div class="card-title">${t(`nodes.binding.execNodeBinding`)}</div>
          <div class="card-sub">${t(`nodes.binding.execNodeBindingSubtitle`)}</div>
        </div>
        <button
          class="btn"
          ?disabled=${r.disabled||!r.configDirty}
          @click=${r.onSave}
        >
          ${r.configSaving?t(`common.saving`):t(`common.save`)}
        </button>
      </div>

      ${r.formMode===`raw`?e`
            <div class="callout warn" style="margin-top: 12px">
              ${t(`nodes.binding.formModeHint`)}
            </div>
          `:n}
      ${r.ready?e`
            <div class="list" style="margin-top: 16px;">
              <div class="list-item">
                <div class="list-main">
                  <div class="list-title">${t(`nodes.binding.defaultBinding`)}</div>
                  <div class="list-sub">${t(`nodes.binding.defaultBindingHint`)}</div>
                </div>
                <div class="list-meta">
                  <label class="field">
                    <span>${t(`nodes.binding.node`)}</span>
                    <select
                      ?disabled=${r.disabled||!i}
                      @change=${e=>{let t=e.target.value.trim();r.onBindDefault(t||null)}}
                    >
                      <option value="" ?selected=${a===``}>Any node</option>
                      ${r.nodes.map(t=>e`<option value=${t.id} ?selected=${a===t.id}>
                            ${t.label}
                          </option>`)}
                    </select>
                  </label>
                  ${i?n:e` <div class="muted">No nodes with system.run available.</div> `}
                </div>
              </div>

              ${r.agents.length===0?e` <div class="muted">No agents found.</div> `:r.agents.map(e=>M(e,r))}
            </div>
          `:e`<div class="row" style="margin-top: 12px; gap: 12px;">
            <div class="muted">${t(`nodes.binding.loadConfigHint`)}</div>
            <button class="btn" ?disabled=${r.configLoading} @click=${r.onLoadConfig}>
              ${r.configLoading?t(`common.loading`):t(`common.loadConfig`)}
            </button>
          </div>`}
    </section>
  `}function M(t,n){let r=t.binding??`__default__`,i=t.name?.trim()?`${t.name} (${t.id})`:t.id,a=n.nodes.length>0;return e`
    <div class="list-item">
      <div class="list-main">
        <div class="list-title">${i}</div>
        <div class="list-sub">
          ${t.isDefault?`default agent`:`agent`} ·
          ${r===`__default__`?`uses default (${n.defaultBinding??`any`})`:`override: ${t.binding}`}
        </div>
      </div>
      <div class="list-meta">
        <label class="field">
          <span>Binding</span>
          <select
            ?disabled=${n.disabled||!a}
            @change=${e=>{let r=e.target.value.trim();n.onBindAgent(t.index,r===`__default__`?null:r)}}
          >
            <option value="__default__" ?selected=${r===`__default__`}>
              Use default
            </option>
            ${n.nodes.map(t=>e`<option value=${t.id} ?selected=${r===t.id}>
                  ${t.label}
                </option>`)}
          </select>
        </label>
      </div>
    </div>
  `}function N(e){return s(e,[`system.run`])}function P(e){let t={id:`main`,name:void 0,index:0,isDefault:!0,binding:null};if(!e||typeof e!=`object`)return{defaultBinding:null,agents:[t]};let n=(e.tools??{}).exec??{},r=typeof n.node==`string`&&n.node.trim()?n.node.trim():null,i=e.agents??{};if(!Array.isArray(i.list)||i.list.length===0)return{defaultBinding:r,agents:[t]};let a=o(e).map(e=>{let t=(e.record.tools??{}).exec??{},n=typeof t.node==`string`&&t.node.trim()?t.node.trim():null;return{id:e.id,name:e.name,index:e.index,isDefault:e.isDefault,binding:n}});return a.length===0&&a.push(t),{defaultBinding:r,agents:a}}function F(t){let n=!!t.connected,r=!!t.paired,i=typeof t.displayName==`string`&&t.displayName.trim()||(typeof t.nodeId==`string`?t.nodeId:`unknown`),a=Array.isArray(t.caps)?t.caps:[],o=Array.isArray(t.commands)?t.commands:[];return e`
    <div class="list-item">
      <div class="list-main">
        <div class="list-title">${i}</div>
        <div class="list-sub">
          ${typeof t.nodeId==`string`?t.nodeId:``}
          ${typeof t.remoteIp==`string`?` · ${t.remoteIp}`:``}
          ${typeof t.version==`string`?` · ${t.version}`:``}
        </div>
        <div class="chip-row" style="margin-top: 6px;">
          <span class="chip">${r?`paired`:`unpaired`}</span>
          <span class="chip ${n?`chip-ok`:`chip-warn`}">
            ${n?`connected`:`offline`}
          </span>
          ${a.slice(0,12).map(t=>e`<span class="chip">${String(t)}</span>`)}
          ${o.slice(0,8).map(t=>e`<span class="chip">${String(t)}</span>`)}
        </div>
      </div>
    </div>
  `}export{T as renderNodes};
//# sourceMappingURL=nodes-HNuQJcTZ.js.map