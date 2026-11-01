"""Independent provider workers: an optional offline service never stalls local metrics."""
import argparse
import copy
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import threading
import time
from calendars import collect_calendar
from claude_metrics import claude_local
from codex_account import read_limits, account_fingerprint
from cube import Cube
from local_metrics import codex_local
from runtime import HERE, load_settings, load_secrets, provider_home
from safeio import atomic_json
from antigravity_metrics import antigravity_local, profile
from usage_metrics import combined_usage, DailyUsageMemory
from claude_usage import ClaudeQuotaMemory
from burn import metric_window, day_start_msk
from usage_history import UsageHistory
from history_readers import read_history


class Collector:
    def __init__(self, root=HERE):
        self.root, self.lock = root, threading.Lock()
        self.data, self.keys, self.pending, self.next_at = {}, {}, {}, {}
        self.pool = ThreadPoolExecutor(max_workers=6, thread_name_prefix='rhythm')
        self.cube = Cube()
        self.daily_memory = DailyUsageMemory(root)
        self.claude_quota_memory = ClaudeQuotaMemory(root)
        self.history = UsageHistory(root)
        self.history_jobs, self.history_imports, self.history_next, self.history_ids = {}, {}, {}, {}

    def history_identity(self, name, settings):
        section = settings[name]
        source = section.get('source', 'local') if name == 'claude' else 'local'
        if name == 'antigravity':
            location = os.path.normcase(os.path.abspath(profile(section['home'])))
        elif source == 'external':
            location = load_secrets(self.root).get('claude_command', [])
        else:
            location = os.path.normcase(os.path.abspath(provider_home(section['home'],
                'CODEX_HOME' if name == 'codex' else 'CLAUDE_CONFIG_DIR', '.'+name)))
        return hashlib.sha256(json.dumps([name, source, location], sort_keys=True).encode()).hexdigest()

    def history_work(self, name, settings):
        if name == 'antigravity':
            return read_history(profile(settings[name]['home']), name)
        if name == 'claude' and settings[name].get('source') == 'external':
            command = load_secrets(self.root).get('claude_command', [])
            if '--legacy-root' in command and '--legacy-provider' in command:
                from legacy_bridge import read_token_history
                return read_token_history(command[command.index('--legacy-root')+1])
            # Other external readers may explicitly provide daily history in their contract.
            return dict(days=[], checked_at=time.time(), available=False)
        return read_history(provider_home(settings[name]['home'],
            'CODEX_HOME' if name == 'codex' else 'CLAUDE_CONFIG_DIR', '.'+name), name)

    def history_step(self, snapshot, settings, now):
        identities = {}
        for name in ('codex', 'claude', 'antigravity'):
            identity = self.history_identity(name, settings)
            identities[name] = identity
            if identity != self.history_ids.get(name):
                self.history_ids[name] = identity
                self.history_imports.pop(name, None)
                self.history_next[name] = 0
            job = self.history_jobs.get(name)
            if job and job[1].done():
                old_identity, future = self.history_jobs.pop(name)
                if old_identity == identity and settings[name]['enabled']:
                    try:
                        self.history_imports[name] = future.result()
                    except Exception as error:
                        self.history_imports[name] = dict(error=type(error).__name__)
                    self.history_next[name] = now + 300
            if settings[name]['enabled'] and name not in self.history_jobs and now >= self.history_next.get(name, 0):
                self.history_jobs[name] = identity, self.pool.submit(self.history_work, name, copy.deepcopy(settings))
            supplied = snapshot.get(name, {}).get('history')
            if isinstance(supplied, dict) and isinstance(supplied.get('days'), list):
                self.history_imports[name] = supplied
        return self.history.enrich(snapshot, identities, self.history_imports, now)

    def usage_identity(self, name, settings):
        if name == 'antigravity':
            home = profile(settings[name]['home'])
        elif name == 'codex':
            home = provider_home(settings[name]['home'], 'CODEX_HOME', '.codex')
        else:
            home = provider_home(settings[name]['home'], 'CLAUDE_CONFIG_DIR', '.claude')
        # Resolved environment profile plus existing settings/protected-command generation.
        return hashlib.sha256((self.key(name, settings)+'|'+os.path.normcase(os.path.abspath(home))).encode()).hexdigest()

    def run_work(self, name, settings):
        start = day_start_msk(time.time())
        result = self.work(name, settings)
        if name in ('codex', 'claude', 'antigravity'):
            result = dict(result, usage_day=start)  # Never label a cross-midnight request as the new day's total.
        return result

    def key(self, name, settings):
        path = self.root / 'connections.sealed'
        secret_time = path.stat().st_mtime_ns if path.exists() and name in ('calendar', 'claude') else 0
        section = settings['codex'] if name == 'limits' else settings[name]
        identity = [section, secret_time]
        if name in ('codex','limits'):
            identity.append(account_fingerprint(provider_home(settings['codex']['home'], 'CODEX_HOME', '.codex')))
        return hashlib.sha256(json.dumps(identity, sort_keys=True).encode()).hexdigest()

    def work(self, name, settings):
        if name == 'antigravity':
            home = profile(settings['antigravity']['home'])
            result = antigravity_local(home, window_seconds=metric_window(self.root))
            if settings['antigravity'].get('capture_quota'):
                from antigravity_quota import read_quota
                result.update(read_quota(self.root, home))
            return result
        if name == 'codex':
            return codex_local(provider_home(settings['codex']['home'], 'CODEX_HOME', '.codex'))
        if name == 'claude':
            if settings['claude'].get('source') == 'external':
                from external_reader import read_external
                return read_external(load_secrets(self.root).get('claude_command'))
            return claude_local(provider_home(settings['claude']['home'], 'CLAUDE_CONFIG_DIR', '.claude'), window_seconds=metric_window(self.root))
        if name == 'limits':
            return read_limits(settings['codex'], provider_home(settings['codex']['home'], 'CODEX_HOME', '.codex'))
        if settings['calendar'].get('kind') == 'external':
            from external_reader import read_external
            return read_external(load_secrets(self.root).get('calendar_command'))
        return collect_calendar(settings['calendar'], load_secrets(self.root))

    def step(self, now=None):
        now = time.time() if now is None else now
        settings = load_settings(self.root)
        for name in ('codex', 'claude', 'antigravity', 'limits', 'calendar'):
            section = settings['codex'] if name == 'limits' else settings[name]
            enabled = section['enabled'] and (section.get('limits', True) if name == 'limits' else True)
            key = self.key(name, settings)
            if key != self.keys.get(name):
                self.data[name] = {'enabled': enabled, 'events': []} if name == 'calendar' else {'enabled': enabled}
                self.keys[name], self.next_at[name] = key, 0
            pending = self.pending.get(name)
            if pending and pending[1].done():
                old_key, future = self.pending.pop(name)
                if old_key == key and enabled:
                    try:
                        self.data[name] = dict(future.result(), enabled=True)
                    except Exception as error:
                        self.data[name]['error'] = type(error).__name__  # No private exception messages.
                    self.next_at[name] = now + (180 if name == 'limits' else 60 if name == 'calendar' else 15)
            if not enabled:
                self.data[name] = {'enabled': False, 'events': []} if name == 'calendar' else {'enabled': False}
            elif name not in self.pending and now >= self.next_at.get(name, 0):
                self.pending[name] = key, self.pool.submit(self.run_work, name, copy.deepcopy(settings))
        snapshot = dict(self.data, edition='personal', checked_at=now)
        snapshot['calendar_enabled'] = settings['calendar']['enabled']
        snapshot['view'] = copy.deepcopy(settings['view'])
        snapshot['claude'] = self.claude_quota_memory.enrich(snapshot.get('claude', {}), self.usage_identity('claude', settings), now)
        snapshot = self.daily_memory.enrich(snapshot, {name:self.usage_identity(name, settings)
            for name in ('codex', 'claude', 'antigravity')}, now)
        snapshot['usage'] = combined_usage(snapshot, now)
        snapshot['usage']['history'] = self.history_step(snapshot, settings, now)
        cube_key = self.key('cube', settings)
        cube_pending = self.pending.get('cube')
        if cube_pending and cube_pending[1].done():
            old_key, future = self.pending.pop('cube')
            if old_key == cube_key:
                try:
                    self.data['cube'] = future.result()
                except Exception as error:
                    self.data['cube'] = {'enabled': settings['cube']['enabled'], 'error': type(error).__name__}
                self.next_at['cube'] = now + 30
        if not settings['cube']['enabled']:
            self.data['cube'] = {'enabled': False}
        elif 'cube' not in self.pending and now >= self.next_at.get('cube', 0):
            self.pending['cube'] = cube_key, self.pool.submit(self.cube.update, copy.deepcopy(settings['cube']), copy.deepcopy(snapshot))
        snapshot['cube'] = self.data.get('cube', {'enabled': settings['cube']['enabled']})
        return snapshot

    def close(self):
        self.pool.shutdown(wait=True, cancel_futures=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--once', action='store_true')
    args = parser.parse_args()
    import msvcrt
    HERE.mkdir(parents=True, exist_ok=True)
    lock = (HERE / 'collector.lock').open('a+b')
    lock.write(b'0'); lock.flush(); lock.seek(0)
    try:
        msvcrt.locking(lock.fileno(), msvcrt.LK_NBLCK, 1)
    except OSError:
        return
    collector = Collector()
    try:
        if args.once:
            collector.step()
            for _, future in list(collector.pending.values()) + list(collector.history_jobs.values()):
                try:
                    future.result(timeout=25)
                except Exception:
                    pass
            atomic_json(HERE / 'snapshot.json', collector.step())
        else:
            while True:
                try:
                    atomic_json(HERE / 'snapshot.json', collector.step())
                except Exception as error:
                    atomic_json(HERE / 'collector-health.json', {'error': type(error).__name__, 'at': time.time()})
                time.sleep(2)
    finally:
        collector.close()


if __name__ == '__main__':
    main()
