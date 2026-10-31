"""Optional compatibility with a user's existing read-only collector, never shipped settings."""
import importlib.util
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
    if cache.exists():
        previous = json.loads(cache.read_text(encoding='utf-8'))
        module._claude_limits = previous.get('limits', {})
        module._claude_limits_at = previous.get('limits_at')
        module._claude_last_attempt = previous.get('attempt_at', 0)
    from claude_usage import preserve_reset_metadata, with_reset_metadata_source
    original_ssh = getattr(module, 'ssh', None)
    if original_ssh:
        def reader_ssh(host, source, *args, **kwargs):
            return original_ssh(host, with_reset_metadata_source(source), *args, **kwargs)
        module.ssh = reader_ssh
    try:
        result = preserve_reset_metadata(module.claude_remote)
    finally:
        if original_ssh:
            module.ssh = original_ssh
    from safeio import atomic_json
    atomic_json(cache, {'limits': result.get('limits', {}), 'limits_at': result.get('limits_at'),
                        'attempt_at': module._claude_last_attempt})
    return result
