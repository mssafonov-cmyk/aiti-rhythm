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
from codex_account import read_limits
from cube import Cube
from local_metrics import codex_local
from runtime import HERE, load_settings, load_secrets, provider_home
from safeio import atomic_json


class Collector:
    def __init__(self, root=HERE):
        self.root, self.lock = root, threading.Lock()
        self.data, self.keys, self.pending, self.next_at = {}, {}, {}, {}
        self.pool = ThreadPoolExecutor(max_workers=5, thread_name_prefix='rhythm')
        self.cube = Cube()

    def key(self, name, settings):
        path = self.root / 'connections.sealed'
        secret_time = path.stat().st_mtime_ns if path.exists() and name in ('calendar', 'claude') else 0
        section = settings['codex'] if name == 'limits' else settings[name]
        return hashlib.sha256(json.dumps([section, secret_time], sort_keys=True).encode()).hexdigest()

    def work(self, name, settings):
        if name == 'codex':
            return codex_local(provider_home(settings['codex']['home'], 'CODEX_HOME', '.codex'))
        if name == 'claude':
            if settings['claude'].get('source') == 'external':
                from external_reader import read_external
                return read_external(load_secrets(self.root).get('claude_command'))
            return claude_local(provider_home(settings['claude']['home'], 'CLAUDE_CONFIG_DIR', '.claude'))
        if name == 'limits':
            return read_limits(settings['codex'], provider_home(settings['codex']['home'], 'CODEX_HOME', '.codex'))
        if settings['calendar'].get('kind') == 'external':
            from external_reader import read_external
            return read_external(load_secrets(self.root).get('calendar_command'))
        return collect_calendar(settings['calendar'], load_secrets(self.root))

    def step(self, now=None):
        now = time.time() if now is None else now
        settings = load_settings(self.root)
        for name in ('codex', 'claude', 'limits', 'calendar'):
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
                self.pending[name] = key, self.pool.submit(self.work, name, copy.deepcopy(settings))
        snapshot = dict(self.data, edition='personal', checked_at=now)
        snapshot['calendar_enabled'] = settings['calendar']['enabled']
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
            for _, future in list(collector.pending.values()):
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
