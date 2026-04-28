package metis.gateway.runtime

public func gatewayBuildControlUiV3PanelsScript(): String {
    """

  function buildV3NavItem(id, label, iconName) {
    const active = (currentTab === id) ? ' nav-item--active' : '';
    return '<button type="button" class="nav-item' + active + '" data-tab="' + id + '">' +
      '<span class="nav-item__icon" aria-hidden="true">' + svgIcon(iconName) + '</span>' +
      '<span class="nav-item__text">' + label + '</span>' +
    '</button>';
  }

  function buildV3NavSectionHtml(sectionKey, title, itemsHtml) {
    var collapsed = false;
    try {
      var s = localStorage.getItem('cj_v3_nav_section_' + sectionKey);
      collapsed = (s === '1');
    } catch (_e) {}
    var collapsedCls = collapsed ? ' nav-section--collapsed' : '';
    var expandedAttr = collapsed ? 'false' : 'true';
    return '<section class="nav-section nav-section--collapsible' + collapsedCls + '" data-nav-section="' + sectionKey + '">' +
      '<button type="button" class="nav-section__head" aria-expanded="' + expandedAttr + '">' +
        '<span class="nav-section__headText">' + title + '</span>' +
        '<span class="nav-section__chevron" aria-hidden="true">' + svgIcon('chevronDown') + '</span>' +
      '</button>' +
      '<div class="nav-section__items">' + itemsHtml + '</div>' +
    '</section>';
  }

  function buildV3SidebarNavHtml() {
    return (
      buildV3NavSectionHtml('chat', '聊天', buildV3NavItem('chat', '聊天', 'messageSquare')) +
      buildV3NavSectionHtml('control', '控制',
        buildV3NavItem('overview', '概览', 'barChart') +
        buildV3NavItem('channels', '频道', 'link') +
        buildV3NavItem('instances', '实例', 'radio') +
        buildV3NavItem('sessions', '会话', 'scrollText') +
        buildV3NavItem('subagents', 'Subagents', 'terminal') +
        buildV3NavItem('usage', '使用情况', 'barChart') +
        buildV3NavItem('cron', '定时任务', 'sparkles')
      ) +
      buildV3NavSectionHtml('agent', '代理',
        buildV3NavItem('agentHome', '代理', 'folder') +
        buildV3NavItem('skills', '技能', 'zap') +
        buildV3NavItem('nodes', '节点', 'monitor')
      ) +
      buildV3NavSectionHtml('settings', '设置',
        buildV3NavItem('config', '配置', 'settings') +
        buildV3NavItem('comm', '通信', 'send') +
        buildV3NavItem('appearance', '外观与设置', 'star') +
        buildV3NavItem('automation', '自动化', 'terminal') +
        buildV3NavItem('infra', '基础设施', 'globe') +
        buildV3NavItem('aiAgents', 'AI 与 代理', 'brain') +
        buildV3NavItem('debug', '调试', 'bug') +
        buildV3NavItem('logs', '日志', 'fileText')
      )
    );
  }

  function buildV3ChatPanelHtml() {
    return (
      '<section class="card chat" data-tab-panel="chat" style="' + (currentTab === 'chat' ? '' : 'display:none;') + '">' +
        '<div class="chat-thread" id="chat-box">' +
          '<div class="muted">请选择会话后开始对话。</div>' +
        '</div>' +
        '<div class="agent-chat__input">' +
          '<textarea id="chat-input" placeholder="Message Assistant (Enter 发送，Shift+Enter 换行)" rows="1"></textarea>' +
          '<div class="agent-chat__toolbar">' +
            '<div style="display:flex;align-items:center;gap:4px;">' +
              '<button type="button" class="btn-ghost" id="refresh-btn" title="刷新">' + svgIcon('scrollText') + '</button>' +
            '</div>' +
            '<div style="display:flex;align-items:center;gap:6px;">' +
              '<button type="button" class="chat-send-btn" id="chat-send-btn" title="发送">' + svgIcon('send') + '</button>' +
            '</div>' +
          '</div>' +
        '</div>' +
      '</section>'
    );
  }

  function buildV3SkillsPanelHtml() {
    return (
      '<section class="card" data-tab-panel="skills" style="' + (currentTab === 'skills' ? '' : 'display:none;') + '">' +
        '<div class="skills-topbar">' +
          '<div class="skills-topbar-left">' +
            '<div class="skills-topbar-title">Skills</div>' +
            '<div class="skills-topbar-sub">Installed skills and their status.</div>' +
          '</div>' +
          '<button class="btn btn--sm" id="refresh-btn-skills">Refresh</button>' +
        '</div>' +
        '<div class="skills-actions-row">' +
          '<button class="btn btn--sm" type="button" id="browse-skill-store-btn">Browse Skills Store</button>' +
          '<div class="skills-search"><input id="skills-search" type="text" placeholder="Search skills" /></div>' +
          '<div class="skills-shown" id="skills-shown">0 shown</div>' +
        '</div>' +
        '<div id="skills-list-host"></div>' +
      '</section>'
    );
  }

  function buildV3LogsPanelHtml(data) {
    const logsTail = (((data && data.logs && data.logs.tail) ? data.logs.tail : [])).map(function(s) {
      return '<li>' + String(s || '') + '</li>';
    }).join('') || '<li class="muted">暂无日志。</li>';
    return (
      '<section class="card" data-tab-panel="logs" style="' + (currentTab === 'logs' ? '' : 'display:none;') + '">' +
        '<div class="card-title">日志</div>' +
        '<div class="card-sub">当前显示仍复用 /api/status 的 tail（与 v2 一致）。</div>' +
        '<ul class="logs-list" style="margin-top:12px;">' + logsTail + '</ul>' +
      '</section>'
    );
  }

  function buildV3SubagentsPanelHtml(data) {
    const subagents = (data && data.subagents) ? data.subagents : {};
    const rows = (subagents.sessions || subagents.active || []).map(function(r) {
      const runId = String((r && r.runId) || '');
      const sessionKey = String((r && r.sessionKey) || '');
      const status = String((r && (r.status || r.state)) || '');
      const agentId = String((r && r.agentId) || '');
      const runtime = String((r && r.runtime) || '');
      const notice = String((r && r.noticeStatus) || '');
      const live = !!(r && (r.hasLiveFuture || r.hasLiveProcess));
      const target = runId || sessionKey;
      return '' +
        '<tr>' +
          '<td style="min-width:230px;"><span class="mono">' + escapeHtml(runId || '--') + '</span><div class="session-key-display-name">' + escapeHtml(sessionKey) + '</div></td>' +
          '<td style="width:120px;"><span class="data-table-badge">' + escapeHtml(status || '--') + '</span></td>' +
          '<td style="width:140px;">' + escapeHtml(agentId || '--') + '</td>' +
          '<td style="width:110px;">' + escapeHtml(runtime || '--') + '</td>' +
          '<td style="width:90px;">' + (live ? '<span class="data-table-badge data-table-badge--direct">live</span>' : '<span class="data-table-badge data-table-badge--unknown">idle</span>') + '</td>' +
          '<td style="width:130px;">' + escapeHtml(notice || '--') + '</td>' +
          '<td style="width:190px;">' +
            '<button type="button" class="btn btn--sm subagent-status" data-target="' + escapeHtml(target) + '">Status</button> ' +
            '<button type="button" class="btn btn--sm subagent-logs" data-target="' + escapeHtml(target) + '">Logs</button> ' +
            '<button type="button" class="btn btn--sm btn-danger subagent-kill" data-target="' + escapeHtml(target) + '">Kill</button>' +
          '</td>' +
        '</tr>';
    }).join('');
    const body = rows || '<tr><td colspan="7" class="muted">No subagent runs.</td></tr>';
    return (
      '<section class="card" data-tab-panel="subagents" style="' + (currentTab === 'subagents' ? '' : 'display:none;') + '">' +
        '<div class="sessions-head">' +
          '<div>' +
            '<div class="sessions-title">Subagents</div>' +
            '<div class="sessions-sub">后台运行、状态和日志。</div>' +
          '</div>' +
          '<button class="btn btn--sm" id="refresh-btn-subagents">Refresh</button>' +
        '</div>' +
        '<div class="data-table-wrapper">' +
          '<div class="data-table-container">' +
            '<table class="data-table">' +
              '<thead><tr><th>RUN</th><th>STATUS</th><th>AGENT</th><th>RUNTIME</th><th>LIVE</th><th>NOTICE</th><th>ACTIONS</th></tr></thead>' +
              '<tbody>' + body + '</tbody>' +
            '</table>' +
          '</div>' +
        '</div>' +
        '<pre class="logs-list mono" id="subagents-detail" style="margin-top:12px;white-space:pre-wrap;max-height:360px;overflow:auto;"></pre>' +
      '</section>'
    );
  }
"""
}
