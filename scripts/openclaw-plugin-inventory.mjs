#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const TEXT_EXTENSIONS = new Set([".js", ".mjs", ".cjs", ".ts", ".tsx", ".json"]);
const SKIP_DIRS = new Set([".git", "node_modules", "coverage", ".turbo", ".next", ".cache"]);
const STATUS_VALUES = new Set(["aligned", "partial", "missing", "not-applicable"]);

const REGISTER_API_PATTERNS = new Map([
  ["registerChannel", /\bregisterChannel\b/g],
  ["registerHttpRoute", /\bregisterHttpRoute\b/g],
  ["registerHttpHandler", /\bregisterHttpHandler\b/g],
  ["registerTool", /\bregisterTool\b/g],
  ["registerProvider", /\bregisterProvider\b/g],
  ["registerWebSearchProvider", /\bregisterWebSearchProvider\b/g],
  ["registerHook", /\bregisterHook\b/g],
  ["registerMessageHook", /\bregisterMessageHook\b/g],
  ["registerCommand", /\bregisterCommand\b/g],
  ["registerCli", /\bregisterCli\b/g],
  ["registerInteractiveHandler", /\bregisterInteractiveHandler\b/g],
  ["registerApprovalHandler", /\bregisterApprovalHandler\b/g],
  ["registerMemoryEmbeddingProvider", /\bregisterMemoryEmbeddingProvider\b/g],
  ["registerGatewayMethod", /\bregisterGatewayMethod\b/g],
  ["registerService", /\bregisterService\b/g],
]);

const KIND_BY_API = new Map([
  ["registerChannel", "channel"],
  ["registerHttpRoute", "http-route"],
  ["registerHttpHandler", "http-route"],
  ["registerTool", "tool"],
  ["registerProvider", "provider"],
  ["registerWebSearchProvider", "provider"],
  ["registerHook", "hook"],
  ["registerMessageHook", "hook"],
  ["registerCommand", "command"],
  ["registerCli", "cli"],
  ["registerInteractiveHandler", "interactive"],
  ["registerApprovalHandler", "approval"],
  ["registerMemoryEmbeddingProvider", "memory"],
  ["registerGatewayMethod", "gateway-method"],
  ["registerService", "service"],
]);

const HIGH_RISK_KIND_PATTERNS = [
  ["browser", /\bbrowser\b|playwright|puppeteer/i],
  ["process", /\bchild_process\b|\bspawn\(|\bexecFile?\(/i],
  ["realtime", /\brealtime\b|websocket|ws\b|voice-call|rtc/i],
  ["media", /\bmedia\b|sendMedia|outbound-media|speech|image-generation|video-generation/i],
  ["memory", /\bmemory\b|embedding/i],
];

function usage() {
  return `Usage:
  node scripts/openclaw-plugin-inventory.mjs --source name:/path [--source name:/path ...] [--source-ref name:ref] --out-json file [--out-md file]

Examples:
  node scripts/openclaw-plugin-inventory.mjs \\
    --source openclaw:/Users/me/openclaw \\
    --source openclaw-china:/Users/me/openclaw-china \\
    --source openclaw-weixin:/tmp/openclaw-weixin \\
    --source-ref openclaw-weixin:archive-sha256:... \\
    --out-json develop_steps/openclaw-plugin-compatibility-matrix.json
`;
}

function parseArgs(argv) {
  const sources = [];
  const sourceRefs = new Map();
  let outJson = "";
  let outMd = "";
  let pretty = true;
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--source") {
      const value = argv[++i];
      if (!value || !value.includes(":")) {
        throw new Error("--source must be name:/absolute/or/relative/path");
      }
      const [name, ...rest] = value.split(":");
      sources.push({ name: name.trim(), root: rest.join(":").trim() });
    } else if (arg === "--source-ref") {
      const value = argv[++i];
      if (!value || !value.includes(":")) {
        throw new Error("--source-ref must be name:git-or-archive-ref");
      }
      const [name, ...rest] = value.split(":");
      const ref = rest.join(":").trim();
      if (!name.trim() || !ref) {
        throw new Error("--source-ref must be name:git-or-archive-ref");
      }
      sourceRefs.set(name.trim(), ref);
    } else if (arg === "--out-json") {
      outJson = argv[++i] ?? "";
    } else if (arg === "--out-md") {
      outMd = argv[++i] ?? "";
    } else if (arg === "--compact") {
      pretty = false;
    } else if (arg === "--help" || arg === "-h") {
      console.log(usage());
      process.exit(0);
    } else {
      throw new Error(`Unknown argument: ${arg}`);
    }
  }
  if (sources.length === 0) {
    throw new Error("At least one --source is required");
  }
  if (!outJson) {
    throw new Error("--out-json is required");
  }
  for (const name of sourceRefs.keys()) {
    if (!sources.some((source) => source.name === name)) {
      throw new Error(`--source-ref was provided for unknown source: ${name}`);
    }
  }
  for (const source of sources) {
    if (sourceRefs.has(source.name)) {
      source.ref = sourceRefs.get(source.name);
    }
  }
  return { sources, outJson, outMd, pretty };
}

function readJsonIfExists(file) {
  if (!fs.existsSync(file)) {
    return null;
  }
  return JSON.parse(fs.readFileSync(file, "utf8"));
}

function safeRelative(from, target) {
  if (!target) {
    return "";
  }
  return path.relative(from, target).replaceAll(path.sep, "/") || ".";
}

function hasPluginShape(dir) {
  if (!fs.existsSync(dir) || !fs.statSync(dir).isDirectory()) {
    return false;
  }
  const packagePath = path.join(dir, "package.json");
  const openclawManifest = path.join(dir, "openclaw.plugin.json");
  if (fs.existsSync(openclawManifest)) {
    return true;
  }
  const pkg = readJsonIfExists(packagePath);
  if (!pkg) {
    return false;
  }
  return Boolean(
    pkg.openclaw?.extensions ||
      pkg.openclaw?.entry ||
      pkg.openclaw?.channel ||
      pkg.openclaw?.install ||
      pkg.openclaw?.setupEntry ||
      pkg.moltbot?.extensions ||
      pkg.clawdbot?.extensions
  );
}

function discoverPluginRoots(sourceRoot) {
  const roots = new Map();
  if (hasPluginShape(sourceRoot)) {
    roots.set(path.resolve(sourceRoot), "root");
  }
  const conventionalDirs = ["extensions", "plugins", "packages"];
  for (const dirName of conventionalDirs) {
    const parent = path.join(sourceRoot, dirName);
    if (!fs.existsSync(parent) || !fs.statSync(parent).isDirectory()) {
      continue;
    }
    for (const entry of fs.readdirSync(parent, { withFileTypes: true })) {
      if (entry.isDirectory()) {
        const candidate = path.join(parent, entry.name);
        if (hasPluginShape(candidate)) {
          roots.set(path.resolve(candidate), dirName);
        }
      }
    }
  }
  return [...roots.entries()].map(([root, discoveredBy]) => ({ root, discoveredBy }));
}

function entryCandidateRecords(pluginRoot, pkg, openclawManifest) {
  const candidates = [];
  const append = (value, source = "fallback") => {
    if (!value) {
      return;
    }
    if (Array.isArray(value)) {
      value.forEach((item) => append(item, source));
      return;
    }
    if (typeof value === "string") {
      candidates.push({ value, source });
    }
  };

  append(openclawManifest?.entry, "manifest");
  append(openclawManifest?.pluginEntry, "manifest");
  append(openclawManifest?.runtime?.openclawEntry, "manifest");
  append(openclawManifest?.runtime?.pluginEntry, "manifest");
  append(pkg?.openclaw?.extensions, "package");
  append(pkg?.openclaw?.entry, "package");
  append(pkg?.openclaw?.setupEntry, "package");
  append(openclawManifest?.setupEntry, "manifest");
  append(pkg?.module, "package");
  append(pkg?.main, "package");
  if (typeof pkg?.exports === "string") {
    append(pkg.exports, "package");
  } else if (pkg?.exports?.["."]) {
    const dot = pkg.exports["."];
    if (typeof dot === "string") {
      append(dot, "package");
    } else {
      append(dot.default, "package");
      append(dot.import, "package");
      append(dot.require, "package");
    }
  }
  append("dist/index.js", "published-fallback");
  append(["src/index.ts", "src/index.js", "index.ts", "index.js", "index.mjs"], "source-fallback");

  const seen = new Set();
  return candidates
    .map((candidate) => ({
      value: candidate.value,
      source: candidate.source,
      path: path.resolve(pluginRoot, candidate.value),
    }))
    .filter((candidate) => {
      if (seen.has(candidate.path)) {
        return false;
      }
      seen.add(candidate.path);
      return true;
    });
}

function resolveEntry(pluginRoot, pkg, openclawManifest) {
  const candidates = entryCandidateRecords(pluginRoot, pkg, openclawManifest);
  const publishedEntry = candidates.find((candidate) => candidate.source !== "source-fallback")?.path ?? "";
  for (const candidate of candidates) {
    if (fs.existsSync(candidate.path) && fs.statSync(candidate.path).isFile()) {
      const diagnostics = [];
      if (publishedEntry && candidate.path !== publishedEntry && candidate.source === "source-fallback") {
        diagnostics.push({
          code: "entry_uses_source_fallback",
          message: "Published package entry is absent locally; using source entry fallback for unbuilt workspace scan.",
          published_entry_path: publishedEntry,
          source_entry_path: candidate.path,
        });
      }
      return { entry: candidate.path, publishedEntry, diagnostics };
    }
  }
  return { entry: "", publishedEntry, diagnostics: [] };
}

function walkTextFiles(root, options = {}) {
  const maxFiles = options.maxFiles ?? 250;
  const maxBytes = options.maxBytes ?? 2_000_000;
  const files = [];
  let bytes = 0;
  const stack = [root];
  while (stack.length > 0 && files.length < maxFiles && bytes < maxBytes) {
    const current = stack.pop();
    let entries = [];
    try {
      entries = fs.readdirSync(current, { withFileTypes: true });
    } catch {
      continue;
    }
    for (const entry of entries) {
      const full = path.join(current, entry.name);
      if (entry.isDirectory()) {
        if (!SKIP_DIRS.has(entry.name)) {
          stack.push(full);
        }
        continue;
      }
      if (!entry.isFile() || !TEXT_EXTENSIONS.has(path.extname(entry.name))) {
        continue;
      }
      const stat = fs.statSync(full);
      if (stat.size > 500_000) {
        continue;
      }
      files.push(full);
      bytes += stat.size;
      if (files.length >= maxFiles || bytes >= maxBytes) {
        break;
      }
    }
  }
  return files.sort();
}

function scanSource(pluginRoot) {
  const files = walkTextFiles(pluginRoot);
  const registerApis = new Set();
  const sdkSubpaths = new Set();
  const highRiskKinds = new Set();
  const secretFields = new Set();
  const evidenceFiles = new Set();
  for (const file of files) {
    const text = fs.readFileSync(file, "utf8");
    let matched = false;
    for (const [api, pattern] of REGISTER_API_PATTERNS.entries()) {
      pattern.lastIndex = 0;
      if (pattern.test(text)) {
        registerApis.add(api);
        matched = true;
      }
    }
    for (const match of text.matchAll(/openclaw\/plugin-sdk\/([A-Za-z0-9._/-]+)/g)) {
      sdkSubpaths.add(match[1].replace(/['"`);,]+$/g, ""));
      matched = true;
    }
    for (const [kind, pattern] of HIGH_RISK_KIND_PATTERNS) {
      pattern.lastIndex = 0;
      if (pattern.test(text)) {
        highRiskKinds.add(kind);
        matched = true;
      }
    }
    for (const match of text.matchAll(/\b([A-Za-z0-9_-]*(token|secret|password|apiKey|appSecret|authorization)[A-Za-z0-9_-]*)\b/gi)) {
      secretFields.add(match[1]);
      matched = true;
    }
    if (matched) {
      evidenceFiles.add(safeRelative(pluginRoot, file));
    }
  }
  return {
    scannedFiles: files.length,
    evidenceFiles: [...evidenceFiles].sort(),
    registerApis: [...registerApis].sort(),
    sdkSubpaths: [...sdkSubpaths].sort(),
    highRiskKinds: [...highRiskKinds].sort(),
    secretFields: [...secretFields].sort(),
  };
}

function pluginKinds(pkg, openclawManifest, scan) {
  const kinds = new Set();
  if (pkg?.openclaw?.channel || openclawManifest?.channel) {
    kinds.add("channel");
  }
  if (pkg?.openclaw?.setupEntry || openclawManifest?.setupEntry) {
    kinds.add("setup");
  }
  const packageText = `${pkg?.name ?? ""} ${pkg?.description ?? ""}`.toLowerCase();
  if (/\b(provider|model)\b/.test(packageText)) {
    kinds.add("provider");
  }
  if (/\b(tool|mcp|search|crawl|browser)\b/.test(packageText)) {
    kinds.add("tool");
  }
  if (/\b(memory|embedding)\b/.test(packageText)) {
    kinds.add("memory");
  }
  if (/\bmedia|image|video|voice|speech\b/.test(packageText)) {
    kinds.add("media");
  }
  if (/\b(skill|skills|skill pack|plugin-shipped)\b/.test(packageText)) {
    kinds.add("setup");
  }
  for (const api of scan.registerApis) {
    const kind = KIND_BY_API.get(api);
    if (kind) {
      kinds.add(kind);
    }
  }
  for (const kind of scan.highRiskKinds) {
    kinds.add(kind);
  }
  if (kinds.size === 0 && (pkg?.openclaw?.install || openclawManifest?.install)) {
    kinds.add("setup");
  }
  if (kinds.size === 0) {
    kinds.add("unknown");
  }
  return [...kinds].sort();
}

function initialStatus(kinds, registerApis) {
  const onlyCurrentlyPartial = new Set(["command", "hook", "interactive", "approval"]);
  const hasHardMissing = kinds.some((kind) =>
    ["channel", "http-route", "tool", "provider", "memory", "media", "browser", "process", "realtime", "gateway-method", "service", "unknown"].includes(kind)
  );
  if (hasHardMissing) {
    return "missing";
  }
  if (registerApis.length > 0 && kinds.every((kind) => onlyCurrentlyPartial.has(kind))) {
    return "partial";
  }
  return "missing";
}

function implementationTaskFor(kinds) {
  const tasks = [];
  if (kinds.includes("channel")) {
    tasks.push("Implement registerChannel capture and OpenClaw ChannelPlugin -> Metis ChannelAdapter bridge.");
  }
  if (kinds.includes("http-route")) {
    tasks.push("Implement Gateway HTTP/webhook route forwarding to OpenClaw sidecar handlers.");
  }
  if (kinds.includes("tool")) {
    tasks.push("Implement registerTool -> Metis tool registry mapping with schema, permission, and result conversion.");
  }
  if (kinds.includes("provider")) {
    tasks.push("Implement registerProvider -> Metis provider/model registry mapping.");
  }
  if (kinds.includes("media")) {
    tasks.push("Implement media runtime, inbound archive, outbound media, and media understanding/generation bridges.");
  }
  if (kinds.includes("memory")) {
    tasks.push("Implement memory/conversation/thread runtime mapping.");
  }
  if (kinds.includes("browser") || kinds.includes("process") || kinds.includes("realtime")) {
    tasks.push("Implement explicit permission, process/browser/realtime lifecycle, and sandbox policy.");
  }
  if (kinds.includes("setup")) {
    tasks.push("Map OpenClaw setup/install metadata to Metis configuration, doctor, and secret storage flows.");
  }
  if (kinds.includes("unknown")) {
    tasks.push("Audit source evidence and classify the package as a concrete OpenClaw capability or documented not-applicable helper.");
  }
  if (tasks.length === 0) {
    tasks.push("Implement full OpenClaw host API capture and add plugin-specific smoke test from original package.");
  }
  return tasks;
}

function acceptanceTestsFor(kinds) {
  const tests = ["Original package installs/loads/registers without source, manifest, or wrapper changes."];
  if (kinds.includes("channel")) {
    tests.push("Mock channel start/inbound/reply/outbound/health flow passes through Metis Gateway/session boundary.");
  }
  if (kinds.includes("http-route")) {
    tests.push("Mock HTTP request is dispatched through Metis Gateway to sidecar handler and returns status/headers/body.");
  }
  if (kinds.includes("tool")) {
    tests.push("Mock tool execution validates parameters, permissions, timeout, and result conversion.");
  }
  if (kinds.includes("provider")) {
    tests.push("Mock provider request/stream/result path works without real API keys.");
  }
  if (kinds.includes("media")) {
    tests.push("Mock media payload preserves MIME, file reference, thumbnails, and redacted diagnostics.");
  }
  if (kinds.includes("memory")) {
    tests.push("Mock memory provider read/write/query is isolated from real user state.");
  }
  if (kinds.includes("setup")) {
    tests.push("Setup/config metadata can be rendered, saved, read back, and redacted without touching real user state.");
  }
  if (kinds.includes("unknown")) {
    tests.push("Source audit explains why the package is not-applicable or reclassifies it to a concrete runtime facet.");
  }
  return tests;
}

function inventoryPlugin(source, pluginRoot, discoveredBy) {
  const pkgPath = path.join(pluginRoot, "package.json");
  const openclawManifestPath = path.join(pluginRoot, "openclaw.plugin.json");
  const pkg = readJsonIfExists(pkgPath);
  const openclawManifest = readJsonIfExists(openclawManifestPath);
  const scan = scanSource(pluginRoot);
  const resolvedEntry = resolveEntry(pluginRoot, pkg, openclawManifest);
  const kinds = pluginKinds(pkg, openclawManifest, scan);
  const status = initialStatus(kinds, scan.registerApis);
  if (!STATUS_VALUES.has(status)) {
    throw new Error(`invalid status for ${pluginRoot}: ${status}`);
  }
  const channelId = firstNonEmpty(pkg?.openclaw?.channel?.id, openclawManifest?.channel?.id);
  const pluginId = firstNonEmpty(openclawManifest?.id, pkg?.openclaw?.id, channelId, pkg?.name, path.basename(pluginRoot));
  const install = pkg?.openclaw?.install ?? openclawManifest?.install ?? {};
  const diagnostics = [...resolvedEntry.diagnostics];
  if (!resolvedEntry.entry) {
    diagnostics.push({ code: "entry_not_found", message: "No existing plugin entry was resolved from manifest/package conventions." });
  }
  if (kinds.includes("unknown")) {
    diagnostics.push({
      code: "unknown_classifier",
      message: "No audited OpenClaw capability marker matched this package; keep this diagnostic until source evidence classifies it or marks it not-applicable.",
      evidence_files: scan.evidenceFiles,
    });
  }
  const runtimeFacetsRequired = runtimeFacetsFor(kinds);
  const releaseBlockers = releaseBlockersForPlugin({
    pluginId,
    source,
    entry: resolvedEntry.entry,
    status,
    diagnostics,
    requiresMetisManifest: false,
    requiresWrapper: false,
    sourcePatched: false,
  });

  return {
    plugin_id: String(pluginId),
    source_repo: source.name,
    source_root: path.resolve(source.root),
    source_ref: source.ref ?? "",
    package_name: pkg?.name ?? "",
    package_version: pkg?.version ?? openclawManifest?.version ?? "",
    install_source: install.npmSpec ?? install.localPath ?? "",
    discovered_by: discoveredBy,
    plugin_root: pluginRoot,
    manifest_path: fs.existsSync(openclawManifestPath) ? openclawManifestPath : pkgPath,
    entry_path: resolvedEntry.entry,
    published_entry_path: resolvedEntry.publishedEntry,
    requires_metis_manifest: false,
    requires_wrapper: false,
    source_patched: false,
    plugin_kinds: kinds,
    register_apis: scan.registerApis,
    sdk_subpaths: scan.sdkSubpaths,
    runtime_dependencies: Object.keys(pkg?.dependencies ?? {}).sort(),
    external_services: inferExternalServices(pkg, kinds),
    permissions: inferPermissions(pkg, kinds, scan.highRiskKinds),
    config_schema: summarizeConfigSchema(pkg, openclawManifest),
    secret_fields: scan.secretFields,
    openclaw_evidence: scan.evidenceFiles,
    runtime_facets_required: runtimeFacetsRequired,
    real_plugin_smoke_status: "not-run",
    behavior_test_status: "not-run",
    metis_status: status,
    gap: gapFor(status, kinds),
    implementation_task: implementationTaskFor(kinds),
    acceptance_tests: acceptanceTestsFor(kinds),
    release_blockers: releaseBlockers,
    diagnostics,
  };
}

function firstNonEmpty(...values) {
  for (const value of values) {
    const normalized = String(value ?? "").trim();
    if (normalized) {
      return normalized;
    }
  }
  return "";
}

function inferExternalServices(pkg, kinds) {
  const services = new Set();
  const nameText = `${pkg?.name ?? ""} ${pkg?.description ?? ""}`.toLowerCase();
  for (const key of Object.keys(pkg?.dependencies ?? {})) {
    if (/grammy|telegram/.test(key)) services.add("telegram");
    if (/slack/.test(key)) services.add("slack");
    if (/discord/.test(key)) services.add("discord");
    if (/openai/.test(key)) services.add("openai");
    if (/anthropic/.test(key)) services.add("anthropic");
    if (/ws|websocket/.test(key)) services.add("websocket");
  }
  for (const word of ["wechat", "weixin", "wecom", "dingtalk", "feishu", "qqbot", "openai", "anthropic", "google", "ollama"]) {
    if (nameText.includes(word)) {
      services.add(word);
    }
  }
  if (kinds.includes("http-route")) {
    services.add("webhook");
  }
  return [...services].sort();
}

function inferPermissions(pkg, kinds, highRiskKinds) {
  const permissions = new Set();
  if (kinds.includes("http-route")) permissions.add("webhook");
  if (kinds.includes("provider")) permissions.add("model-provider");
  if (kinds.includes("tool")) permissions.add("tool-execution");
  if (kinds.includes("media")) permissions.add("media");
  if (kinds.includes("memory")) permissions.add("memory");
  if (highRiskKinds.includes("browser")) permissions.add("browser");
  if (highRiskKinds.includes("process")) permissions.add("process");
  if (highRiskKinds.includes("realtime")) permissions.add("realtime");
  if (Object.keys(pkg?.dependencies ?? {}).length > 0) permissions.add("network");
  return [...permissions].sort();
}

function summarizeConfigSchema(pkg, openclawManifest) {
  const schema = openclawManifest?.configSchema ?? pkg?.openclaw?.configSchema ?? null;
  if (!schema) {
    return { present: false };
  }
  return {
    present: true,
    keys: typeof schema === "object" && schema ? Object.keys(schema).sort() : [],
  };
}

function gapFor(status, kinds) {
  if (status === "aligned") {
    return "";
  }
  if (status === "partial") {
    return "Current Metis sidecar only covers a small command/hook/interactive subset and lacks full OpenClaw host/runtime verification.";
  }
  return `Metis lacks zero-cost OpenClaw compatibility for capability kinds: ${kinds.join(", ")}.`;
}

function runtimeFacetsFor(kinds) {
  const facets = new Set();
  const addIf = (kind, facet = kind) => {
    if (kinds.includes(kind)) {
      facets.add(facet);
    }
  };
  addIf("channel");
  addIf("http-route");
  addIf("tool");
  addIf("provider");
  addIf("hook");
  addIf("command");
  addIf("cli");
  addIf("interactive");
  addIf("approval");
  addIf("memory");
  addIf("media");
  addIf("browser");
  addIf("process");
  addIf("realtime");
  addIf("gateway-method");
  addIf("service");
  addIf("setup");
  addIf("unknown", "classifier-audit");
  return [...facets].sort();
}

function releaseBlockersForPlugin({
  pluginId,
  source,
  entry,
  status,
  diagnostics,
  requiresMetisManifest,
  requiresWrapper,
  sourcePatched,
}) {
  const blockers = [];
  const record = { plugin_id: String(pluginId), source: source.name };
  if (!firstNonEmpty(source.ref)) {
    blockers.push({ ...record, code: "missing_source_ref", message: "Source ref is required for release-ready compatibility evidence." });
  }
  if (!firstNonEmpty(entry)) {
    blockers.push({ ...record, code: "missing_entry", message: "Resolved plugin entry is required for host smoke tests." });
  }
  if (!["aligned", "not-applicable"].includes(status)) {
    blockers.push({ ...record, code: "release_status_not_ready", message: `Compatibility status ${status} is not release-ready.` });
  }
  if (requiresMetisManifest) {
    blockers.push({ ...record, code: "requires_metis_manifest", message: "Zero-cost policy forbids requiring metis.plugin.json conversion." });
  }
  if (requiresWrapper) {
    blockers.push({ ...record, code: "requires_wrapper", message: "Zero-cost policy forbids per-plugin wrappers." });
  }
  if (sourcePatched) {
    blockers.push({ ...record, code: "source_patched", message: "Zero-cost policy forbids patched plugin source." });
  }
  for (const diagnostic of diagnostics) {
    if (diagnostic.code === "unknown_classifier") {
      blockers.push({ ...record, code: "unknown_classifier", message: diagnostic.message });
    }
  }
  return blockers;
}

function summarize(plugins, diagnostics) {
  const byStatus = {};
  const byKind = {};
  const releaseBlockers = [];
  for (const plugin of plugins) {
    byStatus[plugin.metis_status] = (byStatus[plugin.metis_status] ?? 0) + 1;
    for (const kind of plugin.plugin_kinds) {
      byKind[kind] = (byKind[kind] ?? 0) + 1;
    }
    releaseBlockers.push(...(plugin.release_blockers ?? []));
  }
  for (const diagnostic of diagnostics) {
    if (diagnostic.code === "source_missing") {
      releaseBlockers.push({
        code: "source_missing",
        source: diagnostic.source,
        message: diagnostic.message,
      });
    }
  }
  return {
    plugin_count: plugins.length,
    diagnostics_count: diagnostics.length,
    by_status: Object.fromEntries(Object.entries(byStatus).sort()),
    by_kind: Object.fromEntries(Object.entries(byKind).sort()),
    release_blockers: releaseBlockers,
    release_ready: plugins.length > 0 && releaseBlockers.length === 0,
  };
}

export function buildInventory(options) {
  const diagnostics = [];
  const plugins = [];
  const sources = [];
  for (const source of options.sources) {
    const root = path.resolve(source.root);
    const sourceRecord = { ...source, root, exists: fs.existsSync(root), ref: source.ref ?? gitRefFor(root) };
    sources.push(sourceRecord);
    if (!sourceRecord.exists) {
      diagnostics.push({ source: source.name, code: "source_missing", message: `Source root not found: ${root}` });
      continue;
    }
    const roots = discoverPluginRoots(root);
    if (roots.length === 0) {
      diagnostics.push({ source: source.name, code: "no_plugins_discovered", message: `No plugin roots discovered under ${root}` });
      continue;
    }
    for (const discovered of roots) {
      try {
        plugins.push(inventoryPlugin(sourceRecord, discovered.root, discovered.discoveredBy));
      } catch (error) {
        diagnostics.push({
          source: source.name,
          pluginRoot: discovered.root,
          code: "plugin_inventory_failed",
          message: String(error?.message ?? error),
        });
      }
    }
  }
  plugins.sort((a, b) => `${a.source_repo}:${a.plugin_id}`.localeCompare(`${b.source_repo}:${b.plugin_id}`));
  return {
    schema_version: 1,
    generated_at: new Date().toISOString(),
    zero_cost_policy: {
      requires_original_source: true,
      allows_metis_manifest_conversion: false,
      allows_per_plugin_wrapper: false,
      allows_source_patch: false,
    },
    sources,
    summary: summarize(plugins, diagnostics),
    plugins,
    diagnostics,
  };
}

function gitRefFor(root) {
  try {
    return execFileSync("git", ["-C", root, "rev-parse", "--short", "HEAD"], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
      timeout: 2000,
    }).trim();
  } catch {
    return sourceSnapshotRefFor(root);
  }
}

function sourceSnapshotRefFor(root) {
  if (!fs.existsSync(root) || !fs.statSync(root).isDirectory()) {
    return "";
  }
  const files = [];
  const stack = [root];
  while (stack.length > 0) {
    const current = stack.pop();
    let entries = [];
    try {
      entries = fs.readdirSync(current, { withFileTypes: true });
    } catch {
      continue;
    }
    for (const entry of entries) {
      const full = path.join(current, entry.name);
      if (entry.isDirectory()) {
        if (!SKIP_DIRS.has(entry.name)) {
          stack.push(full);
        }
        continue;
      }
      if (entry.isFile()) {
        files.push(full);
      }
    }
  }
  const hash = crypto.createHash("sha256");
  for (const file of files.sort()) {
    const relative = safeRelative(root, file);
    hash.update(relative);
    hash.update("\0");
    hash.update(fs.readFileSync(file));
    hash.update("\0");
  }
  return `archive-sha256:${hash.digest("hex")}`;
}

export function renderMarkdown(inventory) {
  const lines = [];
  lines.push("# OpenClaw Plugin Compatibility Matrix");
  lines.push("");
  lines.push(`Generated: ${inventory.generated_at}`);
  lines.push("");
  lines.push("## Summary");
  lines.push("");
  lines.push(`- Plugins: ${inventory.summary.plugin_count}`);
  lines.push(`- Diagnostics: ${inventory.summary.diagnostics_count}`);
  lines.push(`- Release blockers: ${inventory.summary.release_blockers?.length ?? 0}`);
  lines.push(`- Release ready: ${inventory.summary.release_ready ? "yes" : "no"}`);
  lines.push("");
  lines.push("### By Status");
  lines.push("");
  for (const [status, count] of Object.entries(inventory.summary.by_status)) {
    lines.push(`- \`${status}\`: ${count}`);
  }
  lines.push("");
  lines.push("### By Kind");
  lines.push("");
  for (const [kind, count] of Object.entries(inventory.summary.by_kind)) {
    lines.push(`- \`${kind}\`: ${count}`);
  }
  lines.push("");
  lines.push("## Plugins");
  lines.push("");
  lines.push("| Plugin | Source | Source Ref | Entry | Version | Kinds | Runtime Facets | APIs | Smoke | Behavior | Status | Blockers | Gap |");
  lines.push("|---|---|---|---|---:|---|---|---|---|---|---|---:|---|");
  for (const plugin of inventory.plugins) {
    lines.push(
      `| ${escapeMd(plugin.plugin_id)} | ${escapeMd(plugin.source_repo)} | ${escapeMd(plugin.source_ref)} | ${escapeMd(safeRelative(plugin.source_root, plugin.entry_path))} | ${escapeMd(plugin.package_version)} | ${escapeMd(plugin.plugin_kinds.join(", "))} | ${escapeMd(plugin.runtime_facets_required.join(", "))} | ${escapeMd(plugin.register_apis.join(", "))} | ${escapeMd(plugin.real_plugin_smoke_status)} | ${escapeMd(plugin.behavior_test_status)} | \`${plugin.metis_status}\` | ${plugin.release_blockers.length} | ${escapeMd(plugin.gap)} |`
    );
  }
  if ((inventory.summary.release_blockers?.length ?? 0) > 0) {
    lines.push("");
    lines.push("## Release Blockers");
    lines.push("");
    for (const blocker of inventory.summary.release_blockers) {
      lines.push(`- \`${blocker.code}\` ${escapeMd(blocker.plugin_id ?? blocker.source ?? "")}: ${escapeMd(blocker.message)}`);
    }
  }
  if (inventory.diagnostics.length > 0) {
    lines.push("");
    lines.push("## Diagnostics");
    lines.push("");
    for (const diagnostic of inventory.diagnostics) {
      lines.push(`- \`${diagnostic.code}\` ${escapeMd(diagnostic.source ?? "")}: ${escapeMd(diagnostic.message)}`);
    }
  }
  lines.push("");
  return `${lines.join("\n").replace(/\n+$/g, "")}\n`;
}

function escapeMd(value) {
  return String(value ?? "").replaceAll("|", "\\|").replaceAll("\n", " ");
}

function writeFileEnsuringDir(file, content) {
  fs.mkdirSync(path.dirname(path.resolve(file)), { recursive: true });
  fs.writeFileSync(file, content);
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const inventory = buildInventory(args);
  writeFileEnsuringDir(args.outJson, JSON.stringify(inventory, null, args.pretty ? 2 : 0));
  if (args.outMd) {
    writeFileEnsuringDir(args.outMd, renderMarkdown(inventory));
  }
  process.stdout.write(
    JSON.stringify({
      ok: true,
      outJson: args.outJson,
      outMd: args.outMd || null,
      summary: inventory.summary,
    }) + "\n"
  );
}

const invokedPath = process.argv[1] ? path.resolve(process.argv[1]) : "";
if (invokedPath === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    console.error(error?.stack ?? String(error));
    process.exit(1);
  });
}
