import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { shouldMetisAppRenderForChangedKeys } from "./app-render-boundary.ts";

const here = path.dirname(fileURLToPath(import.meta.url));
const uiRoot = path.resolve(here, "../..");
const repoRoot = path.resolve(uiRoot, "..");
const forbiddenBrandTerms = [
  `Open${"Claw"}`,
  `OPEN${"CLAW"}`,
  `open${"claw"}`,
];

function read(rel: string): string {
  return fs.readFileSync(path.join(repoRoot, rel), "utf8");
}

function walk(dir: string, out: string[] = []): string[] {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.name === "node_modules") {
      continue;
    }
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      walk(full, out);
      continue;
    }
    out.push(full);
  }
  return out;
}

function builtJavaScriptFiles(): string[] {
  const assetsDir = path.join(repoRoot, "assets/control-ui/assets");
  if (!fs.existsSync(assetsDir)) {
    return [];
  }
  return fs
    .readdirSync(assetsDir)
    .filter((entry) => entry.endsWith(".js"))
    .map((entry) => path.join(assetsDir, entry));
}

describe("Metis control-ui contracts", () => {
  it("does not expose upstream branding in source assets", () => {
    const offenders = walk(uiRoot)
      .filter((file) => /\.(ts|js|mjs|json|html|css|svg|map)$/.test(file))
      .flatMap((file) => {
        const text = fs.readFileSync(file, "utf8");
        return forbiddenBrandTerms
          .filter((needle) => text.includes(needle))
          .map((needle) => `${path.relative(repoRoot, file)}: ${needle}`);
      });

    expect(offenders).toEqual([]);
  });

  it("keeps chat pages out of nodes polling", () => {
    const polling = read("ui/src/ui/app-polling.ts");
    const gateway = read("ui/src/ui/app-gateway.ts");
    const settings = read("ui/src/ui/app-settings.ts");

    expect(polling).toContain("function isNodesPollingTab(tab: string): boolean");
    expect(polling).toContain("if (!isNodesPollingTab(host.tab))");
    expect(gateway).toContain('if (host.tab === "nodes" || host.tab === "overview")');
    expect(settings).toContain('next === "nodes" || next === "overview"');
    expect(settings).toContain("stopNodesPolling(host as unknown as");
  });

  it("builds decorators into browser-executable JavaScript", () => {
    const tsconfig = read("ui/tsconfig.json");
    expect(tsconfig).toContain('"experimentalDecorators": true');
    expect(tsconfig).toContain('"useDefineForClassFields": false');

    const offenders = builtJavaScriptFiles().flatMap((file) => {
      const text = fs.readFileSync(file, "utf8");
      const hasDecoratorSyntax =
        /(^|[\s;(])@(customElement|state|property|query|eventOptions)\s*\(/m.test(text);
      return hasDecoratorSyntax ? [path.relative(repoRoot, file)] : [];
    });
    expect(offenders).toEqual([]);
  });

  it("uses stable built asset names for gateway static routes", () => {
    const viteConfig = read("ui/vite.config.ts");
    const index = read("assets/control-ui/index.html");

    expect(viteConfig).toContain('entryFileNames: "assets/[name].js"');
    expect(viteConfig).toContain('chunkFileNames: "assets/[name].js"');
    expect(viteConfig).toContain('assetFileNames: "assets/[name][extname]"');
    expect(index).toContain('src="./assets/index.js"');
    expect(index).toContain('href="./assets/index.css"');
    expect(index).not.toMatch(/assets\/index-[A-Za-z0-9_-]+\.(?:js|css)/);
  });

  it("does not rerender the chat root for nodes-only state changes", () => {
    expect(shouldMetisAppRenderForChangedKeys("chat", ["nodes"])).toBe(false);
    expect(shouldMetisAppRenderForChangedKeys("chat", ["nodesLoading"])).toBe(false);
    expect(shouldMetisAppRenderForChangedKeys("chat", ["nodes", "chatMessages"])).toBe(true);
    expect(shouldMetisAppRenderForChangedKeys("nodes", ["nodes"])).toBe(true);
  });

  it("keeps gateway tokens out of URL hash writeback", () => {
    const index = read("ui/index.html");

    expect(index).not.toContain("window.location.hash =");
    expect(index).not.toContain('hash = "token="');
    expect(index).toContain("metis.control.token.v1");
    expect(index).toContain("writeTokenVariants(sessionStorage");
    expect(index).not.toContain("writeTokenVariants(localStorage");
  });
});
