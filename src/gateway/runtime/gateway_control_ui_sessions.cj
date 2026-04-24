package metis.gateway.runtime

public func gatewayBuildControlUiSessionsScript(): String {
    """

  function buildV3SessionsRenderState(sessionsFiltered, detailsMap) {
    const totalSessions = sessionsFiltered.length;
    let pageSize = Number(v3SessionsPageSize || 20);
    if (!pageSize || pageSize < 1) pageSize = 20;
    let pageIndex = Number(v3SessionsPageIndex || 0);
    if (!pageIndex || pageIndex < 0) pageIndex = 0;
    const maxPageIndex = totalSessions ? Math.max(0, Math.ceil(totalSessions / pageSize) - 1) : 0;
    if (pageIndex > maxPageIndex) pageIndex = maxPageIndex;
    v3SessionsPageIndex = pageIndex;
    const start = totalSessions ? (pageIndex * pageSize) : 0;
    const end = totalSessions ? Math.min(totalSessions, start + pageSize) : 0;

    const sessionsRows = sessionsFiltered.slice(start, end).map(function(sk) {
      const d = detailsMap[sk] || {};
      const updated = formatTs(d.updatedTs || '');
      const tokenApprox = Number(d.tokenApprox || 0);
      const kind = sessionKind(sk);
      const kindBadge = kind === 'other' ? 'data-table-badge data-table-badge--unknown' : 'data-table-badge data-table-badge--direct';
      const kindText = kind === 'other' ? 'unknown' : 'direct';
      const currentLabel = getSessionLabel(sk);
      const label = '<input class="cell-input session-label-input" data-session="' + sk.replace(/"/g, '&quot;') + '" value="' + currentLabel.replace(/"/g, '&quot;') + '" placeholder="(optional)" />';
      const tokens = tokenApprox ? (String(tokenApprox) + ' / --') : '-- / --';
      const selects = '<select class="cell-select" disabled><option>inherit</option></select>';
      const checked = v3SessionsSelected && v3SessionsSelected.has(sk) ? ' checked' : '';
      const trCls = v3SessionsSelected && v3SessionsSelected.has(sk) ? ' class="is-selected"' : '';
      return '' +
        '<tr' + trCls + '>' +
          '<td style="width:34px;"><input type="checkbox" class="session-select" data-session="' + sk.replace(/"/g, '&quot;') + '"' + checked + ' /></td>' +
          '<td style="min-width:360px;">' +
            '<div class="session-key-cell">' +
              '<a class="session-link" href="javascript:void(0)" data-session="' + sk.replace(/"/g, '&quot;') + '">' + sk + '</a>' +
              '<div class="session-key-display-name">' + (d.lastRole ? String(d.lastRole) : '') + '</div>' +
            '</div>' +
          '</td>' +
          '<td style="min-width:180px;">' + label + '</td>' +
          '<td style="width:90px;"><span class="' + kindBadge + '">' + kindText + '</span></td>' +
          '<td class="cell-updated" style="width:180px;">' + (updated || '--') + '</td>' +
          '<td class="cell-tokens" style="width:140px;">' + tokens + '</td>' +
          '<td style="width:110px;">' + selects + '</td>' +
          '<td style="width:90px;">' + selects + '</td>' +
          '<td style="width:110px;">' + selects + '</td>' +
          '<td style="width:120px;">' + selects + '</td>' +
        '</tr>';
    }).join('');

    const perPageOptions = [10, 20, 50, 100].map(function(n) {
      const sel = (n === pageSize) ? ' selected' : '';
      return '<option value="' + n + '"' + sel + '>' + n + ' per page</option>';
    }).join('');
    const pageInfoText = totalSessions ? ((start + 1) + '-' + end + ' of ' + totalSessions) : '0 of 0';
    const prevDisabled = (pageIndex <= 0) ? ' disabled' : '';
    const nextDisabled = (pageIndex >= maxPageIndex) ? ' disabled' : '';

    return {
      pageInfoText: pageInfoText,
      perPageOptions: perPageOptions,
      prevDisabled: prevDisabled,
      nextDisabled: nextDisabled,
      sessionsRows: sessionsRows
    };
  }

  function wireV3SessionsPagination() {
    if (uiVariant !== 'v3') return;
    const sizeSel = document.getElementById('sessions-page-size');
    const prev = document.getElementById('sessions-prev');
    const next = document.getElementById('sessions-next');
    if (sizeSel) {
      sizeSel.onchange = function() {
        const n = Number(sizeSel.value || 0);
        if (n && n > 0) {
          v3SessionsPageSize = n;
          v3SessionsPageIndex = 0;
          if (lastStatusData) renderShell(lastStatusData);
        }
      };
    }
    if (prev) {
      prev.onclick = function() {
        if (v3SessionsPageIndex > 0) {
          v3SessionsPageIndex = v3SessionsPageIndex - 1;
          if (lastStatusData) renderShell(lastStatusData);
        }
      };
    }
    if (next) {
      next.onclick = function() {
        v3SessionsPageIndex = v3SessionsPageIndex + 1;
        if (lastStatusData) renderShell(lastStatusData);
      };
    }
  }

  function wireV3SessionsSelection() {
    if (uiVariant !== 'v3') return;
    const host = document.querySelector('.oc-root');
    if (!host) return;

    const updateBar = function() {
      const bar = document.getElementById('sessions-selectionbar');
      const cnt = document.getElementById('sessions-selected-count');
      const all = document.getElementById('sessions-select-all');
      const n = v3SessionsSelected ? v3SessionsSelected.size : 0;
      if (cnt) cnt.textContent = String(n);
      if (bar) {
        if (n > 0) bar.classList.add('is-on'); else bar.classList.remove('is-on');
      }
      if (all) {
        const checks = host.querySelectorAll('input.session-select');
        let total = 0;
        let checked = 0;
        checks.forEach(function(c) { total++; if (c.checked) checked++; });
        all.indeterminate = (checked > 0 && checked < total);
        all.checked = (total > 0 && checked === total);
      }
    };

    const all = document.getElementById('sessions-select-all');
    if (all) {
      all.onchange = function() {
        const checks = host.querySelectorAll('input.session-select');
        const want = !!all.checked;
        checks.forEach(function(c) {
          const k = c.getAttribute('data-session') || '';
          if (!k) return;
          c.checked = want;
          if (want) v3SessionsSelected.add(k); else v3SessionsSelected.delete(k);
        });
        if (lastStatusData) renderShell(lastStatusData);
      };
    }
    const unselect = document.getElementById('sessions-unselect');
    if (unselect) {
      unselect.onclick = function() {
        v3SessionsSelected = new Set();
        if (lastStatusData) renderShell(lastStatusData);
      };
    }
    const del = document.getElementById('sessions-delete');
    if (del) {
      del.onclick = function() {
        const keys = Array.from(v3SessionsSelected.values());
        if (!keys.length) return;
        if (!confirm('Delete selected sessions?')) return;
        apiPost('/api/sessions/delete', { keys: keys.join(String.fromCharCode(10)) })
          .then(function(_resp) {
            v3SessionsSelected = new Set();
            loadStatus().catch(function(err){ console.warn(err); });
          })
          .catch(function(err) {
            alert('Delete failed: ' + err);
          });
      };
    }

    if (!host.__wiredV3SessionsSelection) {
      host.__wiredV3SessionsSelection = true;
      host.addEventListener('change', function(e) {
        const t = e.target;
        if (!t) return;
        if (t.classList && t.classList.contains('session-select')) {
          const k = t.getAttribute('data-session') || '';
          if (!k) return;
          if (t.checked) v3SessionsSelected.add(k); else v3SessionsSelected.delete(k);
          if (lastStatusData) renderShell(lastStatusData);
        }
      });
    }

    updateBar();
  }

  function wireV3SessionsLabelAndFilter() {
    if (uiVariant !== 'v3') return;
    const host = document.querySelector('.oc-root');
    if (!host) return;

    const filter = document.getElementById('sessions-filter');
    if (filter) {
      filter.oninput = function() {
        v3SessionsFilterText = filter.value || '';
        v3SessionsPageIndex = 0;
        if (lastStatusData) renderShell(lastStatusData);
      };
    }
    const active = document.getElementById('sessions-active-min');
    if (active) {
      active.oninput = function() {
        v3SessionsActiveMin = active.value || '';
        v3SessionsPageIndex = 0;
        if (lastStatusData) renderShell(lastStatusData);
      };
    }
    const lim = document.getElementById('sessions-status-limit');
    if (lim) {
      lim.onchange = function() {
        var raw = String(lim.value || '').trim();
        var n = parseInt(raw, 10);
        if (!Number.isFinite(n) || n < 1) n = 120;
        if (n > 5000) n = 5000;
        v3SessionsStatusLimit = String(n);
        try { localStorage.setItem('cj_dashboard_sessions_limit', v3SessionsStatusLimit); } catch (_e) {}
        v3SessionsPageIndex = 0;
        loadStatus().catch(function(err){ console.warn(err); });
      };
    }

    if (host.__wiredV3SessionsLabel) return;
    host.__wiredV3SessionsLabel = true;

    host.addEventListener('keydown', function(e) {
      const t = e.target;
      if (!t || !t.classList || !t.classList.contains('session-label-input')) return;
      if (e.key === 'Enter') {
        e.preventDefault();
        try { t.blur(); } catch (_e) {}
      }
    });
    host.addEventListener('blur', function(e) {
      const t = e.target;
      if (!t || !t.classList || !t.classList.contains('session-label-input')) return;
      const sk = t.getAttribute('data-session') || '';
      if (!sk) return;
      setSessionLabel(sk, t.value || '');
    }, true);
  }

"""
}
