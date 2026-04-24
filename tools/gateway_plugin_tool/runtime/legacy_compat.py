# -*- coding: utf-8 -*-
"""
与参考实现对齐的配置读取约定。

推荐在 plugin-config.json 或 gateway.channelsExtra.<pluginId> 中使用：

{
  "channels": {
    "dingtalk": {
      "enabled": true,
      "clientId": "dingxxxx",
      "clientSecret": "secret",
      "webhookHost": "0.0.0.0",
      "webhookPort": 8890,
      "webhookPath": "/dingtalk/callback"
    }
  }
}

同时兼容 CLI 写入的扁平键：app-id / app-secret（会映射为 clientId / clientSecret）。
后续扩展 wecom、wechat-mp 等，只需在 channels.<id> 下增加同结构字段。
"""

from __future__ import annotations

from typing import Any, Dict, MutableMapping, Optional


def _ensure_dict(d: MutableMapping[str, Any], key: str) -> Dict[str, Any]:
    v = d.get(key)
    if isinstance(v, dict):
        return v
    inner: Dict[str, Any] = {}
    d[key] = inner
    return inner


def get_channel_block(cfg: Dict[str, Any], channel_id: str) -> Dict[str, Any]:
    """返回 channels.<channel_id>，若不存在则创建空 dict（仅用于读取时勿写回污染）。"""
    ch = cfg.get("channels")
    if not isinstance(ch, dict):
        return {}
    block = ch.get(channel_id)
    return block if isinstance(block, dict) else {}


def normalize_legacy_config(cfg: Dict[str, Any], channel_id: str) -> Dict[str, Any]:
    """
    合并扁平别名到兼容的 channels.<channel_id>。
    返回新的 dict（浅拷贝 channels 子树）。
    """
    out = dict(cfg)
    channels = _ensure_dict(out, "channels")
    block: Dict[str, Any] = dict(channels.get(channel_id) or {}) if isinstance(channels.get(channel_id), dict) else {}

    # CLI / 旧模板：app-id, app-secret
    if "clientId" not in block and cfg.get("app-id"):
        block["clientId"] = str(cfg["app-id"])
    if "clientSecret" not in block and cfg.get("app-secret"):
        block["clientSecret"] = str(cfg["app-secret"])
    # 顶层误写的 clientId（无 channels 包裹）
    if "clientId" not in block and cfg.get("clientId"):
        block["clientId"] = str(cfg["clientId"])
    if "clientSecret" not in block and cfg.get("clientSecret"):
        block["clientSecret"] = str(cfg["clientSecret"])

    channels[channel_id] = block
    out["channels"] = channels
    return out


def dingtalk_transport(block: Dict[str, Any]) -> str:
    """
    默认 stream：与参考实现一致，仅需 clientId/clientSecret，无需在钉钉控制台配置回调 URL。
    显式设置 transport/mode 为 webhook/http/callback 时使用 HTTP 入站（需公网 URL）。
    """
    t = str(block.get("transport") or block.get("mode") or "").strip().lower()
    if t in {"http", "callback", "webhook"}:
        return "webhook"
    if t in {"stream", "streaming"}:
        return "stream"
    return "stream"


def dingtalk_webhook_listen(block: Dict[str, Any]) -> tuple[str, int, str]:
    host = str(block.get("webhookHost") or block.get("host") or "127.0.0.1")
    port = int(block.get("webhookPort") or block.get("port") or 8890)
    path = str(block.get("webhookPath") or "/dingtalk/callback")
    if not path.startswith("/"):
        path = "/" + path
    return host, port, path
