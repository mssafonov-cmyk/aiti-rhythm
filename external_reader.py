"""Advanced, explicit per-user JSON reader; no shell and no built-in server/account."""
import json
import subprocess


def read_external(command):
    if not isinstance(command, list) or not command or any(not isinstance(value, str) for value in command):
        raise ValueError('Configure an explicit executable and argument list')
    process = subprocess.run(command, stdin=subprocess.DEVNULL, capture_output=True, timeout=45,
                             creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
    if process.returncode or len(process.stdout) > 5 * 1024 * 1024:
        raise RuntimeError('External reader unavailable')
    value = json.loads(process.stdout.decode('utf-8-sig'))
    if not isinstance(value, dict):
        raise ValueError('External reader must return a JSON object')
    return value
