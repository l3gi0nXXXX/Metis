#!/usr/bin/env node

import fs from "node:fs";
import { fileURLToPath } from "node:url";

const RELEASE_READY_STATUSES = new Set(["aligned", "not-applicable"]);
const RELEASE_READY_EVIDENCE_STATUSES = new Set(["passed", "not-applicable"]);
const VALID_STATUSES = new Set(["aligned", "not-applicable", "partial", "missing"]);
const RECORD_COLLECTION_KEYS = new Set(["plugins", "matrix", "items", "records", "capabilities"]);
const METADATA_KEYS = new Set([
  "sources",
  "diagnostics",
  "summary",
  "zero_cost_policy",
  "zeroCostPolicy",
  "release_blockers",
  "releaseBlockers",
]);

export function validateOpenClawCompatGate({ inventory = {}, matrix = {} } = {}) {
  const errors = [];

  validateDocumentMetadata(inventory, "inventory", errors);
  validateDocumentMetadata(matrix, "matrix", errors);

  const records = [
    ...extractRecords(inventory, "inventory"),
    ...extractRecords(matrix, "matrix"),
  ];

  if (records.length === 0) {
    errors.push(error("missing_records", "inventory/matrix JSON did not contain any plugin compatibility records"));
  }

  for (const record of records) {
    validateRecord(record, errors);
  }

  return {
    ok: errors.length === 0,
    releaseReady: errors.length === 0,
    errors,
    records: records.map(({ value, source, recordId }) => ({ source, recordId, status: value.status })),
  };
}

function validateRecord(record, errors) {
  const { value, recordId, source } = record;
  requireField(value, "sourceRef", "missing_source_ref", record, errors, isPresent);
  requireField(value, "entry", "missing_entry", record, errors, isPresent);
  requireField(value, "registerApis", "missing_register_apis", record, errors, isPresentList);
  requireField(value, "sdkSubpaths", "missing_sdk_subpaths", record, errors, isPresentList);
  requireField(value, "status", "missing_status", record, errors, isPresent);
  requireField(value, "realPluginSmokeStatus", "missing_real_plugin_smoke_status", record, errors, isPresent);
  requireField(value, "behaviorTestStatus", "missing_behavior_test_status", record, errors, isPresent);
  requireField(value, "runtimeFacetsRequired", "missing_runtime_facets_required", record, errors, Array.isArray);
  requireField(value, "releaseBlockers", "missing_release_blockers", record, errors, Array.isArray);

  if (isPresent(value.status) && !VALID_STATUSES.has(value.status)) {
    errors.push(error("invalid_status", `${source}:${recordId} has unsupported status ${JSON.stringify(value.status)}`, record));
  } else if (isPresent(value.status) && !RELEASE_READY_STATUSES.has(value.status)) {
    errors.push(error("release_status_not_ready", `${source}:${recordId} status ${value.status} is not release-ready`, record));
  }

  validateEvidenceStatus(value.realPluginSmokeStatus, "real plugin smoke", "real_plugin_smoke_not_ready", record, errors);
  validateEvidenceStatus(value.behaviorTestStatus, "behavior test", "behavior_test_not_ready", record, errors);
  validateReleaseBlockers(value.releaseBlockers, record, errors);

  if (isMarked(value.requiresMetisManifest)) {
    errors.push(error("requires_metis_manifest", `${source}:${recordId} requires metis.plugin.json`, record));
  }
  if (isMarked(value.requiresWrapper)) {
    errors.push(error("requires_wrapper", `${source}:${recordId} requires a per-plugin wrapper`, record));
  }
  if (isMarked(value.sourcePatched)) {
    errors.push(error("source_patched", `${source}:${recordId} requires patched plugin source`, record));
  }
}

function validateDocumentMetadata(document, source, errors) {
  if (!isObject(document)) return;
  validateSources(document.sources, source, errors);
  validateDiagnostics(document.diagnostics, source, errors);
  validateSummary(document.summary, source, errors);
  validateDocumentReleaseBlockers(document.release_blockers ?? document.releaseBlockers, source, errors);
}

function validateSources(sources, documentSource, errors) {
  if (!Array.isArray(sources)) return;
  for (let index = 0; index < sources.length; index += 1) {
    const sourceRecord = sources[index];
    if (!isObject(sourceRecord)) continue;
    const recordId = firstNonEmpty(sourceRecord.name, sourceRecord.source, `sources[${index}]`);
    const source = `${documentSource}.sources`;
    const record = { source, recordId };
    if (sourceRecord.exists === false) {
      errors.push(error("source_missing", `${source}:${recordId} source root is missing`, record));
      continue;
    }
    if (!isPresent(sourceRecord.ref ?? sourceRecord.source_ref ?? sourceRecord.sourceRef)) {
      errors.push(error("missing_source_ref", `${source}:${recordId} is missing pinned source ref`, record));
    }
  }
}

function validateDiagnostics(diagnostics, documentSource, errors) {
  if (!Array.isArray(diagnostics)) return;
  for (let index = 0; index < diagnostics.length; index += 1) {
    const diagnostic = diagnostics[index];
    if (!isObject(diagnostic)) continue;
    const recordId = firstNonEmpty(diagnostic.source, diagnostic.name, `diagnostics[${index}]`);
    const diagnosticCode = firstNonEmpty(diagnostic.code, "diagnostic_blocker");
    const source = `${documentSource}.diagnostics`;
    const code = diagnosticCode === "source_missing" ? "source_missing" : "diagnostic_blocker";
    errors.push(error(code, `${source}:${recordId} reports ${diagnosticCode}`, { source, recordId }));
  }
}

function validateSummary(summary, documentSource, errors) {
  if (!isObject(summary)) return;
  if (isFalseMarker(summary.release_ready ?? summary.releaseReady)) {
    errors.push(error("summary_release_not_ready", `${documentSource}:summary release_ready is false`, {
      source: `${documentSource}.summary`,
      recordId: "release_ready",
    }));
  }
}

function validateDocumentReleaseBlockers(releaseBlockers, documentSource, errors) {
  if (releaseBlockers == null) return;
  if (!Array.isArray(releaseBlockers)) {
    errors.push(error("invalid_release_blockers", `${documentSource}:release_blockers must be an array`, {
      source: documentSource,
      recordId: "release_blockers",
    }));
    return;
  }
  for (const blocker of releaseBlockers) {
    errors.push(error("release_blocker", `${documentSource}:release_blockers contains ${formatBlocker(blocker)}`, {
      source: documentSource,
      recordId: "release_blockers",
    }));
  }
}

function validateEvidenceStatus(value, label, code, record, errors) {
  if (!isPresent(value)) return;
  const normalized = String(value).trim().toLowerCase();
  if (!RELEASE_READY_EVIDENCE_STATUSES.has(normalized)) {
    errors.push(error(code, `${record.source}:${record.recordId} ${label} status ${JSON.stringify(value)} is not release-ready`, record));
  }
}

function validateReleaseBlockers(releaseBlockers, record, errors) {
  if (releaseBlockers == null) return;
  if (!Array.isArray(releaseBlockers)) {
    errors.push(error("invalid_release_blockers", `${record.source}:${record.recordId} release_blockers must be an array`, record));
    return;
  }
  for (const blocker of releaseBlockers) {
    errors.push(error("release_blocker", `${record.source}:${record.recordId} has release blocker ${formatBlocker(blocker)}`, record));
  }
}

function requireField(value, field, code, record, errors, predicate) {
  if (!predicate(value[field])) {
    errors.push(error(code, `${record.source}:${record.recordId} is missing ${field}`, record));
  }
}

function extractRecords(document, source) {
  const records = [];
  collectRecords(document, source, "", records);
  return records;
}

function collectRecords(document, source, fallbackId, records) {
  if (Array.isArray(document)) {
    for (let index = 0; index < document.length; index += 1) {
      if (isObject(document[index])) {
        records.push(toRecord(document[index], source, `${fallbackId}[${index}]`));
      }
    }
    return;
  }
  if (!isObject(document)) return;
  if (looksLikeRecord(document)) {
    records.push(toRecord(document, source, fallbackId));
    return;
  }
  for (const key of RECORD_COLLECTION_KEYS) {
    if (Array.isArray(document[key])) {
      collectRecords(document[key], source, key, records);
    }
  }
  for (const [key, value] of Object.entries(document)) {
    if (RECORD_COLLECTION_KEYS.has(key) || METADATA_KEYS.has(key)) continue;
    if (isObject(value)) {
      collectRecords(value, source, key, records);
    }
  }
}

function toRecord(value, source, fallbackId) {
  const normalized = normalizeRecordFields(value);
  const objectMapId = fallbackId && !fallbackId.includes("[") ? fallbackId : "";
  const recordId = firstNonEmpty(normalized.id, objectMapId, normalized.pluginId, value.plugin_id, normalized.name, fallbackId, source);
  return {
    source,
    value: normalized,
    recordId,
  };
}

function looksLikeRecord(value) {
  return [
    "sourceRef",
    "source_ref",
    "entry",
    "entry_path",
    "registerApis",
    "register_apis",
    "sdkSubpaths",
    "sdk_subpaths",
    "status",
    "metis_status",
    "realPluginSmokeStatus",
    "real_plugin_smoke_status",
    "behaviorTestStatus",
    "behavior_test_status",
    "runtimeFacetsRequired",
    "runtime_facets_required",
    "pluginId",
    "plugin_id",
  ].some((field) =>
    Object.prototype.hasOwnProperty.call(value, field),
  );
}

function normalizeRecordFields(value) {
  if (!isObject(value)) return value;
  return {
    ...value,
    pluginId: value.pluginId ?? value.plugin_id,
    sourceRef: value.sourceRef ?? value.source_ref,
    entry: value.entry ?? value.entry_path,
    registerApis: value.registerApis ?? value.register_apis,
    sdkSubpaths: value.sdkSubpaths ?? value.sdk_subpaths,
    status: value.status ?? value.metis_status,
    realPluginSmokeStatus: value.realPluginSmokeStatus ?? value.real_plugin_smoke_status,
    behaviorTestStatus: value.behaviorTestStatus ?? value.behavior_test_status,
    runtimeFacetsRequired: value.runtimeFacetsRequired ?? value.runtime_facets_required,
    releaseBlockers: value.releaseBlockers ?? value.release_blockers,
    requiresMetisManifest: value.requiresMetisManifest ?? value.requires_metis_manifest,
    requiresWrapper: value.requiresWrapper ?? value.requires_wrapper,
    sourcePatched: value.sourcePatched ?? value.source_patched,
  };
}

function isPresent(value) {
  if (typeof value === "string") return value.trim().length > 0;
  if (Array.isArray(value)) return value.length > 0;
  return value != null;
}

function isPresentList(value) {
  if (Array.isArray(value)) return true;
  if (typeof value === "string") return value.trim().length > 0;
  return false;
}

function isMarked(value) {
  if (value === true || value === 1) return true;
  if (typeof value === "string") {
    return ["1", "true", "yes"].includes(value.trim().toLowerCase());
  }
  return false;
}

function isFalseMarker(value) {
  if (value === false || value === 0) return true;
  if (typeof value === "string") {
    return ["0", "false", "no"].includes(value.trim().toLowerCase());
  }
  return false;
}

function firstNonEmpty(...values) {
  for (const value of values) {
    const normalized = String(value ?? "").trim();
    if (normalized) return normalized;
  }
  return "";
}

function formatBlocker(blocker) {
  if (typeof blocker === "string") return JSON.stringify(blocker);
  return JSON.stringify(blocker);
}

function error(code, message, record) {
  return {
    code,
    message,
    source: record?.source,
    recordId: record?.recordId,
  };
}

function isObject(value) {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
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
  console.error("Usage: openclaw-compat-ci-gate.mjs --inventory <json> --matrix <json>");
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const args = parseArgs(process.argv.slice(2));
  if (!args.inventory || !args.matrix) {
    printCliUsage();
    process.exit(2);
  }
  const result = validateOpenClawCompatGate({
    inventory: readJsonFile(args.inventory),
    matrix: readJsonFile(args.matrix),
  });
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
  process.exit(result.ok ? 0 : 1);
}
