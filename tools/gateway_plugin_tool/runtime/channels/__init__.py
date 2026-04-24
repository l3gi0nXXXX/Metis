# -*- coding: utf-8 -*-
"""按 channel-id 分发的 IM 适配实现；与兼容的 channels.<id> 配置一一对应。"""

from __future__ import annotations

from typing import Any, Callable, Dict, Optional

# channel_id -> op_start hook (plugin_root, cfg, channel_id) -> None
_START_HOOKS: Dict[str, Callable[[str, Dict[str, Any], str], None]] = {}
_STOP_HOOKS: Dict[str, Callable[[str, Dict[str, Any], str], None]] = {}


def register_channel(channel_id: str, start_hook: Callable[..., None], stop_hook: Optional[Callable[..., None]] = None) -> None:
    _START_HOOKS[channel_id] = start_hook
    if stop_hook:
        _STOP_HOOKS[channel_id] = stop_hook


def channel_start(plugin_root: str, cfg: Dict[str, Any], channel_id: str) -> None:
    h = _START_HOOKS.get(channel_id)
    if h:
        h(plugin_root, cfg, channel_id)


def channel_stop(plugin_root: str, cfg: Dict[str, Any], channel_id: str) -> None:
    h = _STOP_HOOKS.get(channel_id)
    if h:
        h(plugin_root, cfg, channel_id)


def import_builtin_channels() -> None:
    """注册内置渠道（钉钉等）。扩展新 IM：在此增加 import 或动态发现。"""
    try:
        from . import dingtalk  # noqa: F401
    except ImportError:
        pass
    # 可选渠道：如果用户安装/启用相应扩展插件，这里也允许导入其脚本以注册 start/stop hooks
    # （send 分发在 adapter.py 内部按需 import，故不影响发送）。
    for _name in ("feishu", "qq", "wechat", "wecom", "wechat_mp"):
        try:
            __import__(f"{__name__}.{_name}")
        except ImportError:
            pass
