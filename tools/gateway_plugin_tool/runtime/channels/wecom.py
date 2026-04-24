# -*- coding: utf-8 -*-
"""
WeCom channel (extension) for gateway command-adapter.

当前仅提供接口骨架（send 未实现）。
"""

from __future__ import annotations

import sys
from typing import Any, Dict

from channels import register_channel


def start_hook(plugin_root: str, cfg: Dict[str, Any], channel_id: str) -> None:
    _ = (plugin_root, cfg, channel_id)


def stop_hook(plugin_root: str, cfg: Dict[str, Any], channel_id: str) -> None:
    _ = (plugin_root, cfg, channel_id)


def op_send_wecom(plugin_root: str, cfg: Dict[str, Any], peer_id: str, text: str, reply_to: str) -> int:
    _ = (plugin_root, cfg, peer_id, reply_to)
    sys.stderr.write("wecom send not implemented yet\n")
    return 1


register_channel("wecom", start_hook, stop_hook)

