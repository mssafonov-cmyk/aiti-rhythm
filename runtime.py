"""User-owned settings. Calendar secrets are protected by Windows DPAPI."""
import base64
import copy
import ctypes
from ctypes import wintypes
import json
import os
from pathlib import Path
from safeio import atomic_json

from app_paths import DATA as HERE
DEFAULTS = {
    'codex': {'enabled': True, 'home': '', 'executable': '', 'limits': True},
    'claude': {'enabled': True, 'home': '', 'source': 'local'},
    'calendar': {'enabled': False, 'kind': 'ical', 'name': '', 'timezone': 'Europe/Moscow',
                 'mapping': {'id': 'id', 'subject': 'subject', 'start': 'start', 'end': 'end', 'url': 'url'}},
    'cube': {'enabled': False, 'host': '', 'rotation': 0, 'show_titles': False},
}


class Blob(ctypes.Structure):
    _fields_ = [('size', wintypes.DWORD), ('data', ctypes.POINTER(ctypes.c_ubyte))]


def crypt(data, decrypt=False):
    if os.name != 'nt':
        raise RuntimeError('Windows DPAPI is required')
    buffer = ctypes.create_string_buffer(data)
    source = Blob(len(data), ctypes.cast(buffer, ctypes.POINTER(ctypes.c_ubyte)))
    target = Blob()
    api = ctypes.WinDLL('crypt32', use_last_error=True)
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel.LocalFree.argtypes = [ctypes.c_void_p]
    kernel.LocalFree.restype = ctypes.c_void_p
    if decrypt:
        ok = api.CryptUnprotectData(ctypes.byref(source), None, None, None, None, 1, ctypes.byref(target))
    else:
        ok = api.CryptProtectData(ctypes.byref(source), 'AITI Rhythm', None, None, None, 1, ctypes.byref(target))
    if not ok:
        raise RuntimeError('Cannot access user-protected connection settings')
    try:
        return ctypes.string_at(target.data, target.size)
    finally:
        kernel.LocalFree(target.data)


def load_settings(root=HERE):
    result = copy.deepcopy(DEFAULTS)
    path = root / 'connections.json'
    if path.exists():
        raw = json.loads(path.read_text(encoding='utf-8-sig'))
        for key in result:
            if isinstance(raw.get(key), dict):
                result[key].update(raw[key])
    return result


def load_secrets(root=HERE):
    path = root / 'connections.sealed'
    if not path.exists():
        return {}
    return json.loads(crypt(base64.b64decode(path.read_bytes()), decrypt=True))


def save_connection(values, root=HERE):
    settings = load_settings(root)
    secrets = load_secrets(root)
    for key in settings:
        if isinstance(values.get(key), dict):
            settings[key].update(values[key])
    for key, value in values.get('secrets', {}).items():
        if value:  # Blank fields preserve previously saved secrets.
            secrets[key] = value
    if not settings['calendar']['enabled']:
        secrets = {key: value for key, value in secrets.items() if not key.startswith('calendar_')}
    protected = base64.b64encode(crypt(json.dumps(secrets).encode('utf-8')))
    temporary = root / 'connections.sealed.tmp'
    temporary.write_bytes(protected)
    temporary.replace(root / 'connections.sealed')
    atomic_json(root / 'connections.json', settings)
    return settings


def provider_home(value, environment, fallback):
    return Path(os.path.expandvars(value or os.environ.get(environment) or str(Path.home() / fallback))).expanduser()
