"""Passive official statusLine bridge. No credentials, model calls or network requests."""
import base64
import copy
from datetime import datetime
import hashlib
import json
import math
import os
from pathlib import Path
import re
import subprocess
import sys
import time
from antigravity_metrics import profile
from runtime import crypt
from safeio import atomic_json

BUCKETS = ('gemini-weekly', 'gemini-5h', '3p-weekly', '3p-5h')


def profile_key(home):
    return hashlib.sha256(os.path.normcase(os.path.abspath(home)).encode()).hexdigest()


def paths(root, home):
    key = profile_key(home)
    return (root / ('agy-statusline-'+key+'.sealed'), root / ('agy-statusline-'+key+'.cmd'),
            root / ('agy-quota-'+key+'.json'))


def number(value):
    return type(value) in (int, float) and math.isfinite(value)


def normalize(payload, now):
    raw = payload.get('quota') if isinstance(payload, dict) else None
    if not isinstance(raw, dict):
        return None  # Missing quota is not a new zero or a reason to erase the last response.
    out = {}
    for key in BUCKETS:
        value = raw.get(key)
        if not isinstance(value, dict):
            continue
        item = {}
        fraction = value.get('remaining_fraction')
        if number(fraction) and 0 <= fraction <= 1:
            item['remaining_fraction'] = fraction
        amount = value.get('remaining_amount')
        if number(amount) and amount >= 0:
            item['remaining_amount'] = amount
        reset = value.get('reset_time')
        if isinstance(reset, str):
            try:
                dt = datetime.fromisoformat(reset.replace('Z', '+00:00'))
                if dt.tzinfo:
                    item['reset_at'] = dt.timestamp()
            except ValueError:
                pass
        seconds = value.get('reset_in_seconds')
        if 'reset_at' not in item and number(seconds) and 0 <= seconds <= 366*86400:
            item['reset_at'] = round(now+seconds)
        if value.get('disabled') is True:
            item['disabled'] = True
        if item and ('remaining_fraction' in item or 'remaining_amount' in item):
            out[key] = item
    return out


def load_state(path):
    if not path.exists():
        return None
    return json.loads(crypt(base64.b64decode(path.read_bytes()), decrypt=True))


def save_state(path, state):
    temporary = path.with_suffix('.tmp')
    temporary.write_bytes(base64.b64encode(crypt(json.dumps(state, ensure_ascii=False).encode('utf-8'))))
    temporary.replace(path)


def capture(payload, root, home, now=None):
    now = time.time() if now is None else now
    buckets = normalize(payload, now)
    if not buckets:
        return False
    _, _, target = paths(root, home)
    record = dict(version=1, profile_key=profile_key(home), captured_at=now, buckets=buckets)
    try:
        old = json.loads(target.read_text(encoding='utf-8-sig'))
        if old.get('buckets') == buckets and 0 <= now-old.get('captured_at', 0) < 30:
            return True  # Do not write on every terminal repaint.
    except (OSError, ValueError, TypeError):
        pass
    atomic_json(target, record)
    return True


def read_quota(root, home, now=None):
    now = time.time() if now is None else now
    try:
        raw = json.loads(paths(root, home)[2].read_text(encoding='utf-8-sig'))
        at = raw['captured_at']
        if raw.get('version') != 1 or raw.get('profile_key') != profile_key(home) or not number(at) or not 0 <= now-at < 86400:
            return {}
        buckets = {}
        for key in BUCKETS:
            value = raw.get('buckets', {}).get(key, {})
            fraction, reset = value.get('remaining_fraction'), value.get('reset_at')
            if value.get('disabled') or not number(fraction) or not 0 <= fraction <= 1:
                continue
            if number(reset) and reset <= now:
                continue  # A reset is not proof that the quota has become100%.
            if not number(reset) and now-at >= 600:
                continue
            buckets[key] = dict(remaining_fraction=fraction, stale=now-at >= 600,
                                **({'reset_at':reset} if number(reset) else {}))
        return dict(quota=buckets, quota_at=at, limits_error=None) if buckets else {}
    except (OSError, ValueError, TypeError, KeyError, AttributeError):
        return {}


def statusline(root, home):
    """Store only whitelisted quota fields; forward the exact input/output of an existing line."""
    raw = sys.stdin.buffer.read(8*1024*1024+1)
    try:
        state = load_state(paths(root, home)[0])
    except Exception:
        state = None
    if state and state.get('active') and len(raw) <= 8*1024*1024:
        try:
            capture(json.loads(raw), root, home)
        except Exception:
            pass  # Monitoring must never break the native CLI.
    original = state.get('original') if state else None
    if isinstance(original, dict) and original.get('enabled', True) and isinstance(original.get('command'), str) and original['command']:
        try:
            shell = str(Path(os.environ['SystemRoot'])/'System32/cmd.exe')
            run = subprocess.run('"'+shell+'" /d /s /c "'+original['command']+'"', input=raw,
                capture_output=True, timeout=3.5, creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
            sys.stdout.buffer.write(run.stdout)
        except Exception:
            pass
    return 0


def settings_file(home):
    return Path(home)/'settings.json'


def batch_path(value):
    """ASCII launcher paths still support non-ASCII Windows user names through the environment."""
    for key in ('LOCALAPPDATA', 'USERPROFILE', 'SystemRoot'):
        prefix = os.environ.get(key)
        if prefix and os.path.normcase(value).startswith(os.path.normcase(prefix.rstrip('\\/')+os.sep)):
            suffix = value[len(prefix.rstrip('\\/')):]
            if suffix.isascii() and '%' not in suffix:
                return '%'+key+'%'+suffix
    return value.replace('%', '%%') if value.isascii() else None


def wrapper_text(command, root, home):
    encoded = lambda value:base64.b64encode(str(value).encode('utf-8')).decode('ascii')
    args = [*command, '--data-dir-b64', encoded(root), '--agy-statusline', '--agy-profile-b64', encoded(home)]
    safe = [batch_path(arg) for arg in command]+args[len(command):]
    if all(arg is not None for arg in safe):
        line = subprocess.list2cmdline(safe)
    else:
        # Rare custom non-ASCII install paths outside Windows profile folders.
        quote = lambda value:"'"+value.replace("'", "''")+"'"
        script = ("[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false);$s=[Diagnostics.ProcessStartInfo]::new();$s.FileName="+quote(command[0])+";$s.Arguments="+
                  quote(subprocess.list2cmdline(args[1:]))+";$s.UseShellExecute=$false;$s.CreateNoWindow=$true;"
                  "$s.RedirectStandardInput=$true;$s.RedirectStandardOutput=$true;$s.RedirectStandardError=$true;"
                  "$p=[Diagnostics.Process]::Start($s);$e=$p.StandardError.ReadToEndAsync();"
                  "[Console]::OpenStandardInput().CopyTo($p.StandardInput.BaseStream);$p.StandardInput.Close();"
                  "$p.StandardOutput.BaseStream.CopyTo([Console]::OpenStandardOutput());$p.WaitForExit();exit $p.ExitCode")
        line = '"%SystemRoot%\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -NoProfile -NonInteractive -EncodedCommand '+base64.b64encode(script.encode('utf-16le')).decode('ascii')
    return '@echo off\n@setlocal DisableDelayedExpansion\n'+line+'\n'


def native_command(command, root, home):
    """No nested cmd quotes: agy encodes this whole command as a Windows argument."""
    encoded = lambda value:base64.b64encode(str(value).encode('utf-8')).decode('ascii')
    quote = lambda value:"'"+value.replace("'", "''")+"'"
    args = [*command[1:], '--data-dir-b64', encoded(root), '--agy-statusline', '--agy-profile-b64', encoded(home)]
    script = ("[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false);$s=[Diagnostics.ProcessStartInfo]::new();$s.FileName="+quote(command[0])+";$s.Arguments="+
              quote(subprocess.list2cmdline(args))+";$s.UseShellExecute=$false;$s.CreateNoWindow=$true;"
              "$s.RedirectStandardInput=$true;$s.RedirectStandardOutput=$true;$s.RedirectStandardError=$true;"
              "$p=[Diagnostics.Process]::Start($s);$e=$p.StandardError.ReadToEndAsync();"
              "[Console]::OpenStandardInput().CopyTo($p.StandardInput.BaseStream);$p.StandardInput.Close();"
              "$p.StandardOutput.BaseStream.CopyTo([Console]::OpenStandardOutput());$p.WaitForExit();exit $p.ExitCode")
    return '%SystemRoot%\\System32\\WindowsPowerShell\\v1.0\\powershell.exe -NoProfile -NonInteractive -EncodedCommand '+base64.b64encode(script.encode('utf-16le')).decode('ascii')


def manage(root, home, enabled, command):
    """Change only statusLine, keep a DPAPI-protected undo record and return a rollback."""
    root, home = Path(root), Path(home)
    state_path, wrapper, quota_path = paths(root, home)
    target = settings_file(home)
    prior_files = {p:p.read_bytes() if p.exists() else None for p in (target, state_path, wrapper, quota_path)}
    config = json.loads(prior_files[target].decode('utf-8-sig')) if prior_files[target] is not None else {}
    if not isinstance(config, dict):
        raise ValueError('Invalid Antigravity settings')
    state = load_state(state_path)
    current = config.get('statusLine')
    ours = bool(state and isinstance(current, dict) and current.get('command') == state.get('managed_command'))
    def rollback():
        for path, value in prior_files.items():
            if value is None:
                path.unlink(missing_ok=True)
            else:
                path.write_bytes(value)
    try:
        if enabled:
            if not ours:
                state = dict(original_present='statusLine' in config, original=copy.deepcopy(current), original_file_existed=target.exists())
            root.mkdir(parents=True, exist_ok=True);home.mkdir(parents=True, exist_ok=True)
            managed_command = native_command(command, root, home)
            wrapper.write_text(wrapper_text(command, root, home), encoding='ascii', newline='\r\n')
            state.update(active=True, managed_command=managed_command, profile=str(home))
            save_state(state_path, state)
            old = state.get('original')
            custom = isinstance(old, dict) and old.get('command') and old.get('enabled', True)
            new = dict(old) if custom else dict(stack_with_default=True)
            new.update(type='command', command=managed_command, enabled=True)
            config['statusLine'] = new
        elif state:
            if ours:
                if state['original_present']:
                    config['statusLine'] = state.get('original')
                else:
                    config.pop('statusLine', None)
            state['active'] = False;save_state(state_path, state)
            quota_path.unlink(missing_ok=True)
        else:
            return lambda:None
        # Never overwrite a concurrent settings edit by the CLI or its user.
        if (target.read_bytes() if target.exists() else None) != prior_files[target]:
            raise RuntimeError('Antigravity settings changed concurrently')
        if enabled or ours:
            if not config and not state.get('original_file_existed', True):
                target.unlink(missing_ok=True)
            else:
                atomic_json(target, config)
    except Exception:
        # The original configuration has not been written if the concurrency check failed.
        for path in (state_path, wrapper, quota_path):
            value = prior_files[path]
            if value is None:path.unlink(missing_ok=True)
            else:path.write_bytes(value)
        raise
    return rollback


def sync_capture(previous, desired, root, command):
    undos = []
    before, after = previous['antigravity'], desired['antigravity']
    old_home, new_home = profile(before['home']), profile(after['home'])
    old_on = before['enabled'] and before.get('capture_quota', False)
    new_on = after['enabled'] and after.get('capture_quota', False)
    try:
        if old_on and (not new_on or profile_key(old_home) != profile_key(new_home)):
            undos.append(manage(root, old_home, False, command))
        if new_on:
            undos.append(manage(root, new_home, True, command))
    except Exception:
        for undo in reversed(undos):undo()
        raise
    return undos


def remove_all(root):
    for path in root.glob('agy-statusline-*.sealed'):
        try:
            state = load_state(path)
            if state and state.get('active'):
                manage(root, Path(state['profile']), False, [])
        except Exception:
            pass
    try:
        path = root/'connections.json'
        if path.exists():
            config = json.loads(path.read_text(encoding='utf-8-sig'))
            if isinstance(config.get('antigravity'), dict):
                config['antigravity']['capture_quota'] = False
                atomic_json(path, config)
    except (OSError, ValueError, TypeError, AttributeError):
        pass
