#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const RELEASE_READY_STATUSES = new Set(["aligned", "not-applicable"]);
const RELEASE_READY_EVIDENCE_STATUSES = new Set(["passed", "not-applicable"]);
const VALID_STATUSES = new Set(["aligned", "not-applicable", "partial", "missing"]);
const REQUIRED_SOURCE_NAMES = ["openclaw", "openclaw-china", "openclaw-weixin", "clawmate", "qmd"];
const REPRESENTATIVE_EVIDENCE_SOURCES = ["openclaw-china", "openclaw-weixin", "clawmate"];
const SECURITY_EVIDENCE_FIELDS = Object.freeze([
  {
    stage: "install",
    statusField: "installSecurityStatus",
    artifactField: "installSecurityArtifact",
    statusCode: "missing_install_security_status",
    notReadyCode: "install_security_not_ready",
    artifactPrefix: "install_security",
  },
  {
    stage: "start",
    statusField: "startSecurityStatus",
    artifactField: "startSecurityArtifact",
    statusCode: "missing_start_security_status",
    notReadyCode: "start_security_not_ready",
    artifactPrefix: "start_security",
  },
  {
    stage: "handler",
    statusField: "handlerSecurityStatus",
    artifactField: "handlerSecurityArtifact",
    statusCode: "missing_handler_security_status",
    notReadyCode: "handler_security_not_ready",
    artifactPrefix: "handler_security",
  },
]);
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

export function validateOpenClawCompatGate({ inventory = {}, matrix = {}, artifactRoot = process.cwd() } = {}) {
  const errors = [];
  const context = { artifactRoot };

  validateDocumentMetadata(inventory, "inventory", errors);
  validateDocumentMetadata(matrix, "matrix", errors);

  const inventoryRecords = extractRecords(inventory, "inventory");
  const matrixRecords = extractRecords(matrix, "matrix");
  const records = [
    ...inventoryRecords,
    ...matrixRecords,
  ];

  if (records.length === 0) {
    errors.push(error("missing_records", "inventory/matrix JSON did not contain any plugin compatibility records"));
  }

  for (const record of records) {
    validateRecord(record, errors, context);
  }
  validateSourceBoundaryCounts(inventory, "inventory", inventoryRecords, errors);
  validateSourceBoundaryCounts(matrix, "matrix", matrixRecords, errors);
  validateRepresentativeEvidence(records, inventory, matrix, errors);

  return {
    ok: errors.length === 0,
    releaseReady: errors.length === 0,
    errors,
    records: records.map(({ value, source, recordId }) => ({ source, recordId, status: value.status })),
  };
}

function validateRecord(record, errors, context) {
  const { value, recordId, source } = record;
  requireField(value, "sourceRef", "missing_source_ref", record, errors, isPresent);
  requireField(value, "entry", "missing_entry", record, errors, isPresent);
  requireField(value, "registerApis", "missing_register_apis", record, errors, isPresentList);
  requireField(value, "sdkSubpaths", "missing_sdk_subpaths", record, errors, isPresentList);
  requireField(value, "status", "missing_status", record, errors, isPresent);
  requireField(value, "realPluginSmokeStatus", "missing_real_plugin_smoke_status", record, errors, isPresent);
  requireField(value, "behaviorTestStatus", "missing_behavior_test_status", record, errors, isPresent);
  for (const field of SECURITY_EVIDENCE_FIELDS) {
    requireField(value, field.statusField, field.statusCode, record, errors, isPresent);
  }
  requireField(value, "runtimeFacetsRequired", "missing_runtime_facets_required", record, errors, Array.isArray);
  requireField(value, "releaseBlockers", "missing_release_blockers", record, errors, Array.isArray);

  if (isPresent(value.status) && !VALID_STATUSES.has(value.status)) {
    errors.push(error("invalid_status", `${source}:${recordId} has unsupported status ${JSON.stringify(value.status)}`, record));
  } else if (isPresent(value.status) && !RELEASE_READY_STATUSES.has(value.status)) {
    errors.push(error("release_status_not_ready", `${source}:${recordId} status ${value.status} is not release-ready`, record));
  }

  validateEvidenceStatus(value.realPluginSmokeStatus, "real plugin smoke", "real_plugin_smoke_not_ready", record, errors);
  validateEvidenceStatus(value.behaviorTestStatus, "behavior test", "behavior_test_not_ready", record, errors);
  validateEvidenceArtifact(value.realPluginSmokeStatus, value.realPluginSmokeArtifact, {
    label: "real plugin smoke",
    codePrefix: "real_plugin_smoke",
    expectedKind: "real_plugin_smoke",
  }, record, errors, context);
  validateEvidenceArtifact(value.behaviorTestStatus, value.behaviorTestArtifact, {
    label: "behavior test",
    codePrefix: "behavior_test",
    expectedKind: "behavior_test",
  }, record, errors, context);
  for (const field of SECURITY_EVIDENCE_FIELDS) {
    validateEvidenceStatus(value[field.statusField], `${field.stage} security`, field.notReadyCode, record, errors);
    validateEvidenceArtifact(value[field.statusField], value[field.artifactField], {
      label: `${field.stage} security`,
      codePrefix: field.artifactPrefix,
      expectedKind: "security_gate",
      expectedStage: field.stage,
    }, record, errors, context);
  }
  validateAlignedPromotionEvidence(value, record, errors);
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
  const seenSources = new Set();
  for (let index = 0; index < sources.length; index += 1) {
    const sourceRecord = sources[index];
    if (!isObject(sourceRecord)) continue;
    const recordId = firstNonEmpty(sourceRecord.name, sourceRecord.source, `sources[${index}]`);
    seenSources.add(recordId);
    const source = `${documentSource}.sources`;
    const record = { source, recordId };
    if (sourceRecord.exists === false) {
      errors.push(error("source_missing", `${source}:${recordId} source root is missing`, record));
      continue;
    }
    if (isDirtySource(sourceRecord)) {
      errors.push(error("source_dirty", `${source}:${recordId} has uncommitted source changes`, record));
    }
    if (!isPresent(sourceRecord.ref ?? sourceRecord.source_ref ?? sourceRecord.sourceRef)) {
      errors.push(error("missing_source_ref", `${source}:${recordId} is missing pinned source ref`, record));
    }
  }
  for (const sourceName of REQUIRED_SOURCE_NAMES) {
    if (!seenSources.has(sourceName)) {
      errors.push(error("source_missing", `${documentSource}.sources:${sourceName} is missing from release boundary metadata`, {
        source: `${documentSource}.sources`,
        recordId: sourceName,
      }));
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
    const code = diagnosticCode === "source_missing" || diagnosticCode === "source_dirty" ? diagnosticCode : "diagnostic_blocker";
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

function validateSourceBoundaryCounts(document, documentSource, records, errors) {
  if (!isObject(document)) return;
  const actualBySource = records.reduce((counts, record) => {
    const sourceName = firstNonEmpty(record.value.sourceRepo);
    if (sourceName) {
      counts[sourceName] = (counts[sourceName] ?? 0) + 1;
    }
    return counts;
  }, {});
  validateSummaryPluginCount(document.summary, documentSource, records.length, errors);
  validateSummaryBySource(document.summary?.by_source ?? document.summary?.bySource, documentSource, actualBySource, errors);
  validateSourcePluginCounts(document.sources, documentSource, actualBySource, errors);
  validateSourceBoundarySummary(document.summary?.source_boundary ?? document.summary?.sourceBoundary, documentSource, records.length, errors);
}

function validateSummaryPluginCount(summary, documentSource, actualCount, errors) {
  if (!isObject(summary) || summary.plugin_count == null && summary.pluginCount == null) return;
  const expected = Number(summary.plugin_count ?? summary.pluginCount);
  if (Number.isFinite(expected) && expected !== actualCount) {
    errors.push(error("summary_plugin_count_mismatch", `${documentSource}:summary plugin_count ${expected} does not match ${actualCount} records`, {
      source: `${documentSource}.summary`,
      recordId: "plugin_count",
    }));
  }
}

function validateSummaryBySource(bySource, documentSource, actualBySource, errors) {
  if (!isObject(bySource)) return;
  const sourceNames = new Set([...Object.keys(bySource), ...Object.keys(actualBySource)]);
  for (const sourceName of sourceNames) {
    const expected = Number(bySource[sourceName] ?? 0);
    const actual = actualBySource[sourceName] ?? 0;
    if (Number.isFinite(expected) && expected !== actual) {
      errors.push(error("source_plugin_count_mismatch", `${documentSource}:summary by_source ${sourceName}=${expected} does not match ${actual} records`, {
        source: `${documentSource}.summary.by_source`,
        recordId: sourceName,
      }));
    }
  }
}

function validateSourcePluginCounts(sources, documentSource, actualBySource, errors) {
  if (!Array.isArray(sources)) return;
  for (const sourceRecord of sources) {
    if (!isObject(sourceRecord) || sourceRecord.plugin_count == null && sourceRecord.pluginCount == null) continue;
    const sourceName = firstNonEmpty(sourceRecord.name, sourceRecord.source);
    const expected = Number(sourceRecord.plugin_count ?? sourceRecord.pluginCount);
    const actual = actualBySource[sourceName] ?? 0;
    if (Number.isFinite(expected) && expected !== actual) {
      errors.push(error("source_plugin_count_mismatch", `${documentSource}.sources:${sourceName} plugin_count ${expected} does not match ${actual} records`, {
        source: `${documentSource}.sources`,
        recordId: sourceName,
      }));
    }
  }
}

function validateSourceBoundarySummary(sourceBoundary, documentSource, actualCount, errors) {
  if (!isObject(sourceBoundary)) return;
  const total = sourceBoundary.total_from_sources ?? sourceBoundary.totalFromSources;
  if (total != null && Number(total) !== actualCount) {
    errors.push(error("summary_plugin_count_mismatch", `${documentSource}:source_boundary total_from_sources ${total} does not match ${actualCount} records`, {
      source: `${documentSource}.summary.source_boundary`,
      recordId: "plugin_count",
    }));
  }
  if (isFalseMarker(sourceBoundary.plugin_count_matches_sources ?? sourceBoundary.pluginCountMatchesSources)) {
    errors.push(error("summary_plugin_count_mismatch", `${documentSource}:source_boundary reports plugin_count_matches_sources=false`, {
      source: `${documentSource}.summary.source_boundary`,
      recordId: "plugin_count",
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
    errors.push(error(documentReleaseBlockerCode(blocker), `${documentSource}:release_blockers contains ${formatBlocker(blocker)}`, {
      source: documentSource,
      recordId: blockerRecordId(blocker, "release_blockers"),
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

function validateEvidenceArtifact(status, artifactValue, schema, record, errors, context) {
  if (!isPassedEvidence(status)) return;
  const { label, codePrefix } = schema;
  const artifactPaths = artifactPathList(artifactValue);
  if (artifactPaths.length === 0) {
    errors.push(error(`missing_${codePrefix}_artifact`, `${record.source}:${record.recordId} ${label} evidence is missing an artifact path`, record));
    return;
  }
  for (const artifactPath of artifactPaths) {
    const resolved = path.isAbsolute(artifactPath) ? artifactPath : path.resolve(context.artifactRoot, artifactPath);
    if (!fs.existsSync(resolved) || !fs.statSync(resolved).isFile()) {
      errors.push(error(`${codePrefix}_artifact_missing`, `${record.source}:${record.recordId} ${label} artifact is missing: ${artifactPath}`, record));
      continue;
    }
    validateArtifactSchema(resolved, schema, artifactPath, record, errors);
  }
}

function validateArtifactSchema(resolved, schema, artifactPath, record, errors) {
  let artifact;
  try {
    artifact = JSON.parse(fs.readFileSync(resolved, "utf8"));
  } catch {
    errors.push(error(`invalid_${schema.codePrefix}_artifact`, `${record.source}:${record.recordId} ${schema.label} artifact is not valid JSON: ${artifactPath}`, record));
    return;
  }
  if (!isObject(artifact)) {
    errors.push(error(`invalid_${schema.codePrefix}_artifact`, `${record.source}:${record.recordId} ${schema.label} artifact must be a JSON object: ${artifactPath}`, record));
    return;
  }
  if (artifact.kind !== schema.expectedKind) {
    errors.push(error(`invalid_${schema.codePrefix}_artifact`, `${record.source}:${record.recordId} ${schema.label} artifact kind must be ${schema.expectedKind}: ${artifactPath}`, record));
  }
  if (artifact.status !== "passed") {
    errors.push(error(`invalid_${schema.codePrefix}_artifact`, `${record.source}:${record.recordId} ${schema.label} artifact status must be passed: ${artifactPath}`, record));
  }
  if (schema.expectedStage && artifact.stage !== schema.expectedStage) {
    errors.push(error(`invalid_${schema.codePrefix}_artifact`, `${record.source}:${record.recordId} ${schema.label} artifact stage must be ${schema.expectedStage}: ${artifactPath}`, record));
  }
  if (schema.expectedKind === "security_gate") {
    const allowed = artifact.allowed ?? artifact.decision?.allowed;
    if (allowed !== true) {
      errors.push(error(`invalid_${schema.codePrefix}_artifact`, `${record.source}:${record.recordId} ${schema.label} artifact must record an allowed security decision: ${artifactPath}`, record));
    }
  }
}

function validateAlignedPromotionEvidence(value, record, errors) {
  if (value.status !== "aligned") return;
  const requiredEvidence = [
    ["realPluginSmokeStatus", "real plugin smoke"],
    ["behaviorTestStatus", "behavior test"],
  ];
  for (const [statusField, label] of requiredEvidence) {
    if (!isPassedEvidence(value[statusField])) {
      errors.push(error("aligned_evidence_not_passed", `${record.source}:${record.recordId} aligned status requires passed ${label} evidence`, record));
    }
  }
  for (const field of SECURITY_EVIDENCE_FIELDS) {
    if (!isPassedEvidence(value[field.statusField])) {
      errors.push(error("aligned_security_evidence_not_passed", `${record.source}:${record.recordId} aligned status requires passed ${field.stage} security evidence`, record));
    }
  }
}

function validateRepresentativeEvidence(records, inventory, matrix, errors) {
  const sourceNames = new Set([
    ...sourceNamesFromDocument(inventory),
    ...sourceNamesFromDocument(matrix),
  ]);
  if (sourceNames.size === 0) return;

  for (const sourceName of REPRESENTATIVE_EVIDENCE_SOURCES) {
    if (!sourceNames.has(sourceName)) continue;
    const hasEvidence = records.some((record) => isRepresentativeEvidenceForSource(record, sourceName));
    if (!hasEvidence) {
      errors.push(error("missing_representative_plugin_evidence", `representative ${sourceName} plugin evidence is missing`, {
        source: "representative_evidence",
        recordId: sourceName,
      }));
    }
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

function isRepresentativeEvidenceForSource(record, sourceName) {
  const { value } = record;
  return value.sourceRepo === sourceName
    && RELEASE_READY_STATUSES.has(value.status)
    && isPassedEvidence(value.realPluginSmokeStatus)
    && isPassedEvidence(value.behaviorTestStatus)
    && artifactPathList(value.realPluginSmokeArtifact).length > 0
    && artifactPathList(value.behaviorTestArtifact).length > 0;
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
    sourceRepo: value.sourceRepo ?? value.source_repo ?? value.source_name ?? value.source,
    sourceRef: value.sourceRef ?? value.source_ref,
    entry: value.entry ?? value.entry_path,
    registerApis: value.registerApis ?? value.register_apis,
    sdkSubpaths: value.sdkSubpaths ?? value.sdk_subpaths,
    status: value.status ?? value.metis_status,
    realPluginSmokeStatus: value.realPluginSmokeStatus ?? value.real_plugin_smoke_status,
    realPluginSmokeArtifact: value.realPluginSmokeArtifact
      ?? value.realPluginSmokeArtifactPath
      ?? value.real_plugin_smoke_artifact
      ?? value.real_plugin_smoke_artifact_path
      ?? value.realPluginSmokeArtifacts
      ?? value.real_plugin_smoke_artifacts,
    behaviorTestStatus: value.behaviorTestStatus ?? value.behavior_test_status,
    behaviorTestArtifact: value.behaviorTestArtifact
      ?? value.behaviorTestArtifactPath
      ?? value.behavior_test_artifact
      ?? value.behavior_test_artifact_path
      ?? value.behaviorTestArtifacts
      ?? value.behavior_test_artifacts,
    installSecurityStatus: value.installSecurityStatus ?? value.install_security_status,
    installSecurityArtifact: value.installSecurityArtifact
      ?? value.installSecurityArtifactPath
      ?? value.install_security_artifact
      ?? value.install_security_artifact_path
      ?? value.installSecurityArtifacts
      ?? value.install_security_artifacts,
    startSecurityStatus: value.startSecurityStatus ?? value.start_security_status,
    startSecurityArtifact: value.startSecurityArtifact
      ?? value.startSecurityArtifactPath
      ?? value.start_security_artifact
      ?? value.start_security_artifact_path
      ?? value.startSecurityArtifacts
      ?? value.start_security_artifacts,
    handlerSecurityStatus: value.handlerSecurityStatus ?? value.handler_security_status,
    handlerSecurityArtifact: value.handlerSecurityArtifact
      ?? value.handlerSecurityArtifactPath
      ?? value.handler_security_artifact
      ?? value.handler_security_artifact_path
      ?? value.handlerSecurityArtifacts
      ?? value.handler_security_artifacts,
    runtimeFacetsRequired: value.runtimeFacetsRequired ?? value.runtime_facets_required,
    releaseBlockers: value.releaseBlockers ?? value.release_blockers,
    requiresMetisManifest: value.requiresMetisManifest ?? value.requires_metis_manifest,
    requiresWrapper: value.requiresWrapper ?? value.requires_wrapper,
    sourcePatched: value.sourcePatched ?? value.source_patched,
  };
}

function sourceNamesFromDocument(document) {
  if (!isObject(document) || !Array.isArray(document.sources)) return [];
  return document.sources
    .filter(isObject)
    .map((source) => firstNonEmpty(source.name, source.source))
    .filter(Boolean);
}

function isDirtySource(sourceRecord) {
  if (isMarked(sourceRecord.dirty) || isMarked(sourceRecord.source_dirty) || isMarked(sourceRecord.sourceDirty)) return true;
  if (isFalseMarker(sourceRecord.clean)) return true;
  const status = firstNonEmpty(sourceRecord.status, sourceRecord.state, sourceRecord.git_status, sourceRecord.gitStatus).toLowerCase();
  if (status === "dirty" || status === "source_dirty" || status.includes("dirty")) return true;
  return hasDirtyGitWorktree(sourceRecord.root);
}

function isPassedEvidence(value) {
  return String(value ?? "").trim().toLowerCase() === "passed";
}

function artifactPathList(value) {
  if (typeof value === "string") {
    const trimmed = value.trim();
    return trimmed ? [trimmed] : [];
  }
  if (Array.isArray(value)) {
    return value.flatMap((item) => artifactPathList(item));
  }
  if (isObject(value)) {
    return artifactPathList(value.path ?? value.file ?? value.artifact);
  }
  return [];
}

function hasDirtyGitWorktree(root) {
  if (!isPresent(root) || !fs.existsSync(root)) return false;
  try {
    return execFileSync("git", ["-C", String(root), "status", "--porcelain"], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim().length > 0;
  } catch {
    return false;
  }
}

function documentReleaseBlockerCode(blocker) {
  if (!isObject(blocker)) return "release_blocker";
  const code = firstNonEmpty(blocker.code);
  if (code === "source_missing" || code === "source_dirty") return code;
  return "release_blocker";
}

function blockerRecordId(blocker, fallback) {
  if (!isObject(blocker)) return fallback;
  return firstNonEmpty(blocker.plugin_id, blocker.pluginId, blocker.source, blocker.name, fallback);
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
