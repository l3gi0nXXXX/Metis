import fs from "node:fs";
import path from "node:path";

import { enforceOpenClawInstallSource } from "./openclaw-compat-security-policy.mjs";

function isObject(value) {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function readJsonFile(file) {
  try {
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch {
    return {};
  }
}

function packageJson(root) {
  return readJsonFile(path.join(root, "package.json"));
}

function asArray(value) {
  return Array.isArray(value) ? value : typeof value === "string" ? [value] : [];
}

function findWorkspaceRoot(root) {
  let current = path.resolve(root);
  while (true) {
    const pkg = packageJson(current);
    if (Array.isArray(pkg.workspaces) || Array.isArray(pkg.workspaces?.packages)) {
      return current;
    }
    const next = path.dirname(current);
    if (next === current) {
      return "";
    }
    current = next;
  }
}

function workspacePatterns(workspaceRoot) {
  const pkg = packageJson(workspaceRoot);
  return asArray(pkg.workspaces ?? pkg.workspaces?.packages);
}

function workspacePackageDirs(workspaceRoot) {
  const dirs = [];
  for (const pattern of workspacePatterns(workspaceRoot)) {
    if (!pattern.endsWith("/*")) {
      continue;
    }
    const parent = path.join(workspaceRoot, pattern.slice(0, -2));
    if (!fs.existsSync(parent)) {
      continue;
    }
    for (const child of fs.readdirSync(parent)) {
      const dir = path.join(parent, child);
      if (fs.existsSync(path.join(dir, "package.json"))) {
        dirs.push(dir);
      }
    }
  }
  return dirs;
}

function dependencyEntries(pkg) {
  return {
    ...pkg.dependencies,
    ...pkg.devDependencies,
    ...pkg.peerDependencies,
  };
}

function linkPath(nodeModules, name) {
  if (name.startsWith("@")) {
    const [scope, packageName] = name.split("/");
    return path.join(nodeModules, scope, packageName);
  }
  return path.join(nodeModules, name);
}

function detectPackageManager(root, workspaceRoot = "") {
  const roots = [root, workspaceRoot].filter(Boolean);
  for (const base of roots) {
    if (fs.existsSync(path.join(base, "pnpm-lock.yaml"))) {
      return { name: "pnpm", reason: "pnpm-lock.yaml" };
    }
    if (fs.existsSync(path.join(base, "yarn.lock"))) {
      return { name: "yarn", reason: "yarn.lock" };
    }
    if (fs.existsSync(path.join(base, "package-lock.json")) || fs.existsSync(path.join(base, "npm-shrinkwrap.json"))) {
      return { name: "npm", reason: "npm-lockfile" };
    }
  }

  const pkg = packageJson(root);
  if (typeof pkg.packageManager === "string") {
    const [name] = pkg.packageManager.split("@");
    if (["npm", "pnpm", "yarn"].includes(name)) {
      return { name, reason: "packageManager" };
    }
  }
  return { name: "npm", reason: "default" };
}

function installCommandFor(packageManager) {
  if (packageManager.name === "pnpm") {
    return ["pnpm", "install", "--frozen-lockfile", "--ignore-scripts"];
  }
  if (packageManager.name === "yarn") {
    return ["yarn", "install", "--immutable", "--ignore-scripts"];
  }
  return packageManager.reason === "npm-lockfile" ? ["npm", "ci", "--ignore-scripts"] : ["npm", "install", "--ignore-scripts"];
}

function sourceGateConfigured(options) {
  return (
    options.security?.enabled === true ||
    isObject(options.source) ||
    Array.isArray(options.sourceAllowlist) ||
    isObject(options.sourceAllowlist) ||
    Array.isArray(options.security?.sourceAllowlist) ||
    isObject(options.security?.sourceAllowlist)
  );
}

function sourceAllowlistFromOptions(options) {
  return options.sourceAllowlist ?? options.security?.sourceAllowlist ?? [];
}

function sourceFromOptions(root, options) {
  const source = isObject(options.source) ? options.source : isObject(options.security?.source) ? options.security.source : {};
  return {
    url: source.url ?? source.repository ?? source.repo ?? options.sourceUrl ?? "",
    ref: source.ref ?? source.tag ?? source.commit ?? options.sourceRef ?? "",
    hash: source.hash ?? source.sha256 ?? source.integrity ?? options.sourceHash ?? "",
    root,
  };
}

function installSecurityDecision(root, packageName, options) {
  if (!sourceGateConfigured(options)) {
    return {
      pluginId: packageName,
      stage: "install",
      allowed: true,
      code: "not_configured",
      diagnostics: {},
    };
  }
  return enforceOpenClawInstallSource({
    pluginId: packageName,
    source: sourceFromOptions(root, options),
    sourceAllowlist: sourceAllowlistFromOptions(options),
  });
}

function hasUnlinkedDependencies(pkg, workspaceLinks) {
  const linked = new Set(workspaceLinks.map((link) => link.name));
  for (const name of Object.keys(dependencyEntries(pkg))) {
    if (!linked.has(name)) {
      return true;
    }
  }
  return false;
}

function copyPluginPackage(root, target) {
  fs.rmSync(target, { recursive: true, force: true });
  fs.cpSync(root, target, {
    recursive: true,
    dereference: false,
    filter(source) {
      const rel = path.relative(root, source);
      if (!rel) {
        return true;
      }
      const parts = rel.split(path.sep);
      return !["node_modules", ".git", ".metis-openclaw-stage"].includes(parts[0]);
    },
  });
}

export function createInstallPlan(pluginRoot, options = {}) {
  const root = path.resolve(pluginRoot);
  const pkg = packageJson(root);
  const workspaceRoot = findWorkspaceRoot(root);
  const workspaceByName = new Map();
  if (workspaceRoot) {
    for (const dir of workspacePackageDirs(workspaceRoot)) {
      const workspacePkg = packageJson(dir);
      if (typeof workspacePkg.name === "string") {
        workspaceByName.set(workspacePkg.name, dir);
      }
    }
  }

  const workspaceLinks = [];
  for (const [name, spec] of Object.entries(dependencyEntries(pkg))) {
    if (spec === "workspace:*" && workspaceByName.has(name)) {
      workspaceLinks.push({ name, target: workspaceByName.get(name), reason: "workspace_dependency" });
    }
  }

  if (typeof options.openclawPackageRoot === "string" && options.openclawPackageRoot.trim()) {
    workspaceLinks.push({ name: "openclaw", target: path.resolve(options.openclawPackageRoot), reason: "openclaw_sdk" });
  }

  const stageRoot = path.resolve(options.stageRoot ?? path.join(root, ".metis-openclaw-stage"));
  const packageManager = detectPackageManager(root, workspaceRoot);
  const installCommand = installCommandFor(packageManager);
  const packageName = typeof pkg.name === "string" ? pkg.name : path.basename(root);
  const security = installSecurityDecision(root, packageName, options);

  return {
    ok: security.allowed,
    pluginRoot: root,
    packageName,
    stageRoot,
    stagedPluginRoot: path.join(stageRoot, "package"),
    requiresInstall: hasUnlinkedDependencies(pkg, workspaceLinks),
    packageManager,
    installCommand,
    workspaceRoot,
    workspaceLinks,
    security,
  };
}

export function preparePluginStage(pluginRoot, options = {}) {
  const plan = createInstallPlan(pluginRoot, options);
  if (plan.security && plan.security.allowed === false) {
    const error = new Error(`OpenClaw install source denied: ${plan.security.code}`);
    error.security = plan.security;
    throw error;
  }
  const stageRoot = plan.stageRoot;
  const nodeModules = path.join(stageRoot, "node_modules");
  fs.mkdirSync(nodeModules, { recursive: true });
  copyPluginPackage(plan.pluginRoot, plan.stagedPluginRoot);
  for (const link of plan.workspaceLinks) {
    const target = linkPath(nodeModules, link.name);
    fs.mkdirSync(path.dirname(target), { recursive: true });
    fs.rmSync(target, { recursive: true, force: true });
    fs.symlinkSync(link.target, target, "dir");
  }
  return { ...plan, stageRoot };
}

export default { createInstallPlan, preparePluginStage };
