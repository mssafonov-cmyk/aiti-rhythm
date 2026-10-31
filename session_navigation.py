"""Passive session destinations; never execute log-provided commands or start turns."""
import json
import re
import time
from pathlib import Path
from urllib.parse import urlsplit
from safeio import atomic_json

UUID = re.compile(r'[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}', re.I)


def valid_activation_args(argv):
    # A quoted %1 protocol registration must never allow injected worker flags.
    return '--notification' not in argv or (len(argv) == 2 and argv[0] == '--notification')


def uuid(value):
    return value.lower() if isinstance(value, str) and UUID.fullmatch(value) else None


def codex_navigation(meta):
    origin = str(meta.get('originator', '')).strip().lower()
    kind = {'codex desktop': 'codex_desktop', 'vs code': 'codex_vscode',
            'codex_vscode': 'codex_vscode', 'cursor': 'codex_cursor',
            'windsurf': 'codex_windsurf'}.get(origin, 'manual')
    # Desktop also reports source=vscode. Never use that field as an IDE detector.
    source = meta.get('source')
    parent = None
    if isinstance(source, dict):
        sub = source.get('subagent')
        if isinstance(sub, dict) and isinstance(sub.get('thread_spawn'), dict):
            parent = uuid(sub['thread_spawn'].get('parent_thread_id'))
    return dict(kind=kind, **({'target_id': parent} if parent else {}))


def destination(target):
    if not isinstance(target, dict):
        return None
    sid = uuid(target.get('id'))
    nav = target.get('navigation') or {}
    if not sid or not isinstance(nav, dict):
        return None
    sid = uuid(nav.get('target_id', sid))
    if not sid:
        return None
    kind, provider = nav.get('kind'), target.get('provider', 'Codex')
    if provider == 'Codex':
        if kind == 'codex_desktop':
            return 'codex://threads/' + sid
        schemes = {'codex_vscode': 'vscode', 'codex_cursor': 'cursor', 'codex_windsurf': 'windsurf'}
        if kind in schemes:
            return schemes[kind] + '://openai.chatgpt/local/' + sid
    if provider == 'Claude' and kind == 'claude_vscode':
        return 'vscode://anthropic.claude-code/open?session=' + sid
    return None


def notification_target(root, uri, now=None):
    """Only immutable, local notification references; no URL-supplied destinations."""
    parsed = urlsplit(uri)
    ref = uuid(parsed.path.lstrip('/'))
    if parsed.scheme != 'aiti-rhythm' or parsed.netloc != 'notification' or parsed.query or parsed.fragment or not ref:
        raise ValueError('Invalid notification reference')
    data = json.loads((Path(root)/'notifications'/(ref+'.json')).read_text(encoding='utf-8-sig'))
    at = data.get('at')
    age = (time.time() if now is None else now) - at if type(at) in (int, float) else -1
    target = data.get('target')
    if not 0 <= age < 86400 or not isinstance(target, dict) or not uuid(target.get('id')):
        raise ValueError('Expired or invalid notification')
    if target.get('provider', 'Codex') not in ('Codex', 'Claude', 'Antigravity'):
        raise ValueError('Unknown session provider')
    return target


def activate(root, uri, opener):
    target = notification_target(root, uri)
    url = destination(target)
    if url:
        try:
            opener(url)
            atomic_json(Path(root)/'notification-dispatch.json',dict(at=time.time(),id=target['id'],
                        kind=target['navigation']['kind'],shell_accepted=True))
            return True
        except OSError:
            target = dict(target, navigation={'kind':'manual'})
    atomic_json(Path(root)/'notification-open.signal', target)
    return False
