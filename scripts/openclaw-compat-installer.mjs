import fs from "node:fs";
import path from "node:path";

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

  return {
    ok: true,
    pluginRoot: root,
    packageName: typeof pkg.name === "string" ? pkg.name : path.basename(root),
    stageRoot: path.resolve(options.stageRoot ?? path.join(root, ".metis-openclaw-stage")),
    requiresInstall: false,
    workspaceRoot,
    workspaceLinks,
  };
}

export function preparePluginStage(pluginRoot, options = {}) {
  const plan = createInstallPlan(pluginRoot, options);
  const stageRoot = plan.stageRoot;
  const nodeModules = path.join(stageRoot, "node_modules");
  fs.mkdirSync(nodeModules, { recursive: true });
  for (const link of plan.workspaceLinks) {
    const target = linkPath(nodeModules, link.name);
    fs.mkdirSync(path.dirname(target), { recursive: true });
    fs.rmSync(target, { recursive: true, force: true });
    fs.symlinkSync(link.target, target, "dir");
  }
  return { ...plan, stageRoot };
}

export default { createInstallPlan, preparePluginStage };
