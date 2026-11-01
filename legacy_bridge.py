"""Optional compatibility with a user's existing read-only collector, never shipped settings."""
import ast
import importlib.util
import hashlib
import json
from pathlib import Path
import sys
import time


def read_token_history(root):
    """Use the existing configured SSH host, but only read retained token metadata.

    Replaces the remote script, so no quota/API call or remote installation occurs.
    """
    source = Path(root).resolve() / 'collect.py'
    spec = importlib.util.spec_from_file_location('rhythm_history_legacy', source)
    module = importlib.util.module_from_spec(spec)
    sys.path.insert(0, str(source.parent))
    try:
        spec.loader.exec_module(module)
        original_ssh = module.ssh
        reader = (Path(__file__).resolve().parent / 'history_readers.py').read_text(encoding='utf-8')
        remote = reader + "\nprint(json.dumps(read_history(Path.home()/'.claude', 'claude')))\n"
        module.ssh = lambda host, _source, *args, **kwargs: original_ssh(host, remote, *args, **kwargs)
        return module.claude_remote()
    finally:
        sys.path.remove(str(source.parent))


def with_daily_series(source):
    """Add journal metrics to the existing SSH read; no extra quota request."""
    tree = ast.parse(source)
    call = tree.body[-1].value
    if not (isinstance(call, ast.Call) and isinstance(call.func, ast.Name) and call.func.id == 'print'):
        return source
    result = call.args[0].args[0]
    reader = (Path(__file__).parent / 'history_readers.py').read_text(encoding='utf-8-sig')
    burn = (Path(__file__).parent / 'burn.py').read_text(encoding='utf-8-sig')
    prefix = "_rhythm_metrics={}\nexec("+repr(reader+'\n'+burn)+",_rhythm_metrics)\n"
    prefix += """
def _rhythm_daily(value):
    now=value['checked_at']; start=_rhythm_metrics['day_start_msk'](now)
    home=__import__('pathlib').Path.home()/'.claude/projects'
    if not home.is_dir():
        value['status']='journals_not_found'
        return value
    messages={}
    for path in home.rglob('*.jsonl'):
        if path.stat().st_mtime < start: continue
        item=_rhythm_metrics['file_usage'](path,'claude',now)
        for mid,row in item['messages'].items():
            if not start <= row['at'] <= now: continue
            old=messages.setdefault(mid,{'at':row['at'],'usage':{}})
            for key,count in row['usage'].items():old['usage'][key]=max(old['usage'].get(key,0),count)
    points=[]
    for row in messages.values():
        u=row['usage']; cache=u.get('cache_read_input_tokens',0)
        inp=u.get('input_tokens',0)+u.get('cache_creation_input_tokens',0)+cache
        out=u.get('output_tokens',0)
        points.append((row['at'],inp+out,inp-cache+out))
    rate=_rhythm_metrics['velocity'](points,now,900)
    rate.update(series=_rhythm_metrics['day_series'](points,now),leaders=[],alert=False)
    value.update(burn=rate)
    return value
"""
    call.args[0].args[0] = ast.Call(func=ast.Name(id='_rhythm_daily', ctx=ast.Load()), args=[result], keywords=[])
    return prefix + ast.unparse(ast.fix_missing_locations(tree))


def read(root, provider, data_root):
    # No default root, host, account, SSH key or user ref is part of this adapter.
    source = Path(root).resolve() / 'collect.py'
    if not source.is_file():
        raise FileNotFoundError('Existing collector was not found')
    sys.path.insert(0, str(source.parent))
    spec = importlib.util.spec_from_file_location('rhythm_existing_collector', source)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    if provider == 'calendar':
        result = module.meetings()
        for event in result.get('events', []):
            for field in ('planned_date', 'planned_end'):
                if event.get(field):
                    event[field] = module.stamp(event[field]).isoformat()
        result.update(enabled=True, source='Корпоративный календарь')
        return result
    cache = data_root / 'legacy-claude-cache.json'
    from claude_usage import preserve_reset_metadata, with_reset_metadata_source, quota_state, newest_quota
    sealed = data_root / 'connections.sealed'
    identity = hashlib.sha256((str(source)+'|'+str(sealed.stat().st_mtime_ns if sealed.exists() else 0)).encode()).hexdigest()
    previous = {}
    if cache.exists():
        try:
            previous = json.loads(cache.read_text(encoding='utf-8'))
            if previous.get('identity', identity) != identity:
                previous = {}
        except (OSError, ValueError, AttributeError):
            previous = {}
        module._claude_limits = previous.get('limits', {})
        module._claude_limits_at = previous.get('limits_at')
        module._claude_last_attempt = previous.get('attempt_at', 0)
    state = quota_state(previous)
    if state['limits_retry_at'] and state['limits_retry_at'] > time.time():
        # The legacy program's fixed 180s gate must honor the persisted server deadline.
        module._claude_last_attempt = state['limits_retry_at']-180
    original_ssh = getattr(module, 'ssh', None)
    if original_ssh:
        def reader_ssh(host, source, *args, **kwargs):
            return original_ssh(host, with_daily_series(with_reset_metadata_source(source, state)), *args, **kwargs)
        module.ssh = reader_ssh
    try:
        result = module.claude_remote() if original_ssh else preserve_reset_metadata(module.claude_remote, state)
    finally:
        if original_ssh:
            module.ssh = original_ssh
    from safeio import atomic_json
    result = newest_quota(result, previous)
    atomic_json(cache, dict(quota_state(result), identity=identity, attempt_at=module._claude_last_attempt))
    return result
