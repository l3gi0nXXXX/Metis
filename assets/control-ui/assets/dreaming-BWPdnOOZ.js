import{f as e,r as t,u as n}from"./i18n-CV7rUnW0.js";var r=/<!--\s*metis:dreaming:diary:start\s*-->/,i=/<!--\s*metis:dreaming:diary:end\s*-->/;function a(e){let t=e,n=r.exec(e),a=i.exec(e);n&&a&&a.index>n.index&&(t=e.slice(n.index+n[0].length,a.index));let o=[],s=t.split(/\n---\n/).filter(e=>e.trim().length>0);for(let e of s){let t=e.trim().split(`
`),n=``,r=[];for(let e of t){let t=e.trim();if(!n&&t.startsWith(`*`)&&t.endsWith(`*`)&&t.length>2){n=t.slice(1,-1);continue}t.startsWith(`#`)||t.startsWith(`<!--`)||t.length>0&&r.push(t)}r.length>0&&o.push({date:n,body:r.join(`
`)})}return o}var o=[`dreaming.phrases.consolidatingMemories`,`dreaming.phrases.tidyingKnowledgeGraph`,`dreaming.phrases.replayingConversations`,`dreaming.phrases.weavingShortTerm`,`dreaming.phrases.defragmentingMindPalace`,`dreaming.phrases.filingLooseThoughts`,`dreaming.phrases.connectingDots`,`dreaming.phrases.compostingContext`,`dreaming.phrases.alphabetizingSubconscious`,`dreaming.phrases.promotingHunches`,`dreaming.phrases.forgettingNoise`,`dreaming.phrases.dreamingEmbeddings`,`dreaming.phrases.reorganizingAttic`,`dreaming.phrases.indexingDay`,`dreaming.phrases.nurturingInsights`,`dreaming.phrases.simmeringIdeas`,`dreaming.phrases.whisperingVectorStore`],s=Math.floor(Math.random()*o.length),c=0,l=6e3,u=`scene`;function d(e){u=e}var f=0,p=0;function m(e){f=Math.max(0,Math.min(e,Math.max(0,p-1)))}function h(){let e=Date.now();return e-c>l&&(c=e,s=(s+1)%o.length),t(o[s]??o[0])}var g=[{top:8,left:15,size:3,delay:0,hue:`neutral`},{top:12,left:72,size:2,delay:1.4,hue:`neutral`},{top:22,left:35,size:3,delay:.6,hue:`accent`},{top:18,left:88,size:2,delay:2.1,hue:`neutral`},{top:35,left:8,size:2,delay:.9,hue:`neutral`},{top:45,left:92,size:2,delay:1.7,hue:`neutral`},{top:55,left:25,size:3,delay:2.5,hue:`accent`},{top:65,left:78,size:2,delay:.3,hue:`neutral`},{top:75,left:45,size:2,delay:1.1,hue:`neutral`},{top:82,left:60,size:3,delay:1.8,hue:`accent`},{top:30,left:55,size:2,delay:.4,hue:`neutral`},{top:88,left:18,size:2,delay:2.3,hue:`neutral`}],_=e`
  <svg viewBox="0 0 120 120" fill="none">
    <defs>
      <linearGradient id="dream-lob-g" x1="0%" y1="0%" x2="100%" y2="100%">
        <stop offset="0%" stop-color="#ff4d4d" />
        <stop offset="100%" stop-color="#991b1b" />
      </linearGradient>
    </defs>
    <path
      d="M60 10C30 10 15 35 15 55C15 75 30 95 45 100L45 110L55 110L55 100C55 100 60 102 65 100L65 110L75 110L75 100C90 95 105 75 105 55C105 35 90 10 60 10Z"
      fill="url(#dream-lob-g)"
    />
    <path d="M20 45C5 40 0 50 5 60C10 70 20 65 25 55C28 48 25 45 20 45Z" fill="url(#dream-lob-g)" />
    <path
      d="M100 45C115 40 120 50 115 60C110 70 100 65 95 55C92 48 95 45 100 45Z"
      fill="url(#dream-lob-g)"
    />
    <path d="M45 15Q38 8 35 14" stroke="#ff4d4d" stroke-width="3" stroke-linecap="round" />
    <path d="M75 15Q82 8 85 14" stroke="#ff4d4d" stroke-width="3" stroke-linecap="round" />
    <path
      d="M39 36Q45 32 51 36"
      stroke="#050810"
      stroke-width="2.5"
      stroke-linecap="round"
      fill="none"
    />
    <path
      d="M69 36Q75 32 81 36"
      stroke="#050810"
      stroke-width="2.5"
      stroke-linecap="round"
      fill="none"
    />
  </svg>
`;function v(n){let r=!n.active,i=n.dreamingOf??h();return e`
    <div class="dreams-page">
      <!-- ── Sub-tab bar ── -->
      <nav class="dreams__tabs">
        <button
          class="dreams__tab ${u===`scene`?`dreams__tab--active`:``}"
          @click=${()=>{u=`scene`,n.onRequestUpdate?.()}}
        >
          ${t(`dreaming.tabs.scene`)}
        </button>
        <button
          class="dreams__tab ${u===`diary`?`dreams__tab--active`:``}"
          @click=${()=>{u=`diary`,n.onRequestUpdate?.()}}
        >
          ${t(`dreaming.tabs.diary`)}
        </button>
      </nav>

      ${u===`scene`?y(n,r,i):b(n)}
    </div>
  `}function y(r,i,a){return e`
    <section class="dreams ${i?`dreams--idle`:``}">
      ${g.map(t=>e`
          <div
            class="dreams__star"
            style="
              top: ${t.top}%;
              left: ${t.left}%;
              width: ${t.size}px;
              height: ${t.size}px;
              background: ${t.hue===`accent`?`var(--accent-muted)`:`var(--text)`};
              animation-delay: ${t.delay}s;
            "
          ></div>
        `)}

      <div class="dreams__moon"></div>

      ${r.active?e`
            <div class="dreams__bubble">
              <span class="dreams__bubble-text">${a}</span>
            </div>
            <div
              class="dreams__bubble-dot"
              style="top: calc(50% - 160px); left: calc(50% - 120px); width: 12px; height: 12px; animation-delay: 0.2s;"
            ></div>
            <div
              class="dreams__bubble-dot"
              style="top: calc(50% - 120px); left: calc(50% - 90px); width: 8px; height: 8px; animation-delay: 0.4s;"
            ></div>
          `:n}

      <div class="dreams__glow"></div>
      <div class="dreams__lobster">${_}</div>
      <span class="dreams__z">z</span>
      <span class="dreams__z">z</span>
      <span class="dreams__z">Z</span>

      <div class="dreams__status">
        <span class="dreams__status-label"
          >${r.active?t(`dreaming.status.active`):t(`dreaming.status.idle`)}</span
        >
        <div class="dreams__status-detail">
          <div class="dreams__status-dot"></div>
          <span>
            ${r.promotedCount} ${t(`dreaming.status.promotedSuffix`)}
            ${r.nextCycle?e`· ${t(`dreaming.status.nextSweepPrefix`)} ${r.nextCycle}`:n}
            ${r.timezone?e`· ${r.timezone}`:n}
          </span>
        </div>
      </div>

      <div class="dreams__stats">
        <div class="dreams__stat">
          <span class="dreams__stat-value" style="color: var(--text-strong);"
            >${r.shortTermCount}</span
          >
          <span class="dreams__stat-label">${t(`dreaming.stats.shortTerm`)}</span>
        </div>
        <div class="dreams__stat-divider"></div>
        <div class="dreams__stat">
          <span class="dreams__stat-value" style="color: var(--accent);"
            >${r.totalSignalCount}</span
          >
          <span class="dreams__stat-label">${t(`dreaming.stats.signals`)}</span>
        </div>
        <div class="dreams__stat-divider"></div>
        <div class="dreams__stat">
          <span class="dreams__stat-value" style="color: var(--accent-2);"
            >${r.phaseSignalCount}</span
          >
          <span class="dreams__stat-label">${t(`dreaming.stats.phaseHits`)}</span>
        </div>
      </div>

      ${r.statusError?e`<div class="dreams__controls-error">${r.statusError}</div>`:n}
    </section>
  `}function b(r){if(r.dreamDiaryError)return e`
      <section class="dreams-diary">
        <div class="dreams-diary__error">${r.dreamDiaryError}</div>
      </section>
    `;if(typeof r.dreamDiaryContent!=`string`)return e`
      <section class="dreams-diary">
        <div class="dreams-diary__empty">
          <div class="dreams-diary__empty-moon">
            <svg viewBox="0 0 32 32" fill="none" width="32" height="32">
              <circle
                cx="16"
                cy="16"
                r="14"
                stroke="currentColor"
                stroke-width="0.5"
                opacity="0.2"
              />
              <path
                d="M20 8a10 10 0 0 1 0 16 10 10 0 1 0 0-16z"
                fill="currentColor"
                opacity="0.08"
              />
            </svg>
          </div>
          <div class="dreams-diary__empty-text">${t(`dreaming.diary.noDreamsYet`)}</div>
          <div class="dreams-diary__empty-hint">${t(`dreaming.diary.noDreamsHint`)}</div>
        </div>
      </section>
    `;let i=a(r.dreamDiaryContent);if(p=i.length,i.length===0)return e`
      <section class="dreams-diary">
        <div class="dreams-diary__empty">
          <div class="dreams-diary__empty-text">${t(`dreaming.diary.waitingTitle`)}</div>
          <div class="dreams-diary__empty-hint">${t(`dreaming.diary.waitingHint`)}</div>
        </div>
      </section>
    `;let o=[...i].toReversed(),s=Math.max(0,Math.min(f,o.length-1)),c=o[s],l=s>0,u=s<o.length-1;return e`
    <section class="dreams-diary">
      <div class="dreams-diary__header">
        <span class="dreams-diary__title">${t(`dreaming.diary.title`)}</span>
        <div class="dreams-diary__nav">
          <button
            class="dreams-diary__nav-btn"
            ?disabled=${!u}
            @click=${()=>{m(s+1),r.onRequestUpdate?.()}}
            title=${t(`dreaming.diary.older`)}
          >
            ‹
          </button>
          <span class="dreams-diary__page">${s+1} / ${o.length}</span>
          <button
            class="dreams-diary__nav-btn"
            ?disabled=${!l}
            @click=${()=>{m(s-1),r.onRequestUpdate?.()}}
            title=${t(`dreaming.diary.newer`)}
          >
            ›
          </button>
        </div>
        <button
          class="btn btn--subtle btn--sm"
          ?disabled=${r.modeSaving||r.dreamDiaryLoading}
          @click=${()=>{f=0,r.onRefreshDiary()}}
        >
          ${r.dreamDiaryLoading?t(`dreaming.diary.reloading`):t(`dreaming.diary.reload`)}
        </button>
      </div>

      <article class="dreams-diary__entry" key="${s}">
        <div class="dreams-diary__accent"></div>
        ${c.date?e`<time class="dreams-diary__date">${c.date}</time>`:n}
        <div class="dreams-diary__prose">
          ${c.body.split(`
`).map((t,n)=>e`<p class="dreams-diary__para" style="animation-delay: ${.3+n*.15}s;">
                  ${t}
                </p>`)}
        </div>
      </article>
    </section>
  `}export{v as renderDreaming,m as setDiaryPage,d as setDreamSubTab};
//# sourceMappingURL=dreaming-BWPdnOOZ.js.map