import process from "node:process";
import util from "node:util";

const SENSITIVE_KEY =
  /(?:secret|token|password|passwd|authorization|api[_-]?key|credential|private[_-]?key|client[_-]?secret|refresh[_-]?token|access[_-]?token)/i;

let knownSecrets = [];
let consolePatched = false;

function readSecret(value) {
  return typeof value === "string" ? value.trim() : "";
}

export function configureKnownSecrets(values = []) {
  const seen = new Set();
  for (const value of values) {
    const secret = readSecret(value);
    if (secret) {
      seen.add(secret);
    }
  }
  knownSecrets = [...seen].sort((a, b) => b.length - a.length);
}

export function addKnownSecrets(values = []) {
  const seen = new Set(knownSecrets);
  for (const value of values) {
    const secret = readSecret(value);
    if (secret) {
      seen.add(secret);
    }
  }
  knownSecrets = [...seen].sort((a, b) => b.length - a.length);
}

function redactString(value) {
  let out = String(value);
  for (const secret of knownSecrets) {
    out = out.split(secret).join("[REDACTED]");
  }
  return out
    .replace(/([?&](?:token|secret|password|key|authorization)=)[^&#\s]+/gi, "$1[REDACTED]")
    .replace(/\b(authorization:\s*bearer\s+)[^\s,;]+/gi, "$1[REDACTED]")
    .replace(/\b(password|token|secret|api[_-]?key)=([^\s&]+)/gi, "$1=[REDACTED]");
}

export function redactKnownSecrets(value, key = "") {
  if (typeof value === "string") {
    if (SENSITIVE_KEY.test(key)) {
      return "[REDACTED]";
    }
    return redactString(value);
  }
  if (Array.isArray(value)) {
    return value.map((item) => redactKnownSecrets(item, key));
  }
  if (value != null && typeof value === "object") {
    const out = {};
    for (const [childKey, childValue] of Object.entries(value)) {
      out[childKey] = redactKnownSecrets(childValue, childKey);
    }
    return out;
  }
  return value;
}

function writeLine(stream, line) {
  try {
    stream.write(`${line}\n`);
  } catch (error) {
    if (error?.code !== "EPIPE") {
      throw error;
    }
  }
}

// Runtime sidecar stdout is reserved for machine protocol frames.
// Human diagnostics, console capture, and crash context must use stderr.
export function writeProtocol(frame) {
  writeLine(process.stdout, JSON.stringify(redactKnownSecrets(frame)));
}

export function writeDiagnostic(level, message, meta = undefined, options = {}) {
  const prefix = options.prefix ?? "metis-sidecar";
  const normalizedLevel = String(level ?? "info").toLowerCase();
  const text = redactKnownSecrets(String(message ?? ""));
  const redactedMeta = meta == null ? "" : ` ${JSON.stringify(redactKnownSecrets(meta))}`;
  writeLine(process.stderr, `[${prefix}] ${normalizedLevel}: ${text}${redactedMeta}`);
}

export function installConsoleStderrPatch(options = {}) {
  if (consolePatched) {
    return;
  }
  consolePatched = true;

  const prefix = options.prefix ?? "metis-sidecar";
  const emit = (level, args) => {
    writeDiagnostic(level, util.format(...args), undefined, { prefix });
  };

  console.log = (...args) => emit("info", args);
  console.info = (...args) => emit("info", args);
  console.warn = (...args) => emit("warn", args);
  console.error = (...args) => emit("error", args);
  console.debug = (...args) => emit("debug", args);
  console.trace = (...args) => emit("trace", args);
}
