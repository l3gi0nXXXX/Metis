#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Install Metis gateway plugins by channel name.

Usage:
  python tools/gateway_plugin_tool/install.py list
  python tools/gateway_plugin_tool/install.py install dingtalk
  python tools/gateway_plugin_tool/install.py install all
  python tools/gateway_plugin_tool/install.py deps dingtalk
  python tools/gateway_plugin_tool/install.py deps all
  python tools/gateway_plugin_tool/install.py install wechat --state-root C:/Users/example
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Dict, List, Tuple

SUPPORTED: Dict[str, Dict[str, str]] = {
    "dingtalk": {"plugin_id": "dingtalk", "channel": "dingtalk"},
    "wechat": {"plugin_id": "wechat", "channel": "wechat"},
    "wecom": {"plugin_id": "wecom", "channel": "wecom"},
    "wechat-mp": {"plugin_id": "wechat-mp", "channel": "wechat-mp"},
    "qq": {"plugin_id": "qq", "channel": "qq"},
    "feishu": {"plugin_id": "feishu", "channel": "feishu"},
}

_TOOL_ROOT = Path(__file__).resolve().parent
REQUIREMENTS_DIR = _TOOL_ROOT / "requirements"


def default_state_root() -> Path:
    return Path.home()


def plugin_root(state_root: Path, plugin_id: str) -> Path:
    return state_root / ".metis" / "gateway-plugins" / plugin_id


def plugin_config_path(state_root: Path, plugin_id: str) -> Path:
    return plugin_root(state_root, plugin_id) / "plugin-config.json"


def manifest_obj(plugin_id: str, channel: str) -> dict:
    return {
        "id": plugin_id,
        "channels": [channel],
        "gatewayRuntime": {
            "kind": "command-adapter",
            "command": "python",
            "script": "adapter.py",
        },
    }


def default_plugin_config(plugin_id: str, app_id: str, app_secret: str) -> dict:
    """与参考实现对齐：钉钉使用 channels.dingtalk.*；其余渠道可仅用扁平凭证或空对象。"""
    if plugin_id == "dingtalk":
        block: dict = {
            "enabled": True,
            "transport": "stream",
            "webhookHost": "0.0.0.0",
            "webhookPort": 8890,
            "webhookPath": "/dingtalk/callback",
        }
        if app_id:
            block["clientId"] = app_id
        if app_secret:
            block["clientSecret"] = app_secret
        return {"channels": {"dingtalk": block}}
    cfg: dict = {}
    if app_id:
        cfg["app-id"] = app_id
    if app_secret:
        cfg["app-secret"] = app_secret
    return cfg


def copy_runtime_bundle(runtime_src: Path, dst: Path) -> None:
    """将 runtime/ 下 Python 包复制到插件目录（含 channels/*、兼容辅助模块）。"""
    for src_file in runtime_src.rglob("*"):
        if src_file.is_dir():
            continue
        if "__pycache__" in src_file.parts or src_file.suffix == ".pyc":
            continue
        rel = src_file.relative_to(runtime_src)
        out_path = dst / rel
        out_path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src_file, out_path)


def _next_steps_print(plugin_id: str, app_id: str, app_secret: str) -> None:
    print("")
    print("Next steps:")
    if plugin_id == "dingtalk":
        print("  pip install -r tools/gateway_plugin_tool/requirements/dingtalk.txt")
        print("  # 或: python tools/gateway_plugin_tool/install.py deps dingtalk")
        print("  # 钉钉默认 Stream 模式，无需配置回调 URL；需 AppKey/AppSecret（CLI: app-id / app-secret）")
    elif plugin_id in SUPPORTED:
        req_name = plugin_id
        print(f"  pip install -r tools/gateway_plugin_tool/requirements/{req_name}.txt")
        print(f"  # 或: python tools/gateway_plugin_tool/install.py deps {req_name}")
    print(f"  gateway plugin enable {plugin_id}")
    if plugin_id == "dingtalk":
        print("  # 也可在 plugin-config.json 的 channels.dingtalk 填写 clientId / clientSecret")
    if not app_id:
        print(f"  gateway plugin set {plugin_id} app-id <client-id>")
    if not app_secret:
        print(f"  gateway plugin set {plugin_id} app-secret <client-secret>")
    print("  gateway restart")
    print("")
    if app_id or app_secret:
        print("Credentials were written into plugin-config.json; you can still override via CLI.")
    else:
        print("Credentials are optional at install time; you can set them later via CLI.")


def install_plugin(
    name: str,
    state_root: Path,
    force: bool,
    app_id: str,
    app_secret: str,
    *,
    batch: bool,
) -> int:
    if name not in SUPPORTED:
        print(f"Unsupported channel: {name}")
        print("Use `list` to see supported channels.")
        return 1

    meta = SUPPORTED[name]
    pid = meta["plugin_id"]
    channel = meta["channel"]

    dst = plugin_root(state_root, pid)
    dst.mkdir(parents=True, exist_ok=True)

    adapter_dst = dst / "adapter.py"
    manifest_dst = dst / "metis.plugin.json"
    config_dst = plugin_config_path(state_root, pid)
    runtime_src = _TOOL_ROOT / "runtime"

    if not runtime_src.is_dir():
        print(f"Missing runtime bundle: {runtime_src}")
        return 1

    if adapter_dst.exists() and not force:
        if batch:
            print(f"Skip {name}: adapter.py already exists -> {adapter_dst} (use --force to overwrite)")
            return 0
        print(f"adapter.py already exists: {adapter_dst}")
        print("Use --force to overwrite.")
        return 1
    # 批量模式下不因仅有 manifest 而跳过（可能误删了 adapter，需补全）
    if manifest_dst.exists() and not force and not batch:
        print(f"Plugin manifest already exists: {manifest_dst}")
        print("Use --force to overwrite.")
        return 1

    copy_runtime_bundle(runtime_src, dst)
    manifest_dst.write_text(
        json.dumps(manifest_obj(pid, channel), ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    if not config_dst.exists():
        cfg = default_plugin_config(pid, app_id, app_secret)
        config_dst.write_text(json.dumps(cfg, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print(f"Installed plugin: {pid}")
    print(f"Path: {dst}")
    _next_steps_print(pid, app_id, app_secret)
    return 0


def run_list() -> int:
    print("Supported channels:")
    for k in sorted(SUPPORTED.keys()):
        print(f"  - {k}")
    print("")
    print("Install one:  python install.py install <name>")
    print("Install all:  python install.py install all")
    print("Python deps:  python install.py deps <name>|all")
    return 0


def run_install(
    name: str,
    state_root: Path,
    force: bool,
    app_id: str,
    app_secret: str,
) -> int:
    key = name.strip().lower()
    if key == "all":
        return run_install_all(state_root, force, app_id, app_secret)
    return install_plugin(name, state_root, force, app_id, app_secret, batch=False)


def run_install_all(state_root: Path, force: bool, app_id: str, app_secret: str) -> int:
    names: List[str] = sorted(SUPPORTED.keys())
    print(f"Installing {len(names)} plugins into {plugin_root(state_root, '<id>').parent} ...")
    print("")
    failed: List[Tuple[str, int]] = []
    for n in names:
        print(f"--- [{n}] ---")
        rc = install_plugin(n, state_root, force, app_id, app_secret, batch=True)
        if rc != 0:
            failed.append((n, rc))
        print("")
    if failed:
        print(f"Completed with {len(failed)} error(s): {failed}")
        return 1
    print("All plugins installed OK.")
    print("Install Python dependencies:  python install.py deps all")
    return 0


def requirements_path_for(name: str) -> Path:
    n = name.strip().lower()
    if n == "all":
        return REQUIREMENTS_DIR / "requirements-all.txt"
    return REQUIREMENTS_DIR / f"{n}.txt"


def run_deps(name: str) -> int:
    n = name.strip().lower()
    if n != "all" and n not in SUPPORTED:
        print(f"Unknown channel: {name}")
        print("Use `list` for supported names, or `all` for aggregated requirements.")
        return 1
    req = requirements_path_for(n)
    if not req.is_file():
        print(f"Missing file: {req}")
        return 1
    print(f"Running: {sys.executable} -m pip install -r {req}")
    cmd = [sys.executable, "-m", "pip", "install", "-r", str(req)]
    return int(subprocess.call(cmd))


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        description="Install Metis gateway plugins and optional Python dependencies",
    )
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("list", help="List supported channel plugins")

    pi = sub.add_parser("install", help="Copy runtime into ~/.metis/gateway-plugins/<id>")
    pi.add_argument(
        "name",
        help="Channel name (see list), or keyword 'all' to install every supported plugin",
    )
    pi.add_argument(
        "--state-root",
        "--project-root",
        dest="state_root",
        default=str(default_state_root()),
        help="State root whose .metis/gateway-plugins directory receives the plugin runtime",
    )
    pi.add_argument("--force", action="store_true", help="Overwrite existing plugin files")
    pi.add_argument("--app-id", default="", help="Optional app id/client id, stored in plugin-config.json")
    pi.add_argument("--app-secret", default="", help="Optional app secret/client secret, stored in plugin-config.json")

    dep = sub.add_parser(
        "deps",
        help="pip install -r requirements/<channel>.txt (single) or requirements-all.txt (all)",
    )
    dep.add_argument(
        "name",
        nargs="?",
        default="all",
        help="Channel name or 'all' (default: install all optional deps)",
    )

    return p


def main() -> int:
    args = build_parser().parse_args()
    if args.cmd == "list":
        return run_list()
    if args.cmd == "install":
        return run_install(
            args.name,
            Path(args.state_root),
            args.force,
            args.app_id.strip(),
            args.app_secret.strip(),
        )
    if args.cmd == "deps":
        return run_deps(args.name)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
