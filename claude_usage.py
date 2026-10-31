"""Quota metadata only: no credential handling, extra requests or inferred reset dates."""
from datetime import datetime
import ast
import json
import math
from pathlib import Path
import urllib.request


def with_reset_metadata_source(source):
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
        return support + '\n' + ast.unparse(wrapped) + '\nprint(json.dumps(preserve_reset_metadata(_rhythm_existing_read), ensure_ascii=False))\n'
    except (SyntaxError, IndexError, AttributeError, TypeError):
        return source


def normalize_usage(block):
    windows = {}
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


def preserve_reset_metadata(read):
    """Observe the existing legacy reader's response inside its single-use subprocess.

    The former reader discarded resets_at. Preserve that field without reading its
    token, changing its request or making another network call. Restore the hook
    even on failure. Only matching percentages from the same response are merged.
    """
    original = urllib.request.urlopen
    observed = {}

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
        response = original(request, *args, **kwargs)
        url = request.full_url if isinstance(request, urllib.request.Request) else str(request)
        return Response(response) if url == 'https://api.anthropic.com/api/oauth/usage' else response

    urllib.request.urlopen = open_existing
    try:
        result = read()
    finally:
        urllib.request.urlopen = original
    for name, metadata in observed.items():
        current = result.get('limits', {}).get(name, {})
        if current.get('used_percentage') == metadata['used_percentage'] and metadata.get('resets_at'):
            current['resets_at'] = metadata['resets_at']
    return result
