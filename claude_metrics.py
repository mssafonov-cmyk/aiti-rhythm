"""Incremental Claude Code metadata reader. No credentials or message text in cache."""
from datetime import datetime
from pathlib import Path
import json
import time
from burn import velocity, day_series
from local_metrics import MSK
from claude_usage import cached_usage

_cache = {}


def metadata_rows(path, now):
    stat = path.stat()
    identity = (stat.st_dev, stat.st_ino)
    entry = _cache.get(path)
    if (entry is None or entry['identity'] != identity or stat.st_size < entry['offset'] or
            (stat.st_size == entry['size'] and stat.st_mtime_ns != entry['mtime'])):
        entry = dict(identity=identity, size=0, mtime=0, offset=0, rows=[])
        _cache[path] = entry
    with path.open('rb') as stream:
        stream.seek(entry['offset'])
        while stream.tell() < stat.st_size:
            line = stream.readline(stat.st_size - stream.tell())
            if not line.endswith(b'\n'):
                break
            entry['offset'] = stream.tell()
            try:
                raw = json.loads(line)
                dt = datetime.fromisoformat(raw.get('timestamp', '').replace('Z', '+00:00'))
                dt = dt.replace(tzinfo=MSK) if dt.tzinfo is None else dt
                if dt.timestamp() < now - 7 * 86400:
                    continue
            except (ValueError, TypeError):
                continue
            message = raw.get('message') or {}
            content = message.get('content', [])
            ask = isinstance(content, list) and any(v.get('name') == 'AskUserQuestion' for v in content if isinstance(v, dict))
            entry['rows'].append(dict(kind=raw.get('type'), subtype=raw.get('subtype'), at=dt.timestamp(),
                sid=raw.get('sessionId'), project=Path(raw.get('cwd') or '').name,
                mid=message.get('id'), usage={key: value for key, value in (message.get('usage') or {}).items()
                if key in ('input_tokens','output_tokens','cache_read_input_tokens','cache_creation_input_tokens')},
                stop=message.get('stop_reason'), ask=ask))
    entry['size'], entry['mtime'] = stat.st_size, stat.st_mtime_ns
    entry['rows'] = [row for row in entry['rows'] if row['at'] >= now - 7 * 86400]
    return entry['rows']


def claude_local(home, now=None, window_seconds=900):
    now = time.time() if now is None else now
    day = datetime.fromtimestamp(now, MSK).date()
    sessions, totals, points, messages, seen = [], dict(input=0, output=0, cache=0), [], {}, set()
    limits, limits_at = cached_usage(home)
    if not (home / 'projects').is_dir():
        return {'checked_at': now, 'sessions': [], 'observed': False, 'tokens': totals,
                **({'limits': limits, 'limits_at': limits_at} if limits else {}),
                'limits_error': None if limits else 'not_available', 'status': 'journals_not_found'}
    for path in (home / 'projects').rglob('*.jsonl'):
        if path.stat().st_mtime < now - 7 * 86400:
            continue
        seen.add(path)
        state, at, sid, project = 'unknown', 0, path.stem, path.parent.name
        for row in metadata_rows(path, now):
            if row['at'] > now:
                continue
            sid, project = row['sid'] or sid, row['project'] or project
            if row['kind'] == 'user':
                state, at = 'working', row['at']
            elif row['kind'] == 'assistant':
                at = row['at']
                state = 'waiting' if row['ask'] else 'idle' if row['stop'] in ('end_turn', 'stop_sequence') else 'working'
                if row['mid'] and datetime.fromtimestamp(at, MSK).date() == day:
                    item = messages.setdefault(row['mid'], {'at': at, 'usage': {}})
                    for key, value in row['usage'].items():
                        item['usage'][key] = max(item['usage'].get(key, 0), value or 0)
            elif row['kind'] == 'system' and row['subtype'] == 'turn_duration' and state != 'waiting':
                state, at = 'idle', row['at']
        if state == 'working' and now - at > 1800:
            state = 'unknown'
        if datetime.fromtimestamp(at, MSK).date() == day or state in ('working', 'waiting'):
            sessions.append(dict(provider='Claude', id=str(sid), project=project, title=project, status=state, at=at))
    for path in list(_cache):
        if path not in seen:
            del _cache[path]
    for item in messages.values():
        usage = item['usage']; cache = usage.get('cache_read_input_tokens', 0)
        input_count = usage.get('input_tokens', 0) + cache + usage.get('cache_creation_input_tokens', 0)
        output = usage.get('output_tokens', 0)
        totals['input'] += input_count; totals['output'] += output; totals['cache'] += cache
        points.append((item['at'], input_count + output, input_count - cache + output))
    burn = velocity(points, now, window_seconds)
    burn.update(series=day_series(points, now), leaders=[], alert=False)
    return dict(checked_at=now, sessions=sessions, observed=bool(messages), tokens=totals,
                burn=burn, **({'limits': limits, 'limits_at': limits_at} if limits else {}),
                limits_error=None if limits else 'not_available')
