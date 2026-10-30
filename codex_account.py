"""Read quota through the installed Codex app-server; it owns all authentication."""
import json
import os
from pathlib import Path
import queue
import shutil
import subprocess
import threading
import time


def executable(config):
    if config.get('executable'):
        return config['executable']
    found = shutil.which('codex.exe')
    if found:
        return found
    candidates = list((Path(os.environ.get('LOCALAPPDATA', '')) / 'OpenAI/Codex/bin').glob('*/codex.exe'))
    npm = Path(os.environ.get('APPDATA', '')) / 'npm/node_modules/@openai'
    if npm.is_dir():
        candidates.extend(npm.glob('**/codex.exe'))
    if candidates:
        return str(max(candidates, key=lambda path: path.stat().st_mtime))
    raise FileNotFoundError('Codex executable not found')


def normalize(result):
    meters = result.get('rateLimitsByLimitId')
    meter = meters.get('codex', {}) if isinstance(meters, dict) else result.get('rateLimits', {})
    output = {'checked_at': time.time()}
    for window in (meter.get('primary'), meter.get('secondary')):
        if not isinstance(window, dict) or 'usedPercent' not in window:
            continue
        minutes = window.get('windowDurationMins', 0)
        key = 'weekly' if minutes >= 7 * 24 * 60 else 'session' if minutes > 0 else None
        if key:
            output[key + '_pct'] = min(1.0, max(0.0, float(window['usedPercent']) / 100))
            output[key + '_reset_at'] = window.get('resetsAt')
    if 'weekly_pct' not in output and 'session_pct' not in output:
        output['error'] = 'quota_not_available'
    return output


def read_limits(config, home, timeout=15):
    env = dict(os.environ, CODEX_HOME=str(home))
    process = subprocess.Popen([executable(config), 'app-server'], stdin=subprocess.PIPE,
                               stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
                               encoding='utf-8', env=env, creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
    inbox = queue.Queue()
    def consume():
        for line in process.stdout:
            try:
                inbox.put(json.loads(line))
            except ValueError:
                pass
        inbox.put(None)
    threading.Thread(target=consume, daemon=True).start()
    deadline = time.monotonic() + timeout
    def send(value):
        process.stdin.write(json.dumps(value) + '\n')
        process.stdin.flush()
    def receive(identifier):
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError('Codex account read timeout')
            value = inbox.get(timeout=remaining)
            if value is None:
                raise RuntimeError('Codex account read stopped')
            if value.get('id') == identifier:
                if value.get('error'):
                    raise RuntimeError('Codex account read unavailable')
                return value.get('result', {})
    try:
        send({'id': 1, 'method': 'initialize', 'params': {'clientInfo': {'name': 'aiti_rhythm', 'version': '1.0.0'}, 'capabilities': {}}})
        receive(1)
        send({'method': 'initialized', 'params': {}})
        send({'id': 2, 'method': 'account/rateLimits/read', 'params': {}})
        return normalize(receive(2))
    finally:
        try:
            process.stdin.close()
        except OSError:
            pass
        if process.poll() is None:
            process.terminate()
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=3)
