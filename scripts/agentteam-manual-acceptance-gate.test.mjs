import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(__dirname, "..");
const gateScript = path.join(root, "scripts", "agentteam-manual-acceptance-gate.sh");

function runGate(extraEnv = {}) {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "metis-agentteam-gate-test-"));
  const metisHome = path.join(tempRoot, "home");
  const reportDir = path.join(tempRoot, "report");
  fs.mkdirSync(metisHome, { recursive: true });
  const result = spawnSync("bash", [gateScript], {
    cwd: root,
    encoding: "utf8",
    env: {
      ...process.env,
      METIS_AGENTTEAM_SKIP_ENVSETUP: "1",
      METIS_HOME: metisHome,
      METIS_AGENTTEAM_REPORT_DIR: reportDir,
      ...extraEnv,
    },
  });
  return { ...result, tempRoot, reportDir };
}

function readReport(reportDir) {
  return JSON.parse(fs.readFileSync(path.join(reportDir, "report.json"), "utf8"));
}

test("Telegram live opt-in without external resources requires external resources, not a failed gate", () => {
  const result = runGate({
    METIS_AGENTTEAM_LIVE_TELEGRAM: "1",
    METIS_AGENTTEAM_TELEGRAM_ACCOUNT_ID: "",
    METIS_AGENTTEAM_TELEGRAM_TEST_CHAT_ID: "",
  });

  assert.equal(result.status, 0, result.stderr || result.stdout);
  const report = readReport(result.reportDir);
  assert.equal(report.envOptIn.telegram.enabled, true);
  const phase1 = report.phaseStatus.find((phase) => phase.id === "phase1");
  assert.equal(phase1.status, "external-resource-required");
  assert.equal(phase1.reason, "missing-live-resource");
  assert(report.externalResources.some((item) => item.env === "METIS_AGENTTEAM_TELEGRAM_ACCOUNT_ID" && item.status === "missing"));
  assert(report.externalResources.some((item) => item.env === "METIS_AGENTTEAM_TELEGRAM_TEST_CHAT_ID" && item.status === "missing"));
});

test("does not invoke an interactive pager and prints final artifact paths", () => {
  const result = runGate({
    GIT_PAGER: "sh -c 'echo METIS_PAGER_SHOULD_NOT_RUN >&2; exit 97'",
    PAGER: "sh -c 'echo METIS_PAGER_SHOULD_NOT_RUN >&2; exit 97'",
    LESS: "-R",
  });

  assert.equal(result.status, 0, result.stderr || result.stdout);
  const combinedOutput = `${result.stdout}\n${result.stderr}`;
  assert.doesNotMatch(combinedOutput, /METIS_PAGER_SHOULD_NOT_RUN/);
  assert.doesNotMatch(combinedOutput, /\x1b\[[0-9;]*[JH]/);
  assert.match(result.stdout, /interactive pagers disabled/);
  assert.match(result.stdout, /manual acceptance gate completed/);
  assert.match(result.stdout, /report JSON: .*\/report\.json/);
  assert.match(result.stdout, /manual template: .*\/manual-acceptance-template\.md/);
});

test("writes a series23 phase, GAP, and M01-M32 release evidence report", () => {
  const result = runGate();

  assert.equal(result.status, 0, result.stderr || result.stdout);
  const report = readReport(result.reportDir);
  assert.equal(report.kind, "metis-agentteam-series23-manual-acceptance-gate-report");
  assert.equal(report.series, "23");
  assert.equal(report.source.id, "series23");
  assert.match(report.source.path, /metis-agent-team-series-23-source-backed-gap-quantification-manual-acceptance-2026-05-16\.md$/);
  assert.match(report.git.head, /^[0-9a-f]{40}$/);
  assert.equal(report.statuses.localPass, "local-pass");
  assert.equal(report.statuses.skipped, "skipped");
  assert.equal(report.statuses.externalResourceRequired, "external-resource-required");
  assert.equal(report.statuses.operatorRecordRequired, "operator-record-required");

  const phaseById = new Map(report.phaseStatus.map((phase) => [phase.id, phase]));
  assert.equal(phaseById.get("phase0").status, "local-pass");
  assert.equal(phaseById.get("phase1").status, "skipped");
  assert.equal(phaseById.get("phase2").status, "skipped");
  assert.equal(phaseById.get("phase3").status, "skipped");
  assert.equal(phaseById.get("phase4").status, "skipped");
  assert.equal(phaseById.get("phase5").status, "skipped");
  assert.equal(phaseById.get("phase6").status, "skipped");
  assert.equal(phaseById.get("phase7").status, "operator-record-required");
  assert.equal(phaseById.get("phase8").status, "external-resource-required");
  assert.equal(phaseById.get("phase9").status, "operator-record-required");

  const expectedGaps = Array.from({ length: 26 }, (_, index) => `G${String(index + 1).padStart(2, "0")}`);
  assert.deepEqual(report.gapStatus.map((gap) => gap.id), expectedGaps);
  const gapById = new Map(report.gapStatus.map((gap) => [gap.id, gap]));
  assert.equal(gapById.get("G01").status, "local-pass");
  assert.equal(gapById.get("G11").status, "skipped");
  assert.equal(gapById.get("G18").status, "skipped");
  assert.equal(gapById.get("G23").status, "operator-record-required");
  assert.equal(gapById.get("G24").status, "local-pass");
  assert.equal(gapById.get("G25").status, "local-pass");
  assert.equal(gapById.get("G26").status, "operator-record-required");

  const expectedManualItems = Array.from({ length: 32 }, (_, index) => `M${String(index + 1).padStart(2, "0")}`);
  assert.deepEqual(report.manualAcceptance.map((item) => item.id), expectedManualItems);
  const manualById = new Map(report.manualAcceptance.map((item) => [item.id, item]));
  assert.equal(manualById.get("M01").status, "local-pass");
  assert.equal(manualById.get("M12").status, "skipped");
  assert.equal(manualById.get("M18").status, "skipped");
  assert.equal(manualById.get("M19").title, "Feishu app and token modes");
  assert.equal(manualById.get("M27").title, "Feishu auth command");
  assert.equal(manualById.get("M28").title, "Control UI browser smoke");
  assert.equal(manualById.get("M32").status, "local-pass");
  assert.equal(manualById.get("M32").nextStep, "review report.json and complete manual-acceptance-template.md with redacted operator evidence");
  assert(report.manualAcceptance.every((item) => Array.isArray(item.evidenceFields)));
  assert(report.manualAcceptance.every((item) => typeof item.redaction === "string" && item.redaction.length > 0));
  assert(report.operatorGuidance.some((item) => item.status === "skipped" && item.nextStep.includes("Set METIS_AGENTTEAM_LIVE_TELEGRAM")));
  assert(report.releaseVerification.some((item) => item.id === "cangjie-build-test" && item.command.includes("cjpm clean")));
  assert(report.releaseVerification.some((item) => item.id === "ui-browser-smoke" && item.status === "skipped"));

  const template = fs.readFileSync(path.join(result.reportDir, "manual-acceptance-template.md"), "utf8");
  assert.match(template, /## Phase 0 Source Matrix/);
  assert.match(template, /## Phase 1 Telegram Live Gate/);
  assert.match(template, /## Phase 2 Feishu Route Live Gate/);
  assert.match(template, /## Phase 3 Feishu OAuth And OAPI Live Gate/);
  assert.match(template, /## Phase 9 Release Evidence Pack/);
  assert.match(template, /\| M32 \|/);
  assert.match(template, /\| G11 \| skipped \|/);
  assert.match(template, /\| G25 \| local-pass \|/);
  assert.match(template, /\| G26 \| operator-record-required \|/);
  assert.match(template, /\| M28 Control UI browser smoke \| skipped \| TODO \|/);
  assert.match(template, /Evidence fields/);
  assert.match(template, /Redaction/);
});

test("live opt-in with redacted resources records operator evidence requirement, not success", () => {
  const result = runGate({
    METIS_AGENTTEAM_LIVE_TELEGRAM: "1",
    METIS_AGENTTEAM_TELEGRAM_ACCOUNT_ID: "telegram-account-secret-shaped-value",
    METIS_AGENTTEAM_TELEGRAM_TEST_CHAT_ID: "telegram-chat-secret-shaped-value",
    METIS_AGENTTEAM_LIVE_FEISHU: "1",
    METIS_AGENTTEAM_FEISHU_ACCOUNT_ID_A: "feishu-account-a-secret-shaped-value",
    METIS_AGENTTEAM_FEISHU_ACCOUNT_ID_B: "feishu-account-b-secret-shaped-value",
    METIS_AGENTTEAM_FEISHU_TEST_GROUP_ID: "feishu-group-secret-shaped-value",
    METIS_AGENTTEAM_FEISHU_TEST_THREAD_ID: "feishu-thread-secret-shaped-value",
    METIS_AGENTTEAM_FEISHU_TEST_APP_ID: "feishu-app-secret-shaped-value",
    METIS_AGENTTEAM_FEISHU_TEST_USER_ID: "feishu-user-secret-shaped-value",
    METIS_AGENTTEAM_FEISHU_TEST_DOC_ID: "feishu-doc-secret-shaped-value",
    METIS_AGENTTEAM_FEISHU_TEST_WIKI_ID: "feishu-wiki-secret-shaped-value",
    METIS_AGENTTEAM_FEISHU_TEST_CALENDAR_ID: "feishu-calendar-secret-shaped-value",
    METIS_AGENTTEAM_FEISHU_TEST_TASK_ID: "feishu-task-secret-shaped-value",
    METIS_AGENTTEAM_FEISHU_TEST_BITABLE_ID: "feishu-bitable-secret-shaped-value",
    METIS_AGENTTEAM_FEISHU_TEST_SHEET_ID: "feishu-sheet-secret-shaped-value",
    METIS_AGENTTEAM_FEISHU_TEST_MESSAGE_ID: "feishu-message-secret-shaped-value",
  });

  assert.equal(result.status, 0, result.stderr || result.stdout);
  const report = readReport(result.reportDir);
  const phaseById = new Map(report.phaseStatus.map((phase) => [phase.id, phase]));
  assert.equal(phaseById.get("phase1").status, "operator-record-required");
  assert.equal(phaseById.get("phase2").status, "operator-record-required");
  assert.equal(phaseById.get("phase3").status, "operator-record-required");
  assert.equal(phaseById.get("phase6").status, "operator-record-required");
  assert.equal(report.envOptIn.telegram.enabled, true);
  assert.equal(report.envOptIn.feishu.enabled, true);

  const combinedEvidence = [
    fs.readFileSync(path.join(result.reportDir, "report.json"), "utf8"),
    fs.readFileSync(path.join(result.reportDir, "manual-acceptance-template.md"), "utf8"),
  ].join("\n");
  assert.doesNotMatch(combinedEvidence, /telegram-account-secret-shaped-value|feishu-account-a-secret-shaped-value|feishu-message-secret-shaped-value/);
  assert.doesNotMatch(combinedEvidence, /appSecret|accessToken|refreshToken|Authorization|bot token/i);
});

test("Telegram phase 1 evidence fields are explicit and redaction-safe", () => {
  const result = runGate({
    METIS_AGENTTEAM_LIVE_TELEGRAM: "1",
    METIS_AGENTTEAM_TELEGRAM_ACCOUNT_ID: "telegram-account-secret-shaped-value",
    METIS_AGENTTEAM_TELEGRAM_TEST_CHAT_ID: "telegram-private-chat-secret-shaped-value",
    METIS_AGENTTEAM_TELEGRAM_TEST_GROUP_ID: "telegram-group-secret-shaped-value",
    METIS_AGENTTEAM_TELEGRAM_TEST_TOPIC_ID: "telegram-topic-secret-shaped-value",
  });

  assert.equal(result.status, 0, result.stderr || result.stdout);
  const report = readReport(result.reportDir);
  assert.equal(report.telegramLiveReadiness.phase, "phase1");
  assert.equal(report.telegramLiveReadiness.gap, "G11");
  assert.deepEqual(report.telegramLiveReadiness.manualItems, ["M12", "M13", "M14"]);
  assert.deepEqual(report.telegramLiveReadiness.routePreflight.requiredPeerKinds, ["private", "group", "topic"]);
  assert(report.telegramLiveReadiness.broadcastEvidenceFields.includes("selectedAgentIds"));
  assert(report.telegramLiveReadiness.broadcastEvidenceFields.includes("agents[].sessionKey"));
  assert(report.telegramLiveReadiness.logEvidence.requiredMarkers.includes("Gateway.inbound: channel=telegram"));
  assert(report.telegramLiveReadiness.logEvidence.forbiddenMarkerRefs.includes("auth-header"));
  assert.equal(report.telegramLiveReadiness.redacted, true);

  const combinedEvidence = [
    fs.readFileSync(path.join(result.reportDir, "report.json"), "utf8"),
    fs.readFileSync(path.join(result.reportDir, "manual-acceptance-template.md"), "utf8"),
  ].join("\n");
  assert.match(combinedEvidence, /privateBindingCount/);
  assert.match(combinedEvidence, /selectedAgentIds/);
  assert.doesNotMatch(combinedEvidence, /telegram-account-secret-shaped-value|telegram-private-chat-secret-shaped-value|telegram-group-secret-shaped-value|telegram-topic-secret-shaped-value/);
});
