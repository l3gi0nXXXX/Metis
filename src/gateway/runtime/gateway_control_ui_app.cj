package metis.gateway.runtime

public func gatewayBuildControlUiAppScript(): String {
    """
  function renderShell(data) {
    if (uiVariant === 'v3') {
      renderShellV3(data);
    } else if (uiVariant === 'v2') {
      renderShellV2(data);
    } else {
      renderShellV1(data);
    }
  }

  function wireSessionClicks() {
    const bind = function(host, fromV2SessionsTab) {
      if (!host) return;
      host.onclick = function(e) {
        const t = e.target;
        const item = t.closest ? t.closest('.session-item') : null;
        if (!item) return;
        const sk = item.getAttribute('data-session') || '';
        if (!sk || sk === currentSession) return;
        currentSession = sk;
        historyFingerprint = '';
        renderSessionActive();
        const sel = document.getElementById('chat-session-select');
        if (sel) {
          sel.value = sk;
        }
        if (fromV2SessionsTab && (uiVariant === 'v2' || uiVariant === 'v3')) {
          switchTab('chat');
        }
        loadHistory(true).catch(function(err) {
          console.warn('loadHistory failed:', err);
        });
      };
    };
    bind(document.getElementById('session-list'), false);
    bind(document.getElementById('session-list-v2'), true);
  }

  function wireChatSessionSelect() {
    const sel = document.getElementById('chat-session-select');
    if (!sel) return;
    sel.onchange = function() {
      const sk = sel.value || '';
      if (!sk || sk === currentSession) return;
      currentSession = sk;
      if (uiVariant === 'v3') {
        loadDeletedSetForSession(currentSession);
      }
      historyFingerprint = '';
      renderSessionActive();
      loadHistory(true).catch(function(err) {
        console.warn('loadHistory failed:', err);
      });
    };
  }

  function wireSessionFilterV2() {
    const sel = document.getElementById('sessions-source-filter');
    if (!sel) return;
    sel.value = sessionsSourceFilter || 'all';
    sel.onchange = function() {
      sessionsSourceFilter = sel.value || 'all';
      loadStatus().catch(function(err) {
        console.warn('reload after sessions filter failed:', err);
      });
    };
  }

  function renderSessionActive() {
    const elems = document.querySelectorAll('.session-item');
    elems.forEach(function(el) {
      const sk = el.getAttribute('data-session') || '';
      if (sk === currentSession) {
        el.classList.add('session-item-active');
      } else {
        el.classList.remove('session-item-active');
      }
    });
  }

  function wireTabClicks() {
    const btns = document.querySelectorAll('.tab-btn');
    btns.forEach(function(btn) {
      btn.onclick = function() {
        const t = btn.getAttribute('data-tab') || 'sessions';
        switchTab(t);
      };
    });
  }

  function wireThemeButtons() {
    const nodes = document.querySelectorAll('.theme-btn');
    nodes.forEach(function(btn) {
      btn.onclick = function() {
        const t = btn.getAttribute('data-theme') || 'slate';
        applyTheme(t);
      };
    });
  }

  function renderSkillsList(filterText) {
    const host = document.getElementById('skills-list-host');
    if (!host) return;
    const q = String(filterText || '').trim().toLowerCase();
    const items = (skillsCache || []).filter(function(s) {
      if (!q) return true;
      return (s.name || '').toLowerCase().includes(q) || (s.description || '').toLowerCase().includes(q);
    });
    if (items.length === 0) {
      host.innerHTML = '<div class="muted">未找到匹配的 skill。</div>';
      return;
    }
    const html = items.map(function(s) {
      const name = (s.name || '').replace(/</g, '&lt;').replace(/>/g, '&gt;');
      const desc = (s.description || '').replace(/</g, '&lt;').replace(/>/g, '&gt;');
      const checked = s.enabled ? ' checked' : '';
      return '<div class="session-item" style="margin-bottom:8px;">' +
        '<div class="session-title"><code>' + name + '</code></div>' +
        '<div class="session-meta" style="margin-top:6px;font-size:14px;line-height:1.5;">' + (desc || '无描述') + '</div>' +
        '<label class="session-meta" style="display:flex;align-items:center;gap:8px;margin-top:8px;font-size:14px;">' +
          '<input type="checkbox" class="skill-enable-toggle" data-skill="' + name.replace(/"/g, '&quot;') + '"' + checked + ' />' +
          'enabled' +
        '</label>' +
      '</div>';
    }).join('');
    host.innerHTML = html;
  }

  function renderSkillsListV3(filterText) {
    const host = document.getElementById('skills-list-host');
    if (!host) return;
    const q = String(filterText || '').trim().toLowerCase();
    const items = (skillsCache || []).filter(function(s) {
      if (!q) return true;
      return (s.name || '').toLowerCase().includes(q) || (s.description || '').toLowerCase().includes(q);
    });
    const shown = document.getElementById('skills-shown');
    if (shown) {
      shown.textContent = String(items.length) + ' shown';
    }

    if (items.length === 0) {
      host.innerHTML = '<div class="muted" style="margin-top:12px;">No matching skills</div>';
      return;
    }

    const isOther = function(name) {
      const n = String(name || '').toLowerCase();
      return n.startsWith('cangjie-') || n.startsWith('cj-');
    };
    const builtIn = [];
    const extra = [];
    const other = [];
    items.forEach(function(s) {
      if (isOther(s.name)) other.push(s); else extra.push(s);
    });

    const renderSection = function(label, list) {
      const collapsed = !!skillsCollapsed[label];
      const caret = collapsed ? svgIcon('chevronRight') : svgIcon('chevronDown');
      const countText = String((list || []).length);
      const rows = (list || []).map(function(s) {
        const rawName = (s.name || '');
        const name = rawName.replace(/</g, '&lt;').replace(/>/g, '&gt;');
        const desc = (s.description || '').replace(/</g, '&lt;').replace(/>/g, '&gt;');
        const source = String(s.source || 'metis-workspace').replace(/</g, '&lt;').replace(/>/g, '&gt;');
        const enabled = !!s.enabled;
        const btnText = enabled ? 'Disable' : 'Enable';
        const btnCls = 'btn btn--sm skill-toggle-btn';
        const disabledAttr = '';
        const stateHtml = enabled ? '' : '<div class="skill-state">Skill disabled</div>';
        const tagsHtml = enabled
          ? ('<span class="chip">' + source + '</span>' +
             '<span class="chip chip-ok">eligible</span>')
          : ('<span class="chip">' + source + '</span>' +
             '<span class="chip chip-warn">blocked</span>' +
             '<span class="chip chip-warn">disabled</span>');
        const reasonHtml = enabled ? '' : '<div class="skill-reason">Reason: disabled</div>';
        return '' +
          '<div class="skill-row">' +
            '<div>' +
              '<div class="skill-name">' + name + '</div>' +
              '<div class="skill-desc">' + (desc || '') + '</div>' +
              '<div class="skill-tags">' +
                tagsHtml +
              '</div>' +
              reasonHtml +
            '</div>' +
            '<div class="skill-action">' +
              '<button type="button" class="' + btnCls + '" data-skill="' + rawName.replace(/"/g, '&quot;') + '" data-enabled="' + (enabled ? 'true' : 'false') + '"' + disabledAttr + '>' + btnText + '</button>' +
              stateHtml +
            '</div>' +
          '</div>';
      }).join('');
      return '' +
        '<div class="skills-section-head">' +
          '<div class="skills-section-label">' + label + '</div>' +
          '<div class="skills-section-meta">' +
            '<span class="mono">' + countText + '</span>' +
            '<button type="button" class="skills-collapse-btn" data-skill-section="' + label.replace(/"/g, '&quot;') + '">' + caret + '</button>' +
          '</div>' +
        '</div>' +
        '<div class="skills-list" style="' + (collapsed ? 'display:none;' : '') + '">' + (rows || '') + '</div>';
    };

    host.innerHTML =
      renderSection('BUILT-IN SKILLS', builtIn) +
      renderSection('EXTRA SKILLS', extra) +
      renderSection('OTHER SKILLS', other);
  }

  function wireSkillsPanel() {
    const search = document.getElementById('skills-search');
    const host = document.getElementById('skills-list-host');
    if (!search || !host) return;
    const browse = document.getElementById('browse-skill-store-btn');
    if (browse && uiVariant === 'v3') {
      browse.onclick = function() {
        window.open('https://opencsitool.com/ecosystem', '_blank', 'noopener,noreferrer');
      };
    }
    apiGet('/api/skills').then(function(data) {
      skillsCache = data.skills || [];
      if (uiVariant === 'v3') {
        renderSkillsListV3('');
      } else {
        renderSkillsList('');
      }
    }).catch(function(err) {
      host.innerHTML = '<div class="muted">加载 skills 失败：' + err + '</div>';
    });
    search.oninput = function() {
      if (uiVariant === 'v3') {
        renderSkillsListV3(search.value || '');
      } else {
        renderSkillsList(search.value || '');
      }
    };
    host.onclick = function(e) {
      if (uiVariant === 'v3') {
        const secBtn = (e.target && e.target.closest) ? e.target.closest('.skills-collapse-btn') : null;
        if (secBtn) {
          const k = secBtn.getAttribute('data-skill-section') || '';
          if (k && Object.prototype.hasOwnProperty.call(skillsCollapsed, k)) {
            skillsCollapsed[k] = !skillsCollapsed[k];
            renderSkillsListV3(search.value || '');
          }
          return;
        }
        const btn = (e.target && e.target.closest) ? e.target.closest('.skill-toggle-btn') : null;
        if (!btn) return;
        if (btn.disabled) return;
        const skillName = btn.getAttribute('data-skill') || '';
        const currentEnabled = (btn.getAttribute('data-enabled') || 'false') === 'true';
        const enabled = !currentEnabled;
        apiPost('/api/skills/set', { name: skillName, enabled: String(enabled) })
          .then(function() {
            skillsCache = (skillsCache || []).map(function(s) {
              if ((s.name || '') === skillName) {
                s.enabled = enabled;
              }
              return s;
            });
            if (uiVariant === 'v3') {
              renderSkillsListV3(search.value || '');
            } else {
              renderSkillsList(search.value || '');
            }
          })
          .catch(function(err) {
            alert('设置 skill 开关失败：' + err);
          });
        return;
      }

      const t = e.target;
      if (!t || !t.classList || !t.classList.contains('skill-enable-toggle')) return;
      const skillName = t.getAttribute('data-skill') || '';
      const enabled = !!t.checked;
      apiPost('/api/skills/set', { name: skillName, enabled: String(enabled) })
        .then(function() {
          skillsCache = (skillsCache || []).map(function(s) {
            if ((s.name || '') === skillName) {
              s.enabled = enabled;
            }
            return s;
          });
          renderSkillsList(search.value || '');
        })
        .catch(function(err) {
          alert('设置 skill 开关失败：' + err);
        });
    };
  }

  function wireChatInput() {
    const input = document.getElementById('chat-input');
    const btn = document.getElementById('chat-send-btn');
    if (!input || !btn) return;
    btn.onclick = function() { sendMessage().catch(function(e){ console.warn(e); }); };
    input.addEventListener('keydown', function(ev) {
      if (ev.key === 'Enter' && !ev.ctrlKey && !ev.shiftKey) {
        ev.preventDefault();
        sendMessage().catch(function(e){ console.warn(e); });
      }
    });
  }

  function appendChatMessage(role, text, ts) {
    const box = document.getElementById('chat-box');
    if (!box) return;
    const safe = (text || '').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    const timeText = formatTs(ts || '');

    if (uiVariant === 'v3') {
      const isUser = role === 'user';
      const lineCls = isUser ? 'chat-line user' : 'chat-line assistant';
      const who = isUser ? 'You' : 'Assistant';
      const avatarIcon = isUser ? svgIcon('messageSquare') : svgIcon('zap');
      const stamp = who + (timeText ? (' · ' + timeText) : '');
      const msgId = _msgId(role, ts, text);
      if (deletedMsgIds && deletedMsgIds.has(msgId)) {
        return;
      }
      const copyBtn = isUser ? '' : ('<button type="button" class="chat-copy-btn" data-copy="' + safe.replace(/"/g, '&quot;') + '" title="复制">' + svgIcon('copy') + '</button>');
      const delBtn = isUser ? '' : ('<button type="button" class="chat-del-btn" data-del="' + msgId + '" title="删除">' + svgIcon('trash') + '</button>');
      const html =
        '<div class="' + lineCls + '" data-msgid="' + msgId + '">' +
          '<div class="chat-line-inner">' +
            (isUser ? '' : ('<span class="chat-avatar" aria-hidden="true">' + avatarIcon + '</span>')) +
            '<div class="chat-msg">' +
              '<div class="chat-stamp" style="display:flex;align-items:center;justify-content:space-between;gap:10px;">' +
                '<span>' + stamp + '</span>' +
                (isUser ? '' : ('<span style="display:inline-flex;gap:6px;align-items:center;">' + delBtn + '</span>')) +
              '</div>' +
              '<div class="chat-bubble-wrap">' +
                copyBtn +
                '<div class="chat-bubble">' + safe + '</div>' +
              '</div>' +
            '</div>' +
            (isUser ? ('<span class="chat-avatar" aria-hidden="true">' + avatarIcon + '</span>') : '') +
          '</div>' +
        '</div>';
      box.insertAdjacentHTML('beforeend', html);
      box.scrollTop = box.scrollHeight;
      const btn = box.querySelector('.chat-copy-btn:not([data-bound])');
      if (btn) {
        btn.setAttribute('data-bound', '1');
        btn.addEventListener('click', function() {
          const v = btn.getAttribute('data-copy') || '';
          copyToClipboard(v).then(function() {
            const prev = btn.innerHTML;
            btn.classList.add('copied');
            btn.innerHTML = svgIcon('check');
            setTimeout(function() {
              btn.classList.remove('copied');
              btn.innerHTML = prev;
            }, 1200);
          });
        });
      }
      const del = box.querySelector('.chat-del-btn:not([data-bound])');
      if (del) {
        del.setAttribute('data-bound', '1');
        del.addEventListener('click', function() {
          const id = del.getAttribute('data-del') || '';
          if (!id) return;
          deletedMsgIds.add(id);
          saveDeletedSetForSession(currentSession);
          const line = del.closest ? del.closest('.chat-line') : null;
          if (line && line.parentNode) {
            line.parentNode.removeChild(line);
          }
        });
      }
      return;
    }

    const roleCls = role === 'user' ? 'chat-role chat-role-user' : 'chat-role chat-role-assistant';
    const html =
      '<div class="chat-msg">' +
        '<div class="' + roleCls + '">' + role + (timeText ? '<span class="chat-time">' + timeText + '</span>' : '') + '</div>' +
        '<div class="chat-bubble">' + safe + '</div>' +
      '</div>';
    box.insertAdjacentHTML('beforeend', html);
    box.scrollTop = box.scrollHeight;
  }

  function buildHistoryFingerprint(messages) {
    try {
      return JSON.stringify(messages || []);
    } catch (_e) {
      return '';
    }
  }

  function renderHistoryMessages(messages) {
    const box = document.getElementById('chat-box');
    if (!box) return;
    box.innerHTML = '';
    if (!messages || messages.length === 0) {
      box.innerHTML = '<div class="muted">该会话暂无历史消息。</div>';
      return;
    }
    messages.forEach(function(m) {
      appendChatMessage(m.role || 'assistant', m.text || '', m.ts || '');
    });
  }

  async function loadHistory(forceRender) {
    if (!currentSession) {
      return;
    }
    const box = document.getElementById('chat-box');
    if (box && forceRender) {
      box.innerHTML = '<div class="muted">加载会话历史中...</div>';
    }
    try {
      const encoded = encodeURIComponent(currentSession);
      const data = await apiGet('/api/chat/history?session=' + encoded);
      const messages = data.messages || [];
      const fp = buildHistoryFingerprint(messages);
      if (forceRender || fp != historyFingerprint) {
        historyFingerprint = fp;
        renderHistoryMessages(messages);
      }
    } catch (e) {
      if (box) {
        box.innerHTML = '<div class="muted">历史加载失败：' + e + '</div>';
      }
      throw e;
    }
  }

  async function sendMessage() {
    if (isSending) return;
    const input = document.getElementById('chat-input');
    const btn = document.getElementById('chat-send-btn');
    if (!input || !btn) return;
    const text = (input.value || '').trim();
    if (!currentSession) {
      alert('请先在左侧选择一个会话。');
      return;
    }
    if (!text) {
      return;
    }
    isSending = true;
    btn.disabled = true;
    appendChatMessage('user', text, Date.now());
    input.value = '';
    try {
      const data = await apiPost('/api/chat/send', { session: currentSession, text: text });
      if (data.error) {
        appendChatMessage('assistant', '发送失败：' + data.error, Date.now());
        return;
      }
      appendChatMessage('assistant', data.answer || '', Date.now());
    } catch (e) {
      appendChatMessage('assistant', '发送失败：' + e, Date.now());
    } finally {
      isSending = false;
      btn.disabled = false;
    }
  }

  async function loadModelsWidget() {
    const host = document.getElementById('model-select-host');
    if (!host) return;
    try {
      const data = await apiGet('/api/models');
      const current = data.current || '';
      const list = data.candidates || [];
      let options = '';
      list.forEach(function(m) {
        const sel = (m === current) ? ' selected' : '';
        options += '<option value="' + m + '"' + sel + '>' + m + '</option>';
      });
      if (uiVariant === 'v3') {
        host.innerHTML = '<select id="model-select" aria-label="Model">' + options + '</select>';
        const sel = document.getElementById('model-select');
        if (sel) {
          sel.onchange = async function() {
            const val = sel.value || '';
            if (!val) return;
            try {
              await apiPost('/api/model', { model: val });
              loadStatus().catch(function(e){ console.warn(e); });
            } catch (e) {
              alert('切换模型失败：' + e);
            }
          };
        }
      } else {
        host.innerHTML =
          '<select id="model-select" class="model-select">' + options + '</select>' +
          '<div class="model-actions">' +
            '<span class="muted" style="font-size:11px;">改变后仅影响新的请求</span>' +
            '<button class="btn-small" id="model-apply">应用</button>' +
          '</div>';
        const btn = document.getElementById('model-apply');
        const sel = document.getElementById('model-select');
        if (btn && sel) {
          btn.onclick = async function() {
            const val = sel.value || '';
            if (!val) return;
            try {
              await apiPost('/api/model', { model: val });
              loadStatus().catch(function(e){ console.warn(e); });
            } catch (e) {
              alert('切换模型失败：' + e);
            }
          };
        }
      }
    } catch (e) {
      host.innerHTML = '<span class="muted">加载模型列表失败：' + e + '</span>';
    }
  }

  async function loadStatus() {
    var limRaw = String(v3SessionsStatusLimit || '120').trim();
    var limNum = parseInt(limRaw, 10);
    if (!Number.isFinite(limNum) || limNum < 1) limNum = 120;
    if (limNum > 5000) limNum = 5000;
    v3SessionsStatusLimit = String(limNum);
    const data = await apiGet('/api/status?limit=' + encodeURIComponent(String(limNum)), 12000);
    lastStatusData = data;
    if (!currentSession) {
      const fromQuery = getQueryParam('session');
      if (fromQuery) {
        currentSession = fromQuery;
      } else if (data.sessions && Array.isArray(data.sessions.recent) && data.sessions.recent.length > 0) {
        currentSession = data.sessions.recent[0];
      }
    }
    if (uiVariant === 'v3') {
      loadDeletedSetForSession(currentSession);
    }
    renderShell(data);
    loadModelsWidget().catch(function(e){ console.warn(e); });
    if (currentSession) {
      historyFingerprint = '';
      loadHistory(true).catch(function(e){ console.warn(e); });
    }
  }

  function wireRefreshBtn() {
    const b = document.getElementById('refresh-btn');
    if (!b) return;
    b.onclick = function() {
      loadStatus().catch(function(err) {
        console.warn('manual refresh failed:', err);
      });
    };
  }

  (async function init() {
    uiVariant = resolveUiVariant();
    try { document.body.setAttribute('data-ui', uiVariant); } catch (_e) {}
    if (uiVariant === 'v1' && !currentTab) {
      currentTab = 'sessions';
    } else if (uiVariant === 'v2' || uiVariant === 'v3') {
      currentTab = 'chat';
    }
    await dashboardLoadBootstrapConfig();
    dashboardApplyBootstrapConfigUi();
    bootstrapTheme();
    loadStatus().catch(function(err) {
      const root = document.getElementById('root');
      if (root) {
        root.textContent = 'Load failed: ' + err;
      }
    });
    setInterval(function() {
      if (!currentSession || isSending) {
        return;
      }
      loadHistory(false).catch(function(err) {
        console.warn('chat history poll failed:', err);
      });
    }, 3000);
  })();
"""
}
