#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Metis 网关 command-adapter 运行时（与参考插件形态对齐）。

- 配置：优先使用兼容的 `channels.<channelId>.*`，并兼容 CLI 扁平键 `app-id` / `app-secret`。
- 扩展 IM：在 `channels/<id>.py` 中 `register_channel(id, start_hook, stop_hook)`，并由 `install` 整包复制本目录。
- 钉钉：默认 Stream 侧车 `python adapter.py stream ...`（需 `pip install dingtalk-stream`）；可选 `webhook` 子命令。均由 `start`/`stop` 拉起与结束。
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from pathlib import Path
from typing import Any, Dict, List

# 已安装插件根目录（含兼容辅助模块、channels、本文件）
_PLUGIN_ROOT_DIR = os.path.dirname(os.path.abspath(__file__))
if _PLUGIN_ROOT_DIR not in sys.path:
    sys.path.insert(0, _PLUGIN_ROOT_DIR)

import channels  # noqa: E402
from legacy_compat import normalize_legacy_config  # noqa: E402


def ensure_data_dir(plugin_root: Path) -> Path:
    d = plugin_root / ".runtime"
    d.mkdir(parents=True, exist_ok=True)
    return d


def queue_file(plugin_root: Path) -> Path:
    return ensure_data_dir(plugin_root) / "inbox.jsonl"


def runtime_config_path(plugin_root: Path) -> Path:
    return ensure_data_dir(plugin_root) / "runtime-config.json"


def load_config(config_json: str) -> Dict[str, Any]:
    if not config_json:
        return {}
    try:
        return json.loads(config_json)
    except Exception:
        return {}


def append_jsonl(path: Path, obj: Dict[str, Any]) -> None:
    with path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(obj, ensure_ascii=False) + "\n")


def pop_all_jsonl(path: Path) -> List[Dict[str, Any]]:
    if not path.exists():
        return []
    raw = path.read_text(encoding="utf-8")
    path.write_text("", encoding="utf-8")
    out: List[Dict[str, Any]] = []
    for line in raw.splitlines():
        t = line.strip()
        if not t:
            continue
        try:
            out.append(json.loads(t))
        except Exception:
            continue
    return out


def log(plugin_root: Path, text: str) -> None:
    p = ensure_data_dir(plugin_root) / "adapter.log"
    with p.open("a", encoding="utf-8") as f:
        f.write(f"[{int(time.time())}] {text}\n")


def op_start(args: argparse.Namespace, cfg: Dict[str, Any]) -> int:
    channels.import_builtin_channels()
    root = Path(args.plugin_root)
    cfg = normalize_legacy_config(cfg, args.channel_id)
    cfg["_pluginId"] = args.plugin_id
    ensure_data_dir(root)
    runtime_config_path(root).write_text(json.dumps(cfg, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    log(
        root,
        f"start plugin={args.plugin_id} channel={args.channel_id} cfg_keys={list(cfg.keys())}",
    )
    try:
        channels.channel_start(str(root.resolve()), cfg, args.channel_id)
    except Exception as e:
        log(root, f"channel_start error: {e!r}")
    return 0


def op_stop(args: argparse.Namespace, cfg: Dict[str, Any]) -> int:
    channels.import_builtin_channels()
    root = Path(args.plugin_root)
    cfg = normalize_legacy_config(cfg, args.channel_id)
    cfg["_pluginId"] = args.plugin_id
    try:
        channels.channel_stop(str(root.resolve()), cfg, args.channel_id)
    except Exception as e:
        log(root, f"channel_stop error: {e!r}")
    log(root, f"stop plugin={args.plugin_id}")
    return 0


def op_pull(args: argparse.Namespace, cfg: Dict[str, Any]) -> int:
    root = Path(args.plugin_root)
    qf = queue_file(root)
    items = pop_all_jsonl(qf)

    fake = os.getenv("GATEWAY_PLUGIN_FAKE_PULL", "").strip().lower()
    if not items and fake in {"1", "true", "yes"}:
        items = [
            {
                "messageId": f"{args.channel_id}-{int(time.time() * 1000)}",
                "peerId": cfg.get("testPeerId", f"{args.channel_id}-demo-peer"),
                "senderId": cfg.get("testSenderId", f"{args.channel_id}-demo-user"),
                "chatType": "direct",
                "text": cfg.get("testText", f"你好，来自 {args.channel_id} 插件模板"),
                "mentioned": True,
            }
        ]

    # Windows 下 print() 可能对管道写出 CRLF，仓颉侧按行 JSON 解析会因行尾 \r 失败；强制仅 \n
    for item in items:
        line = json.dumps(item, ensure_ascii=False) + "\n"
        sys.stdout.buffer.write(line.encode("utf-8"))
    try:
        sys.stdout.buffer.flush()
    except Exception:
        pass
    return 0


def op_send(args: argparse.Namespace, cfg: Dict[str, Any]) -> int:
    root = Path(args.plugin_root)
    channel_id = args.channel_id.strip().lower()
    peer_id = args.peer_id
    text = args.text
    reply_to = args.reply_to

    # channel_id 可能包含 '-'，python module/function 名用 '_' 规避非法字符
    module_name = channel_id.replace("-", "_")
    fn_name = f"op_send_{module_name}"

    try:
        # 针对 dingtalk 仍保留显式分发（兼容旧实现与更清晰日志）
        if channel_id == "dingtalk":
            from channels.dingtalk import op_send_dingtalk

            ec = op_send_dingtalk(str(root.resolve()), cfg, peer_id, text, reply_to)
            log(
                root,
                f"send channel=dingtalk peer={peer_id} reply_to={reply_to} ec={ec}",
            )
            return ec

        from importlib import import_module

        mod = import_module(f"channels.{module_name}")
        fn = getattr(mod, fn_name, None)
        if fn is None:
            log(root, f"send channel={channel_id} not found fn={fn_name}")
            return 1
        ec = fn(str(root.resolve()), cfg, peer_id, text, reply_to)
        log(root, f"send channel={channel_id} peer={peer_id} reply_to={reply_to} ec={ec}")
        return ec
    except Exception as e:
        log(root, f"send channel={channel_id} dispatch error: {e!r}")
        return 1


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description="Metis gateway command adapter (legacy-compatible config)")
    p.add_argument("op", choices=["start", "pull", "send", "stop"])
    p.add_argument("--plugin-id", required=True)
    p.add_argument("--channel-id", required=True)
    p.add_argument("--plugin-root", required=True)
    p.add_argument("--config-json", default="")
    p.add_argument("--peer-id", default="")
    p.add_argument("--text", default="")
    p.add_argument("--reply-to", default="")
    return p


def main() -> int:
    argv = sys.argv[1:]
    if argv and argv[0] == "webhook":
        wp = argparse.ArgumentParser(prog="adapter webhook")
        wp.add_argument("--plugin-root", required=True)
        wp.add_argument("--plugin-id", required=True)
        wargs = wp.parse_args(argv[1:])
        from channels.dingtalk import cmd_webhook

        return cmd_webhook(wargs.plugin_root, wargs.plugin_id)

    if argv and argv[0] == "stream":
        sp = argparse.ArgumentParser(prog="adapter stream")
        sp.add_argument("--plugin-root", required=True)
        sp.add_argument("--plugin-id", required=True)
        sargs = sp.parse_args(argv[1:])
        from channels.dingtalk import cmd_stream

        return cmd_stream(sargs.plugin_root, sargs.plugin_id)

    if argv and argv[0] == "feishu_long_connect":
        sp = argparse.ArgumentParser(prog="adapter feishu_long_connect")
        sp.add_argument("--plugin-root", required=True)
        sp.add_argument("--plugin-id", required=True)
        sargs = sp.parse_args(argv[1:])
        from channels.feishu import cmd_long_connect_feishu

        return cmd_long_connect_feishu(sargs.plugin_root, sargs.plugin_id)

    if argv and argv[0] == "qq_official_ws":
        sp = argparse.ArgumentParser(prog="adapter qq_official_ws")
        sp.add_argument("--plugin-root", required=True)
        sp.add_argument("--plugin-id", required=True)
        sargs = sp.parse_args(argv[1:])
        from channels.qq import cmd_qq_official_ws

        return cmd_qq_official_ws(sargs.plugin_root, sargs.plugin_id)

    args = build_parser().parse_args()
    cfg = load_config(args.config_json)
    if args.op == "start":
        return op_start(args, cfg)
    if args.op == "pull":
        return op_pull(args, cfg)
    if args.op == "send":
        return op_send(args, cfg)
    if args.op == "stop":
        return op_stop(args, cfg)
    return 1


if __name__ == "__main__":
    sys.exit(main())
