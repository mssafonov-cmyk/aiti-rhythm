"""Quota metadata only: no credential handling, extra requests or inferred reset dates."""
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
import ast
import json
import math
from pathlib import Path
import time
import urllib.error
import urllib.request


def with_reset_metadata_source(source, state=None):
    """Keep metadata in the legacy reader's existing remote Python invocation."""
    try:
        tree = ast.parse(source)
        printed = tree.body[-1].value
        dumped = printed.args[0]
        result = dumped.args[0]
        if not (isinstance(printed, ast.Call) and isinstance(printed.func, ast.Name)
                and printed.func.id == 'print' and isinstance(dumped, ast.Call)
                and isinstance(dumped.func, ast.Attribute) and dumped.func.attr == 'dumps'
                and isinstance(result, ast.Dict)
                and {'limits', 'limits_at'}.issubset({key.value for key in result.keys if isinstance(key, ast.Constant)})):
            return source
        function = ast.parse('def _rhythm_existing_read():\n pass').body[0]
        function.body = tree.body[:-1] + [ast.Return(value=result)]
        wrapped = ast.fix_missing_locations(ast.Module(body=[function], type_ignores=[]))
        # This public source file is explicitly shipped next to the frozen app.
        support = Path(__file__).read_text(encoding='utf-8-sig')
        return support + '\n' + ast.unparse(wrapped) + '\nprint(json.dumps(preserve_reset_metadata(_rhythm_existing_read, '+repr(state)+'), ensure_ascii=False))\n'
    except (SyntaxError, IndexError, AttributeError, TypeError):
        return source


def normalize_usage(block):
    windows = {}
    if not isinstance(block, dict):
        return windows
    for name in ('five_hour', 'seven_day'):
        raw = block.get(name)
        if not isinstance(raw, dict):
            continue
        used = raw.get('used_percentage', raw.get('utilization'))
        if isinstance(used, bool) or not isinstance(used, (int, float)) or not math.isfinite(used):
            continue
        value = {'used_percentage': max(0, min(100, used))}
        reset = raw.get('resets_at')
        if isinstance(reset, str):
            try:
                parsed = datetime.fromisoformat(reset.replace('Z', '+00:00'))
                if parsed.tzinfo is not None:
                    value['resets_at'] = parsed.isoformat()
            except ValueError:
                pass
        windows[name] = value
    return windows


def cached_usage(home):
    home = Path(home)
    path = home.parent / '.claude.json' if home.name == '.claude' else home / '.claude.json'
    try:
        block = json.loads(path.read_text(encoding='utf-8-sig')).get('cachedUsageUtilization') or {}
        values = normalize_usage(block.get('utilization') or {})
        fetched = block.get('fetchedAtMs')
        return values, fetched / 1000 if isinstance(fetched, (int, float)) else None
    except (OSError, ValueError, TypeError, AttributeError):
        return {}, None


def timestamp(value):
    return value if type(value) in (int, float) and math.isfinite(value) and value > 0 else None


def quota_state(value):
    """Only public numeric quota metadata crosses the adapter/process boundary."""
    value = value if isinstance(value, dict) else {}
    state = {'limits': normalize_usage(value.get('limits') or {}), 'limits_at': timestamp(value.get('limits_at'))}
    for key in ('limits_retry_at', 'limits_attempt_at', 'limits_backoff'):
        state[key] = timestamp(value.get(key))
    state['limits_error'] = value.get('limits_error') if value.get('limits_error') in ('rate_limited', 'unavailable') else None
    return state


def retry_seconds(header, now, previous=0):
    """Honor both forms of Retry-After, including waits longer than our fallback cap."""
    try:
        seconds = float(header)
        if math.isfinite(seconds) and seconds >= 0:
            return max(1, seconds)
    except (ValueError, TypeError):
        pass
    try:
        date = parsedate_to_datetime(header)
        if date.tzinfo is None:
            date = date.replace(tzinfo=timezone.utc)
        return max(1, date.timestamp()-now)
    except (ValueError, TypeError, OverflowError, AttributeError):
        return min(1800, max(360, (previous or 180)*2))


def newest_quota(result, previous):
    current, old = quota_state(result), quota_state(previous)
    if old['limits'] and old['limits_at'] and (not current['limits'] or not current['limits_at'] or old['limits_at'] > current['limits_at']):
        result = dict(result, limits=old['limits'], limits_at=old['limits_at'])
        for key in ('limits_retry_at', 'limits_attempt_at', 'limits_backoff', 'limits_error'):
            if key not in result:
                result[key] = old[key]
    return result


def preserve_reset_metadata(read, state=None):
    """Observe the existing legacy reader's response inside its single-use subprocess.

    The former reader discarded resets_at. Preserve that field without reading its
    token, changing its request or making another network call. Restore the hook
    even on failure. Only matching percentages from the same response are merged.
    """
    original = urllib.request.urlopen
    observed = {}
    previous = quota_state(state)
    metadata = {key: previous[key] for key in ('limits_retry_at', 'limits_attempt_at', 'limits_backoff', 'limits_error')}
    attempted = False

    class Response:
        def __init__(self, response):
            self.response = response

        def __enter__(self):
            self.response.__enter__()
            return self

        def __exit__(self, *args):
            return self.response.__exit__(*args)

        def __getattr__(self, name):
            return getattr(self.response, name)

        def read(self, *args, **kwargs):
            body = self.response.read(*args, **kwargs)
            if len(body) <= 1024 * 1024:
                try:
                    observed.update(normalize_usage(json.loads(body)))
                except (ValueError, TypeError, AttributeError):
                    pass
            return body

    def open_existing(request, *args, **kwargs):
        nonlocal attempted
        url = request.full_url if isinstance(request, urllib.request.Request) else str(request)
        if url != 'https://api.anthropic.com/api/oauth/usage':
            return original(request, *args, **kwargs)
        now = time.time()
        if state is not None and (metadata['limits_retry_at'] or 0) > now:
            # The existing reader catches URLError and may still collect local tokens.
            raise urllib.error.URLError('Quota retry is paused')
        attempted = True
        metadata['limits_attempt_at'] = now
        try:
            response = original(request, *args, **kwargs)
        except urllib.error.HTTPError as error:
            metadata['limits_error'] = 'rate_limited' if error.code == 429 else 'unavailable'
            if error.code == 429:
                wait = retry_seconds(error.headers.get('Retry-After') if error.headers else None, now, previous['limits_backoff'])
                metadata.update(limits_retry_at=now+wait, limits_backoff=wait)
            else:
                metadata['limits_retry_at'] = now+180
            raise
        except (OSError, urllib.error.URLError):
            metadata.update(limits_error='unavailable', limits_retry_at=now+180)
            raise
        metadata.update(limits_error=None, limits_retry_at=None, limits_backoff=None)
        return Response(response)

    urllib.request.urlopen = open_existing
    try:
        result = read()
    finally:
        urllib.request.urlopen = original
    for name, window in observed.items():
        current = result.get('limits', {}).get(name, {})
        if current.get('used_percentage') == window['used_percentage'] and window.get('resets_at'):
            current['resets_at'] = window['resets_at']
    if state is not None:
        if attempted and not observed and metadata['limits_error'] is None:
            metadata['limits_error'] = 'unavailable'
        # Keep a newer snapshot even if the legacy reader returns an old file fallback.
        result = newest_quota(result, previous)
        result.update(metadata)
    return result


class ClaudeQuotaMemory:
    """Retain the last quota across provider failures and app restarts, scoped to profile."""
    def __init__(self, root):
        self.path = root / 'claude-quota-memory.json'
        self.identity, self.saved = None, {}
        try:
            raw = json.loads(self.path.read_text(encoding='utf-8-sig'))
            if raw.get('version') == 1 and isinstance(raw.get('identity'), str):
                self.identity, self.saved = raw['identity'], quota_state(raw)
        except (OSError, ValueError, TypeError, AttributeError):
            pass

    def enrich(self, source, identity, now):
        if identity != self.identity:
            self.identity, self.saved = identity, {}
        if source.get('enabled') is False:
            return source
        result = newest_quota(source, self.saved)
        value = quota_state(result)
        if value['limits'] and value['limits_at'] and value['limits_at'] <= now:
            # Keep status alongside the value so a restart during backoff stays explicit.
            if source.get('error') and not value['limits_error']:
                value['limits_error'] = 'unavailable'
            if value != self.saved:
                self.saved = value
                try:
                    from safeio import atomic_json
                    atomic_json(self.path, dict(value, version=1, identity=identity))
                except OSError:
                    pass  # The running collector still retains its RAM snapshot.
            result = dict(result, **value)
            result['limits_cached'] = bool(source.get('error') or value['limits_error'] or now-value['limits_at'] >= 600
                                           or value['limits_at'] != source.get('limits_at'))
        return result
