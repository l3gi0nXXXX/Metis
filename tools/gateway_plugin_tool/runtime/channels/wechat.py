# -*- coding: utf-8 -*-
"""
WeChat channel (extension) for gateway command-adapter.

当前仅提供接口骨架：避免 adapter.py 的 send 分发找不到模块/函数。
真正接入需自行实现 start_hook/事件侧车 + op_send 逻辑。
"""

from __future__ import annotations

import sys
from typing import Any, Dict

from channels import register_channel


def start_hook(plugin_root: str, cfg: Dict[str, Any], channel_id: str) -> None:
    # noop
    _ = (plugin_root, cfg, channel_id)


def stop_hook(plugin_root: str, cfg: Dict[str, Any], channel_id: str) -> None:
    _ = (plugin_root, cfg, channel_id)


def op_send_wechat(plugin_root: str, cfg: Dict[str, Any], peer_id: str, text: str, reply_to: str) -> int:
    _ = (plugin_root, cfg, reply_to)
    sys.stderr.write(f"wechat send not implemented yet (peer_id={peer_id}, text_len={len(text or '')})\n")
    return 1


register_channel("wechat", start_hook, stop_hook)

