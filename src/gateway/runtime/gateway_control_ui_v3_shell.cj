package metis.gateway.runtime

public func gatewayBuildControlUiV3ShellScript(): String {
    """

  function renderShellV3(data) {
    const sessions = (data.sessions && data.sessions.recent) ? data.sessions.recent : [];
    const detailsArr = (data.sessions && data.sessions.details) ? data.sessions.details : [];
    const detailsMap = {};
    detailsArr.forEach(function(d) { if (d && d.key) detailsMap[d.key] = d; });
    const sessionsSorted = sessions.slice().sort(function(a, b) {
      const ta = Number((detailsMap[a] && detailsMap[a].updatedTs) || 0);
      const tb = Number((detailsMap[b] && detailsMap[b].updatedTs) || 0);
      return tb - ta;
    });

    const filterQ = String(v3SessionsFilterText || '').trim().toLowerCase();
    let sessionsFiltered = filterQ ? sessionsSorted.filter(function(sk) {
      const kind = sessionKind(sk);
      const label = getSessionLabel(sk);
      return String(sk || '').toLowerCase().includes(filterQ) ||
             String(kind || '').toLowerCase().includes(filterQ) ||
             String(label || '').toLowerCase().includes(filterQ);
    }) : sessionsSorted;

    const activeMinNum = Number(String(v3SessionsActiveMin || '').trim());
    if (Number.isFinite(activeMinNum) && activeMinNum > 0) {
      const nowMs = Date.now();
      const windowMs = activeMinNum * 60 * 1000;
      sessionsFiltered = sessionsFiltered.filter(function(sk) {
        const d = detailsMap[sk] || {};
        const tsNum = Number(d.updatedTs || 0);
        if (!Number.isFinite(tsNum) || tsNum <= 0) return false;
        return (nowMs - tsNum) <= windowMs;
      });
    }
    const sessionOptions = sessions.map(function(s) {
      const sel = (s === currentSession) ? ' selected' : '';
      return '<option value="' + s.replace(/"/g, '&quot;') + '"' + sel + '>' + s + '</option>';
    }).join('');
    v3SessionOptionsHtml = sessionOptions || '';

    const cronData = data.cron || {};
    const cronRenderState = buildV3CronRenderState(cronData);
    const cronPanelHtml = buildV3CronPanelHtml(cronRenderState);

    const v3PlaceholderStack = buildV3PlaceholderStack();
    const commSection = renderCommSectionHtml(data, currentTab);
    const appearanceSection = buildAppearanceSection(data, currentTab);
    const sessionsRenderState = buildV3SessionsRenderState(sessionsFiltered, detailsMap);
    const sessionsPanelHtml = buildV3SessionsPanelHtml(sessionsRenderState);

    const sidebarNavHtml = buildV3SidebarNavHtml();
    const chatPanelHtml = buildV3ChatPanelHtml();
    const skillsPanelHtml = buildV3SkillsPanelHtml();
    const logsPanelHtml = buildV3LogsPanelHtml(data);

    const html = buildV3ShellHtml({
      sidebarNavHtml: sidebarNavHtml,
      chatPanelHtml: chatPanelHtml,
      sessionsPanelHtml: sessionsPanelHtml,
      skillsPanelHtml: skillsPanelHtml,
      logsPanelHtml: logsPanelHtml,
      cronPanelHtml: cronPanelHtml,
      placeholderStackHtml: v3PlaceholderStack,
      commSectionHtml: commSection,
      appearanceSectionHtml: appearanceSection
    });

    document.getElementById('root').innerHTML = html;
    wireV3NavClicks();
    wireV3NavSectionToggle();
    renderV3Header(currentTab, { sessionOptions: v3SessionOptionsHtml });
    wireChatInput();
    wireRefreshBtn();
    wireRefreshBtnV3Sessions();
    wireV3SessionsTableClicks();
    wireRefreshBtnV3Skills();
    wireCronPanel();
    wireV3SessionsPagination();
    wireV3SessionsSelection();
    wireV3SessionsLabelAndFilter();
    wireSkillsPanel();
    applyV3AppearanceClasses();
    wireAppearancePageV3();
    wireCommSubtabsV3();
    switchTab(currentTab || 'chat');
    syncV3MainLayoutClass(currentTab || 'chat');
  }
"""
}
