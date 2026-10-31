"""Read Antigravity CLI metadata only. Never starts agy or reads account credentials."""
from datetime import datetime, timezone
from contextlib import closing
import json
from pathlib import Path
import shutil
import sqlite3
import time
from uuid import UUID
from burn import day_start_msk, day_series, velocity

_cache = {}
COUNTERS = ('input_tokens', 'output_tokens', 'cache_read_tokens')


def profile(value=''):
    return Path(value).expanduser() if value else Path.home() / '.gemini' / 'antigravity-cli'


def installed():
    return bool(shutil.which('agy') or shutil.which('agy.exe') or
                (Path.home() / '.gemini' / 'bin' / 'agy.exe').is_file() or
                (Path.home() / '.gemini' / 'bin' / 'agy').is_file())


def stamp(value):
    try:
        dt = datetime.fromisoformat(str(value).replace('Z', '+00:00'))
        return (dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)).timestamp()
    except (ValueError, TypeError):
        return 0


def usage_rows(path):
    """Incremental, bounded JSONL reader. Cache stores counters/timestamps, no text."""
    stat = path.stat()
    identity = (stat.st_dev, stat.st_ino)
    entry = _cache.get(path)
    if (not entry or entry['identity'] != identity or stat.st_size < entry['offset'] or
            (entry['size'] == stat.st_size and entry['mtime'] != stat.st_mtime_ns)):
        entry = dict(identity=identity, offset=0, size=0, mtime=0, steps={}, partial=False)
        _cache[path] = entry
    with path.open('rb') as stream:
        stream.seek(entry['offset'])
        while stream.tell() < stat.st_size:
            line = stream.readline(min(1024 * 1024 + 1, stat.st_size - stream.tell()))
            oversized = len(line) > 1024 * 1024
            while oversized and not line.endswith(b'\n') and stream.tell() < stat.st_size:
                line = stream.readline(min(65536, stat.st_size - stream.tell()))
            if not line.endswith(b'\n'):
                break  # Retry incomplete tail on the next refresh.
            entry['offset'] = stream.tell()
            if oversized:
                entry['partial'] = True
                continue
            try:
                row = json.loads(line)
                if not isinstance(row, dict) or row.get('type') != 'PLANNER_RESPONSE':
                    continue
                idx = row.get('step_index')
                at = stamp(row.get('created_at'))
                if type(idx) is not int or not at:
                    continue
                values = {k: row[k] for k in COUNTERS if type(row.get(k)) is int and row[k] >= 0}
                if not {'input_tokens', 'output_tokens'} <= values.keys():
                    entry['partial'] = True
                    continue
                previous = entry['steps'].get(idx, {})
                entry['steps'][idx] = dict(at=at, **{k: max(values.get(k, 0), previous.get(k, 0)) for k in COUNTERS})
            except (ValueError, TypeError, UnicodeError):
                entry['partial'] = True
                continue
    entry.update(size=stat.st_size, mtime=stat.st_mtime_ns)
    return list(entry['steps'].values())


def summaries(root):
    path = root / 'conversation_summaries.db'
    if not path.is_file():
        return {}
    with closing(sqlite3.connect(path.resolve().as_uri() + '?mode=ro', uri=True, timeout=1)) as db:
        db.execute('PRAGMA query_only=ON')
        columns = {r[1] for r in db.execute('PRAGMA table_info(conversation_summaries)')}
        required = ('conversation_id', 'title', 'status', 'last_modified_time')
        if not set(required) <= columns:
            raise ValueError('Unsupported summary schema')
        # Deliberately exclude raw_summary, preview and other message-bearing fields.
        flags = ','.join(name if name in columns else '0 AS '+name for name in ('killed','not_fully_idle'))
        rows = db.execute('SELECT conversation_id,title,status,last_modified_time,' + flags + ' '
                          'FROM conversation_summaries ORDER BY last_modified_time DESC LIMIT 1000')
        return {str(sid): dict(title=str(title or '')[:200], status=str(status), at=stamp(at), killed=bool(killed), not_idle=bool(not_idle))
                for sid, title, status, at, killed, not_idle in rows}


def antigravity_local(home=None, now=None, window_seconds=900):
    root = Path(home) if home is not None else profile()
    now = time.time() if now is None else now
    present = installed() or (root / 'conversation_summaries.db').is_file() or (root / 'brain').is_dir()
    result = dict(checked_at=now, available=present, sessions=[], observed=False,
                  tokens=dict(input=0, output=0, cache=0), limits_error='not_available',
                  usage_note='Antigravity: вход + выход по нативным счётчикам; кэш отдельно. Не стоимость.')
    if not present:
        return dict(result, status='not_installed')
    try:
        meta = summaries(root)
    except (OSError, sqlite3.Error, ValueError):
        meta = {}
        result['metadata_status'] = 'unavailable'
    paths = {}
    for path in (root / 'brain').glob('*/.system_generated/logs/transcript.jsonl'):
        try:
            sid = str(UUID(path.parents[2].name))
            if path.stat().st_mtime >= now - 7 * 86400:
                paths[sid] = path
        except (OSError, ValueError):
            continue
    points, leaders, start = [], [], day_start_msk(now)
    for sid in meta.keys() | paths.keys():
        item = meta.get(sid, {})
        at, title = item.get('at', 0), item.get('title') or 'Сессия Antigravity'
        status = {'CASCADE_RUN_STATUS_IDLE': 'idle', 'CASCADE_RUN_STATUS_RUNNING': 'working',
                  'CASCADE_RUN_STATUS_BUSY': 'working', 'CASCADE_RUN_STATUS_CANCELING': 'interrupted'}.get(item.get('status'), 'unknown')
        if status == 'working' and now - at > 1800:
            status = 'unknown'
        if item.get('killed'):
            status = 'interrupted'
        elif status == 'idle' and item.get('not_idle'):
            status = 'unknown'  # Never invent a waiting/approval state.
        local_points = []
        if sid in paths:
            try:
                for row in usage_rows(paths[sid]):
                    if row['at'] <= now:
                        at = max(at, row['at'])
                    if start <= row['at'] <= now:
                        result['observed'] = True
                        inp, out, cache = (row[k] for k in COUNTERS)
                        result['tokens']['input'] += inp
                        result['tokens']['output'] += out
                        result['tokens']['cache'] += cache
                        # Match native total_tokens=input+output. Do not infer cache pricing.
                        local_points.append((row['at'], inp + out, inp + out))
                if _cache[paths[sid]]['partial']:
                    result['usage_partial'] = True
            except OSError:
                result['metadata_status'] = 'unavailable'
                result['usage_partial'] = True
        points.extend(local_points)
        rate = velocity(local_points, now, window_seconds)
        rate['uncached_per_min'] = None  # Cache accounting is not inferred from native totals.
        if at >= start or status in ('working', 'waiting'):
            result['sessions'].append(dict(provider='Antigravity', id=sid, title=title, project='', status=status, at=at, rate=rate))
        if local_points:
            leaders.append(dict(provider='Antigravity', id=sid, title=title,
                                day_tokens=sum(p[1] for p in local_points), **rate))
    for path in list(_cache):
        if path.is_relative_to(root) and path not in paths.values():
            del _cache[path]
    burn = velocity(points, now, window_seconds)
    burn['uncached_per_min'] = None
    leaders.sort(key=lambda x: (x['per_min'], x['day_tokens']), reverse=True)
    burn.update(series=day_series(points, now), leaders=leaders[:10],
                leader_basis='window' if burn['per_min'] else 'day',
                alert=burn['level'] in ('warning', 'critical'))
    result['burn'] = burn
    if result.get('usage_partial'):
        result['usage_note'] += ' Часть записей недоступна; показан только прочитанный объём.'
    if not paths:
        result['status'] = 'journals_not_found'
    return result
