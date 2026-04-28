package metis.gateway.runtime

public func gatewayBuildControlUiV3TemplatesScript(): String {
    """

  function buildV3PlaceholderPanelHtml(id, title) {
    return '<section class="card" data-tab-panel="' + id + '" style="' + (currentTab === id ? '' : 'display:none;') + '">' +
      '<div class="card-title">' + title + '</div>' +
      '<div class="card-sub muted">与 Metis 侧栏结构对齐占位，后续可接入网关与 Agent 能力。</div>' +
    '</section>';
  }

  function buildV3PlaceholderStack() {
    return (
      buildV3PlaceholderPanelHtml('overview', '概览') +
      buildV3PlaceholderPanelHtml('channels', '频道') +
      buildV3PlaceholderPanelHtml('instances', '实例') +
      buildV3PlaceholderPanelHtml('usage', '使用情况') +
      buildV3PlaceholderPanelHtml('agentHome', '代理') +
      buildV3PlaceholderPanelHtml('nodes', '节点') +
      buildV3PlaceholderPanelHtml('config', '配置') +
      buildV3PlaceholderPanelHtml('automation', '自动化') +
      buildV3PlaceholderPanelHtml('infra', '基础设施') +
      buildV3PlaceholderPanelHtml('aiAgents', 'AI 与 代理') +
      buildV3PlaceholderPanelHtml('debug', '调试')
    );
  }

  function buildV3SessionsPanelHtml(ctx) {
    const pageInfoText = ctx && ctx.pageInfoText ? ctx.pageInfoText : '0 of 0';
    const perPageOptions = ctx && ctx.perPageOptions ? ctx.perPageOptions : '';
    const prevDisabled = ctx && ctx.prevDisabled ? ctx.prevDisabled : '';
    const nextDisabled = ctx && ctx.nextDisabled ? ctx.nextDisabled : '';
    const sessionsRows = ctx && ctx.sessionsRows ? ctx.sessionsRows : '';

    return (
      '<section class="card" data-tab-panel="sessions" style="' + (currentTab === 'sessions' ? '' : 'display:none;') + '">' +
        '<div class="sessions-head">' +
          '<div>' +
            '<div class="sessions-title">Sessions</div>' +
            '<div class="sessions-sub">Store: <span class="mono">(multiple)</span></div>' +
          '</div>' +
          '<button class="btn btn--sm" id="refresh-btn-sessions">Refresh</button>' +
        '</div>' +
        '<div class="filters">' +
          '<span class="field-inline"><span>Active</span><input type="text" id="sessions-active-min" value="' + String(v3SessionsActiveMin || '').replace(/"/g, '&quot;') + '" placeholder="min" style="width:70px" /></span>' +
          '<span class="field-inline"><span>Limit</span><input type="text" id="sessions-status-limit" value="' + String(v3SessionsStatusLimit || '120').replace(/"/g, '&quot;') + '" style="width:70px" /></span>' +
          '<label class="field-inline checkbox"><input type="checkbox" disabled /><span>Global</span></label>' +
          '<label class="field-inline checkbox"><input type="checkbox" disabled /><span>Unknown</span></label>' +
        '</div>' +
        '<div class="data-table-wrapper">' +
          '<div class="data-table-toolbar">' +
              '<div class="data-table-search"><input type="text" id="sessions-filter" placeholder="Filter by key, label, kind..." value="' + String(v3SessionsFilterText || '').replace(/"/g, '&quot;') + '" /></div>' +
          '</div>' +
            '<div class="data-table-selectionbar" id="sessions-selectionbar">' +
              '<span><span id="sessions-selected-count">0</span> selected</span>' +
              '<button type="button" class="btn btn--sm" id="sessions-unselect">Unselect</button>' +
              '<button type="button" class="btn btn--sm btn-danger" id="sessions-delete">Delete</button>' +
            '</div>' +
          '<div class="data-table-container">' +
            '<table class="data-table">' +
              '<thead>' +
                '<tr>' +
                    '<th style="width:34px;"><input type="checkbox" id="sessions-select-all" /></th>' +
                  '<th>KEY</th>' +
                  '<th>LABEL</th>' +
                  '<th>KIND</th>' +
                  '<th>UPDATED</th>' +
                  '<th>TOKENS</th>' +
                  '<th>THINKING</th>' +
                  '<th>FAST</th>' +
                  '<th>VERBOSE</th>' +
                  '<th>REASONING</th>' +
                '</tr>' +
              '</thead>' +
              '<tbody>' +
                (sessionsRows || '') +
              '</tbody>' +
            '</table>' +
          '</div>' +
          '<div class="data-table-pagination">' +
            '<div id="sessions-page-info">' + pageInfoText + '</div>' +
            '<div class="data-table-pagination__controls">' +
              '<select class="cell-select" id="sessions-page-size">' + perPageOptions + '</select>' +
              '<button id="sessions-prev"' + prevDisabled + '>Previous</button>' +
              '<button id="sessions-next"' + nextDisabled + '>Next</button>' +
            '</div>' +
          '</div>' +
        '</div>' +
      '</section>'
    );
  }

  function buildV3CronPanelHtml(ctx) {
    const cronAnyEnabled = !!(ctx && ctx.cronAnyEnabled);
    const cronCount = (ctx && ctx.cronCount) || 0;
    const cronMinNext = (ctx && typeof ctx.cronMinNext !== 'undefined') ? ctx.cronMinNext : null;
    const cronStorePath = (ctx && ctx.cronStorePath) ? ctx.cronStorePath : '';
    const cronCardsHtml = (ctx && ctx.cronCardsHtml) ? ctx.cronCardsHtml : '<div class="cron-empty">没有匹配的任务</div>';
    const cronRunHistoryBlockHtml = (ctx && ctx.cronRunHistoryBlockHtml) ? ctx.cronRunHistoryBlockHtml : '';

    return (
      '<section class="card cron-page" data-tab-panel="cron" style="' + (currentTab === 'cron' ? '' : 'display:none;') + '">' +
        '<div class="card-title">定时任务</div>' +
        '<div class="cron-summary">' +
          '<div class="cron-summary__card"><div class="cron-summary__label">已启用</div><div class="cron-summary__value">' + (cronAnyEnabled ? '<span class="cron-badge--yes">是</span>' : '<span class="cron-badge--no">否</span>') + '</div></div>' +
          '<div class="cron-summary__card"><div class="cron-summary__label">任务数</div><div class="cron-summary__value">' + String(cronCount) + '</div></div>' +
          '<div class="cron-summary__card"><div class="cron-summary__label">下次唤醒</div><div class="cron-summary__value">' + (cronMinNext !== null ? new Date(cronMinNext).toLocaleString() : 'n/a') + '</div></div>' +
          '<div class="cron-summary__card" style="flex:0 0 auto;display:flex;align-items:center;"><button type="button" class="btn btn--sm" id="cron-refresh-btn">刷新</button></div>' +
        '</div>' +
        '<div class="cron-page__layout">' +
          '<div class="cron-page__main">' +
            '<div class="cron-section">' +
              '<div class="cron-section__title">任务列表</div>' +
              '<div class="cron-section__sub">网关中存储的所有定时任务。</div>' +
              '<div class="cron-filters">' +
                '<label>搜索任务<input type="text" id="cron-filter-search" placeholder="名称、描述或代理" value="' + String(v3CronFilterText || '').replace(/"/g, '&quot;') + '" /></label>' +
                '<label>启用状态<select id="cron-filter-enabled">' +
                  '<option value="all"' + (v3CronEnableFilter === 'all' ? ' selected' : '') + '>全部</option>' +
                  '<option value="enabled"' + (v3CronEnableFilter === 'enabled' ? ' selected' : '') + '>已启用</option>' +
                  '<option value="disabled"' + (v3CronEnableFilter === 'disabled' ? ' selected' : '') + '>已禁用</option>' +
                '</select></label>' +
                '<label>Schedule<select id="cron-filter-schedule">' +
                  '<option value="all"' + (v3CronScheduleFilter === 'all' ? ' selected' : '') + '>全部</option>' +
                  '<option value="every"' + (v3CronScheduleFilter === 'every' ? ' selected' : '') + '>every</option>' +
                  '<option value="at"' + (v3CronScheduleFilter === 'at' ? ' selected' : '') + '>at</option>' +
                  '<option value="cron"' + (v3CronScheduleFilter === 'cron' ? ' selected' : '') + '>cron</option>' +
                '</select></label>' +
                '<label>Last run<select id="cron-filter-lastrun">' +
                  '<option value="all"' + (v3CronLastRunFilter === 'all' ? ' selected' : '') + '>全部</option>' +
                  '<option value="has"' + (v3CronLastRunFilter === 'has' ? ' selected' : '') + '>已运行</option>' +
                  '<option value="never"' + (v3CronLastRunFilter === 'never' ? ' selected' : '') + '>从未</option>' +
                '</select></label>' +
                '<label>排序<select id="cron-sort">' +
                  '<option value="next"' + (v3CronSort === 'next' ? ' selected' : '') + '>下次运行</option>' +
                  '<option value="name"' + (v3CronSort === 'name' ? ' selected' : '') + '>名称</option>' +
                '</select></label>' +
                '<label>方向<select id="cron-sort-dir">' +
                  '<option value="asc"' + (v3CronSortDir === 'asc' ? ' selected' : '') + '>升序</option>' +
                  '<option value="desc"' + (v3CronSortDir === 'desc' ? ' selected' : '') + '>降序</option>' +
                '</select></label>' +
                '<label>　<button type="button" class="btn btn--sm" id="cron-filter-reset">重置</button></label>' +
              '</div>' +
              '<div class="cron-task-list">' + cronCardsHtml + '</div>' +
            '</div>' +
            '<div class="cron-section cron-section--run-history">' +
              cronRunHistoryBlockHtml +
            '</div>' +
          '</div>' +
          '<aside class="cron-aside">' +
            '<div class="cron-aside__head" style="display:flex;align-items:center;justify-content:space-between;gap:8px;flex-wrap:wrap;margin-bottom:4px;">' +
              '<div class="cron-aside__title" id="cron-aside-title">新建任务</div>' +
            '</div>' +
            '<p class="muted" style="font-size:12px;margin:0 0 12px;">存储路径：<span class="mono">' + cronStorePath + '</span></p>' +
            '<form id="cron-form-new" novalidate>' +
              '<div class="cron-section__title" style="margin-bottom:10px;">基本信息</div>' +
              '<div class="cron-field"><label>名称 <span class="muted">*</span></label><input type="text" id="cron-in-name" name="name" placeholder="晨间简报" required /></div>' +
              '<div class="cron-field"><label>描述</label><textarea id="cron-in-desc" placeholder="此任务的可选说明" disabled></textarea><div class="cron-field-hint">描述字段当前未持久化（仅对齐 Metis 表单布局）。</div></div>' +
              '<div class="cron-field"><label>代理 ID</label><input type="text" id="cron-in-agent" placeholder="main 或 ops" /></div>' +
              '<div class="cron-field-hint">输入以选择已绑定代理，或输入自定义 ID。未填时以「会话」下拉为准。</div>' +
              '<label class="field-inline checkbox" style="margin-top:6px;"><input type="checkbox" id="cron-in-enabled" checked /><span>已启用</span></label>' +
              '<div class="cron-section__title" style="margin:16px 0 10px;">调度</div>' +
              '<div class="cron-field"><label>调度</label><select id="cron-in-schedule-type"><option value="every">每隔</option><option value="at">一次性</option><option value="cron">五段式 cron</option></select></div>' +
              '<div id="cron-row-every">' +
                '<div class="cron-field"><label>每隔 <span class="muted">*</span></label><input type="number" id="cron-in-interval" min="1" value="30" /></div>' +
                '<div class="cron-field"><label>单位</label><select id="cron-in-interval-unit"><option value="s">秒</option><option value="m">分钟</option><option value="h">小时</option><option value="d">天</option></select></div>' +
              '</div>' +
              '<div id="cron-row-at" style="display:none;">' +
                '<div class="cron-field"><label>时间 <span class="muted">*</span></label><input type="datetime-local" id="cron-in-at" /></div>' +
              '</div>' +
              '<div id="cron-row-cron" style="display:none;">' +
                '<div class="cron-field"><label>表达式 <span class="muted">*</span></label><input type="text" id="cron-in-expr" class="mono" placeholder="分 时 日 月 周，如 0 9 * * 1" /></div>' +
                '<div class="cron-field"><label>时区</label><input type="text" id="cron-in-tz" class="mono" placeholder="UTC、UTC+8" value="UTC" /><div class="cron-field-hint">固定 UTC 偏移（±HH 或 ±HH:MM），非完整 IANA。</div></div>' +
              '</div>' +
              '<div class="cron-section__title" style="margin:16px 0 10px;">投递（可选）</div>' +
              '<div class="cron-field"><label>渠道</label><input type="text" id="cron-in-delivery-channel" class="mono" placeholder="feishu" /></div>' +
              '<div class="cron-field"><label>接收方 peer</label><input type="text" id="cron-in-delivery-to" placeholder="如飞书 chat_id" /></div>' +
              '<label class="field-inline checkbox" style="margin-top:6px;"><input type="checkbox" id="cron-in-delivery-announce" /><span>回复正文加任务前缀</span></label>' +
              '<div class="cron-section__title" style="margin:16px 0 10px;">执行</div>' +
              '<div class="cron-field"><label>会话</label><select id="cron-in-session">' +
                '<option value="main">主会话</option>' +
                '<option value="isolated">隔离会话</option>' +
                '<option value="current">当前</option>' +
              '</select><div class="cron-field-hint">主会话发布系统事件。隔离会话运行独立的代理轮次。</div></div>' +
              '<div class="cron-field"><label>系统事件</label><input type="text" id="cron-in-system-event" placeholder="可选，仅持久化" /></div>' +
              '<div class="cron-field"><label>唤醒模式</label><input type="text" id="cron-in-wake-mode" placeholder="可选，仅持久化" /></div>' +
              '<div class="cron-field"><label>执行内容</label><select disabled><option>运行助手任务（隔离）</option></select><div class="cron-field-hint">使用您的提示在独立会话中启动助手运行。</div></div>' +
              '<div class="cron-field"><label>助手任务提示 <span class="muted">*</span></label><textarea id="cron-in-message" placeholder="代理消息（必填）" required></textarea></div>' +
              '<div class="cron-field"><label>超时（秒）</label><input type="text" disabled placeholder="可选，如 90" /><div class="cron-field-hint">可选。留空以使用网关默认超时行为。</div></div>' +
              '<div id="cron-form-errors" class="cron-form-errors" aria-live="polite"></div>' +
              '<div class="cron-form-actions cron-form-actions--footer">' +
                '<div class="cron-form-footer-btns">' +
                  '<button type="submit" class="btn btn--sm primary" id="cron-submit-btn" disabled>添加任务</button>' +
                  '<button type="button" class="btn btn--sm" id="cron-form-footer-cancel" style="display:none;">取消</button>' +
                '</div>' +
                '<span id="cron-form-errors-hint" class="cron-form-errors-hint muted"></span>' +
              '</div>' +
            '</form>' +
          '</aside>' +
        '</div>' +
      '</section>'
    );
  }

  function buildV3ShellHtml(ctx) {
    const sidebarNavHtml = (ctx && ctx.sidebarNavHtml) ? ctx.sidebarNavHtml : '';
    const chatPanelHtml = (ctx && ctx.chatPanelHtml) ? ctx.chatPanelHtml : '';
    const sessionsPanelHtml = (ctx && ctx.sessionsPanelHtml) ? ctx.sessionsPanelHtml : '';
    const subagentsPanelHtml = (ctx && ctx.subagentsPanelHtml) ? ctx.subagentsPanelHtml : '';
    const skillsPanelHtml = (ctx && ctx.skillsPanelHtml) ? ctx.skillsPanelHtml : '';
    const logsPanelHtml = (ctx && ctx.logsPanelHtml) ? ctx.logsPanelHtml : '';
    const cronPanelHtml = (ctx && ctx.cronPanelHtml) ? ctx.cronPanelHtml : '';
    const placeholderStackHtml = (ctx && ctx.placeholderStackHtml) ? ctx.placeholderStackHtml : '';
    const commSectionHtml = (ctx && ctx.commSectionHtml) ? ctx.commSectionHtml : '';
    const appearanceSectionHtml = (ctx && ctx.appearanceSectionHtml) ? ctx.appearanceSectionHtml : '';

    return (
      '<div class="oc-root">' +
        '<div class="shell shell--chat">' +
          '<header class="topbar">' +
            '<div class="topnav-shell">' +
              '<div class="topnav-shell__content">' +
                '<div class="page-title">Metis</div>' +
              '</div>' +
              '<div class="topnav-shell__actions">' +
                '<div class="topbar-search" aria-hidden="true">' +
                  '<span class="nav-item__icon" style="opacity:0.72">' + svgIcon('search') + '</span>' +
                  '<span class="topbar-search__label muted">搜索</span>' +
                  '<kbd class="topbar-search__kbd">⌘K</kbd>' +
                '</div>' +
              '</div>' +
            '</div>' +
          '</header>' +
          '<div class="shell-nav">' +
            '<aside class="sidebar">' +
              '<div class="sidebar-shell">' +
                '<div class="sidebar-shell__header">' +
                  '<div class="sidebar-brand">' +
                    '<div class="sidebar-brand__logo"></div>' +
                    '<span class="sidebar-brand__copy">' +
                      '<span class="sidebar-brand__eyebrow">Control</span>' +
                      '<span class="sidebar-brand__title">Metis</span>' +
                    '</span>' +
                  '</div>' +
                '</div>' +
                '<div class="sidebar-shell__body">' +
                  '<nav class="sidebar-nav">' + sidebarNavHtml + '</nav>' +
                '</div>' +
                '<div class="sidebar-shell__footer">' +
                  '<a class="sidebar-doc-link" href="https://gitcode.com/gxmm/Metis/blob/main/README.md" target="_blank" rel="noopener noreferrer">' +
                    '<span class="nav-item__icon" aria-hidden="true">' + svgIcon('bookOpen') + '</span>' +
                    '<span class="nav-item__text">文档</span>' +
                  '</a>' +
                '</div>' +
              '</div>' +
            '</aside>' +
          '</div>' +
          '<main class="content" id="oc-main">' +
            '<section class="content-header" id="v3-header-host"></section>' +
            chatPanelHtml +
            sessionsPanelHtml +
            subagentsPanelHtml +
            skillsPanelHtml +
            logsPanelHtml +
            cronPanelHtml +
            placeholderStackHtml +
            commSectionHtml +
            appearanceSectionHtml +
          '</main>' +
        '</div>' +
      '</div>'
    );
  }

"""
}
