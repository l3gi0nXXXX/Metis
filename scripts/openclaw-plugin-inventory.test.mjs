import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import { buildInventory, renderMarkdown } from "./openclaw-plugin-inventory.mjs";

const scriptPath = path.join(path.dirname(fileURLToPath(import.meta.url)), "openclaw-plugin-inventory.mjs");

function tempRoot() {
  return fs.mkdtempSync(path.join(os.tmpdir(), "metis-openclaw-inventory-"));
}

function writeJson(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, JSON.stringify(value, null, 2));
}

function writeText(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, value);
}

test("discovers original OpenClaw extension packages without requiring metis.plugin.json", () => {
  const root = tempRoot();
  const pluginRoot = path.join(root, "extensions", "weixin");
  writeJson(path.join(pluginRoot, "package.json"), {
    name: "@vendor/openclaw-weixin",
    version: "1.2.3",
    type: "module",
    dependencies: { zod: "1.0.0" },
    openclaw: {
      extensions: ["./index.ts"],
      channel: { id: "openclaw-weixin", label: "Weixin" },
      install: { npmSpec: "@vendor/openclaw-weixin" },
    },
  });
  writeText(
    path.join(pluginRoot, "index.ts"),
    `
      import { buildChannelConfigSchema } from "openclaw/plugin-sdk/channel-config-schema";
      export default {
        register(api) {
          const appSecret = "fixture-secret";
          api.registerChannel({ plugin: { id: "openclaw-weixin" } });
          api.registerHttpRoute({ path: "/weixin" });
        }
      };
    `
  );

  const inventory = buildInventory({ sources: [{ name: "fixture-openclaw", root }] });

  assert.equal(inventory.summary.plugin_count, 1);
  const plugin = inventory.plugins[0];
  assert.equal(plugin.plugin_id, "openclaw-weixin");
  assert.equal(plugin.package_name, "@vendor/openclaw-weixin");
  assert.equal(plugin.package_version, "1.2.3");
  assert.deepEqual(plugin.requires_metis_manifest, false);
  assert.deepEqual(plugin.requires_wrapper, false);
  assert.deepEqual(plugin.source_patched, false);
  assert.ok(plugin.entry_path.endsWith("index.ts"));
  assert.deepEqual(plugin.plugin_kinds, ["channel", "http-route"]);
  assert.deepEqual(plugin.register_apis, ["registerChannel", "registerHttpRoute"]);
  assert.deepEqual(plugin.sdk_subpaths, ["channel-config-schema"]);
  assert.equal(plugin.metis_status, "missing");
  assert.match(plugin.gap, /channel, http-route/);
  assert.ok(plugin.acceptance_tests.some((item) => item.includes("Original package")));
  assert.ok(plugin.secret_fields.includes("appSecret"));
});

test("records command and hook only plugins as partial current coverage", () => {
  const root = tempRoot();
  const pluginRoot = path.join(root, "extensions", "commands");
  writeJson(path.join(pluginRoot, "package.json"), {
    name: "@vendor/openclaw-commands",
    version: "1.0.0",
    type: "module",
    openclaw: { extensions: ["./index.js"] },
  });
  writeText(
    path.join(pluginRoot, "index.js"),
    `
      export default {
        register(api) {
          api.registerCommand({ name: "hello", handler() {} });
          api.registerHook("message_sent", () => {});
        }
      };
    `
  );

  const inventory = buildInventory({ sources: [{ name: "fixture-openclaw", root }] });

  assert.equal(inventory.summary.plugin_count, 1);
  assert.equal(inventory.plugins[0].metis_status, "partial");
  assert.deepEqual(inventory.plugins[0].plugin_kinds, ["command", "hook"]);
});

test("reports missing sources and renders markdown summary", () => {
  const inventory = buildInventory({ sources: [{ name: "missing", root: path.join(tempRoot(), "missing") }] });

  assert.equal(inventory.summary.plugin_count, 0);
  assert.equal(inventory.summary.diagnostics_count, 1);
  assert.equal(inventory.diagnostics[0].code, "source_missing");

  const markdown = renderMarkdown(inventory);
  assert.match(markdown, /OpenClaw Plugin Compatibility Matrix/);
  assert.match(markdown, /source_missing/);
});

test("discovers a root plugin such as a downloaded third party package", () => {
  const root = tempRoot();
  writeJson(path.join(root, "package.json"), {
    name: "@third-party/clawmate",
    version: "9.9.9",
    type: "module",
    openclaw: { extensions: ["./index.mjs"] },
  });
  writeText(
    path.join(root, "index.mjs"),
    `
      export default {
        register(api) {
          api.registerTool({ name: "clawmate-tool" });
          api.registerProvider({ id: "clawmate-provider" });
        }
      };
    `
  );

  const inventory = buildInventory({ sources: [{ name: "clawmate", root }] });

  assert.equal(inventory.summary.plugin_count, 1);
  assert.equal(inventory.plugins[0].plugin_id, "@third-party/clawmate");
  assert.deepEqual(inventory.plugins[0].plugin_kinds, ["provider", "tool"]);
  assert.equal(inventory.plugins[0].metis_status, "missing");
});

test("discovers package workspace plugins such as ClawMate companion packages", () => {
  const root = tempRoot();
  const pluginRoot = path.join(root, "packages", "clawmate-companion");
  writeJson(path.join(root, "package.json"), { name: "clawmate-monorepo", private: true });
  writeJson(path.join(pluginRoot, "openclaw.plugin.json"), {
    id: "clawmate-companion",
    version: "0.2.0",
    runtime: { pluginEntry: "./index.js" },
  });
  writeJson(path.join(pluginRoot, "package.json"), {
    name: "@clawmate/companion",
    version: "0.2.0",
    type: "module",
  });
  writeText(
    path.join(pluginRoot, "index.js"),
    `
      export default {
        register(api) {
          api.registerInteractiveHandler({ namespace: "clawmate" }, () => {});
        }
      };
    `
  );

  const inventory = buildInventory({ sources: [{ name: "clawmate", root }] });

  assert.equal(inventory.summary.plugin_count, 1);
  assert.equal(inventory.plugins[0].plugin_id, "clawmate-companion");
  assert.equal(inventory.plugins[0].discovered_by, "packages");
  assert.equal(inventory.plugins[0].metis_status, "partial");
});

test("accepts explicit source refs through the CLI for non-git source snapshots", () => {
  const root = tempRoot();
  const outJson = path.join(tempRoot(), "inventory.json");
  writeJson(path.join(root, "package.json"), {
    name: "@tencent/openclaw-weixin",
    version: "0.0.1",
    type: "module",
    openclaw: { extensions: ["./index.ts"], channel: { id: "openclaw-weixin" } },
  });
  writeText(
    path.join(root, "index.ts"),
    `
      export default {
        register(api) {
          api.registerChannel({ plugin: { id: "openclaw-weixin" } });
        }
      };
    `
  );

  execFileSync(process.execPath, [
    scriptPath,
    "--source",
    `openclaw-weixin:${root}`,
    "--source-ref",
    "openclaw-weixin:archive-sha256:fixturehash",
    "--out-json",
    outJson,
  ]);

  const inventory = JSON.parse(fs.readFileSync(outJson, "utf8"));
  assert.equal(inventory.sources[0].ref, "archive-sha256:fixturehash");
  assert.equal(inventory.plugins[0].source_ref, "archive-sha256:fixturehash");
  assert.ok(!inventory.summary.release_blockers.some((item) => item.code === "missing_source_ref"));
});

test("preserves source_missing diagnostics as release blockers", () => {
  const inventory = buildInventory({ sources: [{ name: "qmd", root: path.join(tempRoot(), "qmd") }] });

  assert.equal(inventory.summary.plugin_count, 0);
  assert.equal(inventory.summary.release_ready, false);
  assert.equal(inventory.diagnostics[0].code, "source_missing");
  assert.ok(
    inventory.summary.release_blockers.some(
      (item) => item.code === "source_missing" && item.source === "qmd"
    )
  );
});

test("falls back to source entry for unbuilt workspace packages while recording package entry", () => {
  const root = tempRoot();
  const pluginRoot = path.join(root, "packages", "channels");
  writeJson(path.join(pluginRoot, "package.json"), {
    name: "@openclaw/channels",
    version: "0.1.0",
    type: "module",
    main: "./dist/index.js",
    openclaw: {
      extensions: ["./dist/index.js"],
      channel: { id: "channels" },
    },
  });
  writeText(
    path.join(pluginRoot, "src", "index.ts"),
    `
      export default {
        register(api) {
          api.registerChannel({ plugin: { id: "channels" } });
        }
      };
    `
  );

  const inventory = buildInventory({ sources: [{ name: "openclaw-china", root, ref: "git:fixture" }] });
  const plugin = inventory.plugins[0];

  assert.ok(plugin.entry_path.endsWith("src/index.ts"));
  assert.ok(plugin.published_entry_path.endsWith("dist/index.js"));
  assert.ok(plugin.diagnostics.some((item) => item.code === "entry_uses_source_fallback"));
  assert.ok(!plugin.release_blockers.some((item) => item.code === "missing_entry"));
});

test("classifies setup-only package helpers instead of emitting unexplained unknown kinds", () => {
  const root = tempRoot();
  const pluginRoot = path.join(root, "packages", "setup-helper");
  writeJson(path.join(pluginRoot, "package.json"), {
    name: "@openclaw/setup-helper",
    version: "0.1.0",
    type: "module",
    openclaw: {
      install: { npmSpec: "@openclaw/setup-helper" },
      setupEntry: "./setup.js",
    },
  });
  writeText(path.join(pluginRoot, "setup.js"), "export function setup() { return true; }\n");

  const inventory = buildInventory({ sources: [{ name: "openclaw", root, ref: "git:fixture" }] });
  const plugin = inventory.plugins[0];

  assert.deepEqual(plugin.plugin_kinds, ["setup"]);
  assert.ok(!inventory.summary.by_kind.unknown);
  assert.ok(plugin.runtime_facets_required.includes("setup"));
  assert.equal(plugin.real_plugin_smoke_status, "not-run");
  assert.equal(plugin.behavior_test_status, "not-run");
  assert.ok(plugin.release_blockers.some((item) => item.code === "release_status_not_ready"));
});

test("adds CI-compatible release and runtime status fields to plugin records", () => {
  const root = tempRoot();
  const pluginRoot = path.join(root, "extensions", "tooling");
  writeJson(path.join(pluginRoot, "package.json"), {
    name: "@vendor/tooling",
    version: "1.0.0",
    type: "module",
    openclaw: { extensions: ["./index.js"] },
  });
  writeText(
    path.join(pluginRoot, "index.js"),
    `
      export default {
        register(api) {
          api.registerTool({ name: "fixture" });
        }
      };
    `
  );

  const inventory = buildInventory({ sources: [{ name: "fixture-openclaw", root, ref: "git:fixture" }] });
  const plugin = inventory.plugins[0];

  assert.deepEqual(plugin.runtime_facets_required, ["tool"]);
  assert.equal(plugin.real_plugin_smoke_status, "not-run");
  assert.equal(plugin.behavior_test_status, "not-run");
  assert.ok(Array.isArray(plugin.release_blockers));
  assert.ok(inventory.summary.release_blockers.some((item) => item.code === "release_status_not_ready"));
});

test("classifies OpenClaw web search providers as provider capabilities", () => {
  const root = tempRoot();
  const pluginRoot = path.join(root, "extensions", "duckduckgo");
  writeJson(path.join(pluginRoot, "package.json"), {
    name: "@openclaw/duckduckgo",
    version: "1.0.0",
    type: "module",
    openclaw: { extensions: ["./index.ts"] },
  });
  writeText(
    path.join(pluginRoot, "index.ts"),
    `
      export default {
        register(api) {
          api.registerWebSearchProvider(createProvider());
        }
      };
    `
  );

  const inventory = buildInventory({ sources: [{ name: "openclaw", root, ref: "git:fixture" }] });
  const plugin = inventory.plugins[0];

  assert.deepEqual(plugin.plugin_kinds, ["provider"]);
  assert.deepEqual(plugin.register_apis, ["registerWebSearchProvider"]);
  assert.ok(!inventory.summary.by_kind.unknown);
});

test("classifies plugin-shipped skill bundles as setup facets instead of unknown", () => {
  const root = tempRoot();
  const pluginRoot = path.join(root, "extensions", "open-prose");
  writeJson(path.join(pluginRoot, "package.json"), {
    name: "@openclaw/open-prose",
    version: "1.0.0",
    type: "module",
    description: "OpenProse VM skill pack plugin.",
    openclaw: { extensions: ["./index.ts"] },
  });
  writeText(
    path.join(pluginRoot, "index.ts"),
    `
      export default definePluginEntry({
        register(_api) {
        }
      });
    `
  );

  const inventory = buildInventory({ sources: [{ name: "openclaw", root, ref: "git:fixture" }] });
  const plugin = inventory.plugins[0];

  assert.deepEqual(plugin.plugin_kinds, ["setup"]);
  assert.deepEqual(plugin.runtime_facets_required, ["setup"]);
  assert.ok(!inventory.summary.by_kind.unknown);
});
