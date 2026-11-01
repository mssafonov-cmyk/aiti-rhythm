"""Read token metadata from retained journals. Standalone for an existing SSH reader.

No credentials, message bodies, titles, network requests or disk writes in this module.
"""
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import time

MSK = timezone(timedelta(hours=3))
_files = {}


def number(value):
    return value if type(value) is int and 0 <= value <= 10**16 else 0


def timestamp(value):
    dt = datetime.fromisoformat(value.replace('Z', '+00:00'))
    return (dt.replace(tzinfo=MSK) if dt.tzinfo is None else dt).timestamp()


def day(at):
    return datetime.fromtimestamp(at, MSK).strftime('%Y-%m-%d')


def file_usage(path, provider, now):
    stat = path.stat()
    signature = (stat.st_dev, stat.st_ino, stat.st_size, stat.st_mtime_ns)
    key = (str(path), provider)
    old = _files.get(key)
    if old and old[0] == signature:
        return old[1]
    totals, messages, previous = {}, {}, {}
    sid, fork_at, partial = str(path), None, False
    with path.open('rb') as stream:
        while True:
            raw = stream.readline(16 * 1024 * 1024)
            if not raw:
                break
            if not raw.endswith(b'\n'):
                partial = True
                while raw and not raw.endswith(b'\n'):
                    raw = stream.readline(16 * 1024 * 1024)
                continue
            try:
                row = json.loads(raw)
                if not isinstance(row, dict):
                    continue
                if provider == 'codex':
                    payload = row.get('payload') or {}
                    if row.get('type') == 'session_meta':
                        sid = payload.get('id') or sid
                        if payload.get('forked_from_id'):
                            fork_at = timestamp(payload.get('timestamp') or row['timestamp'])
                        continue
                    if row.get('type') != 'event_msg' or payload.get('type') != 'token_count':
                        continue
                    usage = (payload.get('info') or {}).get('total_token_usage')
                    if not isinstance(usage, dict) or not usage:
                        continue
                    at = timestamp(row['timestamp'])
                    counts = {k: number(usage.get(k)) for k in ('input_tokens', 'output_tokens')}
                    delta = sum(max(0, counts[k] - previous.get(k, 0)) for k in counts)
                    if fork_at and (at < fork_at or not previous):
                        delta = 0  # Copied parent history is a baseline, never fresh spend.
                    previous = counts
                    if at <= now and (not fork_at or at >= fork_at):
                        totals[day(at)] = totals.get(day(at), 0) + delta
                else:
                    if row.get('type') != 'assistant':
                        continue
                    message = row.get('message') or {}
                    usage, mid = message.get('usage'), message.get('id')
                    if not mid or not isinstance(usage, dict) or not usage:
                        continue
                    at = timestamp(row['timestamp'])
                    if at > now:
                        continue
                    item = messages.setdefault(mid, {'at': at, 'usage': {}})
                    item['at'] = min(item['at'], at)
                    for field in ('input_tokens', 'output_tokens', 'cache_read_input_tokens', 'cache_creation_input_tokens'):
                        item['usage'][field] = max(item['usage'].get(field, 0), number(usage.get(field)))
            except (ValueError, TypeError, KeyError, AttributeError, OverflowError):
                partial = True
    result = dict(totals=totals, messages=messages, sid=sid, partial=partial, modified=stat.st_mtime_ns)
    _files[key] = signature, result
    return result


def read_history(home, provider, now=None):
    now = time.time() if now is None else now
    home = Path(home)
    folders = [home / 'sessions', home / 'archived_sessions'] if provider == 'codex' else [home / 'projects']
    totals, sessions, messages, seen = {}, {}, {}, set()
    partial = False
    for folder in folders:
        if not folder.is_dir():
            continue
        for path in folder.rglob('*.jsonl'):
            seen.add((str(path), provider))
            try:
                item = file_usage(path, provider, now)
            except OSError:
                partial = True
                continue
            partial |= item['partial']
            if provider == 'codex':
                old = sessions.get(item['sid'])
                if not old or item['modified'] > old['modified']:
                    sessions[item['sid']] = item
            else:
                for mid, value in item['messages'].items():
                    old = messages.setdefault(mid, {'at': value['at'], 'usage': {}})
                    old['at'] = min(old['at'], value['at'])
                    for key, count in value['usage'].items():
                        old['usage'][key] = max(old['usage'].get(key, 0), count)
    for key in list(_files):
        if key[1] == provider and key[0].startswith(str(home)) and key not in seen:
            del _files[key]
    for item in sessions.values():
        for date, count in item['totals'].items():
            totals[date] = totals.get(date, 0) + count
    for item in messages.values():
        date = day(item['at'])
        totals[date] = totals.get(date, 0) + sum(item['usage'].values())
    return dict(days=[dict(date=date, total=count, partial=partial) for date, count in sorted(totals.items())],
                checked_at=now, partial=partial, available=any(p.is_dir() for p in folders))
