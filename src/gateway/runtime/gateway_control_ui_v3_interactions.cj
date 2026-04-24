package metis.gateway.runtime

public func gatewayBuildControlUiV3InteractionsScript(): String {
    """

  function wireV3SessionsTableClicks() {
    const host = document.querySelector('.oc-root');
    if (!host) return;
    if (host.__wiredV3SessionsTableClicks) return;
    host.__wiredV3SessionsTableClicks = true;
    host.addEventListener('click', function(e) {
      const link = (e.target && e.target.closest) ? e.target.closest('.session-link') : null;
      if (!link) return;
      const sk = link.getAttribute('data-session') || '';
      if (!sk) return;
      e.preventDefault();

      currentSession = sk;
      if (uiVariant === 'v3') {
        loadDeletedSetForSession(currentSession);
      }
      historyFingerprint = '';

      currentTab = 'chat';
      const navItems = host.querySelectorAll('.nav-item');
      navItems.forEach(function(n) {
        const t = n.getAttribute('data-tab') || '';
        if (t === 'chat') n.classList.add('nav-item--active'); else n.classList.remove('nav-item--active');
      });
      const panels = host.querySelectorAll('[data-tab-panel]');
      panels.forEach(function(p) {
        const t = p.getAttribute('data-tab-panel') || '';
        p.style.display = (t === 'chat') ? '' : 'none';
      });
      syncV3MainLayoutClass('chat');

      renderV3Header('chat', { sessionOptions: v3SessionOptionsHtml || '' });
      const sel = document.getElementById('chat-session-select');
      if (sel) sel.value = sk;
      loadModelsWidget().catch(function(err){ console.warn(err); });
      loadHistory(true).catch(function(err){ console.warn(err); });
    });
  }

  var v3ThemeMediaQuery = null;

  function applyV3ThemeMode() {
    var el = document.querySelector('.oc-root');
    if (!el) return;
    var pref = 'system';
    try { pref = localStorage.getItem('cj_v3_theme_mode') || 'system'; } catch (_e) {}
    var eff = 'light';
    if (pref === 'light') {
      eff = 'light';
    } else if (pref === 'dark') {
      eff = 'dark';
    } else {
      try {
        eff = (window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches) ? 'dark' : 'light';
      } catch (_e2) {
        eff = 'light';
      }
    }
    el.setAttribute('data-theme-mode', eff);
    try { document.body.setAttribute('data-v3-effective-theme', eff); } catch (_e3) {}
    if (v3ThemeMediaQuery && v3ThemeMediaQuery.removeEventListener) {
      v3ThemeMediaQuery.removeEventListener('change', onV3SystemThemeChange);
      v3ThemeMediaQuery = null;
    }
    if (pref === 'system' && window.matchMedia) {
      v3ThemeMediaQuery = window.matchMedia('(prefers-color-scheme: dark)');
      if (v3ThemeMediaQuery && v3ThemeMediaQuery.addEventListener) {
        v3ThemeMediaQuery.addEventListener('change', onV3SystemThemeChange);
      }
    }
  }

  function onV3SystemThemeChange() {
    try {
      var p = localStorage.getItem('cj_v3_theme_mode') || 'system';
      if (p === 'system') {
        applyV3ThemeMode();
      }
    } catch (_e) {}
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
