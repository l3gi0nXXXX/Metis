# -*- coding: utf-8 -*-
"""
QQ channel (extension) for gateway command-adapter.

当前实现范围：
- 入站：官方机器人 WebSocket（official_ws / official gateway op=0 dispatch）-> 写入 inbox.jsonl
- 出站：优先按官方接口发送（当配置了 official_* 模板/Token API），否则 fallback 到 OneBot v11 HTTP API

说明：
- 本实现目标是满足「网关 B 方案：内置 disabled 时，走插件侧长连接收发」。
- peerId 协议对齐内置 QQ 适配器：
  - 私聊：`user:<user_openid>`
  - 群聊：`group:<group_openid>`
"""

from __future__ import annotations

import json
import os
import sys
import time
from typing import Any, Dict, Optional, Tuple

import requests

from legacy_compat import get_channel_block, normalize_legacy_config

from channels import register_channel


def _runtime_dir(plugin_root: str) -> str:
    d = os.path.join(plugin_root, ".runtime")
    os.makedirs(d, exist_ok=True)
    return d


def _adapter_log_path(plugin_root: str) -> str:
    return os.path.join(_runtime_dir(plugin_root), "adapter.log")


def _log(plugin_root: str, text: str) -> None:
    try:
        with open(_adapter_log_path(plugin_root), "a", encoding="utf-8") as f:
            f.write(f"[{int(time.time())}] {text}\n")
    except OSError:
        pass


def _inbox_path(plugin_root: str) -> str:
    return os.path.join(_runtime_dir(plugin_root), "inbox.jsonl")


def _append_inbox(plugin_root: str, line_obj: Dict[str, Any]) -> None:
    with open(_inbox_path(plugin_root), "a", encoding="utf-8") as f:
        f.write(json.dumps(line_obj, ensure_ascii=False) + "\n")


def _get_channel_block(cfg: Dict[str, Any], channel_id: str) -> Dict[str, Any]:
    ncfg = normalize_legacy_config(dict(cfg), channel_id)
    return get_channel_block(ncfg, channel_id)


def _pid_path(plugin_root: str) -> str:
    return os.path.join(_runtime_dir(plugin_root), "qq-ws.pid")


def _kill_pid_file(pid_file: str) -> None:
    try:
        if not os.path.isfile(pid_file):
            return
        with open(pid_file, encoding="utf-8") as f:
            s = (f.read() or "").strip()
        if not s:
            return
        pid = int(s)
        if pid <= 0:
            return
        try:
            import signal

            os.kill(pid, signal.SIGTERM)
        except Exception:
            pass
    except Exception:
        pass
    try:
        os.remove(pid_file)
    except OSError:
        pass


def _kill_all(plugin_root: str) -> None:
    _kill_pid_file(_pid_path(plugin_root))


def _first(block: Dict[str, Any], keys: Tuple[str, ...], default: str = "") -> str:
    for k in keys:
        if k in block and block[k] is not None:
            v = block.get(k)
            if isinstance(v, str):
                if v.strip():
                    return v.strip()
            else:
                # allow numeric -> str
                sv = str(v).strip()
                if sv:
                    return sv
    return default

def _parse_peer_id(peer_id: str) -> Tuple[bool, str]:
    """
    gateway 约定（对齐内置 QQ 适配器）：
    - 私聊：peerId = "user:<user_id>"
    - 群聊：peerId = "group:<group_id>"
    """
    pid = str(peer_id or "").strip()
    if pid.startswith("group:"):
        return True, pid[len("group:") :].strip()
    if pid.startswith("user:"):
        return False, pid[len("user:") :].strip()
    # 兼容无前缀：当作私聊处理
    return False, pid


def _get_onebot_send_base(block: Dict[str, Any]) -> Tuple[str, str]:
    base_url = (
        str(block.get("onebotApiBaseUrl") or block.get("onebot_api_base_url") or "").strip()
        or str(block.get("onebotApiBaseURL") or "").strip()
        or "http://127.0.0.1:5700"
    )
    access_token = str(block.get("accessToken") or block.get("access-token") or block.get("qqAccessToken") or "").strip()
    return base_url, access_token


def _get_official_send_conf(block: Dict[str, Any]) -> Dict[str, str]:
    """
    取出 official 发送所需字段（尽量兼容命名差异）。
    """
    return {
        "officialTokenUrl": _first(block, ("officialTokenUrl", "officialTokenURL", "official_token_url", "officialToken")),
        "officialGatewayUrl": _first(block, ("officialGatewayUrl", "official_gateway_url")),
        "officialWebsocketUrl": _first(block, ("officialWebsocketUrl", "official_websocket_url")),
        "officialAuthScheme": _first(block, ("officialAuthScheme", "official_auth_scheme", "authScheme", "QQBot"), "QQBot"),
        "officialIntents": _first(block, ("officialIntents", "official_intents"), "33559041"),
        "appId": _first(block, ("appId", "clientId", "app-id")),
        "appSecret": _first(block, ("appSecret", "clientSecret", "app-secret", "client_secret")),
        "officialSendPrivateUrlTemplate": _first(
            block,
            ("officialSendPrivateUrlTemplate", "officialSendPrivateUrl", "official_send_private_url_template"),
        ),
        "officialSendGroupUrlTemplate": _first(
            block,
            ("officialSendGroupUrlTemplate", "officialSendGroupUrl", "official_send_group_url_template"),
        ),
        "sendApiMode": _first(block, ("sendApiMode", "send_api_mode"), "split"),
        "dedupWindowSize": _first(block, ("dedupWindowSize", "dedup_window_size"), "2000"),
        "botQQ": _first(block, ("botQQ", "botQq", "bot_qq"), ""),
    }


def _ensure_qq_official_defaults(conf: Dict[str, str]) -> Dict[str, str]:
    """
    若用户只填写 appId/appSecret，官方 WS/Gateway/发送模板未配置时自动补齐。
    这样插件侧不会复用内置 `gateway.qq`，但仍能开箱启动。
    """
    conf = dict(conf)
    if not conf.get("officialTokenUrl"):
        conf["officialTokenUrl"] = "https://bots.qq.com/app/getAppAccessToken"
    # 二选一：我们同时给全，避免缺一项导致启动失败
    if not conf.get("officialGatewayUrl"):
        conf["officialGatewayUrl"] = "https://api.sgroup.qq.com/gateway"
    if not conf.get("officialWebsocketUrl"):
        conf["officialWebsocketUrl"] = "wss://api.sgroup.qq.com/websocket/"
    if not conf.get("officialAuthScheme"):
        conf["officialAuthScheme"] = "QQBot"
    if not conf.get("officialIntents"):
        conf["officialIntents"] = "33559041"
    if not conf.get("officialSendPrivateUrlTemplate"):
        conf["officialSendPrivateUrlTemplate"] = "https://api.sgroup.qq.com/v2/users/{peer_id}/messages"
    if not conf.get("officialSendGroupUrlTemplate"):
        conf["officialSendGroupUrlTemplate"] = "https://api.sgroup.qq.com/v2/groups/{peer_id}/messages"
    return conf


def _get_official_access_token(conf: Dict[str, str]) -> Tuple[bool, str]:
    token_url = conf.get("officialTokenUrl", "").strip()
    app_id = conf.get("appId", "").strip()
    app_secret = conf.get("appSecret", "").strip()
    if not token_url or not app_id or not app_secret:
        return False, "missing officialTokenUrl/appId/appSecret"
    header = {"Content-Type": "application/json; charset=utf-8"}
    body = {"appId": app_id, "clientSecret": app_secret}
    try:
        resp = requests.post(token_url, headers=header, json=body, timeout=30)
        resp.raise_for_status()
        jo = resp.json() if resp.content else {}
    except Exception as e:
        return False, f"official token request failed: {e!r}"
    token = str(jo.get("access_token") or "").strip()
    if not token:
        return False, f"official token missing access_token: {jo!r}"
    return True, token


def _parse_peer_id_for_send(peer_id: str) -> Tuple[bool, str]:
    pid = str(peer_id or "").strip()
    if pid.startswith("group:"):
        return True, pid[len("group:") :].strip()
    if pid.startswith("user:"):
        return False, pid[len("user:") :].strip()
    return False, pid


def start_hook(plugin_root: str, cfg: Dict[str, Any], channel_id: str) -> None:
    """
    启动 QQ official_ws 长连接侧车，把收到的消息写入 inbox.jsonl。
    """
    _ = cfg
    _kill_all(plugin_root)

    subcmd = "qq_official_ws"
    plugin_id = str(cfg.get("_pluginId") or channel_id)

    creationflags = 0
    if sys.platform == "win32":
        import subprocess as _sp

        creationflags = getattr(_sp, "DETACHED_PROCESS", 0)
        creationflags |= getattr(_sp, "CREATE_NO_WINDOW", 0)

    script = os.path.join(plugin_root, "adapter.py")
    if not os.path.isfile(script):
        _log(plugin_root, "[qq] adapter.py missing under plugin root; cannot start sidecar")
        return

    args = [sys.executable, "-u", script, subcmd, "--plugin-root", plugin_root, "--plugin-id", plugin_id]
    import subprocess as _sp

    try:
        log_fp = open(_adapter_log_path(plugin_root), "a", encoding="utf-8")
    except OSError:
        log_fp = None

    kwargs: Dict[str, Any] = {
        "stdout": log_fp if log_fp is not None else _sp.DEVNULL,
        "stderr": log_fp if log_fp is not None else _sp.DEVNULL,
        "stdin": _sp.DEVNULL,
        "close_fds": True,
    }
    if sys.platform == "win32":
        kwargs["creationflags"] = creationflags
    else:
        kwargs["start_new_session"] = True

    proc = _sp.Popen(args, **kwargs)
    with open(_pid_path(plugin_root), "w", encoding="utf-8") as f:
        f.write(str(proc.pid))


def stop_hook(plugin_root: str, cfg: Dict[str, Any], channel_id: str) -> None:
    _ = (cfg, channel_id)
    _kill_all(plugin_root)


def op_send_qq(plugin_root: str, cfg: Dict[str, Any], peer_id: str, text: str, reply_to: str) -> int:
    pid = str(peer_id or "").strip()
    text = str(text or "").strip()
    reply_to = str(reply_to or "").strip()
    if not pid or not text:
        sys.stderr.write("qq send: empty peer_id or text\n")
        return 1

    block = _get_channel_block(cfg, "qq")
    mode = str(block.get("mode") or block.get("receiveMode") or block.get("sendMode") or "").strip().lower()
    # 插件侧运行时可能只包含 appId/appSecret（clientId/clientSecret），缺省视为官方接口模式。
    if not mode:
        mode = "official_ws"

    # 官方模式：尽量走 official 接口（如果配置了模板/Token API）
    if mode in {"official_ws", "official_webhook"}:
        conf = _get_official_send_conf(block)
        # 允许用户只配置 appId/appSecret，缺失官方 ws/gateway/发送模板时自动补齐。
        conf = _ensure_qq_official_defaults(conf)
        private_tpl = conf.get("officialSendPrivateUrlTemplate", "").strip()
        group_tpl = conf.get("officialSendGroupUrlTemplate", "").strip()
        if conf.get("officialTokenUrl") and (private_tpl or group_tpl):
            is_group, pure_id = _parse_peer_id_for_send(pid)
            return _send_official(
                plugin_root=plugin_root,
                conf=conf,
                is_group=is_group,
                pure_id=pure_id,
                text=text,
                reply_to=reply_to,
            )

    # fallback：OneBot HTTP API
    base_url, access_token = _get_onebot_send_base(block)
    is_group, pure_id = _parse_peer_id(pid)
    if not pure_id:
        sys.stderr.write("qq send: pure_id is empty (peerId parse failed)\n")
        return 1

    url = base_url.rstrip("/") + "/send_msg"
    headers = {"Content-Type": "application/json; charset=utf-8"}
    if access_token:
        headers["Authorization"] = f"Bearer {access_token}"

    body: Dict[str, Any] = {
        "message_type": "group" if is_group else "private",
        ("group_id" if is_group else "user_id"): pure_id,
        "message": text,
        "auto_escape": False,
    }

    _log(
        plugin_root,
        f"[qq] send onebot url={url} to={'group' if is_group else 'private'} id={pure_id[:24]} text_len={len(text)}",
    )
    try:
        resp = requests.post(url, headers=headers, json=body, timeout=30)
        resp.raise_for_status()
        data = resp.json() if resp.content else {}
    except Exception as e:
        _log(plugin_root, f"[qq] send request error: {e!r}")
        sys.stderr.write(f"qq send request error: {e!r}\n")
        return 1

    status = data.get("status")
    retcode = data.get("retcode")
    if status == "ok" and retcode == 0:
        _log(plugin_root, "[qq] send ok")
        return 0

    msg = data.get("msg") or str(data)
    _log(plugin_root, f"[qq] send failed: status={status} retcode={retcode} msg={msg}")
    sys.stderr.write(f"qq send failed: status={status} retcode={retcode} msg={msg}\n")
    return 1


def _send_official(
    plugin_root: str,
    conf: Dict[str, str],
    is_group: bool,
    pure_id: str,
    text: str,
    reply_to: str,
) -> int:
    if not pure_id:
        return 1
    token_ok, token_or_err = _get_official_access_token(conf)
    if not token_ok:
        sys.stderr.write(f"qq official send token error: {token_or_err}\n")
        _log(plugin_root, f"[qq] official send token error: {token_or_err}")
        return 1

    auth_scheme = conf.get("officialAuthScheme", "QQBot")
    app_id = conf.get("appId", "")

    tpl = conf.get("officialSendGroupUrlTemplate") if is_group else conf.get("officialSendPrivateUrlTemplate")
    if not tpl:
        sys.stderr.write("qq official send: missing url template\n")
        return 1
    url = str(tpl).replace("{peer_id}", pure_id)

    header: Dict[str, str] = {
        "Content-Type": "application/json; charset=utf-8",
        "Authorization": f"{auth_scheme} {token_or_err}",
    }
    if app_id:
        header["X-Union-Appid"] = app_id

    body: Dict[str, Any] = {"content": text}
    if reply_to:
        body["msg_id"] = reply_to

    _log(plugin_root, f"[qq] send official url={url} is_group={is_group}")
    try:
        resp = requests.post(url, headers=header, json=body, timeout=30)
        resp.raise_for_status()
        data = resp.json() if resp.content else {}
    except Exception as e:
        _log(plugin_root, f"[qq] official send http error: {e!r}")
        sys.stderr.write(f"qq official send http error: {e!r}\n")
        return 1

    ok_id = str(data.get("id") or "").strip()
    if ok_id:
        _log(plugin_root, "[qq] official send ok")
        return 0
    code = data.get("code")
    if code == 0:
        _log(plugin_root, "[qq] official send ok (code==0)")
        return 0
    sys.stderr.write(f"qq official send failed: {data!r}\n")
    _log(plugin_root, f"[qq] official send failed: {data!r}")
    return 1


def _resolve_official_sender_id(data: Dict[str, Any]) -> str:
    user_openid = str(data.get("user_openid") or "").strip()
    if user_openid:
        return user_openid
    author_id = str(data.get("author_id") or "").strip()
    if author_id:
        return author_id
    author = data.get("author") or {}
    if isinstance(author, dict):
        return str(author.get("id") or "").strip()
    return ""


def _map_official_event_to_inbound(event_type: str, data: Dict[str, Any], bot_qq: str) -> Optional[Dict[str, Any]]:
    event_type = str(event_type or "").strip()
    message_id = str(data.get("id") or "").strip()
    text = str(data.get("content") or "").strip()
    if not text:
        return None
    sender_id = _resolve_official_sender_id(data)
    if not sender_id:
        return None

    mentioned = False
    chat_type = "direct"
    peer_id = ""

    if event_type in {"GROUP_AT_MESSAGE_CREATE", "GROUP_MESSAGE_CREATE", "AT_MESSAGE_CREATE"}:
        group_openid = str(data.get("group_openid") or "").strip()
        if not group_openid:
            return None
        chat_type = "group"
        peer_id = f"group:{group_openid}"
        if event_type in {"GROUP_AT_MESSAGE_CREATE", "AT_MESSAGE_CREATE"}:
            mentioned = True
        else:
            # 兼容：group 普通消息按文本包含 @ 判断（与内置一致）
            mentioned = "@" in text
        return {
            "messageId": message_id,
            "peerId": peer_id,
            "senderId": sender_id,
            "chatType": chat_type,
            "text": text,
            "mentioned": bool(mentioned),
        }

    if event_type in {"C2C_MESSAGE_CREATE", "DIRECT_MESSAGE_CREATE", "MESSAGE_CREATE"}:
        chat_type = "direct"
        peer_openid = str(data.get("user_openid") or "").strip()
        real_peer = peer_openid if peer_openid else sender_id
        if not real_peer:
            return None
        peer_id = f"user:{real_peer}"
        return {
            "messageId": message_id,
            "peerId": peer_id,
            "senderId": sender_id,
            "chatType": chat_type,
            "text": text,
            "mentioned": True,
        }

    # 其他事件略过
    return None


def cmd_qq_official_ws(plugin_root: str, plugin_id: str) -> int:
    """
    插件侧 QQ official_ws 长连接接收入口（由 adapter.py 子命令启动）。
    """
    cfg_path = os.path.join(_runtime_dir(plugin_root), "runtime-config.json")
    if not os.path.isfile(cfg_path):
        sys.stderr.write(f"qq_official_ws missing {cfg_path}\n")
        return 1
    with open(cfg_path, encoding="utf-8") as f:
        cfg = json.load(f)
    cfg["_pluginId"] = plugin_id

    block = _get_channel_block(cfg, "qq")
    conf = _get_official_send_conf(block)
    conf = _ensure_qq_official_defaults(conf)

    official_auth_scheme = conf.get("officialAuthScheme", "QQBot")
    official_intents = conf.get("officialIntents", "33559041")
    try:
        intents_i = int(official_intents)
    except Exception:
        intents_i = 33559041

    official_ws_url = conf.get("officialWebsocketUrl", "").strip()
    official_gateway_url = conf.get("officialGatewayUrl", "").strip()
    official_token_url = conf.get("officialTokenUrl", "").strip()
    if not official_ws_url and not official_gateway_url:
        sys.stderr.write("qq_official_ws: missing officialWebsocketUrl or officialGatewayUrl\n")
        return 1
    if not official_token_url:
        sys.stderr.write("qq_official_ws: missing officialTokenUrl\n")
        return 1

    dedup_window = 2000
    try:
        dedup_window = int(conf.get("dedupWindowSize", "2000"))
    except Exception:
        dedup_window = 2000
    recent_ids: list[str] = []
    bot_qq = conf.get("botQQ", "")

    try:
        import ssl
        from websocket import create_connection
        from websocket import WebSocketTimeoutException
    except ImportError:
        sys.stderr.write("qq_official_ws: missing websocket-client. Please `pip install -r tools/gateway_plugin_tool/requirements/qq.txt`\n")
        return 1

    def resolve_gateway_ws_url(access_token: str) -> str:
        nonlocal official_ws_url
        if official_ws_url.startswith("ws://") or official_ws_url.startswith("wss://"):
            return official_ws_url
        if not official_gateway_url:
            return ""
        headers = {"Authorization": f"{official_auth_scheme} {access_token}"}
        app_id = conf.get("appId", "").strip()
        if app_id:
            headers["X-Union-Appid"] = app_id
        try:
            resp = requests.post(official_gateway_url, headers=headers, json={}, timeout=30)
            resp.raise_for_status()
            jo = resp.json() if resp.content else {}
        except Exception:
            return ""
        return str(jo.get("url") or "").strip()

    while True:
        try:
            token_ok, access_token_or_err = _get_official_access_token(conf)
            if not token_ok:
                raise Exception(access_token_or_err)
            ws_url = resolve_gateway_ws_url(access_token_or_err) if not official_ws_url else official_ws_url
            if not ws_url:
                raise Exception("official gateway ws url is empty")

            _log(plugin_root, f"[qq] official_ws connecting: {ws_url}")
            sslopt = {"cert_reqs": ssl.CERT_NONE}
            # 使用较短 recv 超时，确保可以按时发送 Heartbeat；
            # 否则 ws.recv() 会阻塞到超时才返回，导致心跳无法及时发出并被断开。
            ws = create_connection(ws_url, sslopt=sslopt, timeout=5)

            official_seq = 0
            heartbeat_interval_ms = 30000
            heartbeat_started = False
            next_heartbeat = 0.0

            while True:
                now_ms = time.time() * 1000
                try:
                    raw = ws.recv()
                except WebSocketTimeoutException:
                    # 定期发送心跳（如果到点了），避免服务器在无业务消息时认为连接失活
                    if heartbeat_started and now_ms >= next_heartbeat:
                        hb = {"op": 1, "d": int(official_seq)}
                        try:
                            ws.send(json.dumps(hb, ensure_ascii=False))
                        except Exception:
                            break
                        next_heartbeat = now_ms + heartbeat_interval_ms
                    continue
                if raw is None:
                    break
                if isinstance(raw, bytes):
                    raw = raw.decode("utf-8", errors="ignore")
                try:
                    jo = json.loads(raw)
                except Exception:
                    continue
                op = jo.get("op")
                d = jo.get("d") or {}
                if "s" in jo and jo.get("s") is not None:
                    try:
                        official_seq = int(float(jo.get("s")))
                    except Exception:
                        pass

                if op == 10:  # Hello
                    if isinstance(d, dict):
                        interval = d.get("heartbeat_interval")
                        if interval:
                            try:
                                heartbeat_interval_ms = int(interval)
                            except Exception:
                                pass
                    # IDENTIFY
                    identify = {
                        "op": 2,
                        "d": {
                            "token": f"{official_auth_scheme} {access_token_or_err}",
                            "intents": intents_i,
                            "shard": [0, 1],
                            "properties": {"$os": "windows", "$sdk": "magic-cli", "$device": "magic-cli"},
                        },
                    }
                    ws.send(json.dumps(identify, ensure_ascii=False))
                    if not heartbeat_started:
                        heartbeat_started = True
                        next_heartbeat = time.time() * 1000 + heartbeat_interval_ms
                    continue

                if op == 0:  # Dispatch
                    event_type = jo.get("t") or ""
                    if not isinstance(d, dict):
                        continue
                    inbound = _map_official_event_to_inbound(event_type, d, bot_qq)
                    if not inbound:
                        continue
                    message_id = str(inbound.get("messageId") or "").strip()
                    if message_id:
                        if message_id in recent_ids:
                            continue
                    _append_inbox(plugin_root, inbound)
                    if message_id:
                        recent_ids.append(message_id)
                        if len(recent_ids) > dedup_window:
                            recent_ids = recent_ids[-dedup_window:]
                    continue

                if op == 7:  # Reconnect
                    break

                # heartbeat tick
                if heartbeat_started:
                    now_ms = time.time() * 1000
                    if now_ms >= next_heartbeat:
                        hb = {"op": 1, "d": int(official_seq)}
                        try:
                            ws.send(json.dumps(hb, ensure_ascii=False))
                        except Exception:
                            break
                        next_heartbeat = now_ms + heartbeat_interval_ms

        except Exception as e:
            _log(plugin_root, f"[qq] official_ws loop error: {e!r}")
            try:
                _kill_all(plugin_root)
            except Exception:
                pass
            time.sleep(3)

    return 0


register_channel("qq", start_hook, stop_hook)
