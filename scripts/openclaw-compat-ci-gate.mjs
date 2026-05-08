#!/usr/bin/env node

import fs from "node:fs";
import { fileURLToPath } from "node:url";

const RELEASE_READY_STATUSES = new Set(["aligned", "not-applicable"]);
const VALID_STATUSES = new Set(["aligned", "not-applicable", "partial", "missing"]);

export function validateOpenClawCompatGate({ inventory = {}, matrix = {} } = {}) {
  const records = [
    ...extractRecords(inventory, "inventory"),
    ...extractRecords(matrix, "matrix"),
  ];
  const errors = [];

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

  if (isPresent(value.status) && !VALID_STATUSES.has(value.status)) {
    errors.push(error("invalid_status", `${source}:${recordId} has unsupported status ${JSON.stringify(value.status)}`, record));
  } else if (isPresent(value.status) && !RELEASE_READY_STATUSES.has(value.status)) {
    errors.push(error("release_status_not_ready", `${source}:${recordId} status ${value.status} is not release-ready`, record));
  }

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
  for (const key of ["plugins", "matrix", "items", "records", "capabilities"]) {
    if (Array.isArray(document[key])) {
      collectRecords(document[key], source, key, records);
    }
  }
  for (const [key, value] of Object.entries(document)) {
    if (["plugins", "matrix", "items", "records", "capabilities"].includes(key)) continue;
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
  return ["sourceRef", "source_ref", "entry", "entry_path", "registerApis", "register_apis", "sdkSubpaths", "sdk_subpaths", "status", "metis_status", "pluginId", "plugin_id"].some((field) =>
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

function firstNonEmpty(...values) {
  for (const value of values) {
    const normalized = String(value ?? "").trim();
    if (normalized) return normalized;
  }
  return "";
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
