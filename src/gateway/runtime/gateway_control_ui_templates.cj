package metis.gateway.runtime

public func gatewayBuildControlUiOfflineHtml(wsDisplayUrl: String): String {
    """
<!doctype html>
<html>
<head>
  <meta charset="utf-8" />
  <title>Metis Dashboard</title>
  <style>
    body {
      margin: 0;
      font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      background: #f5f5f7;
      color: #111827;
    }
    .shell {
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 24px;
      box-sizing: border-box;
    }
    .card {
      width: 380px;
      max-width: 100%;
      background: #ffffff;
      border-radius: 18px;
      box-shadow: 0 18px 45px rgba(15, 23, 42, 0.16);
      padding: 26px 28px 22px;
      box-sizing: border-box;
    }
    .logo {
      width: 40px;
      height: 40px;
      border-radius: 20px;
      background: #fee2e2;
      color: #b91c1c;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      font-size: 22px;
      margin-bottom: 10px;
    }
    h1 {
      margin: 0 0 4px 0;
      font-size: 22px;
      font-weight: 650;
    }
    .sub {
      margin: 0 0 16px 0;
      font-size: 13px;
      color: #6b7280;
    }
    .field {
      margin-bottom: 14px;
    }
    .field label {
      display: block;
      font-size: 12px;
      font-weight: 600;
      color: #6b7280;
      margin-bottom: 4px;
    }
    .field input[type="text"] {
      width: 100%;
      min-height: 48px;
      box-sizing: border-box;
      border-radius: 8px;
      border: 1px solid #d1d5db;
      padding: 12px 14px;
      font-size: 14px;
      line-height: 1.45;
      color: #111827;
      background: #f9fafb;
    }
    .field pre {
      margin: 0;
      padding: 10px 12px;
      border-radius: 8px;
      background: #f9fafb;
      border: 1px solid #e5e7eb;
      font-size: 12px;
      font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace;
      white-space: pre-wrap;
      color: #111827;
    }
    .error {
      margin-top: 10px;
      padding: 8px 10px;
      border-radius: 8px;
      background: #fee2e2;
      color: #b91c1c;
      font-size: 12px;
      text-align: center;
    }
  </style>
</head>
<body>
  <div class="shell">
    <div class="card">
      <div class="logo">🐾</div>
      <h1>Metis Gateway</h1>
      <p class="sub">当前网关未运行，请先在本机启动 gateway 后再打开仪表盘。</p>
      <div class="field">
        <label>WebSocket URL</label>
        <input type="text" readonly value="${wsDisplayUrl}" />
      </div>
      <div class="field">
        <label>如何启动网关</label>
        <pre>1. 在项目根目录启动网关:
   cjpm run -- gateway serve

2. 启动 Dashboard (可选):
   metis dashboard --open</pre>
      </div>
      <div class="error">disconnected: gateway.running = false</div>
    </div>
  </div>
</body>
</html>
"""
}
