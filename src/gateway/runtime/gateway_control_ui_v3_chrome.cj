package metis.gateway.runtime

public func gatewayBuildControlUiV3ChromeScript(): String {
    """
  function buildAppearanceSection(data, currentTab) {
    const tf = (function(){ try { return localStorage.getItem('cj_v3_theme_family') || 'claw'; } catch(_e){ return 'claw'; } })();
    const rad = (function(){ try { return localStorage.getItem('cj_v3_radius') || 'default'; } catch(_e){ return 'default'; } })();
    const tmPref = (function(){ try { return localStorage.getItem('cj_v3_theme_mode') || 'system'; } catch(_e){ return 'system'; } })();
    function ocThemeFamilyCard(id, label, hint, iconName, activeId) {
      var on = (activeId === id);
      return '<button type="button" class="settings-theme-card' + (on ? ' settings-theme-card--active' : '') + '" data-theme-family="' + id + '" title="' + hint.replace(/"/g, '&quot;') + '">' +
        '<span class="settings-theme-card__icon" aria-hidden="true">' + svgIcon(iconName) + '</span>' +
        '<span class="settings-theme-card__label">' + label + '</span>' +
        (on ? '<span class="settings-theme-card__check" aria-hidden="true">' + svgIcon('check') + '</span>' : '') +
        '</button>';
    }
    function ocThemeModeCard(id, label, hint, iconName, activeId) {
      var on = (activeId === id);
      return '<button type="button" class="settings-theme-card' + (on ? ' settings-theme-card--active' : '') + '" data-theme-mode-pref="' + id + '" title="' + hint.replace(/"/g, '&quot;') + '">' +
        '<span class="settings-theme-card__icon" aria-hidden="true">' + svgIcon(iconName) + '</span>' +
        '<span class="settings-theme-card__label">' + label + '</span>' +
        (on ? '<span class="settings-theme-card__check" aria-hidden="true">' + svgIcon('check') + '</span>' : '') +
        '</button>';
    }
    function ocRadiusCard(id, label, hint, iconName, activeId) {
      var on = (activeId === id);
      return '<button type="button" class="settings-theme-card' + (on ? ' settings-theme-card--active' : '') + '" data-radius="' + id + '" title="' + hint.replace(/"/g, '&quot;') + '">' +
        '<span class="settings-theme-card__icon" aria-hidden="true">' + svgIcon(iconName) + '</span>' +
        '<span class="settings-theme-card__label">' + label + '</span>' +
        (on ? '<span class="settings-theme-card__check" aria-hidden="true">' + svgIcon('check') + '</span>' : '') +
        '</button>';
    }
    const gw = data.gateway || {};
    const dash = data.dashboard || {};
    const gwRunning = !!gw.running;
    const gwStatusText = gwRunning ? 'Connected' : 'Offline';
    const gwDotClass = gwRunning ? 'settings-status-dot settings-status-dot--ok' : 'settings-status-dot';
    const modelName = String(data.model || '--').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    const connWs = String(dash.wsUrl || '').replace(/</g, '&lt;').replace(/>/g, '&gt;') || DASHBOARD_WS_FALLBACK;
    return '<section class="appearance-shell" data-tab-panel="appearance" style="' + (currentTab === 'appearance' ? '' : 'display:none;') + '">' +
      '<div class="appearance-page">' +
        '<div class="appearance-subtabs">' +
          '<button type="button" class="appearance-subtab appearance-subtab--active" data-ap-sub="appearance">Appearance</button>' +
          '<button type="button" class="appearance-subtab" data-ap-sub="ui">UI</button>' +
          '<button type="button" class="appearance-subtab" data-ap-sub="wizard">Setup Wizard</button>' +
        '</div>' +
        '<div class="appearance-panel" data-ap-panel="appearance">' +
          '<div class="settings-appearance">' +
            '<div class="settings-appearance__section">' +
              '<h3 class="settings-appearance__heading">Theme</h3>' +
              '<p class="settings-appearance__hint">Choose a theme family.</p>' +
              '<div class="settings-theme-grid">' +
                ocThemeFamilyCard('claw', 'Claw', 'Chroma family', 'zap', tf) +
                ocThemeFamilyCard('knot', 'Knot', 'Knot family', 'link', tf) +
                ocThemeFamilyCard('dash', 'Dash', 'Field family', 'barChart', tf) +
              '</div>' +
            '</div>' +
            '<div class="settings-appearance__section">' +
              '<h3 class="settings-appearance__heading">Mode</h3>' +
              '<p class="settings-appearance__hint">Choose light or dark mode for the selected theme.</p>' +
              '<div class="settings-theme-grid">' +
                ocThemeModeCard('system', 'System', 'Follow OS light or dark', 'monitor', tmPref) +
                ocThemeModeCard('light', 'Light', 'Force light mode', 'sun', tmPref) +
                ocThemeModeCard('dark', 'Dark', 'Force dark mode', 'moon', tmPref) +
              '</div>' +
            '</div>' +
            '<div class="settings-appearance__section">' +
              '<h3 class="settings-appearance__heading">Roundness</h3>' +
              '<p class="settings-appearance__hint">Adjust corner radius across the UI.</p>' +
              '<div class="settings-theme-grid">' +
                ocRadiusCard('none', 'None', 'Sharp corners', 'radiusNone', rad) +
                ocRadiusCard('slight', 'Slight', 'Subtle rounding', 'radiusSlight', rad) +
                ocRadiusCard('default', 'Default', 'Balanced rounding', 'radiusDefault', rad) +
                ocRadiusCard('round', 'Round', 'Strong rounding', 'radiusRound', rad) +
                ocRadiusCard('full', 'Full', 'Pill-shaped controls', 'radiusFull', rad) +
              '</div>' +
            '</div>' +
            '<div class="settings-appearance__section">' +
              '<h3 class="settings-appearance__heading">Connection</h3>' +
              '<div class="settings-info-grid">' +
                '<div class="settings-info-row">' +
                  '<span class="settings-info-row__label">Gateway</span>' +
                  '<span class="settings-info-row__value mono">' + connWs + '</span>' +
                '</div>' +
                '<div class="settings-info-row">' +
                  '<span class="settings-info-row__label">Status</span>' +
                  '<span class="settings-info-row__value"><span class="' + gwDotClass + '"></span>' + gwStatusText + '</span>' +
                '</div>' +
                '<div class="settings-info-row">' +
                  '<span class="settings-info-row__label">Assistant</span>' +
                  '<span class="settings-info-row__value">' + modelName + '</span>' +
                '</div>' +
              '</div>' +
            '</div>' +
          '</div>' +
        '</div>' +
        '<div class="appearance-panel" data-ap-panel="ui" style="display:none;">' +
          '<div class="settings-appearance">' +
            '<div class="settings-appearance__section">' +
              '<h3 class="settings-appearance__heading">UI</h3>' +
              '<p class="settings-appearance__hint">Additional UI settings (not connected yet).</p>' +
              '<p class="muted" style="margin-top:10px;font-size:13px;">--</p>' +
            '</div>' +
          '</div>' +
        '</div>' +
        '<div class="appearance-panel" data-ap-panel="wizard" style="display:none;">' +
          '<div class="settings-appearance">' +
            '<div class="settings-appearance__section">' +
              '<h3 class="settings-appearance__heading">Setup Wizard</h3>' +
              '<p class="settings-appearance__hint">Wizard last run metadata (placeholder).</p>' +
              '<div class="appearance-wizard-meta">' +
                '<div><span class="muted">Wizard Last Run Timestamp:</span> <span class="mono">--</span> <span class="chip">advanced</span></div>' +
                '<div><span class="muted">Wizard Last Run Command:</span></div>' +
                '<div class="appearance-wizard-box">--</div>' +
              '</div>' +
            '</div>' +
          '</div>' +
        '</div>' +
      '</div>' +
    '</section>';
  }

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

  function applyV3AppearanceClasses() {
    var el = document.querySelector('.oc-root');
    if (!el) return;
    var tf = 'claw';
    var rad = 'default';
    try { tf = localStorage.getItem('cj_v3_theme_family') || 'claw'; } catch (_e) {}
    try { rad = localStorage.getItem('cj_v3_radius') || 'default'; } catch (_e) {}
    el.classList.remove('theme-family-claw', 'theme-family-knot', 'theme-family-dash');
    el.classList.add('theme-family-' + tf);
    el.classList.remove('appearance-radius-none', 'appearance-radius-slight', 'appearance-radius-default', 'appearance-radius-round', 'appearance-radius-full');
    el.classList.add('appearance-radius-' + rad);
    applyV3ThemeMode();
  }

  function wireAppearancePageV3() {
    if (uiVariant !== 'v3') return;
    if (document.body.__v3AppearanceDelegated) return;
    document.body.__v3AppearanceDelegated = true;
    document.body.addEventListener('click', function(e) {
      if (uiVariant !== 'v3') return;
      var host = document.querySelector('.oc-root');
      if (!host || !e.target || !host.contains(e.target)) return;
      var sub = e.target.closest ? e.target.closest('.appearance-subtab') : null;
      if (sub) {
        var id = sub.getAttribute('data-ap-sub') || '';
        host.querySelectorAll('.appearance-subtab').forEach(function(x) {
          x.classList.toggle('appearance-subtab--active', (x.getAttribute('data-ap-sub') || '') === id);
        });
        host.querySelectorAll('[data-ap-panel]').forEach(function(p) {
          var pid = p.getAttribute('data-ap-panel') || '';
          p.style.display = (pid === id) ? '' : 'none';
        });
        return;
      }
      var tt = e.target.closest ? e.target.closest('.settings-theme-card[data-theme-family]') : null;
      if (tt) {
        var v = tt.getAttribute('data-theme-family') || 'claw';
        try { localStorage.setItem('cj_v3_theme_family', v); } catch (_e) {}
        host.querySelectorAll('.settings-theme-card[data-theme-family]').forEach(function(t2) {
          var on = (t2.getAttribute('data-theme-family') || '') === v;
          t2.classList.toggle('settings-theme-card--active', on);
          var chk = t2.querySelector('.settings-theme-card__check');
          if (on && !chk) {
            var span = document.createElement('span');
            span.className = 'settings-theme-card__check';
            span.setAttribute('aria-hidden', 'true');
            span.innerHTML = svgIcon('check');
            t2.appendChild(span);
          } else if (!on && chk) {
            chk.remove();
          }
        });
        applyV3AppearanceClasses();
        return;
      }
      var mt = e.target.closest ? e.target.closest('.settings-theme-card[data-theme-mode-pref]') : null;
      if (mt) {
        var m = mt.getAttribute('data-theme-mode-pref') || 'system';
        try { localStorage.setItem('cj_v3_theme_mode', m); } catch (_e2) {}
        host.querySelectorAll('.settings-theme-card[data-theme-mode-pref]').forEach(function(t2) {
          var on = (t2.getAttribute('data-theme-mode-pref') || '') === m;
          t2.classList.toggle('settings-theme-card--active', on);
          var chk = t2.querySelector('.settings-theme-card__check');
          if (on && !chk) {
            var span = document.createElement('span');
            span.className = 'settings-theme-card__check';
            span.setAttribute('aria-hidden', 'true');
            span.innerHTML = svgIcon('check');
            t2.appendChild(span);
          } else if (!on && chk) {
            chk.remove();
          }
        });
        applyV3AppearanceClasses();
        return;
      }
      var rt = e.target.closest ? e.target.closest('.settings-theme-card[data-radius]') : null;
      if (rt) {
        var r = rt.getAttribute('data-radius') || 'default';
        try { localStorage.setItem('cj_v3_radius', r); } catch (_e3) {}
        host.querySelectorAll('.settings-theme-card[data-radius]').forEach(function(t2) {
          var on = (t2.getAttribute('data-radius') || '') === r;
          t2.classList.toggle('settings-theme-card--active', on);
          var chk = t2.querySelector('.settings-theme-card__check');
          if (on && !chk) {
            var span = document.createElement('span');
            span.className = 'settings-theme-card__check';
            span.setAttribute('aria-hidden', 'true');
            span.innerHTML = svgIcon('check');
            t2.appendChild(span);
          } else if (!on && chk) {
            chk.remove();
          }
        });
        applyV3AppearanceClasses();
      }
    });
  }

  function wireCommSubtabsV3() {
    if (uiVariant !== 'v3') return;
    if (document.body.__v3CommSubDelegated) return;
    document.body.__v3CommSubDelegated = true;
    document.body.addEventListener('click', function(e) {
      if (uiVariant !== 'v3') return;
      const btn = (e.target && e.target.closest) ? e.target.closest('.comm-subtab') : null;
      if (!btn) return;
      const root = document.querySelector('.oc-root');
      if (!root || !root.contains(btn)) return;
      const id = btn.getAttribute('data-comm-sub') || '';
      if (!id) return;
      try { localStorage.setItem('cj_v3_comm_sub', id); } catch (_e) {}
      if (lastStatusData) renderShell(lastStatusData);
    });
  }
"""
}
