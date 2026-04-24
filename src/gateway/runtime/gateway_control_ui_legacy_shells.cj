package metis.gateway.runtime

public func gatewayBuildControlUiLegacyShellsScript(): String {
    """
  // V1: 当前版本（作为备份保留）
  function renderShellV1(data) {
    const oldInput = document.getElementById('chat-input');
    const oldInputValue = oldInput ? (oldInput.value || '') : '';
    const wasFocused = !!oldInput && (document.activeElement === oldInput);
    const oldStart = wasFocused && typeof oldInput.selectionStart === 'number' ? oldInput.selectionStart : -1;
    const oldEnd = wasFocused && typeof oldInput.selectionEnd === 'number' ? oldInput.selectionEnd : -1;

    const cm = data.gateway.channelModels || {};
    const cmItems = Object.entries(cm).map(function(entry) {
      return '<li><code>' + entry[0] + ' -> ' + entry[1] + '</code></li>';
    }).join('');
    const skillItems = (data.skills || []).map(function(s) {
      return '<li><code>' + s + '</code></li>';
    }).join('');
    const skillsHtml = skillItems ? '<ul>' + skillItems + '</ul>' : '<div class="muted">未发现任何 skill。</div>';
    const cmHtml = cmItems
      ? '<div style="margin-top:6px">channelModels:</div><ul>' + cmItems + '</ul>'
      : '';
    const sessions = (data.sessions && data.sessions.recent) ? data.sessions.recent : [];
    const detailsArr = (data.sessions && data.sessions.details) ? data.sessions.details : [];
    const detailsMap = {};
    detailsArr.forEach(function(d) {
      if (d && d.key) detailsMap[d.key] = d;
    });
    const sessionItems = sessions.map(function(s) {
      const active = (s === currentSession);
      const cls = 'session-item' + (active ? ' session-item-active' : '');
      const kind = sessionKind(s);
      const d = detailsMap[s] || {};
      const tsText = formatTs(d.updatedTs || '');
      return '<div class="' + cls + '" data-session="' + s.replace(/"/g, '&quot;') + '">' +
             '<div class="session-meta"><span class="session-kind">' + kind + '</span>session</div>' +
             '<div class="session-title"><code>' + s + '</code></div>' +
             '<div class="session-stats">' +
               '<span class="session-stat">messages ' + (d.messageCount || 0) + '</span>' +
               '<span class="session-stat">tokens ~ ' + (d.tokenApprox || 0) + '</span>' +
             '</div>' +
             '<div class="session-updated">updated ' + (tsText || '--') + '</div>' +
             '</div>';
    }).join('');
    const logItems = (((data.logs && data.logs.tail) ? data.logs.tail : [])).map(function(s) {
      return '<li><code>' + s + '</code></li>';
    }).join('');

    const html =
      '<div class="layout">' +
        '<div class="col-left">' +
          '<div class="card">' +
            '<div class="left-shell">' +
              '<div class="tabs">' +
                '<button class="tab-btn" data-tab="sessions">Sessions</button>' +
                '<button class="tab-btn" data-tab="model">Model</button>' +
                '<button class="tab-btn" data-tab="gateway">Gateway</button>' +
                '<button class="tab-btn" data-tab="skills">Skills</button>' +
                '<button class="tab-btn" data-tab="logs">Logs</button>' +
                '<button class="tab-btn" data-tab="appearance">Appearance</button>' +
                '<button class="tab-btn btn-small-muted" id="refresh-btn">Refresh</button>' +
              '</div>' +
              '<div class="tab-content">' +
                '<div class="tab-panel" data-tab="sessions">' +
                  '<h2>Sessions</h2>' +
                  '<div style="font-size:16px;">count: <code>' + ((data.sessions && data.sessions.count) ? data.sessions.count : 0) + '</code></div>' +
                  '<div style="font-size:16px;">root: <code>' + ((data.sessions && data.sessions.root) ? data.sessions.root : '') + '</code></div>' +
                  '<div class="session-list" id="session-list">' +
                    (sessionItems || '<div class="muted" style="margin-top:6px;">暂无会话。</div>') +
                  '</div>' +
                '</div>' +
                '<div class="tab-panel" data-tab="model">' +
                  '<h2>Model</h2>' +
                  '<div style="font-size:13px;">Current: <code>' + data.model + '</code></div>' +
                  '<div id="model-select-host" style="margin-top:6px;"><span class="muted">加载中...</span></div>' +
                '</div>' +
                '<div class="tab-panel" data-tab="gateway">' +
                  '<h2>Gateway</h2>' +
                  '<div style="font-size:12px;">gateway.enabled = <code>' + data.gateway.enabled + '</code></div>' +
                  '<div style="font-size:12px;">gateway.running = <code>' + data.gateway.running + '</code></div>' +
                  '<div style="font-size:12px;">feishu.enabled = <code>' + data.gateway.feishuEnabled + '</code></div>' +
                  '<div style="font-size:12px;">qq.enabled = <code>' + data.gateway.qqEnabled + '</code></div>' +
                  '<div style="font-size:12px;">telegram.enabled = <code>' + data.gateway.telegramEnabled + '</code></div>' +
                  cmHtml +
                '</div>' +
                '<div class="tab-panel" data-tab="skills">' +
                  '<h2>Skills</h2>' +
                  '<div style="font-size:12px;">skills.enabled = <code>' + data.skillsEnabled + '</code></div>' +
                  skillsHtml +
                '</div>' +
                '<div class="tab-panel" data-tab="logs">' +
                  '<h2>Logs</h2>' +
                  '<div style="font-size:12px;">latest: <code>' + ((data.logs && data.logs.latestFile) ? data.logs.latestFile : '') + '</code></div>' +
                  '<ul class="logs-list">' +
                    (logItems || '<li class="muted">暂无日志。</li>') +
                  '</ul>' +
                '</div>' +
                '<div class="tab-panel" data-tab="appearance">' +
                  '<h2>Appearance</h2>' +
                  '<div class="muted" style="font-size:12px;">选择主题色，自动记住下次打开：</div>' +
                  '<div class="theme-palette">' +
                    '<button class="theme-btn" data-theme="slate"><span class="theme-dot" style="background:#0ea5e9"></span>Slate</button>' +
                    '<button class="theme-btn" data-theme="emerald"><span class="theme-dot" style="background:#10b981"></span>Emerald</button>' +
                    '<button class="theme-btn" data-theme="violet"><span class="theme-dot" style="background:#8b5cf6"></span>Violet</button>' +
                    '<button class="theme-btn" data-theme="amber"><span class="theme-dot" style="background:#f59e0b"></span>Amber</button>' +
                  '</div>' +
                '</div>' +
              '</div>' +
            '</div>' +
          '</div>' +
        '</div>' +
        '<div class="col-main">' +
          '<div class="card" style="flex:1; display:flex; flex-direction:column; min-height:320px;">' +
            '<h2>Chat</h2>' +
            '<div class="chat-box" id="chat-box">' +
              '<div class="muted">请选择左侧会话后开始对话。</div>' +
            '</div>' +
            '<div class="chat-input-row">' +
              '<textarea id="chat-input" placeholder="在此输入你的问题，回车发送（Ctrl+Enter 换行）"></textarea>' +
              '<button id="chat-send-btn">发送</button>' +
            '</div>' +
          '</div>' +
        '</div>' +
      '</div>';

    document.getElementById('root').innerHTML = html;
    wireSessionClicks();
    wireChatSessionSelect();
    wireChatInput();
    wireRefreshBtn();
    wireTabClicks();
    wireThemeButtons();
    switchTab(currentTab || 'sessions');
    applyTheme((document.body && document.body.getAttribute('data-theme')) || 'slate');

    const newInput = document.getElementById('chat-input');
    if (newInput) {
      newInput.value = oldInputValue;
      if (wasFocused) {
        newInput.focus();
        if (oldStart >= 0 && oldEnd >= 0 && typeof newInput.setSelectionRange === 'function') {
          try {
            newInput.setSelectionRange(oldStart, oldEnd);
          } catch (_e) {}
        }
      }
    }
  }

  function renderShellV2(data) {
    const isV3 = uiVariant === 'v3';
    const labelChat = isV3 ? '聊天' : 'Chat';
    const labelSessions = isV3 ? '会话' : 'Sessions';
    const labelModel = isV3 ? '模型' : 'Model';
    const labelGateway = isV3 ? '网关' : 'Gateway';
    const labelSkills = isV3 ? '技能' : 'Skills';
    const labelLogs = isV3 ? '日志' : 'Logs';
    const labelAppearance = isV3 ? '外观' : 'Appearance';
    const labelRefresh = isV3 ? '刷新' : 'Refresh';

    const oldInput = document.getElementById('chat-input');
    const oldInputValue = oldInput ? (oldInput.value || '') : '';
    const wasFocused = !!oldInput && (document.activeElement === oldInput);
    const oldStart = wasFocused && typeof oldInput.selectionStart === 'number' ? oldInput.selectionStart : -1;
    const oldEnd = wasFocused && typeof oldInput.selectionEnd === 'number' ? oldInput.selectionEnd : -1;

    const cm = data.gateway.channelModels || {};
    const cmItems = Object.entries(cm).map(function(entry) {
      return '<li><code>' + entry[0] + ' -> ' + entry[1] + '</code></li>';
    }).join('');
    const skillItems = (data.skills || []).map(function(s) {
      return '<li><code>' + s + '</code></li>';
    }).join('');
    const skillsHtml = skillItems ? '<ul>' + skillItems + '</ul>' : '<div class="muted">未发现任何 skill。</div>';
    const sessions = (data.sessions && data.sessions.recent) ? data.sessions.recent : [];
    const detailsArr = (data.sessions && data.sessions.details) ? data.sessions.details : [];
    const detailsMap = {};
    detailsArr.forEach(function(d) { if (d && d.key) detailsMap[d.key] = d; });
    const sessionsSorted = sessions.slice().sort(function(a, b) {
      const ta = Number((detailsMap[a] && detailsMap[a].updatedTs) || 0);
      const tb = Number((detailsMap[b] && detailsMap[b].updatedTs) || 0);
      return tb - ta;
    });
    const filteredSessions = sessionsSorted.filter(function(s) {
      if (sessionsSourceFilter === 'all') return true;
      return sessionKind(s) === sessionsSourceFilter;
    });
    const sessionItems = filteredSessions.map(function(s) {
      const active = (s === currentSession);
      const cls = 'session-item' + (active ? ' session-item-active' : '');
      const kind = sessionKind(s);
      const d = detailsMap[s] || {};
      const tsText = formatTs(d.updatedTs || '');
      return '<div class="' + cls + '" data-session="' + s.replace(/"/g, '&quot;') + '">' +
             '<div class="session-meta"><span class="session-kind">' + kind + '</span>session</div>' +
             '<div class="session-title"><code>' + s + '</code></div>' +
             '<div class="session-stats">' +
               '<span class="session-stat">messages ' + (d.messageCount || 0) + '</span>' +
               '<span class="session-stat">tokens ~ ' + (d.tokenApprox || 0) + '</span>' +
             '</div>' +
             '<div class="session-updated">updated ' + (tsText || '--') + '</div>' +
             '</div>';
    }).join('');
    const logItems = (((data.logs && data.logs.tail) ? data.logs.tail : [])).map(function(s) {
      return '<li><code>' + s + '</code></li>';
    }).join('');

    const sessionOptions = sessions.map(function(s) {
      const sel = (s === currentSession) ? ' selected' : '';
      return '<option value="' + s.replace(/"/g, '&quot;') + '"' + sel + '>' + s + '</option>';
    }).join('');

    const html =
      '<div class="layout">' +
        '<div class="col-left">' +
          '<div class="card">' +
            '<div class="tabs">' +
              '<button class="tab-btn" data-tab="chat">' + labelChat + '</button>' +
              '<button class="tab-btn" data-tab="sessions">' + labelSessions + '</button>' +
              '<button class="tab-btn" data-tab="model">' + labelModel + '</button>' +
              '<button class="tab-btn" data-tab="gateway">' + labelGateway + '</button>' +
              '<button class="tab-btn" data-tab="skills">' + labelSkills + '</button>' +
              '<button class="tab-btn" data-tab="logs">' + labelLogs + '</button>' +
              '<button class="tab-btn" data-tab="appearance">' + labelAppearance + '</button>' +
              '<button class="tab-btn btn-small-muted" id="refresh-btn">' + labelRefresh + '</button>' +
            '</div>' +
          '</div>' +
        '</div>' +
        '<div class="col-main">' +
          '<div class="card tab-panel" data-tab="chat">' +
            '<h2>' + labelChat + '</h2>' +
            '<div style="font-size:12px;">当前会话</div>' +
            '<select id="chat-session-select" class="model-select">' +
              (sessionOptions || '') +
            '</select>' +
            '<div class="muted" style="font-size:12px;margin-top:4px;">可在下拉中切换会话；详细列表见 Sessions 页签。</div>' +
            '<div class="chat-box" id="chat-box" style="margin-top:8px;">' +
              '<div class="muted">请选择上方会话后开始对话。</div>' +
            '</div>' +
            '<div class="chat-input-row">' +
              '<textarea id="chat-input" placeholder="在此输入你的问题，回车发送（Ctrl+Enter 换行）"></textarea>' +
              '<button id="chat-send-btn">发送</button>' +
            '</div>' +
          '</div>' +
          '<div class="card tab-panel" data-tab="sessions">' +
            '<h2>' + labelSessions + '</h2>' +
            '<div style="font-size:16px;">count: <code>' + ((data.sessions && data.sessions.count) ? data.sessions.count : 0) + '</code></div>' +
            '<div style="font-size:16px;">root: <code>' + ((data.sessions && data.sessions.root) ? data.sessions.root : '') + '</code></div>' +
            '<div style="display:flex;gap:8px;align-items:center;margin-top:8px;">' +
              '<span class="muted" style="font-size:12px;">来源</span>' +
              '<select id="sessions-source-filter" class="model-select" style="max-width:180px;margin-top:0;">' +
                '<option value="all">all</option>' +
                '<option value="qq">qq</option>' +
                '<option value="feishu">feishu</option>' +
                '<option value="cli">cli</option>' +
              '</select>' +
              '<span class="muted" style="font-size:12px;">排序: 最近更新时间↓</span>' +
            '</div>' +
            '<div class="session-list" id="session-list-v2">' +
              (sessionItems || '<div class="muted" style="margin-top:6px;">暂无会话。</div>') +
            '</div>' +
          '</div>' +
          '<div class="card tab-panel" data-tab="model">' +
            '<h2>' + labelModel + '</h2>' +
            '<div style="font-size:13px;">Current: <code>' + data.model + '</code></div>' +
            '<div id="model-select-host" style="margin-top:6px;"><span class="muted">加载中...</span></div>' +
          '</div>' +
          '<div class="card tab-panel" data-tab="gateway">' +
            '<h2>' + labelGateway + '</h2>' +
            '<div style="font-size:12px;">gateway.enabled = <code>' + data.gateway.enabled + '</code></div>' +
            '<div style="font-size:12px;">gateway.running = <code>' + data.gateway.running + '</code></div>' +
            '<div style="font-size:12px;">feishu.enabled = <code>' + data.gateway.feishuEnabled + '</code></div>' +
            '<div style="font-size:12px;">qq.enabled = <code>' + data.gateway.qqEnabled + '</code></div>' +
            '<div style="font-size:12px;">telegram.enabled = <code>' + data.gateway.telegramEnabled + '</code></div>' +
            (cmItems ? '<div style="margin-top:6px">channelModels:</div><ul>' + cmItems + '</ul>' : '<div class="muted">暂无 channelModels。</div>') +
          '</div>' +
          '<div class="card tab-panel" data-tab="skills">' +
            '<h2>' + labelSkills + '</h2>' +
            '<div style="font-size:12px;">skills.enabled = <code>' + data.skillsEnabled + '</code></div>' +
            '<input id="skills-search" class="model-select" placeholder="搜索 skills..." style="margin-top:8px;" />' +
            '<div id="skills-list-host" style="margin-top:8px;">' + skillsHtml + '</div>' +
          '</div>' +
          '<div class="card tab-panel" data-tab="logs">' +
            '<h2>' + labelLogs + '</h2>' +
            '<div style="font-size:12px;">latest: <code>' + ((data.logs && data.logs.latestFile) ? data.logs.latestFile : '') + '</code></div>' +
            '<ul class="logs-list">' +
              (logItems || '<li class="muted">暂无日志。</li>') +
            '</ul>' +
          '</div>' +
          '<div class="card tab-panel" data-tab="appearance">' +
            '<h2>' + labelAppearance + '</h2>' +
            '<div class="muted" style="font-size:12px;">选择主题色，自动记住下次打开：</div>' +
            '<div class="theme-palette">' +
              '<button class="theme-btn" data-theme="slate"><span class="theme-dot" style="background:#0ea5e9"></span>Slate</button>' +
              '<button class="theme-btn" data-theme="emerald"><span class="theme-dot" style="background:#10b981"></span>Emerald</button>' +
              '<button class="theme-btn" data-theme="violet"><span class="theme-dot" style="background:#8b5cf6"></span>Violet</button>' +
              '<button class="theme-btn" data-theme="amber"><span class="theme-dot" style="background:#f59e0b"></span>Amber</button>' +
            '</div>' +
            '<div class="muted" style="margin-top:8px;font-size:12px;">可通过 URL 切换 UI：<code>?ui=v1</code> / <code>?ui=v2</code> / <code>?ui=v3</code></div>' +
          '</div>' +
        '</div>' +
      '</div>';

    document.getElementById('root').innerHTML = html;
    wireSessionClicks();
    wireChatInput();
    wireRefreshBtn();
    wireTabClicks();
    wireThemeButtons();
    wireSkillsPanel();
    wireSessionFilterV2();
    switchTab(currentTab || 'chat');
    applyTheme((document.body && document.body.getAttribute('data-theme')) || 'slate');

    const newInput = document.getElementById('chat-input');
    if (newInput) {
      newInput.value = oldInputValue;
      if (wasFocused) {
        newInput.focus();
        if (oldStart >= 0 && oldEnd >= 0 && typeof newInput.setSelectionRange === 'function') {
          try {
            newInput.setSelectionRange(oldStart, oldEnd);
          } catch (_e) {}
        }
      }
    }
  }
"""
}
