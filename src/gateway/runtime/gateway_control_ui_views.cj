package metis.gateway.runtime

public func gatewayBuildControlUiViewsScript(): String {
    """
  function renderCommSectionHtml(data, tab) {
    const vis = (tab === 'comm') ? '' : 'display:none;';
    const gw = (data && data.gateway) ? data.gateway : {};
    const channels = (data && data.channels) ? data.channels : [];
    let commSub = 'channels';
    try { commSub = localStorage.getItem('cj_v3_comm_sub') || 'channels'; } catch (_e) {}
    const subTabs = ['overview', 'channels', 'messages', 'broadcast', 'talk', 'audio'];
    const subLabels = { overview: 'Communication', channels: 'Channels', messages: 'Messages', broadcast: 'Broadcast', talk: 'Talk', audio: 'Audio' };
    const secTitles = {
      channels: { title: 'Channels', sub: 'Messaging channels (Telegram, Discord, Slack, Feishu, QQ, plugins, etc.)' },
      overview: { title: 'Communication', sub: 'Gateway messaging overview.' },
      messages: { title: 'Messages', sub: 'Message routing and defaults.' },
      broadcast: { title: 'Broadcast', sub: 'Broadcast channels.' },
      talk: { title: 'Talk', sub: 'Talk / voice gateway settings.' },
      audio: { title: 'Audio', sub: 'Audio / TTS settings.' }
    };
    const h = secTitles[commSub] || secTitles.channels;
    const cardsHtml = channels.map(function(c) {
      const tags = (c.tags || []).map(function(t) {
        return '<span class="comm-tag">' + escapeHtml(t) + '</span>';
      }).join('');
      const rows = (c.rows || []).map(function(r) {
        return '<div class="comm-field"><div class="comm-field__label">' + escapeHtml(r.label) + '</div><div class="comm-field__value mono">' + escapeHtml(r.value) + '</div></div>';
      }).join('');
      const on = !!c.enabled;
      return '<div class="comm-channel-card">' +
        '<div class="comm-channel-card__head">' +
          '<div class="comm-channel-card__headIcon" aria-hidden="true">' + svgIcon('messageSquare') + '</div>' +
          '<div class="comm-channel-card__headText">' +
            '<div class="comm-channel-card__nameRow">' +
              '<span class="comm-channel-card__name">' + escapeHtml(c.title) + '</span>' +
              (c.subtitle ? '<span class="comm-channel-card__sub muted">' + escapeHtml(c.subtitle) + '</span>' : '') +
            '</div>' +
            '<div class="comm-channel-card__tags">' + tags + '</div>' +
            '<p class="comm-channel-card__desc muted">' + escapeHtml(c.description || '') + '</p>' +
          '</div>' +
          '<div class="comm-toggle' + (on ? ' comm-toggle--on' : '') + '" aria-hidden="true"><span class="comm-toggle__track"></span></div>' +
        '</div>' +
        (c.boundModel ? '<div class="comm-bound"><span class="muted">绑定模型</span> <code class="mono">' + escapeHtml(c.boundModel) + '</code></div>' : '') +
        '<div class="comm-channel-card__fields">' + rows + '</div>' +
      '</div>';
    }).join('');
    const channelsBody = (channels.length)
      ? ('<div class="comm-channels-wrap">' +
          '<div class="comm-section-head">' +
            '<div class="comm-section-head__icon">' + svgIcon('messageSquare') + '</div>' +
            '<div><div class="comm-section-head__title">' + escapeHtml(h.title) + '</div><div class="comm-section-head__sub muted">' + escapeHtml(h.sub) + '</div></div>' +
          '</div>' +
          '<div class="comm-channel-list">' + cardsHtml + '</div>' +
        '</div>')
      : '<div class="comm-empty muted">暂无渠道数据。</div>';
    const overviewBody = '<div class="comm-overview">' +
      '<div class="settings-info-grid">' +
        '<div class="settings-info-row"><span class="settings-info-row__label">Gateway running</span><span class="settings-info-row__value">' + (gw.running ? 'Yes' : 'No') + '</span></div>' +
        '<div class="settings-info-row"><span class="settings-info-row__label">Gateway enabled</span><span class="settings-info-row__value">' + escapeHtml(String(!!gw.enabled)) + '</span></div>' +
        '<div class="settings-info-row"><span class="settings-info-row__label">Feishu</span><span class="settings-info-row__value">' + escapeHtml(String(!!gw.feishuEnabled)) + '</span></div>' +
        '<div class="settings-info-row"><span class="settings-info-row__label">QQ</span><span class="settings-info-row__value">' + escapeHtml(String(!!gw.qqEnabled)) + '</span></div>' +
        '<div class="settings-info-row"><span class="settings-info-row__label">Channels</span><span class="settings-info-row__value">' + String(channels.length) + '</span></div>' +
      '</div></div>';
    const placeholder = '<div class="comm-placeholder muted">此子页为当前网关通信子页占位，后续接入。</div>';
    let panelBody = placeholder;
    if (commSub === 'overview') panelBody = overviewBody;
    else if (commSub === 'channels') panelBody = channelsBody;
    const subHtml = subTabs.map(function(id) {
      const sel = (id === commSub) ? ' comm-subtab--active' : '';
      return '<button type="button" class="comm-subtab' + sel + '" data-comm-sub="' + id + '">' + escapeHtml(subLabels[id] || id) + '</button>';
    }).join('');
    return '<section class="comm-page" data-tab-panel="comm" style="' + vis + '">' +
      '<div class="comm-subtabs">' + subHtml + '</div>' +
      '<div class="comm-body">' + panelBody + '</div>' +
    '</section>';
  }
"""
}
