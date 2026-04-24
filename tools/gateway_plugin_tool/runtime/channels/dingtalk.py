# -*- coding: utf-8 -*-
"""
钉钉：配置键与参考实现对齐（channels.dingtalk.*）。

默认 **Stream 模式**（dingtalk-stream SDK）：出站长连接收消息，无需在钉钉开放平台配置 HTTP 回调 URL，
只需 clientId / clientSecret，并在本机安装 `pip install dingtalk-stream`。

可选 **Webhook**：设置 `"transport": "webhook"`，由侧车 HTTP 服务接收 POST（需配置公网回调 URL）。
"""

from __future__ import annotations

import json
import os
import platform
import signal
import subprocess
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any, Dict, List, Optional, Tuple
from urllib.parse import parse_qs, urlparse

import requests

from legacy_compat import dingtalk_transport, dingtalk_webhook_listen, get_channel_block, normalize_legacy_config


def _runtime_dir(plugin_root: str) -> str:
    d = os.path.join(plugin_root, ".runtime")
    os.makedirs(d, exist_ok=True)
    return d


def _webhook_pid_path(plugin_root: str) -> str:
    return os.path.join(_runtime_dir(plugin_root), "dingtalk-webhook.pid")


def _stream_pid_path(plugin_root: str) -> str:
    return os.path.join(_runtime_dir(plugin_root), "dingtalk-stream.pid")


def _log_path(plugin_root: str) -> str:
    return os.path.join(_runtime_dir(plugin_root), "dingtalk.log")


def _append_inbox(plugin_root: str, line_obj: Dict[str, Any]) -> None:
    inbox = os.path.join(_runtime_dir(plugin_root), "inbox.jsonl")
    with open(inbox, "a", encoding="utf-8") as f:
        f.write(json.dumps(line_obj, ensure_ascii=False) + "\n")


def _reply_context_path(plugin_root: str) -> str:
    return os.path.join(_runtime_dir(plugin_root), "dingtalk_reply_context.json")


def _load_reply_context(plugin_root: str) -> Dict[str, Any]:
    p = _reply_context_path(plugin_root)
    if not os.path.isfile(p):
        return {}
    try:
        with open(p, encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def _save_reply_context(plugin_root: str, ctx: Dict[str, Any]) -> None:
    _runtime_dir(plugin_root)
    p = _reply_context_path(plugin_root)
    with open(p, "w", encoding="utf-8") as f:
        json.dump(ctx, f, ensure_ascii=False, indent=2)


def _persist_stream_reply_context(plugin_root: str, incoming: Any, peer_id: str) -> None:
    """保存 Stream 回调里的 sessionWebhook，供网关异步 send 时回复同一会话。"""
    sw = getattr(incoming, "session_webhook", None)
    if not sw:
        return
    exp = getattr(incoming, "session_webhook_expired_time", None) or 0
    try:
        exp_i = int(exp)
    except (TypeError, ValueError):
        exp_i = 0
    staff = str(getattr(incoming, "sender_staff_id", None) or getattr(incoming, "sender_id", None) or "")
    ct = getattr(incoming, "conversation_type", None)
    chat_type = "group" if ct is not None and str(ct) != "1" else "direct"
    ctx = _load_reply_context(plugin_root)
    ctx[peer_id] = {
        "sessionWebhook": str(sw),
        "expireTime": exp_i,
        "staffId": staff,
        "chatType": chat_type,
    }
    _save_reply_context(plugin_root, ctx)


def _reply_context_not_expired(rec: Dict[str, Any]) -> bool:
    exp = rec.get("expireTime") or 0
    if not exp:
        return True
    try:
        exp_i = int(exp)
    except (TypeError, ValueError):
        return True
    # 钉钉部分字段为毫秒时间戳，部分为秒
    if exp_i > 10**12:
        return int(time.time() * 1000) < exp_i
    return int(time.time()) < exp_i + 120


def _post_session_webhook(webhook_url: str, text: str) -> Tuple[bool, str]:
    """
    钉钉会话 Webhook（sendBySession）已绑定当前会话，仅需 msgtype/text。
    附带 at/atUserIds 时，oapi 常返回非 2xx 或 errcode≠0，表现为「发了没反应」。
    """
    payload: Dict[str, Any] = {
        "msgtype": "text",
        "text": {"content": text},
    }
    try:
        r = requests.post(
            webhook_url,
            headers={"Content-Type": "application/json"},
            data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
            timeout=30,
        )
        body = (r.text or "")[:800]
        # 部分接口 HTTP 200 但 body 含 errcode
        try:
            j = r.json()
            if isinstance(j, dict) and j.get("errcode") not in (None, 0):
                return False, "errcode=%s %s" % (j.get("errcode"), j.get("errmsg", body))
        except Exception:
            pass
        r.raise_for_status()
    except requests.RequestException as e:
        extra = ""
        if e.response is not None:
            try:
                extra = e.response.text[:500]
            except Exception:
                pass
        return False, "%s %s" % (e, extra)
    return True, ""


def _robot_otomessages_batch_send(client_id: str, client_secret: str, user_id: str, text: str) -> Tuple[bool, str]:
    """企业机器人单聊：OpenAPI batchSend（需应用具备机器人发单聊消息权限）。"""
    try:
        import dingtalk_stream
        from dingtalk_stream.utils import DINGTALK_OPENAPI_ENDPOINT
    except ImportError:
        return False, "dingtalk-stream not installed"

    cred = dingtalk_stream.Credential(client_id, client_secret)
    client = dingtalk_stream.DingTalkStreamClient(cred)
    token = client.get_access_token()
    if not token:
        return False, "cannot get access token"

    url = DINGTALK_OPENAPI_ENDPOINT + "/v1.0/robot/oToMessages/batchSend"
    body = {
        "robotCode": client_id,
        "userIds": [user_id],
        "msgKey": "sampleText",
        "msgParam": json.dumps({"content": text}, ensure_ascii=False),
    }
    headers = {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "x-acs-dingtalk-access-token": token,
        "User-Agent": (
            "DingTalkStream/1.0 Metis-Gateway Python/%s "
            "(+https://github.com/open-dingtalk/dingtalk-stream-sdk-python)"
        )
        % platform.python_version(),
    }
    try:
        r = requests.post(url, headers=headers, json=body, timeout=30)
        txt = r.text
        r.raise_for_status()
    except requests.RequestException as e:
        extra = ""
        if e.response is not None:
            try:
                extra = e.response.text[:800]
            except Exception:
                pass
        return False, "%s %s" % (e, extra)

    try:
        j = json.loads(txt) if txt else {}
        if isinstance(j, dict):
            code = j.get("code") or j.get("errcode")
            if code not in (None, "", "OK", 0):
                return False, txt[:800]
    except Exception:
        pass
    return True, ""


def _kill_pid_file(pid_file: str) -> None:
    if not os.path.isfile(pid_file):
        return
    try:
        with open(pid_file, encoding="utf-8") as f:
            pid = int(f.read().strip())
    except (ValueError, OSError):
        try:
            os.remove(pid_file)
        except OSError:
            pass
        return
    try:
        if sys.platform == "win32":
            subprocess.run(["taskkill", "/PID", str(pid), "/T", "/F"], capture_output=True, timeout=15)
        else:
            os.kill(pid, signal.SIGTERM)
    except OSError:
        pass
    try:
        os.remove(pid_file)
    except OSError:
        pass


def _kill_all_sidecars(plugin_root: str) -> None:
    _kill_pid_file(_webhook_pid_path(plugin_root))
    _kill_pid_file(_stream_pid_path(plugin_root))


def _extract_inbound_from_dingtalk_body(data: Any) -> Optional[Dict[str, Any]]:
    if not isinstance(data, dict):
        return None
    msg_id = None
    for k in ("msgId", "msg_id", "messageId", "uuid"):
        if k in data and data[k]:
            msg_id = str(data[k])
            break
    text = None
    if "text" in data and isinstance(data["text"], dict):
        text = data["text"].get("content")
    if text is None and "content" in data:
        text = data.get("content")
    if text is None and "message" in data and isinstance(data["message"], dict):
        m = data["message"]
        text = m.get("text") or m.get("content")
    if isinstance(text, dict):
        text = text.get("content")
    if text is not None:
        text = str(text).strip()
    if not text:
        return None

    sender = (
        data.get("senderId")
        or data.get("senderStaffId")
        or data.get("senderUnionId")
        or data.get("openId")
        or data.get("userId")
        or "unknown"
    )
    sender = str(sender)

    conv = data.get("conversationId") or data.get("chatId") or data.get("openConversationId")
    peer = str(conv) if conv else f"user:{sender}"

    chat_type = "direct"
    ct = data.get("conversationType")
    if ct is not None:
        try:
            if int(ct) != 1:
                chat_type = "group"
        except (TypeError, ValueError):
            pass
    if str(data.get("chatType") or "").lower() == "group":
        chat_type = "group"

    mentioned = bool(data.get("mentioned") or data.get("isAt") or data.get("atUsers"))

    return {
        "messageId": msg_id or "",
        "peerId": peer,
        "senderId": sender,
        "chatType": chat_type,
        "text": text,
        "mentioned": mentioned,
    }


def _inbound_from_chatbot_message(incoming: Any) -> Optional[Dict[str, Any]]:
    """从 dingtalk_stream.ChatbotMessage 转为网关 Inbound JSON。"""
    try:
        texts: List[str] = incoming.get_text_list() or []
    except Exception:
        texts = []
    text = "\n".join(str(t).strip() for t in texts if t).strip()
    if not text:
        return None

    sender = str(incoming.sender_staff_id or incoming.sender_id or "unknown")
    peer = str(incoming.conversation_id) if incoming.conversation_id else f"user:{sender}"
    ct = incoming.conversation_type
    chat_type = "direct"
    if ct is not None and str(ct) != "1":
        chat_type = "group"

    mentioned = bool(getattr(incoming, "is_in_at_list", False))
    mid = str(incoming.message_id or "")

    return {
        "messageId": mid,
        "peerId": peer,
        "senderId": sender,
        "chatType": chat_type,
        "text": text,
        "mentioned": mentioned,
    }


def _make_handler(plugin_root: str, webhook_path: str):
    path_norm = webhook_path.rstrip("/") or "/"

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, fmt: str, *args: Any) -> None:
            try:
                with open(_log_path(plugin_root), "a", encoding="utf-8") as lf:
                    lf.write("[webhook] " + self.address_string() + " - " + (fmt % args) + "\n")
            except OSError:
                pass

        def do_GET(self) -> None:
            parsed = urlparse(self.path)
            if parsed.path.rstrip("/") != path_norm.rstrip("/"):
                self.send_error(404)
                return
            qs = parse_qs(parsed.query or "")
            echostr = (qs.get("echostr") or [None])[0]
            if echostr:
                body = echostr.encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "text/plain; charset=utf-8")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
                return
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"ok")

        def do_POST(self) -> None:
            parsed = urlparse(self.path)
            if parsed.path.rstrip("/") != path_norm.rstrip("/"):
                self.send_error(404)
                return
            length = int(self.headers.get("Content-Length") or "0")
            raw = self.rfile.read(length) if length > 0 else b""
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b'{"ok":true}')
            try:
                data = json.loads(raw.decode("utf-8"))
            except (UnicodeDecodeError, json.JSONDecodeError):
                with open(_log_path(plugin_root), "a", encoding="utf-8") as lf:
                    lf.write("[webhook] non-json post len=%d\n" % len(raw))
                return
            line = _extract_inbound_from_dingtalk_body(data)
            if not line:
                with open(_log_path(plugin_root), "a", encoding="utf-8") as lf:
                    lf.write("[webhook] post no text: %s\n" % json.dumps(data, ensure_ascii=False)[:500])
                return
            _append_inbox(plugin_root, line)

    return Handler


def run_webhook_server(plugin_root: str, host: str, port: int, path: str) -> None:
    Handler = _make_handler(plugin_root, path)
    server = ThreadingHTTPServer((host, port), Handler)
    with open(_log_path(plugin_root), "a", encoding="utf-8") as lf:
        lf.write("[webhook] listening http://%s:%s%s\n" % (host, port, path))
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.shutdown()


def _stream_diag_log(plugin_root: str, line: str) -> None:
    with open(_log_path(plugin_root), "a", encoding="utf-8") as lf:
        lf.write(line.rstrip() + "\n")


def _configure_stream_file_logging(plugin_root: str) -> None:
    """把 dingtalk-stream 的 logging 打到 dingtalk.log，便于排查连接/订阅问题。"""
    import logging

    root = logging.getLogger()
    for h in root.handlers:
        if isinstance(h, logging.FileHandler):
            return
    log_file = _log_path(plugin_root)
    fmt = logging.Formatter("%(asctime)s [sdk] %(levelname)s %(name)s %(message)s")
    fh = logging.FileHandler(log_file, encoding="utf-8")
    fh.setFormatter(fmt)
    root.addHandler(fh)
    root.setLevel(logging.INFO)
    for name in ("dingtalk_stream", "dingtalk_stream.client", "dingtalk_stream.handler", "websockets"):
        logging.getLogger(name).setLevel(logging.INFO)


def run_stream_client(plugin_root: str, client_id: str, client_secret: str) -> None:
    import dingtalk_stream

    class GatewayBridgeHandler(dingtalk_stream.ChatbotHandler):
        def __init__(self, proot: str) -> None:
            super().__init__()
            self._plugin_root = proot

        async def process(self, callback: dingtalk_stream.CallbackMessage):
            try:
                incoming = dingtalk_stream.ChatbotMessage.from_dict(callback.data)
                mt = getattr(incoming, "message_type", None)
                has_sw = bool(getattr(incoming, "session_webhook", None))
                _stream_diag_log(
                    self._plugin_root,
                    "[stream] callback msgtype=%r convType=%r has_sessionWebhook=%s topic=%s"
                    % (
                        mt,
                        getattr(incoming, "conversation_type", None),
                        has_sw,
                        getattr(callback.headers, "topic", ""),
                    ),
                )
                line = _inbound_from_chatbot_message(incoming)
                if line:
                    _append_inbox(self._plugin_root, line)
                    _persist_stream_reply_context(self._plugin_root, incoming, line["peerId"])
                    _stream_diag_log(
                        self._plugin_root,
                        "[stream] -> inbox peer=%s text_len=%d" % (line["peerId"][:48], len(line.get("text") or "")),
                    )
                else:
                    _stream_diag_log(self._plugin_root, "[stream] skip: no extractable text (msgtype=%r)" % (mt,))
            except Exception as e:
                _stream_diag_log(self._plugin_root, "[stream] handler error: %r" % (e,))
            return dingtalk_stream.AckMessage.STATUS_OK, "OK"

    _stream_diag_log(plugin_root, "[stream] starting DingTalkStreamClient")
    _configure_stream_file_logging(plugin_root)

    credential = dingtalk_stream.Credential(client_id, client_secret)
    client = dingtalk_stream.DingTalkStreamClient(credential)
    # 部分租户/场景消息走 delegate topic，仅注册 TOPIC 会收不到
    client.register_callback_handler(dingtalk_stream.ChatbotMessage.TOPIC, GatewayBridgeHandler(plugin_root))
    client.register_callback_handler(dingtalk_stream.ChatbotMessage.DELEGATE_TOPIC, GatewayBridgeHandler(plugin_root))
    client.start_forever()


def _spawn_daemon(plugin_root: str, plugin_id: str, subcmd: str, pid_path: str) -> None:
    script = os.path.join(plugin_root, "adapter.py")
    if not os.path.isfile(script):
        with open(_log_path(plugin_root), "a", encoding="utf-8") as lf:
            lf.write("[%s] adapter.py missing under plugin root\n" % subcmd)
        return
    creationflags = 0
    if sys.platform == "win32":
        creationflags = getattr(subprocess, "DETACHED_PROCESS", 0)
        creationflags |= getattr(subprocess, "CREATE_NO_WINDOW", 0)
    args = [sys.executable, "-u", script, subcmd, "--plugin-root", plugin_root, "--plugin-id", plugin_id]
    # 子进程 stdout/stderr 写入 dingtalk.log，避免 SDK 报错被 DEVNULL 吃掉
    try:
        log_fp = open(_log_path(plugin_root), "a", encoding="utf-8")
    except OSError:
        log_fp = None
    kwargs: Dict[str, Any] = {
        "stdout": log_fp if log_fp is not None else subprocess.DEVNULL,
        "stderr": log_fp if log_fp is not None else subprocess.DEVNULL,
        "stdin": subprocess.DEVNULL,
        "close_fds": True,
    }
    if sys.platform == "win32":
        kwargs["creationflags"] = creationflags
    else:
        kwargs["start_new_session"] = True
    proc = subprocess.Popen(args, **kwargs)
    with open(pid_path, "w", encoding="utf-8") as f:
        f.write(str(proc.pid))


def start_hook(plugin_root: str, cfg: Dict[str, Any], channel_id: str) -> None:
    block = get_channel_block(cfg, channel_id)
    transport = dingtalk_transport(block)
    _kill_all_sidecars(plugin_root)
    plugin_id = str(cfg.get("_pluginId") or channel_id)
    if transport == "stream":
        _spawn_daemon(plugin_root, plugin_id, "stream", _stream_pid_path(plugin_root))
    elif transport == "webhook":
        _spawn_daemon(plugin_root, plugin_id, "webhook", _webhook_pid_path(plugin_root))
    else:
        with open(_log_path(plugin_root), "a", encoding="utf-8") as lf:
            lf.write("dingtalk unknown transport=%s\n" % transport)


def stop_hook(plugin_root: str, cfg: Dict[str, Any], channel_id: str) -> None:
    _kill_all_sidecars(plugin_root)


def cmd_webhook(plugin_root: str, plugin_id: str) -> int:
    cfg_path = os.path.join(_runtime_dir(plugin_root), "runtime-config.json")
    if not os.path.isfile(cfg_path):
        sys.stderr.write("missing %s\n" % cfg_path)
        return 1
    with open(cfg_path, encoding="utf-8") as f:
        cfg = json.load(f)
    cfg["_pluginId"] = plugin_id
    block = get_channel_block(cfg, "dingtalk")
    host, port, path = dingtalk_webhook_listen(block)
    run_webhook_server(plugin_root, host, port, path)
    return 0


def cmd_stream(plugin_root: str, plugin_id: str) -> int:
    cfg_path = os.path.join(_runtime_dir(plugin_root), "runtime-config.json")
    if not os.path.isfile(cfg_path):
        sys.stderr.write("missing %s\n" % cfg_path)
        return 1
    with open(cfg_path, encoding="utf-8") as f:
        cfg = json.load(f)
    cfg["_pluginId"] = plugin_id
    block = get_channel_block(cfg, "dingtalk")
    cid = str(block.get("clientId") or "").strip()
    csec = str(block.get("clientSecret") or "").strip()
    if not cid or not csec:
        sys.stderr.write("channels.dingtalk.clientId and clientSecret are required for stream mode\n")
        return 1
    try:
        run_stream_client(plugin_root, cid, csec)
    except ImportError:
        sys.stderr.write(
            "未安装 dingtalk-stream。请执行: pip install dingtalk-stream\n"
            "或: pip install -r tools/gateway_plugin_tool/requirements.txt\n"
        )
        return 1
    return 0


def op_send_dingtalk(plugin_root: str, cfg: Dict[str, Any], peer_id: str, text: str, reply_to: str) -> int:
    """
    发消息优先单聊：
    1) 使用近期入站写入的 sessionWebhook（Stream 回调，同 peerId）；
    2) 否则单聊走 OpenAPI POST /v1.0/robot/oToMessages/batchSend（userIds 取 user: 前缀或上下文 staffId）。
    群聊在无有效 sessionWebhook 时暂不调用 batchSend（避免错误接口）。
    """
    _ = reply_to
    peer_id = peer_id.strip()
    text = text.strip()
    if not peer_id or not text:
        sys.stderr.write("dingtalk send: empty peer-id or text\n")
        return 1

    cfg = normalize_legacy_config(dict(cfg), "dingtalk")
    block = get_channel_block(cfg, "dingtalk")
    client_id = str(block.get("clientId") or "").strip()
    client_secret = str(block.get("clientSecret") or "").strip()

    ctx = _load_reply_context(plugin_root)
    rec = ctx.get(peer_id)

    if rec and rec.get("sessionWebhook") and _reply_context_not_expired(rec):
        with open(_log_path(plugin_root), "a", encoding="utf-8") as lf:
            lf.write("[send] try sessionWebhook peer=%s text_len=%d\n" % (peer_id[:48], len(text)))
        ok, err = _post_session_webhook(str(rec["sessionWebhook"]), text)
        if ok:
            with open(_log_path(plugin_root), "a", encoding="utf-8") as lf:
                lf.write("[send] sessionWebhook ok\n")
            return 0
        with open(_log_path(plugin_root), "a", encoding="utf-8") as lf:
            lf.write("[send] sessionWebhook failed: %s\n" % err)

    chat_type = (rec or {}).get("chatType") or "direct"
    if chat_type == "group":
        sys.stderr.write(
            "钉钉群聊回复需要有效的 sessionWebhook。请让用户在该会话内再发一条消息，或后续接入群聊 OpenAPI。\n"
        )
        return 1

    uid: Optional[str] = None
    if peer_id.startswith("user:"):
        uid = peer_id[5:].strip()
    elif rec and rec.get("staffId"):
        uid = str(rec["staffId"]).strip()
    if not uid:
        sys.stderr.write(
            "钉钉单聊发送失败：无可用 sessionWebhook，且无法解析用户 ID。"
            "请先与机器人私聊一句（推荐），或确保 peerId 为 user:<钉钉用户ID>。\n"
        )
        return 1
    if not client_id or not client_secret:
        sys.stderr.write("channels.dingtalk.clientId / clientSecret 未配置，无法用 OpenAPI 发单聊。\n")
        return 1

    with open(_log_path(plugin_root), "a", encoding="utf-8") as lf:
        lf.write("[send] try batchSend userId=%s text_len=%d\n" % (uid[:32], len(text)))
    ok, err = _robot_otomessages_batch_send(client_id, client_secret, uid, text)
    if ok:
        with open(_log_path(plugin_root), "a", encoding="utf-8") as lf:
            lf.write("[send] batchSend ok\n")
        return 0
    with open(_log_path(plugin_root), "a", encoding="utf-8") as lf:
        lf.write("[send] batchSend failed: %s\n" % err)
    sys.stderr.write("钉钉 batchSend 失败: %s\n" % err)
    return 1


from channels import register_channel

register_channel("dingtalk", start_hook, stop_hook)
