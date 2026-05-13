import fs from "node:fs";
import http from "node:http";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";
import { describe, expect, it } from "vitest";

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(here, "../../..");
const controlUiRoot = path.join(repoRoot, "assets/control-ui");
const chromePath = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";

function contentType(file: string): string {
  if (file.endsWith(".html")) {
    return "text/html; charset=utf-8";
  }
  if (file.endsWith(".js")) {
    return "text/javascript; charset=utf-8";
  }
  if (file.endsWith(".css")) {
    return "text/css; charset=utf-8";
  }
  if (file.endsWith(".json") || file.endsWith(".map")) {
    return "application/json; charset=utf-8";
  }
  if (file.endsWith(".svg")) {
    return "image/svg+xml";
  }
  if (file.endsWith(".png")) {
    return "image/png";
  }
  return "application/octet-stream";
}

function startServer(): Promise<{ url: string; close: () => Promise<void> }> {
  const server = http.createServer((req, res) => {
    const requestUrl = new URL(req.url ?? "/", "http://127.0.0.1");
    if (requestUrl.pathname === "/__metis/control-ui-config.json") {
      res.writeHead(200, { "content-type": "application/json" });
      res.end(JSON.stringify({ basePath: "/", wsUrl: "ws://127.0.0.1:18788/ws" }));
      return;
    }
    if (requestUrl.pathname === "/__metis/control-ui-auth.json") {
      res.writeHead(200, { "content-type": "application/json" });
      res.end(JSON.stringify({ authToken: "smoke-token", authPassword: "" }));
      return;
    }
    const rel =
      requestUrl.pathname === "/" || requestUrl.pathname === "/chat"
        ? "index.html"
        : requestUrl.pathname.replace(/^\/+/, "");
    const full = path.resolve(controlUiRoot, rel);
    if (
      !full.startsWith(controlUiRoot) ||
      !fs.existsSync(full) ||
      fs.statSync(full).isDirectory()
    ) {
      res.writeHead(404);
      res.end("not found");
      return;
    }
    res.writeHead(200, { "content-type": contentType(full) });
    fs.createReadStream(full).pipe(res);
  });

  return new Promise((resolve, reject) => {
    server.on("error", reject);
    server.listen(0, "127.0.0.1", () => {
      const address = server.address();
      if (!address || typeof address === "string") {
        reject(new Error("failed to bind test server"));
        return;
      }
      resolve({
        url: `http://127.0.0.1:${address.port}`,
        close: () => new Promise((done) => server.close(() => done())),
      });
    });
  });
}

describe("Metis control-ui browser smoke", () => {
  it.skipIf(!fs.existsSync(chromePath))("registers the metis app in a real browser", async () => {
    const server = await startServer();
    const browser = await chromium.launch({ headless: true, executablePath: chromePath });
    try {
      const page = await browser.newPage();
      const errors: string[] = [];
      page.on("pageerror", (err) => errors.push(err.message));
      page.on("requestfailed", (req) => errors.push(`${req.url()} ${req.failure()?.errorText}`));
      await page.goto(`${server.url}/chat?session=agent%3Amain%3Aexplicit%3Acli%3Amain`, {
        waitUntil: "domcontentloaded",
      });
      await page.waitForFunction(() => Boolean(customElements.get("metis-app")));
      const appState = await page.evaluate(() => ({
        defined: Boolean(customElements.get("metis-app")),
        renderedText: document.querySelector("metis-app")?.textContent?.trim().slice(0, 64) ?? "",
        scopedSessionToken: sessionStorage.getItem("metis.control.token.v1:ws://127.0.0.1:18788/ws"),
        legacyLocalToken: localStorage.getItem("metis.control.token.v1"),
        scopedLocalToken: localStorage.getItem("metis.control.token.v1:ws://127.0.0.1:18788/ws"),
      }));
      expect(errors).toEqual([]);
      expect(appState.defined).toBe(true);
      expect(appState.renderedText).toContain("Metis");
      expect(appState.scopedSessionToken).toBe("smoke-token");
      expect(appState.legacyLocalToken).toBeNull();
      expect(appState.scopedLocalToken).toBeNull();
    } finally {
      await browser.close();
      await server.close();
    }
  }, 20_000);
});
