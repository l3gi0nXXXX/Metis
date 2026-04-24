package metis.gateway.runtime

public func gatewayBuildControlUiCoreScript(): String {
    """

  // surface JS errors on-page to avoid "Loading..." forever
  (function wireGlobalErrorOverlay() {
    const show = function(title, err) {
      try {
        const root = document.getElementById('root');
        if (!root) return;
        const msg = (err && (err.stack || err.message)) ? (err.stack || err.message) : String(err || '');
        root.innerHTML =
          '<div style="max-width:960px;margin:18px auto;padding:14px 16px;border:1px solid #fecaca;background:#fff1f2;border-radius:12px;color:#7f1d1d;">' +
            '<div style="font-weight:700;margin-bottom:6px;">' + String(title || 'Error') + '</div>' +
            '<pre style="white-space:pre-wrap;word-break:break-word;margin:0;font-size:12px;line-height:1.5;">' + msg.replace(/</g, '&lt;').replace(/>/g, '&gt;') + '</pre>' +
          '</div>';
      } catch (_e) {}
    };
    window.addEventListener('error', function(ev) {
      show('Dashboard crashed', ev && ev.error ? ev.error : (ev && ev.message));
    });
    window.addEventListener('unhandledrejection', function(ev) {
      show('Unhandled promise rejection', ev && ev.reason ? ev.reason : ev);
    });
  })();

  function _labelKeyForSession(sessionKey) {
    return 'cj_dashboard_v3_label:' + String(sessionKey || '');
  }
  function getSessionLabel(sessionKey) {
    try { return (localStorage.getItem(_labelKeyForSession(sessionKey)) || '').trim(); } catch (_e) { return ''; }
  }
  function setSessionLabel(sessionKey, label) {
    const k = _labelKeyForSession(sessionKey);
    const v = String(label || '').trim();
    try {
      if (!v) localStorage.removeItem(k); else localStorage.setItem(k, v);
    } catch (_e) {}
  }

  function getQueryParam(name) {
    const params = new URLSearchParams(window.location.search || '');
    return params.get(name) || '';
  }

  function resolveUiVariant() {
    const v = (getQueryParam('ui') || '').toLowerCase();
    if (v === 'v1') return 'v1';
    if (v === 'v2') return 'v2';
    if (v === 'v3' || v === 'metis' || v === 'metis') return 'v3';
    return 'v3';
  }

  function svgIcon(name) {
    if (name === 'messageSquare') return '<svg viewBox="0 0 24 24"><path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z" /></svg>';
    if (name === 'scrollText') return '<svg viewBox="0 0 24 24"><path d="M8 21h12a2 2 0 0 0 2-2v-2H10v2a2 2 0 1 1-4 0V5a2 2 0 1 0-4 0v3h4" /><path d="M19 17V5a2 2 0 0 0-2-2H4" /><path d="M15 8h-5" /><path d="M15 12h-5" /></svg>';
    if (name === 'zap') return '<svg viewBox="0 0 24 24"><polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2" /></svg>';
    if (name === 'link') return '<svg viewBox="0 0 24 24" fill="none"><path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" /><path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" /></svg>';
    if (name === 'barChart') return '<svg viewBox="0 0 24 24" fill="none"><line x1="12" x2="12" y1="20" y2="10" stroke="currentColor" stroke-width="2" stroke-linecap="round" /><line x1="18" x2="18" y1="20" y2="4" stroke="currentColor" stroke-width="2" stroke-linecap="round" /><line x1="6" x2="6" y1="20" y2="16" stroke="currentColor" stroke-width="2" stroke-linecap="round" /></svg>';
    if (name === 'monitor') return '<svg viewBox="0 0 24 24" fill="none"><rect width="20" height="14" x="2" y="3" rx="2" stroke="currentColor" stroke-width="1.5" /><line x1="8" x2="16" y1="21" y2="21" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" /><line x1="12" x2="12" y1="17" y2="21" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" /></svg>';
    if (name === 'sun') return '<svg viewBox="0 0 24 24" fill="none"><circle cx="12" cy="12" r="4" stroke="currentColor" stroke-width="1.5" /><path d="M12 2v2 M12 20v2 M4.93 4.93l1.41 1.41 M17.66 17.66l1.41 1.41 M2 12h2 M20 12h2 M6.34 17.66l-1.41 1.41 M19.07 4.93l-1.41 1.41" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" /></svg>';
    if (name === 'moon') return '<svg viewBox="0 0 24 24" fill="none"><path d="M12 3a6.5 6.5 0 0 0 9 9 9 9 0 1 1-9-9Z" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" /></svg>';
    if (name === 'radiusNone') return '<svg viewBox="0 0 24 24"><rect x="4" y="4" width="16" height="16" rx="0" stroke="currentColor" fill="none" stroke-width="1.5" /></svg>';
    if (name === 'radiusSlight') return '<svg viewBox="0 0 24 24"><rect x="4" y="4" width="16" height="16" rx="2" stroke="currentColor" fill="none" stroke-width="1.5" /></svg>';
    if (name === 'radiusDefault') return '<svg viewBox="0 0 24 24"><rect x="4" y="4" width="16" height="16" rx="4" stroke="currentColor" fill="none" stroke-width="1.5" /></svg>';
    if (name === 'radiusRound') return '<svg viewBox="0 0 24 24"><rect x="3" y="3" width="18" height="18" rx="7" stroke="currentColor" fill="none" stroke-width="1.5" /></svg>';
    if (name === 'radiusFull') return '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="9" stroke="currentColor" fill="none" stroke-width="1.5" /></svg>';
    if (name === 'fileText') return '<svg viewBox="0 0 24 24"><path d="M14.5 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7.5L14.5 2z" /><polyline points="14 2 14 8 20 8" /><line x1="16" x2="8" y1="13" y2="13" /><line x1="16" x2="8" y1="17" y2="17" /><line x1="10" x2="8" y1="9" y2="9" /></svg>';
    if (name === 'send') return '<svg viewBox="0 0 24 24"><path d="m22 2-7 20-4-9-9-4Z" /><path d="M22 2 11 13" /></svg>';
    if (name === 'copy') return '<svg viewBox="0 0 24 24"><rect width="14" height="14" x="8" y="8" rx="2" ry="2" /><path d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2" /></svg>';
    if (name === 'check') return '<svg viewBox="0 0 24 24"><path d="M20 6 9 17l-5-5" /></svg>';
    if (name === 'trash') return '<svg viewBox="0 0 24 24"><path d="M3 6h18" /><path d="M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6" /><path d="M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2" /><line x1="10" x2="10" y1="11" y2="17" /><line x1="14" x2="14" y1="11" y2="17" /></svg>';
    if (name === 'search') return '<svg viewBox="0 0 24 24"><circle cx="11" cy="11" r="8" /><path d="m21 21-4.3-4.3" /></svg>';
    if (name === 'chevronDown') return '<svg viewBox="0 0 24 24" fill="none"><path d="m6 9 6 6 6-6" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" /></svg>';
    if (name === 'chevronRight') return '<svg viewBox="0 0 24 24"><path d="m9 6 6 6-6 6" /></svg>';
    if (name === 'palette') return '<svg viewBox="0 0 24 24"><circle cx="8" cy="9" r="2.5" /><circle cx="16" cy="9" r="2.5" /><circle cx="12" cy="15" r="2.5" /><path d="M12 17.5v2M9 21h6" /></svg>';
    if (name === 'bookOpen') return '<svg viewBox="0 0 24 24" fill="none"><path d="M2 3h6a4 4 0 0 1 4 4v14a3 3 0 0 0-3-3H2z" /><path d="M22 3h-6a4 4 0 0 0-4 4v14a3 3 0 0 1 3-3h7z" /></svg>';
    if (name === 'star') return '<svg viewBox="0 0 24 24" fill="none"><path d="M12 2l2.4 7.4h7.6l-6 4.6 2.3 7-6-4.6-6 4.6 2.3-7-6-4.6h7.6z" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round" /></svg>';
    if (name === 'settings') return '<svg viewBox="0 0 24 24" fill="none"><path d="M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.39a2 2 0 0 0-.73-2.73l-.15-.08a2 2 0 0 1-1-1.74v-.5a2 2 0 0 1 1-1.74l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z" stroke="currentColor" stroke-width="1.5" /><circle cx="12" cy="12" r="3" stroke="currentColor" stroke-width="1.5" /></svg>';
    if (name === 'folder') return '<svg viewBox="0 0 24 24" fill="none"><path d="M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round" /></svg>';
    if (name === 'radio') return '<svg viewBox="0 0 24 24" fill="none"><circle cx="12" cy="12" r="2" stroke="currentColor" stroke-width="1.5" /><path d="M16.24 7.76a6 6 0 0 1 0 8.49m-8.48-.01a6 6 0 0 1 0-8.49m11.31-2.82a10 10 0 0 1 0 14.14m-14.14 0a10 10 0 0 1 0-14.14" stroke="currentColor" stroke-width="1.5" /></svg>';
    if (name === 'sparkles') return '<svg viewBox="0 0 24 24" fill="none"><path d="M9.937 15.5A2 2 0 0 0 8.5 14.063l-6.135-1.582a.5.5 0 0 1 0-.962L8.5 9.936A2 2 0 0 0 9.937 8.5l1.582-6.135a.5.5 0 0 1 .963 0L14.063 8.5a2 2 0 0 0 1.437 1.437l6.135 1.582a.5.5 0 0 1 0 .962L15.5 14.063a2 2 0 0 0-1.437 1.437l-1.582 6.135a.5.5 0 0 1-.963 0z" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round" /></svg>';
    if (name === 'terminal') return '<svg viewBox="0 0 24 24" fill="none"><path d="m4 17 6-6-6-6" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" /><path d="M12 19h8" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" /></svg>';
    if (name === 'globe') return '<svg viewBox="0 0 24 24" fill="none"><circle cx="12" cy="12" r="10" stroke="currentColor" stroke-width="1.5" /><path d="M2 12h20M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z" stroke="currentColor" stroke-width="1.5" /></svg>';
    if (name === 'brain') return '<svg viewBox="0 0 24 24" fill="none"><path d="M12 5a3 3 0 1 0-5.997.125 4 4 0 0 0-2.526 5.77 4 4 0 0 0 .556 6.588A4 4 0 1 0 12 18Z" stroke="currentColor" stroke-width="1.5" /><path d="M12 5a3 3 0 1 1 5.997.125 4 4 0 0 1 2.526 5.77 4 4 0 0 1-.556 6.588A4 4 0 1 1 12 18Z" stroke="currentColor" stroke-width="1.5" /><path d="M15 13a4.5 4.5 0 0 1-3-4 4.5 4.5 0 0 1-3 4" stroke="currentColor" stroke-width="1.5" /></svg>';
    if (name === 'bug') return '<svg viewBox="0 0 24 24" fill="none"><path d="m8 2 1.88 1.88M14.12 3.88 16 2M9 7.13v-1a3.003 3.003 0 1 1 6 0v1M12 20c-3.3 0-6-2.7-6-6v-3a4 4 0 0 1 4-4h4a4 4 0 0 1 4 4v3c0 3.3-2.7 6-6 6M12 20v-9M6.53 9C4.6 8.8 3 7.1 3 5M6 13H2M3 21c0-2.1 1.7-3.9 3.8-4M20.97 5c0 2.1-1.6 3.8-3.5 4M22 13h-4M17.2 17c2.1.1 3.8 1.9 3.8 4" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" /></svg>';
    return '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="10" /></svg>';
  }

  function escapeHtml(s) {
    return String(s === undefined || s === null ? '' : s)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  function _msgId(role, ts, text) {
    const base = String(role || '') + '|' + String(ts || '') + '|' + String(text || '');
    let h = 2166136261;
    for (let i = 0; i < base.length; i++) {
      h ^= base.charCodeAt(i);
      h = Math.imul(h, 16777619);
    }
    return 'm' + (h >>> 0).toString(16);
  }

  function _deletedKeyForSession(sessionKey) {
    return 'cj_dashboard_deleted_v3:' + String(sessionKey || '');
  }

  function loadDeletedSetForSession(sessionKey) {
    deletedMsgIds = new Set();
    try {
      const raw = localStorage.getItem(_deletedKeyForSession(sessionKey)) || '';
      if (!raw) return;
      const arr = JSON.parse(raw);
      if (Array.isArray(arr)) {
        arr.forEach(function(x) { if (typeof x === 'string' && x) deletedMsgIds.add(x); });
      }
    } catch (_e) {}
  }

  function saveDeletedSetForSession(sessionKey) {
    try {
      const arr = Array.from(deletedMsgIds.values()).slice(-500);
      localStorage.setItem(_deletedKeyForSession(sessionKey), JSON.stringify(arr));
    } catch (_e) {}
  }

  async function copyToClipboard(text) {
    const t = String(text || '');
    if (!t) return;
    try {
      if (navigator && navigator.clipboard && typeof navigator.clipboard.writeText === 'function') {
        await navigator.clipboard.writeText(t);
        return;
      }
    } catch (_e) {}
    try {
      const ta = document.createElement('textarea');
      ta.value = t;
      ta.style.position = 'fixed';
      ta.style.left = '-9999px';
      ta.style.top = '0';
      document.body.appendChild(ta);
      ta.focus();
      ta.select();
      document.execCommand('copy');
      document.body.removeChild(ta);
    } catch (_e2) {}
  }

  function sessionKind(sk) {
    if ((sk || '').startsWith('feishu:')) return 'feishu';
    if ((sk || '').startsWith('qq:')) return 'qq';
    if ((sk || '').startsWith('cli:')) return 'cli';
    return 'other';
  }

  function formatTs(ts) {
    const t = String(ts || '').trim();
    if (!t) return '';
    const n = Number(t);
    if (!Number.isFinite(n) || n <= 0) return t;
    try {
      return new Date(n).toLocaleString();
    } catch (_e) {
      return t;
    }
  }

  function switchTab(tabName) {
    currentTab = tabName;
    const btns = document.querySelectorAll('.tab-btn');
    btns.forEach(function(b) {
      const t = b.getAttribute('data-tab') || '';
      if (t === tabName) b.classList.add('active'); else b.classList.remove('active');
    });
    const panels = document.querySelectorAll('.tab-panel');
    panels.forEach(function(p) {
      const t = p.getAttribute('data-tab') || '';
      if (t === tabName) p.classList.add('active'); else p.classList.remove('active');
    });
  }

  function applyTheme(themeName) {
    const body = document.body;
    if (!body) return;
    const t = themeName || 'slate';
    body.setAttribute('data-theme', t);
    try { localStorage.setItem('cj_dashboard_theme', t); } catch (_e) {}
    const nodes = document.querySelectorAll('.theme-btn');
    nodes.forEach(function(n) {
      const x = n.getAttribute('data-theme') || '';
      if (x === t) n.classList.add('active'); else n.classList.remove('active');
    });
  }

  function bootstrapTheme() {
    let t = 'slate';
    try {
      const s = localStorage.getItem('cj_dashboard_theme') || '';
      if (s) t = s;
    } catch (_e) {}
    applyTheme(t);
  }
"""
}
