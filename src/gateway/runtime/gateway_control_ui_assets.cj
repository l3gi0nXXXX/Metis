package metis.gateway.runtime

import magic.jsonable.*

import metis.gateway.model.GatewayConfig

import std.fs.{Directory, File, FileInfo, Path, exists}
import stdx.encoding.json.{JsonObject, JsonString}
import stdx.net.http.Server

public struct GatewayControlUiRootState {
    public let kind: String
    public let rootPath: String
    public let indexPath: String
    public let message: String

    public init(kind!: String, rootPath!: String, indexPath!: String, message!: String = "") {
        this.kind = kind
        this.rootPath = rootPath
        this.indexPath = indexPath
        this.message = message
    }
}

private func gatewayControlUiBundledRootPath(): Path {
    gatewayCjpmProjectDirForExternalServe().join("assets").join("control-ui")
}

private func gatewayControlUiConfiguredRootPath(cfg: GatewayConfig): Path {
    let trimmed = cfg.controlUi.root.trimAscii()
    if (trimmed.isEmpty()) {
        return Path("")
    }
    let p = Path(trimmed)
    if (p.isAbsolute()) {
        return p
    }
    Path(trimmed)
}

public func gatewayControlUiResolveRootState(cfg: GatewayConfig): GatewayControlUiRootState {
    let root = gatewayControlUiConfiguredRootPath(cfg)
    let rootText = root.toString()
    if (rootText.trimAscii().isEmpty()) {
        let bundled = gatewayControlUiBundledRootPath()
        if (exists(bundled) && FileInfo(bundled).isDirectory()) {
            let bundledIndex = bundled.join("index.html")
            if (exists(bundledIndex) && FileInfo(bundledIndex).isRegular()) {
                return GatewayControlUiRootState(
                    kind: "bundled",
                    rootPath: bundled.toString(),
                    indexPath: bundledIndex.toString(),
                    message: ""
                )
            }
        }
        return GatewayControlUiRootState(kind: "inline-fallback", rootPath: "", indexPath: "", message: "")
    }
    if (!exists(root)) {
        return GatewayControlUiRootState(
            kind: "missing",
            rootPath: rootText,
            indexPath: "",
            message: "Configured Control UI root does not exist."
        )
    }
    let info = FileInfo(root)
    if (!info.isDirectory()) {
        return GatewayControlUiRootState(
            kind: "invalid",
            rootPath: rootText,
            indexPath: "",
            message: "Configured Control UI root is not a directory."
        )
    }
    let indexPath = root.join("index.html")
    if (!exists(indexPath) || !FileInfo(indexPath).isRegular()) {
        return GatewayControlUiRootState(
            kind: "missing-index",
            rootPath: rootText,
            indexPath: indexPath.toString(),
            message: "Configured Control UI root does not contain index.html."
        )
    }
    GatewayControlUiRootState(
        kind: "resolved",
        rootPath: rootText,
        indexPath: indexPath.toString(),
        message: ""
    )
}

public func gatewayControlUiAssetMode(cfg: GatewayConfig): String {
    let state = gatewayControlUiResolveRootState(cfg)
    if (state.kind == "bundled") { return "bundled-root" }
    if (state.kind == "resolved") { return "static-root" }
    "inline-fallback"
}

private func gatewayControlUiMimeTypeFor(path: String): String {
    let lowered = path.toAsciiLower()
    if (lowered.endsWith(".html")) { return "text/html; charset=utf-8" }
    if (lowered.endsWith(".js") || lowered.endsWith(".mjs")) { return "text/javascript; charset=utf-8" }
    if (lowered.endsWith(".css")) { return "text/css; charset=utf-8" }
    if (lowered.endsWith(".json")) { return "application/json; charset=utf-8" }
    if (lowered.endsWith(".svg")) { return "image/svg+xml; charset=utf-8" }
    if (lowered.endsWith(".txt")) { return "text/plain; charset=utf-8" }
    if (lowered.endsWith(".map")) { return "application/json; charset=utf-8" }
    "application/octet-stream"
}

private func gatewayControlUiCanServeAsText(path: String): Bool {
    let lowered = path.toAsciiLower()
    lowered.endsWith(".html") ||
    lowered.endsWith(".js") ||
    lowered.endsWith(".mjs") ||
    lowered.endsWith(".css") ||
    lowered.endsWith(".json") ||
    lowered.endsWith(".svg") ||
    lowered.endsWith(".txt") ||
    lowered.endsWith(".map")
}

public func gatewayControlUiAssetsUnavailableHtml(cfg: GatewayConfig, state: GatewayControlUiRootState): String {
    let configured = if (state.rootPath.trimAscii().isEmpty()) { cfg.controlUi.root.trimAscii() } else { state.rootPath }
    let detail = if (state.message.trimAscii().isEmpty()) { "Control UI assets are unavailable." } else { state.message }
    """
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Control UI Assets Unavailable</title>
    <style>
      :root { color-scheme: light; }
      body {
        margin: 0;
        font-family: ui-sans-serif, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
        background: linear-gradient(180deg, #f8fafc 0%, #e2e8f0 100%);
        color: #0f172a;
      }
      .shell {
        max-width: 860px;
        margin: 48px auto;
        padding: 32px;
        background: rgba(255,255,255,0.92);
        border: 1px solid rgba(15,23,42,0.08);
        border-radius: 20px;
        box-shadow: 0 24px 80px rgba(15,23,42,0.10);
      }
      h1 { margin: 0 0 12px; font-size: 28px; }
      p { line-height: 1.6; }
      code {
        display: inline-block;
        padding: 2px 6px;
        border-radius: 8px;
        background: #e2e8f0;
        font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
      }
      .block {
        margin-top: 18px;
        padding: 14px 16px;
        border-radius: 14px;
        background: #0f172a;
        color: #e2e8f0;
      }
    </style>
  </head>
  <body>
    <main class="shell">
      <h1>Control UI Assets Unavailable</h1>
      <p>${gatewayControlUiJsonEscape(detail)}</p>
      <div class="block">Configured root: <code>${gatewayControlUiJsonEscape(configured)}</code></div>
      <p>The formal Control UI path is static assets. Set <code>gateway.controlUi.root</code> to a built UI directory that contains <code>index.html</code>.</p>
    </main>
  </body>
</html>
"""
}

public func gatewayControlUiRootStateJson(cfg: GatewayConfig): JsonObject {
    let state = gatewayControlUiResolveRootState(cfg)
    let out = JsonObject()
    out.put("kind", JsonString(state.kind))
    out.put("rootPath", JsonString(state.rootPath))
    out.put("indexPath", JsonString(state.indexPath))
    out.put("message", JsonString(state.message))
    out.put("staticServingEnabled", (state.kind == "resolved" || state.kind == "bundled").toJsonValue())
    out.put("inlineFallback", (state.kind == "inline-fallback").toJsonValue())
    out
}

public func gatewayControlUiRootIndexHtml(cfg: GatewayConfig): Option<String> {
    let state = gatewayControlUiResolveRootState(cfg)
    if (state.kind != "resolved" && state.kind != "bundled") {
        return None<String>
    }
    try {
        Some(String.fromUtf8(File.readFrom(Path(state.indexPath))))
    } catch (_e: Exception) {
        None<String>
    }
}

private func gatewayRegisterControlUiStaticAssetRoutesUnder(
    server: Server,
    cfg: GatewayConfig,
    root: Path,
    dir: Path
): Int64 {
    var count: Int64 = 0
    let rootPrefix = root.normalize().toString().replace("\\", "/")
    let rootPrefixWithSlash = if (rootPrefix.endsWith("/")) { rootPrefix } else { rootPrefix + "/" }
    for (entry in Directory.readFrom(dir)) {
        let path = entry.path
        if (entry.isDirectory()) {
            count += gatewayRegisterControlUiStaticAssetRoutesUnder(server, cfg, root, path)
            continue
        }
        let info = FileInfo(path)
        if (!info.isRegular()) {
            continue
        }
        let full = path.normalize().toString().replace("\\", "/")
        if (!full.startsWith(rootPrefixWithSlash)) {
            continue
        }
        let rel = full.replace(rootPrefixWithSlash, "")
        if (rel.isEmpty() || rel == "index.html") {
            continue
        }
        if (!gatewayControlUiCanServeAsText(rel)) {
            continue
        }
        let routePath = "/" + rel
        let contentType = gatewayControlUiMimeTypeFor(rel)
        let diskPath = path
        GatewayControlUiRuntime.registerRoute(server, cfg, routePath, { ctx =>
            let rb = ctx.responseBuilder
            rb.header("content-type", contentType)
            rb.header("cache-control", "no-cache")
            try {
                rb.body(String.fromUtf8(File.readFrom(diskPath)))
            } catch (e: Exception) {
                rb.body("asset read failed: ${gatewayControlUiJsonEscape(e.message)}")
            }
        })
        count += 1
    }
    let indexPath = dir.join("index.html")
    if (exists(indexPath) && FileInfo(indexPath).isRegular()) {
        let normalizedDir = dir.normalize().toString().replace("\\", "/")
        if (normalizedDir.startsWith(rootPrefixWithSlash)) {
            let relDir = normalizedDir.replace(rootPrefixWithSlash, "")
            if (!relDir.isEmpty()) {
                let routePath = "/" + relDir
                let diskPath = indexPath
                GatewayControlUiRuntime.registerRoute(server, cfg, routePath, { ctx =>
                    let rb = ctx.responseBuilder
                    rb.header("content-type", "text/html; charset=utf-8")
                    rb.header("cache-control", "no-cache")
                    try {
                        rb.body(String.fromUtf8(File.readFrom(diskPath)))
                    } catch (e: Exception) {
                        rb.body("asset read failed: ${gatewayControlUiJsonEscape(e.message)}")
                    }
                })
                count += 1
            }
        }
    }
    count
}

public func gatewayRegisterControlUiStaticAssetRoutes(server: Server, cfg: GatewayConfig): Int64 {
    let state = gatewayControlUiResolveRootState(cfg)
    if (state.kind != "resolved" && state.kind != "bundled") {
        return 0
    }
    let root = Path(state.rootPath)
    gatewayRegisterControlUiStaticAssetRoutesUnder(server, cfg, root, root)
}
