package metis.gateway.runtime

public func gatewayBuildControlUiBootstrapScript(
    dashboardDeviceId: String,
    dashboardDeviceToken: String,
    dashboardAuthToken: String,
    dashboardAuthPassword: String,
    dashboardBasePath: String,
    dashboardWsFallback: String
): String {
    """
  const CONTROL_UI_BOOTSTRAP_CONFIG_PATH = '${gatewayControlUiJsonEscape(CONTROL_UI_BOOTSTRAP_CONFIG_PATH)}';
  const DASHBOARD_DEVICE_ID = '${gatewayControlUiJsonEscape(dashboardDeviceId)}';
  const DASHBOARD_DEVICE_TOKEN = '${gatewayControlUiJsonEscape(dashboardDeviceToken)}';
  const DASHBOARD_AUTH_TOKEN = '${gatewayControlUiJsonEscape(dashboardAuthToken)}';
  const DASHBOARD_AUTH_PASSWORD = '${gatewayControlUiJsonEscape(dashboardAuthPassword)}';
  const DASHBOARD_BASE_PATH = '${gatewayControlUiJsonEscape(dashboardBasePath)}';
  const DASHBOARD_WS_FALLBACK = '${gatewayControlUiJsonEscape(dashboardWsFallback)}';
  let dashboardBootstrapConfig = {
    basePath: DASHBOARD_BASE_PATH,
    assistantName: 'Metis',
    assistantAvatar: ''
  };

  function dashboardBootstrapConfigUrl() {
    if (!DASHBOARD_BASE_PATH) return CONTROL_UI_BOOTSTRAP_CONFIG_PATH;
    return DASHBOARD_BASE_PATH + CONTROL_UI_BOOTSTRAP_CONFIG_PATH;
  }

  async function dashboardLoadBootstrapConfig() {
    try {
      const res = await fetch(dashboardBootstrapConfigUrl(), {
        headers: { 'X-Metis-Client-Mode': 'control-ui-browser' }
      });
      if (!res.ok) {
        throw new Error('HTTP ' + res.status);
      }
      const data = await res.json();
      if (data && typeof data === 'object') {
        dashboardBootstrapConfig = {
          basePath: String(data.basePath || DASHBOARD_BASE_PATH || ''),
          assistantName: String(data.assistantName || 'Metis'),
          assistantAvatar: String(data.assistantAvatar || '')
        };
      }
    } catch (e) {
      console.warn('control ui bootstrap config load failed:', e);
    }
    try {
      window.__LEGACY_CONTROL_UI_BOOTSTRAP_CONFIG__ = dashboardBootstrapConfig;
    } catch (_e) {}
    return dashboardBootstrapConfig;
  }

  function dashboardConfiguredBasePath() {
    if (dashboardBootstrapConfig && typeof dashboardBootstrapConfig.basePath === 'string') {
      return dashboardBootstrapConfig.basePath;
    }
    return DASHBOARD_BASE_PATH;
  }

  function dashboardApplyBootstrapConfigUi() {
    const assistantName = dashboardBootstrapConfig && dashboardBootstrapConfig.assistantName
      ? String(dashboardBootstrapConfig.assistantName)
      : 'Metis';
    try { document.title = assistantName + ' Dashboard'; } catch (_e) {}
    try {
      const heading = document.querySelector('.shell h1');
      if (heading) heading.textContent = assistantName + ' Dashboard';
    } catch (_e2) {}
  }

  function dashboardApiUrl(path) {
    const p = String(path || '');
    const normalized = p.startsWith('/') ? p : ('/' + p);
    const configuredBasePath = dashboardConfiguredBasePath();
    if (!configuredBasePath) return normalized;
    return configuredBasePath + normalized;
  }

  function dashboardHeaders(base) {
    const headers = Object.assign({}, base || {});
    if (DASHBOARD_DEVICE_ID) headers['X-Metis-Device-Id'] = DASHBOARD_DEVICE_ID;
    if (DASHBOARD_DEVICE_TOKEN) headers['X-Metis-Device-Token'] = DASHBOARD_DEVICE_TOKEN;
    if (DASHBOARD_AUTH_TOKEN) headers['X-Metis-Gateway-Token'] = DASHBOARD_AUTH_TOKEN;
    if (DASHBOARD_AUTH_PASSWORD) headers['X-Metis-Gateway-Password'] = DASHBOARD_AUTH_PASSWORD;
    headers['X-Metis-Client-Mode'] = 'control-ui-browser';
    headers['X-Metis-Operator-Scopes'] = 'admin,read,write,approvals,pairing,talk-secrets';
    return headers;
  }

  async function apiGet(url, timeoutMs) {
    const ms = Number(timeoutMs || 12000);
    let ctrl = null;
    let t = null;
    const opts = { headers: dashboardHeaders({}) };
    try {
      ctrl = new AbortController();
      opts.signal = ctrl.signal;
      t = setTimeout(function() {
        try { ctrl.abort(); } catch (_e) {}
      }, ms);
    } catch (_e2) {
      // AbortController not available; best-effort without timeout
    }
    const res = await fetch(dashboardApiUrl(url), opts);
    if (t) {
      try { clearTimeout(t); } catch (_e3) {}
    }
    if (!res.ok) {
      throw new Error('HTTP ' + res.status);
    }
    return await res.json();
  }

  async function apiPost(url, formData) {
    const body = new URLSearchParams(formData || {}).toString();
    const res = await fetch(dashboardApiUrl(url), {
      method: 'POST',
      headers: dashboardHeaders({ 'content-type': 'application/x-www-form-urlencoded;charset=UTF-8' }),
      body: body
    });
    if (!res.ok) {
      throw new Error('HTTP ' + res.status);
    }
    return await res.json();
  }
"""
}
