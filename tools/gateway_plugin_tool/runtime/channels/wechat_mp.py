# -*- coding: utf-8 -*-
"""
WeChat MP channel (extension) for gateway command-adapter.

注意：模块文件名用 `wechat_mp.py`，以便 python import 通过。
在网关插件里 channelId 仍为 `wechat-mp`，adapter.py 会把 '-' 替换成 '_' 后调用对应函数：
- op_send_wechat_mp
"""

from __future__ import annotations

import sys
from typing import Any, Dict

from channels import register_channel


def start_hook(plugin_root: str, cfg: Dict[str, Any], channel_id: str) -> None:
    _ = (plugin_root, cfg, channel_id)


def stop_hook(plugin_root: str, cfg: Dict[str, Any], channel_id: str) -> None:
    _ = (plugin_root, cfg, channel_id)


def op_send_wechat_mp(plugin_root: str, cfg: Dict[str, Any], peer_id: str, text: str, reply_to: str) -> int:
    _ = (plugin_root, cfg, reply_to)
    sys.stderr.write(f"wechat-mp send not implemented yet (peer_id={peer_id})\n")
    return 1


register_channel("wechat-mp", start_hook, stop_hook)

