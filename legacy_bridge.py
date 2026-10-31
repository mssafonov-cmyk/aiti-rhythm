"""Optional compatibility with a user's existing read-only collector, never shipped settings."""
import importlib.util
import hashlib
import json
from pathlib import Path
import sys
import time


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
            return original_ssh(host, with_reset_metadata_source(source, state), *args, **kwargs)
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
