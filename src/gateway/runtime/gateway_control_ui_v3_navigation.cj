package metis.gateway.runtime

public func gatewayBuildControlUiV3NavigationScript(): String {
    """

  function renderV3Header(tab, ctx) {
    const host = document.getElementById('v3-header-host');
    if (!host) return;
    const sessionOptions = (ctx && ctx.sessionOptions) ? ctx.sessionOptions : '';

    if (tab === 'cron') {
      host.innerHTML =
        '<div style="min-width:0">' +
          '<div class="page-title">Metis · 定时任务</div>' +
          '<div class="page-sub">唤醒和重复运行</div>' +
        '</div>' +
        '<div class="page-meta"></div>';
      return;
    }

    if (tab === 'sessions') {
      host.innerHTML =
        '<div style="min-width:0">' +
          '<div class="page-title">会话</div>' +
          '<div class="page-sub">活动会话和默认设置。</div>' +
        '</div>' +
        '<div class="page-meta"></div>';
      return;
    }

    if (tab === 'appearance') {
      host.innerHTML =
        '<div style="min-width:0;flex:1">' +
          '<div class="page-title">外观与设置</div>' +
          '<div class="page-sub">主题、界面和设置向导设置。</div>' +
        '</div>' +
        '<div class="appearance-header-actions">' +
          '<button type="button" class="btn btn--sm" disabled title="未接入">Open</button>' +
          '<button type="button" class="btn btn--sm" disabled title="未接入">Reload</button>' +
          '<button type="button" class="btn btn--sm primary" disabled title="未接入">Save</button>' +
          '<button type="button" class="btn btn--sm" disabled title="未接入">Apply</button>' +
          '<button type="button" class="btn btn--sm" disabled title="未接入">Update</button>' +
        '</div>';
      return;
    }

    if (tab === 'comm') {
      host.innerHTML =
        '<div style="min-width:0;flex:1">' +
          '<div class="comm-breadcrumb muted">Metis / 通信</div>' +
          '<div class="page-title">通信</div>' +
          '<div class="page-sub">频道、消息和音频设置。</div>' +
        '</div>' +
        '<div class="comm-toolbar">' +
          '<div class="topbar-search comm-toolbar__search" aria-hidden="true">' +
            '<span class="nav-item__icon" style="opacity:0.72">' + svgIcon('search') + '</span>' +
            '<span class="topbar-search__label muted">Search settings...</span>' +
          '</div>' +
          '<div class="appearance-header-actions">' +
            '<button type="button" class="btn btn--sm" disabled title="未接入">Open</button>' +
            '<button type="button" class="btn btn--sm" disabled title="未接入">Reload</button>' +
            '<button type="button" class="btn btn--sm primary" disabled title="未接入">Save</button>' +
            '<button type="button" class="btn btn--sm" disabled title="未接入">Apply</button>' +
            '<button type="button" class="btn btn--sm" disabled title="未接入">Update</button>' +
          '</div>' +
        '</div>';
      return;
    }

    if (tab === 'chat') {
      host.innerHTML =
        '<div style="min-width:0">' +
          '<div class="chat-controls">' +
            '<div class="chat-controls__session">' +
              '<select id="chat-session-select" aria-label="Session">' +
                (sessionOptions || '') +
              '</select>' +
            '</div>' +
            '<div class="chat-controls__model" id="model-select-host"><span class="muted">加载模型...</span></div>' +
          '</div>' +
        '</div>' +
        '<div class="page-meta"></div>';
      wireChatSessionSelect();
      loadModelsWidget().catch(function(e){ console.warn(e); });
      return;
    }

    const titleMap = {
      overview: '概览',
      channels: '频道',
      instances: '实例',
      skills: '技能',
      usage: '使用情况',
      cron: '定时任务',
      agentHome: '代理',
      nodes: '节点',
      config: '配置',
      comm: '通信',
      automation: '自动化',
      infra: '基础设施',
      aiAgents: 'AI 与 代理',
      debug: '调试',
      logs: '日志',
      appearance: '外观与设置'
    };
    const title = titleMap[tab] || '';
    host.innerHTML =
      '<div style="min-width:0">' +
        '<div class="page-title">' + (title || '') + '</div>' +
        '<div class="page-sub"></div>' +
      '</div>' +
      '<div class="page-meta"></div>';
  }

  function wireRefreshBtnV3Sessions() {
    const b = document.getElementById('refresh-btn-sessions');
    if (!b) return;
    b.onclick = function() {
      loadStatus().catch(function(err) { console.warn(err); });
    };
  }

  function wireRefreshBtnV3Skills() {
    const b = document.getElementById('refresh-btn-skills');
    if (!b) return;
    b.onclick = function() {
      loadStatus().catch(function(err) { console.warn(err); });
    };
  }

  function wireV3NavSectionToggle() {
    const host = document.querySelector('.oc-root');
    if (!host || host.__v3NavSectionToggle) return;
    host.__v3NavSectionToggle = true;
    host.addEventListener('click', function(e) {
      const head = (e.target && e.target.closest) ? e.target.closest('.nav-section__head') : null;
      if (!head) return;
      e.preventDefault();
      const sec = head.closest ? head.closest('.nav-section--collapsible') : null;
      if (!sec) return;
      sec.classList.toggle('nav-section--collapsed');
      var collapsed = sec.classList.contains('nav-section--collapsed');
      head.setAttribute('aria-expanded', collapsed ? 'false' : 'true');
      try {
        var k = sec.getAttribute('data-nav-section') || '';
        if (k) localStorage.setItem('cj_v3_nav_section_' + k, collapsed ? '1' : '0');
      } catch (_e) {}
    });
  }

  function syncV3MainLayoutClass(tab) {
    const main = document.getElementById('oc-main');
    if (!main) return;
    if (tab === 'chat') {
      main.classList.add('content--chat');
    } else {
      main.classList.remove('content--chat');
    }
    if (tab === 'cron') {
      main.classList.add('content--cron');
    } else {
      main.classList.remove('content--cron');
    }
  }

  function wireV3NavClicks() {
    const host = document.querySelector('.oc-root');
    if (!host) return;
    host.addEventListener('click', function(e) {
      const btn = (e.target && e.target.closest) ? e.target.closest('.nav-item') : null;
      if (!btn) return;
      const tab = btn.getAttribute('data-tab') || '';
      if (!tab) return;
      currentTab = tab;
      syncV3MainLayoutClass(tab);
      renderV3Header(tab, { sessionOptions: v3SessionOptionsHtml || '' });
      const items = host.querySelectorAll('.nav-item');
      items.forEach(function(n) {
        const t = n.getAttribute('data-tab') || '';
        if (t === tab) n.classList.add('nav-item--active'); else n.classList.remove('nav-item--active');
      });
      const panels = host.querySelectorAll('[data-tab-panel]');
      panels.forEach(function(p) {
        const t = p.getAttribute('data-tab-panel') || '';
        p.style.display = (t === tab) ? '' : 'none';
      });
      if (tab === 'chat') {
        loadHistory(true).catch(function(err){ console.warn(err); });
      }
    });
  }

"""
}
