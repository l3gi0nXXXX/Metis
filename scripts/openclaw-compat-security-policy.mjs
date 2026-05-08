#!/usr/bin/env node

import fs from "node:fs";
import { fileURLToPath } from "node:url";

export const PERMISSION_CATEGORIES = Object.freeze([
  "network",
  "filesystem",
  "env",
  "process",
  "browser",
  "webhook",
  "model",
  "secret",
  "media",
]);

const CATEGORY_SET = new Set(PERMISSION_CATEGORIES);
const DEFAULT_APPROVAL_CATEGORIES = new Set(["filesystem", "env", "process", "webhook", "secret", "media"]);
const SCRIPT_PERMISSION_NAMES = new Set(["preinstall", "install", "postinstall", "prepare"]);

export class OpenClawSecurityEnforcer {
  constructor({
    pluginId = "unknown-plugin",
    manifest = {},
    packageJson = {},
    capabilityRecords = [],
    source = {},
    sourceAllowlist = [],
    grants = {},
    approvalCategories = DEFAULT_APPROVAL_CATEGORIES,
  } = {}) {
    this.pluginId = pluginId;
    this.manifest = manifest;
    this.packageJson = packageJson;
    this.capabilityRecords = capabilityRecords;
    this.source = source;
    this.sourceAllowlist = sourceAllowlist;
    this.grants = grants;
    this.approvalCategories = approvalCategories;
  }

  enforceInstall() {
    return enforceOpenClawInstallSource({
      pluginId: this.pluginId,
      source: this.source,
      sourceAllowlist: this.sourceAllowlist,
    });
  }

  enforceStart() {
    const result = evaluateSecurityPolicy({
      pluginId: this.pluginId,
      manifest: this.manifest,
      packageJson: this.packageJson,
      capabilityRecords: this.capabilityRecords,
      allowlist: this.grants,
      approvalCategories: this.approvalCategories,
    });
    const denied = result.denied.map(sanitizeRequirement);
    const needsApproval = result.needsApproval.map(sanitizeRequirement);
    return securityDecision({
      pluginId: this.pluginId,
      stage: "start",
      allowed: denied.length === 0 && needsApproval.length === 0,
      code: denied.length > 0 ? "permission_denied" : needsApproval.length > 0 ? "approval_required" : "allowed",
      diagnostics: {
        manifest: result.diagnostics.manifest,
        package: result.diagnostics.package,
        denied,
        needsApproval,
      },
      denied,
      needsApproval,
    });
  }

  enforceRuntimePermission(requirement) {
    const normalized = normalizeRequirement({ ...requirement, source: requirement?.source ?? "runtime" });
    if (!normalized) {
      return securityDecision({
        pluginId: this.pluginId,
        stage: "handler",
        allowed: false,
        code: "invalid_permission_request",
        diagnostics: { request: redactDiagnostics(requirement) },
      });
    }
    const grant = findGrant(normalized, normalizeAllowlist(this.grants));
    return securityDecision({
      pluginId: this.pluginId,
      stage: "handler",
      allowed: Boolean(grant),
      code: grant ? "allowed" : "permission_denied",
      diagnostics: grant ? {} : { denied: sanitizeRequirement(normalized) },
      denied: grant ? [] : [sanitizeRequirement(normalized)],
    });
  }

  async dispatchHandler(stage, permissionRequests, handler, { timeoutMs = 30000 } = {}) {
    const denied = [];
    for (const request of normalizePermissionRequestList(permissionRequests)) {
      const decision = this.enforceRuntimePermission(request);
      if (!decision.allowed) {
        denied.push(...(decision.denied ?? []));
      }
    }
    if (denied.length > 0) {
      return securityDecision({
        pluginId: this.pluginId,
        stage,
        allowed: false,
        code: "permission_denied",
        diagnostics: { denied },
        denied,
      });
    }
    return this.runGuardedHandler(stage, handler, { timeoutMs });
  }

  async runGuardedHandler(stage, handler, { timeoutMs = 30000 } = {}) {
    let timeoutId;
    try {
      const timeout = new Promise((resolve) => {
        timeoutId = setTimeout(() => {
          resolve(securityDecision({
            pluginId: this.pluginId,
            stage,
            allowed: false,
            code: "handler_timeout",
            diagnostics: { timeoutMs },
          }));
        }, timeoutMs);
      });
      const result = await Promise.race([
        Promise.resolve().then(handler),
        timeout,
      ]);
      if (result && result.code === "handler_timeout") {
        return result;
      }
      return securityDecision({
        pluginId: this.pluginId,
        stage,
        allowed: true,
        code: "allowed",
        diagnostics: { result: redactDiagnostics(result) },
      });
    } catch (error) {
      return securityDecision({
        pluginId: this.pluginId,
        stage,
        allowed: false,
        code: "handler_crash",
        diagnostics: { message: redactDiagnostics(String(error?.message ?? error)) },
      });
    } finally {
      if (timeoutId) clearTimeout(timeoutId);
    }
  }
}

export function enforceOpenClawInstallSource({
  pluginId = "unknown-plugin",
  source = {},
  sourceAllowlist = [],
} = {}) {
  const normalizedSource = normalizeSource(source);
  const rules = normalizeSourceAllowlist(sourceAllowlist);
  const urlMatch = rules.find((rule) => rule.url === normalizedSource.url);
  if (!urlMatch) {
    return securityDecision({
      pluginId,
      stage: "install",
      allowed: false,
      code: "source_not_allowed",
      diagnostics: { source: normalizedSource },
    });
  }
  if (urlMatch.ref && urlMatch.ref !== normalizedSource.ref) {
    return securityDecision({
      pluginId,
      stage: "install",
      allowed: false,
      code: "source_ref_mismatch",
      diagnostics: { source: normalizedSource, expectedRef: urlMatch.ref },
    });
  }
  if (urlMatch.hash && urlMatch.hash !== normalizedSource.hash) {
    return securityDecision({
      pluginId,
      stage: "install",
      allowed: false,
      code: "source_hash_mismatch",
      diagnostics: { source: normalizedSource, expectedHash: urlMatch.hash },
    });
  }
  return securityDecision({
    pluginId,
    stage: "install",
    allowed: true,
    code: "allowed",
    diagnostics: { source: normalizedSource },
  });
}

export function derivePermissionRequirements({ manifest = {}, packageJson = {}, capabilityRecords = [] } = {}) {
  const requirements = [];
  const seen = new Set();

  const add = (raw) => {
    const requirement = normalizeRequirement(raw);
    if (!requirement) return;
    const key = [
      requirement.category,
      requirement.action,
      requirement.resource,
      requirement.source,
      requirement.reason,
    ].join("\u0000");
    if (seen.has(key)) return;
    seen.add(key);
    requirements.push(requirement);
  };

  collectPermissionBlock(manifest.permissions, "manifest.permissions", add);
  collectPermissionBlock(manifest.openclaw?.permissions, "manifest.openclaw.permissions", add);
  collectPermissionBlock(manifest.metis?.permissions, "manifest.metis.permissions", add);
  collectPermissionBlock(manifest.capabilities, "manifest.capabilities", add);
  collectPermissionBlock(packageJson.permissions, "package.permissions", add);
  collectPermissionBlock(packageJson.openclaw?.permissions, "package.openclaw.permissions", add);
  collectPermissionBlock(packageJson.metis?.permissions, "package.metis.permissions", add);
  collectPermissionBlock(packageJson.capabilities, "package.capabilities", add);

  if (isObject(packageJson.scripts)) {
    for (const [scriptName, command] of Object.entries(packageJson.scripts)) {
      if (SCRIPT_PERMISSION_NAMES.has(scriptName) && String(command ?? "").trim()) {
        add({
          category: "process",
          action: "lifecycle-script",
          resource: scriptName,
          source: "package.scripts",
          reason: `npm lifecycle script ${scriptName}`,
        });
      }
    }
  }

  for (const record of normalizeRecordList(capabilityRecords)) {
    collectPermissionBlock(record.permissions, `capability.${record.id ?? record.name ?? "record"}.permissions`, add);
    collectPermissionBlock(record.requires, `capability.${record.id ?? record.name ?? "record"}.requires`, add);
    add({ ...record, source: `capability.${record.id ?? record.name ?? "record"}` });
    for (const category of PERMISSION_CATEGORIES) {
      if (record[category] != null) {
        collectCategoryValue(category, record[category], `capability.${record.id ?? record.name ?? "record"}.${category}`, add);
      }
    }
  }

  return requirements;
}

export function evaluateSecurityPolicy({
  pluginId = "unknown-plugin",
  manifest = {},
  packageJson = {},
  capabilityRecords = [],
  allowlist = {},
  approvalCategories = DEFAULT_APPROVAL_CATEGORIES,
} = {}) {
  const requirements = derivePermissionRequirements({ manifest, packageJson, capabilityRecords });
  const rules = normalizeAllowlist(allowlist);
  const approvalSet = new Set(approvalCategories);
  const allowed = [];
  const denied = [];
  const needsApproval = [];

  for (const requirement of requirements) {
    const grant = findGrant(requirement, rules);
    if (!grant) {
      denied.push(requirement);
      continue;
    }
    if (grant.needsApproval !== false && approvalSet.has(requirement.category)) {
      needsApproval.push({ ...requirement, grantSource: grant.source });
      continue;
    }
    allowed.push({ ...requirement, grantSource: grant.source });
  }

  return {
    pluginId,
    releaseReady: denied.length === 0,
    requirements,
    allowed,
    denied,
    needsApproval,
    diagnostics: redactDiagnostics({
      manifest: manifest.diagnostics,
      package: packageJson.diagnostics,
      denied: denied.map((requirement) => diagnosticForRequirement(requirement)),
      needsApproval: needsApproval.map((requirement) => diagnosticForRequirement(requirement)),
    }),
  };
}

export function redactDiagnostics(value, key = "") {
  if (Array.isArray(value)) {
    return value.map((item) => redactDiagnostics(item));
  }
  if (isObject(value)) {
    return Object.fromEntries(Object.entries(value).map(([childKey, childValue]) => [childKey, redactDiagnostics(childValue, childKey)]));
  }
  if (typeof value !== "string") {
    return value;
  }
  if (isSensitiveKey(key) || /^\d{6,}:[A-Za-z0-9_-]{20,}$/.test(value.trim())) {
    return "[REDACTED]";
  }
  return redactString(value);
}

export function normalizeSecurityDecisionSnapshot(decision) {
  return securityDecision({ ...decision });
}

function collectPermissionBlock(block, source, add) {
  if (block == null || block === false) return;
  if (Array.isArray(block)) {
    for (const item of block) {
      addPermissionItem(item, source, add);
    }
    return;
  }
  if (!isObject(block)) {
    addPermissionItem(block, source, add);
    return;
  }
  if (CATEGORY_SET.has(block.category) || CATEGORY_SET.has(block.type)) {
    add({ ...block, source: block.source ?? source });
    return;
  }
  for (const [category, value] of Object.entries(block)) {
    if (!CATEGORY_SET.has(category)) continue;
    collectCategoryValue(category, value, `${source}.${category}`, add);
  }
}

function addPermissionItem(item, source, add) {
  if (typeof item === "string") {
    add(parsePermissionString(item, source));
    return;
  }
  if (isObject(item)) {
    add({ ...item, source: item.source ?? source });
  }
}

function collectCategoryValue(category, value, source, add) {
  if (value == null || value === false) return;
  if (value === true) {
    add({ category, action: "use", resource: "*", source });
    return;
  }
  if (Array.isArray(value)) {
    for (const item of value) {
      collectCategoryValue(category, item, source, add);
    }
    return;
  }
  if (typeof value === "string") {
    add(normalizeCategoryString(category, value, source));
    return;
  }
  if (isObject(value)) {
    add({ category, ...value, source: value.source ?? source });
  }
}

function parsePermissionString(raw, source) {
  const value = raw.trim();
  const separator = value.indexOf(":");
  if (separator < 1) {
    return null;
  }
  const category = value.slice(0, separator);
  if (!CATEGORY_SET.has(category)) {
    return null;
  }
  return normalizeCategoryString(category, value.slice(separator + 1), source);
}

function normalizeCategoryString(category, rawResource, source) {
  let action = defaultActionForCategory(category);
  let resource = rawResource.trim();
  if (category === "filesystem") {
    const access = resource.match(/^(read|write|readwrite):(.+)$/);
    if (access) {
      action = access[1];
      resource = access[2];
    }
  }
  return { category, action, resource: resource || "*", source };
}

function normalizeRequirement(raw) {
  if (!isObject(raw)) return null;
  const category = raw.category ?? raw.type;
  if (!CATEGORY_SET.has(category)) return null;
  const resource = normalizeResource(category, raw);
  return {
    category,
    action: String(raw.action ?? defaultActionForCategory(category)).trim() || defaultActionForCategory(category),
    resource,
    source: String(raw.source ?? "unknown").trim() || "unknown",
    reason: String(raw.reason ?? defaultReasonForCategory(category)).trim() || defaultReasonForCategory(category),
  };
}

function securityDecision({ pluginId, stage, allowed, code, diagnostics = {}, denied = [], needsApproval = [] }) {
  const out = {
    pluginId,
    stage,
    allowed,
    code,
    diagnostics: redactDiagnostics(diagnostics),
  };
  if (denied.length > 0) out.denied = denied.map(sanitizeRequirement);
  if (needsApproval.length > 0) out.needsApproval = needsApproval.map(sanitizeRequirement);
  return redactDiagnostics(out);
}

function normalizeSource(source) {
  return {
    url: String(source?.url ?? source?.repository ?? source?.repo ?? "").trim(),
    ref: String(source?.ref ?? source?.tag ?? source?.commit ?? "").trim(),
    hash: String(source?.hash ?? source?.sha256 ?? source?.integrity ?? "").trim(),
    diagnostics: redactDiagnostics(source?.diagnostics ?? {}),
  };
}

function normalizeSourceAllowlist(sourceAllowlist) {
  const rawRules = Array.isArray(sourceAllowlist)
    ? sourceAllowlist
    : Array.isArray(sourceAllowlist.sources)
      ? sourceAllowlist.sources
      : Object.values(sourceAllowlist ?? {});
  return rawRules.filter(isObject).map(normalizeSource).filter((rule) => rule.url);
}

function sanitizeRequirement(requirement) {
  const category = String(requirement?.category ?? "");
  const resource = String(requirement?.resource ?? "");
  return {
    category,
    action: String(requirement?.action ?? ""),
    resource: shouldRedactRequirementResource(category, resource) ? "[REDACTED]" : resource,
    source: redactRequirementText(String(requirement?.source ?? "")),
    reason: redactRequirementText(String(requirement?.reason ?? "")),
    grantSource: requirement?.grantSource == null ? undefined : redactRequirementText(String(requirement.grantSource)),
  };
}

function shouldRedactRequirementResource(category, resource) {
  return category === "secret" || isSensitiveKey(resource);
}

function normalizeResource(category, raw) {
  const resource =
    raw.resource ??
    raw.path ??
    raw.url ??
    raw.host ??
    raw.domain ??
    raw.env ??
    raw.key ??
    raw.name ??
    raw.model ??
    raw.provider ??
    raw.command ??
    raw.kind ??
    raw.media ??
    "*";
  if (category === "network" || category === "webhook") {
    return normalizeNetworkResource(resource);
  }
  return String(resource).trim() || "*";
}

function normalizeNetworkResource(resource) {
  const raw = String(resource).trim();
  if (!raw) return "*";
  try {
    return new URL(raw).host || raw;
  } catch {
    return raw.replace(/^https?:\/\//, "").replace(/\/.*$/, "");
  }
}

function normalizeRecordList(records) {
  if (Array.isArray(records)) return records.filter(isObject);
  if (isObject(records)) {
    if (Array.isArray(records.records)) return records.records.filter(isObject);
    if (Array.isArray(records.capabilities)) return records.capabilities.filter(isObject);
    return Object.values(records).filter(isObject);
  }
  return [];
}

function normalizePermissionRequestList(permissionRequests) {
  if (permissionRequests == null) return [];
  if (Array.isArray(permissionRequests)) return permissionRequests;
  return [permissionRequests];
}

function normalizeAllowlist(allowlist) {
  const rules = [];
  const addRule = (category, rule, source) => {
    if (!CATEGORY_SET.has(category) && category !== "*") return;
    if (rule === true) {
      rules.push({ category, resource: "*", source });
      return;
    }
    if (typeof rule === "string") {
      rules.push({ category, resource: normalizeRuleResource(category, rule), source });
      return;
    }
    if (isObject(rule)) {
      rules.push({
        category,
        action: rule.action == null ? undefined : String(rule.action),
        resource: normalizeRuleResource(category, rule.resource ?? rule.path ?? rule.url ?? rule.host ?? rule.domain ?? rule.name ?? "*"),
        needsApproval: rule.needsApproval,
        source,
      });
    }
  };

  if (Array.isArray(allowlist)) {
    for (const item of allowlist) {
      if (typeof item === "string") {
        const parsed = parsePermissionString(item, "allowlist");
        if (parsed) addRule(parsed.category, parsed.resource, "allowlist");
      } else if (isObject(item)) {
        addRule(item.category ?? "*", item, "allowlist");
      }
    }
    return rules;
  }
  if (isObject(allowlist)) {
    for (const [category, value] of Object.entries(allowlist)) {
      if (Array.isArray(value)) {
        for (const item of value) addRule(category, item, `allowlist.${category}`);
      } else {
        addRule(category, value, `allowlist.${category}`);
      }
    }
  }
  return rules;
}

function findGrant(requirement, rules) {
  return rules.find((rule) => {
    if (rule.category !== "*" && rule.category !== requirement.category) return false;
    if (rule.action && rule.action !== requirement.action) return false;
    if (rule.resource === "*") return true;
    return rule.resource === normalizeRuleResource(requirement.category, requirement.resource);
  });
}

function normalizeRuleResource(category, resource) {
  if (category === "network" || category === "webhook") {
    return normalizeNetworkResource(resource);
  }
  return String(resource ?? "*").trim() || "*";
}

function defaultActionForCategory(category) {
  if (category === "filesystem" || category === "env" || category === "secret") return "read";
  if (category === "process") return "spawn";
  return "use";
}

function defaultReasonForCategory(category) {
  return `${category} permission requested by OpenClaw compatibility metadata`;
}

function diagnosticForRequirement(requirement) {
  return {
    category: requirement.category,
    action: requirement.action,
    resource: requirement.resource,
    source: requirement.source,
    reason: requirement.reason,
  };
}

function isObject(value) {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function isSensitiveKey(key) {
  return /(?:token|secret|password|authorization|api[_-]?key|credential)/i.test(key);
}

function redactString(value) {
  return value
    .replace(/\bBearer\s+[A-Za-z0-9._~+/=-]+/gi, "Bearer [REDACTED]")
    .replace(/(https?:\/\/)([^/\s:@]+):([^@\s/]+)@/gi, "$1[REDACTED]@")
    .replace(/([?&](?:token|secret|password|key|authorization)=)[^&#\s]+/gi, "$1[REDACTED]")
    .replace(/\b([A-Z0-9_]*(?:TOKEN|SECRET|KEY|PASSWORD|AUTH)[A-Z0-9_]*)=([^\s&]+)/g, "$1=[REDACTED]")
    .replace(/\b(password|token|secret|authorization)=([^\s&]+)/gi, "$1=[REDACTED]");
}

function redactRequirementText(value) {
  const redacted = redactDiagnostics(value);
  if (typeof redacted !== "string") return redacted;
  if (/(?:token|password|authorization|api[_-]?key|credential|\bBearer\b)/i.test(redacted)) {
    return "[REDACTED]";
  }
  return redacted;
}

function parseArgs(argv) {
  const out = { _: [] };
  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    if (!token.startsWith("--")) {
      out._.push(token);
      continue;
    }
    const key = token.slice(2);
    const next = argv[i + 1];
    if (next == null || next.startsWith("--")) {
      out[key] = true;
      continue;
    }
    out[key] = next;
    i += 1;
  }
  return out;
}

function readJsonFile(file) {
  return file ? JSON.parse(fs.readFileSync(file, "utf8")) : {};
}

function printCliUsage() {
  console.error("Usage: openclaw-compat-security-policy.mjs --manifest <json> [--package <json>] [--capabilities <json>] [--allowlist <json>]");
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const args = parseArgs(process.argv.slice(2));
  if (!args.manifest) {
    printCliUsage();
    process.exit(2);
  }
  const result = evaluateSecurityPolicy({
    pluginId: args.pluginId,
    manifest: readJsonFile(args.manifest),
    packageJson: readJsonFile(args.package),
    capabilityRecords: readJsonFile(args.capabilities),
    allowlist: readJsonFile(args.allowlist),
  });
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
  process.exit(result.denied.length === 0 ? 0 : 1);
}
