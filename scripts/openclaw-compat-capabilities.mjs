#!/usr/bin/env node

import fs from "node:fs";
import { fileURLToPath } from "node:url";

const STATUSES = new Set(["aligned", "partial", "missing", "not-applicable"]);

const GROUPS = [
  { name: "channel", aliases: ["channel", "channels"], keys: ["channels", "channel"] },
  { name: "httpRoute", aliases: ["httproute", "http_route", "http-route", "route", "http-routes"], keys: ["httpRoutes", "routes"] },
  {
    name: "httpHandler",
    aliases: ["httphandler", "http_handler", "http-handler", "handler", "http-handlers"],
    keys: ["httpHandlers"],
  },
  { name: "tool", aliases: ["tool", "tools"], keys: ["tools", "tool"] },
  { name: "provider", aliases: ["provider", "providers", "modelprovider", "model-provider"], keys: ["providers", "modelProviders"] },
  { name: "hook", aliases: ["hook", "hooks"], keys: ["hooks"] },
  { name: "command", aliases: ["command", "commands"], keys: ["commands"] },
  { name: "cli", aliases: ["cli", "clis", "cliCommand", "cli-command"], keys: ["cli", "cliCommands"] },
  { name: "approval", aliases: ["approval", "approvals"], keys: ["approvals"] },
  { name: "interactive", aliases: ["interactive", "interactives"], keys: ["interactive", "interactives"] },
  { name: "memory", aliases: ["memory", "memories"], keys: ["memory", "memories"] },
  { name: "media", aliases: ["media", "medias", "attachment", "attachments"], keys: ["media", "attachments"] },
  { name: "process", aliases: ["process", "processes"], keys: ["processes", "process"] },
  { name: "browser", aliases: ["browser", "browsers"], keys: ["browser", "browsers"] },
  { name: "realtime", aliases: ["realtime", "real-time", "stream", "streams"], keys: ["realtime", "streams"] },
  { name: "acp", aliases: ["acp", "agent-client-protocol"], keys: ["acp"] },
];

const GROUP_BY_ALIAS = new Map();
for (const group of GROUPS) {
  GROUP_BY_ALIAS.set(normalizeGroupToken(group.name), group.name);
  for (const alias of group.aliases) {
    GROUP_BY_ALIAS.set(normalizeGroupToken(alias), group.name);
  }
}

const SECRET_KEY_PATTERN =
  /(?:token|secret|password|passwd|api[_-]?key|authorization|credential|private[_-]?key|client[_-]?secret|refresh[_-]?token|access[_-]?token)/i;

function isObject(value) {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function normalizeGroupToken(value) {
  return String(value ?? "")
    .trim()
    .replace(/[\s_.-]+/g, "")
    .toLowerCase();
}

function canonicalGroup(value) {
  return GROUP_BY_ALIAS.get(normalizeGroupToken(value)) ?? "";
}

function asArray(value) {
  if (Array.isArray(value)) return value;
  if (isObject(value)) return Object.entries(value).map(([key, item]) => (isObject(item) ? { id: key, ...item } : { id: key, value: item }));
  return [];
}

function firstString(...values) {
  for (const value of values) {
    if (typeof value === "string" && value.trim()) {
      return value.trim();
    }
    if (typeof value === "number" || typeof value === "boolean") {
      return String(value);
    }
  }
  return "";
}

function normalizeId(capability) {
  return firstString(
    capability.id,
    capability.name,
    capability.command,
    capability.path,
    capability.route,
    capability.method && capability.path ? `${capability.method} ${capability.path}` : "",
  );
}

function normalizeStatus(capability) {
  const raw = firstString(capability.metisStatus, capability.status, capability.compatStatus, capability.compatibilityStatus).toLowerCase();
  if (STATUSES.has(raw)) return { status: raw, valid: true, raw };
  if (capability.notApplicable === true || capability.applicable === false) return { status: "not-applicable", valid: true, raw };
  if (capability.missing === true || capability.metisSupported === false || capability.supported === false) {
    return { status: "missing", valid: true, raw };
  }
  return { status: "partial", valid: raw === "", raw };
}

function normalizeAcceptanceTests(value) {
  if (Array.isArray(value)) {
    return value.map((item) => String(item ?? "").trim()).filter(Boolean);
  }
  if (typeof value === "string" && value.trim()) {
    return [value.trim()];
  }
  return [];
}

function capabilityEntries(capture) {
  const out = [];
  const containers = [capture, isObject(capture.registry) ? capture.registry : null].filter(Boolean);

  for (const item of asArray(capture.capabilities)) {
    if (isObject(item)) out.push(item);
  }

  for (const container of containers) {
    for (const group of GROUPS) {
      for (const key of group.keys) {
        for (const item of asArray(container[key])) {
          if (isObject(item)) out.push({ ...item, group: item.group ?? item.kind ?? group.name });
        }
      }
    }
  }

  return out;
}

function withDiagnostic(diagnostics, code, message, detail = {}) {
  diagnostics.push({ code, message, detail: redactSecrets(detail) });
}

function normalizeRecord(capability, source, diagnostics) {
  const group = canonicalGroup(capability.group ?? capability.kind ?? capability.type ?? capability.capabilityGroup);
  if (!group) {
    withDiagnostic(diagnostics, "unknown_capability_group", "Unknown OpenClaw capability group.", {
      group: capability.group ?? capability.kind ?? capability.type ?? capability.capabilityGroup ?? "",
      capability,
    });
    return null;
  }

  const id = normalizeId(capability);
  if (!id) {
    withDiagnostic(diagnostics, "missing_capability_id", "Capability record is missing an id/name/command/path.", { group, capability });
    return null;
  }

  const statusResult = normalizeStatus(capability);
  if (!statusResult.valid) {
    withDiagnostic(diagnostics, "invalid_status", "Capability status is invalid; treating record as partial.", {
      group,
      id,
      status: statusResult.raw,
    });
  }

  const rawGap = firstString(capability.gap);
  const rawImplementationTask = firstString(capability.implementationTask, capability.task, capability.nextStep);
  if ((statusResult.status === "partial" || statusResult.status === "missing") && !rawGap) {
    withDiagnostic(diagnostics, "missing_gap", "Partial/missing capability record must include a gap.", { group, id });
  }
  if ((statusResult.status === "partial" || statusResult.status === "missing") && !rawImplementationTask) {
    withDiagnostic(diagnostics, "missing_implementation_task", "Partial/missing capability record must include an implementationTask.", {
      group,
      id,
    });
  }

  let status = statusResult.status;
  const acceptanceTests = normalizeAcceptanceTests(capability.acceptanceTests ?? capability.tests ?? capability.acceptance);
  if (status !== "not-applicable" && acceptanceTests.length === 0) {
    status = "partial";
    withDiagnostic(diagnostics, "missing_acceptance_tests", "Capability record must include acceptanceTests for CI gating.", {
      group,
      id,
    });
  }

  return {
    group,
    id,
    status,
    gap: firstString(rawGap, status === "aligned" || status === "not-applicable" ? "" : `Metis ${group} capability is ${status}.`),
    implementationTask: rawImplementationTask,
    acceptanceTests,
    source,
    raw: redactSecrets(capability),
  };
}

function summarizeGroup(name, records) {
  if (records.length === 0) {
    return {
      status: "not-applicable",
      gap: `No captured OpenClaw ${name} capabilities.`,
      implementationTask: "",
      acceptanceTests: [],
      records: [],
    };
  }

  let status = "aligned";
  if (records.some((record) => record.status === "missing")) {
    status = "missing";
  } else if (records.some((record) => record.status === "partial")) {
    status = "partial";
  } else if (records.every((record) => record.status === "not-applicable")) {
    status = "not-applicable";
  }

  return {
    status,
    gap: records
      .filter((record) => record.status === "partial" || record.status === "missing")
      .map((record) => `${record.id}: ${record.gap}`)
      .filter(Boolean)
      .join("; "),
    implementationTask: records
      .filter((record) => record.status === "partial" || record.status === "missing")
      .map((record) => `${record.id}: ${record.implementationTask}`)
      .filter((value) => !value.endsWith(": "))
      .join("; "),
    acceptanceTests: [...new Set(records.flatMap((record) => record.acceptanceTests))],
    records,
  };
}

function buildReleaseGate(records) {
  const blockingRecords = records.filter((record) => record.status === "partial" || record.status === "missing");
  return {
    zeroCostCompatible: blockingRecords.length === 0,
    reason:
      blockingRecords.length === 0
        ? "No partial/missing capability records were found."
        : "Zero cost compatibility is blocked by partial/missing capability records.",
    blockingRecords,
  };
}

export function redactSecrets(value) {
  if (Array.isArray(value)) {
    return value.map((item) => redactSecrets(item));
  }
  if (!isObject(value)) {
    return value;
  }
  const out = {};
  for (const [key, item] of Object.entries(value)) {
    out[key] = SECRET_KEY_PATTERN.test(key) ? "[REDACTED]" : redactSecrets(item);
  }
  return out;
}

export function normalizeCapabilityRegistry(capture, options = {}) {
  if (!isObject(capture)) {
    throw new TypeError("normalizeCapabilityRegistry requires an object capture result.");
  }

  const diagnostics = [];
  const source = firstString(options.source, capture.source, capture.host, "openclaw-host-capture");
  const records = capabilityEntries(capture)
    .map((capability) => normalizeRecord(capability, source, diagnostics))
    .filter(Boolean);

  const groups = {};
  for (const group of GROUPS) {
    groups[group.name] = summarizeGroup(
      group.name,
      records.filter((record) => record.group === group.name),
    );
  }

  return {
    source,
    capturedAt: firstString(capture.capturedAt, capture.timestamp),
    records,
    groups,
    diagnostics,
    releaseGate: buildReleaseGate(records),
    sanitizedCapture: redactSecrets(capture),
  };
}

export function canClaimZeroCostCompatibility(reportOrCapture) {
  const report = isObject(reportOrCapture) && isObject(reportOrCapture.releaseGate)
    ? reportOrCapture
    : normalizeCapabilityRegistry(reportOrCapture);
  return report.releaseGate.zeroCostCompatible === true;
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
      out[key] = "true";
      continue;
    }
    out[key] = next;
    i += 1;
  }
  return out;
}

function readInput(args) {
  if (typeof args.input === "string" && args.input.trim()) {
    return fs.readFileSync(args.input.trim(), "utf8");
  }
  return fs.readFileSync(0, "utf8");
}

function isMainModule() {
  return process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1];
}

if (isMainModule()) {
  const args = parseArgs(process.argv.slice(2));
  const raw = readInput(args);
  const report = normalizeCapabilityRegistry(JSON.parse(raw), { source: args.source });
  process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
  if (args["fail-on-gaps"] === "true" && !report.releaseGate.zeroCostCompatible) {
    process.exitCode = 1;
  }
}
