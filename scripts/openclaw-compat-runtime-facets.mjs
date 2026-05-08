const HOST_VERSION = "0.1.0";
const SENSITIVE_KEY = /(?:secret|token|password|passwd|authorization|api[_-]?key|credential)/i;

function isObject(value) {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function clone(value) {
  if (Array.isArray(value)) {
    return value.map((item) => clone(item));
  }
  if (isObject(value)) {
    return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, clone(item)]));
  }
  return value;
}

function deepFreeze(value) {
  if (Array.isArray(value) || isObject(value)) {
    for (const item of Object.values(value)) {
      deepFreeze(item);
    }
    Object.freeze(value);
  }
  return value;
}

export function createRedactor(config = {}, secrets = {}) {
  const secretValues = new Set();

  function collect(value, key = "") {
    if (value == null) {
      return;
    }
    if (typeof value === "string") {
      if ((SENSITIVE_KEY.test(key) || key === "") && value) {
        secretValues.add(value);
      }
      return;
    }
    if (Array.isArray(value)) {
      for (const item of value) {
        collect(item, key);
      }
      return;
    }
    if (isObject(value)) {
      for (const [childKey, childValue] of Object.entries(value)) {
        collect(childValue, childKey);
      }
    }
  }

  collect(secrets);
  collect(config);

  function redactString(value) {
    let out = String(value ?? "");
    for (const secret of secretValues) {
      if (secret) {
        out = out.split(secret).join("[REDACTED]");
      }
    }
    return out;
  }

  function sanitize(value, key = "") {
    if (typeof value === "string") {
      if (SENSITIVE_KEY.test(key)) {
        return "[REDACTED]";
      }
      return redactString(value);
    }
    if (typeof value === "function") {
      return "[Function]";
    }
    if (Array.isArray(value)) {
      return value.map((item) => sanitize(item, key));
    }
    if (isObject(value)) {
      return Object.fromEntries(Object.entries(value).map(([childKey, childValue]) => [childKey, sanitize(childValue, childKey)]));
    }
    return value;
  }

  return { sanitize, redactString };
}

export function createRuntimeState(params = {}) {
  const configSnapshot = isObject(params.config) ? clone(params.config) : {};
  const secrets = isObject(params.secrets) ? { ...params.secrets } : {};
  const redactor = params.redactor ?? createRedactor(configSnapshot, secrets);
  return {
    version: String(params.version ?? params.runtime?.version ?? HOST_VERSION),
    configSnapshot,
    secrets,
    redactor,
    diagnostics: Array.isArray(params.diagnostics) ? params.diagnostics : [],
    permissions: isObject(params.permissions) ? { ...params.permissions } : {},
    fetchPolicy: isObject(params.fetchPolicy) ? params.fetchPolicy : {},
    fetchImpl: typeof params.fetchImpl === "function" ? params.fetchImpl : null,
    adapters: isObject(params.adapters) ? params.adapters : {},
    mediaStore: new Map(),
    nextMediaId: 1,
  };
}

function addDiagnostic(state, diagnostic) {
  state.diagnostics.push(state.redactor.sanitize(diagnostic));
}

function allowedByGate(state, pluginId, facet) {
  if (state.permissions[facet] === true) {
    return true;
  }
  addDiagnostic(state, {
    code: "permission_denied",
    pluginId,
    facet,
    message: `${facet} runtime facet requires an explicit permission grant`,
  });
  return false;
}

async function resolveSecret(state, pluginId, name) {
  const key = String(name ?? "");
  const value = state.secrets[key] ?? "";
  addDiagnostic(state, {
    code: "secret_resolved",
    pluginId,
    name: key,
    value: value ? "[REDACTED]" : "",
    found: Boolean(value),
  });
  return value;
}

function normalizeUrl(value) {
  try {
    return new URL(String(value));
  } catch {
    return null;
  }
}

function urlMatches(pattern, url) {
  if (typeof pattern !== "string" || !pattern.trim()) {
    return false;
  }
  if (pattern === "*") {
    return true;
  }
  return url.href.startsWith(pattern) || `${url.protocol}//${url.host}` === pattern;
}

async function runtimeFetch(state, pluginId, urlValue, init = {}) {
  const url = normalizeUrl(urlValue);
  if (!url || (url.protocol !== "https:" && url.protocol !== "http:")) {
    addDiagnostic(state, { code: "fetch_denied", pluginId, reason: "invalid_url", url: String(urlValue ?? "") });
    return { ok: false, status: "blocked", reason: "invalid_url" };
  }

  const deny = Array.isArray(state.fetchPolicy.deny) ? state.fetchPolicy.deny : [];
  const allow = Array.isArray(state.fetchPolicy.allow) ? state.fetchPolicy.allow : [];
  if (deny.some((pattern) => urlMatches(pattern, url)) || (allow.length > 0 && !allow.some((pattern) => urlMatches(pattern, url)))) {
    addDiagnostic(state, { code: "fetch_denied", pluginId, reason: "policy", url: url.href });
    return { ok: false, status: "blocked", reason: "policy", url: url.href };
  }

  if (!state.fetchImpl) {
    addDiagnostic(state, { code: "fetch_diagnostic", pluginId, status: "not_configured", url: url.href });
    return { ok: false, status: "not_configured", url: url.href };
  }

  const response = await state.fetchImpl(url.href, init);
  const headers = response?.headers instanceof Map ? Object.fromEntries(response.headers) : Object.fromEntries(response?.headers ?? []);
  const body = typeof response?.text === "function" ? await response.text() : "";
  addDiagnostic(state, { code: "fetch_completed", pluginId, url: url.href, status: response?.status ?? 0 });
  return { ok: Boolean(response?.ok), status: response?.status ?? 0, headers, body };
}

function mediaRef(state, request) {
  const id = `media-${state.nextMediaId}`;
  state.nextMediaId += 1;
  return {
    id,
    uri: `metis://media/${id}`,
    name: String(request?.name ?? `${id}.bin`),
    mimeType: String(request?.mimeType ?? request?.mime ?? "application/octet-stream"),
    size: typeof request?.content === "string" ? Buffer.byteLength(request.content) : 0,
  };
}

function mediaKey(refOrId) {
  if (isObject(refOrId)) {
    return String(refOrId.id ?? refOrId.uri ?? "");
  }
  return String(refOrId ?? "");
}

function createMediaRuntime(state, pluginId) {
  return {
    upload: async (request = {}) => {
      if (!allowedByGate(state, pluginId, "media")) {
        return { ok: false, status: "permission_denied", facet: "media" };
      }
      const ref = mediaRef(state, request);
      state.mediaStore.set(ref.id, { ref, content: request.content ?? "" });
      addDiagnostic(state, { code: "media_ref_created", pluginId, ref });
      return { ok: true, ref };
    },
    resolve: async (refOrId) => {
      if (!allowedByGate(state, pluginId, "media")) {
        return { ok: false, status: "permission_denied", facet: "media" };
      }
      const key = mediaKey(refOrId).replace("metis://media/", "");
      const entry = state.mediaStore.get(key);
      return entry ? { ok: true, ref: entry.ref } : { ok: false, status: "not_found", ref: refOrId };
    },
    download: async (refOrId) => {
      if (!allowedByGate(state, pluginId, "media")) {
        return { ok: false, status: "permission_denied", facet: "media" };
      }
      const key = mediaKey(refOrId).replace("metis://media/", "");
      const entry = state.mediaStore.get(key);
      return entry ? { ok: true, ref: entry.ref, content: entry.content } : { ok: false, status: "not_found", ref: refOrId };
    },
  };
}

function gatedAdapter(state, pluginId, facet, action, fallback) {
  return async (...args) => {
    if (!allowedByGate(state, pluginId, facet)) {
      return { ok: false, status: "permission_denied", facet };
    }
    const adapter = state.adapters[facet];
    if (adapter && typeof adapter[action] === "function") {
      return adapter[action](...args);
    }
    return fallback(...args);
  };
}

function notApplicableFacet(state, pluginId, facet, action) {
  addDiagnostic(state, {
    code: "runtime_facet_not_applicable",
    pluginId,
    facet,
    action,
    message: `${facet}.${action} requires a Gateway adapter that is not wired in this runtime slice`,
  });
  return { ok: false, status: "not_applicable", facet, action };
}

export function createRuntimeFacets(state, pluginId) {
  const config = deepFreeze(state.redactor.sanitize(clone(state.configSnapshot)));
  return {
    version: state.version,
    config,
    secrets: {
      get: async (name) => resolveSecret(state, pluginId, name),
      resolve: async (name) => resolveSecret(state, pluginId, name),
    },
    media: createMediaRuntime(state, pluginId),
    fetch: async (url, init = {}) => runtimeFetch(state, pluginId, url, init),
    reply: {
      send: gatedAdapter(state, pluginId, "reply", "send", async () => notApplicableFacet(state, pluginId, "reply", "send")),
    },
    conversation: {
      get: gatedAdapter(state, pluginId, "conversation", "get", async () =>
        notApplicableFacet(state, pluginId, "conversation", "get"),
      ),
      list: gatedAdapter(state, pluginId, "conversation", "list", async () =>
        notApplicableFacet(state, pluginId, "conversation", "list"),
      ),
    },
    thread: {
      get: gatedAdapter(state, pluginId, "thread", "get", async () => notApplicableFacet(state, pluginId, "thread", "get")),
      list: gatedAdapter(state, pluginId, "thread", "list", async () => notApplicableFacet(state, pluginId, "thread", "list")),
    },
    process: {
      spawn: gatedAdapter(state, pluginId, "process", "spawn", async () =>
        notApplicableFacet(state, pluginId, "process", "spawn"),
      ),
      env: gatedAdapter(state, pluginId, "process", "env", async () => notApplicableFacet(state, pluginId, "process", "env")),
    },
    provider: {
      listModels: gatedAdapter(state, pluginId, "provider", "listModels", async (request = {}) => ({
        ok: false,
        status: "not_configured",
        contract: "metis.model-provider-registry.v1",
        providerId: String(request.providerId ?? ""),
        models: [],
      })),
      stream: gatedAdapter(state, pluginId, "provider", "stream", async (request = {}) => ({
        ok: false,
        status: "not_configured",
        contract: "metis.model-provider-stream.v1",
        model: String(request.model ?? ""),
        chunks: [],
      })),
      toolCall: gatedAdapter(state, pluginId, "provider", "toolCall", async (request = {}) => ({
        ok: false,
        status: "not_configured",
        contract: "metis.model-provider-tool-call.v1",
        name: String(request.name ?? ""),
      })),
    },
    memory: {
      search: gatedAdapter(state, pluginId, "memory", "search", async (request = {}) => ({
        ok: false,
        status: "not_configured",
        contract: "metis.memory-context-backend.v1",
        query: String(request.query ?? ""),
        hits: [],
      })),
      write: gatedAdapter(state, pluginId, "memory", "write", async (request = {}) => ({
        ok: false,
        status: "not_configured",
        contract: "metis.memory-context-backend.v1",
        key: String(request.key ?? ""),
      })),
    },
    browser: {
      open: gatedAdapter(state, pluginId, "browser", "open", async () => ({
        ok: false,
        status: "not_applicable",
        facet: "browser",
        notApplicable: true,
        reason: "browser automation is not exposed by this Metis OpenClaw runtime slice",
      })),
    },
    realtime: {
      connect: gatedAdapter(state, pluginId, "realtime", "connect", async () => ({
        ok: false,
        status: "not_applicable",
        facet: "realtime",
        notApplicable: true,
        reason: "realtime socket/session runtime is not exposed by this Metis OpenClaw runtime slice",
      })),
    },
  };
}
